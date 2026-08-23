{- EVE Online warp-to-0 auto-pilot version 2025-11-19

   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot. It jumps by pressing the Selected Item panel's own Jump button where the panel is already showing the route's next stargate, and falls back to the route marker's context menu everywhere else -- including every dock.

   Before starting the bot, set up the game client as follows:

   + Set the UI language to English.
   + Set the in-game autopilot route.
   + Make sure the autopilot info panel is expanded, so that the route is visible.
   + Make sure the overview is visible, so that the stargate the route names can be identified. Without it the bot still travels, on the context menu alone.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `activate-module-always` : Text found in tooltips of ship modules that should always be active. For example: "cloaking device".

   To learn more about the autopilot, see <https://to.botlab.org/guide/app/eve-online-autopilot-bot>

-}
{-
   catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import BotLab.NotificationsShim
import Color
import Common.Basics exposing (stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow exposing (Location2d, MouseButton(..))
import Common.PromptParser as PromptParser
import Dict
import EveOnline.BotFramework
    exposing
        ( BotEvent(..)
        , ModuleButtonTooltipMemory
        , PixelValueRGB
        , ReadingFromGameClient
        , ShipModulesMemory
        , infoPanelRouteFirstMarkerFromReadingFromGameClient
        , menuCascadeCompleted
        , mouseClickOnUIElement
        , shipUIIndicatesShipIsWarpingOrJumping
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        , useMenuEntryWithTextEqual
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , UpdateMemoryContext
        , branchDependingOnDockedOrInSpace
        , clickModuleButtonButWaitIfClickedInPreviousStep
        , decideActionForCurrentStep
        , discardContextMenuIfTooDistantFromTargetElement
        , useContextMenuCascadeOnListSurroundingsButton
        , useContextMenuCascadeWithCustomConfig
        , waitForProgressInGame
        )
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion)
import Json.Decode


defaultBotSettings : BotSettings
defaultBotSettings =
    { activateModulesAlways = [] }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    PromptParser.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "activate-module-always"
           , { alternativeNames = []
             , description = "Text found in tooltips of ship modules that should always be active. For example: 'cloaking device'."
             , valueParser =
                PromptParser.valueTypeString
                    (\moduleName settings ->
                        { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways }
                    )
             }
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { activateModulesAlways : List String
    }


type alias BotMemory =
    { lastSolarSystemName : Maybe String
    , jumpsCompleted : Int
    , shipModules : ShipModulesMemory
    , didTravelEnRoute : Bool
    , lastReadingsWithoutRoute : Int

    -- Ported from saxrat's #330 fix for the identical failure shape in the
    -- identical cascade. Right after a route is (re)set, the route panel's
    -- marker strip needs a moment to finish computing -- during that window
    -- its icon can be absent, partial, or still shifting, and right-clicking
    -- during it means clicking a position with no clickable icon there yet.
    -- `routeFirstMarkerUnchangedTicks` requires the marker's own region to
    -- have read the same for at least one full tick before it is clicked.
    , routeFirstMarkerRegion : Maybe EveOnline.ParseUserInterface.DisplayRegion
    , routeFirstMarkerUnchangedTicks : Int

    -- How many consecutive readings the route panel has named the *same*
    -- next system without a jump landing (`jumpsCompleted` moving), and
    -- which system that was. Past `jumpCascadeStuckReadings`,
    -- `jumpToNextSystemViaSurroundingsButton` takes over instead of the
    -- marker cascade continuing to retry the same small, shifting icon.
    --
    -- Counted in readings rather than in menu (re)opens the way saxrat's own
    -- #330 fix counts it, because this app's vendored `UpdateMemoryContext`
    -- (unlike saxrat's and the mission runner's) carries no
    -- `previousStepsEffects` to attribute a right-click to -- extending the
    -- host-interface plumbing to add that is a larger, separate change this
    -- fix does not make. A reading-count bound is coarser (it cannot tell
    -- "waiting for a menu to render" from "stuck"), so it is set well above
    -- an ordinary multi-open cascade rather than at the edge of one -- see
    -- `jumpCascadeStuckReadings`.
    , jumpCascadeSystem : Maybe String
    , jumpCascadeStuckReadings : Int
    }


type alias State =
    BotLab.NotificationsShim.StateWithNotifications
        (EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory)


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


initBotMemory : BotMemory
initBotMemory =
    { lastSolarSystemName = Nothing
    , jumpsCompleted = 0
    , shipModules = EveOnline.BotFramework.initShipModulesMemory
    , didTravelEnRoute = False
    , lastReadingsWithoutRoute = 0
    , routeFirstMarkerRegion = Nothing
    , routeFirstMarkerUnchangedTicks = 0
    , jumpCascadeSystem = Nothing
    , jumpCascadeStuckReadings = 0
    }


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        describeSessionPerformance =
            "jumps completed: " ++ (context.memory.jumpsCompleted |> String.fromInt)

        describeCurrentReading =
            [ [ "current solar system: "
                    ++ (currentSolarSystemNameFromReading context.readingFromGameClient |> Maybe.withDefault "Unknown")
              ]
            , if List.isEmpty context.eventContext.botSettings.activateModulesAlways then
                []

              else
                [ "Ship module buttons: " ++ describeShipModuleButtons context ]
            ]
                |> List.concat
                |> String.join "\n"
    in
    [ describeSessionPerformance
    , describeCurrentReading
    ]
        |> String.join "\n"


autopilotBotDecisionRoot : BotDecisionContext -> DecisionPathNode
autopilotBotDecisionRoot context =
    (case infoPanelRouteFirstMarkerFromReadingFromGameClient context.readingFromGameClient of
        Nothing ->
            {-
               Adapt to observation from session-recording-2024-06-02T13-10-35, as discussed on Discord — 03/06/2024 18:44:
               > Looks like in event 1101 the list of route markers was empty in the memory reading. Might be a sporadic fail to read that part of the UI. Probably the solution is not rely only on the last reading but consider previous readings as well.
            -}
            if context.memory.didTravelEnRoute && 3 < context.memory.lastReadingsWithoutRoute then
                describeBranch
                    "I see no route in the info panel. We finished traveling the route."
                    (Common.DecisionPath.endDecisionPath
                        EveOnline.BotFrameworkSeparatingMemory.FinishSession
                    )

            else
                describeBranch
                    "I see no route in the info panel. I will start when a route is set."
                    (decideStepWhenInSpaceWaiting context)

        Just infoPanelRouteFirstMarker ->
            branchDependingOnDockedOrInSpace
                { ifDocked =
                    describeBranch
                        "To continue, undock manually."
                        waitForProgressInGame
                , ifSeeShipUI =
                    decideStepWhenInSpace
                        context
                        { infoPanelRouteFirstMarker = infoPanelRouteFirstMarker }
                }
                context
    )
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase 2000


decideStepWhenInSpace :
    BotDecisionContext
    -> { infoPanelRouteFirstMarker : EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker }
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
decideStepWhenInSpace context { infoPanelRouteFirstMarker } shipUI =
    if shipUIIndicatesShipIsWarpingOrJumping shipUI then
        describeBranch
            "I see the ship is warping or jumping. I wait until that maneuver ends."
            (decideStepWhenInSpaceWaiting context)

    else if context.memory.routeFirstMarkerUnchangedTicks < 1 then
        describeBranch
            "Route panel's first marker just appeared or moved since the last reading -- wait for the route to finish (re)computing before clicking it."
            waitForProgressInGame

    else if jumpCascadeStuckReadings <= context.memory.jumpCascadeStuckReadings then
        jumpToNextSystemViaSurroundingsButton context

    else
        jumpThroughRouteStargate context
            (routeMarkerCascade context infoPanelRouteFirstMarker)


{-| How many consecutive readings the route panel may go on naming the *same*
next system, with no jump landing, before giving up on the marker cascade and
falling back to `jumpToNextSystemViaSurroundingsButton` instead.

Ported from saxrat's #330, whose own `jumpCascadeStuckReopens` counts menu
(re)opens rather than readings and is set to 3 -- "at the edge of what the
marker cascade's own comment calls ordinary" for that unit. This app's
`UpdateMemoryContext` carries no `previousStepsEffects` to count re-opens
from, so this counts readings instead, which cannot distinguish "waiting for
a menu to render" from "stuck" the way saxrat's can -- and is set well above
an ordinary cascade's length rather than at its edge for that reason. This
bot's own measured baseline (see `jumpThroughRouteStargate`'s doc comment) is
about 19 readings per completed jump on the *old*, un-widened 70px tolerance;
30 gives the newly-widened 200px tolerance room to still be slower than the
other apps' own copies of this cascade without tripping the fallback on an
ordinary leg.
-}
jumpCascadeStuckReadings : Int
jumpCascadeStuckReadings =
    30


{-| Jump to the route's next system by right-clicking the persistent
"surroundings" button rather than the route panel's own marker. Ported from
saxrat's #330 -- see that bot's own `jumpToNextSystemViaSurroundingsButton`
for the full argument and what is and is not verified about it live. This bot
has no drones to recall first, unlike saxrat's version.
-}
jumpToNextSystemViaSurroundingsButton : BotDecisionContext -> DecisionPathNode
jumpToNextSystemViaSurroundingsButton context =
    case context.readingFromGameClient |> nextSystemOnRouteFromReading of
        Nothing ->
            describeBranch
                "Was going to fall back to the surroundings-button cascade, but the route panel no longer names a next system -- nothing to jump toward this way either."
                waitForProgressInGame

        Just systemName ->
            describeBranch
                ("The route-marker cascade has spent "
                    ++ String.fromInt context.memory.jumpCascadeStuckReadings
                    ++ " reading(s) trying to jump toward '"
                    ++ systemName
                    ++ "' with no jump landing, past "
                    ++ String.fromInt jumpCascadeStuckReadings
                    ++ " -- right-click the surroundings button instead and cascade to this gate by name."
                )
                (useContextMenuCascadeOnListSurroundingsButton
                    (useMenuEntryWithTextEqual "Stargates"
                        (useMenuEntryWithTextContaining systemName
                            (useMenuEntryWithTextEqual "Jump" menuCascadeCompleted)
                        )
                    )
                    context
                )


{-| Right-click the route panel's first marker and take whichever of "dock" or
"jump" the client offers.

Unchanged, and still the fall-back under `jumpThroughRouteStargate` -- which is
what travels every leg the panel cannot identify a gate for, and every leg that
ends in a dock rather than a jump.

**"dock" stays first in the list, and that ordering is load-bearing.** This bot
has no docking branch of its own: the final waypoint is a station, the client
offers `Dock` on the route marker there, and taking it is how the session ends.
Observed live on 2026-08-16 -- run 6's log ends in Amarr with this cascade's
last click, then `I see no ship UI, assume we are docked.`, then
`FinishSession: jumps completed: 4`. #99 records that a
cascade cannot finish a dock on the mission runner, but that bot has a run-in
guard and a `dockAtDestinationStation` panel branch, and this one has neither, so
the evidence there does not carry across. Only the **jump** leg moved to the
panel.

-}
routeMarkerCascade :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
    -> DecisionPathNode
routeMarkerCascade context infoPanelRouteFirstMarker =
    -- Widened from the shared 70px default to 200, matching the mission
    -- runner's and saxrat's own copies of this same cascade -- both of them
    -- widened it for the identical reason this bot's own doc comment above
    -- already gives ("'Jump Through Stargate' took 3-4 menu opens before
    -- being recognized... the route icon is small and sits in a strip that
    -- can shift as the route updates"), which this bot had evidently
    -- written down and never actually applied to the cascade it describes.
    useContextMenuCascadeWithCustomConfig
        (discardContextMenuIfTooDistantFromTargetElement { toleratedDistance = 200 })
        { targetUIElement = infoPanelRouteFirstMarker.uiNode, targetUIElementName = "route element icon" }
        (useMenuEntryWithTextContainingFirstOf
            [ "dock"

            -- https://forum.botlab.org/t/i-want-to-add-korean-support-on-eve-online-bot-what-should-i-do/4370/14
            , "도킹"
            , "jump"

            -- https://forum.botlab.org/t/i-want-to-add-korean-support-on-eve-online-bot-what-should-i-do/4370
            , "점프 - 스타게이트 사용"
            ]
            menuCascadeCompleted
        )
        context


{-| Whether to press the Selected Item panel's Jump, and which gate it would be.

#170's rule, ported unchanged from saxrat (#169), where it is byte for byte the
mission runner's. The two have not diverged since: `routeStargateJump`,
`describeRouteStargateJump`, `stargateNameLeadsToSystem`,
`nextSystemOnRouteFromReading` and `overviewEntryIsAStargate` are identical in
both files today, and the only difference between the apps is that saxrat's
`selectedItemButtonNamed` and `selectedItemIsOverviewEntry` take a
`ReadingFromGameClient` where the mission runner's take a `BotDecisionContext`.
This bot takes saxrat's shape, for the reason saxrat gives: a reading is the
smaller thing to ask, and nothing here needs a decision to answer it.

**A jump to the wrong gate is a wrong system, not a wasted tick**, so every
clause below is a way this could act on the wrong object and the answer to each
is to fall back to `routeMarkerCascade` -- which right-clicks the route's own
marker and cannot pick the wrong gate at all. The mission runner's
`dockAtDestinationStation` shipped assuming one route marker meant the nearest
station was the destination, #98 was the regression, and nothing had checked
identity.

**The identity, and what makes it possible.**
`InfoPanelRouteRouteElementMarker` carries a `uiNode` and no name -- which is why
the marker cannot say which gate it is. What answers instead is the route panel's
_own label_:

    <a href="showinfo:5//30005001" alt="Next System in Route">Arnon</a>

and the overview's stargate rows, which carry the system a gate leads to in the
Name column and the word in the Type column:

    Name "Tar" Type "Stargate (CONCORD System)"

So "the gate to the next system in the route" is a name match between two
readings the client itself renders, and needs nothing from the marker.

**Only the row's own name is matched, never its type.** A type reads
`Stargate (Amarr Border)` and Amarr is a real system, so a rule that looked at
both would match a gate leading somewhere else entirely on the strength of the
region it borders.

**Exactly one match, or fall back.** Two rows naming one system is not something
this reading can choose between, and a system's name is unique, so more than one
means the match is not the one this rule thinks it is.

**The panel is already showing that gate.** Where it is showing something else
this falls back rather than selecting the row first: selecting spends the very
reading this exists to save, and the cascade is what the fall-back does anyway.

**The panel offers the button.** Whether `selectedItemJump` is drawn on a gate
out of jump range is unread; if it is, pressing it is still the right gate and
the client's own warp-and-jump, and if it is not this falls back to the cascade,
which is what flies the ship there. Either way the gate is the route's.

-}
type RouteStargateJump
    = PressTheJumpButton String
    | NoNextSystemOnRoute
    | NoStargateNamedForTheNextSystem String
    | SeveralStargatesNamedForTheNextSystem String
    | ThePanelIsShowingSomethingElse String
    | ThePanelOffersNoJump String


routeStargateJump :
    { nextSystemOnRoute : Maybe String
    , stargatesOnOverview : List { name : String, panelIsShowingIt : Bool }
    , panelOffersJump : Bool
    }
    -> RouteStargateJump
routeStargateJump input =
    case input.nextSystemOnRoute of
        Nothing ->
            NoNextSystemOnRoute

        Just nextSystem ->
            case input.stargatesOnOverview |> List.filter (.name >> stargateNameLeadsToSystem nextSystem) of
                [] ->
                    NoStargateNamedForTheNextSystem nextSystem

                [ gate ] ->
                    if not gate.panelIsShowingIt then
                        ThePanelIsShowingSomethingElse nextSystem

                    else if not input.panelOffersJump then
                        ThePanelOffersNoJump nextSystem

                    else
                        PressTheJumpButton gate.name

                _ ->
                    SeveralStargatesNamedForTheNextSystem nextSystem


{-| What the decision log says about `routeStargateJump`'s answer.

Derived from the verdict rather than stored beside it: two places that can
disagree about why a branch did something eventually do.

Every fall-back names the route marker, because that is what runs next and an
operator reading a stretch of these needs to see the cascade is still travelling
the route rather than that the jump has stopped happening.

-}
describeRouteStargateJump : RouteStargateJump -> String
describeRouteStargateJump jump =
    case jump of
        PressTheJumpButton gateName ->
            "Jump through '" ++ gateName ++ "' from the selected-item panel, which is already showing it."

        NoNextSystemOnRoute ->
            "The route panel does not name a next system, so nothing here says which stargate is the route's -- right-click the route marker instead."

        NoStargateNamedForTheNextSystem nextSystem ->
            "No stargate on the overview is named for '" ++ nextSystem ++ "' -- right-click the route marker instead."

        SeveralStargatesNamedForTheNextSystem nextSystem ->
            "More than one stargate on the overview is named for '" ++ nextSystem ++ "', so which one the route means is not readable here -- right-click the route marker instead."

        ThePanelIsShowingSomethingElse nextSystem ->
            "The selected-item panel is not showing the stargate to '" ++ nextSystem ++ "' -- selecting it would spend the reading this saves, so right-click the route marker instead."

        ThePanelOffersNoJump nextSystem ->
            "The selected-item panel is showing the stargate to '" ++ nextSystem ++ "' and offers no 'selectedItemJump' -- right-click the route marker instead, which is what closes the distance."


{-| Whether an overview row's name says this stargate leads to `systemName`.

`containsWords`' whole-word rule, with punctuation read as a separator first.
The rows this client draws name the system alone -- `Tar` -- and an overview
preset that renders `Stargate (Tar)` in the Name column has to match too;
without the normalisation the parentheses make that a different word and the
match is lost, and with a plain substring rule `Ami` would match `Amir`.

Both sides get the same treatment, so a system whose own name carries punctuation
-- `1DQ1-A` -- is compared as the same sequence of words on each side.

-}
stargateNameLeadsToSystem : String -> String -> Bool
stargateNameLeadsToSystem systemName gateName =
    containsWords (punctuationAsSeparators systemName) (punctuationAsSeparators gateName)


punctuationAsSeparators : String -> String
punctuationAsSeparators =
    String.map
        (\character ->
            if Char.isAlphaNum character then
                character

            else
                ' '
        )


{-| The system the route panel says this ship jumps to next, if it says.

`NextWaypointPanel`'s label. This bot has only ever asked the route panel whether
it holds a marker, never what it says. Both quote styles, exactly as
`parseCurrentSolarSystemFromUINodeText` takes them: this client writes
`alt="Next System in Route"` and the 2019 recording in `explore/` writes
`alt='Next System in Route'`.

-}
nextSystemOnRouteFromReading : ReadingFromGameClient -> Maybe String
nextSystemOnRouteFromReading readingFromGameClient =
    readingFromGameClient.infoPanelContainer
        |> Maybe.andThen .infoPanelRoute
        |> Maybe.map (.uiNode >> .uiNode >> EveOnline.ParseUserInterface.getAllContainedDisplayTexts)
        |> Maybe.withDefault []
        |> List.filterMap parseNextSystemInRouteFromLabelText
        |> List.head


parseNextSystemInRouteFromLabelText : String -> Maybe String
parseNextSystemInRouteFromLabelText labelText =
    [ "alt='Next System in Route'", "alt=\"Next System in Route\"" ]
        |> List.filterMap
            (\marker ->
                labelText |> EveOnline.ParseUserInterface.getSubstringBetweenXmlTagsAfterMarker marker
            )
        |> List.map String.trim
        |> List.filter (String.isEmpty >> not)
        |> List.head


{-| Whether an overview row's own words say it is a stargate.

Name _and_ type, because the two columns carry the word differently depending on
the overview preset -- this client puts `Stargate (CONCORD System)` in Type and
the destination system alone in Name. Unlike the identity match above, which is
only ever handed the Name.

-}
overviewEntryIsAStargate : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsAStargate entry =
    [ entry.objectName, entry.objectType ]
        |> List.filterMap identity
        |> List.any (containsWords "stargate")


{-| Take the route's next stargate by pressing the Selected Item panel's own
Jump button, where the panel is already showing that gate.

**What this replaces on the readings it can, and how much.** `routeMarkerCascade`
below right-clicks an 8x8 icon in a strip that shifts as the route updates, and
does it on this bot through the _shared_ 70px tolerance -- the mission runner
widened its own copy to 200 because "'Jump Through Stargate' took 3-4 menu opens
before being recognized", and this bot never got that widening either. Counted
over the six recorded runs in `~/eve-bot-logs/autopilot_run*.log` in **readings**
rather than decision lines, the cascade's three rungs hold **401 of 649
readings** -- 62% of every reading in every run, and about **19 readings per
completed jump** across the 21 jumps those runs completed. The mission runner
answers 3 and 2 readings a leg on the same measurement and saxrat 12 and 13, so
this is the most expensive copy of this cascade in the repo, on the bot whose
whole job is travelling.

Against that saving sits a wrong system, which is why `routeStargateJump` refuses
on every reading it cannot identify the gate from the client's own two renderings
of the system's name.

**Two branches rather than three, and the missing one is the point:** there is no
select-first step. Selecting spends the reading this exists to save, and the
cascade below travels the route regardless.

-}
jumpThroughRouteStargate : BotDecisionContext -> DecisionPathNode -> DecisionPathNode
jumpThroughRouteStargate context ifThePanelCannotDoIt =
    let
        jumpButton : Maybe EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
        jumpButton =
            routeStargateJumpButton context.readingFromGameClient

        verdict : RouteStargateJump
        verdict =
            routeStargateJumpFromReading context.readingFromGameClient
    in
    case ( verdict, jumpButton ) of
        ( PressTheJumpButton _, Just buttonToPress ) ->
            describeBranch (describeRouteStargateJump verdict) (clickUiElement buttonToPress)

        _ ->
            describeBranch (describeRouteStargateJump verdict) ifThePanelCannotDoIt


{-| The three readings `routeStargateJump` decides from, taken off one reading.

**A top-level function rather than a `let` binding inside
`jumpThroughRouteStargate`, and that is the one place this port departs from
saxrat's and the mission runner's shape.** In both of those the record is built
inline, which means the only way to check that the identity match is handed the
Name column and not the Type is to read the source and assert on the text. A
case that does that passes on a comment quoting the right thing, and this repo
has watched a mutation survive exactly that way -- so here the wiring is a
function of a `ReadingFromGameClient`, and the cases that matter most execute it
against a parsed reading instead of restating it.

Nothing else moves: `routeStargateJump` is byte for byte the rule both other
apps run.

-}
routeStargateJumpFromReading : ReadingFromGameClient -> RouteStargateJump
routeStargateJumpFromReading readingFromGameClient =
    routeStargateJump
        { nextSystemOnRoute = nextSystemOnRouteFromReading readingFromGameClient
        , stargatesOnOverview =
            readingFromGameClient.overviewWindows
                |> List.concatMap .entries
                |> List.filter overviewEntryIsDisplayed
                |> List.filter overviewEntryIsAStargate
                |> List.map
                    (\gate ->
                        { name = gate.objectName |> Maybe.withDefault ""
                        , panelIsShowingIt =
                            selectedItemIsOverviewEntry readingFromGameClient gate
                        }
                    )
        , panelOffersJump = routeStargateJumpButton readingFromGameClient /= Nothing
        }


{-| The Selected Item panel's Jump button, named once.

Both the verdict and the press ask for it here rather than each spelling the
name out, so the button the rule is told about cannot drift from the button that
gets clicked -- which is the two-places-can-disagree failure
`describeRouteStargateJump` is derived from the verdict to avoid, in its other
form.

-}
routeStargateJumpButton : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
routeStargateJumpButton readingFromGameClient =
    selectedItemButtonNamed readingFromGameClient "selectedItemJump"


{-| Whether `pattern` occurs in `text` as whole words rather than as a substring.

Substring matching has cost this codebase real bugs -- a live rogue drone called
a "Wrecker" contains "wreck" -- so the identity test above compares on word
boundaries. Whitespace is normalised and both sides padded, so a match can
neither begin nor end mid-word and a multi-word pattern still matches as a
sequence.

-}
containsWords : String -> String -> Bool
containsWords pattern text =
    let
        padded value =
            " " ++ (value |> String.toLower |> String.words |> String.join " ") ++ " "
    in
    String.contains (padded pattern) (padded text)


{-| A button in the Selected Item panel, by its own `_name`.

`ParseUserInterface` exposes only `orbitButton` off this window -- in this bot's
parser as in saxrat's -- so every other button is reached by name, and no parser
change is needed to press one. This is the first panel button this bot has ever
pressed.

-}
selectedItemButtonNamed :
    ReadingFromGameClient
    -> String
    -> Maybe EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
selectedItemButtonNamed readingFromGameClient name =
    readingFromGameClient.selectedItemWindow
        |> Maybe.map (.uiNode >> EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion)
        |> Maybe.withDefault []
        |> List.filter
            (\node ->
                (node.uiNode |> EveOnline.ParseUserInterface.getNameFromDictEntries) == Just name
            )
        |> List.head


{-| Whether the Selected Item panel is showing this overview entry.

Asked before pressing any of the panel's buttons, because they act on whatever is
selected rather than on whatever the decision is about.

-}
selectedItemIsOverviewEntry :
    ReadingFromGameClient
    -> EveOnline.ParseUserInterface.OverviewWindowEntry
    -> Bool
selectedItemIsOverviewEntry readingFromGameClient entry =
    case ( readingFromGameClient.selectedItemWindow, entry.objectName ) of
        ( Just window, Just name ) ->
            EveOnline.ParseUserInterface.getAllContainedDisplayTexts window.uiNode.uiNode
                |> List.any (containsWords name)

        _ ->
            False


{-| Whether an overview row is actually drawn.

A row scrolled out of the overview keeps a plausible region pointing at a row
that now belongs to something else, so an undisplayed row can name a system this
bot would then believe a gate for. `_display` is what distinguishes them; the
region does not.

-}
overviewEntryIsDisplayed : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsDisplayed entry =
    nodeIsDisplayed entry.uiNode.uiNode


{-| The widget's own `_display` flag, defaulting to shown when absent (most
nodes never set it).
-}
nodeIsDisplayed : EveOnline.MemoryReading.UITreeNode -> Bool
nodeIsDisplayed uiNode =
    uiNode.dictEntriesOfInterest
        |> Dict.get "_display"
        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.bool >> Result.toMaybe)
        |> Maybe.withDefault True


clickUiElement : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion -> DecisionPathNode
clickUiElement uiElement =
    decideActionForCurrentStep
        (mouseClickOnUIElement MouseButtonLeft uiElement |> Result.withDefault [])


decideStepWhenInSpaceWaiting : BotDecisionContext -> DecisionPathNode
decideStepWhenInSpaceWaiting context =
    case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> moduleButtonLooksActive context >> Maybe.withDefault False >> not) |> List.head of
        Just ( inactiveModuleMatchingText, inactiveModule ) ->
            describeBranch ("I see inactive module '" ++ inactiveModuleMatchingText ++ "' to activate always. Activate it.")
                (describeBranch "Click on the module."
                    (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)
                )

        Nothing ->
            readShipUIModuleButtonTooltips context |> Maybe.withDefault waitForProgressInGame


updateMemoryForNewReadingFromGame : UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context memoryBefore =
    let
        ( lastSolarSystemName, newJumpsCompleted ) =
            case currentSolarSystemNameFromReading context.readingFromGameClient of
                Nothing ->
                    ( memoryBefore.lastSolarSystemName, 0 )

                Just currentSolarSystemName ->
                    ( Just currentSolarSystemName
                    , if
                        (memoryBefore.lastSolarSystemName /= Nothing)
                            && (memoryBefore.lastSolarSystemName /= Just currentSolarSystemName)
                      then
                        1

                      else
                        0
                    )

        doesTravelEnRoute : Bool
        doesTravelEnRoute =
            case infoPanelRouteFirstMarkerFromReadingFromGameClient context.readingFromGameClient of
                Just _ ->
                    True

                Nothing ->
                    {- Observation from the game client: Route icons disappear while jumping.
                       Therefore, do not only rely on the info panel route markers.
                    -}
                    case context.readingFromGameClient.shipUI of
                        Nothing ->
                            False

                        Just shipUI ->
                            shipUIIndicatesShipIsWarpingOrJumping shipUI

        lastReadingsWithoutRoute =
            if doesTravelEnRoute then
                0

            else
                memoryBefore.lastReadingsWithoutRoute + 1

        currentRouteFirstMarkerRegion =
            infoPanelRouteFirstMarkerFromReadingFromGameClient context.readingFromGameClient
                |> Maybe.map (.uiNode >> .totalDisplayRegion)

        currentJumpCascadeSystem =
            context.readingFromGameClient |> nextSystemOnRouteFromReading
    in
    { jumpsCompleted = memoryBefore.jumpsCompleted + newJumpsCompleted
    , lastSolarSystemName = lastSolarSystemName
    , shipModules =
        EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory
            context.readingFromGameClient
            memoryBefore.shipModules
    , didTravelEnRoute = memoryBefore.didTravelEnRoute || doesTravelEnRoute
    , lastReadingsWithoutRoute = lastReadingsWithoutRoute
    , routeFirstMarkerRegion = currentRouteFirstMarkerRegion
    , routeFirstMarkerUnchangedTicks =
        if currentRouteFirstMarkerRegion == Nothing then
            0

        else if currentRouteFirstMarkerRegion == memoryBefore.routeFirstMarkerRegion then
            memoryBefore.routeFirstMarkerUnchangedTicks + 1

        else
            0
    , jumpCascadeSystem = currentJumpCascadeSystem
    , jumpCascadeStuckReadings =
        -- A jump landing is read off `newJumpsCompleted` rather than off the
        -- system name changing, because the *destination* station's own
        -- "system" can repeat the previous entry's name on a route that
        -- jumps back through the same system twice, which would otherwise
        -- read as no progress on a leg that genuinely completed.
        if currentJumpCascadeSystem == Nothing then
            0

        else if (currentJumpCascadeSystem == memoryBefore.jumpCascadeSystem) && (newJumpsCompleted == 0) then
            memoryBefore.jumpCascadeStuckReadings + 1

        else
            0
    }


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    case context.readingFromGameClient.shipUI of
        Nothing ->
            []

        Just shipUI ->
            shipUI.moduleButtons
                |> List.filterMap
                    (\moduleButton ->
                        case
                            EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton
                                context.memory.shipModules
                                moduleButton
                        of
                            Nothing ->
                                Nothing

                            Just moduleButtonTooltip ->
                                case tooltipLooksLikeModuleToActivateAlways context moduleButtonTooltip of
                                    Nothing ->
                                        Nothing

                                    Just moduleName ->
                                        Just ( moduleName, moduleButton )
                    )


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> ModuleButtonTooltipMemory -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .allContainedDisplayTextsWithRegion
        >> List.filterMap
            (\( tooltipText, _ ) ->
                context.eventContext.botSettings.activateModulesAlways
                    |> List.filterMap
                        (\moduleToActivateAlways ->
                            if tooltipText |> stringContainsIgnoringCase moduleToActivateAlways then
                                Just tooltipText

                            else
                                Nothing
                        )
                    |> List.head
            )
        >> List.head


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , decideNextStep = autopilotBotDecisionRoot
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            }
    }
        |> BotLab.NotificationsShim.addNotifications notificationsFunction


notificationsFunction : { statusText : String } -> List BotLab.NotificationsShim.Notification
notificationsFunction botResponse =
    [ ( "undock manually"
      , BotLab.NotificationsShim.consoleBeepNotification
            [ { frequency = 0
              , durationInMs = 200
              }
            , { frequency = 400
              , durationInMs = 300
              }
            , { frequency = 500
              , durationInMs = 300
              }
            ]
      )
    ]
        |> List.filterMap
            (\( keyword, notification ) ->
                if botResponse.statusText |> String.toLower |> String.contains (String.toLower keyword) then
                    Just notification

                else
                    Nothing
            )


currentSolarSystemNameFromReading : ReadingFromGameClient -> Maybe String
currentSolarSystemNameFromReading readingFromGameClient =
    readingFromGameClient.infoPanelContainer
        |> Maybe.andThen .infoPanelLocationInfo
        |> Maybe.andThen .currentSolarSystemName


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.BotFrameworkSeparatingMemory.readShipUIModuleButtonTooltipWhereNotYetInMemory


locationToMeasureGlowFromModuleButton : EveOnline.ParseUserInterface.ShipUIModuleButton -> Location2d
locationToMeasureGlowFromModuleButton moduleButton =
    let
        moduleButtonCenter =
            moduleButton.uiNode.totalDisplayRegion |> centerFromDisplayRegion
    in
    { x = moduleButtonCenter.x - 20, y = moduleButtonCenter.y }


describeShipModuleButtons : BotDecisionContext -> String
describeShipModuleButtons context =
    case context.readingFromGameClient.shipUI of
        Nothing ->
            "I see no ship UI"

        Just shipUI ->
            let
                moduleButtonsRowsList =
                    [ shipUI.moduleButtonsRows.top
                    , shipUI.moduleButtonsRows.middle
                    , shipUI.moduleButtonsRows.bottom
                    ]

                describeGreenessOfPixelValue { activeIndicationSampledPixels, activeIndicationPixelGreenessPercent } =
                    Maybe.withDefault "None" (Maybe.map String.fromInt activeIndicationPixelGreenessPercent)
                        ++ " % ("
                        ++ String.fromInt (List.length activeIndicationSampledPixels)
                        ++ " sampled pixels)"

                describeAllModuleButtonsGreeness =
                    moduleButtonsRowsList
                        |> List.indexedMap
                            (\rowIndex row ->
                                row
                                    |> List.indexedMap
                                        (\columnIndex moduleButton ->
                                            let
                                                maybeGreennessText =
                                                    moduleButtonImageProcessing context moduleButton
                                                        |> describeGreenessOfPixelValue
                                            in
                                            "["
                                                ++ String.fromInt rowIndex
                                                ++ ","
                                                ++ String.fromInt columnIndex
                                                ++ "]: "
                                                ++ maybeGreennessText
                                        )
                                    |> String.join ", "
                            )
                        |> String.join "\n"
            in
            "I see "
                ++ (moduleButtonsRowsList |> List.map List.length |> List.sum |> String.fromInt)
                ++ " module buttons in total, with greenness as follows:\n"
                ++ describeAllModuleButtonsGreeness


moduleButtonLooksActive : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUIModuleButton -> Maybe Bool
moduleButtonLooksActive context moduleButton =
    if moduleButton.isActive == Just True then
        moduleButton.isActive

    else
        {-
           Adapt to discovery in March 2021 by Victor Santamaría Caballero and Samuel Pagé:
           Some module buttons don't have the ramp:
           https://forum.botlab.org/t/cloaking-device-in-warp-to-0-bot/3917/3
        -}
        case (moduleButtonImageProcessing context moduleButton).activeIndicationPixelGreenessPercent of
            Nothing ->
                moduleButton.isActive

            Just greenness ->
                Just (4 < greenness)


moduleButtonImageProcessing :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUIModuleButton
    -> { activeIndicationSampledPixels : List PixelValueRGB, activeIndicationPixelGreenessPercent : Maybe Int }
moduleButtonImageProcessing context moduleButton =
    let
        measurementLocation : Location2d
        measurementLocation =
            locationToMeasureGlowFromModuleButton moduleButton

        sampledLocations : List ( Int, Int )
        sampledLocations =
            [ ( -1, 0 )
            , ( -1, 1 )
            , ( 0, 0 )
            , ( 0, 1 )
            , ( 1, 0 )
            , ( 1, 1 )
            ]
                |> List.map
                    (\( offsetX, offsetY ) ->
                        ( measurementLocation.x // 2 + offsetX
                        , measurementLocation.y // 2 + offsetY
                        )
                    )

        activeIndicationSampledPixels : List PixelValueRGB
        activeIndicationSampledPixels =
            sampledLocations
                |> List.filterMap context.screenshot.pixels_2x2

        activeIndicationSampledPixelsGreenessPercents : List Int
        activeIndicationSampledPixelsGreenessPercents =
            List.map greenessPercentFromPixelValue activeIndicationSampledPixels

        activeIndicationPixelGreenessPercent : Maybe Int
        activeIndicationPixelGreenessPercent =
            if 0 < List.length activeIndicationSampledPixelsGreenessPercents then
                activeIndicationSampledPixelsGreenessPercents
                    |> List.sort
                    |> List.drop (List.length activeIndicationSampledPixelsGreenessPercents // 2)
                    |> List.head

            else
                Nothing
    in
    { activeIndicationSampledPixels = activeIndicationSampledPixels
    , activeIndicationPixelGreenessPercent = activeIndicationPixelGreenessPercent
    }


greenessPercentFromPixelValue : PixelValueRGB -> Int
greenessPercentFromPixelValue pixelValue =
    -- https://www.w3.org/TR/css-color-3/#hsl-color
    let
        hsla : { hue : Float, saturation : Float, lightness : Float, alpha : Float }
        hsla =
            Color.toHsla (Color.rgb255 pixelValue.red pixelValue.green pixelValue.blue)

        hueGreenessFactor : Float
        hueGreenessFactor =
            max 0 (1 - (abs (hsla.hue - 0.333) * 4))
    in
    round ((hueGreenessFactor * hsla.saturation) * 100)

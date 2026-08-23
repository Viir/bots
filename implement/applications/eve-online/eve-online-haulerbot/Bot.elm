{- EVE Online hauler bot version 2026-08-23

   Moves cargo between two named stations. As long as the source station's item
   hangar has anything in it worth taking, the bot flies there, loads the ship's
   cargo hold (and, if the ship has one, a specialised ore/mining hold -- see
   below), flies to the destination, and unloads. Then it goes back for more.
   With the source hangar empty and nothing left aboard, it idles at the source
   and keeps watching rather than ending the session -- the next reading shows
   the hangar's live contents on its own, so nothing needs to poll on a timer.

   This is a recombination of two other bots here rather than new territory:
   the travel and docking logic is `eve-online-warp-to-0-autopilot`'s, and the
   hangar-to-hold drag-and-drop is `eve-online-mining-bot`'s, plus
   `eve-online-mission-runner`'s own trick for finding the ship's cargo hold
   (which has no fixed label -- it carries the ship's own name) and its
   `reload_drones.py`-derived sequence for opening a hold reliably from the
   ship's own card rather than Alt+C, which silently refuses drops into a
   specialised hold while looking identical in the UI tree.

   Before starting the bot, set up the game client as follows:

   + Set the UI language to English.
   + Open one inventory window.
   + If your ship has a specialised ore or mining hold (a Miasmos-family hull,
     an Expedition Frigate, a mining barge, etc.), nothing extra to configure --
     the bot looks for one and uses it automatically if present.
   + **Switch every panel the bot will drag from or into to List View**
     (station item hangar, ship cargo hold, ship ore/mining hold) rather than
     the default icon grid. Confirmed live: dragging a single item out of an
     icon grid's first slot works, but a second item one column over does
     not -- the drag lands to the left of its icon, repeatedly, and nothing
     tried here corrects it. List view has no such problem (see
     `itemIconGrabPoint`'s doc comment for the detail), and is what every
     live-confirmed run of this bot has used.

   ## Configuration Settings

   + `source-station` (required) : Full name of the station to load cargo at,
     exactly as the client renders it -- parentheses and hyphens included, the
     same convention `home-station` uses elsewhere in this repo.
   + `destination-station` (required) : Full name of the station to unload
     cargo at.
   + `include-item-pattern` : Text an item's name must contain to be loaded at
     all. Repeatable; with none given, everything in the source hangar is
     eligible.
   + `ore-hold-item-pattern` : Text that routes an eligible item to the ship's
     ore/mining hold instead of the general cargo hold, when the ship has one.
     Repeatable, and defaults to a list of ore type names (see
     `defaultOreHoldItemPatterns`) -- "Compressed Veldspar" matches on
     "Veldspar" the same as raw ore does. Not exhaustive; extend it if your ore
     is not in the default list.
   + `activate-module-always` : Text found in tooltips of ship modules that
     should always be active. For example: "shield hardener".
   + `route-by-esi` : Ask the host to set the route through ESI (`yes`,
     default) rather than driving the in-game search bar (`no`). See
     `eve-online-mission-runner`'s own use of this same setting.

-}
{-
   catalog-tags:eve-online,hauling,logistics,industry
   authors-forum-usernames:
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.BotFramework
    exposing
        ( ModuleButtonTooltipMemory
        , ReadingFromGameClient
        , ShipModulesMemory
        , infoPanelRouteFirstMarkerFromReadingFromGameClient
        , menuCascadeCompleted
        , mouseClickOnUIElement
        , mouseDoubleClickOnUIElement
        , shipUIIndicatesShipIsWarpingOrJumping
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , UpdateMemoryContext
        , askForHelpToGetUnstuck
        , branchDependingOnDockedOrInSpace
        , clickModuleButtonButWaitIfClickedInPreviousStep
        , decideActionForCurrentStep
        , ensureInfoPanelLocationInfoIsExpanded
        , readShipUIModuleButtonTooltipWhereNotYetInMemory
        , useContextMenuCascade
        , waitForProgressInGame
        )
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface
    exposing
        ( UITreeNodeWithDisplayRegion
        , centerFromDisplayRegion
        )
import Json.Decode


{-| The default set of ore type names routed to a specialised hold rather than
the general cargo hold. Not exhaustive -- new ore types are added to the game
periodically, and this list is from this bot's own time. "Compressed X"
matches on the same substring a raw "X" does, so compressed variants need no
separate entry.
-}
defaultOreHoldItemPatterns : List String
defaultOreHoldItemPatterns =
    [ "Veldspar"
    , "Scordite"
    , "Pyroxeres"
    , "Plagioclase"
    , "Omber"
    , "Kernite"
    , "Jaspet"
    , "Hemorphite"
    , "Hedbergite"
    , "Gneiss"
    , "Ochre"
    , "Spodumain"
    , "Crokite"
    , "Bistot"
    , "Arkonor"
    , "Mercoxit"
    , "Bezdnacine"
    , "Rakovene"
    , "Talassonite"
    , "Ytirium"
    , "Griemeer"
    , "Mordunium"
    , "Ueganite"
    , "Kylixium"
    ]


defaultBotSettings : BotSettings
defaultBotSettings =
    { sourceStationName = ""
    , destinationStationName = ""
    , includeItemPatterns = []
    , oreHoldItemPatterns = defaultOreHoldItemPatterns
    , activateModulesAlways = []
    , routeByEsi = AppSettings.Yes
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "source-station"
           , AppSettings.valueTypeString (\name settings -> { settings | sourceStationName = name })
           )
         , ( "destination-station"
           , AppSettings.valueTypeString (\name settings -> { settings | destinationStationName = name })
           )
         , ( "include-item-pattern"
           , AppSettings.valueTypeString
                (\pattern settings ->
                    { settings | includeItemPatterns = pattern :: settings.includeItemPatterns }
                )
           )
         , ( "ore-hold-item-pattern"
           , AppSettings.valueTypeString
                (\pattern settings ->
                    -- The first one seen replaces the shipped default rather
                    -- than joining it -- #198's own argument, applied here:
                    -- an operator narrowing this list should not find ore
                    -- types they did not name still routing to the hold.
                    { settings
                        | oreHoldItemPatterns =
                            if settings.oreHoldItemPatterns == defaultOreHoldItemPatterns then
                                [ pattern ]

                            else
                                pattern :: settings.oreHoldItemPatterns
                    }
                )
           )
         , ( "activate-module-always"
           , AppSettings.valueTypeString
                (\moduleName settings -> { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways })
           )
         , ( "route-by-esi"
           , AppSettings.valueTypeYesOrNo (\routeByEsi settings -> { settings | routeByEsi = routeByEsi })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { sourceStationName : String
    , destinationStationName : String
    , includeItemPatterns : List String
    , oreHoldItemPatterns : List String
    , activateModulesAlways : List String
    , routeByEsi : AppSettings.YesOrNo
    }


{-| Which of the two holds this is about. `CargoHold` always exists; `OreHold`
is Maybe everywhere it is looked up, since most hulls do not have one.
-}
type Hold
    = CargoHold
    | OreHold


{-| Per-hold progress, the same shape the drone-bay restock elsewhere in this
repo uses for exactly the same reason: a look at the gauge and a drag do not
happen on the same reading, so the two counts say which this reading is for,
and `willTakeNoMore` is the latch that stops the bot re-trying a hold that has
already refused a drop or read full.
-}
type alias HoldProgress =
    { dragsDispatched : Int
    , looksWithRoom : Int
    , willTakeNoMore : Bool
    , readingsNotSelected : Int

    -- Whether this hold's own item list read anything other than empty the
    -- last time it was genuinely confirmed to be the selected container --
    -- i.e. captured in the same reading `looksWithRoom` increments, so it is
    -- exactly as fresh as that counter's own "one look precedes each drag"
    -- discipline already guarantees. Read instead of re-selecting the hold
    -- on demand at the departure decision, which this bot's first live run
    -- showed thrashing: selecting the hold to check it deselects the item
    -- hangar, which the loading step then reselects to re-check eligibility,
    -- which deselects the hold again, forever. `Nothing` means "never looked
    -- at yet this session" -- distinguished from `Just False` so a hold that
    -- has genuinely been confirmed empty is not confused with one nobody has
    -- checked.
    , carriesAnythingAsOfLastLook : Maybe Bool
    }


initHoldProgress : HoldProgress
initHoldProgress =
    { dragsDispatched = 0
    , looksWithRoom = 0
    , willTakeNoMore = False
    , readingsNotSelected = 0
    , carriesAnythingAsOfLastLook = Nothing
    }


{-| Which station the ship is currently working towards. Set once, on the
undock transition, from the cargo state observed while still docked -- not
re-derived every reading in space, since that would cost a UI selection this
decision does not otherwise need. See the header comment and the plan this
was built from for the argument.
-}
type Errand
    = HeadingToSource
    | HeadingToDestination


type alias BotMemory =
    { shipModules : ShipModulesMemory
    , currentErrand : Maybe Errand
    , cargoOpenedFromShipCard : Bool
    , cargoHold : HoldProgress
    , oreHold : HoldProgress
    , tripsCompleted : Int
    , lastDockedStationNameFromInfoPanel : Maybe String
    , searchResultsWithoutStationInfoTicks : Int
    , dockedLastReading : Bool
    , readingsSinceSearchSubmitted : Int
    }


initBotMemory : BotMemory
initBotMemory =
    { shipModules = EveOnline.BotFramework.initShipModulesMemory
    , currentErrand = Nothing
    , cargoOpenedFromShipCard = False
    , cargoHold = initHoldProgress
    , oreHold = initHoldProgress
    , tripsCompleted = 0
    , lastDockedStationNameFromInfoPanel = Nothing
    , searchResultsWithoutStationInfoTicks = 0
    , dockedLastReading = False
    , readingsSinceSearchSubmitted = searchSubmitCooldownReadings
    }


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


type alias State =
    EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory



-- How many readings a hold is looked at (for its capacity gauge) before a
-- pending drag is judged to have landed or not. Mirrors the drone-bay
-- restock's own `droneRestockLooksBeforeGivingUp`, at the same value.


holdLooksBeforeGivingUp : Int
holdLooksBeforeGivingUp =
    3


{-| How many consecutive readings a hold may go on failing to become the
selected container before the bot gives up on it for the rest of the session,
rather than clicking the same tree entry forever. Counted in readings rather
than in clicks or drags, since either of those can be dispatched at this
hold's tree entry without the selection ever landing -- see
`readingsNotSelected` on `HoldProgress`.
-}
holdSelectionFailuresBeforeGivingUp : Int
holdSelectionFailuresBeforeGivingUp =
    20


{-| A floor on how many readings must pass between one search submission
(click the search bar, clear it, type the query, press Return) and the next,
while no results window has appeared yet. Confirmed live to be needed: without
one, a results window that took more than a reading or two to render was read
as "search hasn't produced anything, try again", and the client answered with
its own anti-spam refusal -- `You can't do this quite so fast. Please wait 52
seconds before trying again.` A single submission should be enough; this bounds
the cost of retrying when it is not, rather than trying to guess exactly how
long the client needs.
-}
searchSubmitCooldownReadings : Int
searchSubmitCooldownReadings =
    20


{-| How many readings the search bar's results window is watched without ever
raising the `Station: Information` window before giving up on that attempt and
trying the search again from the top. A simplified bound compared to
`eve-online-mission-runner`'s own version of this, which additionally
diagnoses *why* nothing matched -- left out here since the search bar is only
the fallback path, exercised while `route-by-esi = no` or while no ESI
credentials are configured.
-}
searchResultsWithoutStationInfoTicksBeforeGivingUp : Int
searchResultsWithoutStationInfoTicksBeforeGivingUp =
    40


haulerBotDecisionRoot : BotDecisionContext -> DecisionPathNode
haulerBotDecisionRoot context =
    haulerBotDecisionRootBeforeApplyingSettings context
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase 2000


haulerBotDecisionRootBeforeApplyingSettings : BotDecisionContext -> DecisionPathNode
haulerBotDecisionRootBeforeApplyingSettings context =
    if String.isEmpty (String.trim context.eventContext.botSettings.sourceStationName) then
        describeBranch "Please configure the 'source-station' setting -- I do not know where to load cargo." askForHelpToGetUnstuck

    else if String.isEmpty (String.trim context.eventContext.botSettings.destinationStationName) then
        describeBranch "Please configure the 'destination-station' setting -- I do not know where to unload cargo." askForHelpToGetUnstuck

    else
        generalSetupInUserInterface context.previousStepsEffects context.readingFromGameClient
            |> Maybe.withDefault
                (branchDependingOnDockedOrInSpace
                    { ifDocked = decideActionWhileDocked context
                    , ifSeeShipUI = decideActionInSpace context
                    }
                    context
                )


generalSetupInUserInterface :
    List (List EffectOnWindow.EffectOnWindowStruct)
    -> ReadingFromGameClient
    -> Maybe DecisionPathNode
generalSetupInUserInterface previousStepsEffects readingFromGameClient =
    [ closeMessageBox, ensureInfoPanelLocationInfoIsExpanded previousStepsEffects ]
        |> List.filterMap (\step -> step readingFromGameClient)
        |> List.head


closeMessageBox : ReadingFromGameClient -> Maybe DecisionPathNode
closeMessageBox readingFromGameClient =
    readingFromGameClient.messageBoxes
        |> List.head
        |> Maybe.map
            (\messageBox ->
                describeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose =
                            .mainText
                                >> Maybe.map (String.trim >> String.toLower >> (\text -> [ "close", "ok" ] |> List.member text))
                                >> Maybe.withDefault False
                     in
                     case messageBox.buttons |> List.filter buttonCanBeUsedToClose |> List.head of
                        Nothing ->
                            describeBranch "I see no way to close this message box." askForHelpToGetUnstuck

                        Just buttonToUse ->
                            describeBranch
                                ("Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'.")
                                (clickUiElement buttonToUse.uiNode)
                    )
            )



-- DOCKED


decideActionWhileDocked : BotDecisionContext -> DecisionPathNode
decideActionWhileDocked context =
    case dockedStationNameFromInfoPanel context.readingFromGameClient of
        Nothing ->
            describeBranch "I do not see which station I am docked in yet." waitForProgressInGame

        Just stationName ->
            if stationNameMatches context.eventContext.botSettings.sourceStationName stationName then
                describeBranch ("I am docked at the source station '" ++ stationName ++ "'.")
                    (decideActionAtSource context)

            else if stationNameMatches context.eventContext.botSettings.destinationStationName stationName then
                describeBranch ("I am docked at the destination station '" ++ stationName ++ "'.")
                    (decideActionAtDestination context)

            else
                describeBranch
                    ("I am docked at '"
                        ++ stationName
                        ++ "', which is neither the source nor the destination station. Check what is aboard and head out."
                    )
                    (decideActionAtUnknownStation context)


stationNameMatches : String -> String -> Bool
stationNameMatches settingName renderedName =
    stringContainsIgnoringCase (String.trim settingName) renderedName


dockedStationNameFromInfoPanel : ReadingFromGameClient -> Maybe String
dockedStationNameFromInfoPanel readingFromGameClient =
    readingFromGameClient.infoPanelContainer
        |> Maybe.andThen .infoPanelLocationInfo
        |> Maybe.andThen .expandedContent
        |> Maybe.andThen .currentStationName


{-| A dock at neither named station -- normally only the very first reading of
a session, wherever the ship happened to be left. Decide the errand from
what is aboard rather than guessing: cargo already holding something means
there is somewhere to deliver it, and an empty hold means there is nothing to
do here but go and get some.
-}
decideActionAtUnknownStation : BotDecisionContext -> DecisionPathNode
decideActionAtUnknownStation context =
    case openCargoFromShipCard context of
        Just openStep ->
            openStep

        Nothing ->
            case holdTreeEntry CargoHold context.readingFromGameClient of
                Nothing ->
                    describeBranch "I do not see the ship's cargo hold here." askForHelpToGetUnstuck

                Just cargoEntry ->
                    if not (holdIsSelectedContainer CargoHold context.readingFromGameClient) then
                        if previousStepClickedMouse context then
                            describeBranch "I just clicked -- wait for the reading to catch up." waitForProgressInGame

                        else
                            describeBranch "Select the cargo hold to see what is aboard." (clickUiElement (cargoEntry.selectRegion |> Maybe.withDefault cargoEntry.uiNode))

                    else if cargoCarriesAnything context.readingFromGameClient then
                        describeBranch "Cargo already holds something. Head for the destination station." (undockWithErrand context HeadingToDestination)

                    else
                        describeBranch "Cargo is empty. Head for the source station." (undockWithErrand context HeadingToSource)


{-| Loading at the source: fill both holds that exist, ore-matching items into
the ore hold where the ship has one, everything else into the general cargo
hold. Stops and departs once neither hold can take anything more from the
hangar; if nothing was loaded at all, waits instead of making a pointless
round trip.
-}
decideActionAtSource : BotDecisionContext -> DecisionPathNode
decideActionAtSource context =
    case openCargoFromShipCard context of
        Just openStep ->
            openStep

        Nothing ->
            let
                oreHoldExists =
                    holdTreeEntry OreHold context.readingFromGameClient /= Nothing

                loadStepFor hold =
                    loadOneItemIntoHold context hold
            in
            case loadStepFor OreHold |> orIfNothing (\() -> loadStepFor CargoHold) of
                Just step ->
                    step

                Nothing ->
                    -- Neither hold has anything more it will take from the
                    -- hangar right now (full, refused, or nothing eligible
                    -- left in the hangar for it). Whether either hold
                    -- carries something is read from what the last genuine
                    -- look at it found (`carriesAnythingAsOfLastLook`)
                    -- rather than by re-selecting it here: an earlier
                    -- version tried to confirm this by selecting the hold
                    -- on demand, and a live run showed that thrashing --
                    -- selecting the hold deselects the item hangar, which
                    -- `loadOneItemIntoHold` then reselects to recheck
                    -- eligibility, which deselects the hold again, forever.
                    -- The remembered answer is exactly as fresh as
                    -- `loadOneItemIntoHold`'s own "one look precedes each
                    -- drag" discipline already keeps it, since both are
                    -- written from the same `isSelectedNow` branch in the
                    -- memory update.
                    if holdOrLikelyCarriesAnything CargoHold context.memory then
                        describeBranch "Nothing more to load. Head for the destination station."
                            (undockWithErrand context HeadingToDestination)

                    else if oreHoldExists && holdOrLikelyCarriesAnything OreHold context.memory then
                        describeBranch "Nothing more to load. Head for the destination station."
                            (undockWithErrand context HeadingToDestination)

                    else
                        describeBranch
                            "The source station's item hangar has nothing (more) for me to load, and I am carrying nothing yet. Wait here -- I will see new items as soon as they show up."
                            waitForProgressInGame


{-| Whether `hold` is known, or reasonably assumed, to carry anything --
`carriesAnythingAsOfLastLook`'s answer where there is one, and `True`
(assume the worst, i.e. assume there is cargo rather than risk leaving it
behind) where the hold has never once been looked at this session. That
second case matters only for a session that loads nothing at all before its
first "is there anything to load" check -- an empty source hangar from the
very start -- where assuming `False` would undock immediately with nothing
aboard, and assuming `True` costs one wasted trip that a subsequent look
corrects.
-}
holdOrLikelyCarriesAnything : Hold -> BotMemory -> Bool
holdOrLikelyCarriesAnything hold memory =
    (holdProgressFor hold memory).carriesAnythingAsOfLastLook |> Maybe.withDefault True


orIfNothing : (() -> Maybe a) -> Maybe a -> Maybe a
orIfNothing fallback maybe =
    case maybe of
        Just value ->
            Just value

        Nothing ->
            fallback ()


cargoCarriesAnything : ReadingFromGameClient -> Bool
cargoCarriesAnything readingFromGameClient =
    holdCarriesAnything CargoHold readingFromGameClient


{-| Unloading at the destination: drain both holds that exist into the item
hangar, then undock and head back for another load.
-}
decideActionAtDestination : BotDecisionContext -> DecisionPathNode
decideActionAtDestination context =
    case openCargoFromShipCard context of
        Just openStep ->
            openStep

        Nothing ->
            case unloadOneItemFromHold context OreHold |> orIfNothing (\() -> unloadOneItemFromHold context CargoHold) of
                Just step ->
                    step

                Nothing ->
                    describeBranch
                        "Both holds are empty. Head back to the source station for another load."
                        (undockWithErrand context HeadingToSource)


{-| Right-click the ship's own card and choose "Open Cargohold". Reused
verbatim from `eve-online-mission-runner`'s drone-bay restock, which
established live that Alt+C silently refuses a drop into a specialised hold
while looking identical in the UI tree -- this bot never uses Alt+C for that
reason. Latches `cargoOpenedFromShipCard` in memory once the cargo hold shows
up as *some* inventory window's selected container, the only evidence a
reading carries that the click landed.
-}
openCargoFromShipCard : BotDecisionContext -> Maybe DecisionPathNode
openCargoFromShipCard context =
    if context.memory.cargoOpenedFromShipCard then
        Nothing

    else
        case shipItemCardsOnScreen context.readingFromGameClient |> List.head of
            Just shipCard ->
                Just
                    (describeBranch
                        ("Open the cargo hold from the ship's own card (" ++ (shipCard.mainText |> Maybe.withDefault "unnamed ship") ++ "), the only place a drop into a specialised hold is reliably accepted.")
                        (useContextMenuCascade
                            ( "ship card", shipCard.uiNode )
                            (useMenuEntryWithTextContaining "Open Cargohold" menuCascadeCompleted)
                            context
                        )
                    )

            Nothing ->
                case shipHangarTabToOpen context.readingFromGameClient of
                    Just ( tabName, tabNode ) ->
                        if previousStepClickedMouse context then
                            Just (describeBranch "I just clicked a hangar tab -- wait for the reading to catch up." waitForProgressInGame)

                        else
                            Just
                                (describeBranch
                                    ("No ship card in this reading -- open the '" ++ tabName ++ "' tab, which is where the cards are.")
                                    (clickUiElement tabNode)
                                )

                    Nothing ->
                        Just (describeBranch "I see no ship card and no Hangars/Ships tab to reveal one." askForHelpToGetUnstuck)


{-| The tab to click to bring the ship cards into view. Ported from
`eve-online-mission-runner`'s `shipHangarTabToOpen`.
-}
shipHangarTabToOpen : ReadingFromGameClient -> Maybe ( String, UITreeNodeWithDisplayRegion )
shipHangarTabToOpen readingFromGameClient =
    (if shipItemCardsOnScreen readingFromGameClient == [] && readingFromGameClient.shipItemCards /= [] then
        [ "Hangars" ]

     else
        [ "Ships", "Hangars" ]
    )
        |> List.filterMap
            (\tabName ->
                readingFromGameClient
                    |> widestNodeLabelledExactly { label = tabName, pythonObjectTypeName = Just "EveLabelMedium" }
                    |> Maybe.map (\node -> ( tabName, node ))
            )
        |> List.head


shipItemCardsOnScreen : ReadingFromGameClient -> List EveOnline.ParseUserInterface.ShipItemCard
shipItemCardsOnScreen readingFromGameClient =
    case readingFromGameClient.stationWindow |> Maybe.andThen .agentsTab of
        Just agentsTab ->
            if agentsTab.isSelected then
                []

            else
                readingFromGameClient.shipItemCards

        Nothing ->
            readingFromGameClient.shipItemCards


{-| Load one eligible item from the item hangar into `hold`, or say why none
was loaded. `Nothing` means this hold cannot usefully be asked again this
reading (full, refused, or nothing in the hangar matches it) -- the caller
tries the other hold, or concludes there is nothing left to load at all.
-}
loadOneItemIntoHold : BotDecisionContext -> Hold -> Maybe DecisionPathNode
loadOneItemIntoHold context hold =
    if hold == OreHold && holdTreeEntry OreHold context.readingFromGameClient == Nothing then
        Nothing

    else
        case dropRefusalStep context hold of
            Just step ->
                Just step

            Nothing ->
                if (holdProgressFor hold context.memory).willTakeNoMore then
                    Nothing

                else
                    case holdTreeEntry hold context.readingFromGameClient of
                        Nothing ->
                            Nothing

                        Just targetEntry ->
                            if holdSelectionFailuresBeforeGivingUp <= (holdProgressFor hold context.memory).readingsNotSelected then
                                -- The select click has been asked for
                                -- repeatedly and this hold has never once
                                -- become the selected container -- give up on
                                -- it silently rather than clicking the same
                                -- tree entry forever. `readingsNotSelected`
                                -- is written in the memory update from the
                                -- reading alone, so it keeps climbing whether
                                -- or not any particular click here was ever
                                -- attributed to this hold, unlike
                                -- `looksWithRoom`.
                                Nothing

                            else if readyToLookAtHoldAgain hold context then
                                Just (lookAtHold context hold targetEntry)

                            else
                                case itemHangarTreeEntry context.readingFromGameClient of
                                    Nothing ->
                                        Just (describeBranch "I do not see the item hangar in this inventory." askForHelpToGetUnstuck)

                                    Just hangarEntry ->
                                        if not (hangarIsSelectedContainer context.readingFromGameClient) then
                                            if previousStepClickedMouse context then
                                                Just (describeBranch "I just clicked -- wait for the reading to catch up." waitForProgressInGame)

                                            else
                                                Just (describeBranch "Select the station's item hangar." (clickUiElement (hangarEntry.selectRegion |> Maybe.withDefault hangarEntry.uiNode)))

                                        else
                                            case firstEligibleHangarItem context hold of
                                                Nothing ->
                                                    Nothing

                                                Just itemNode ->
                                                    if previousStepClickedMouse context then
                                                        Just (describeBranch "I just dragged -- wait for the reading to catch up before dragging again." waitForProgressInGame)

                                                    else
                                                        Just
                                                            (describeBranch
                                                                ("Drag an item from the item hangar into the " ++ describeHold hold ++ " (attempt " ++ String.fromInt ((holdProgressFor hold context.memory).dragsDispatched + 1) ++ ").")
                                                                (dragFromItemIconOntoUiElement itemNode (targetEntry.selectRegion |> Maybe.withDefault targetEntry.uiNode))
                                                            )


{-| Whether the previous drag into (or out of) `hold` needs a fresh look at
its gauge before deciding anything else -- mirrors the drone-bay restock's own
"one look precedes each drag" bookkeeping.
-}
readyToLookAtHoldAgain : Hold -> BotDecisionContext -> Bool
readyToLookAtHoldAgain hold context =
    let
        progress =
            holdProgressFor hold context.memory
    in
    progress.looksWithRoom <= progress.dragsDispatched && not (holdIsSelectedContainer hold context.readingFromGameClient)


lookAtHold : BotDecisionContext -> Hold -> EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry -> DecisionPathNode
lookAtHold context hold treeEntry =
    if previousStepClickedMouse context then
        describeBranch "I just clicked -- wait for the reading to catch up." waitForProgressInGame

    else
        describeBranch
            ("Select the " ++ describeHold hold ++ " to read its capacity gauge (look " ++ String.fromInt ((holdProgressFor hold context.memory).looksWithRoom + 1) ++ " of " ++ String.fromInt holdLooksBeforeGivingUp ++ ").")
            (clickUiElement (treeEntry.selectRegion |> Maybe.withDefault treeEntry.uiNode))


describeHold : Hold -> String
describeHold hold =
    case hold of
        CargoHold ->
            "ship's cargo hold"

        OreHold ->
            "ship's ore/mining hold"


holdProgressFor : Hold -> BotMemory -> HoldProgress
holdProgressFor hold memory =
    case hold of
        CargoHold ->
            memory.cargoHold

        OreHold ->
            memory.oreHold


{-| The hold's own left-tree entry. The general cargo hold has no fixed label
-- it carries the ship's own name -- so it is found by node type, the same
trick `eve-online-mission-runner`'s `loadCourierCargo` uses. The ore/mining
hold *is* found by label, since nothing in this repo has established a type
name for it the way `"TreeViewEntryInventoryCargo"` is established for cargo;
both "ore hold" and "mining hold" are matched, since which the client renders
for a hauler hull specifically is unverified against a live client.
-}
holdTreeEntry : Hold -> ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
holdTreeEntry hold readingFromGameClient =
    holdInventoryWindow readingFromGameClient
        |> Maybe.andThen
            (\inventoryWindow ->
                case hold of
                    CargoHold ->
                        inventoryWindow.leftTreeEntries
                            |> List.concatMap flattenInventoryTreeEntry
                            |> List.filter (.uiNode >> .uiNode >> .pythonObjectTypeName >> (==) "TreeViewEntryInventoryCargo")
                            |> List.head

                    OreHold ->
                        inventoryWindow.leftTreeEntries
                            |> List.concatMap flattenInventoryTreeEntry
                            |> List.filter
                                (\entry ->
                                    stringContainsIgnoringCase "ore hold" entry.text
                                        || stringContainsIgnoringCase "mining hold" entry.text
                                )
                            |> List.head
            )


{-| Which hold's tree entry the previous step's drag ended on, by comparing
the drag's own final `MouseMoveTo` (the drop point) against each hold's
current on-screen region. `Nothing` covers both "the previous step was not a
drag" and "it landed nowhere either hold currently occupies" -- the caller
treats both the same way, by crediting neither hold.
-}
holdBeingDraggedIntoLastStep : ReadingFromGameClient -> List EffectOnWindow.EffectOnWindowStruct -> Maybe Hold
holdBeingDraggedIntoLastStep readingFromGameClient effects =
    case lastMouseMoveLocation effects of
        Nothing ->
            Nothing

        Just location ->
            [ CargoHold, OreHold ]
                |> List.filter
                    (\hold ->
                        holdTreeEntry hold readingFromGameClient
                            |> Maybe.map (\entry -> pointIsWithinRegion location (entry.selectRegion |> Maybe.withDefault entry.uiNode).totalDisplayRegionVisible)
                            |> Maybe.withDefault False
                    )
                |> List.head


lastMouseMoveLocation : List EffectOnWindow.EffectOnWindowStruct -> Maybe { x : Int, y : Int }
lastMouseMoveLocation effects =
    effects
        |> List.filterMap
            (\effect ->
                case effect of
                    EffectOnWindow.MouseMoveTo location ->
                        Just location

                    _ ->
                        Nothing
            )
        |> List.reverse
        |> List.head


pointIsWithinRegion : { x : Int, y : Int } -> { x : Int, y : Int, width : Int, height : Int } -> Bool
pointIsWithinRegion point region =
    (region.x <= point.x)
        && (point.x <= region.x + region.width)
        && (region.y <= point.y)
        && (point.y <= region.y + region.height)


itemHangarTreeEntry : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
itemHangarTreeEntry readingFromGameClient =
    holdInventoryWindow readingFromGameClient
        |> Maybe.andThen
            (\inventoryWindow ->
                inventoryWindow.leftTreeEntries
                    |> List.concatMap flattenInventoryTreeEntry
                    |> List.filter (.text >> stringContainsIgnoringCase "item hangar")
                    |> List.head
            )


flattenInventoryTreeEntry :
    EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
    -> List EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
flattenInventoryTreeEntry entry =
    entry
        :: (entry.children
                |> List.map EveOnline.ParseUserInterface.unwrapInventoryWindowLeftTreeEntryChild
                |> List.concatMap flattenInventoryTreeEntry
           )


{-| The one inventory window this bot works in. There is normally exactly
one open (per the setup instructions); if the client opened a second one
(e.g. from double-clicking a wreck), prefer whichever one currently shows the
ship's cargo tree entry at all, falling back to the first.
-}
holdInventoryWindow : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindow
holdInventoryWindow readingFromGameClient =
    readingFromGameClient.inventoryWindows |> List.head


{-| Whether `hold` is the currently selected/viewed container in the
inventory window -- checked structurally, via the same "SelectionIndicator"
node `eve-online-mining-bot` already uses to detect its own mining hold on
this Photon-UI client build, rather than by guessing the selected-container's
own `pythonObjectTypeName` (which, unlike `"ShipDroneBay"`, is not established
anywhere in this repo for either the cargo or the ore hold -- see the header
comment).
-}
holdIsSelectedContainer : Hold -> ReadingFromGameClient -> Bool
holdIsSelectedContainer hold readingFromGameClient =
    case holdTreeEntry hold readingFromGameClient of
        Nothing ->
            False

        Just treeEntry ->
            containsSelectionIndicatorPhotonUI treeEntry.uiNode


hangarIsSelectedContainer : ReadingFromGameClient -> Bool
hangarIsSelectedContainer readingFromGameClient =
    case itemHangarTreeEntry readingFromGameClient of
        Nothing ->
            False

        Just treeEntry ->
            containsSelectionIndicatorPhotonUI treeEntry.uiNode


containsSelectionIndicatorPhotonUI : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion -> Bool
containsSelectionIndicatorPhotonUI =
    EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion
        >> List.any
            (.uiNode
                >> (\uiNode ->
                        (uiNode.pythonObjectTypeName |> String.startsWith "SelectionIndicator")
                            && (uiNode
                                    |> EveOnline.ParseUserInterface.getColorPercentFromDictEntries
                                    |> Maybe.map (.a >> (<) 10)
                                    |> Maybe.withDefault False
                               )
                   )
            )


{-| Whether `hold` currently holds anything at all -- only meaningful once it
is the selected container; `False` if it is not selected, since there is
nothing to read.
-}
holdCarriesAnything : Hold -> ReadingFromGameClient -> Bool
holdCarriesAnything hold readingFromGameClient =
    holdIsSelectedContainer hold readingFromGameClient
        && (itemsInSelectedContainer readingFromGameClient /= [])


itemsInSelectedContainer : ReadingFromGameClient -> List UITreeNodeWithDisplayRegion
itemsInSelectedContainer readingFromGameClient =
    holdInventoryWindow readingFromGameClient
        |> Maybe.map inventoryItemsInView
        |> Maybe.withDefault []


inventoryItemsInView : EveOnline.ParseUserInterface.InventoryWindow -> List UITreeNodeWithDisplayRegion
inventoryItemsInView inventoryWindow =
    case inventoryWindow.selectedContainerInventory |> Maybe.andThen .itemsView of
        Just (EveOnline.ParseUserInterface.InventoryItemsListView listView) ->
            listView.items |> List.map .uiNode

        Just (EveOnline.ParseUserInterface.InventoryItemsNotListView notListView) ->
            notListView.items

        Nothing ->
            []


{-| The first item in the (currently selected) item hangar eligible for
`hold` -- matching `include-item-pattern` if any is set, and, for the ore
hold specifically, matching `ore-hold-item-pattern`; for the cargo hold,
anything eligible that is *not* an ore-hold match, so ore never lands in
general cargo while the ore hold still has room for it (the ore hold's own
`willTakeNoMore` latch is what lets ore fall through to cargo once it is
full or absent).
-}
firstEligibleHangarItem : BotDecisionContext -> Hold -> Maybe UITreeNodeWithDisplayRegion
firstEligibleHangarItem context hold =
    let
        settings =
            context.eventContext.botSettings

        itemsInView =
            holdInventoryWindow context.readingFromGameClient
                |> Maybe.map inventoryItemsInView
                |> Maybe.withDefault []

        textOf itemNode =
            itemNode.uiNode |> EveOnline.ParseUserInterface.getAllContainedDisplayTexts |> String.join " "

        includedAtAll text =
            (settings.includeItemPatterns == [])
                || List.any (\pattern -> stringContainsIgnoringCase pattern text) settings.includeItemPatterns

        isOreMatch text =
            List.any (\pattern -> stringContainsIgnoringCase pattern text) settings.oreHoldItemPatterns

        oreHoldExists =
            holdTreeEntry OreHold context.readingFromGameClient /= Nothing
    in
    itemsInView
        |> List.filter (textOf >> includedAtAll)
        |> List.filter
            (\itemNode ->
                let
                    text =
                        textOf itemNode
                in
                case hold of
                    OreHold ->
                        isOreMatch text

                    CargoHold ->
                        not (oreHoldExists && isOreMatch text)
            )
        |> List.head


{-| A quantity dialog (accepted -- its default already reflects what fits) or
a refusal dialog ("No room for more in destination container", dismissed and
latched as `willTakeNoMore`) for `hold`, if either is currently on screen.
Ported from the drone-bay restock's `okButtonInReading` /
`dismissRefusedDropIntoDroneBay` pair.
-}
dropRefusalStep : BotDecisionContext -> Hold -> Maybe DecisionPathNode
dropRefusalStep context hold =
    if (holdProgressFor hold context.memory).dragsDispatched <= 0 then
        Nothing

    else
        case okButtonInReading context.readingFromGameClient of
            Nothing ->
                Nothing

            Just okButton ->
                if previousStepClickedMouse context then
                    Just (describeBranch "I just clicked -- wait for the reading to catch up before deciding on the dialog again." waitForProgressInGame)

                else if dropWasRefused context.readingFromGameClient then
                    Just
                        (describeBranch
                            ("The client refused the drop into the " ++ describeHold hold ++ " -- '" ++ dropRefusedDialogText ++ " in destination container'. It will take no more; dismiss this and move on.")
                            (clickUiElement okButton)
                        )

                else
                    Just
                        (describeBranch
                            ("Accept the quantity dialog for the " ++ describeHold hold ++ ", whose default already reflects what fits.")
                            (clickUiElement okButton)
                        )


okButtonInReading : ReadingFromGameClient -> Maybe UITreeNodeWithDisplayRegion
okButtonInReading readingFromGameClient =
    [ "OK", "Ok" ]
        |> List.filterMap (\label -> readingFromGameClient |> widestNodeLabelledExactly { label = label, pythonObjectTypeName = Nothing })
        |> List.head


dropWasRefused : ReadingFromGameClient -> Bool
dropWasRefused readingFromGameClient =
    readingFromGameClient.uiTree.uiNode
        |> EveOnline.ParseUserInterface.getAllContainedDisplayTexts
        |> List.any (stringContainsIgnoringCase dropRefusedDialogText)


dropRefusedDialogText : String
dropRefusedDialogText =
    "No room for more"


{-| Unload one item from `hold` into the item hangar, or say why none was
unloaded. `Nothing` means this hold is empty (or does not exist) -- the
caller tries the other hold, or concludes both are drained.
-}
unloadOneItemFromHold : BotDecisionContext -> Hold -> Maybe DecisionPathNode
unloadOneItemFromHold context hold =
    if hold == OreHold && holdTreeEntry OreHold context.readingFromGameClient == Nothing then
        Nothing

    else
        case holdTreeEntry hold context.readingFromGameClient of
            Nothing ->
                Nothing

            Just holdEntry ->
                if not (holdIsSelectedContainer hold context.readingFromGameClient) then
                    if holdSelectionFailuresBeforeGivingUp <= (holdProgressFor hold context.memory).readingsNotSelected then
                        -- Same give-up as the loading side: this hold has
                        -- never once become the selected container, however
                        -- many readings it has been asked for. Give up on it
                        -- silently rather than clicking the same tree entry
                        -- forever.
                        Nothing

                    else if previousStepClickedMouse context then
                        Just (describeBranch "I just clicked -- wait for the reading to catch up." waitForProgressInGame)

                    else
                        Just (describeBranch ("Select the " ++ describeHold hold ++ " to see what is in it.") (clickUiElement (holdEntry.selectRegion |> Maybe.withDefault holdEntry.uiNode)))

                else
                    case itemsInSelectedContainer context.readingFromGameClient |> List.head of
                        Nothing ->
                            Nothing

                        Just itemNode ->
                            case itemHangarTreeEntry context.readingFromGameClient of
                                Nothing ->
                                    Just (describeBranch "I do not see the item hangar to unload into." askForHelpToGetUnstuck)

                                Just hangarEntry ->
                                    if previousStepClickedMouse context then
                                        Just (describeBranch "I just dragged -- wait for the reading to catch up before dragging again." waitForProgressInGame)

                                    else
                                        Just
                                            (describeBranch
                                                ("Drag an item from the " ++ describeHold hold ++ " into the item hangar.")
                                                (dragFromItemIconOntoUiElement itemNode (hangarEntry.selectRegion |> Maybe.withDefault hangarEntry.uiNode))
                                            )


undock : BotDecisionContext -> DecisionPathNode
undock context =
    undockUsingStationWindow context


undockWithErrand : BotDecisionContext -> Errand -> DecisionPathNode
undockWithErrand context _ =
    -- The errand itself is written in `updateMemoryForNewReadingFromGame` on
    -- the observed docked -> undocked transition, from the same cargo state
    -- this branch just decided from -- see that function. This wrapper exists
    -- so every call site reads as "undock, heading to X" even though the
    -- write happens one layer down, where the transition is actually visible.
    undock context


undockUsingStationWindow : BotDecisionContext -> DecisionPathNode
undockUsingStationWindow context =
    case context.readingFromGameClient.stationWindow of
        Nothing ->
            describeBranch "I do not see the station window." askForHelpToGetUnstuck

        Just stationWindow ->
            case stationWindow.undockButton of
                Nothing ->
                    case stationWindow.abortUndockButton of
                        Nothing ->
                            describeBranch "I do not see the undock button." askForHelpToGetUnstuck

                        Just _ ->
                            describeBranch "I see we are already undocking." waitForProgressInGame

                Just undockButton ->
                    describeBranch "Click on the button to undock." (clickUiElement undockButton)



-- IN SPACE


decideActionInSpace : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUI -> DecisionPathNode
decideActionInSpace context shipUI =
    if shipUIIndicatesShipIsWarpingOrJumping shipUI then
        describeBranch "I see the ship is warping or jumping. Wait for that to finish."
            (readShipUIModuleButtonTooltipWhereNotYetInMemory context |> Maybe.withDefault waitForProgressInGame)

    else
        case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> .isActive >> Maybe.withDefault False >> not) |> List.head of
            Just ( matchingText, inactiveModule ) ->
                describeBranch ("I see inactive module '" ++ matchingText ++ "' to activate always. Activate it.")
                    (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)

            Nothing ->
                let
                    targetStationName =
                        case context.memory.currentErrand of
                            Just HeadingToDestination ->
                                context.eventContext.botSettings.destinationStationName

                            _ ->
                                context.eventContext.botSettings.sourceStationName
                in
                case infoPanelRouteFirstMarkerFromReadingFromGameClient context.readingFromGameClient of
                    Just infoPanelRouteFirstMarker ->
                        jumpThroughRouteStargate context (routeMarkerCascade context infoPanelRouteFirstMarker)

                    Nothing ->
                        describeBranch
                            ("I see no route. I am heading to '" ++ targetStationName ++ "'.")
                            (routeToStation context targetStationName)


routeMarkerCascade :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
    -> DecisionPathNode
routeMarkerCascade context infoPanelRouteFirstMarker =
    useContextMenuCascade
        ( "route element icon", infoPanelRouteFirstMarker.uiNode )
        (useMenuEntryWithTextContainingFirstOf [ "dock", "jump" ] menuCascadeCompleted)
        context


jumpThroughRouteStargate : BotDecisionContext -> DecisionPathNode -> DecisionPathNode
jumpThroughRouteStargate context ifThePanelCannotDoIt =
    case ( routeStargateJumpFromReading context.readingFromGameClient, routeStargateJumpButton context.readingFromGameClient ) of
        ( PressTheJumpButton _, Just buttonToPress ) ->
            describeBranch "Jump through the route's next stargate from the selected-item panel, which is already showing it." (clickUiElement buttonToPress)

        _ ->
            ifThePanelCannotDoIt


type RouteStargateJump
    = PressTheJumpButton String
    | ThePanelCannotDoIt


routeStargateJumpFromReading : ReadingFromGameClient -> RouteStargateJump
routeStargateJumpFromReading readingFromGameClient =
    case nextSystemOnRouteFromReading readingFromGameClient of
        Nothing ->
            ThePanelCannotDoIt

        Just nextSystem ->
            case
                readingFromGameClient.overviewWindows
                    |> List.concatMap .entries
                    |> List.filter overviewEntryIsDisplayed
                    |> List.filter overviewEntryIsAStargate
                    |> List.filter (.objectName >> Maybe.map (stargateNameLeadsToSystem nextSystem) >> Maybe.withDefault False)
            of
                [ gate ] ->
                    if selectedItemIsOverviewEntry readingFromGameClient gate && routeStargateJumpButton readingFromGameClient /= Nothing then
                        PressTheJumpButton (gate.objectName |> Maybe.withDefault "")

                    else
                        ThePanelCannotDoIt

                _ ->
                    ThePanelCannotDoIt


routeStargateJumpButton : ReadingFromGameClient -> Maybe UITreeNodeWithDisplayRegion
routeStargateJumpButton readingFromGameClient =
    selectedItemButtonNamed readingFromGameClient "selectedItemJump"


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
        |> List.filterMap (\marker -> labelText |> EveOnline.ParseUserInterface.getSubstringBetweenXmlTagsAfterMarker marker)
        |> List.map String.trim
        |> List.filter (String.isEmpty >> not)
        |> List.head


overviewEntryIsAStargate : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsAStargate entry =
    [ entry.objectName, entry.objectType ]
        |> List.filterMap identity
        |> List.any (containsWords "stargate")


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


containsWords : String -> String -> Bool
containsWords pattern text =
    let
        padded value =
            " " ++ (value |> String.toLower |> String.words |> String.join " ") ++ " "
    in
    String.contains (padded pattern) (padded text)


selectedItemButtonNamed : ReadingFromGameClient -> String -> Maybe UITreeNodeWithDisplayRegion
selectedItemButtonNamed readingFromGameClient name =
    readingFromGameClient.selectedItemWindow
        |> Maybe.map (.uiNode >> EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion)
        |> Maybe.withDefault []
        |> List.filter (\node -> (node.uiNode |> EveOnline.ParseUserInterface.getNameFromDictEntries) == Just name)
        |> List.head


selectedItemIsOverviewEntry : ReadingFromGameClient -> EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
selectedItemIsOverviewEntry readingFromGameClient entry =
    case ( readingFromGameClient.selectedItemWindow, entry.objectName ) of
        ( Just window, Just name ) ->
            EveOnline.ParseUserInterface.getAllContainedDisplayTexts window.uiNode.uiNode |> List.any (containsWords name)

        _ ->
            False


overviewEntryIsDisplayed : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsDisplayed entry =
    nodeIsDisplayed entry.uiNode.uiNode


nodeIsDisplayed : EveOnline.MemoryReading.UITreeNode -> Bool
nodeIsDisplayed uiNode =
    uiNode.dictEntriesOfInterest
        |> Dict.get "_display"
        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.bool >> Result.toMaybe)
        |> Maybe.withDefault True



-- SETTING THE ROUTE TO A NAMED STATION


hostDirectivePrefix : String
hostDirectivePrefix =
    "@host "


hostDirectiveSetDestination : String -> String
hostDirectiveSetDestination stationName =
    hostDirectivePrefix ++ "set-destination " ++ stationName


{-| ESI resolves a player-owned structure's name only through the
authenticated character search (see `esi_waypoint.py`'s
`_resolve_via_character_search`), which needs the character to already have
docking access to it -- so the first trip to a structure the character has
never visited still falls to the search bar below. A right-click-in-the-
Assets-window alternative was tried and abandoned here: it depends on a
generic "widest node mentioning the word Assets" heuristic to find the
window at all, and a live run showed that heuristic landing on something
other than the Assets window, with the follow-on right-click finding no
usable menu. Once ESI has resolved a structure once, it keeps resolving it
for the rest of this repo's `resolve_name` cache and every subsequent
session, so the search bar only ever has to carry a station or structure
through its very first visit.
-}
routeToStation : BotDecisionContext -> String -> DecisionPathNode
routeToStation context stationName =
    if esiRouteIsPreferred context then
        describeBranch
            ("Ask the host to set the route to '" ++ stationName ++ "' through ESI, which can name a station this bot cannot type.")
            (describeBranch (hostDirectiveSetDestination stationName) waitForProgressInGame)

    else
        routeToStationByName context stationName


esiRouteIsPreferred : BotDecisionContext -> Bool
esiRouteIsPreferred context =
    (context.eventContext.botSettings.routeByEsi == AppSettings.Yes)
        && (searchResultsWindow context == Nothing)
        && not (esiRouteAskHasGoneUnanswered context.previousStepsEffects)


esiRouteAskHasGoneUnanswered : List (List EffectOnWindow.EffectOnWindowStruct) -> Bool
esiRouteAskHasGoneUnanswered previousStepsEffects =
    let
        recentSteps =
            previousStepsEffects |> List.take esiRouteReadingsBeforeSearchBar
    in
    (List.length recentSteps == esiRouteReadingsBeforeSearchBar) && List.all List.isEmpty recentSteps


esiRouteReadingsBeforeSearchBar : Int
esiRouteReadingsBeforeSearchBar =
    3


routeToStationByName : BotDecisionContext -> String -> DecisionPathNode
routeToStationByName context stationName =
    let
        query =
            searchQueryForStation stationName

        withinWindow window textToFind =
            findUiElementWithText textToFind window
    in
    case stationInfoWindowForStation context stationName |> Maybe.andThen (\window -> withinWindow window "Set Destination") of
        Just setDestination ->
            describeBranch ("Set destination to '" ++ stationName ++ "'.") (clickUiElement setDestination)

        Nothing ->
            case searchResultsWindow context of
                Just resultsWindow ->
                    case withinWindow resultsWindow stationName of
                        Just row ->
                            describeBranch ("Open '" ++ stationName ++ "' from the search results.") (doubleClickUiElement row)

                        Nothing ->
                            let
                                stationsGroup =
                                    withinWindow resultsWindow "Stations ("

                                readingsSoFar =
                                    context.memory.searchResultsWithoutStationInfoTicks
                            in
                            if searchResultsWithoutStationInfoTicksBeforeGivingUp <= readingsSoFar then
                                describeBranch
                                    ("The search results do not offer '" ++ stationName ++ "' after " ++ String.fromInt readingsSoFar ++ " readings.")
                                    askForHelpToGetUnstuck

                            else
                                case stationsGroup of
                                    Just group ->
                                        if previousStepClickedMouse context then
                                            describeBranch "I just clicked in the search results -- wait for the reading to catch up." waitForProgressInGame

                                        else
                                            describeBranch "Expand the Stations group in the search results." (clickUiElement group)

                                    Nothing ->
                                        describeBranch ("The search results do not (yet) offer '" ++ stationName ++ "'. Wait.") waitForProgressInGame

                Nothing ->
                    if context.memory.readingsSinceSearchSubmitted < searchSubmitCooldownReadings then
                        describeBranch
                            ("Waiting for a search results window to appear (submitted " ++ String.fromInt context.memory.readingsSinceSearchSubmitted ++ " of " ++ String.fromInt searchSubmitCooldownReadings ++ " readings ago) rather than searching again -- the client refuses a search submitted too soon after the last one.")
                            waitForProgressInGame

                    else
                        case searchInputField context of
                            Just searchField ->
                                if previousStepClickedMouse context then
                                    describeBranch "I just clicked the search bar -- wait for the reading to catch up before typing." waitForProgressInGame

                                else
                                    describeBranch ("Search for '" ++ query ++ "'.")
                                        (decideActionForCurrentStep
                                            (List.concat
                                                [ mouseClickOnUIElement MouseButtonLeft searchField |> Result.withDefault []
                                                , clearTextFieldEffects
                                                , typeTextEffects query
                                                , [ EffectOnWindow.KeyDown EffectOnWindow.vkey_RETURN, EffectOnWindow.KeyUp EffectOnWindow.vkey_RETURN ]
                                                ]
                                            )
                                        )

                            Nothing ->
                                describeBranch "I do not see the search bar." askForHelpToGetUnstuck


stationInfoWindowForStation : BotDecisionContext -> String -> Maybe UITreeNodeWithDisplayRegion
stationInfoWindowForStation context stationName =
    allUiNodesInReading context
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InfoWindow")
        |> List.filter (\window -> EveOnline.ParseUserInterface.getAllContainedDisplayTexts window.uiNode |> List.any (stringContainsIgnoringCase stationName))
        |> List.head


{-| The full name is what actually distinguishes a station or structure in
the search results, so it is what gets typed whenever every character in it
can be. NPC station names commonly carry parentheses (`Amarr VIII (Oris) -
Emperor Family Academy`), which this bot cannot type at all, so those still
fall back to the tail after the last `" - "` -- the distinctive part, and free
of the punctuation that cannot be pressed. A player-owned structure's name
typically carries none of that (just a hyphen, which is typeable), so it goes
in whole. Confirmed live that the truncated form can fail where the full name
succeeds: searching just the tail of a structure's name returned nothing
useful, where the operator's own manual search on the full name found it.
-}
searchQueryForStation : String -> String
searchQueryForStation stationName =
    if stationName |> String.all (\char -> virtualKeyCodeForTypedCharacter char /= Nothing) then
        stationName

    else
        stationName |> String.split " - " |> List.reverse |> List.head |> Maybe.withDefault stationName


allUiNodesInReading : BotDecisionContext -> List UITreeNodeWithDisplayRegion
allUiNodesInReading context =
    context.readingFromGameClient.uiTree |> EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion


searchInputField : BotDecisionContext -> Maybe UITreeNodeWithDisplayRegion
searchInputField context =
    allUiNodesInReading context |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InfoPanelSearch") |> List.head


searchResultsWindow : BotDecisionContext -> Maybe UITreeNodeWithDisplayRegion
searchResultsWindow context =
    searchResultsWindowInReading context.readingFromGameClient


searchResultsWindowInReading : ReadingFromGameClient -> Maybe UITreeNodeWithDisplayRegion
searchResultsWindowInReading readingFromGameClient =
    readingFromGameClient.uiTree
        |> EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ListWindow")
        |> List.filter (\window -> EveOnline.ParseUserInterface.getAllContainedDisplayTexts window.uiNode |> List.any (stringContainsIgnoringCase "Search Results"))
        |> List.head


findUiElementWithText : String -> UITreeNodeWithDisplayRegion -> Maybe UITreeNodeWithDisplayRegion
findUiElementWithText textToFind uiNode =
    EveOnline.ParseUserInterface.getAllContainedDisplayTextsWithRegion uiNode
        |> List.filter (Tuple.first >> stringContainsIgnoringCase textToFind)
        |> List.map Tuple.second
        |> List.head


{-| Move to the end of whatever the field already holds and backspace well
past any plausible search query, so a query dispatched into a field that
still carries an earlier attempt (the search-results window not opening in
time, or opening under a caption the parser does not recognise) replaces it
instead of appending onto it. Confirmed live to be needed: an earlier run of
this bot typed the same query into the field twice in a row and produced
`freeportfreeport`.
-}
clearTextFieldEffects : List EffectOnWindow.EffectOnWindowStruct
clearTextFieldEffects =
    [ EffectOnWindow.KeyDown EffectOnWindow.vkey_END, EffectOnWindow.KeyUp EffectOnWindow.vkey_END ]
        ++ (List.repeat 40 () |> List.concatMap (\_ -> [ EffectOnWindow.KeyDown EffectOnWindow.vkey_BACK, EffectOnWindow.KeyUp EffectOnWindow.vkey_BACK ]))


typeTextEffects : String -> List EffectOnWindow.EffectOnWindowStruct
typeTextEffects text =
    text
        |> String.toList
        |> List.filterMap virtualKeyCodeForTypedCharacter
        |> List.concatMap (\key -> [ EffectOnWindow.KeyDown key, EffectOnWindow.KeyUp key ])


virtualKeyCodeForTypedCharacter : Char -> Maybe EffectOnWindow.VirtualKeyCode
virtualKeyCodeForTypedCharacter char =
    let
        code =
            char |> Char.toUpper |> Char.toCode
    in
    if char == '-' then
        -- On this host's own vkey_* values are literal Windows virtual key
        -- codes with no translation table between them and what gets sent,
        -- unlike the macOS host's `_VK_TO_CGKEYCODE`, which is missing
        -- `vkey_SUBTRACT` entirely -- see `tools/windows-host/input.py`'s own
        -- header comment. Needed so a station or structure name carrying a
        -- hyphen (most player-owned structures do; NPC station names use
        -- parentheses instead, which stay untypeable) can be searched for by
        -- its full name rather than a truncated substring.
        Just EffectOnWindow.vkey_SUBTRACT

    else if (0x41 <= code && code <= 0x5A) || (0x30 <= code && code <= 0x39) || code == 0x20 then
        Just (EffectOnWindow.VirtualKeyCodeFromInt code)

    else
        Nothing



-- SHARED LOW-LEVEL HELPERS


clickUiElement : UITreeNodeWithDisplayRegion -> DecisionPathNode
clickUiElement uiElement =
    decideActionForCurrentStep (mouseClickOnUIElement MouseButtonLeft uiElement |> Result.withDefault [])


doubleClickUiElement : UITreeNodeWithDisplayRegion -> DecisionPathNode
doubleClickUiElement uiElement =
    decideActionForCurrentStep (mouseDoubleClickOnUIElement MouseButtonLeft uiElement |> Result.withDefault [])


{-| Drag an inventory item onto a sidebar row, taking hold of the item's own
icon rather than the centre of whatever region it reports.

**Confirmed live to matter, and confirmed live to be wrong before this fix.**
The item hangar and hold can each be read as either
`EveOnline.ParseUserInterface.InventoryItemsListView` (a table of rows, icon
then name then quantity then volume, much wider than it is tall) or
`InventoryItemsNotListView` (a roughly square icon stacked over its label) --
`inventoryItemsInView` already handles both when *finding* items, but this
function used one grab point for both, taking the horizontal centre of
whatever region it was handed. Centred on a list-view row that lands on a
text column or the gap between two of them, not on the icon -- and a
click-drag that starts there reads as a rubber-band multi-select rather than
picking the item up, which is exactly what a live run showed: repeated
"drag" attempts that each selected every item in the hangar and moved
nothing, the hold never gaining anything and the hangar never losing
anything.

Distinguished by the region's own shape rather than by threading the view
mode through every caller: a list-view row is much wider than it is tall,
where an icon-view item is not.

**A plain click at the same point precedes the drag, in the same step, and
this is confirmed live to be necessary.** The grab point alone was not
enough: two consecutive attempts read back the identical item region -- the
item never actually left the hangar -- despite the point landing within the
icon's own bounds by the numbers, and the operator confirmed the client's
own visible symptom was every item in the hangar getting selected rather
than one being dragged. The mechanism: an icon-grid selection widget (this
one included) only treats a press-and-drag as *move the item* once that
item is already the active selection; a press-and-drag starting on an item
that is not yet selected is read as the start of a rubber-band multi-select
instead. So a full click (`MouseMoveTo`, `ButtonDown`, `ButtonUp`) at the
same point goes out first, and the drag's own press follows it in the same
dispatched list -- the framework's own `WaitMilliseconds` between every
pair of effects gives the client room to register them as two separate
gestures (select, then drag) rather than one continuous one. Confirmed live
across both directions: a full load and a full unload, both landing.
-}
dragFromItemIconOntoUiElement : UITreeNodeWithDisplayRegion -> UITreeNodeWithDisplayRegion -> DecisionPathNode
dragFromItemIconOntoUiElement itemElement targetElement =
    let
        itemRegion =
            itemElement.totalDisplayRegionVisible

        from =
            itemIconGrabPoint itemRegion

        to =
            targetElement.totalDisplayRegionVisible |> centerFromDisplayRegion

        selectClickEffects =
            [ EffectOnWindow.MouseMoveTo from
            , EffectOnWindow.ButtonDown MouseButtonLeft
            , EffectOnWindow.ButtonUp MouseButtonLeft
            ]
    in
    decideActionForCurrentStep
        (selectClickEffects
            ++ EffectOnWindow.effectsForDragAndDrop
                { startLocation = from
                , mouseButton = MouseButtonLeft
                , waypointsPositionsInBetween = [ { x = (from.x + to.x) // 2, y = (from.y + to.y) // 2 } ]
                , endLocation = to
                }
        )


{-| **List-view rows are confirmed live**, 16px inset from the row's own left
edge: a full two-stack unload landed cleanly this way. **Icon-view grid items
have a known, unresolved limitation past the first column.** A single item
in the grid's first slot drags correctly with the plain
`region.width // 2` centre this branch uses -- confirmed live, the same run
that established the click-then-drag fix above. A *second* item, one column
over, did not: the operator watched the drag land to the left of the second
column's icon, repeatedly, and no offset tried here corrected it before the
operator switched that inventory panel to list view instead, which is the
operational workaround this bot currently depends on for any hold or hangar
that can hold more than one stack in icon view. Multi-column icon-grid
geometry (a per-column x offset, not just a row/label y offset) was never
worked out; the fix in production is "use list view here," not a code
change.
-}
itemIconGrabPoint : { x : Int, y : Int, width : Int, height : Int } -> { x : Int, y : Int }
itemIconGrabPoint region =
    if region.width > region.height * 3 then
        -- A list-view row. The icon sits at the row's own left edge; grab
        -- there rather than at the horizontal centre, which is what read as
        -- a rubber-band multi-select instead of an item drag.
        { x = region.x + min itemListRowIconOffsetFromLeft (region.width // 2)
        , y = region.y + (region.height // 2)
        }

    else
        -- An icon-view item: a roughly square icon stacked over its label.
        -- `itemIconOffsetFromTop` is `reload_drones.py`'s own offset for
        -- exactly this shape. Only confirmed correct for a single item in
        -- the grid's first column -- see the doc comment above.
        { x = region.x + (region.width // 2)
        , y = region.y + min itemIconOffsetFromTop (region.height // 2)
        }


itemListRowIconOffsetFromLeft : Int
itemListRowIconOffsetFromLeft =
    16


itemIconOffsetFromTop : Int
itemIconOffsetFromTop =
    25


widestNodeLabelledExactly : { label : String, pythonObjectTypeName : Maybe String } -> ReadingFromGameClient -> Maybe UITreeNodeWithDisplayRegion
widestNodeLabelledExactly config readingFromGameClient =
    readingFromGameClient.uiTree
        |> EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion
        |> List.filter
            (\node ->
                ((config.pythonObjectTypeName == Nothing) || (config.pythonObjectTypeName == Just node.uiNode.pythonObjectTypeName))
                    && (firstVisibleTextOfNode node == Just config.label)
            )
        |> List.sortBy (.totalDisplayRegionVisible >> .width >> negate)
        |> List.head


firstVisibleTextOfNode : UITreeNodeWithDisplayRegion -> Maybe String
firstVisibleTextOfNode node =
    node.uiNode
        |> EveOnline.ParseUserInterface.getAllContainedDisplayTexts
        |> List.map (EveOnline.ParseUserInterface.stripHtmlTags >> String.trim)
        |> List.filter (String.isEmpty >> not)
        |> List.head


previousStepClickedMouse : BotDecisionContext -> Bool
previousStepClickedMouse context =
    previousStepsEffectsPressedMouse context.previousStepsEffects


previousStepsEffectsPressedMouse : List (List EffectOnWindow.EffectOnWindowStruct) -> Bool
previousStepsEffectsPressedMouse previousStepsEffects =
    previousStepsEffects
        |> List.take 1
        |> List.any (List.any (\effect -> effect == EffectOnWindow.ButtonDown MouseButtonLeft))


selectedContainerTypeNameOfWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe String
selectedContainerTypeNameOfWindow inventoryWindow =
    inventoryWindow.selectedContainerInventory |> Maybe.map (.uiNode >> .uiNode >> .pythonObjectTypeName)



-- MODULE ACTIVATION (optional, `activate-module-always`)


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filterMap
            (\moduleButton ->
                moduleButton
                    |> EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                    |> Maybe.andThen (tooltipLooksLikeModuleToActivateAlways context)
                    |> Maybe.map (\moduleName -> ( moduleName, moduleButton ))
            )


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> ModuleButtonTooltipMemory -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .allContainedDisplayTextsWithRegion
        >> List.map Tuple.first
        >> List.filterMap
            (\tooltipText ->
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



-- MEMORY


updateMemoryForNewReadingFromGame : UpdateMemoryContext BotSettings -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context memoryBefore =
    let
        currentStationNameFromInfoPanel =
            dockedStationNameFromInfoPanel context.readingFromGameClient

        isDockedNow =
            currentStationNameFromInfoPanel /= Nothing

        -- The undock transition: docked in the *previous* reading, now
        -- seeing the ship UI in space. This is the one moment the errand is
        -- decided and written -- see the header comment on `Errand`.
        --
        -- Deliberately keyed on `dockedLastReading` rather than on
        -- `lastDockedStationNameFromInfoPanel /= Nothing` -- that field is
        -- never cleared once the bot has docked anywhere once (it exists to
        -- answer "where did we last see a station name", not "are we docked
        -- right now"), so a check against it reads `True` on every reading
        -- spent in space for the rest of the session, not just the reading
        -- right after undocking. Confirmed live: that mistake had
        -- `tripsCompleted` climbing by one every couple of readings while the
        -- ship was still travelling to the source station on its first trip.
        justUndocked =
            memoryBefore.dockedLastReading
                && not isDockedNow
                && (context.readingFromGameClient.shipUI /= Nothing)

        currentErrand =
            if justUndocked then
                -- Read from `memoryBefore` rather than
                -- `context.readingFromGameClient` deliberately:
                -- `holdCarriesAnything` needs the hold to be the currently
                -- *selected* container to answer anything but `False`, and
                -- by the reading the ship has just undocked, neither hold
                -- is likely to still be selected -- confirmed live, this
                -- read the ship as carrying nothing on every undock and
                -- sent it straight back to the source station it had just
                -- loaded cargo at. `holdOrLikelyCarriesAnything` reads what
                -- was last genuinely seen while still docked instead, which
                -- `holdProgressAfter`'s own "not docked -> reset" branch
                -- has not yet overwritten on this same reading.
                if holdOrLikelyCarriesAnything CargoHold memoryBefore || holdOrLikelyCarriesAnything OreHold memoryBefore then
                    Just HeadingToDestination

                else
                    Just HeadingToSource

            else
                memoryBefore.currentErrand

        cargoOpenedFromShipCard =
            if isDockedNow then
                if (holdInventoryWindow context.readingFromGameClient |> Maybe.andThen selectedContainerTypeNameOfWindow) /= Nothing then
                    True

                else
                    memoryBefore.cargoOpenedFromShipCard

            else
                -- Reset on undock; a fresh dock needs the ship-card cascade
                -- again, since the inventory window does not carry a
                -- selection across a session change reliably.
                False

        -- Which hold, if any, the previous step's drag actually dropped onto
        -- -- resolved by the drop's screen position against this reading's
        -- own tree-entry regions, the same technique this repo already uses
        -- to attribute a lock click to an overview row (see
        -- `lockClickLocationFromStepEffects` elsewhere in this project).
        -- Needed because both holds' progress is tracked independently, and
        -- a single shared "did the previous step press the mouse" flag would
        -- credit *both* holds' `dragsDispatched` for one drag into either of
        -- them.
        lastDraggedIntoHold =
            holdBeingDraggedIntoLastStep context.readingFromGameClient (context.previousStepsEffects |> List.head |> Maybe.withDefault [])

        holdProgressAfter hold =
            let
                progressBefore =
                    holdProgressFor hold memoryBefore

                wasLastDraggedInto =
                    lastDraggedIntoHold == Just hold

                isSelectedNow =
                    holdIsSelectedContainer hold context.readingFromGameClient

                progressBeforeGiveUpTracking =
                    if not isDockedNow then
                        initHoldProgress

                    else if wasLastDraggedInto && dropWasRefused context.readingFromGameClient then
                        -- Refusal attribution shares the same drag-target
                        -- evidence, so it cannot mis-credit the other hold
                        -- either. The one gap left: a refusal dialog that is
                        -- still up several readings after the drag that
                        -- caused it, with a *different* hold dragged into in
                        -- between, would go unattributed here (the decision
                        -- tree still dismisses it via `dropRefusalStep`,
                        -- which is more lenient -- it just would not latch
                        -- `willTakeNoMore` on the right hold in that narrow
                        -- case).
                        { progressBefore | willTakeNoMore = True, dragsDispatched = progressBefore.dragsDispatched + 1 }

                    else if isSelectedNow then
                        { progressBefore
                            | looksWithRoom = progressBefore.looksWithRoom + 1
                            , carriesAnythingAsOfLastLook = Just (itemsInSelectedContainer context.readingFromGameClient /= [])
                        }

                    else if wasLastDraggedInto then
                        { progressBefore | dragsDispatched = progressBefore.dragsDispatched + 1 }

                    else
                        progressBefore
            in
            -- `readingsNotSelected` is tracked independently of the branches
            -- above: whether or not any click lands is ambiguous (a plain
            -- select click and a drag can both be attributed to this hold by
            -- `holdBeingDraggedIntoLastStep`, since both end with a
            -- `MouseMoveTo` inside the same tree-entry region), but whether
            -- the hold is *actually* the selected container this reading is
            -- not. Counting readings rather than attributed clicks is what
            -- keeps the give-up in `loadOneItemIntoHold` reachable even if
            -- selection can never be confirmed at all.
            if not isDockedNow then
                progressBeforeGiveUpTracking

            else if isSelectedNow then
                { progressBeforeGiveUpTracking | readingsNotSelected = 0 }

            else
                { progressBeforeGiveUpTracking | readingsNotSelected = progressBeforeGiveUpTracking.readingsNotSelected + 1 }

        tripsCompleted =
            memoryBefore.tripsCompleted
                + (if
                    justUndocked
                        && (memoryBefore.currentErrand == Just HeadingToSource)
                        && not (holdOrLikelyCarriesAnything CargoHold memoryBefore)
                        && not (holdOrLikelyCarriesAnything OreHold memoryBefore)
                   then
                    1

                   else
                    0
                  )
    in
    { shipModules =
        memoryBefore.shipModules
            |> EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory context.readingFromGameClient
    , currentErrand = currentErrand
    , cargoOpenedFromShipCard = cargoOpenedFromShipCard
    , cargoHold = holdProgressAfter CargoHold
    , oreHold = holdProgressAfter OreHold
    , tripsCompleted = tripsCompleted
    , lastDockedStationNameFromInfoPanel =
        [ currentStationNameFromInfoPanel, memoryBefore.lastDockedStationNameFromInfoPanel ] |> List.filterMap identity |> List.head
    , searchResultsWithoutStationInfoTicks =
        if searchResultsWindowInReading context.readingFromGameClient /= Nothing then
            memoryBefore.searchResultsWithoutStationInfoTicks + 1

        else
            0
    , dockedLastReading = isDockedNow
    , readingsSinceSearchSubmitted =
        if
            context.previousStepsEffects
                |> List.take 1
                |> List.any (List.any ((==) (EffectOnWindow.KeyDown EffectOnWindow.vkey_RETURN)))
        then
            0

        else
            memoryBefore.readingsSinceSearchSubmitted + 1
    }



-- STATUS TEXT


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        describeErrand =
            case context.memory.currentErrand of
                Just HeadingToSource ->
                    "heading to source ('" ++ context.eventContext.botSettings.sourceStationName ++ "')"

                Just HeadingToDestination ->
                    "heading to destination ('" ++ context.eventContext.botSettings.destinationStationName ++ "')"

                Nothing ->
                    "errand not yet decided"

        describeLocation =
            case dockedStationNameFromInfoPanel context.readingFromGameClient of
                Just stationName ->
                    "docked at '" ++ stationName ++ "'"

                Nothing ->
                    "in space, " ++ describeErrand

        describeHolds =
            "cargo hold drags " ++ String.fromInt context.memory.cargoHold.dragsDispatched ++ (if context.memory.cargoHold.willTakeNoMore then " (full)" else "") ++ ", ore hold drags " ++ String.fromInt context.memory.oreHold.dragsDispatched ++ (if context.memory.oreHold.willTakeNoMore then " (full)" else "")
    in
    [ "Trips completed: " ++ String.fromInt context.memory.tripsCompleted
    , describeLocation
    , describeHolds
    ]
        |> String.join "\n"



-- ENTRY POINT


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , decideNextStep = haulerBotDecisionRoot
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            }
    }

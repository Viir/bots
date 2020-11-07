{- EVE Online Warp-to-0 auto-pilot version 2020-11-07
   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.

   Before starting the bot, set up the game client as follows:

   + Set the UI language to English.
   + Set the in-game autopilot route.
   + Make sure the autopilot info panel is expanded, so that the route is visible.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `module-to-activate-always` : Text found in tooltips of ship modules that should always be active. For example: "cloaking device".

-}
{-
   app-catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree exposing (describeBranch, endDecisionPath)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , ReadingFromGameClient
        , SeeUndockingComplete
        , ShipModulesMemory
        , actWithoutFurtherReadings
        , branchDependingOnDockedOrInSpace
        , clickOnUIElement
        , infoPanelRouteFirstMarkerFromReadingFromGameClient
        , menuCascadeCompleted
        , shipUIIndicatesShipIsWarpingOrJumping
        , useContextMenuCascade
        , useMenuEntryWithTextContainingFirstOf
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface exposing (getAllContainedDisplayTexts)


defaultBotSettings : BotSettings
defaultBotSettings =
    { modulesToActivateAlways = [] }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignments { assignmentsSeparators = [ ",", "\n" ] }
        ([ ( "module-to-activate-always"
           , AppSettings.valueTypeString (\moduleName -> \settings -> { settings | modulesToActivateAlways = moduleName :: settings.modulesToActivateAlways })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { modulesToActivateAlways : List String
    }


type alias BotMemory =
    { lastSolarSystemName : Maybe String
    , jumpsCompleted : Int
    , shipModules : ShipModulesMemory
    }


type alias StateMemoryAndDecisionTree =
    EveOnline.AppFramework.AppStateWithMemoryAndDecisionTree BotMemory


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings StateMemoryAndDecisionTree


type alias BotDecisionContext =
    EveOnline.AppFramework.StepDecisionContext BotSettings BotMemory


initState : State
initState =
    EveOnline.AppFramework.initState
        (EveOnline.AppFramework.initStateWithMemoryAndDecisionTree
            { lastSolarSystemName = Nothing
            , jumpsCompleted = 0
            , shipModules = EveOnline.AppFramework.initShipModulesMemory
            }
        )


statusTextFromState : BotDecisionContext -> String
statusTextFromState context =
    let
        describeSessionPerformance =
            "jumps completed: " ++ (context.memory.jumpsCompleted |> String.fromInt)

        describeCurrentReading =
            "current solar system: "
                ++ (currentSolarSystemNameFromReading context.readingFromGameClient |> Maybe.withDefault "Unknown")
    in
    [ describeSessionPerformance
    , describeCurrentReading
    ]
        |> String.join "\n"


autopilotBotDecisionRoot : BotDecisionContext -> DecisionPathNode
autopilotBotDecisionRoot context =
    branchDependingOnDockedOrInSpace
        { ifDocked = describeBranch "To continue, undock manually." waitForProgressInGame
        , ifSeeShipUI = always Nothing
        , ifUndockingComplete = decisionTreeWhenInSpace context
        }
        context.readingFromGameClient


decisionTreeWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decisionTreeWhenInSpace context undockingComplete =
    case context.readingFromGameClient |> infoPanelRouteFirstMarkerFromReadingFromGameClient of
        Nothing ->
            describeBranch "I see no route in the info panel. I will start when a route is set."
                (waitingInSpaceDecisionTree context)

        Just infoPanelRouteFirstMarker ->
            if undockingComplete.shipUI |> shipUIIndicatesShipIsWarpingOrJumping then
                describeBranch
                    "I see the ship is warping or jumping. I wait until that maneuver ends."
                    (waitingInSpaceDecisionTree context)

            else
                useContextMenuCascade
                    ( "route element icon", infoPanelRouteFirstMarker.uiNode )
                    (useMenuEntryWithTextContainingFirstOf
                        [ "dock", "jump" ]
                        menuCascadeCompleted
                    )
                    context.readingFromGameClient


waitingInSpaceDecisionTree : BotDecisionContext -> DecisionPathNode
waitingInSpaceDecisionTree context =
    case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> .isActive >> Maybe.withDefault False >> not) |> List.head of
        Just ( inactiveModuleMatchingText, inactiveModule ) ->
            describeBranch ("I see inactive module '" ++ inactiveModuleMatchingText ++ "' to activate always. Activate it.")
                (endDecisionPath
                    (actWithoutFurtherReadings
                        ( "Click on the module.", inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft )
                    )
                )

        Nothing ->
            readShipUIModuleButtonTooltips context |> Maybe.withDefault waitForProgressInGame


updateMemoryForNewReadingFromGame : ReadingFromGameClient -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame currentReading memoryBefore =
    let
        ( lastSolarSystemName, newJumpsCompleted ) =
            case currentSolarSystemNameFromReading currentReading of
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
    in
    { jumpsCompleted = memoryBefore.jumpsCompleted + newJumpsCompleted
    , lastSolarSystemName = lastSolarSystemName
    , shipModules =
        EveOnline.AppFramework.integrateCurrentReadingsIntoShipModulesMemory
            currentReading
            memoryBefore.shipModules
    }


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filterMap
            (\moduleButton ->
                moduleButton
                    |> EveOnline.AppFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                    |> Maybe.andThen (tooltipLooksLikeModuleToActivateAlways context)
                    |> Maybe.map (\moduleName -> ( moduleName, moduleButton ))
            )


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> EveOnline.ParseUserInterface.ModuleButtonTooltip -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .uiNode
        >> .uiNode
        >> getAllContainedDisplayTexts
        >> List.filterMap
            (\tooltipText ->
                context.eventContext.appSettings.modulesToActivateAlways
                    |> List.filterMap
                        (\moduleToActivateAlways ->
                            if tooltipText |> String.toLower |> String.contains (moduleToActivateAlways |> String.toLower) then
                                Just tooltipText

                            else
                                Nothing
                        )
                    |> List.head
            )
        >> List.head


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> StateMemoryAndDecisionTree
    -> ( StateMemoryAndDecisionTree, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
        , decisionTreeRoot = autopilotBotDecisionRoot
        , statusTextFromState = statusTextFromState
        , millisecondsToNextReadingFromGame = always 2000
        }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = parseBotSettings
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


currentSolarSystemNameFromReading : ReadingFromGameClient -> Maybe String
currentSolarSystemNameFromReading readingFromGameClient =
    readingFromGameClient.infoPanelContainer
        |> Maybe.andThen .infoPanelLocationInfo
        |> Maybe.andThen .currentSolarSystemName


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.AppFramework.readShipUIModuleButtonTooltipWhereNotYetInMemory

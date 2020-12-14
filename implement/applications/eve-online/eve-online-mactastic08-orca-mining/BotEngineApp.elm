{- Mactastic08 & annar_731 orca mining version 2020-12-14
   Orca mining described by Mactastic08 and annar_731 at https://forum.botengine.org/t/orca-targeting-mining/3591
-}
{-
   app-catalog-tags:eve-online,mining
   authors-forum-usernames:Mactastic08,annar_731,viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20201207 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree exposing (describeBranch)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , ReadingFromGameClient
        , ShipModulesMemory
        , menuCascadeCompleted
        , useContextMenuCascade
        , useContextMenuCascadeOnOverviewEntry
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextEqual
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface exposing (OverviewWindowEntry, getAllContainedDisplayTexts)


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


annar_731_orca_mining_BotDecisionRoot : BotDecisionContext -> DecisionPathNode
annar_731_orca_mining_BotDecisionRoot context =
    if context.readingFromGameClient.targets == [] then
        describeBranch "I see no target, lock an asteroid." (targetAsteroid context)

    else
        -- Send drones part of https://forum.botengine.org/t/orca-targeting-mining/3591/3?u=viir
        launchDronesAndSendThemToMine context.readingFromGameClient
            |> Maybe.withDefault (describeBranch "Drones already busy" waitForProgressInGame)


targetAsteroid : BotDecisionContext -> DecisionPathNode
targetAsteroid context =
    case context.readingFromGameClient |> topmostAsteroidFromOverviewWindow of
        Nothing ->
            describeBranch "I see no asteroid in the overview." waitForProgressInGame

        Just asteroidInOverview ->
            describeBranch ("Choosing asteroid '" ++ (asteroidInOverview.objectName |> Maybe.withDefault "Nothing") ++ "'")
                (lockTargetFromOverviewEntry asteroidInOverview context.readingFromGameClient)


lockTargetFromOverviewEntry : OverviewWindowEntry -> ReadingFromGameClient -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry readingFromGameClient =
    describeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
        (useContextMenuCascadeOnOverviewEntry
            (useMenuEntryWithTextEqual "Lock target" menuCascadeCompleted)
            overviewEntry
            readingFromGameClient
        )


launchDronesAndSendThemToMine : ReadingFromGameClient -> Maybe DecisionPathNode
launchDronesAndSendThemToMine readingFromGameClient =
    readingFromGameClient.dronesWindow
        |> Maybe.andThen
            (\dronesWindow ->
                case ( dronesWindow.droneGroupInBay, dronesWindow.droneGroupInLocalSpace ) of
                    ( Just droneGroupInBay, Just droneGroupInLocalSpace ) ->
                        let
                            idlingDrones =
                                droneGroupInLocalSpace.drones
                                    |> List.filter (.uiNode >> .uiNode >> EveOnline.ParseUserInterface.getAllContainedDisplayTexts >> List.any (String.toLower >> String.contains "idle"))

                            dronesInBayQuantity =
                                droneGroupInBay.header.quantityFromTitle |> Maybe.withDefault 0

                            dronesInLocalSpaceQuantity =
                                droneGroupInLocalSpace.header.quantityFromTitle |> Maybe.withDefault 0
                        in
                        if 0 < (idlingDrones |> List.length) then
                            Just
                                (describeBranch "Send idling drone(s)"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                        (useMenuEntryWithTextContaining "mine" menuCascadeCompleted)
                                        readingFromGameClient
                                    )
                                )

                        else if 0 < dronesInBayQuantity && dronesInLocalSpaceQuantity < 5 then
                            Just
                                (describeBranch "Launch drones"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInBay.header.uiNode )
                                        (useMenuEntryWithTextContaining "Launch drone" menuCascadeCompleted)
                                        readingFromGameClient
                                    )
                                )

                        else
                            Nothing

                    _ ->
                        Nothing
            )


topmostAsteroidFromOverviewWindow : ReadingFromGameClient -> Maybe OverviewWindowEntry
topmostAsteroidFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


overviewWindowEntriesRepresentingAsteroids : ReadingFromGameClient -> List OverviewWindowEntry
overviewWindowEntriesRepresentingAsteroids =
    .overviewWindow
        >> Maybe.map (.entries >> List.filter overviewWindowEntryRepresentsAnAsteroid)
        >> Maybe.withDefault []


overviewWindowEntryRepresentsAnAsteroid : OverviewWindowEntry -> Bool
overviewWindowEntryRepresentsAnAsteroid entry =
    (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "asteroid"))
        && (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "belt") |> not)


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


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> StateMemoryAndDecisionTree
    -> ( StateMemoryAndDecisionTree, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
        , decisionTreeRoot = annar_731_orca_mining_BotDecisionRoot
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

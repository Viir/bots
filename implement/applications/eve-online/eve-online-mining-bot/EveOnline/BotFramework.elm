module EveOnline.BotFramework exposing (..)

{-| A framework to build EVE Online bots and intel tools.
Features:

  - Read from the game client using Sanderling memory reading and parse the user interface from the memory reading (<https://github.com/Arcitectus/Sanderling>).
  - Play sounds.
  - Send mouse and keyboard input to the game client.
  - Parse the bot-settings and inform the user about the result.

The framework automatically selects an EVE Online client process and finishes the session when that process disappears.
When multiple game clients are open, the framework prioritizes the one with the topmost window. This approach helps users control which game client is picked by an app.
To use the framework, import this module and use the `initState` and `processEvent` functions.

To learn more about developing for EVE Online, see the guide at <https://to.botlab.org/guide/developing-for-eve-online>

-}

import Array
import Bitwise
import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import Common.Basics
import Common.EffectOnWindow
import Common.FNV
import CompilationInterface.SourceFiles
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface exposing (DisplayRegion, centerFromDisplayRegion, getAllContainedDisplayTextsWithRegion)
import EveOnline.VolatileProcessInterface as VolatileProcessInterface
import Json.Decode
import Json.Encode
import List.Extra
import Maybe.Extra
import Result.Extra
import String.Extra


type alias BotConfiguration botSettings botState =
    { parseBotSettings : String -> Result String botSettings
    , selectGameClientInstance : Maybe botSettings -> List GameClientProcessSummary -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
    , processEvent : BotEventContext botSettings -> BotEvent -> botState -> ( botState, BotEventResponse )
    }


type BotEvent
    = ReadingFromGameClientCompleted EveOnline.ParseUserInterface.ParsedUserInterface ReadingFromGameClientScreenshot


type BotEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession { statusText : String }


type InternalBotEventResponse
    = InternalContinueSession InternalContinueSessionStructure
    | InternalFinishSession { statusText : String }


type alias InternalContinueSessionStructure =
    { statusText : String
    , startTasks : List { areaId : String, taskType : Maybe TaskType, task : InterfaceToHost.Task }
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type TaskType
    = StartsReadingTaskType
    | SetupTaskType { description : String }


type alias ContinueSessionStructure =
    { effects : List Common.EffectOnWindow.EffectOnWindowStructure
    , millisecondsToNextReadingFromGame : Int
    , statusText : String
    }


type alias Rect2dStructure =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


type alias BotEventContext botSettings =
    { timeInMilliseconds : Int
    , botSettings : botSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias StateIncludingFramework botSettings botState =
    { setup : SetupState
    , botState : BotAndLastEventState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , waitingForSetupTasks : List { taskId : String, description : String }
    , botSettings : Maybe botSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotAndLastEventState botState =
    { botState : botState
    , lastEvent :
        Maybe
            { timeInMilliseconds : Int
            , eventResult : ( botState, BotEventResponse )
            }
    }


type alias SetupState =
    { createVolatileProcessResult : Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , requestsToVolatileProcessCount : Int
    , lastRequestToVolatileProcessResult : Maybe (Result String ( InterfaceToHost.RequestToVolatileProcessComplete, Result String VolatileProcessInterface.ResponseFromVolatileHost ))
    , gameClientProcesses : Maybe (List GameClientProcessSummary)
    , searchUIRootAddressResult : Maybe VolatileProcessInterface.SearchUIRootAddressResultStructure
    , lastReadingFromGame : Maybe { timeInMilliseconds : Int, stage : ReadingFromGameState }
    , lastEffectFailedToAcquireInputFocus : Maybe String
    }


type ReadingFromGameState
    = ReadingFromGameInProgress ReadingFromGameClientAggregateState
    | ReadingFromGameCompleted


type alias ReadingFromGameClientAggregateState =
    { memoryReading : Maybe VolatileProcessInterface.ReadFromWindowResultStructure
    , readingFromWindow : Maybe InterfaceToHost.ReadFromWindowCompleteStruct
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot OperateBotConfiguration
    | FrameworkStopSession String


type alias OperateBotConfiguration =
    { buildTaskFromEffectSequence : List Common.EffectOnWindow.EffectOnWindowStructure -> InterfaceToHost.Task
    , readFromWindowTasks : List InterfaceToHost.Task
    , releaseVolatileProcessTask : InterfaceToHost.Task
    }


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias GameClientProcessSummary =
    VolatileProcessInterface.GameClientProcessSummaryStruct


type alias ShipModulesMemory =
    { tooltipFromModuleButton : Dict.Dict String ModuleButtonTooltipMemory
    , previousReadingTooltip : Maybe ModuleButtonTooltipMemory
    }


type alias ReadingFromGameClientMemory =
    { contextMenus : List ContextMenu
    }


type alias ModuleButtonTooltipMemory =
    { uiNode : UITreeNodeWithDisplayRegion
    , shortcut : Maybe { text : String, parseResult : Result String (List Common.EffectOnWindow.VirtualKeyCode) }
    , optimalRange : Maybe { asString : String, inMeters : Result String Int }
    , allContainedDisplayTextsWithRegion : List ( String, UITreeNodeWithDisplayRegion )
    }


type alias ContextMenu =
    { uiNode : UITreeNodeWithDisplayRegion
    , entries : List ContextMenuEntry
    }


type alias ContextMenuEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , text : String
    }


type alias UITreeNodeWithDisplayRegion =
    { uiNode : { pythonObjectAddress : String }
    , totalDisplayRegion : EveOnline.ParseUserInterface.DisplayRegion
    }


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


type alias ReadingFromGameClientScreenshot =
    { pixels_1x1 : ( Int, Int ) -> Maybe PixelValueRGB
    , pixels_2x2 : ( Int, Int ) -> Maybe PixelValueRGB
    }


type alias PixelValueRGB =
    { red : Int, green : Int, blue : Int }


type alias ReadingFromGameClientStructure =
    { parsedMemoryReading : EveOnline.ParseUserInterface.ParsedUserInterface
    , readingFromWindow : InterfaceToHost.ReadFromWindowCompleteStruct
    }


type alias ImageCrop =
    { offset : InterfaceToHost.WinApiPointStruct
    , widthPixels : Int
    , pixels : Array.Array Int
    }


effectSequenceSpacingMilliseconds : Int
effectSequenceSpacingMilliseconds =
    30


volatileProcessRecycleInterval : Int
volatileProcessRecycleInterval =
    400


getImageDataFromReadingRequestLimit : Int
getImageDataFromReadingRequestLimit =
    3


initShipModulesMemory : ShipModulesMemory
initShipModulesMemory =
    { tooltipFromModuleButton = Dict.empty
    , previousReadingTooltip = Nothing
    }


integrateCurrentReadingsIntoShipModulesMemory : EveOnline.ParseUserInterface.ParsedUserInterface -> ShipModulesMemory -> ShipModulesMemory
integrateCurrentReadingsIntoShipModulesMemory currentReading memoryBefore =
    let
        currentTooltipMemory =
            currentReading.moduleButtonTooltip
                |> Maybe.map asModuleButtonTooltipMemory

        getTooltipDataForEqualityComparison tooltip =
            tooltip.allContainedDisplayTextsWithRegion
                |> List.map (Tuple.mapSecond .totalDisplayRegion)

        {- To ensure robustness, we store a new tooltip only when the display texts match in two readings from the game client. -}
        tooltipAvailableToStore =
            case ( memoryBefore.previousReadingTooltip, currentTooltipMemory ) of
                ( Just previousTooltip, Just currentTooltip ) ->
                    if getTooltipDataForEqualityComparison previousTooltip == getTooltipDataForEqualityComparison currentTooltip then
                        Just currentTooltip

                    else
                        Nothing

                _ ->
                    Nothing

        visibleModuleButtons =
            currentReading.shipUI
                |> Maybe.map .moduleButtons
                |> Maybe.withDefault []

        visibleModuleButtonsIds =
            visibleModuleButtons |> List.map getModuleButtonIdentifierInMemory

        maybeModuleButtonWithHighlight =
            visibleModuleButtons
                |> List.filter .isHiliteVisible
                |> List.head

        tooltipFromModuleButtonAddition =
            case ( tooltipAvailableToStore, maybeModuleButtonWithHighlight ) of
                ( Just tooltip, Just moduleButtonWithHighlight ) ->
                    Dict.insert (moduleButtonWithHighlight |> getModuleButtonIdentifierInMemory) tooltip

                _ ->
                    identity

        tooltipFromModuleButton =
            memoryBefore.tooltipFromModuleButton
                |> tooltipFromModuleButtonAddition
                |> Dict.filter (\moduleButtonId _ -> visibleModuleButtonsIds |> List.member moduleButtonId)
    in
    { tooltipFromModuleButton = tooltipFromModuleButton
    , previousReadingTooltip =
        currentTooltipMemory
            |> Maybe.Extra.orElse memoryBefore.previousReadingTooltip
    }


getModuleButtonTooltipFromModuleButton : ShipModulesMemory -> EveOnline.ParseUserInterface.ShipUIModuleButton -> Maybe ModuleButtonTooltipMemory
getModuleButtonTooltipFromModuleButton moduleMemory moduleButton =
    moduleMemory.tooltipFromModuleButton |> Dict.get (moduleButton |> getModuleButtonIdentifierInMemory)


getModuleButtonIdentifierInMemory : EveOnline.ParseUserInterface.ShipUIModuleButton -> String
getModuleButtonIdentifierInMemory =
    .uiNode >> .uiNode >> .pythonObjectAddress


initSetup : SetupState
initSetup =
    { createVolatileProcessResult = Nothing
    , requestsToVolatileProcessCount = 0
    , lastRequestToVolatileProcessResult = Nothing
    , gameClientProcesses = Nothing
    , searchUIRootAddressResult = Nothing
    , lastReadingFromGame = Nothing
    , lastEffectFailedToAcquireInputFocus = Nothing
    }


initState : botState -> StateIncludingFramework botSettings botState
initState botState =
    { setup = initSetup
    , botState =
        { botState = botState
        , lastEvent = Nothing
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , waitingForSetupTasks = []
    , botSettings = Nothing
    , sessionTimeLimitInMilliseconds = Nothing
    }


processEvent :
    BotConfiguration botSettings botState
    -> InterfaceToHost.BotEvent
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InterfaceToHost.BotEventResponse )
processEvent botConfiguration fromHostEvent stateBefore =
    let
        ( state, response ) =
            processEventLessMappingTasks botConfiguration fromHostEvent stateBefore
    in
    case response of
        InternalFinishSession finishSession ->
            ( state, InterfaceToHost.FinishSession finishSession )

        InternalContinueSession continueSession ->
            let
                startTasksWithOrigin =
                    continueSession.startTasks
                        |> List.indexedMap
                            (\startTaskIndex startTask ->
                                let
                                    taskIdString =
                                        startTask.areaId ++ "-" ++ String.fromInt (state.lastTaskIndex + startTaskIndex)
                                in
                                { taskId = taskIdString
                                , task = startTask.task
                                , taskType = startTask.taskType
                                }
                            )

                startsReading =
                    List.any (.taskType >> (==) (Just StartsReadingTaskType)) continueSession.startTasks

                setupStateBefore =
                    state.setup

                setupState =
                    if startsReading then
                        { setupStateBefore
                            | lastReadingFromGame =
                                Just
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds
                                    , stage =
                                        ReadingFromGameInProgress
                                            { memoryReading = Nothing
                                            , readingFromWindow = Nothing
                                            }
                                    }
                        }

                    else
                        setupStateBefore

                waitingForSetupTasks =
                    (startTasksWithOrigin
                        |> List.filterMap
                            (\startTask ->
                                case startTask.taskType of
                                    Just (SetupTaskType setupTask) ->
                                        Just { taskId = startTask.taskId, description = setupTask.description }

                                    _ ->
                                        Nothing
                            )
                    )
                        ++ state.waitingForSetupTasks

                startTasks =
                    startTasksWithOrigin
                        |> List.map (\startTask -> { taskId = startTask.taskId, task = startTask.task })
            in
            ( { state
                | lastTaskIndex = state.lastTaskIndex + List.length startTasks
                , waitingForSetupTasks = waitingForSetupTasks
                , setup = setupState
              }
            , InterfaceToHost.ContinueSession
                { statusText = continueSession.statusText
                , startTasks = startTasks
                , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                }
            )


processEventLessMappingTasks :
    BotConfiguration botSettings botState
    -> InterfaceToHost.BotEvent
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventLessMappingTasks botConfiguration fromHostEvent stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = fromHostEvent.timeInMilliseconds }

        continueAfterIntegrateEvent =
            processEventAfterIntegrateEvent botConfiguration
    in
    case fromHostEvent.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            continueAfterIntegrateEvent stateBefore

        InterfaceToHost.TaskCompletedEvent taskComplete ->
            let
                waitingForSetupTasks =
                    stateBefore.waitingForSetupTasks
                        |> List.filter (.taskId >> (/=) taskComplete.taskId)

                setupState =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
            in
            continueAfterIntegrateEvent
                { stateBefore
                    | setup = setupState
                    , waitingForSetupTasks = waitingForSetupTasks
                }

        InterfaceToHost.BotSettingsChangedEvent botSettings ->
            case botConfiguration.parseBotSettings botSettings of
                Err parseSettingsError ->
                    ( stateBefore
                    , InternalFinishSession
                        { statusText = "Failed to parse these bot-settings: " ++ parseSettingsError }
                    )

                Ok parsedBotSettings ->
                    ( { stateBefore | botSettings = Just parsedBotSettings }
                    , InternalContinueSession
                        { statusText = "Succeeded parsing these bot-settings."
                        , startTasks = []
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = 0 }
                        }
                    )

        InterfaceToHost.SessionDurationPlannedEvent sessionTimeLimit ->
            continueAfterIntegrateEvent
                { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }


processEventAfterIntegrateEvent :
    BotConfiguration botSettings botState
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventAfterIntegrateEvent botConfiguration stateBefore =
    let
        ( stateBeforeCountingRequests, responseBeforeAddingStatusMessage ) =
            case stateBefore.botSettings of
                Nothing ->
                    ( stateBefore
                    , InternalFinishSession
                        { statusText =
                            "Unexpected order of events: I did not receive any bot-settings changed event."
                        }
                    )

                Just botSettings ->
                    processEventNotWaitingForTaskCompletion
                        botConfiguration
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , botSettings = botSettings
                        , sessionTimeLimitInMilliseconds = stateBefore.sessionTimeLimitInMilliseconds
                        }
                        stateBefore

        newRequestsToVolatileProcessCount =
            case responseBeforeAddingStatusMessage of
                InternalFinishSession _ ->
                    0

                InternalContinueSession continueSession ->
                    continueSession.startTasks
                        |> List.map
                            (\startTask ->
                                case startTask.task of
                                    InterfaceToHost.RequestToVolatileProcess _ ->
                                        1

                                    _ ->
                                        0
                            )
                        |> List.sum

        setupBeforeCountingRequests =
            stateBeforeCountingRequests.setup

        state =
            { stateBeforeCountingRequests
                | setup =
                    { setupBeforeCountingRequests
                        | requestsToVolatileProcessCount =
                            setupBeforeCountingRequests.requestsToVolatileProcessCount + newRequestsToVolatileProcessCount
                    }
            }

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        notifyWhenArrivedAtTimeUpperBound =
            stateBefore.timeInMilliseconds + 2000

        response =
            case responseBeforeAddingStatusMessage of
                InternalContinueSession continueSession ->
                    InternalContinueSession
                        { continueSession
                            | statusText = statusMessagePrefix ++ continueSession.statusText
                            , notifyWhenArrivedAtTime =
                                Just
                                    { timeInMilliseconds =
                                        continueSession.notifyWhenArrivedAtTime
                                            |> Maybe.map .timeInMilliseconds
                                            |> Maybe.withDefault notifyWhenArrivedAtTimeUpperBound
                                            |> min notifyWhenArrivedAtTimeUpperBound
                                    }
                        }

                InternalFinishSession finishSession ->
                    InternalFinishSession
                        { statusText = statusMessagePrefix ++ finishSession.statusText
                        }
    in
    ( state, response )


processEventNotWaitingForTaskCompletion :
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventNotWaitingForTaskCompletion botConfiguration botEventContext stateBefore =
    case stateBefore.setup |> getNextSetupTask botConfiguration stateBefore.botSettings of
        ContinueSetup setupState setupTask setupTaskDescription ->
            case List.head stateBefore.waitingForSetupTasks of
                Nothing ->
                    ( { stateBefore | setup = setupState }
                    , { startTasks =
                            [ { areaId = "setup"
                              , task = setupTask
                              , taskType = Just (SetupTaskType { description = setupTaskDescription })
                              }
                            ]
                      , statusText = "Continue setup: " ++ setupTaskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                      }
                        |> InternalContinueSession
                    )

                Just waitingForSetupTask ->
                    ( stateBefore
                    , { startTasks = []
                      , statusText = "Continue setup: Wait for completion: " ++ waitingForSetupTask.description
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                      }
                        |> InternalContinueSession
                    )

        OperateBot operateBot ->
            if volatileProcessRecycleInterval < stateBefore.setup.requestsToVolatileProcessCount then
                let
                    taskAreaIdString =
                        "maintain"

                    setupStateBefore =
                        stateBefore.setup

                    setupState =
                        { setupStateBefore | createVolatileProcessResult = Nothing }

                    setupTaskDescription =
                        "Recycle the volatile process after " ++ (setupStateBefore.requestsToVolatileProcessCount |> String.fromInt) ++ " requests."
                in
                ( { stateBefore | setup = setupState }
                , { startTasks =
                        [ { areaId = taskAreaIdString
                          , task = operateBot.releaseVolatileProcessTask
                          , taskType = Just (SetupTaskType { description = setupTaskDescription })
                          }
                        ]
                  , statusText = "Continue setup: " ++ setupTaskDescription
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                  }
                    |> InternalContinueSession
                )

            else
                operateBotExceptRenewingVolatileProcess
                    botConfiguration
                    botEventContext
                    stateBefore
                    operateBot

        FrameworkStopSession reason ->
            ( stateBefore
            , InternalFinishSession { statusText = "Stop session (" ++ reason ++ ")" }
            )


operateBotExceptRenewingVolatileProcess :
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> StateIncludingFramework botSettings botState
    -> OperateBotConfiguration
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
operateBotExceptRenewingVolatileProcess botConfiguration botEventContext stateBefore operateBot =
    let
        continueWithNamedTasksToWaitOn { startsReading, taskAreaId } tasks =
            ( stateBefore
            , { startTasks =
                    tasks
                        |> List.map
                            (\task ->
                                { areaId = taskAreaId
                                , taskType =
                                    if startsReading then
                                        Just StartsReadingTaskType

                                    else
                                        Nothing
                                , task = task
                                }
                            )
              , statusText = "Operate bot"
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InternalContinueSession
            )

        maybeReadingFromGameClient =
            case stateBefore.setup.lastReadingFromGame of
                Nothing ->
                    Nothing

                Just lastReadingFromGame ->
                    case lastReadingFromGame.stage of
                        ReadingFromGameCompleted ->
                            Nothing

                        ReadingFromGameInProgress aggregate ->
                            aggregate
                                |> parseReadingFromGameClient
                                |> Result.toMaybe

        continueWithReadingFromGameClient =
            continueWithNamedTasksToWaitOn
                { startsReading = True
                , taskAreaId = "read-from-game"
                }
                operateBot.readFromWindowTasks
    in
    case maybeReadingFromGameClient of
        Just readingFromGameClient ->
            let
                clientRectOffset =
                    readingFromGameClient.readingFromWindow.clientRectLeftUpperToScreen

                pixelFromCropsInClientArea binningFactor crops ( pixelX, pixelY ) =
                    pixelFromCrops crops
                        ( pixelX + (clientRectOffset.x // binningFactor)
                        , pixelY + (clientRectOffset.y // binningFactor)
                        )

                screenshotCrops_original =
                    readingFromGameClient.readingFromWindow.imageData.screenshotCrops_original
                        |> List.map parseImageCropFromInterface
                        |> List.filterMap Result.toMaybe

                screenshotCrops_binned_2x2 =
                    readingFromGameClient.readingFromWindow.imageData.screenshotCrops_binned_2x2
                        |> List.map parseImageCropFromInterface
                        |> List.filterMap Result.toMaybe

                screenshot =
                    { pixels_1x1 = screenshotCrops_original |> pixelFromCropsInClientArea 1
                    , pixels_2x2 = screenshotCrops_binned_2x2 |> pixelFromCropsInClientArea 2
                    }

                ( parsedUserInterface, statusTextAdditionFromParseFromScreenshot ) =
                    case parseUserInterfaceFromScreenshot screenshot readingFromGameClient.parsedMemoryReading of
                        Ok parsed ->
                            ( parsed, [] )

                        Err parseErr ->
                            ( readingFromGameClient.parsedMemoryReading
                            , [ "Failed to parse user interface: " ++ parseErr ]
                            )

                botStateBefore =
                    stateBefore.botState

                botEvent =
                    ReadingFromGameClientCompleted parsedUserInterface screenshot

                ( newBotState, botEventResponse ) =
                    botStateBefore.botState
                        |> botConfiguration.processEvent botEventContext botEvent

                lastEvent =
                    { timeInMilliseconds = stateBefore.timeInMilliseconds
                    , eventResult = ( newBotState, botEventResponse )
                    }

                sharedStatusTextAddition =
                    statusTextAdditionFromParseFromScreenshot

                response =
                    case botEventResponse of
                        FinishSession _ ->
                            InternalFinishSession
                                { statusText =
                                    "The bot finished the session."
                                        :: sharedStatusTextAddition
                                        |> String.join "\n"
                                }

                        ContinueSession continueSession ->
                            let
                                timeForNextReadingFromGame =
                                    stateBefore.timeInMilliseconds
                                        + continueSession.millisecondsToNextReadingFromGame

                                startTasks =
                                    case continueSession.effects of
                                        [] ->
                                            []

                                        effects ->
                                            [ { areaId = "send-effects"
                                              , taskType = Nothing
                                              , task = operateBot.buildTaskFromEffectSequence effects
                                              }
                                            ]
                            in
                            { startTasks = startTasks
                            , statusText =
                                "Operate bot"
                                    :: sharedStatusTextAddition
                                    |> String.join "\n"
                            , notifyWhenArrivedAtTime =
                                if startTasks == [] then
                                    Just { timeInMilliseconds = timeForNextReadingFromGame }

                                else
                                    Nothing
                            }
                                |> InternalContinueSession

                setupStateBefore =
                    stateBefore.setup

                setup =
                    { setupStateBefore
                        | lastReadingFromGame =
                            setupStateBefore.lastReadingFromGame
                                |> Maybe.map
                                    (\lastReadingFromGame ->
                                        { lastReadingFromGame | stage = ReadingFromGameCompleted }
                                    )
                    }

                state =
                    { stateBefore
                        | botState =
                            { botStateBefore
                                | botState = newBotState
                                , lastEvent = Just lastEvent
                            }
                        , setup = setup
                    }
            in
            ( state, response )

        Nothing ->
            let
                timeForNextReadingFromGameGeneral =
                    (stateBefore.setup.lastReadingFromGame
                        |> Maybe.map .timeInMilliseconds
                        |> Maybe.withDefault 0
                    )
                        + 5000

                timeForNextReadingFromGameFromBot =
                    stateBefore.botState.lastEvent
                        |> Maybe.andThen
                            (\botLastEvent ->
                                case botLastEvent.eventResult |> Tuple.second of
                                    ContinueSession continueSessionResponse ->
                                        Just
                                            (botLastEvent.timeInMilliseconds
                                                + continueSessionResponse.millisecondsToNextReadingFromGame
                                            )

                                    FinishSession _ ->
                                        Nothing
                            )
                        |> Maybe.withDefault 0

                nextReadingLowerBoundByLast =
                    case stateBefore.setup.lastReadingFromGame of
                        Nothing ->
                            0

                        Just startedReading ->
                            let
                                lastReadingCompleted =
                                    case stateBefore.setup.lastReadingFromGame of
                                        Nothing ->
                                            False

                                        Just lastReadingFromGame ->
                                            startedReading.timeInMilliseconds < lastReadingFromGame.timeInMilliseconds
                            in
                            if lastReadingCompleted then
                                0

                            else
                                startedReading.timeInMilliseconds + 3000

                timeForNextReadingFromGame =
                    timeForNextReadingFromGameFromBot
                        |> min timeForNextReadingFromGameGeneral
                        |> max nextReadingLowerBoundByLast

                remainingTimeToNextReadingFromGame =
                    timeForNextReadingFromGame - stateBefore.timeInMilliseconds
            in
            if remainingTimeToNextReadingFromGame <= 0 then
                continueWithReadingFromGameClient

            else
                ( stateBefore
                , { startTasks = []
                  , statusText = "Operate bot."
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = timeForNextReadingFromGame }
                  }
                    |> InternalContinueSession
                )


pixelFromCrops : List ImageCrop -> ( Int, Int ) -> Maybe PixelValueRGB
pixelFromCrops crops ( pixelX, pixelY ) =
    crops
        |> List.Extra.findMap
            (\imageCrop ->
                let
                    inCropX =
                        pixelX - imageCrop.offset.x

                    inCropY =
                        pixelY - imageCrop.offset.y
                in
                if inCropX < 0 || inCropY < 0 || imageCrop.widthPixels <= inCropX then
                    Nothing

                else
                    Array.get (inCropY * imageCrop.widthPixels + inCropX) imageCrop.pixels
                        |> Maybe.map colorFromInt_R8G8B8
            )


parseImageCropFromInterface : InterfaceToHost.ImageCrop -> Result String ImageCrop
parseImageCropFromInterface imageCrop =
    imageCrop.pixelsString
        |> parseImageCropPixelsArrayFromPixelsString
        |> Result.map
            (\pixels ->
                { offset = imageCrop.offset
                , widthPixels = imageCrop.widthPixels
                , pixels = pixels
                }
            )


parseImageCropPixelsArrayFromPixelsString : String -> Result String (Array.Array Int)
parseImageCropPixelsArrayFromPixelsString =
    Json.Decode.decodeString
        (Json.Decode.array Json.Decode.int)
        >> Result.mapError Json.Decode.errorToString


integrateTaskResult :
    ( Int, InterfaceToHost.TaskResultStructure )
    -> SetupState
    -> SetupState
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResult ->
            { setupStateBefore
                | createVolatileProcessResult = Just createVolatileProcessResult
                , requestsToVolatileProcessCount = 0
            }

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.ProcessNotFound) ->
            { setupStateBefore | createVolatileProcessResult = Nothing }

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.FailedToAcquireInputFocus) ->
            { setupStateBefore | lastEffectFailedToAcquireInputFocus = Just "Failed before entering volatile process." }

        InterfaceToHost.RequestToVolatileProcessResponse (Ok requestResult) ->
            let
                requestToVolatileProcessResult =
                    case requestResult.exceptionToString of
                        Just exception ->
                            Err ("Exception from volatile process: " ++ exception)

                        Nothing ->
                            let
                                decodeResponseResult =
                                    case requestResult.returnValueToString of
                                        Nothing ->
                                            Err "Unexpected response: return value is empty"

                                        Just returnValueToString ->
                                            returnValueToString
                                                |> VolatileProcessInterface.deserializeResponseFromVolatileHost
                                                |> Result.mapError Json.Decode.errorToString
                            in
                            Ok ( requestResult, decodeResponseResult )

                setupStateWithScriptRunResult =
                    { setupStateBefore | lastRequestToVolatileProcessResult = Just requestToVolatileProcessResult }
            in
            case requestToVolatileProcessResult |> Result.andThen Tuple.second |> Result.toMaybe of
                Nothing ->
                    setupStateWithScriptRunResult

                Just responseFromVolatileProcessOk ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileProcess responseFromVolatileProcessOk

        InterfaceToHost.OpenWindowResponse _ ->
            setupStateBefore

        InterfaceToHost.InvokeMethodOnWindowResponse _ methodOnWindowResult ->
            case methodOnWindowResult of
                Ok (InterfaceToHost.ReadFromWindowMethodResult readFromWindowComplete) ->
                    setupStateBefore
                        |> integrateReadFromWindowComplete
                            { readFromWindowComplete = readFromWindowComplete
                            }

                _ ->
                    setupStateBefore

        InterfaceToHost.RandomBytesResponse _ ->
            setupStateBefore

        InterfaceToHost.CompleteWithoutResult ->
            setupStateBefore


integrateResponseFromVolatileProcess :
    VolatileProcessInterface.ResponseFromVolatileHost
    -> SetupState
    -> SetupState
integrateResponseFromVolatileProcess responseFromVolatileProcess stateBefore =
    case responseFromVolatileProcess of
        VolatileProcessInterface.ListGameClientProcessesResponse gameClientProcesses ->
            { stateBefore | gameClientProcesses = Just gameClientProcesses }

        VolatileProcessInterface.SearchUIRootAddressResult searchUIRootAddressResult ->
            let
                state =
                    { stateBefore | searchUIRootAddressResult = Just searchUIRootAddressResult }
            in
            state

        VolatileProcessInterface.ReadFromWindowResult readFromWindowResult ->
            case stateBefore.lastReadingFromGame of
                Nothing ->
                    stateBefore

                Just lastReadingFromGame ->
                    case lastReadingFromGame.stage of
                        ReadingFromGameCompleted ->
                            stateBefore

                        ReadingFromGameInProgress inProgress ->
                            let
                                readingFromGameStage =
                                    { inProgress
                                        | memoryReading = Just readFromWindowResult
                                    }

                                state =
                                    { stateBefore
                                        | lastReadingFromGame =
                                            Just
                                                { lastReadingFromGame
                                                    | stage = ReadingFromGameInProgress readingFromGameStage
                                                }
                                    }
                            in
                            state

        VolatileProcessInterface.FailedToBringWindowToFront error ->
            { stateBefore | lastEffectFailedToAcquireInputFocus = Just error }

        VolatileProcessInterface.CompletedEffectSequenceOnWindow ->
            { stateBefore | lastEffectFailedToAcquireInputFocus = Nothing }


integrateReadFromWindowComplete :
    { readFromWindowComplete : InterfaceToHost.ReadFromWindowCompleteStruct }
    -> SetupState
    -> SetupState
integrateReadFromWindowComplete { readFromWindowComplete } stateBefore =
    case stateBefore.lastReadingFromGame of
        Nothing ->
            stateBefore

        Just lastReadingFromGame ->
            case lastReadingFromGame.stage of
                ReadingFromGameCompleted ->
                    stateBefore

                ReadingFromGameInProgress aggregateBefore ->
                    let
                        aggregate =
                            { aggregateBefore | readingFromWindow = Just readFromWindowComplete }
                    in
                    { stateBefore
                        | lastReadingFromGame = Just { lastReadingFromGame | stage = ReadingFromGameInProgress aggregate }
                    }


colorFromInt_R8G8B8 : Int -> PixelValueRGB
colorFromInt_R8G8B8 combined =
    { red = combined |> Bitwise.shiftRightZfBy 16 |> Bitwise.and 0xFF
    , green = combined |> Bitwise.shiftRightZfBy 8 |> Bitwise.and 0xFF
    , blue = combined |> Bitwise.and 0xFF
    }


parseReadingFromGameClient :
    ReadingFromGameClientAggregateState
    -> Result String ReadingFromGameClientStructure
parseReadingFromGameClient readingAggregate =
    case readingAggregate.memoryReading of
        Nothing ->
            Err "Memory reading not completed"

        Just memoryReading ->
            case memoryReading of
                VolatileProcessInterface.ProcessNotFound ->
                    Err "Initial reading failed with 'Process Not Found'"

                VolatileProcessInterface.Completed completedReading ->
                    case completedReading.memoryReadingSerialRepresentationJson of
                        Nothing ->
                            Err "Missing json representation of memory reading"

                        Just memoryReadingSerialRepresentationJson ->
                            case readingAggregate.readingFromWindow of
                                Nothing ->
                                    Err "Reading from window not arrived yet"

                                Just readingFromWindow ->
                                    memoryReadingSerialRepresentationJson
                                        |> EveOnline.MemoryReading.decodeMemoryReadingFromString
                                        |> Result.mapError Json.Decode.errorToString
                                        |> Result.map (EveOnline.ParseUserInterface.parseUITreeWithDisplayRegionFromUITree >> EveOnline.ParseUserInterface.parseUserInterfaceFromUITree)
                                        |> Result.map
                                            (\parsedMemoryReading ->
                                                { parsedMemoryReading = parsedMemoryReading
                                                , readingFromWindow = readingFromWindow
                                                }
                                            )


getNextSetupTask :
    BotConfiguration botSettings botState
    -> Maybe botSettings
    -> SetupState
    -> SetupTask
getNextSetupTask botConfiguration botSettings stateBefore =
    case stateBefore.createVolatileProcessResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileProcess
                    { programCode = CompilationInterface.SourceFiles.file____EveOnline_VolatileProcess_csx.utf8 }
                )
                "Setting up volatile process. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FrameworkStopSession ("Create volatile process failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileProcessComplete) ->
            getSetupTaskWhenVolatileProcessSetupCompleted
                botConfiguration
                botSettings
                stateBefore
                createVolatileProcessComplete.processId


getSetupTaskWhenVolatileProcessSetupCompleted :
    BotConfiguration botSettings appState
    -> Maybe botSettings
    -> SetupState
    -> String
    -> SetupTask
getSetupTaskWhenVolatileProcessSetupCompleted botConfiguration botSettings stateBefore volatileProcessId =
    case stateBefore.gameClientProcesses of
        Nothing ->
            ContinueSetup stateBefore
                (InterfaceToHost.RequestToVolatileProcess
                    (InterfaceToHost.RequestNotRequiringInputFocus
                        { processId = volatileProcessId
                        , request =
                            VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                VolatileProcessInterface.ListGameClientProcessesRequest
                        }
                    )
                )
                "Get list of EVE Online client processes."

        Just gameClientProcesses ->
            case gameClientProcesses |> botConfiguration.selectGameClientInstance botSettings of
                Err selectGameClientProcessError ->
                    FrameworkStopSession ("Failed to select the game client process: " ++ selectGameClientProcessError)

                Ok gameClientSelection ->
                    let
                        continueWithSearchUIRootAddress =
                            ContinueSetup stateBefore
                                (InterfaceToHost.RequestToVolatileProcess
                                    (InterfaceToHost.RequestNotRequiringInputFocus
                                        { processId = volatileProcessId
                                        , request =
                                            VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                                (VolatileProcessInterface.SearchUIRootAddress { processId = gameClientSelection.selectedProcess.processId })
                                        }
                                    )
                                )
                                ((("Search the address of the UI root in process "
                                    ++ (gameClientSelection.selectedProcess.processId |> String.fromInt)
                                  )
                                    :: gameClientSelection.report
                                 )
                                    |> String.join "\n"
                                )
                    in
                    case stateBefore.searchUIRootAddressResult of
                        Nothing ->
                            continueWithSearchUIRootAddress

                        Just searchResult ->
                            if searchResult.processId /= gameClientSelection.selectedProcess.processId then
                                continueWithSearchUIRootAddress

                            else
                                case searchResult.uiRootAddress of
                                    Nothing ->
                                        FrameworkStopSession
                                            ("Did not find the root of the UI tree in game client instance '"
                                                ++ gameClientSelection.selectedProcess.mainWindowTitle
                                                ++ "' (pid "
                                                ++ String.fromInt gameClientSelection.selectedProcess.processId
                                                ++ "). Maybe the selected game client had not yet completed its startup? TODO: Check if we can read memory of that process at all."
                                            )

                                    Just uiRootAddress ->
                                        let
                                            readFromWindowRequest =
                                                VolatileProcessInterface.ReadFromWindow
                                                    { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                    , uiRootAddress = uiRootAddress
                                                    }
                                        in
                                        let
                                            buildTaskFromRequestToVolatileProcess maybeAcquireInputFocus requestToVolatileProcess =
                                                let
                                                    requestBeforeConsideringInputFocus =
                                                        { processId = volatileProcessId
                                                        , request = VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost requestToVolatileProcess
                                                        }
                                                in
                                                InterfaceToHost.RequestToVolatileProcess
                                                    (case maybeAcquireInputFocus of
                                                        Nothing ->
                                                            InterfaceToHost.RequestNotRequiringInputFocus
                                                                requestBeforeConsideringInputFocus

                                                        Just acquireInputFocus ->
                                                            InterfaceToHost.RequestRequiringInputFocus
                                                                { request = requestBeforeConsideringInputFocus
                                                                , acquireInputFocus = acquireInputFocus
                                                                }
                                                    )

                                            buildTaskFromInvokeMethodOnWindowRequest methodOnWindow =
                                                InterfaceToHost.InvokeMethodOnWindowRequest
                                                    ("winapi-" ++ gameClientSelection.selectedProcess.mainWindowId)
                                                    methodOnWindow

                                            continueNormalOperation =
                                                OperateBot
                                                    { buildTaskFromEffectSequence =
                                                        \effectSequenceOnWindow ->
                                                            { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                            , task =
                                                                effectSequenceOnWindow
                                                                    |> List.map (effectOnWindowAsVolatileProcessEffectOnWindow >> VolatileProcessInterface.Effect)
                                                                    |> List.intersperse (VolatileProcessInterface.DelayMilliseconds effectSequenceSpacingMilliseconds)
                                                            , bringWindowToForeground = True
                                                            }
                                                                |> VolatileProcessInterface.EffectSequenceOnWindow
                                                                |> buildTaskFromRequestToVolatileProcess (Just { maximumDelayMilliseconds = 500 })
                                                    , readFromWindowTasks =
                                                        [ readFromWindowRequest
                                                            |> buildTaskFromRequestToVolatileProcess
                                                                (Just { maximumDelayMilliseconds = 500 })
                                                        , buildTaskFromInvokeMethodOnWindowRequest
                                                            InterfaceToHost.ReadFromWindowMethod
                                                        ]
                                                    , releaseVolatileProcessTask = InterfaceToHost.ReleaseVolatileProcess { processId = volatileProcessId }
                                                    }
                                        in
                                        case stateBefore.lastReadingFromGame of
                                            Nothing ->
                                                continueNormalOperation

                                            Just lastReadingFromGame ->
                                                case lastReadingFromGame.stage of
                                                    ReadingFromGameCompleted ->
                                                        continueNormalOperation

                                                    ReadingFromGameInProgress inProgress ->
                                                        case inProgress.memoryReading of
                                                            Nothing ->
                                                                continueNormalOperation

                                                            Just VolatileProcessInterface.ProcessNotFound ->
                                                                FrameworkStopSession "The EVE Online client process disappeared."

                                                            Just (VolatileProcessInterface.Completed _) ->
                                                                continueNormalOperation


effectOnWindowAsVolatileProcessEffectOnWindow : Common.EffectOnWindow.EffectOnWindowStructure -> VolatileProcessInterface.EffectOnWindowStructure
effectOnWindowAsVolatileProcessEffectOnWindow effectOnWindow =
    case effectOnWindow of
        Common.EffectOnWindow.MouseMoveTo mouseMoveTo ->
            VolatileProcessInterface.MouseMoveTo { location = mouseMoveTo }

        Common.EffectOnWindow.KeyDown key ->
            VolatileProcessInterface.KeyDown key

        Common.EffectOnWindow.KeyUp key ->
            VolatileProcessInterface.KeyUp key


selectGameClientInstanceWithTopmostWindow :
    List GameClientProcessSummary
    -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
selectGameClientInstanceWithTopmostWindow gameClientProcesses =
    case gameClientProcesses |> List.sortBy .mainWindowZIndex |> List.head of
        Nothing ->
            Err "I did not find an EVE Online client process."

        Just selectedProcess ->
            let
                report =
                    if [ selectedProcess ] == gameClientProcesses then
                        []

                    else
                        [ "I found "
                            ++ (gameClientProcesses |> List.length |> String.fromInt)
                            ++ " game client processes. I selected process "
                            ++ (selectedProcess.processId |> String.fromInt)
                            ++ " ('"
                            ++ selectedProcess.mainWindowTitle
                            ++ "') because its main window was the topmost."
                        ]
            in
            Ok { selectedProcess = selectedProcess, report = report }


selectGameClientInstanceWithPilotName :
    String
    -> List GameClientProcessSummary
    -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
selectGameClientInstanceWithPilotName pilotName gameClientProcesses =
    if gameClientProcesses |> List.isEmpty then
        Err "I did not find an EVE Online client process."

    else
        case
            gameClientProcesses
                |> List.filter (.mainWindowTitle >> Common.Basics.stringContainsIgnoringCase pilotName)
                |> List.head
        of
            Nothing ->
                Err
                    ("I did not find an EVE Online client process for the pilot name '"
                        ++ pilotName
                        ++ "'. Here is a list of window names of the visible game client instances: "
                        ++ (gameClientProcesses |> List.map (.mainWindowTitle >> String.Extra.surround "'") |> String.join ", ")
                    )

            Just selectedProcess ->
                let
                    report =
                        if [ selectedProcess ] == gameClientProcesses then
                            []

                        else
                            [ "I found "
                                ++ (gameClientProcesses |> List.length |> String.fromInt)
                                ++ " game client processes. I selected process "
                                ++ (selectedProcess.processId |> String.fromInt)
                                ++ " ('"
                                ++ selectedProcess.mainWindowTitle
                                ++ "') because its main window title matches the given pilot name."
                            ]
                in
                Ok { selectedProcess = selectedProcess, report = report }


requestToVolatileProcessResultDisplayString :
    Result String ( InterfaceToHost.RequestToVolatileProcessComplete, Result String VolatileProcessInterface.ResponseFromVolatileHost )
    -> Result String String
requestToVolatileProcessResultDisplayString =
    Result.andThen
        (\( runInVolatileProcessComplete, decodeResult ) ->
            let
                describeReturnValue =
                    runInVolatileProcessComplete.returnValueToString
                        |> Maybe.withDefault "null"
            in
            case decodeResult of
                Ok _ ->
                    Ok describeReturnValue

                Err decodeError ->
                    Err
                        ("Failed to decode response from volatile process: " ++ decodeError ++ " (" ++ describeReturnValue ++ ")")
        )


statusReportFromState : StateIncludingFramework botSettings s -> String
statusReportFromState state =
    let
        fromBot =
            state.botState.lastEvent
                |> Maybe.map
                    (\lastEvent ->
                        case lastEvent.eventResult |> Tuple.second of
                            FinishSession finishSession ->
                                finishSession.statusText

                            ContinueSession continueSession ->
                                continueSession.statusText
                    )
                |> Maybe.withDefault ""

        inputFocusLines =
            case state.setup.lastEffectFailedToAcquireInputFocus of
                Nothing ->
                    []

                Just error ->
                    [ "Failed to acquire input focus: " ++ error ]

        describeLastReadingFromGame =
            case state.setup.lastReadingFromGame of
                Nothing ->
                    "None so far"

                Just lastReadingFromGame ->
                    case lastReadingFromGame.stage of
                        ReadingFromGameInProgress _ ->
                            "in progress"

                        ReadingFromGameCompleted ->
                            "completed"
    in
    [ [ fromBot ]
    , [ "----"
      , "EVE Online framework status:"
      ]
    , [ "Last reading from game client: " ++ describeLastReadingFromGame ]
    , inputFocusLines
    ]
        |> List.concat
        |> String.join "\n"


{-| This works only while the context menu model does not support branching. In this special case, we can unpack the tree into a list.

With the switch to the new 'Photon UI' in the game client, the effects used to expand menu entries change: Before, the player used a click on the menu entry to expand its children, but now expanding it requires hovering the mouse over the menu entry.

-}
unpackContextMenuTreeToListOfActionsDependingOnReadings :
    UseContextMenuCascadeNode
    -> List (ReadingFromGameClient -> ( String, Maybe (List Common.EffectOnWindow.EffectOnWindowStructure) ))
unpackContextMenuTreeToListOfActionsDependingOnReadings treeNode =
    let
        actionFromChoice { isLastElement } ( describeChoice, chooseEntry ) =
            chooseEntry
                >> Maybe.map
                    (\menuEntry ->
                        let
                            useClick =
                                isLastElement
                                    || (String.toLower (String.trim menuEntry.text) == "dock")
                        in
                        if useClick then
                            ( "Click menu entry " ++ describeChoice ++ "."
                            , menuEntry.uiNode |> mouseClickOnUIElement Common.EffectOnWindow.MouseButtonLeft |> Just
                            )

                        else
                            ( "Hover menu entry " ++ describeChoice ++ "."
                            , menuEntry.uiNode |> mouseMoveToUIElement |> Just
                            )
                    )
                >> Maybe.withDefault
                    ( "Search menu entry " ++ describeChoice ++ "."
                    , Nothing
                    )

        listFromNextChoiceAndFollowingNodes nextChoice following =
            (nextChoice |> actionFromChoice { isLastElement = following == MenuCascadeCompleted })
                :: (following |> unpackContextMenuTreeToListOfActionsDependingOnReadings)
    in
    case treeNode of
        MenuCascadeCompleted ->
            []

        MenuEntryWithCustomChoice custom following ->
            listFromNextChoiceAndFollowingNodes
                ( "'" ++ custom.describeChoice ++ "'"
                , custom.chooseEntry
                )
                following


getEntropyIntFromReadingFromGameClient : EveOnline.ParseUserInterface.ParsedUserInterface -> Int
getEntropyIntFromReadingFromGameClient readingFromGameClient =
    let
        entropyFromString =
            Common.FNV.hashString

        entropyFromUiElement uiElement =
            [ uiElement.uiNode.pythonObjectAddress |> entropyFromString
            , uiElement.totalDisplayRegion.x
            , uiElement.totalDisplayRegion.y
            , uiElement.totalDisplayRegion.width
            , uiElement.totalDisplayRegion.height
            ]

        entropyFromOverviewEntry overviewEntry =
            (overviewEntry.cellsTexts |> Dict.values |> List.map entropyFromString)
                ++ (overviewEntry.uiNode |> entropyFromUiElement)

        entropyFromProbeScanResult probeScanResult =
            [ probeScanResult.uiNode |> entropyFromUiElement, probeScanResult.textsLeftToRight |> List.map entropyFromString ]
                |> List.concat

        fromMenus =
            readingFromGameClient.contextMenus
                |> List.concatMap (.entries >> List.map .uiNode)
                |> List.concatMap entropyFromUiElement

        fromOverview =
            readingFromGameClient.overviewWindow
                |> Maybe.map .entries
                |> Maybe.withDefault []
                |> List.concatMap entropyFromOverviewEntry

        fromProbeScanner =
            readingFromGameClient.probeScannerWindow
                |> Maybe.map .scanResults
                |> Maybe.withDefault []
                |> List.concatMap entropyFromProbeScanResult
    in
    (fromMenus ++ fromOverview ++ fromProbeScanner) |> List.sum


secondsToSessionEnd : BotEventContext a -> Maybe Int
secondsToSessionEnd botEventContext =
    botEventContext.sessionTimeLimitInMilliseconds
        |> Maybe.map (\sessionTimeLimitInMilliseconds -> (sessionTimeLimitInMilliseconds - botEventContext.timeInMilliseconds) // 1000)


mouseMoveToUIElement : UIElement -> List Common.EffectOnWindow.EffectOnWindowStructure
mouseMoveToUIElement uiElement =
    Common.EffectOnWindow.effectsMouseMoveToLocation
        (uiElement.totalDisplayRegionVisible |> centerFromDisplayRegion)


mouseClickOnUIElement : Common.EffectOnWindow.MouseButton -> UIElement -> List Common.EffectOnWindow.EffectOnWindowStructure
mouseClickOnUIElement mouseButton uiElement =
    Common.EffectOnWindow.effectsMouseClickAtLocation
        mouseButton
        (uiElement.totalDisplayRegionVisible |> centerFromDisplayRegion)


type UseContextMenuCascadeNode
    = MenuEntryWithCustomChoice { describeChoice : String, chooseEntry : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry } UseContextMenuCascadeNode
    | MenuCascadeCompleted


useMenuEntryWithTextContaining : String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextContaining textToSearch =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text containing '" ++ textToSearch ++ "'"
        , chooseEntry =
            List.filter (.text >> Common.Basics.stringContainsIgnoringCase textToSearch)
                >> List.sortBy (.text >> String.trim >> String.length)
                >> List.head
        }


useMenuEntryWithTextContainingFirstOf : List String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextContainingFirstOf priorities =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text containing first available of " ++ (priorities |> List.map (String.Extra.surround "'") |> String.join ", ")
        , chooseEntry =
            \menuEntries ->
                priorities
                    |> List.concatMap
                        (\textToSearch ->
                            menuEntries
                                |> List.filter (.text >> Common.Basics.stringContainsIgnoringCase textToSearch)
                                |> List.sortBy (.text >> String.trim >> String.length)
                        )
                    |> List.head
        }


useMenuEntryWithTextEqual : String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextEqual textToSearch =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text equal '" ++ textToSearch ++ "'"
        , chooseEntry =
            List.filter (.text >> String.trim >> String.toLower >> (==) (textToSearch |> String.toLower))
                >> List.head
        }


useMenuEntryInLastContextMenuInCascade :
    { describeChoice : String, chooseEntry : List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry }
    -> UseContextMenuCascadeNode
    -> UseContextMenuCascadeNode
useMenuEntryInLastContextMenuInCascade choice =
    MenuEntryWithCustomChoice
        { describeChoice = choice.describeChoice
        , chooseEntry = pickEntryFromLastContextMenuInCascade choice.chooseEntry
        }


useRandomMenuEntry : UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useRandomMenuEntry =
    MenuEntryWithCustomChoice
        { describeChoice = "random entry"
        , chooseEntry =
            \readingFromGameClient ->
                readingFromGameClient
                    |> pickEntryFromLastContextMenuInCascade
                        (Common.Basics.listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient readingFromGameClient))
        }


menuCascadeCompleted : UseContextMenuCascadeNode
menuCascadeCompleted =
    MenuCascadeCompleted


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromLocationInfoPanel : String -> EveOnline.ParseUserInterface.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


pickEntryFromLastContextMenuInCascade :
    (List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry)
    -> ReadingFromGameClient
    -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry
pickEntryFromLastContextMenuInCascade pickEntry =
    lastContextMenuOrSubmenu >> Maybe.map .entries >> Maybe.withDefault [] >> pickEntry


lastContextMenuOrSubmenu : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


infoPanelRouteFirstMarkerFromReadingFromGameClient : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromReadingFromGameClient =
    .infoPanelContainer
        >> Maybe.andThen .infoPanelRoute
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiNode.totalDisplayRegion.x + routeMarker.uiNode.totalDisplayRegion.y))
        >> Maybe.andThen List.head


localChatWindowFromUserInterface : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ChatWindow
localChatWindowFromUserInterface =
    .chatWindowStacks
        >> List.filterMap .chatWindow
        >> List.filter (.name >> Maybe.map (String.endsWith "_local") >> Maybe.withDefault False)
        >> List.head


shipUIIndicatesShipIsWarpingOrJumping : EveOnline.ParseUserInterface.ShipUI -> Bool
shipUIIndicatesShipIsWarpingOrJumping =
    .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map
            (\maneuverType ->
                [ EveOnline.ParseUserInterface.ManeuverWarp, EveOnline.ParseUserInterface.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


doEffectsClickModuleButton : EveOnline.ParseUserInterface.ShipUIModuleButton -> List Common.EffectOnWindow.EffectOnWindowStructure -> Bool
doEffectsClickModuleButton moduleButton =
    List.Extra.tails
        >> List.any
            (\effects ->
                case effects of
                    firstEffect :: secondEffect :: _ ->
                        case ( firstEffect, secondEffect ) of
                            ( Common.EffectOnWindow.MouseMoveTo mouseMoveTo, Common.EffectOnWindow.KeyDown keyDown ) ->
                                doesPointIntersectRegion mouseMoveTo moduleButton.uiNode.totalDisplayRegion
                                    && (keyDown == Common.EffectOnWindow.vkey_LBUTTON)

                            _ ->
                                False

                    [ _ ] ->
                        False

                    [] ->
                        False
            )


doesPointIntersectRegion : { x : Int, y : Int } -> EveOnline.ParseUserInterface.DisplayRegion -> Bool
doesPointIntersectRegion { x, y } region =
    (region.x <= x)
        && (x <= region.x + region.width)
        && (region.y <= y)
        && (y <= region.y + region.height)


cornersFromDisplayRegion : EveOnline.ParseUserInterface.DisplayRegion -> List { x : Int, y : Int }
cornersFromDisplayRegion region =
    [ { x = region.x, y = region.y }
    , { x = region.x + region.width, y = region.y }
    , { x = region.x, y = region.y + region.height }
    , { x = region.x + region.width, y = region.y + region.height }
    ]


growRegionOnAllSides : Int -> EveOnline.ParseUserInterface.DisplayRegion -> EveOnline.ParseUserInterface.DisplayRegion
growRegionOnAllSides growthAmount region =
    { x = region.x - growthAmount
    , y = region.y - growthAmount
    , width = region.width + growthAmount * 2
    , height = region.height + growthAmount * 2
    }


parseUserInterfaceFromScreenshot :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.ParsedUserInterface
    -> Result String EveOnline.ParseUserInterface.ParsedUserInterface
parseUserInterfaceFromScreenshot screenshot original =
    original.messageBoxes
        |> List.map (parseUserInterfaceFromScreenshotMessageBox screenshot)
        |> Result.Extra.combine
        |> Result.map (\messageBoxes -> { original | messageBoxes = messageBoxes })


parseUserInterfaceFromScreenshotMessageBox :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.MessageBox
    -> Result String EveOnline.ParseUserInterface.MessageBox
parseUserInterfaceFromScreenshotMessageBox screenshot messageBox =
    let
        colorSum color =
            color.red + color.green + color.blue

        colorDifferenceSum colorA colorB =
            [ colorA.red - colorB.red
            , colorA.green - colorB.green
            , colorA.blue - colorB.blue
            ]
                |> List.map abs
                |> List.sum

        {- Based on this sample:
           data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAUCAYAAACXtf2DAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsIAAA7CARUoSoAAAANWSURBVEhL1VVbb0xRFP7OHL3QzqheZjQtdUsZqhfNSAdhVKlrxJSIS0hFJEiQeJWI+AU8STzwIBGijRDSoiEpIcSgrom4PajeVAztGMwZa619zpnpqL77zux99uX71tpn773WaOXLG+IQxOkZHho9jI6WJmkozUj8RO2QmhBnCReDhFyow31l5W9T1rDNT9Iks8kBDdKTnjYKR/ftwv5tG+GvmIWDjZvhzMzAod07YJA4WcZ8/q1cOA97NjXg8N6dmODJR8PSADbU18JX5hUWw/6C8fm5ePT8JZpabsBDbV7NptX1OHXhInETxi2wE++0STh2+gzCAwMwYjEUe9woGDcW90JPbJbtQEGtTCY0Byq8pRiMRKhHz3BOeMjk83yFdzoi0ai0re2yHfyI/kKh241xOS7ZknjcwJHjJ7Bl7SqTMRR88D+iP1Fc6IEzKwuaQ8Pltlu01WmYMqHYZIkDdUe6P/fj2eu3NFmE9gch3Al1oLO3Dw+fvyIDY4ihbgVDWlQ1tbbBP6cS19vvIvx9AC/evMO5K9dQQFts8c1rSiumDq+abwN3eEUyGqcFUJufp63NoipfHpTdEV2MNNTiCRnTqEUNh0NtDtWKytBoUqMJTecPozadgzLOSPCGgPlszHwrG5a7f2j+KwxJFf+G2qTUVDEylEadBIHpUlhqyq1i1amQeaqG1yiIA3VbgICvGmvrFiLX5aR0UQbjdwy1NT5TkCzjOKHoz8vDuqWL4K8sgytrNLyTS1DkLkBpyUThMOxb5M7NwcypJXjz7gPmV88m0WxUzyxF3lgnXV1DOBZYwSW4LIDb90NY4vfBOToTMyZPxPZ1q9DV02NaTUoVmRnp+NTTiy/hb5Qm1P5tC67B2UtXxZqKlGTESZOBj93d+D4YgUExtCKwAKFnL9D/NaxWQJXtwDoUyw77eExRvFi2SDykwOQL4tJ7SZmgpqocOsUDa3gbbQddff2omuXF+pV16Or9LPZOnm/GYv9cM1UkwMbEIKWGA41b4crOliB739mJKzfbEaxfYrqnoLNTBbkzjJiEvprjVRgSzRz2/E5NFXw2nKZlqfTJPMaRzNB1nXuJQ2YCG3LQH49jFBcdOr8dRBSRyUsCpwTmCZ8M6tymt2gEwB+SX2kpOjZ/ywAAAABJRU5ErkJggg==
        -}
        matchesButtonTextOk buttonCenter =
            let
                colorFromRelativeLocation_binned ( fromCenterX, fromCenterY ) =
                    screenshot.pixels_2x2 ( buttonCenter.x // 2 + fromCenterX, buttonCenter.y // 2 + fromCenterY )
                        |> Maybe.withDefault { red = 0, green = 0, blue = 0 }

                ( darkestOffsetX, darkestOffsetY ) =
                    [ ( 0, 0 ), ( -1, 0 ), ( -2, 0 ), ( 0, 1 ), ( -1, 1 ), ( -2, 1 ) ]
                        |> List.sortBy (colorFromRelativeLocation_binned >> colorSum)
                        |> List.head
                        |> Maybe.withDefault ( 0, 0 )

                edgeThreshold =
                    20

                colorsAndEdges =
                    List.range -3 2
                        |> List.map
                            (\index ->
                                let
                                    leftColor =
                                        colorFromRelativeLocation_binned
                                            ( darkestOffsetX + index, darkestOffsetY )

                                    rightColor =
                                        colorFromRelativeLocation_binned
                                            ( darkestOffsetX + index + 1, darkestOffsetY )
                                in
                                ( leftColor
                                , ((colorSum rightColor - colorSum leftColor) // edgeThreshold)
                                    |> min 1
                                    |> max -1
                                )
                            )

                edges =
                    colorsAndEdges |> List.map Tuple.second
            in
            (List.drop 1 edges == [ 1, -1, 1, -1, 1 ])
                || (List.take 5 edges == [ 1, 1, -1, 1, 1 ])

        getTextFromButtonCenter buttonCenter =
            [ ( matchesButtonTextOk, "OK" )
            ]
                |> List.Extra.find (Tuple.first >> (|>) buttonCenter)
                |> Maybe.map Tuple.second
    in
    case messageBox.buttonGroup of
        Nothing ->
            Ok messageBox

        Just buttonGroup ->
            let
                measureButtonEdgesY =
                    buttonGroup.totalDisplayRegion.y + 6

                measureButtonEdgesLeft_2 =
                    buttonGroup.totalDisplayRegion.x // 2 - 1

                measureButtonEdgesRight_2 =
                    (measureButtonEdgesLeft_2 + buttonGroup.totalDisplayRegion.width // 2) + 1

                getEdgeLinePixel x =
                    screenshot.pixels_2x2 ( x, measureButtonEdgesY // 2 )
            in
            case
                List.range measureButtonEdgesLeft_2 measureButtonEdgesRight_2
                    |> List.map
                        (\x ->
                            case ( getEdgeLinePixel (x - 1), getEdgeLinePixel (x + 1) ) of
                                ( Just leftPixel, Just rightPixel ) ->
                                    Just (20 < colorDifferenceSum leftPixel rightPixel)

                                _ ->
                                    Nothing
                        )
                    |> Maybe.Extra.combine
            of
                Nothing ->
                    Err
                        ("Missing pixel data for button group at "
                            ++ String.fromInt
                                (buttonGroup.totalDisplayRegion.x + buttonGroup.totalDisplayRegion.width // 2)
                            ++ ","
                            ++ String.fromInt
                                (buttonGroup.totalDisplayRegion.y + buttonGroup.totalDisplayRegion.height // 2)
                        )

                Just buttonEdgesBools_2 ->
                    let
                        fromImageButtonsRegions =
                            buttonEdgesBools_2
                                |> centersOfTrueSequences
                                |> List.map ((+) measureButtonEdgesLeft_2)
                                |> pairsFromList
                                |> Tuple.first
                                |> List.map
                                    (\( left_binned, right_binned ) ->
                                        { x = left_binned * 2
                                        , y = buttonGroup.totalDisplayRegion.y
                                        , width = (right_binned - left_binned) * 2
                                        , height = buttonGroup.totalDisplayRegion.height
                                        }
                                    )

                        displayRegionOverlapsWithExistingButton displayRegion =
                            List.any
                                (.uiNode >> .totalDisplayRegion >> regionAddMarginOnEachSide -2 >> EveOnline.ParseUserInterface.regionsOverlap displayRegion)
                                messageBox.buttons

                        fromImageButtons :
                            List
                                { uiNode : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
                                , mainText : Maybe String
                                }
                        fromImageButtons =
                            fromImageButtonsRegions
                                |> List.filterMap
                                    (\fromImageButtonRegion ->
                                        if displayRegionOverlapsWithExistingButton fromImageButtonRegion then
                                            Nothing

                                        else
                                            let
                                                mainText =
                                                    fromImageButtonRegion
                                                        |> centerFromDisplayRegion
                                                        |> getTextFromButtonCenter
                                            in
                                            Just
                                                { uiNode =
                                                    { uiNode =
                                                        { originalJson = Json.Encode.null
                                                        , pythonObjectAddress = buttonGroup.uiNode.pythonObjectAddress ++ "-button"
                                                        , pythonObjectTypeName = "button-from-screenshot"
                                                        , dictEntriesOfInterest = Dict.empty
                                                        , children = Nothing
                                                        }
                                                    , totalDisplayRegion = fromImageButtonRegion
                                                    , totalDisplayRegionVisible = fromImageButtonRegion
                                                    , children = Nothing
                                                    , selfDisplayRegion = fromImageButtonRegion
                                                    }
                                                , mainText = mainText
                                                }
                                    )
                    in
                    Ok
                        { messageBox
                            | buttons = messageBox.buttons ++ fromImageButtons
                        }


centersOfTrueSequences : List Bool -> List Int
centersOfTrueSequences list =
    (list ++ [ False ])
        |> List.Extra.indexedFoldl
            (\index currentBool aggregate ->
                if currentBool then
                    if aggregate.trueStartIndex == Nothing then
                        { aggregate | trueStartIndex = Just index }

                    else
                        aggregate

                else
                    case aggregate.trueStartIndex of
                        Nothing ->
                            aggregate

                        Just trueStartIndex ->
                            { aggregate
                                | edges = aggregate.edges ++ [ (trueStartIndex + index) // 2 ]
                                , trueStartIndex = Nothing
                            }
            )
            { edges = [], trueStartIndex = Nothing }
        |> .edges


pairsFromList : List a -> ( List ( a, a ), Maybe a )
pairsFromList list =
    case list of
        [] ->
            ( [], Nothing )

        [ single ] ->
            ( [], Just single )

        first :: second :: remainder ->
            pairsFromList remainder |> Tuple.mapFirst ((::) ( first, second ))


regionAddMarginOnEachSide : Int -> DisplayRegion -> DisplayRegion
regionAddMarginOnEachSide marginSize originalRect =
    { x = originalRect.x - marginSize
    , y = originalRect.y - marginSize
    , width = originalRect.width + marginSize * 2
    , height = originalRect.height + marginSize * 2
    }


asReadingFromGameClientMemory : EveOnline.ParseUserInterface.ParsedUserInterface -> ReadingFromGameClientMemory
asReadingFromGameClientMemory reading =
    { contextMenus = reading.contextMenus |> List.map asContextMenuMemory }


asModuleButtonTooltipMemory : EveOnline.ParseUserInterface.ModuleButtonTooltip -> ModuleButtonTooltipMemory
asModuleButtonTooltipMemory tooltip =
    { uiNode = tooltip.uiNode |> asUITreeNodeWithDisplayRegionMemory
    , shortcut = tooltip.shortcut
    , optimalRange = tooltip.optimalRange
    , allContainedDisplayTextsWithRegion =
        tooltip.uiNode
            |> getAllContainedDisplayTextsWithRegion
            |> List.map (Tuple.mapSecond asUITreeNodeWithDisplayRegionMemory)
    }


asContextMenuMemory : EveOnline.ParseUserInterface.ContextMenu -> ContextMenu
asContextMenuMemory contextMenu =
    { uiNode = contextMenu.uiNode |> asUITreeNodeWithDisplayRegionMemory
    , entries = contextMenu.entries |> List.map asContextMenuEntryMemory
    }


asContextMenuEntryMemory : EveOnline.ParseUserInterface.ContextMenuEntry -> ContextMenuEntry
asContextMenuEntryMemory contextMenuEntry =
    { uiNode = contextMenuEntry.uiNode |> asUITreeNodeWithDisplayRegionMemory
    , text = contextMenuEntry.text
    }


asUITreeNodeWithDisplayRegionMemory : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion -> UITreeNodeWithDisplayRegion
asUITreeNodeWithDisplayRegionMemory node =
    { uiNode = { pythonObjectAddress = node.uiNode.pythonObjectAddress }
    , totalDisplayRegion = node.totalDisplayRegion
    }

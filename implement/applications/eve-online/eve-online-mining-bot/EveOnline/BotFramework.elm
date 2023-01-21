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

import Bitwise
import BotLab.BotInterface_To_Host_2023_01_17 as InterfaceToHost
import Common.Basics
import Common.EffectOnWindow
import Common.FNV
import CompilationInterface.SourceFiles
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface exposing (DisplayRegion, Location2d, centerFromDisplayRegion)
import EveOnline.VolatileProcessInterface as VolatileProcessInterface
import Json.Decode
import Json.Encode
import List.Extra
import String.Extra


type alias BotConfiguration botSettings botState =
    { parseBotSettings : String -> Result String botSettings
    , selectGameClientInstance : Maybe botSettings -> List GameClientProcessSummary -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
    , processEvent : BotEventContext botSettings -> BotEvent -> botState -> ( botState, BotEventResponse )
    }


type BotEvent
    = ReadingFromGameClientCompleted EveOnline.ParseUserInterface.ParsedUserInterface ReadingFromGameClientImage


type BotEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession { statusText : String }


type InternalBotEventResponse
    = InternalContinueSession InternalContinueSessionStructure
    | InternalFinishSession { statusText : String }


type alias InternalContinueSessionStructure =
    { statusText : String
    , startTasks : List { areaId : String, taskDescription : String, task : InterfaceToHost.Task }
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias ContinueSessionStructure =
    { effects : List Common.EffectOnWindow.EffectOnWindowStructure
    , millisecondsToNextReadingFromGame : Int
    , screenshotRegionsToRead : ReadingFromGameClient -> { rects1x1 : List Rect2dStructure }
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
    , tasksInProgress : Dict.Dict String { startTimeInMilliseconds : Int, taskDescription : String }
    , botSettings : Maybe botSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotAndLastEventState botState =
    { botState : botState
    , lastEvent : Maybe { timeInMilliseconds : Int, eventResult : ( botState, BotEventResponse ) }
    }


type alias SetupState =
    { createVolatileProcessResult : Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , requestsToVolatileProcessCount : Int
    , lastRequestToVolatileProcessResult : Maybe (Result String ( InterfaceToHost.RequestToVolatileProcessComplete, Result String VolatileProcessInterface.ResponseFromVolatileHost ))
    , gameClientProcesses : Maybe (List GameClientProcessSummary)
    , searchUIRootAddressResult : Maybe VolatileProcessInterface.SearchUIRootAddressResultStructure
    , lastReadingFromGame : Maybe { timeInMilliseconds : Int, aggregate : ReadingFromGameClientAggregateState }
    , lastEffectFailedToAcquireInputFocus : Maybe String
    , lastReadingFromWindowComplete : Maybe { timeInMilliseconds : Int, reading : InterfaceToHost.ReadFromWindowCompleteStruct }
    }


type alias ReadingFromGameClientAggregateState =
    { initialReading : VolatileProcessInterface.ReadFromWindowResultStructure
    , imageDataFromReadingResults : List GetImageDataFromReadingResultStructure
    , lastReadingFromWindow : Maybe InterfaceToHost.ReadFromWindowCompleteStruct
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot OperateBotConfiguration
    | FrameworkStopSession String


type alias OperateBotConfiguration =
    { buildTaskFromEffectSequence : List Common.EffectOnWindow.EffectOnWindowStructure -> InterfaceToHost.Task
    , readFromWindowTasks : GetImageDataFromReadingStructure -> List InterfaceToHost.Task
    , getImageDataFromReadingTask : GetImageDataFromReadingStructure -> InterfaceToHost.Task
    , releaseVolatileProcessTask : InterfaceToHost.Task
    }


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias GameClientProcessSummary =
    VolatileProcessInterface.GameClientProcessSummaryStruct


type alias ShipModulesMemory =
    { tooltipFromModuleButton : Dict.Dict String EveOnline.ParseUserInterface.ModuleButtonTooltip
    , lastReadingTooltip : Maybe EveOnline.ParseUserInterface.ModuleButtonTooltip
    }


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


type alias ReadingFromGameClientImage =
    { pixels_1x1 : Dict.Dict ( Int, Int ) PixelValueRGB
    , pixels_2x2 : Dict.Dict ( Int, Int ) PixelValueRGB
    }


type alias PixelValueRGB =
    { red : Int, green : Int, blue : Int }


type alias GetImageDataFromReadingStructure =
    { screenshotCrops_1x1 : List Rect2dStructure
    , screenshotCrops_2x2 : List Rect2dStructure
    }


type alias ReadingFromGameClientStructure =
    { parsedMemoryReading : EveOnline.ParseUserInterface.ParsedUserInterface
    , lastReadingFromWindow : Maybe InterfaceToHost.ReadFromWindowCompleteStruct
    , imageDataFromReadingResults : List GetImageDataFromReadingResultStructure
    }


type alias GetImageDataFromReadingResultStructure =
    { screenshot1x1Rects : List VolatileProcessInterface.ImageCrop
    , screenshot2x2Rects : List VolatileProcessInterface.ImageCrop
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
    , lastReadingTooltip = Nothing
    }


integrateCurrentReadingsIntoShipModulesMemory : EveOnline.ParseUserInterface.ParsedUserInterface -> ShipModulesMemory -> ShipModulesMemory
integrateCurrentReadingsIntoShipModulesMemory currentReading memoryBefore =
    let
        getTooltipDataForEqualityComparison tooltip =
            tooltip.uiNode
                |> EveOnline.ParseUserInterface.getAllContainedDisplayTextsWithRegion
                |> List.map (Tuple.mapSecond .totalDisplayRegion)

        {- To ensure robustness, we store a new tooltip only when the display texts match in two consecutive readings from the game client. -}
        tooltipAvailableToStore =
            case ( memoryBefore.lastReadingTooltip, currentReading.moduleButtonTooltip ) of
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
    , lastReadingTooltip = currentReading.moduleButtonTooltip
    }


getModuleButtonTooltipFromModuleButton : ShipModulesMemory -> EveOnline.ParseUserInterface.ShipUIModuleButton -> Maybe EveOnline.ParseUserInterface.ModuleButtonTooltip
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
    , lastReadingFromWindowComplete = Nothing
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
    , tasksInProgress = Dict.empty
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
                startTasksWithDescription =
                    continueSession.startTasks
                        |> List.indexedMap
                            (\startTaskIndex startTask ->
                                let
                                    taskIdString =
                                        startTask.areaId ++ "-" ++ String.fromInt (state.lastTaskIndex + startTaskIndex)
                                in
                                { taskId = taskIdString
                                , task = startTask.task
                                , taskDescription = startTask.taskDescription
                                }
                            )

                newTasksInProgress =
                    startTasksWithDescription
                        |> List.map
                            (\startTask ->
                                ( startTask.taskId
                                , { startTimeInMilliseconds = state.timeInMilliseconds
                                  , taskDescription = startTask.taskDescription
                                  }
                                )
                            )
                        |> Dict.fromList

                tasksInProgress =
                    state.tasksInProgress
                        |> Dict.union newTasksInProgress

                startTasks =
                    startTasksWithDescription
                        |> List.map (\startTask -> { taskId = startTask.taskId, task = startTask.task })
            in
            ( { state
                | lastTaskIndex = state.lastTaskIndex + List.length startTasks
                , tasksInProgress = tasksInProgress
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
            continueAfterIntegrateEvent Nothing stateBefore

        InterfaceToHost.TaskCompletedEvent taskComplete ->
            let
                ( setupState, maybeReadingFromGameClient ) =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
            in
            continueAfterIntegrateEvent
                maybeReadingFromGameClient
                { stateBefore
                    | setup = setupState
                    , tasksInProgress = stateBefore.tasksInProgress |> Dict.remove taskComplete.taskId
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
                Nothing
                { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }


processEventAfterIntegrateEvent :
    BotConfiguration botSettings botState
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventAfterIntegrateEvent botConfiguration maybeReadingFromGameClient stateBefore =
    let
        ( stateBeforeCountingRequests, responseBeforeAddingStatusMessage ) =
            case stateBefore.tasksInProgress |> Dict.toList |> List.head of
                Nothing ->
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
                                maybeReadingFromGameClient
                                stateBefore

                Just ( taskInProgressId, taskInProgress ) ->
                    ( stateBefore
                    , InternalContinueSession
                        { statusText =
                            "Waiting for completion of task '"
                                ++ taskInProgressId
                                ++ "': "
                                ++ taskInProgress.taskDescription
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                        , startTasks = []
                        }
                    )

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
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventNotWaitingForTaskCompletion botConfiguration botEventContext maybeReadingFromGameClient stateBefore =
    case stateBefore.setup |> getNextSetupTask botConfiguration stateBefore.botSettings of
        ContinueSetup setupState setupTask setupTaskDescription ->
            ( { stateBefore | setup = setupState }
            , { startTasks =
                    [ { areaId = "setup"
                      , task = setupTask
                      , taskDescription = "Setup: " ++ setupTaskDescription
                      }
                    ]
              , statusText = "Continue setup: " ++ setupTaskDescription
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
                          , taskDescription = setupTaskDescription
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
                    maybeReadingFromGameClient
                    stateBefore
                    operateBot

        FrameworkStopSession reason ->
            ( stateBefore
            , InternalFinishSession { statusText = "Stop session (" ++ reason ++ ")" }
            )


operateBotExceptRenewingVolatileProcess :
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework botSettings botState
    -> OperateBotConfiguration
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
operateBotExceptRenewingVolatileProcess botConfiguration botEventContext maybeNewReadingFromGameClient stateBefore operateBot =
    let
        continueWithNamedTasksToWaitOn { taskDescription, taskAreaId } tasks =
            ( stateBefore
            , { startTasks =
                    tasks
                        |> List.map
                            (\task ->
                                { areaId = taskAreaId
                                , taskDescription = taskDescription
                                , task = task
                                }
                            )
              , statusText = "Operate bot - " ++ taskDescription
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InternalContinueSession
            )

        continueWithReadingFromGameClient =
            continueWithNamedTasksToWaitOn
                { taskDescription = "Reading from game"
                , taskAreaId = "read-from-game"
                }
                (operateBot.readFromWindowTasks { screenshotCrops_1x1 = [], screenshotCrops_2x2 = [] })
    in
    case maybeNewReadingFromGameClient of
        Just readingFromGameClient ->
            let
                screenshot1x1Rects =
                    readingFromGameClient.imageDataFromReadingResults
                        |> List.concatMap .screenshot1x1Rects

                screenshot2x2Rects =
                    readingFromGameClient.imageDataFromReadingResults
                        |> List.concatMap .screenshot2x2Rects

                image =
                    { pixels_1x1 = pixelDictionaryFromCrops screenshot1x1Rects
                    , pixels_2x2 = pixelDictionaryFromCrops screenshot2x2Rects
                    }

                ( frameworkRequestedScreenshotCrops, parsedUserInterface ) =
                    parseUserInterface readingFromGameClient.parsedMemoryReading image

                screenshotRequiredRegionsFromBot =
                    case stateBefore.botState.lastEvent of
                        Nothing ->
                            { binned_1x1 = []
                            , binned_2x2 = []
                            }

                        Just lastEvent ->
                            case Tuple.second lastEvent.eventResult of
                                FinishSession _ ->
                                    { binned_1x1 = []
                                    , binned_2x2 = []
                                    }

                                ContinueSession continueSession ->
                                    { binned_1x1 =
                                        (continueSession.screenshotRegionsToRead readingFromGameClient.parsedMemoryReading).rects1x1
                                    , binned_2x2 = []
                                    }

                screenshotRequiredRegions =
                    { binned_1x1 =
                        screenshotRequiredRegionsFromBot.binned_1x1
                            ++ frameworkRequestedScreenshotCrops.screenshotCrops_1x1
                    , binned_2x2 =
                        screenshotRequiredRegionsFromBot.binned_2x2
                            ++ frameworkRequestedScreenshotCrops.screenshotCrops_2x2
                    }

                coveredRegions_1x1 =
                    screenshot1x1Rects
                        |> List.map
                            (\imageCrop ->
                                let
                                    width =
                                        imageCrop.pixels
                                            |> List.map List.length
                                            |> List.minimum
                                            |> Maybe.withDefault 0

                                    height =
                                        List.length imageCrop.pixels
                                in
                                { x = imageCrop.offset.x
                                , y = imageCrop.offset.y
                                , width = width
                                , height = height
                                }
                            )

                coveredRegions_2x2 =
                    screenshot2x2Rects
                        |> List.map
                            (\imageCrop ->
                                let
                                    width =
                                        imageCrop.pixels
                                            |> List.map List.length
                                            |> List.minimum
                                            |> Maybe.withDefault 0

                                    height =
                                        List.length imageCrop.pixels
                                in
                                { x = imageCrop.offset.x * 2
                                , y = imageCrop.offset.y * 2
                                , width = width * 2
                                , height = height * 2
                                }
                            )

                isRegionCovered_1x1 region =
                    EveOnline.ParseUserInterface.subtractRegionsFromRegion
                        { minuend = region, subtrahend = coveredRegions_1x1 }
                        |> List.isEmpty

                isRegionCovered_2x2 region =
                    EveOnline.ParseUserInterface.subtractRegionsFromRegion
                        { minuend = region, subtrahend = coveredRegions_2x2 }
                        |> List.isEmpty

                requiredRegionsNotCovered_1x1 =
                    screenshotRequiredRegions.binned_1x1
                        |> List.filter (isRegionCovered_1x1 >> not)

                requiredRegionsNotCovered_2x2 =
                    screenshotRequiredRegions.binned_2x2
                        |> List.filter (isRegionCovered_2x2 >> not)

                newCrops_1x1_WithMargins =
                    requiredRegionsNotCovered_1x1
                        |> List.map (regionAddMarginOnEachSide 1)

                newCrops_2x2_WithMargins =
                    requiredRegionsNotCovered_2x2
                        |> List.map (regionAddMarginOnEachSide 2)

                getImageData =
                    { screenshotCrops_1x1 = newCrops_1x1_WithMargins
                    , screenshotCrops_2x2 = newCrops_2x2_WithMargins
                    }
            in
            if
                (getImageData /= { screenshotCrops_1x1 = [], screenshotCrops_2x2 = [] })
                    && (List.length readingFromGameClient.imageDataFromReadingResults < getImageDataFromReadingRequestLimit)
            then
                continueWithNamedTasksToWaitOn
                    { taskDescription = "Get image data from reading"
                    , taskAreaId = "get-image-data-from-reading"
                    }
                    [ operateBot.getImageDataFromReadingTask getImageData ]

            else
                let
                    botStateBefore =
                        stateBefore.botState

                    botEvent =
                        ReadingFromGameClientCompleted parsedUserInterface image

                    ( newBotState, botEventResponse ) =
                        botStateBefore.botState
                            |> botConfiguration.processEvent botEventContext botEvent

                    lastEvent =
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , eventResult = ( newBotState, botEventResponse )
                        }

                    response =
                        case botEventResponse of
                            FinishSession _ ->
                                InternalFinishSession
                                    { statusText = "The bot finished the session." }

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
                                                  , taskDescription = "Send effects to game client"
                                                  , task = operateBot.buildTaskFromEffectSequence effects
                                                  }
                                                ]
                                in
                                { startTasks = startTasks
                                , statusText = "Operate bot"
                                , notifyWhenArrivedAtTime =
                                    if startTasks == [] then
                                        Just { timeInMilliseconds = timeForNextReadingFromGame }

                                    else
                                        Nothing
                                }
                                    |> InternalContinueSession

                    state =
                        { stateBefore
                            | botState =
                                { botStateBefore
                                    | botState = newBotState
                                    , lastEvent = Just lastEvent
                                }
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
                        + 10000

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

                timeForNextReadingFromGame =
                    min timeForNextReadingFromGameGeneral timeForNextReadingFromGameFromBot

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


pixelDictionaryFromCrops : List VolatileProcessInterface.ImageCrop -> Dict.Dict ( Int, Int ) PixelValueRGB
pixelDictionaryFromCrops crops =
    crops
        |> List.concatMap
            (\imageCrop ->
                imageCrop.pixels
                    |> List.indexedMap
                        (\rowIndexInCrop rowPixels ->
                            rowPixels
                                |> List.indexedMap
                                    (\columnIndexInCrop pixelValue ->
                                        ( ( columnIndexInCrop + imageCrop.offset.x
                                          , rowIndexInCrop + imageCrop.offset.y
                                          )
                                        , pixelValue
                                        )
                                    )
                        )
                    |> List.concat
            )
        |> Dict.fromList


integrateTaskResult :
    ( Int, InterfaceToHost.TaskResultStructure )
    -> SetupState
    -> ( SetupState, Maybe ReadingFromGameClientStructure )
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResult ->
            ( { setupStateBefore
                | createVolatileProcessResult = Just createVolatileProcessResult
                , requestsToVolatileProcessCount = 0
              }
            , Nothing
            )

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.ProcessNotFound) ->
            ( { setupStateBefore | createVolatileProcessResult = Nothing }
            , Nothing
            )

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.FailedToAcquireInputFocus) ->
            ( { setupStateBefore | lastEffectFailedToAcquireInputFocus = Just "Failed before entering volatile process." }
            , Nothing
            )

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
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileProcessOk ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileProcess
                            { timeInMilliseconds = timeInMilliseconds
                            , responseFromVolatileProcess = responseFromVolatileProcessOk
                            , runInVolatileProcessDurationInMs = requestResult.durationInMilliseconds
                            }

        InterfaceToHost.OpenWindowResponse _ ->
            ( setupStateBefore, Nothing )

        InterfaceToHost.InvokeMethodOnWindowResponse _ methodOnWindowResult ->
            case methodOnWindowResult of
                Ok (InterfaceToHost.ReadFromWindowMethodResult readFromWindowComplete) ->
                    setupStateBefore
                        |> integrateReadFromWindowComplete
                            { timeInMilliseconds = timeInMilliseconds
                            , readFromWindowComplete = readFromWindowComplete
                            }

                _ ->
                    ( setupStateBefore, Nothing )

        InterfaceToHost.RandomBytesResponse _ ->
            ( setupStateBefore, Nothing )

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateResponseFromVolatileProcess :
    { timeInMilliseconds : Int, responseFromVolatileProcess : VolatileProcessInterface.ResponseFromVolatileHost, runInVolatileProcessDurationInMs : Int }
    -> SetupState
    -> ( SetupState, Maybe ReadingFromGameClientStructure )
integrateResponseFromVolatileProcess { timeInMilliseconds, responseFromVolatileProcess, runInVolatileProcessDurationInMs } stateBefore =
    case responseFromVolatileProcess of
        VolatileProcessInterface.ListGameClientProcessesResponse gameClientProcesses ->
            ( { stateBefore | gameClientProcesses = Just gameClientProcesses }, Nothing )

        VolatileProcessInterface.SearchUIRootAddressResult searchUIRootAddressResult ->
            let
                state =
                    { stateBefore | searchUIRootAddressResult = Just searchUIRootAddressResult }
            in
            ( state, Nothing )

        VolatileProcessInterface.ReadFromWindowResult readFromWindowResult ->
            let
                lastReadingFromGame =
                    { timeInMilliseconds = timeInMilliseconds
                    , aggregate =
                        { initialReading = readFromWindowResult
                        , imageDataFromReadingResults = []
                        , lastReadingFromWindow = Nothing
                        }
                    }

                state =
                    { stateBefore
                        | lastReadingFromGame = Just lastReadingFromGame
                    }

                maybeReadingFromGameClient =
                    parseReadingFromGameClient lastReadingFromGame.aggregate
                        |> Result.toMaybe
            in
            ( state, maybeReadingFromGameClient )

        {-
           TODO: Remove VolatileProcessInterface.GetImageDataFromReadingResult
        -}
        VolatileProcessInterface.GetImageDataFromReadingResult getImageDataFromReadingResult ->
            ( stateBefore, Nothing )

        VolatileProcessInterface.FailedToBringWindowToFront error ->
            ( { stateBefore | lastEffectFailedToAcquireInputFocus = Just error }, Nothing )

        VolatileProcessInterface.CompletedEffectSequenceOnWindow ->
            ( { stateBefore | lastEffectFailedToAcquireInputFocus = Nothing }, Nothing )


integrateReadFromWindowComplete :
    { timeInMilliseconds : Int, readFromWindowComplete : InterfaceToHost.ReadFromWindowCompleteStruct }
    -> SetupState
    -> ( SetupState, Maybe ReadingFromGameClientStructure )
integrateReadFromWindowComplete { timeInMilliseconds, readFromWindowComplete } stateBeforeUpdateLastReading =
    let
        stateBefore =
            { stateBeforeUpdateLastReading
                | lastReadingFromWindowComplete =
                    Just
                        { timeInMilliseconds = timeInMilliseconds
                        , reading = readFromWindowComplete
                        }
            }
    in
    case stateBefore.lastReadingFromGame of
        Nothing ->
            ( stateBefore, Nothing )

        Just lastReadingFromGameBefore ->
            let
                screenshot1x1RectsFromCrop : InterfaceToHost.ImageCrop -> List VolatileProcessInterface.ImageCrop
                screenshot1x1RectsFromCrop crop =
                    if crop.origin.binning == { x = 1, y = 1 } then
                        [ { offset =
                                { x = crop.origin.offset.x - readFromWindowComplete.clientRectLeftUpperToScreen.x
                                , y = crop.origin.offset.y - readFromWindowComplete.clientRectLeftUpperToScreen.y
                                }
                          , pixels = crop.pixels |> List.map (List.map colorFromInt_R8G8B8)
                          }
                        ]

                    else
                        []

                screenshot2x2RectsFromCrop : InterfaceToHost.ImageCrop -> List VolatileProcessInterface.ImageCrop
                screenshot2x2RectsFromCrop crop =
                    let
                        inWindowOffsetX =
                            crop.origin.offset.x - readFromWindowComplete.clientRectLeftUpperToScreen.x

                        inWindowOffsetY =
                            crop.origin.offset.y - readFromWindowComplete.clientRectLeftUpperToScreen.y
                    in
                    if
                        crop.origin.binning == { x = 2, y = 2 }
                        {-
                           && ((inWindowOffsetX |> modBy 2) == 0)
                           && ((inWindowOffsetY |> modBy 2) == 0)
                        -}
                    then
                        [ { offset =
                                { x = inWindowOffsetX // 2
                                , y = inWindowOffsetY // 2
                                }
                          , pixels = crop.pixels |> List.map (List.map colorFromInt_R8G8B8)
                          }
                        ]

                    else
                        []

                getImageDataFromReadingResult : GetImageDataFromReadingResultStructure
                getImageDataFromReadingResult =
                    { screenshot1x1Rects =
                        readFromWindowComplete.imageData.screenshotCrops
                            |> List.concatMap screenshot1x1RectsFromCrop
                    , screenshot2x2Rects =
                        readFromWindowComplete.imageData.screenshotCrops
                            |> List.concatMap screenshot2x2RectsFromCrop
                    }

                aggregateBefore =
                    lastReadingFromGameBefore.aggregate

                imageDataFromReadingResults =
                    getImageDataFromReadingResult :: aggregateBefore.imageDataFromReadingResults

                lastReadingFromGame =
                    { lastReadingFromGameBefore
                        | aggregate =
                            { aggregateBefore
                                | imageDataFromReadingResults = imageDataFromReadingResults
                                , lastReadingFromWindow = Just readFromWindowComplete
                            }
                    }

                maybeReadingFromGameClient =
                    parseReadingFromGameClient lastReadingFromGame.aggregate
                        |> Result.toMaybe
            in
            ( { stateBefore | lastReadingFromGame = Just lastReadingFromGame }
            , maybeReadingFromGameClient
            )


colorFromInt_R8G8B8 : Int -> VolatileProcessInterface.PixelValueRGB
colorFromInt_R8G8B8 combined =
    { red = combined |> Bitwise.shiftRightZfBy 16 |> Bitwise.and 0xFF
    , green = combined |> Bitwise.shiftRightZfBy 8 |> Bitwise.and 0xFF
    , blue = combined |> Bitwise.and 0xFF
    }


parseReadingFromGameClient :
    ReadingFromGameClientAggregateState
    -> Result String ReadingFromGameClientStructure
parseReadingFromGameClient readingAggregate =
    case readingAggregate.initialReading of
        VolatileProcessInterface.ProcessNotFound ->
            Err "Initial reading failed with 'Process Not Found'"

        VolatileProcessInterface.Completed completedReading ->
            case completedReading.memoryReadingSerialRepresentationJson of
                Nothing ->
                    Err "Missing json representation of memory reading"

                Just memoryReadingSerialRepresentationJson ->
                    memoryReadingSerialRepresentationJson
                        |> EveOnline.MemoryReading.decodeMemoryReadingFromString
                        |> Result.mapError Json.Decode.errorToString
                        |> Result.map (EveOnline.ParseUserInterface.parseUITreeWithDisplayRegionFromUITree >> EveOnline.ParseUserInterface.parseUserInterfaceFromUITree)
                        |> Result.map
                            (\parsedMemoryReading ->
                                { parsedMemoryReading = parsedMemoryReading
                                , lastReadingFromWindow = Nothing
                                , imageDataFromReadingResults = readingAggregate.imageDataFromReadingResults
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
                                            readFromWindowRequest getImageData =
                                                VolatileProcessInterface.ReadFromWindow
                                                    { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                    , uiRootAddress = uiRootAddress
                                                    , getImageData = getImageData
                                                    }
                                        in
                                        case stateBefore.lastReadingFromGame of
                                            Nothing ->
                                                ContinueSetup stateBefore
                                                    (InterfaceToHost.RequestToVolatileProcess
                                                        (InterfaceToHost.RequestNotRequiringInputFocus
                                                            { processId = volatileProcessId
                                                            , request =
                                                                VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                                                    (readFromWindowRequest { screenshot1x1Rects = [] })
                                                            }
                                                        )
                                                    )
                                                    "Get the first memory reading from the EVE Online client process. This can take several seconds."

                                            Just lastMemoryReading ->
                                                case lastMemoryReading.aggregate.initialReading of
                                                    VolatileProcessInterface.ProcessNotFound ->
                                                        FrameworkStopSession "The EVE Online client process disappeared."

                                                    VolatileProcessInterface.Completed lastCompletedMemoryReading ->
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

                                                            lastReadingClientRectLeftUpperToScreen =
                                                                stateBefore.lastReadingFromWindowComplete
                                                                    |> Maybe.map (.reading >> .clientRectLeftUpperToScreen)
                                                                    |> Maybe.withDefault { x = 0, y = 0 }

                                                            mapGetImageData : GetImageDataFromReadingStructure -> InterfaceToHost.GetImageDataFromReadingStruct
                                                            mapGetImageData botGetImageData =
                                                                let
                                                                    crops_1x1 =
                                                                        botGetImageData.screenshotCrops_1x1
                                                                            |> List.map
                                                                                (\rectInClientArea ->
                                                                                    { offset =
                                                                                        { x =
                                                                                            ((rectInClientArea.x // 2) * 2)
                                                                                                + lastReadingClientRectLeftUpperToScreen.x
                                                                                        , y =
                                                                                            ((rectInClientArea.y // 2) * 2)
                                                                                                + lastReadingClientRectLeftUpperToScreen.y
                                                                                        }
                                                                                    , binning = { x = 1, y = 1 }
                                                                                    , binnedWidth = rectInClientArea.width
                                                                                    , binnedHeight = rectInClientArea.height
                                                                                    }
                                                                                )

                                                                    crops_2x2 =
                                                                        botGetImageData.screenshotCrops_2x2
                                                                            |> List.map
                                                                                (\rectInClientArea ->
                                                                                    { offset =
                                                                                        { x = rectInClientArea.x + lastReadingClientRectLeftUpperToScreen.x
                                                                                        , y = rectInClientArea.y + lastReadingClientRectLeftUpperToScreen.y
                                                                                        }
                                                                                    , binning = { x = 2, y = 2 }
                                                                                    , binnedWidth = rectInClientArea.width // 2
                                                                                    , binnedHeight = rectInClientArea.height // 2
                                                                                    }
                                                                                )
                                                                in
                                                                { screenshotCrops = crops_1x1 ++ crops_2x2 }
                                                        in
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
                                                                {-
                                                                   \getImageData ->
                                                                       buildTaskFromInvokeMethodOnWindowRequest
                                                                           (InterfaceToHost.ReadFromWindowMethod
                                                                               { reuseLastReading = False
                                                                               , imageData = mapGetImageData getImageData
                                                                               }
                                                                           )
                                                                -}
                                                                \getImageData ->
                                                                    [ readFromWindowRequest
                                                                        -- getImageData
                                                                        { screenshot1x1Rects = [] }
                                                                        |> buildTaskFromRequestToVolatileProcess
                                                                            (Just { maximumDelayMilliseconds = 500 })
                                                                    , buildTaskFromInvokeMethodOnWindowRequest
                                                                        (InterfaceToHost.ReadFromWindowMethod
                                                                            { reuseLastReading = False

                                                                            {- For now, do the reading of screenshot crops after we get the memory reading.

                                                                               , imageData = mapGetImageData getImageData
                                                                            -}
                                                                            , imageData = { screenshotCrops = [] }
                                                                            }
                                                                        )
                                                                    ]
                                                            , getImageDataFromReadingTask =
                                                                \getImageData ->
                                                                    buildTaskFromInvokeMethodOnWindowRequest
                                                                        (InterfaceToHost.ReadFromWindowMethod
                                                                            { reuseLastReading = True
                                                                            , imageData = mapGetImageData getImageData
                                                                            }
                                                                        )
                                                            , releaseVolatileProcessTask = InterfaceToHost.ReleaseVolatileProcess { processId = volatileProcessId }
                                                            }


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
                    let
                        allCrops =
                            lastReadingFromGame.aggregate.imageDataFromReadingResults
                                |> List.concatMap (\r -> [ r.screenshot1x1Rects, r.screenshot2x2Rects ])
                                |> List.concat

                        allPixelsCount =
                            allCrops
                                |> List.map (.pixels >> List.map List.length >> List.sum)
                                |> List.sum
                    in
                    Maybe.withDefault "no-reading" (Maybe.map .readingId lastReadingFromGame.aggregate.lastReadingFromWindow)
                        ++ ": "
                        ++ String.fromInt (List.length allCrops)
                        ++ " crops containing "
                        ++ String.fromInt allPixelsCount
                        ++ " pixels"
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


offsetRect : Location2d -> Rect2dStructure -> Rect2dStructure
offsetRect offset rect =
    { rect | x = rect.x + offset.x, y = rect.y + offset.y }


parseUserInterface :
    EveOnline.ParseUserInterface.ParsedUserInterface
    -> ReadingFromGameClientImage
    -> ( GetImageDataFromReadingStructure, EveOnline.ParseUserInterface.ParsedUserInterface )
parseUserInterface original readingFromImage =
    let
        {- Based on this sample:
           data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAUCAYAAACXtf2DAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsIAAA7CARUoSoAAAANWSURBVEhL1VVbb0xRFP7OHL3QzqheZjQtdUsZqhfNSAdhVKlrxJSIS0hFJEiQeJWI+AU8STzwIBGijRDSoiEpIcSgrom4PajeVAztGMwZa619zpnpqL77zux99uX71tpn773WaOXLG+IQxOkZHho9jI6WJmkozUj8RO2QmhBnCReDhFyow31l5W9T1rDNT9Iks8kBDdKTnjYKR/ftwv5tG+GvmIWDjZvhzMzAod07YJA4WcZ8/q1cOA97NjXg8N6dmODJR8PSADbU18JX5hUWw/6C8fm5ePT8JZpabsBDbV7NptX1OHXhInETxi2wE++0STh2+gzCAwMwYjEUe9woGDcW90JPbJbtQEGtTCY0Byq8pRiMRKhHz3BOeMjk83yFdzoi0ai0re2yHfyI/kKh241xOS7ZknjcwJHjJ7Bl7SqTMRR88D+iP1Fc6IEzKwuaQ8Pltlu01WmYMqHYZIkDdUe6P/fj2eu3NFmE9gch3Al1oLO3Dw+fvyIDY4ihbgVDWlQ1tbbBP6cS19vvIvx9AC/evMO5K9dQQFts8c1rSiumDq+abwN3eEUyGqcFUJufp63NoipfHpTdEV2MNNTiCRnTqEUNh0NtDtWKytBoUqMJTecPozadgzLOSPCGgPlszHwrG5a7f2j+KwxJFf+G2qTUVDEylEadBIHpUlhqyq1i1amQeaqG1yiIA3VbgICvGmvrFiLX5aR0UQbjdwy1NT5TkCzjOKHoz8vDuqWL4K8sgytrNLyTS1DkLkBpyUThMOxb5M7NwcypJXjz7gPmV88m0WxUzyxF3lgnXV1DOBZYwSW4LIDb90NY4vfBOToTMyZPxPZ1q9DV02NaTUoVmRnp+NTTiy/hb5Qm1P5tC67B2UtXxZqKlGTESZOBj93d+D4YgUExtCKwAKFnL9D/NaxWQJXtwDoUyw77eExRvFi2SDykwOQL4tJ7SZmgpqocOsUDa3gbbQddff2omuXF+pV16Or9LPZOnm/GYv9cM1UkwMbEIKWGA41b4crOliB739mJKzfbEaxfYrqnoLNTBbkzjJiEvprjVRgSzRz2/E5NFXw2nKZlqfTJPMaRzNB1nXuJQ2YCG3LQH49jFBcdOr8dRBSRyUsCpwTmCZ8M6tymt2gEwB+SX2kpOjZ/ywAAAABJRU5ErkJggg==
        -}
        matchesButtonTextOk buttonCenter =
            let
                colorSum color =
                    color.red + color.green + color.blue

                colorFromRelativeLocation_binned ( fromCenterX, fromCenterY ) =
                    readingFromImage.pixels_2x2
                        |> Dict.get ( buttonCenter.x // 2 - fromCenterX, buttonCenter.y // 2 - fromCenterY )
                        |> Maybe.withDefault { red = 0, green = 0, blue = 0 }

                ( darkestOffsetX, darkestOffsetY ) =
                    [ ( 0, 0 ), ( -1, 0 ), ( -2, 0 ), ( 0, 1 ), ( -1, 1 ), ( -2, 1 ) ]
                        |> List.sortBy (colorFromRelativeLocation_binned >> colorSum)
                        |> List.head
                        |> Maybe.withDefault ( 0, 0 )

                edgeThreshold =
                    20

                edges =
                    List.range -3 2
                        |> List.map
                            (\index ->
                                let
                                    leftSum =
                                        colorSum
                                            (colorFromRelativeLocation_binned
                                                ( darkestOffsetX + index, darkestOffsetY )
                                            )

                                    rightSum =
                                        colorSum
                                            (colorFromRelativeLocation_binned
                                                ( darkestOffsetX + index + 1, darkestOffsetY )
                                            )
                                in
                                (rightSum - leftSum) // edgeThreshold |> min 1 |> max -1
                            )
            in
            (List.drop 1 edges == [ 1, -1, 1, -1, 1 ])
                || (List.take 5 edges == [ 1, 1, -1, 1, 1 ])

        getTextFromButtonCenter buttonCenter =
            [ ( matchesButtonTextOk, "OK" )
            ]
                |> List.Extra.find (Tuple.first >> (|>) buttonCenter)
                |> Maybe.map Tuple.second

        mapMessageBox messageBox =
            case messageBox.buttonGroup of
                Nothing ->
                    { messageBox = messageBox
                    , crops_2x2 = []
                    }

                Just buttonGroup ->
                    let
                        cropRegionCenterY =
                            buttonGroup.totalDisplayRegion.y
                                + (buttonGroup.totalDisplayRegion.height // 2)

                        measureButtonEdgesY =
                            buttonGroup.totalDisplayRegion.y + 6

                        measureButtonEdgesLeft_2 =
                            buttonGroup.totalDisplayRegion.x // 2 - 1

                        measureButtonEdgesRight_2 =
                            (measureButtonEdgesLeft_2 + buttonGroup.totalDisplayRegion.width // 2) + 1

                        getEdgeLinePixel x =
                            Dict.get ( x, measureButtonEdgesY // 2 ) readingFromImage.pixels_2x2

                        colorDifferenceSum colorA colorB =
                            [ colorA.red - colorB.red
                            , colorA.green - colorB.green
                            , colorA.blue - colorB.blue
                            ]
                                |> List.map abs
                                |> List.sum

                        buttonEdgesBools_2 =
                            List.range measureButtonEdgesLeft_2 measureButtonEdgesRight_2
                                |> List.map
                                    (\x ->
                                        case ( getEdgeLinePixel (x - 1), getEdgeLinePixel (x + 1) ) of
                                            ( Just leftPixel, Just rightPixel ) ->
                                                Just (20 < colorDifferenceSum leftPixel rightPixel)

                                            _ ->
                                                Nothing
                                    )

                        fromImageButtonsRegions =
                            buttonEdgesBools_2
                                |> List.map (Maybe.withDefault False)
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

                        fromImageButtons : List { uiNode : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion, mainText : Maybe String }
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

                        cropRegion =
                            { x = buttonGroup.totalDisplayRegion.x - 6
                            , y = measureButtonEdgesY - 2
                            , width = buttonGroup.totalDisplayRegion.width + 12
                            , height = cropRegionCenterY - measureButtonEdgesY + 14
                            }
                    in
                    { messageBox =
                        { messageBox
                            | buttons = messageBox.buttons ++ fromImageButtons
                        }
                    , crops_2x2 = [ cropRegion ]
                    }

        mappedMessageBoxes =
            original.messageBoxes |> List.map mapMessageBox

        screenshotCrops_2x2 =
            mappedMessageBoxes |> List.concatMap .crops_2x2
    in
    ( { screenshotCrops_1x1 = []
      , screenshotCrops_2x2 = screenshotCrops_2x2
      }
    , { original | messageBoxes = mappedMessageBoxes |> List.map .messageBox }
    )


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

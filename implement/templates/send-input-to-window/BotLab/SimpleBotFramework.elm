{-
   This framework helps with bot development by taking care of these common tasks:

   + Keeping track of the window the bot should work in so that the bot reads from and sends input to the right window.
   + Set up the volatile process to interface with Windows.
   + Map typical tasks like sending inputs or taking screenshots to the Windows API.

   To use this framework:

   + Wrap you bots `processEvent` function with `BotLab.SimpleBotFramework.processEvent`.
   + Wrap you bots `initState` function with `BotLab.SimpleBotFramework.initState`.
-}


module BotLab.SimpleBotFramework exposing (..)

import BotLab.BotInterface_To_Host_2022_12_03 as InterfaceToHost
import Common.EffectOnWindow exposing (MouseButton(..))
import CompilationInterface.SourceFiles
import Dict
import Json.Decode
import List.Extra
import Windows.VolatileProcessInterface as VolatileProcessInterface


type alias BotEvent =
    { timeInMilliseconds : Int
    , eventAtTime : BotEventAtTime
    }


type BotEventAtTime
    = TimeArrivedEvent
    | SessionDurationPlannedEvent { timeInMilliseconds : Int }
    | TaskCompletedEvent CompletedTaskStructure


type EventMainBranch
    = ReturnToHostBranch (Result String String)
    | ContinueToBotBranch InternalEvent


type InternalEvent
    = TimeArrivedInternal
    | SessionDurationPlannedInternal { timeInMilliseconds : Int }
    | TaskCompletedInternal InterfaceToHost.CompletedTaskStructure


type BotResponse
    = ContinueSession BotResponseContinueSession
    | FinishSession BotResponseFinishSession


type alias CompletedTaskStructure =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = NoResultValue
    | ReadFromWindowResult ReadFromWindowResultStruct ImageStructure


type alias ReadFromWindowResultStruct =
    { windowSize : Location2d
    , windowClientRectOffset : Location2d
    , windowClientAreaSize : Location2d
    }


type alias ImageStructure =
    { imageAsDict : Dict.Dict ( Int, Int ) PixelValue
    , imageBinned2x2AsDict : Dict.Dict ( Int, Int ) PixelValue
    }


type alias ImageCropStructure =
    { imageWidth : Int
    , imageHeight : Int
    , imageAsDict : Dict.Dict ( Int, Int ) PixelValue
    }


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


type alias BotResponseContinueSession =
    { statusText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias BotResponseFinishSession =
    { statusText : String
    }


type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type TaskId
    = TaskIdFromString String


type alias Location2d =
    { x : Int, y : Int }


type Task
    = BringWindowToForeground
    | ReadFromWindow GetImageDataFromReadingStructure
    | GetImageDataFromReading GetImageDataFromReadingStructure
    | EffectSequenceOnWindowTask (List VolatileProcessInterface.EffectSequenceOnWindowElement)


type alias BotConfig botSettings botState =
    { init : botState
    , parseBotSettings : String -> Result String botSettings
    , processEvent : botSettings -> BotEvent -> botState -> ( botState, BotResponse )
    }


type alias State botSettings botState =
    { timeInMilliseconds : Int
    , createVolatileProcessResponse :
        Maybe
            { timeInMilliseconds : Int
            , result : Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete
            }
    , targetWindow : Maybe { windowId : String, windowTitle : String }
    , lastReadFromWindowResult :
        Maybe
            { readFromWindowComplete : VolatileProcessInterface.ReadFromWindowCompleteStruct
            , aggregateImage : ImageStructure
            }
    , tasksInProgress : Dict.Dict String TaskInProgress
    , lastTaskIndex : Int
    , error : Maybe String
    , botSettings : Maybe botSettings
    , simpleBot : botState
    , simpleBotAggregateQueueResponse : Maybe BotResponse
    }


type alias TaskInProgress =
    { startTimeInMilliseconds : Int
    , origin : TaskToHostOrigin
    }


type FrameworkSetupStepActivity
    = StopWithResult { resultDescription : String }
    | ContinueSetupWithTask { task : InterfaceToHost.StartTaskStructure, taskDescription : String }
    | OperateSimpleBot
        { windowId : String
        , buildHostTaskFromRequest : VolatileProcessInterface.RequestToVolatileProcess -> InterfaceToHost.Task
        }


type LocatePatternInImageApproach
    = TestPerPixelWithBroadPhase2x2
        { testOnBinned2x2 : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
        , testOnOriginalResolution : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
        }


type ImageSearchRegion
    = SearchEverywhere


type TaskToHostOrigin
    = FrameworkOrigin
    | BotOrigin TaskId Task


type InternalBotEventResponse
    = InternalContinueSession InternalContinueSessionStructure
    | InternalFinishSession InterfaceToHost.FinishSessionStructure


type alias InternalContinueSessionStructure =
    { statusText : String
    , startTasks : List InternalStartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias InternalStartTaskStructure =
    { taskId : String
    , task : InterfaceToHost.Task
    , taskOrigin : TaskToHostOrigin
    }


type alias GetImageDataFromReadingStructure =
    VolatileProcessInterface.GetImageDataFromReadingStructure


composeSimpleBotMain : BotConfig botSettings botState -> InterfaceToHost.BotConfig (State botSettings botState)
composeSimpleBotMain botConfig =
    { init = initState botConfig.init
    , processEvent = processEvent botConfig
    }


initState : botState -> State botSettings botState
initState simpleBotInitState =
    { timeInMilliseconds = 0
    , createVolatileProcessResponse = Nothing
    , targetWindow = Nothing
    , lastReadFromWindowResult = Nothing
    , tasksInProgress = Dict.empty
    , lastTaskIndex = 0
    , error = Nothing
    , botSettings = Nothing
    , simpleBot = simpleBotInitState
    , simpleBotAggregateQueueResponse = Nothing
    }


processEvent :
    BotConfig botSettings botState
    -> InterfaceToHost.BotEvent
    -> State botSettings botState
    -> ( State botSettings botState, InterfaceToHost.BotEventResponse )
processEvent botConfig event stateBeforeUpdateTime =
    let
        ( stateBefore, responseClass ) =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
                |> integrateEvent botConfig event.eventAtTime
    in
    case responseClass of
        ReturnToHostBranch (Ok continueSessionStatusText) ->
            ( stateBefore
            , InterfaceToHost.ContinueSession
                { statusText = continueSessionStatusText
                , startTasks = []
                , notifyWhenArrivedAtTime = Just { timeInMilliseconds = 0 }
                }
            )

        ReturnToHostBranch (Err finishSessionStatusText) ->
            ( stateBefore
            , InterfaceToHost.FinishSession
                { statusText = finishSessionStatusText }
            )

        ContinueToBotBranch internalEvent ->
            stateBefore
                |> processEventTrackingTasksInProgress botConfig internalEvent
                |> processEventAddStatusText


processEventAddStatusText :
    ( State botSettings botState, InterfaceToHost.BotEventResponse )
    -> ( State botSettings botState, InterfaceToHost.BotEventResponse )
processEventAddStatusText ( state, responseBeforeAddStatusText ) =
    let
        frameworkStatusText =
            (state |> statusTextFromState) ++ "\n"

        botStatusText =
            state.simpleBotAggregateQueueResponse
                |> Maybe.map
                    (\simpleBotLastResponse ->
                        case simpleBotLastResponse of
                            ContinueSession continueSession ->
                                continueSession.statusText

                            FinishSession finishSession ->
                                finishSession.statusText
                    )
                |> Maybe.withDefault ""

        generalStatusText =
            [ botStatusText
            , "--- Framework ---"
            , frameworkStatusText
            ]
                |> String.join "\n"

        response =
            case responseBeforeAddStatusText of
                InterfaceToHost.FinishSession finishSession ->
                    InterfaceToHost.FinishSession
                        { finishSession
                            | statusText = generalStatusText ++ finishSession.statusText
                        }

                InterfaceToHost.ContinueSession continueSession ->
                    InterfaceToHost.ContinueSession
                        { continueSession
                            | statusText = generalStatusText ++ continueSession.statusText
                        }
    in
    ( state, response )


processEventTrackingTasksInProgress :
    BotConfig botSettings botState
    -> InternalEvent
    -> State botSettings botState
    -> ( State botSettings botState, InterfaceToHost.BotEventResponse )
processEventTrackingTasksInProgress botConfig event stateBefore =
    let
        ( tasksInProgressAfterTaskCompleted, maybeCompletedBotTask ) =
            case event of
                TaskCompletedInternal taskCompletedEvent ->
                    let
                        maybeTaskFromBot =
                            case stateBefore.tasksInProgress |> Dict.get taskCompletedEvent.taskId of
                                Nothing ->
                                    Nothing

                                Just taskInProgress ->
                                    case taskInProgress.origin of
                                        BotOrigin taskIdFromBot taskFromBot ->
                                            Just ( taskIdFromBot, taskFromBot )

                                        FrameworkOrigin ->
                                            Nothing
                    in
                    ( stateBefore.tasksInProgress |> Dict.remove taskCompletedEvent.taskId
                    , maybeTaskFromBot
                    )

                _ ->
                    ( stateBefore.tasksInProgress, Nothing )

        tasksInProgress =
            tasksInProgressAfterTaskCompleted

        ( state, response ) =
            processEventLessTrackingTasks
                botConfig
                event
                maybeCompletedBotTask
                { stateBefore
                    | tasksInProgress = tasksInProgressAfterTaskCompleted
                }
    in
    case response of
        InternalFinishSession finishSession ->
            ( state, InterfaceToHost.FinishSession finishSession )

        InternalContinueSession continueSession ->
            let
                startTasks =
                    continueSession.startTasks
                        |> List.indexedMap
                            (\startTaskIndex startTask ->
                                { startTask
                                    | taskId =
                                        startTask.taskId
                                            ++ "-"
                                            ++ String.fromInt
                                                (stateBefore.lastTaskIndex
                                                    + 1
                                                    + startTaskIndex
                                                )
                                }
                            )

                lastTaskIndex =
                    stateBefore.lastTaskIndex + List.length startTasks

                newTasksInProgress =
                    startTasks
                        |> List.map
                            (\startTask ->
                                ( startTask.taskId
                                , { startTimeInMilliseconds = state.timeInMilliseconds
                                  , origin = startTask.taskOrigin
                                  }
                                )
                            )
                        |> Dict.fromList

                startTasksForHost =
                    startTasks
                        |> List.map
                            (\startTask ->
                                { taskId = startTask.taskId
                                , task = startTask.task
                                }
                            )
            in
            ( { state
                | lastTaskIndex = lastTaskIndex
                , tasksInProgress = tasksInProgress |> Dict.union newTasksInProgress
              }
            , InterfaceToHost.ContinueSession
                { statusText = continueSession.statusText
                , startTasks = startTasksForHost
                , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                }
            )


processEventLessTrackingTasks :
    BotConfig botSettings botState
    -> InternalEvent
    -> Maybe ( TaskId, Task )
    -> State botSettings botState
    -> ( State botSettings botState, InternalBotEventResponse )
processEventLessTrackingTasks botConfig event maybeCompletedBotTask stateBefore =
    case stateBefore.error of
        Just error ->
            ( stateBefore
            , InternalFinishSession { statusText = "Error: " ++ error }
            )

        Nothing ->
            processEventIgnoringLastError botConfig event maybeCompletedBotTask stateBefore


{-| On the relation between tasks from the bot and tasks from the framework:

For some events, it is easier to see that we should forward them to the bot immediately.
One example is bot-settings-changed: If the bot decides to finish the session in response, the response should reach the host for the same event, not later. The same applies to changes in the status text.

What about commands from the bot? If the bot says "take a screenshot" we need to wait for the completion of the framework setup (volatile process) first.
Therefore we queue tasks from the bot to forward them when we have completed the framework setup.

-}
processEventIgnoringLastError :
    BotConfig botSettings botState
    -> InternalEvent
    -> Maybe ( TaskId, Task )
    -> State botSettings botState
    -> ( State botSettings botState, InternalBotEventResponse )
processEventIgnoringLastError botConfig event maybeCompletedBotTask stateBefore =
    stateBefore
        |> processEventIntegrateBotEvents botConfig event maybeCompletedBotTask
        |> deriveTasksAfterIntegrateBotEvents


processEventIntegrateBotEvents :
    BotConfig botSettings botState
    -> InternalEvent
    -> Maybe ( TaskId, Task )
    -> State botSettings botState
    -> State botSettings botState
processEventIntegrateBotEvents botConfig event maybeCompletedBotTask stateBefore =
    case simpleBotEventsFromHostEvent event maybeCompletedBotTask stateBefore of
        Err _ ->
            stateBefore

        Ok ( state, [] ) ->
            state

        Ok ( state, firstBotEvent :: otherBotEvents ) ->
            let
                botSettingsResult =
                    stateBefore.botSettings
                        |> Maybe.map Ok
                        |> Maybe.withDefault (botConfig.parseBotSettings "")
            in
            case botSettingsResult of
                Err _ ->
                    -- TODO: Handle bot settings parse error
                    stateBefore

                Ok botSettings ->
                    let
                        ( simpleBotState, simpleBotAggregateQueueResponse ) =
                            state.simpleBot
                                |> processSequenceOfSimpleBotEventsAndCombineResponses
                                    (botConfig.processEvent botSettings)
                                    state.simpleBotAggregateQueueResponse
                                    firstBotEvent
                                    otherBotEvents
                    in
                    { state
                        | simpleBot = simpleBotState
                        , simpleBotAggregateQueueResponse = Just simpleBotAggregateQueueResponse
                    }


deriveTasksAfterIntegrateBotEvents :
    State botSettings simpleBotState
    -> ( State botSettings simpleBotState, InternalBotEventResponse )
deriveTasksAfterIntegrateBotEvents stateBefore =
    if not (Dict.isEmpty stateBefore.tasksInProgress) then
        ( stateBefore
        , InternalContinueSession
            { startTasks = []
            , statusText = "Waiting for all tasks to complete..."
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
            }
        )

    else
        case stateBefore |> getNextSetupStepWithDescriptionFromState of
            StopWithResult { resultDescription } ->
                ( stateBefore
                , InternalFinishSession
                    { statusText = "Stopped with result: " ++ resultDescription
                    }
                )

            ContinueSetupWithTask continue ->
                ( stateBefore
                , InternalContinueSession
                    { startTasks =
                        [ { taskId = continue.task.taskId
                          , task = continue.task.task
                          , taskOrigin = FrameworkOrigin
                          }
                        ]
                    , statusText = "I continue to set up the framework: Current step: " ++ continue.taskDescription
                    , notifyWhenArrivedAtTime = Nothing
                    }
                )

            OperateSimpleBot operateSimpleBot ->
                case stateBefore.simpleBotAggregateQueueResponse of
                    Nothing ->
                        ( stateBefore
                        , InternalContinueSession
                            { statusText = "Bot not started yet."
                            , startTasks = []
                            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 1000 }
                            }
                        )

                    Just (FinishSession finishSession) ->
                        ( stateBefore
                        , InternalFinishSession
                            { statusText = "Bot finished the session: " ++ finishSession.statusText }
                        )

                    Just (ContinueSession continueSession) ->
                        let
                            ( startTasks, simpleBotAggregateQueueResponse ) =
                                ( continueSession.startTasks
                                    |> consolidateBotTasks
                                    |> List.map
                                        (\simpleBotTaskWithId ->
                                            ( { taskId = simpleBotTaskWithId.taskId |> taskIdFromSimpleBotTaskId
                                              , task =
                                                    simpleBotTaskWithId.task
                                                        |> taskOnWindowFromSimpleBotTask { windowId = operateSimpleBot.windowId } stateBefore
                                                        |> operateSimpleBot.buildHostTaskFromRequest
                                              , taskOrigin = BotOrigin simpleBotTaskWithId.taskId simpleBotTaskWithId.task
                                              }
                                            , simpleBotTaskWithId
                                            )
                                        )
                                , ContinueSession { continueSession | startTasks = [] }
                                )

                            notifyWhenArrivedAtTime =
                                if startTasks == [] then
                                    continueSession.notifyWhenArrivedAtTime
                                        |> Maybe.withDefault
                                            { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }

                                else
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                        in
                        ( { stateBefore
                            | simpleBotAggregateQueueResponse = Just simpleBotAggregateQueueResponse
                          }
                        , InternalContinueSession
                            { statusText = "Operate bot"
                            , notifyWhenArrivedAtTime = Just notifyWhenArrivedAtTime
                            , startTasks = startTasks |> List.map Tuple.first
                            }
                        )


consolidateBotTasks : List StartTaskStructure -> List StartTaskStructure
consolidateBotTasks =
    let
        tryMerge taskA taskB =
            case ( taskA.task, taskB.task ) of
                ( ReadFromWindow readFromWindowTaskA, ReadFromWindow readFromWindowTaskB ) ->
                    Just
                        { taskId = taskB.taskId
                        , task =
                            {-
                               TODO: Also remove crops which are completely covered by other crop.
                            -}
                            ReadFromWindow
                                { crops_1x1_r8g8b8 =
                                    readFromWindowTaskA.crops_1x1_r8g8b8
                                        ++ readFromWindowTaskB.crops_1x1_r8g8b8
                                        |> List.Extra.unique
                                , crops_2x2_r8g8b8 =
                                    readFromWindowTaskA.crops_2x2_r8g8b8
                                        ++ readFromWindowTaskB.crops_2x2_r8g8b8
                                        |> List.Extra.unique
                                }
                        }

                _ ->
                    Nothing
    in
    List.foldl
        (\startTask aggregate ->
            case List.reverse aggregate of
                [] ->
                    aggregate ++ [ startTask ]

                lastFromAggregate :: previousFromAggregateReversed ->
                    case tryMerge lastFromAggregate startTask of
                        Nothing ->
                            aggregate ++ [ startTask ]

                        Just merged ->
                            List.reverse previousFromAggregateReversed ++ [ merged ]
        )
        []


simpleBotEventsFromHostEvent :
    InternalEvent
    -> Maybe ( TaskId, Task )
    -> State botSettings botState
    -> Result String ( State botSettings botState, List BotEvent )
simpleBotEventsFromHostEvent event maybeCompletedBotTask stateBefore =
    simpleBotEventsFromHostEventAtTime event maybeCompletedBotTask stateBefore
        |> Result.map
            (Tuple.mapSecond
                (List.map
                    (\eventAtTime ->
                        { timeInMilliseconds = stateBefore.timeInMilliseconds, eventAtTime = eventAtTime }
                    )
                )
            )


simpleBotEventsFromHostEventAtTime :
    InternalEvent
    -> Maybe ( TaskId, Task )
    -> State botSettings botState
    -> Result String ( State botSettings botState, List BotEventAtTime )
simpleBotEventsFromHostEventAtTime event maybeCompletedBotTask stateBefore =
    case event of
        TimeArrivedInternal ->
            Ok ( stateBefore, [ TimeArrivedEvent ] )

        SessionDurationPlannedInternal sessionDurationPlannedEvent ->
            Ok ( stateBefore, [ SessionDurationPlannedEvent sessionDurationPlannedEvent ] )

        TaskCompletedInternal completedTask ->
            let
                taskIdString =
                    completedTask.taskId
            in
            case maybeCompletedBotTask of
                Nothing ->
                    Err ("Did not find a bot task for task with ID " ++ taskIdString)

                Just ( simpleBotTaskId, simpleBotTask ) ->
                    let
                        taskResultResult =
                            case completedTask.taskResult of
                                InterfaceToHost.CreateVolatileProcessResponse _ ->
                                    Err "CreateVolatileProcessResponse"

                                InterfaceToHost.CompleteWithoutResult ->
                                    Err "CompleteWithoutResult"

                                InterfaceToHost.OpenWindowResponse _ ->
                                    Err "OpenWindowResponse"

                                InterfaceToHost.InvokeMethodOnWindowResponse _ ->
                                    Err "InvokeMethodOnWindowResponse"

                                InterfaceToHost.RequestToVolatileProcessResponse requestToVolatileProcessResponse ->
                                    case requestToVolatileProcessResponse of
                                        Err InterfaceToHost.ProcessNotFound ->
                                            Err "Error running script in volatile process: ProcessNotFound"

                                        Err InterfaceToHost.FailedToAcquireInputFocus ->
                                            Err "Error running script in volatile process: FailedToAcquireInputFocus"

                                        Ok volatileProcessResponseSuccess ->
                                            case volatileProcessResponseSuccess.exceptionToString of
                                                Just exceptionInVolatileProcess ->
                                                    Err ("Exception in volatile process: " ++ exceptionInVolatileProcess)

                                                Nothing ->
                                                    case volatileProcessResponseSuccess.returnValueToString |> Maybe.withDefault "" |> VolatileProcessInterface.deserializeResponseFromVolatileProcess of
                                                        Err error ->
                                                            Err ("Failed to parse response from volatile process: " ++ (error |> Json.Decode.errorToString))

                                                        Ok parsedResponse ->
                                                            let
                                                                continueForReadFromWindowOrGetImageData =
                                                                    case parsedResponse of
                                                                        VolatileProcessInterface.ReadingNotFound ->
                                                                            Err "ReadingNotFound"

                                                                        VolatileProcessInterface.TaskOnWindowResponse taskOnWindowResponse ->
                                                                            case taskOnWindowResponse.result of
                                                                                VolatileProcessInterface.WindowNotFound ->
                                                                                    Err "WindowNotFound"

                                                                                VolatileProcessInterface.ReadFromWindowComplete readFromWindowComplete ->
                                                                                    let
                                                                                        aggregateImage =
                                                                                            deriveImageRepresentation
                                                                                                readFromWindowComplete.imageData

                                                                                        lastReadFromWindowResult =
                                                                                            { readFromWindowComplete = readFromWindowComplete
                                                                                            , aggregateImage = aggregateImage
                                                                                            }
                                                                                    in
                                                                                    Ok
                                                                                        ( { stateBefore
                                                                                            | lastReadFromWindowResult = Just lastReadFromWindowResult
                                                                                          }
                                                                                        , ReadFromWindowResult
                                                                                            { windowSize = readFromWindowComplete.windowSize
                                                                                            , windowClientRectOffset = readFromWindowComplete.windowClientRectOffset
                                                                                            , windowClientAreaSize = readFromWindowComplete.windowClientAreaSize
                                                                                            }
                                                                                            aggregateImage
                                                                                        )

                                                                        VolatileProcessInterface.GetImageDataFromReadingComplete getImageDataFromReadingComplete ->
                                                                            case stateBefore.lastReadFromWindowResult of
                                                                                Nothing ->
                                                                                    Err "No lastReadFromWindowResult"

                                                                                Just lastReadFromWindowResultBefore ->
                                                                                    if lastReadFromWindowResultBefore.readFromWindowComplete.readingId /= getImageDataFromReadingComplete.readingId then
                                                                                        Err "readingId mismatch"

                                                                                    else
                                                                                        let
                                                                                            newImage =
                                                                                                deriveImageRepresentation
                                                                                                    getImageDataFromReadingComplete.imageData

                                                                                            aggregateImage =
                                                                                                mergeImageRepresentation
                                                                                                    lastReadFromWindowResultBefore.aggregateImage
                                                                                                    newImage

                                                                                            lastReadFromWindowResult =
                                                                                                { lastReadFromWindowResultBefore
                                                                                                    | aggregateImage = aggregateImage
                                                                                                }
                                                                                        in
                                                                                        Ok
                                                                                            ( { stateBefore
                                                                                                | lastReadFromWindowResult = Just lastReadFromWindowResult
                                                                                              }
                                                                                            , ReadFromWindowResult
                                                                                                { windowSize = lastReadFromWindowResult.readFromWindowComplete.windowSize
                                                                                                , windowClientRectOffset = lastReadFromWindowResult.readFromWindowComplete.windowClientRectOffset
                                                                                                , windowClientAreaSize = lastReadFromWindowResult.readFromWindowComplete.windowClientAreaSize
                                                                                                }
                                                                                                aggregateImage
                                                                                            )

                                                                        _ ->
                                                                            Err ("Unexpected return value from volatile process: " ++ (volatileProcessResponseSuccess.returnValueToString |> Maybe.withDefault ""))
                                                            in
                                                            case simpleBotTask of
                                                                BringWindowToForeground ->
                                                                    Ok ( stateBefore, NoResultValue )

                                                                EffectSequenceOnWindowTask _ ->
                                                                    Ok ( stateBefore, NoResultValue )

                                                                ReadFromWindow _ ->
                                                                    continueForReadFromWindowOrGetImageData

                                                                GetImageDataFromReading _ ->
                                                                    continueForReadFromWindowOrGetImageData
                    in
                    case taskResultResult of
                        Err error ->
                            Err ("Unexpected task result: " ++ error)

                        Ok ( state, taskResultOk ) ->
                            Ok
                                ( state
                                , [ TaskCompletedEvent { taskId = simpleBotTaskId, taskResult = taskResultOk } ]
                                )


mergeImageRepresentation : ImageStructure -> ImageStructure -> ImageStructure
mergeImageRepresentation imageA imageB =
    { imageAsDict = Dict.union imageA.imageAsDict imageB.imageAsDict
    , imageBinned2x2AsDict = Dict.union imageA.imageBinned2x2AsDict imageB.imageBinned2x2AsDict
    }


deriveImageRepresentation : VolatileProcessInterface.GetImageDataFromReadingResultStructure -> ImageStructure
deriveImageRepresentation imageData =
    let
        crops_1x1_r8g8b8_Derivations =
            imageData.crops_1x1_r8g8b8 |> List.map deriveImageCropRepresentation

        crops_2x2_r8g8b8_Derivations =
            imageData.crops_2x2_r8g8b8
                |> List.map (\crop -> { crop | offset = { x = crop.offset.x // 2, y = crop.offset.y // 2 } })
                |> List.map deriveImageCropRepresentation

        imageAsDict =
            crops_1x1_r8g8b8_Derivations
                |> List.map .imageAsDict
                |> List.foldl Dict.union Dict.empty

        imageBinned2x2AsDict =
            crops_2x2_r8g8b8_Derivations
                |> List.map .imageAsDict
                |> List.foldl Dict.union Dict.empty
    in
    { imageAsDict = imageAsDict
    , imageBinned2x2AsDict = imageBinned2x2AsDict
    }


deriveImageRepresentationFromNestedListOfPixels : List (List PixelValue) -> ImageStructure
deriveImageRepresentationFromNestedListOfPixels imageAsNestedList =
    let
        imageAsDict =
            imageAsNestedList |> dictWithTupleKeyFromIndicesInNestedList

        imageBinned2x2AsDict =
            List.range 0 (((imageAsNestedList |> List.length) - 1) // 2)
                |> List.map
                    (\binnedRowIndex ->
                        let
                            rowWidth =
                                imageAsNestedList
                                    |> List.drop (binnedRowIndex * 2)
                                    |> List.take 2
                                    |> List.map List.length
                                    |> List.maximum
                                    |> Maybe.withDefault 0

                            rowBinnedWidth =
                                (rowWidth - 1) // 2 + 1
                        in
                        List.range 0 (rowBinnedWidth - 1)
                            |> List.map
                                (\binnedColumnIndex ->
                                    let
                                        sourcePixelsValues =
                                            [ ( 0, 0 ), ( 1, 0 ), ( 0, 1 ), ( 1, 1 ) ]
                                                |> List.filterMap (\( relX, relY ) -> imageAsDict |> Dict.get ( binnedColumnIndex * 2 + relX, binnedRowIndex * 2 + relY ))

                                        pixelValueSum =
                                            sourcePixelsValues
                                                |> List.foldl (\pixel sum -> { red = sum.red + pixel.red, green = sum.green + pixel.green, blue = sum.blue + pixel.blue }) { red = 0, green = 0, blue = 0 }

                                        sourcePixelsValuesCount =
                                            sourcePixelsValues |> List.length

                                        pixelValue =
                                            { red = pixelValueSum.red // sourcePixelsValuesCount
                                            , green = pixelValueSum.green // sourcePixelsValuesCount
                                            , blue = pixelValueSum.blue // sourcePixelsValuesCount
                                            }
                                    in
                                    pixelValue
                                )
                    )
                |> dictWithTupleKeyFromIndicesInNestedList
    in
    { imageAsDict = imageAsDict
    , imageBinned2x2AsDict = imageBinned2x2AsDict
    }


deriveImageCropRepresentation : VolatileProcessInterface.ImageCropRGB -> ImageCropStructure
deriveImageCropRepresentation crop =
    let
        imageWidths =
            crop.pixels |> List.map List.length

        imageWidth =
            imageWidths |> List.maximum |> Maybe.withDefault 0

        imageHeight =
            imageWidths |> List.length

        imageAsDict =
            crop.pixels |> dictWithTupleKeyFromIndicesInNestedListWithOffset crop.offset
    in
    { imageWidth = imageWidth
    , imageHeight = imageHeight
    , imageAsDict = imageAsDict
    }


locatePatternInImage : LocatePatternInImageApproach -> ImageSearchRegion -> ImageStructure -> List Location2d
locatePatternInImage searchPattern searchRegion image =
    case searchPattern of
        TestPerPixelWithBroadPhase2x2 { testOnBinned2x2, testOnOriginalResolution } ->
            let
                binnedSearchLocations =
                    case searchRegion of
                        SearchEverywhere ->
                            image.imageBinned2x2AsDict |> Dict.keys |> List.map (\( x, y ) -> { x = x, y = y })

                matchLocationsOnBinned2x2 =
                    image.imageBinned2x2AsDict
                        |> getMatchesLocationsFromImage testOnBinned2x2 binnedSearchLocations

                originalResolutionSearchLocations =
                    matchLocationsOnBinned2x2
                        |> List.concatMap
                            (\binnedLocation ->
                                [ { x = binnedLocation.x * 2, y = binnedLocation.y * 2 }
                                , { x = binnedLocation.x * 2 + 1, y = binnedLocation.y * 2 }
                                , { x = binnedLocation.x * 2, y = binnedLocation.y * 2 + 1 }
                                , { x = binnedLocation.x * 2 + 1, y = binnedLocation.y * 2 + 1 }
                                ]
                            )

                matchLocations =
                    image.imageAsDict
                        |> getMatchesLocationsFromImage testOnOriginalResolution originalResolutionSearchLocations
            in
            matchLocations


getMatchesLocationsFromImage :
    (({ x : Int, y : Int } -> Maybe PixelValue) -> Bool)
    -> List { x : Int, y : Int }
    -> Dict.Dict ( Int, Int ) PixelValue
    -> List { x : Int, y : Int }
getMatchesLocationsFromImage imageMatchesPatternAtOrigin locationsToSearchAt image =
    locationsToSearchAt
        |> List.filter
            (\searchOrigin ->
                imageMatchesPatternAtOrigin
                    (\relativeLocation -> image |> Dict.get ( relativeLocation.x + searchOrigin.x, relativeLocation.y + searchOrigin.y ))
            )


processSequenceOfSimpleBotEventsAndCombineResponses :
    (BotEvent -> botState -> ( botState, BotResponse ))
    -> Maybe BotResponse
    -> BotEvent
    -> List BotEvent
    -> botState
    -> ( botState, BotResponse )
processSequenceOfSimpleBotEventsAndCombineResponses simpleBotProcessEvent maybeLastBotResponse nextEvent followingEvents botStateBefore =
    let
        integrateLastBotResponse =
            case maybeLastBotResponse of
                Nothing ->
                    identity

                Just lastBotResponse ->
                    combineBotResponse lastBotResponse

        ( nextBotState, nextBotResponse ) =
            botStateBefore
                |> simpleBotProcessEvent nextEvent
                |> Tuple.mapSecond integrateLastBotResponse
    in
    case nextBotResponse of
        FinishSession _ ->
            ( nextBotState, nextBotResponse )

        ContinueSession _ ->
            let
                ( followingBotState, followingBotResponse ) =
                    case followingEvents of
                        [] ->
                            ( nextBotState, nextBotResponse )

                        nextNextBotEvent :: nextFollowingBotEvents ->
                            nextBotState
                                |> processSequenceOfSimpleBotEventsAndCombineResponses
                                    simpleBotProcessEvent
                                    (Just nextBotResponse)
                                    nextNextBotEvent
                                    nextFollowingBotEvents
            in
            ( followingBotState, followingBotResponse )


combineBotResponse : BotResponse -> BotResponse -> BotResponse
combineBotResponse firstResponse secondResponse =
    case firstResponse of
        FinishSession _ ->
            firstResponse

        ContinueSession firstContinueSession ->
            case secondResponse of
                FinishSession _ ->
                    secondResponse

                ContinueSession secondContinueSession ->
                    ContinueSession
                        { secondContinueSession
                            | startTasks = firstContinueSession.startTasks ++ secondContinueSession.startTasks
                        }


taskIdFromSimpleBotTaskId : TaskId -> String
taskIdFromSimpleBotTaskId simpleBotTaskId =
    case simpleBotTaskId of
        TaskIdFromString asString ->
            "bot-" ++ asString


taskOnWindowFromSimpleBotTask :
    { windowId : String }
    -> State botSettings botState
    -> Task
    -> VolatileProcessInterface.RequestToVolatileProcess
taskOnWindowFromSimpleBotTask config state simpleBotTask =
    let
        continueWithTaskOnWindow taskOnWindow =
            { windowId = config.windowId, task = taskOnWindow }
                |> VolatileProcessInterface.TaskOnWindowRequest
    in
    case simpleBotTask of
        BringWindowToForeground ->
            VolatileProcessInterface.BringWindowToForeground
                |> continueWithTaskOnWindow

        ReadFromWindow readFromWindowTask ->
            { getImageData = readFromWindowTask }
                |> VolatileProcessInterface.ReadFromWindowRequest
                |> continueWithTaskOnWindow

        GetImageDataFromReading getImageDataFromReadingTask ->
            case state.lastReadFromWindowResult of
                Nothing ->
                    { getImageData = getImageDataFromReadingTask }
                        |> VolatileProcessInterface.ReadFromWindowRequest
                        |> continueWithTaskOnWindow

                Just lastReadFromWindowResult ->
                    { readingId = lastReadFromWindowResult.readFromWindowComplete.readingId
                    , getImageData = getImageDataFromReadingTask
                    }
                        |> VolatileProcessInterface.GetImageDataFromReadingRequest

        EffectSequenceOnWindowTask effectSequence ->
            effectSequence
                |> VolatileProcessInterface.EffectSequenceOnWindowRequest
                |> continueWithTaskOnWindow


integrateEvent :
    BotConfig botSettings botState
    -> InterfaceToHost.BotEventAtTime
    -> State botSettings botState
    -> ( State botSettings botState, EventMainBranch )
integrateEvent botConfig eventAtTime stateBefore =
    case eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            ( stateBefore
            , ContinueToBotBranch TimeArrivedInternal
            )

        InterfaceToHost.BotSettingsChangedEvent botSettingsString ->
            case botConfig.parseBotSettings botSettingsString of
                Err err ->
                    ( stateBefore
                    , ReturnToHostBranch
                        (Err ("Failed to parse these bot settings:" ++ err))
                    )

                Ok ok ->
                    ( { stateBefore | botSettings = Just ok }
                    , ReturnToHostBranch (Ok "Succeeded parsing these bot-settings.")
                    )

        InterfaceToHost.TaskCompletedEvent taskCompleted ->
            ( integrateEventTaskComplete taskCompleted.taskId taskCompleted.taskResult stateBefore
            , ContinueToBotBranch (TaskCompletedInternal taskCompleted)
            )

        InterfaceToHost.SessionDurationPlannedEvent durationPlanned ->
            ( stateBefore
            , ContinueToBotBranch (SessionDurationPlannedInternal durationPlanned)
            )


integrateEventTaskComplete :
    String
    -> InterfaceToHost.TaskResultStructure
    -> State botSettings botState
    -> State botSettings botState
integrateEventTaskComplete taskId taskResult stateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResult ->
            { stateBefore
                | createVolatileProcessResponse =
                    Just
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , result = createVolatileProcessResult
                        }
            }

        InterfaceToHost.RequestToVolatileProcessResponse requestToVolatileProcessResponse ->
            case requestToVolatileProcessResponse of
                Err InterfaceToHost.ProcessNotFound ->
                    { stateBefore | error = Just "Error running script in volatile process: ProcessNotFound" }

                Err InterfaceToHost.FailedToAcquireInputFocus ->
                    stateBefore

                Ok runInVolatileProcessComplete ->
                    case runInVolatileProcessComplete.returnValueToString of
                        Nothing ->
                            { stateBefore | error = Just ("Error in volatile process: " ++ (runInVolatileProcessComplete.exceptionToString |> Maybe.withDefault "")) }

                        Just returnValueToString ->
                            case stateBefore.createVolatileProcessResponse |> Maybe.map .result of
                                Nothing ->
                                    { stateBefore | error = Just ("Unexpected response from volatile process: " ++ returnValueToString) }

                                Just (Err createVolatileProcessError) ->
                                    { stateBefore | error = Just ("Failed to create volatile process: " ++ createVolatileProcessError.exceptionToString) }

                                Just (Ok createVolatileProcessCompleted) ->
                                    case returnValueToString |> VolatileProcessInterface.deserializeResponseFromVolatileProcess of
                                        Err error ->
                                            { stateBefore | error = Just ("Failed to parse response from volatile process: " ++ (error |> Json.Decode.errorToString)) }

                                        Ok responseFromVolatileProcess ->
                                            case stateBefore.targetWindow of
                                                Nothing ->
                                                    case responseFromVolatileProcess of
                                                        VolatileProcessInterface.ListWindowsResponse windowsSummaries ->
                                                            { stateBefore
                                                                | targetWindow =
                                                                    windowsSummaries
                                                                        |> List.sortBy .windowZIndex
                                                                        |> List.head
                                                                        |> Maybe.map
                                                                            (\summary ->
                                                                                { windowId = summary.windowId
                                                                                , windowTitle = summary.windowTitle
                                                                                }
                                                                            )
                                                            }

                                                        _ ->
                                                            { stateBefore | error = Just ("Unexpected response from volatile process: " ++ returnValueToString) }

                                                Just _ ->
                                                    stateBefore

        InterfaceToHost.CompleteWithoutResult ->
            stateBefore

        InterfaceToHost.OpenWindowResponse _ ->
            stateBefore

        InterfaceToHost.InvokeMethodOnWindowResponse _ ->
            stateBefore


statusTextFromState : State botSettings botState -> String
statusTextFromState state =
    let
        portionWindow =
            case state.targetWindow of
                Nothing ->
                    ""

                Just targetWindow ->
                    "I work in the window with title '" ++ targetWindow.windowTitle ++ "'."

        tasksReport =
            "Waiting for "
                ++ (state.tasksInProgress |> Dict.size |> String.fromInt)
                ++ " task(s) to complete: "
                ++ (state.tasksInProgress |> Dict.keys |> String.join ", ")

        botTaskQueueReport =
            case state.simpleBotAggregateQueueResponse of
                Nothing ->
                    ""

                Just (FinishSession _) ->
                    "Bot finished the session"

                Just (ContinueSession continueSession) ->
                    (continueSession.startTasks |> List.length |> String.fromInt)
                        ++ " task(s) from bot in queue"
    in
    [ portionWindow
    , tasksReport
    , botTaskQueueReport
    ]
        |> String.join "\n"


getNextSetupStepWithDescriptionFromState : State botSettings botState -> FrameworkSetupStepActivity
getNextSetupStepWithDescriptionFromState state =
    case state.createVolatileProcessResponse of
        Nothing ->
            { task =
                { taskId = "create_volatile_process"
                , task = InterfaceToHost.CreateVolatileProcess { programCode = CompilationInterface.SourceFiles.file____Windows_VolatileProcess_csx.utf8 }
                }
            , taskDescription = "Set up the volatile process. This can take several seconds, especially when assemblies are not cached yet."
            }
                |> ContinueSetupWithTask

        Just createVolatileProcessResponse ->
            case createVolatileProcessResponse.result of
                Err createVolatileProcessError ->
                    StopWithResult { resultDescription = "Failed to create volatile process: " ++ createVolatileProcessError.exceptionToString }

                Ok createVolatileProcessCompleted ->
                    let
                        listWindowsTask =
                            InterfaceToHost.RequestToVolatileProcess
                                (InterfaceToHost.RequestRequiringInputFocus
                                    {-
                                       Use RequestRequiringInputFocus in setup to ensure that infra is initialized before handing over to the bot.
                                    -}
                                    { acquireInputFocus = { maximumDelayMilliseconds = 500 }
                                    , request =
                                        { processId = createVolatileProcessCompleted.processId
                                        , request =
                                            VolatileProcessInterface.ListWindowsRequest
                                                |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                        }
                                    }
                                )

                        continueWithListWindows =
                            { task = { taskId = "list_windows", task = listWindowsTask }
                            , taskDescription = "List windows"
                            }
                                |> ContinueSetupWithTask
                    in
                    case state.targetWindow of
                        Nothing ->
                            continueWithListWindows

                        Just targetWindow ->
                            OperateSimpleBot
                                { windowId = targetWindow.windowId
                                , buildHostTaskFromRequest =
                                    \request ->
                                        InterfaceToHost.RequestToVolatileProcess
                                            (InterfaceToHost.RequestRequiringInputFocus
                                                { acquireInputFocus = { maximumDelayMilliseconds = 500 }
                                                , request =
                                                    { processId = createVolatileProcessCompleted.processId
                                                    , request =
                                                        request
                                                            |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                                    }
                                                }
                                            )
                                }


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


dictWithTupleKeyFromIndicesInNestedList : List (List element) -> Dict.Dict ( Int, Int ) element
dictWithTupleKeyFromIndicesInNestedList =
    dictWithTupleKeyFromIndicesInNestedListWithOffset { x = 0, y = 0 }


dictWithTupleKeyFromIndicesInNestedListWithOffset : Location2d -> List (List element) -> Dict.Dict ( Int, Int ) element
dictWithTupleKeyFromIndicesInNestedListWithOffset offset nestedList =
    nestedList
        |> List.indexedMap
            (\rowIndex list ->
                list
                    |> List.indexedMap
                        (\columnIndex element ->
                            ( ( columnIndex + offset.x, rowIndex + offset.y ), element )
                        )
            )
        |> List.concat
        |> Dict.fromList


bringWindowToForeground : Task
bringWindowToForeground =
    BringWindowToForeground


setMouseCursorPositionEffect : Location2d -> Common.EffectOnWindow.EffectOnWindowStructure
setMouseCursorPositionEffect =
    Common.EffectOnWindow.SetMouseCursorPositionEffect


mouseButtonDownEffect : MouseButton -> Common.EffectOnWindow.EffectOnWindowStructure
mouseButtonDownEffect =
    Common.EffectOnWindow.virtualKeyCodeFromMouseButton
        >> Common.EffectOnWindow.KeyDownEffect


mouseButtonUpEffect : MouseButton -> Common.EffectOnWindow.EffectOnWindowStructure
mouseButtonUpEffect =
    Common.EffectOnWindow.virtualKeyCodeFromMouseButton
        >> Common.EffectOnWindow.KeyUpEffect


keyboardKeyDownEffect : Common.EffectOnWindow.VirtualKeyCode -> Common.EffectOnWindow.EffectOnWindowStructure
keyboardKeyDownEffect =
    Common.EffectOnWindow.KeyDownEffect


keyboardKeyUpEffect : Common.EffectOnWindow.VirtualKeyCode -> Common.EffectOnWindow.EffectOnWindowStructure
keyboardKeyUpEffect =
    Common.EffectOnWindow.KeyUpEffect


effectSequenceTask :
    { delayBetweenEffectsMilliseconds : Int }
    -> List Common.EffectOnWindow.EffectOnWindowStructure
    -> Task
effectSequenceTask config effects =
    effects
        |> List.concatMap
            (\effect ->
                [ VolatileProcessInterface.EffectElement effect
                , VolatileProcessInterface.DelayInMillisecondsElement config.delayBetweenEffectsMilliseconds
                ]
            )
        |> EffectSequenceOnWindowTask


readFromWindow : GetImageDataFromReadingStructure -> Task
readFromWindow getImageData =
    getImageData
        |> sanitizeGetImageDataFromReading
        |> ReadFromWindow


getImageDataFromReading : GetImageDataFromReadingStructure -> Task
getImageDataFromReading getImageData =
    getImageData
        |> sanitizeGetImageDataFromReading
        |> GetImageDataFromReading


sanitizeGetImageDataFromReading : GetImageDataFromReadingStructure -> GetImageDataFromReadingStructure
sanitizeGetImageDataFromReading getImageData =
    let
        sanitizeAndOptimizeCrops =
            sanitizeGetImageDataFromReadingCrops
                >> optimizeGetImageDataFromReadingCrops
    in
    { crops_1x1_r8g8b8 = sanitizeAndOptimizeCrops getImageData.crops_1x1_r8g8b8
    , crops_2x2_r8g8b8 = sanitizeAndOptimizeCrops getImageData.crops_2x2_r8g8b8
    }


sanitizeGetImageDataFromReadingCrops :
    List VolatileProcessInterface.Rect2dStructure
    -> List VolatileProcessInterface.Rect2dStructure
sanitizeGetImageDataFromReadingCrops =
    List.map (rectIntersection { x = 0, y = 0, width = 9999, height = 9999 })
        >> List.filter (\rect -> 0 < rect.width && 0 < rect.height)


optimizeGetImageDataFromReadingCrops :
    List VolatileProcessInterface.Rect2dStructure
    -> List VolatileProcessInterface.Rect2dStructure
optimizeGetImageDataFromReadingCrops =
    optimizeGetImageDataFromReadingCropsRecursive


optimizeGetImageDataFromReadingCropsRecursive :
    List VolatileProcessInterface.Rect2dStructure
    -> List VolatileProcessInterface.Rect2dStructure
optimizeGetImageDataFromReadingCropsRecursive crops =
    let
        rectIntersectEnoughToConsolidate a b =
            let
                intersection =
                    rectIntersection a b
            in
            (max 0 intersection.width * max 0 intersection.height * 4)
                > min (a.width * a.height) (b.width * b.height)

        groupedCrops =
            List.Extra.gatherWith rectIntersectEnoughToConsolidate crops

        boundingBoxes =
            groupedCrops
                |> List.map
                    (\( firstCrop, otherCrops ) ->
                        otherCrops |> List.foldl rectBoundingBox firstCrop
                    )
    in
    if crops == boundingBoxes then
        boundingBoxes

    else
        optimizeGetImageDataFromReadingCropsRecursive boundingBoxes


rectIntersection : VolatileProcessInterface.Rect2dStructure -> VolatileProcessInterface.Rect2dStructure -> VolatileProcessInterface.Rect2dStructure
rectIntersection a b =
    let
        a_right =
            a.x + a.width

        b_right =
            b.x + b.width

        a_bottom =
            a.y + a.height

        b_bottom =
            b.y + b.height

        x =
            max a.x b.x

        y =
            max a.y b.y

        right =
            min a_right b_right

        bottom =
            min a_bottom b_bottom
    in
    { x = x
    , y = y
    , width = right - x
    , height = bottom - y
    }


rectBoundingBox : VolatileProcessInterface.Rect2dStructure -> VolatileProcessInterface.Rect2dStructure -> VolatileProcessInterface.Rect2dStructure
rectBoundingBox a b =
    let
        a_right =
            a.x + a.width

        b_right =
            b.x + b.width

        a_bottom =
            a.y + a.height

        b_bottom =
            b.y + b.height

        x =
            min a.x b.x

        y =
            min a.y b.y

        right =
            max a_right b_right

        bottom =
            max a_bottom b_bottom
    in
    { x = x
    , y = y
    , width = right - x
    , height = bottom - y
    }

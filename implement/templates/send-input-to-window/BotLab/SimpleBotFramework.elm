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

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Common.EffectOnWindow
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
    | BotSettingsChangedEvent String
    | SessionDurationPlannedEvent { timeInMilliseconds : Int }
    | TaskCompletedEvent CompletedTaskStructure


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
    { statusDescriptionText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias BotResponseFinishSession =
    { statusDescriptionText : String
    }


type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type TaskId
    = TaskIdFromString String


type alias Location2d =
    { x : Int, y : Int }


type MouseButton
    = MouseButtonLeft
    | MouseButtonRight


type Task
    = BringWindowToForeground
    | ReadFromWindow GetImageDataFromReadingStructure
    | GetImageDataFromReading GetImageDataFromReadingStructure
    | EffectOnWindowTask Common.EffectOnWindow.EffectOnWindowStructure


type alias State simpleBotState =
    { timeInMilliseconds : Int
    , createVolatileProcessResult :
        Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , targetWindow : Maybe { windowId : String, windowTitle : String }
    , lastReadFromWindowResult :
        Maybe
            { readFromWindowComplete : VolatileProcessInterface.ReadFromWindowCompleteStruct
            , aggregateImage : ImageStructure
            }
    , tasksInProgress : Dict.Dict String TaskInProgress
    , lastTaskIndex : Int
    , error : Maybe String
    , simpleBot : simpleBotState
    , simpleBotAggregateQueueResponse : Maybe BotResponse
    }


type alias TaskInProgress =
    { startTimeInMilliseconds : Int
    , origin : TaskToHostOrigin
    }


type FrameworkSetupStepActivity
    = StopWithResult { resultDescription : String }
    | ContinueSetupWithTask { task : InterfaceToHost.StartTaskStructure, taskDescription : String }
    | OperateSimpleBot { buildTaskFromTaskOnWindow : VolatileProcessInterface.TaskOnWindowRequestStruct -> InterfaceToHost.Task }


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
    { statusDescriptionText : String
    , startTasks : List InternalStartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias InternalStartTaskStructure =
    { taskId : InterfaceToHost.TaskId
    , task : InterfaceToHost.Task
    , taskOrigin : TaskToHostOrigin
    }


type alias GetImageDataFromReadingStructure =
    VolatileProcessInterface.GetImageDataFromReadingStructure


initState : simpleBotState -> State simpleBotState
initState simpleBotInitState =
    { timeInMilliseconds = 0
    , createVolatileProcessResult = Nothing
    , targetWindow = Nothing
    , lastReadFromWindowResult = Nothing
    , tasksInProgress = Dict.empty
    , lastTaskIndex = 0
    , error = Nothing
    , simpleBot = simpleBotInitState
    , simpleBotAggregateQueueResponse = Nothing
    }


processEvent :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> State simpleBotState
    -> ( State simpleBotState, InterfaceToHost.BotEventResponse )
processEvent simpleBotProcessEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    stateBefore
        |> integrateEvent event
        |> processEventTrackingTasksInProgress simpleBotProcessEvent event
        |> processEventAddStatusDescription


processEventAddStatusDescription : ( State simpleBotState, InterfaceToHost.BotEventResponse ) -> ( State simpleBotState, InterfaceToHost.BotEventResponse )
processEventAddStatusDescription ( state, responseBeforeAddStatusDesc ) =
    let
        frameworkStatusDescription =
            (state |> statusDescriptionFromState) ++ "\n"

        botStatusText =
            state.simpleBotAggregateQueueResponse
                |> Maybe.map
                    (\simpleBotLastResponse ->
                        case simpleBotLastResponse of
                            ContinueSession continueSession ->
                                continueSession.statusDescriptionText

                            FinishSession finishSession ->
                                finishSession.statusDescriptionText
                    )
                |> Maybe.withDefault ""

        generalStatusDescription =
            [ botStatusText
            , "--- Framework ---"
            , frameworkStatusDescription
            ]
                |> String.join "\n"

        response =
            case responseBeforeAddStatusDesc of
                InterfaceToHost.FinishSession finishSession ->
                    InterfaceToHost.FinishSession
                        { finishSession
                            | statusDescriptionText = generalStatusDescription ++ finishSession.statusDescriptionText
                        }

                InterfaceToHost.ContinueSession continueSession ->
                    InterfaceToHost.ContinueSession
                        { continueSession
                            | statusDescriptionText = generalStatusDescription ++ continueSession.statusDescriptionText
                        }
    in
    ( state, response )


processEventTrackingTasksInProgress :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> State simpleBotState
    -> ( State simpleBotState, InterfaceToHost.BotEventResponse )
processEventTrackingTasksInProgress simpleBotProcessEvent event stateBefore =
    let
        ( tasksInProgressAfterTaskCompleted, maybeCompletedBotTask ) =
            case event.eventAtTime of
                InterfaceToHost.TaskCompletedEvent taskCompletedEvent ->
                    case taskCompletedEvent.taskId of
                        InterfaceToHost.TaskIdFromString taskIdString ->
                            let
                                maybeTaskFromBot =
                                    case stateBefore.tasksInProgress |> Dict.get taskIdString of
                                        Nothing ->
                                            Nothing

                                        Just taskInProgress ->
                                            case taskInProgress.origin of
                                                BotOrigin taskIdFromBot taskFromBot ->
                                                    Just ( taskIdFromBot, taskFromBot )

                                                FrameworkOrigin ->
                                                    Nothing
                            in
                            ( stateBefore.tasksInProgress |> Dict.remove taskIdString
                            , maybeTaskFromBot
                            )

                _ ->
                    ( stateBefore.tasksInProgress, Nothing )

        tasksInProgress =
            tasksInProgressAfterTaskCompleted

        ( state, response ) =
            processEventLessTrackingTasks
                simpleBotProcessEvent
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
                                case startTask.taskId of
                                    InterfaceToHost.TaskIdFromString taskIdString ->
                                        { startTask
                                            | taskId =
                                                InterfaceToHost.TaskIdFromString
                                                    (taskIdString
                                                        ++ "-"
                                                        ++ String.fromInt
                                                            (stateBefore.lastTaskIndex
                                                                + 1
                                                                + startTaskIndex
                                                            )
                                                    )
                                        }
                            )

                lastTaskIndex =
                    stateBefore.lastTaskIndex + List.length startTasks

                newTasksInProgress =
                    startTasks
                        |> List.map
                            (\startTask ->
                                case startTask.taskId of
                                    InterfaceToHost.TaskIdFromString taskIdString ->
                                        ( taskIdString
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
                { statusDescriptionText = continueSession.statusDescriptionText
                , startTasks = startTasksForHost
                , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                }
            )


processEventLessTrackingTasks :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> Maybe ( TaskId, Task )
    -> State simpleBotState
    -> ( State simpleBotState, InternalBotEventResponse )
processEventLessTrackingTasks simpleBotProcessEvent event maybeCompletedBotTask stateBefore =
    case stateBefore.error of
        Just error ->
            ( stateBefore
            , InternalFinishSession { statusDescriptionText = "Error: " ++ error }
            )

        Nothing ->
            processEventIgnoringLastError simpleBotProcessEvent event maybeCompletedBotTask stateBefore


{-| On the relation between tasks from the bot and tasks from the framework:

For some events, it is easier to see that we should forward them to the bot immediately.
One example is bot-settings-changed: If the bot decides to finish the session in response, the response should reach the host for the same event, not later. The same applies to changes in the status text.

What about commands from the bot? If the bot says "take a screenshot" we need to wait for the completion of the framework setup (volatile process) first.
Therefore we queue tasks from the bot to forward them when we have completed the framework setup.

-}
processEventIgnoringLastError :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> Maybe ( TaskId, Task )
    -> State simpleBotState
    -> ( State simpleBotState, InternalBotEventResponse )
processEventIgnoringLastError simpleBotProcessEvent event maybeCompletedBotTask stateBefore =
    stateBefore
        |> processEventIntegrateBotEvents simpleBotProcessEvent event maybeCompletedBotTask
        |> deriveTasksAfterIntegrateBotEvents


processEventIntegrateBotEvents :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> Maybe ( TaskId, Task )
    -> State simpleBotState
    -> State simpleBotState
processEventIntegrateBotEvents simpleBotProcessEvent event maybeCompletedBotTask stateBefore =
    case simpleBotEventsFromHostEvent event maybeCompletedBotTask stateBefore of
        Err _ ->
            stateBefore

        Ok ( state, [] ) ->
            state

        Ok ( state, firstBotEvent :: otherBotEvents ) ->
            let
                ( simpleBotState, simpleBotAggregateQueueResponse ) =
                    state.simpleBot
                        |> processSequenceOfSimpleBotEventsAndCombineResponses
                            simpleBotProcessEvent
                            state.simpleBotAggregateQueueResponse
                            firstBotEvent
                            otherBotEvents
            in
            { state
                | simpleBot = simpleBotState
                , simpleBotAggregateQueueResponse = Just simpleBotAggregateQueueResponse
            }


deriveTasksAfterIntegrateBotEvents :
    State simpleBotState
    -> ( State simpleBotState, InternalBotEventResponse )
deriveTasksAfterIntegrateBotEvents stateBefore =
    if not (Dict.isEmpty stateBefore.tasksInProgress) then
        ( stateBefore
        , InternalContinueSession
            { startTasks = []
            , statusDescriptionText = "Waiting for all tasks to complete..."
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
            }
        )

    else
        case stateBefore |> getNextSetupStepWithDescriptionFromState of
            StopWithResult { resultDescription } ->
                ( stateBefore
                , InternalFinishSession
                    { statusDescriptionText = "Stopped with result: " ++ resultDescription
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
                    , statusDescriptionText = "I continue to set up the framework: Current step: " ++ continue.taskDescription
                    , notifyWhenArrivedAtTime = Nothing
                    }
                )

            OperateSimpleBot operateSimpleBot ->
                case stateBefore.simpleBotAggregateQueueResponse of
                    Nothing ->
                        ( stateBefore
                        , InternalContinueSession
                            { statusDescriptionText = "Bot not started yet."
                            , startTasks = []
                            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 1000 }
                            }
                        )

                    Just (FinishSession finishSession) ->
                        ( stateBefore
                        , InternalFinishSession
                            { statusDescriptionText = "Bot finished the session: " ++ finishSession.statusDescriptionText }
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
                                                        |> taskOnWindowFromSimpleBotTask stateBefore
                                                        |> operateSimpleBot.buildTaskFromTaskOnWindow
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
                            { statusDescriptionText = "Operate bot"
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
    InterfaceToHost.BotEvent
    -> Maybe ( TaskId, Task )
    -> State simpleBotState
    -> Result String ( State simpleBotState, List BotEvent )
simpleBotEventsFromHostEvent event maybeCompletedBotTask stateBefore =
    simpleBotEventsFromHostEventAtTime event.eventAtTime maybeCompletedBotTask stateBefore
        |> Result.map
            (Tuple.mapSecond
                (List.map
                    (\eventAtTime ->
                        { timeInMilliseconds = event.timeInMilliseconds, eventAtTime = eventAtTime }
                    )
                )
            )


simpleBotEventsFromHostEventAtTime :
    InterfaceToHost.BotEventAtTime
    -> Maybe ( TaskId, Task )
    -> State simpleBotState
    -> Result String ( State simpleBotState, List BotEventAtTime )
simpleBotEventsFromHostEventAtTime event maybeCompletedBotTask stateBefore =
    case event of
        InterfaceToHost.TimeArrivedEvent ->
            Ok ( stateBefore, [ TimeArrivedEvent ] )

        InterfaceToHost.BotSettingsChangedEvent settingsString ->
            Ok ( stateBefore, [ BotSettingsChangedEvent settingsString ] )

        InterfaceToHost.SessionDurationPlannedEvent sessionDurationPlannedEvent ->
            Ok ( stateBefore, [ SessionDurationPlannedEvent sessionDurationPlannedEvent ] )

        InterfaceToHost.TaskCompletedEvent completedTask ->
            let
                taskIdString =
                    case completedTask.taskId of
                        InterfaceToHost.TaskIdFromString taskIdStringHost ->
                            taskIdStringHost
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
                                                                        VolatileProcessInterface.TaskOnWindowResponse taskOnWindowResponse ->
                                                                            case taskOnWindowResponse.result of
                                                                                VolatileProcessInterface.WindowNotFound ->
                                                                                    Err "WindowNotFound"

                                                                                VolatileProcessInterface.ReadingNotFound ->
                                                                                    Err "ReadingNotFound"

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

                                                                EffectOnWindowTask _ ->
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
    (BotEvent
     -> simpleBotState
     -> ( simpleBotState, BotResponse )
    )
    -> Maybe BotResponse
    -> BotEvent
    -> List BotEvent
    -> simpleBotState
    -> ( simpleBotState, BotResponse )
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


taskIdFromSimpleBotTaskId : TaskId -> InterfaceToHost.TaskId
taskIdFromSimpleBotTaskId simpleBotTaskId =
    case simpleBotTaskId of
        TaskIdFromString asString ->
            InterfaceToHost.taskIdFromString ("bot-" ++ asString)


taskOnWindowFromSimpleBotTask : State simpleBotState -> Task -> VolatileProcessInterface.TaskOnWindowRequestStruct
taskOnWindowFromSimpleBotTask state simpleBotTask =
    case simpleBotTask of
        BringWindowToForeground ->
            VolatileProcessInterface.BringWindowToForeground

        ReadFromWindow readFromWindowTask ->
            VolatileProcessInterface.ReadFromWindowRequest
                { getImageData = readFromWindowTask }

        GetImageDataFromReading getImageDataFromReadingTask ->
            case state.lastReadFromWindowResult of
                Nothing ->
                    VolatileProcessInterface.ReadFromWindowRequest
                        { getImageData = getImageDataFromReadingTask }

                Just lastReadFromWindowResult ->
                    VolatileProcessInterface.GetImageDataFromReadingRequest
                        { readingId = lastReadFromWindowResult.readFromWindowComplete.readingId
                        , getImageData = getImageDataFromReadingTask
                        }

        EffectOnWindowTask effectOnWindowTask ->
            effectOnWindowTask
                |> VolatileProcessInterface.EffectOnWindowRequest


integrateEvent : InterfaceToHost.BotEvent -> State simpleBotState -> State simpleBotState
integrateEvent event stateBefore =
    case event.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            stateBefore

        InterfaceToHost.BotSettingsChangedEvent _ ->
            stateBefore

        InterfaceToHost.TaskCompletedEvent { taskId, taskResult } ->
            integrateEventTaskComplete taskId taskResult stateBefore

        InterfaceToHost.SessionDurationPlannedEvent _ ->
            stateBefore


integrateEventTaskComplete : InterfaceToHost.TaskId -> InterfaceToHost.TaskResultStructure -> State simpleBotState -> State simpleBotState
integrateEventTaskComplete taskId taskResult stateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResult ->
            { stateBefore | createVolatileProcessResult = Just createVolatileProcessResult }

        InterfaceToHost.RequestToVolatileProcessResponse requestToVolatileProcessResponse ->
            case requestToVolatileProcessResponse of
                Err InterfaceToHost.ProcessNotFound ->
                    { stateBefore | error = Just "Error running script in volatile process: ProcessNotFound" }

                Err InterfaceToHost.FailedToAcquireInputFocus ->
                    { stateBefore | error = Just "Error running script in volatile process: FailedToAcquireInputFocus" }

                Ok runInVolatileProcessComplete ->
                    case runInVolatileProcessComplete.returnValueToString of
                        Nothing ->
                            { stateBefore | error = Just ("Error in volatile process: " ++ (runInVolatileProcessComplete.exceptionToString |> Maybe.withDefault "")) }

                        Just returnValueToString ->
                            case stateBefore.createVolatileProcessResult of
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


statusDescriptionFromState : State simpleBotState -> String
statusDescriptionFromState state =
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


getNextSetupStepWithDescriptionFromState : State simpleBotState -> FrameworkSetupStepActivity
getNextSetupStepWithDescriptionFromState state =
    case state.createVolatileProcessResult of
        Nothing ->
            { task =
                { taskId = InterfaceToHost.taskIdFromString "create_volatile_process"
                , task = InterfaceToHost.CreateVolatileProcess { programCode = CompilationInterface.SourceFiles.file____Windows_VolatileProcess_cx.utf8 }
                }
            , taskDescription = "Set up the volatile process. This can take several seconds, especially when assemblies are not cached yet."
            }
                |> ContinueSetupWithTask

        Just (Err createVolatileProcessError) ->
            StopWithResult { resultDescription = "Failed to create volatile process: " ++ createVolatileProcessError.exceptionToString }

        Just (Ok createVolatileProcessCompleted) ->
            case state.targetWindow of
                Nothing ->
                    let
                        task =
                            InterfaceToHost.RequestToVolatileProcess
                                (InterfaceToHost.RequestNotRequiringInputFocus
                                    { processId = createVolatileProcessCompleted.processId
                                    , request =
                                        VolatileProcessInterface.ListWindowsRequest
                                            |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                    }
                                )
                    in
                    { task = { taskId = InterfaceToHost.taskIdFromString "list_windows", task = task }
                    , taskDescription = "List windows"
                    }
                        |> ContinueSetupWithTask

                Just targetWindow ->
                    OperateSimpleBot
                        { buildTaskFromTaskOnWindow =
                            \taskOnWindow ->
                                InterfaceToHost.RequestToVolatileProcess
                                    (InterfaceToHost.RequestNotRequiringInputFocus
                                        { processId = createVolatileProcessCompleted.processId
                                        , request =
                                            { windowId = targetWindow.windowId, task = taskOnWindow }
                                                |> VolatileProcessInterface.TaskOnWindowRequest
                                                |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                        }
                                    )
                        }


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


volatileProcessKeyFromMouseButton : MouseButton -> Common.EffectOnWindow.VirtualKeyCode
volatileProcessKeyFromMouseButton mouseButton =
    case mouseButton of
        MouseButtonLeft ->
            Common.EffectOnWindow.vkey_LBUTTON

        MouseButtonRight ->
            Common.EffectOnWindow.vkey_RBUTTON


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


setMouseCursorPositionTask : Location2d -> Task
setMouseCursorPositionTask =
    Common.EffectOnWindow.SetMouseCursorPositionEffect
        >> EffectOnWindowTask


mouseButtonDownTask : MouseButton -> Task
mouseButtonDownTask =
    volatileProcessKeyFromMouseButton
        >> Common.EffectOnWindow.KeyDownEffect
        >> EffectOnWindowTask


mouseButtonUpTask : MouseButton -> Task
mouseButtonUpTask =
    volatileProcessKeyFromMouseButton
        >> Common.EffectOnWindow.KeyUpEffect
        >> EffectOnWindowTask


keyboardKeyDownTask : Common.EffectOnWindow.VirtualKeyCode -> Task
keyboardKeyDownTask =
    Common.EffectOnWindow.KeyDownEffect
        >> EffectOnWindowTask


keyboardKeyUpTask : Common.EffectOnWindow.VirtualKeyCode -> Task
keyboardKeyUpTask =
    Common.EffectOnWindow.KeyUpEffect
        >> EffectOnWindowTask


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


mouseButtonLeft : MouseButton
mouseButtonLeft =
    MouseButtonLeft


mouseButtonRight : MouseButton
mouseButtonRight =
    MouseButtonRight


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

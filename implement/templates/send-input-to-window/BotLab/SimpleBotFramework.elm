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
import CompilationInterface.SourceFiles
import Dict
import Json.Decode
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
    | TakeScreenshotResult ImageStructure


type alias ImageStructure =
    { imageWidth : Int
    , imageHeight : Int
    , imageAsDict : Dict.Dict ( Int, Int ) PixelValue
    , imageBinned2x2AsDict : Dict.Dict ( Int, Int ) PixelValue
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


type KeyboardKey
    = KeyboardKeyFromVirtualKeyCode Int


type Task
    = BringWindowToForeground
    | MoveMouseToLocation Location2d
    | MouseButtonDown MouseButton
    | MouseButtonUp MouseButton
    | KeyboardKeyDown KeyboardKey
    | KeyboardKeyUp KeyboardKey
    | TakeScreenshot


type alias State simpleBotState =
    { timeInMilliseconds : Int
    , createVolatileProcessResult :
        Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , windowId : Maybe VolatileProcessInterface.WindowId
    , lastWindowTitleMeasurement : Maybe { timeInMilliseconds : Int, windowTitle : String }
    , tasksInProgress :
        Dict.Dict
            String
            { startTimeInMilliseconds : Int
            , origin : TaskToHostOrigin
            }
    , lastTaskIndex : Int
    , error : Maybe String
    , simpleBot : simpleBotState
    , simpleBotAggregateQueueResponse : Maybe BotResponse
    }


type FrameworkSetupStepActivity
    = StopWithResult { resultDescription : String }
    | ContinueSetupWithTask { task : InterfaceToHost.StartTaskStructure, taskDescription : String }
    | OperateSimpleBot { buildTaskFromTaskOnWindow : VolatileProcessInterface.TaskOnWindowStructure -> InterfaceToHost.Task }


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


initState : simpleBotState -> State simpleBotState
initState simpleBotInitState =
    { timeInMilliseconds = 0
    , createVolatileProcessResult = Nothing
    , windowId = Nothing
    , lastWindowTitleMeasurement = Nothing
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
        ( stateBeforeRemoveTasks, response ) =
            processEventLessTrackingTasks simpleBotProcessEvent event stateBefore

        tasksInProgressAfterTaskCompleted =
            case event.eventAtTime of
                InterfaceToHost.TaskCompletedEvent taskCompletedEvent ->
                    case taskCompletedEvent.taskId of
                        InterfaceToHost.TaskIdFromString taskIdString ->
                            stateBeforeRemoveTasks.tasksInProgress
                                |> Dict.remove taskIdString

                _ ->
                    stateBeforeRemoveTasks.tasksInProgress

        tasksInProgress =
            tasksInProgressAfterTaskCompleted

        state =
            { stateBeforeRemoveTasks
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
    -> State simpleBotState
    -> ( State simpleBotState, InternalBotEventResponse )
processEventLessTrackingTasks simpleBotProcessEvent event stateBefore =
    case stateBefore.error of
        Just error ->
            ( stateBefore
            , InternalFinishSession { statusDescriptionText = "Error: " ++ error }
            )

        Nothing ->
            processEventIgnoringLastError simpleBotProcessEvent event stateBefore


{-| On the relation between tasks from the bot and tasks from the framework:

For some events, it is easier to see that we should forward them to the bot immediately.
One example is bot-settings-changed: If the bot decides to finish the session in response, the response should reach the host for the same event, not later. The same applies to changes in the status text.

What about commands from the bot? If the bot says "take a screenshot" we need to wait for the completion of the framework setup (volatile process) first.
Therefore we queue tasks from the bot to forward them when we have completed the framework setup.

-}
processEventIgnoringLastError :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> State simpleBotState
    -> ( State simpleBotState, InternalBotEventResponse )
processEventIgnoringLastError simpleBotProcessEvent event stateBefore =
    stateBefore
        |> processEventIntegrateBotEvents simpleBotProcessEvent event
        |> processEventAfterIntegrateBotEvents simpleBotProcessEvent event


processEventIntegrateBotEvents :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> State simpleBotState
    -> State simpleBotState
processEventIntegrateBotEvents simpleBotProcessEvent event stateBefore =
    case simpleBotEventsFromHostEvent event stateBefore of
        Err _ ->
            stateBefore

        Ok [] ->
            stateBefore

        Ok (firstBotEvent :: otherBotEvents) ->
            let
                ( simpleBotState, simpleBotAggregateQueueResponse ) =
                    stateBefore.simpleBot
                        |> processSequenceOfSimpleBotEventsAndCombineResponses
                            simpleBotProcessEvent
                            stateBefore.simpleBotAggregateQueueResponse
                            firstBotEvent
                            otherBotEvents
            in
            { stateBefore
                | simpleBot = simpleBotState
                , simpleBotAggregateQueueResponse = Just simpleBotAggregateQueueResponse
            }


processEventAfterIntegrateBotEvents :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> State simpleBotState
    -> ( State simpleBotState, InternalBotEventResponse )
processEventAfterIntegrateBotEvents simpleBotProcessEvent event stateBefore =
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
                                                        |> taskOnWindowFromSimpleBotTask
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
        areRedundant taskA taskB =
            case ( taskA, taskB ) of
                ( TakeScreenshot, TakeScreenshot ) ->
                    True

                _ ->
                    False
    in
    List.foldl
        (\startTask aggregate ->
            if aggregate |> List.map .task |> List.any (areRedundant startTask.task) then
                aggregate

            else
                aggregate ++ [ startTask ]
        )
        []


simpleBotEventsFromHostEvent :
    InterfaceToHost.BotEvent
    -> State simpleBotState
    -> Result String (List BotEvent)
simpleBotEventsFromHostEvent event stateBefore =
    simpleBotEventsFromHostEventAtTime event.eventAtTime stateBefore
        |> Result.map
            (List.map (\eventAtTime -> { timeInMilliseconds = event.timeInMilliseconds, eventAtTime = eventAtTime }))


simpleBotEventsFromHostEventAtTime :
    InterfaceToHost.BotEventAtTime
    -> State simpleBotState
    -> Result String (List BotEventAtTime)
simpleBotEventsFromHostEventAtTime event stateBefore =
    case event of
        InterfaceToHost.TimeArrivedEvent ->
            Ok [ TimeArrivedEvent ]

        InterfaceToHost.BotSettingsChangedEvent settingsString ->
            Ok [ BotSettingsChangedEvent settingsString ]

        InterfaceToHost.SessionDurationPlannedEvent sessionDurationPlannedEvent ->
            Ok [ SessionDurationPlannedEvent sessionDurationPlannedEvent ]

        InterfaceToHost.TaskCompletedEvent completedTask ->
            let
                taskIdString =
                    case completedTask.taskId of
                        InterfaceToHost.TaskIdFromString taskIdStringHost ->
                            taskIdStringHost
            in
            case stateBefore.tasksInProgress |> Dict.get taskIdString of
                Nothing ->
                    Err ("Failed to remember task with ID " ++ taskIdString)

                Just taskInProgress ->
                    case taskInProgress.origin of
                        FrameworkOrigin ->
                            Err ("Task ID mismatch: Found framework task for ID " ++ taskIdString)

                        BotOrigin simpleBotTaskId simpleBotTask ->
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
                                                                    case simpleBotTask of
                                                                        BringWindowToForeground ->
                                                                            Ok NoResultValue

                                                                        MoveMouseToLocation _ ->
                                                                            Ok NoResultValue

                                                                        MouseButtonDown _ ->
                                                                            Ok NoResultValue

                                                                        MouseButtonUp _ ->
                                                                            Ok NoResultValue

                                                                        KeyboardKeyDown _ ->
                                                                            Ok NoResultValue

                                                                        KeyboardKeyUp _ ->
                                                                            Ok NoResultValue

                                                                        TakeScreenshot ->
                                                                            case parsedResponse of
                                                                                VolatileProcessInterface.TakeScreenshotResult takeScreenshotResult ->
                                                                                    Ok
                                                                                        (TakeScreenshotResult (deriveImageRepresentation takeScreenshotResult.pixels))

                                                                                _ ->
                                                                                    Err ("Unexpected return value from volatile process: " ++ (volatileProcessResponseSuccess.returnValueToString |> Maybe.withDefault ""))
                            in
                            case taskResultResult of
                                Err error ->
                                    Err ("Unexpected task result: " ++ error)

                                Ok taskResultOk ->
                                    Ok
                                        [ TaskCompletedEvent { taskId = simpleBotTaskId, taskResult = taskResultOk } ]


deriveImageRepresentation : List (List PixelValue) -> ImageStructure
deriveImageRepresentation imageAsNestedList =
    let
        imageWidths =
            imageAsNestedList |> List.map List.length

        imageWidth =
            imageWidths |> List.maximum |> Maybe.withDefault 0

        imageHeight =
            imageWidths |> List.length

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
    { imageWidth = imageWidth
    , imageHeight = imageHeight
    , imageAsDict = imageAsDict
    , imageBinned2x2AsDict = imageBinned2x2AsDict
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


taskOnWindowFromSimpleBotTask : Task -> VolatileProcessInterface.TaskOnWindowStructure
taskOnWindowFromSimpleBotTask simpleBotTask =
    case simpleBotTask of
        BringWindowToForeground ->
            VolatileProcessInterface.BringWindowToForeground

        MoveMouseToLocation location ->
            VolatileProcessInterface.MoveMouseToLocation location

        MouseButtonDown button ->
            VolatileProcessInterface.MouseButtonDown
                (volatileProcessMouseButtonFromMouseButton button)

        MouseButtonUp button ->
            VolatileProcessInterface.MouseButtonUp
                (volatileProcessMouseButtonFromMouseButton button)

        KeyboardKeyDown key ->
            VolatileProcessInterface.KeyboardKeyDown
                (volatileProcessKeyboardKeyFromKeyboardKey key)

        KeyboardKeyUp key ->
            VolatileProcessInterface.KeyboardKeyUp
                (volatileProcessKeyboardKeyFromKeyboardKey key)

        TakeScreenshot ->
            VolatileProcessInterface.TakeScreenshot


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
                                            case stateBefore.windowId of
                                                Nothing ->
                                                    case responseFromVolatileProcess of
                                                        VolatileProcessInterface.GetForegroundWindowResult windowId ->
                                                            { stateBefore | windowId = Just windowId }

                                                        _ ->
                                                            { stateBefore | error = Just ("Unexpected response from volatile process: " ++ returnValueToString) }

                                                Just windowId ->
                                                    case responseFromVolatileProcess of
                                                        VolatileProcessInterface.GetWindowTextResult windowText ->
                                                            { stateBefore
                                                                | lastWindowTitleMeasurement = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, windowTitle = windowText }
                                                            }

                                                        _ ->
                                                            stateBefore

        InterfaceToHost.CompleteWithoutResult ->
            stateBefore


statusDescriptionFromState : State simpleBotState -> String
statusDescriptionFromState state =
    let
        portionWindow =
            case state.lastWindowTitleMeasurement of
                Nothing ->
                    ""

                Just { windowTitle } ->
                    "I work in the window with title '" ++ windowTitle ++ "'."

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
                        ++ " tasks from bot in queue"
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
            case state.windowId of
                Nothing ->
                    let
                        task =
                            InterfaceToHost.RequestToVolatileProcess
                                (InterfaceToHost.RequestNotRequiringInputFocus
                                    { processId = createVolatileProcessCompleted.processId
                                    , request =
                                        VolatileProcessInterface.GetForegroundWindow
                                            |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                    }
                                )
                    in
                    { task = { taskId = InterfaceToHost.taskIdFromString "get_foreground_window", task = task }
                    , taskDescription = "Get foreground window"
                    }
                        |> ContinueSetupWithTask

                Just windowId ->
                    case state.lastWindowTitleMeasurement of
                        Nothing ->
                            let
                                task =
                                    InterfaceToHost.RequestToVolatileProcess
                                        (InterfaceToHost.RequestNotRequiringInputFocus
                                            { processId = createVolatileProcessCompleted.processId
                                            , request =
                                                windowId
                                                    |> VolatileProcessInterface.GetWindowText
                                                    |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                            }
                                        )
                            in
                            { task = { taskId = InterfaceToHost.taskIdFromString "get_window_title", task = task }
                            , taskDescription = "Get window title"
                            }
                                |> ContinueSetupWithTask

                        Just { windowTitle } ->
                            OperateSimpleBot
                                { buildTaskFromTaskOnWindow =
                                    \taskOnWindow ->
                                        InterfaceToHost.RequestToVolatileProcess
                                            (InterfaceToHost.RequestNotRequiringInputFocus
                                                { processId = createVolatileProcessCompleted.processId
                                                , request =
                                                    { windowId = windowId, task = taskOnWindow }
                                                        |> VolatileProcessInterface.TaskOnWindow
                                                        |> VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                                }
                                            )
                                }


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


volatileProcessMouseButtonFromMouseButton : MouseButton -> VolatileProcessInterface.MouseButton
volatileProcessMouseButtonFromMouseButton mouseButton =
    case mouseButton of
        MouseButtonLeft ->
            VolatileProcessInterface.MouseButtonLeft

        MouseButtonRight ->
            VolatileProcessInterface.MouseButtonRight


volatileProcessKeyboardKeyFromKeyboardKey : KeyboardKey -> VolatileProcessInterface.KeyboardKey
volatileProcessKeyboardKeyFromKeyboardKey keyboardKey =
    case keyboardKey of
        KeyboardKeyFromVirtualKeyCode keyCode ->
            VolatileProcessInterface.KeyboardKeyFromVirtualKeyCode keyCode


dictWithTupleKeyFromIndicesInNestedList : List (List element) -> Dict.Dict ( Int, Int ) element
dictWithTupleKeyFromIndicesInNestedList nestedList =
    nestedList
        |> List.indexedMap
            (\rowIndex list ->
                list
                    |> List.indexedMap
                        (\columnIndex element ->
                            ( ( columnIndex, rowIndex ), element )
                        )
            )
        |> List.concat
        |> Dict.fromList


bringWindowToForeground : Task
bringWindowToForeground =
    BringWindowToForeground


moveMouseToLocation : Location2d -> Task
moveMouseToLocation =
    MoveMouseToLocation


mouseButtonDown : MouseButton -> Task
mouseButtonDown =
    MouseButtonDown


mouseButtonUp : MouseButton -> Task
mouseButtonUp =
    MouseButtonUp


keyboardKeyDown : KeyboardKey -> Task
keyboardKeyDown =
    KeyboardKeyDown


keyboardKeyUp : KeyboardKey -> Task
keyboardKeyUp =
    KeyboardKeyUp


takeScreenshot : Task
takeScreenshot =
    TakeScreenshot


mouseButtonLeft : MouseButton
mouseButtonLeft =
    MouseButtonLeft


mouseButtonRight : MouseButton
mouseButtonRight =
    MouseButtonRight


{-| For documentation of virtual key codes, see <https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes>
-}
keyboardKeyFromVirtualKeyCode : Int -> KeyboardKey
keyboardKeyFromVirtualKeyCode =
    KeyboardKeyFromVirtualKeyCode


keyboardKey_space : KeyboardKey
keyboardKey_space =
    keyboardKeyFromVirtualKeyCode 0x20

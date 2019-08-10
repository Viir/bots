{-
   This bot framework takes care of:

   + Identify the window the bot should work.
   + Set up the volatile host to interface with Windows.
   + Map typical tasks to the Windows API.

   To use this framework:

   + Wrap you bots `processEvent` function with `SimpleBotFramework.processEvent`.
   + Wrap you bots `initState` function with `SimpleBotFramework.initState`.
-}


module SimpleBotFramework exposing
    ( BotEvent(..)
    , BotResponse(..)
    , EffectOnWindowStructure(..)
    , KeyboardKey(..)
    , MouseButton(..)
    , State
    , Task(..)
    , TaskId
    , initState
    , processEvent
    , taskIdFromString
    )

import Interface_To_Host_20190808 as InterfaceToHost
import Json.Decode
import VolatileHostWindowsApi


type BotEvent
    = ArrivedAtTime { timeInMilliseconds : Int }
    | SetBotConfiguration String
    | SetSessionTimeLimit { timeInMilliseconds : Int }
    | CompletedTask CompletedTaskStructure


type BotResponse
    = ContinueSession BotResponseContinueSession
    | FinishSession BotResponseFinishSession


type alias CompletedTaskStructure =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type alias TaskResultStructure =
    {}


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


type Task
    = EffectOnWindow EffectOnWindowStructure
    | TakeScreenshot


type alias Location2d =
    VolatileHostWindowsApi.Location2d


type MouseButton
    = MouseButtonLeft
    | MouseButtonRight


type KeyboardKey
    = KeyboardKeyFromVirtualKeyCode Int
    | VK_SPACE


type EffectOnWindowStructure
    = BringWindowToForeground
    | MoveMouseToLocation Location2d
    | MouseButtonDown MouseButton
    | MouseButtonUp MouseButton
    | KeyboardKeyDown KeyboardKey
    | KeyboardKeyUp KeyboardKey


type alias State simpleBotState =
    { timeInMilliseconds : Int
    , volatileHost : Maybe VolatileHostState
    , windowId : Maybe VolatileHostWindowsApi.WindowId
    , lastWindowTitleMeasurement : Maybe { timeInMilliseconds : Int, windowTitle : String }
    , waitingForTaskId : Maybe InterfaceToHost.TaskId
    , error : Maybe String
    , configuration : Maybe String
    , simpleBotInitState : simpleBotState
    , simpleBot : Maybe simpleBotState
    , simpleBotLastResponse : Maybe BotResponse
    , simpleBotTasksInProgress : List ( InterfaceToHost.TaskId, TaskId )
    }


type VolatileHostState
    = Initial { volatileHostId : InterfaceToHost.VolatileHostId }
    | SetupCompleted { volatileHostId : InterfaceToHost.VolatileHostId }


type FrameworkSetupStepActivity
    = StopWithResult { resultDescription : String }
    | ContinueSetupWithTask { task : InterfaceToHost.StartTaskStructure, taskDescription : String }
    | OperateSimpleBot { buildTaskFromTaskOnWindow : VolatileHostWindowsApi.TaskOnWindowStructure -> InterfaceToHost.Task }


initState : simpleBotState -> State simpleBotState
initState simpleBotInitState =
    { timeInMilliseconds = 0
    , volatileHost = Nothing
    , windowId = Nothing
    , lastWindowTitleMeasurement = Nothing
    , waitingForTaskId = Nothing
    , error = Nothing
    , configuration = Nothing
    , simpleBotInitState = simpleBotInitState
    , simpleBot = Nothing
    , simpleBotLastResponse = Nothing
    , simpleBotTasksInProgress = []
    }


processEvent :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.BotEvent
    -> State simpleBotState
    -> ( State simpleBotState, InterfaceToHost.BotResponse )
processEvent simpleBotProcessEvent event stateBefore =
    let
        state =
            stateBefore |> integrateEvent event

        generalStatusDescription =
            (state |> statusDescriptionFromState) ++ "\n"
    in
    case stateBefore.error of
        Just error ->
            ( state, InterfaceToHost.FinishSession { statusDescriptionText = generalStatusDescription ++ "Error: " ++ error } )

        Nothing ->
            case state |> getNextSetupStepWithDescriptionFromState of
                StopWithResult { resultDescription } ->
                    ( state
                    , InterfaceToHost.FinishSession
                        { statusDescriptionText = generalStatusDescription ++ "Stopped with result: " ++ resultDescription
                        }
                    )

                ContinueSetupWithTask continue ->
                    ( state
                    , InterfaceToHost.ContinueSession
                        { startTasks = [ continue.task ]
                        , statusDescriptionText = generalStatusDescription ++ "I continue to set up the framework: Current step: " ++ continue.taskDescription
                        , notifyWhenArrivedAtTime = Nothing
                        }
                    )

                OperateSimpleBot { buildTaskFromTaskOnWindow } ->
                    let
                        ( simpleBotStateBefore, simpleBotEventsBefore ) =
                            case state.simpleBot of
                                Nothing ->
                                    let
                                        configurationEvents =
                                            case state.configuration of
                                                Nothing ->
                                                    []

                                                Just configuration ->
                                                    [ SetBotConfiguration configuration ]
                                    in
                                    ( stateBefore.simpleBotInitState
                                    , configurationEvents
                                        ++ [ ArrivedAtTime { timeInMilliseconds = state.timeInMilliseconds } ]
                                    )

                                Just simpleBot ->
                                    ( simpleBot, [] )

                        simpleBotLastResponseNotifyWhenArrivedAtTime =
                            case state.simpleBotLastResponse of
                                Nothing ->
                                    Nothing

                                Just (ContinueSession simpleBotLastResponseContinue) ->
                                    simpleBotLastResponseContinue.notifyWhenArrivedAtTime

                                Just (FinishSession _) ->
                                    Nothing

                        arriveAtTimeEvents =
                            case simpleBotLastResponseNotifyWhenArrivedAtTime of
                                Nothing ->
                                    []

                                Just notifyWhenArrivedAtTime ->
                                    if notifyWhenArrivedAtTime.timeInMilliseconds <= state.timeInMilliseconds then
                                        [ ArrivedAtTime { timeInMilliseconds = state.timeInMilliseconds } ]

                                    else
                                        []

                        ( simpleBotEventsFromCurrentEvent, simpleBotTasksInProgressAfterRemoval ) =
                            case event of
                                InterfaceToHost.ArrivedAtTime arrivedAtTime ->
                                    ( [], state.simpleBotTasksInProgress )

                                InterfaceToHost.SetBotConfiguration setBotConfiguration ->
                                    ( [ SetBotConfiguration setBotConfiguration ], state.simpleBotTasksInProgress )

                                InterfaceToHost.SetSessionTimeLimit setSessionTimeLimit ->
                                    ( [ SetSessionTimeLimit setSessionTimeLimit ], state.simpleBotTasksInProgress )

                                InterfaceToHost.CompletedTask completedTask ->
                                    case state.simpleBotTasksInProgress |> List.filter (\( key, _ ) -> key == completedTask.taskId) |> List.head of
                                        Nothing ->
                                            ( [], state.simpleBotTasksInProgress )

                                        Just ( completedTaskInterfaceId, simpleBotTaskId ) ->
                                            ( [ CompletedTask { taskId = simpleBotTaskId, taskResult = {} } ]
                                            , state.simpleBotTasksInProgress
                                                |> List.filter
                                                    (Tuple.first >> (/=) completedTaskInterfaceId)
                                            )

                        ( simpleBotState, simpleBotResponse ) =
                            simpleBotStateBefore
                                |> processSequenceOfSimpleBotEventsAndCombineResponses
                                    simpleBotProcessEvent
                                    (simpleBotEventsBefore ++ arriveAtTimeEvents ++ simpleBotEventsFromCurrentEvent)

                        simpleBotLastResponse =
                            [ simpleBotResponse, state.simpleBotLastResponse ]
                                |> List.filterMap identity
                                |> List.head

                        ( response, simpleBotTasksInProgress ) =
                            case simpleBotLastResponse of
                                Nothing ->
                                    ( InterfaceToHost.ContinueSession
                                        { statusDescriptionText = generalStatusDescription ++ "Operate bot:\nNo response from bot so far."
                                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = state.timeInMilliseconds + 1000 }
                                        , startTasks = []
                                        }
                                    , simpleBotTasksInProgressAfterRemoval
                                    )

                                Just (ContinueSession continueSession) ->
                                    let
                                        startTasks =
                                            continueSession.startTasks
                                                |> List.map
                                                    (\simpleBotTaskWithId ->
                                                        ( { taskId = simpleBotTaskWithId.taskId |> taskIdFromSimpleBotTaskId
                                                          , task = simpleBotTaskWithId.task |> taskOnWindowFromSimpleBotTask |> buildTaskFromTaskOnWindow
                                                          }
                                                        , simpleBotTaskWithId
                                                        )
                                                    )

                                        addedSimpleBotTasksInProgress =
                                            startTasks
                                                |> List.map
                                                    (\( interfaceStartTask, simpleBotStartTask ) ->
                                                        ( interfaceStartTask.taskId, simpleBotStartTask.taskId )
                                                    )
                                    in
                                    ( InterfaceToHost.ContinueSession
                                        { statusDescriptionText = generalStatusDescription ++ "Operate bot:\n" ++ continueSession.statusDescriptionText
                                        , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                                        , startTasks = startTasks |> List.map Tuple.first
                                        }
                                    , simpleBotTasksInProgressAfterRemoval ++ addedSimpleBotTasksInProgress
                                    )

                                Just (FinishSession finishSession) ->
                                    ( InterfaceToHost.FinishSession
                                        { statusDescriptionText = generalStatusDescription ++ "Finish session: " ++ finishSession.statusDescriptionText
                                        }
                                    , simpleBotTasksInProgressAfterRemoval
                                    )
                    in
                    ( { state
                        | simpleBot = Just simpleBotState
                        , simpleBotLastResponse = simpleBotLastResponse
                        , simpleBotTasksInProgress = simpleBotTasksInProgress
                      }
                    , response
                    )


processSequenceOfSimpleBotEventsAndCombineResponses : (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse )) -> List BotEvent -> simpleBotState -> ( simpleBotState, Maybe BotResponse )
processSequenceOfSimpleBotEventsAndCombineResponses simpleBotProcessEvent events botStateBefore =
    case events of
        [] ->
            ( botStateBefore, Nothing )

        nextEvent :: followingEvents ->
            let
                ( nextBotState, nextBotResponse ) =
                    botStateBefore |> simpleBotProcessEvent nextEvent
            in
            case nextBotResponse of
                FinishSession _ ->
                    ( nextBotState, Just nextBotResponse )

                ContinueSession nextBotResponseContinue ->
                    let
                        ( followingBotState, followingBotResponse ) =
                            nextBotState
                                |> processSequenceOfSimpleBotEventsAndCombineResponses simpleBotProcessEvent followingEvents

                        combinedResponse =
                            case followingBotResponse of
                                Nothing ->
                                    nextBotResponse

                                Just (ContinueSession followingContinueSession) ->
                                    let
                                        startTasks =
                                            nextBotResponseContinue.startTasks ++ followingContinueSession.startTasks
                                    in
                                    ContinueSession
                                        { startTasks = startTasks
                                        , notifyWhenArrivedAtTime = followingContinueSession.notifyWhenArrivedAtTime
                                        , statusDescriptionText = followingContinueSession.statusDescriptionText
                                        }

                                Just (FinishSession finishSession) ->
                                    FinishSession finishSession
                    in
                    ( followingBotState, Just combinedResponse )


taskIdFromSimpleBotTaskId : TaskId -> InterfaceToHost.TaskId
taskIdFromSimpleBotTaskId simpleBotTaskId =
    case simpleBotTaskId of
        TaskIdFromString asString ->
            InterfaceToHost.taskIdFromString ("simple-bot-" ++ asString)


taskOnWindowFromSimpleBotTask : Task -> VolatileHostWindowsApi.TaskOnWindowStructure
taskOnWindowFromSimpleBotTask simpleBotTask =
    case simpleBotTask of
        EffectOnWindow effectOnWindow ->
            case effectOnWindow of
                BringWindowToForeground ->
                    VolatileHostWindowsApi.BringWindowToForeground

                MoveMouseToLocation location ->
                    VolatileHostWindowsApi.MoveMouseToLocation location

                MouseButtonDown button ->
                    VolatileHostWindowsApi.MouseButtonDown
                        (volatileHostMouseButtonFromMouseButton button)

                MouseButtonUp button ->
                    VolatileHostWindowsApi.MouseButtonUp
                        (volatileHostMouseButtonFromMouseButton button)

                KeyboardKeyDown key ->
                    VolatileHostWindowsApi.KeyboardKeyDown
                        (volatileHostKeyboardKeyFromKeyboardKey key)

                KeyboardKeyUp key ->
                    VolatileHostWindowsApi.KeyboardKeyUp
                        (volatileHostKeyboardKeyFromKeyboardKey key)

        TakeScreenshot ->
            VolatileHostWindowsApi.TakeScreenshot


integrateEvent : InterfaceToHost.BotEvent -> State simpleBotState -> State simpleBotState
integrateEvent event stateBefore =
    case event of
        InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
            { stateBefore | timeInMilliseconds = timeInMilliseconds }

        InterfaceToHost.SetBotConfiguration configuration ->
            { stateBefore | configuration = Just configuration }

        InterfaceToHost.CompletedTask { taskId, taskResult } ->
            case taskResult of
                InterfaceToHost.CreateVolatileHostResponse createVolatileHostResponse ->
                    case createVolatileHostResponse of
                        Err _ ->
                            { stateBefore | error = Just "Failed to create volatile host." }

                        Ok { hostId } ->
                            { stateBefore | volatileHost = Just (Initial { volatileHostId = hostId }) }

                InterfaceToHost.RunInVolatileHostResponse runInVolatileHostResponse ->
                    case runInVolatileHostResponse of
                        Err InterfaceToHost.HostNotFound ->
                            { stateBefore | error = Just "Error running script in volatile host: HostNotFound" }

                        Ok runInVolatileHostComplete ->
                            case runInVolatileHostComplete.returnValueToString of
                                Nothing ->
                                    { stateBefore | error = Just ("Error in volatile host: " ++ (runInVolatileHostComplete.exceptionToString |> Maybe.withDefault "")) }

                                Just returnValueToString ->
                                    case stateBefore.volatileHost of
                                        Nothing ->
                                            { stateBefore | error = Just ("Unexpected response from volatile host: " ++ returnValueToString) }

                                        Just (Initial volatileHost) ->
                                            if returnValueToString == "Setup Completed" then
                                                { stateBefore | volatileHost = Just (SetupCompleted volatileHost) }

                                            else
                                                { stateBefore | error = Just ("Unexpected response from volatile host: " ++ returnValueToString) }

                                        Just (SetupCompleted { volatileHostId }) ->
                                            case returnValueToString |> VolatileHostWindowsApi.deserializeResponseFromVolatileHost of
                                                Err error ->
                                                    { stateBefore | error = Just ("Failed to parse response from volatile host: " ++ (error |> Json.Decode.errorToString)) }

                                                Ok responseFromVolatileHost ->
                                                    case stateBefore.windowId of
                                                        Nothing ->
                                                            case responseFromVolatileHost of
                                                                VolatileHostWindowsApi.GetForegroundWindowResult windowId ->
                                                                    { stateBefore | windowId = Just windowId }

                                                                _ ->
                                                                    { stateBefore | error = Just ("Unexpected response from volatile host: " ++ returnValueToString) }

                                                        Just windowId ->
                                                            case responseFromVolatileHost of
                                                                VolatileHostWindowsApi.GetWindowTextResult windowText ->
                                                                    { stateBefore
                                                                        | lastWindowTitleMeasurement = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, windowTitle = windowText }
                                                                    }

                                                                _ ->
                                                                    stateBefore

                InterfaceToHost.CompleteWithoutResult ->
                    stateBefore

        InterfaceToHost.SetSessionTimeLimit _ ->
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
    in
    portionWindow


getNextSetupStepWithDescriptionFromState : State simpleBotState -> FrameworkSetupStepActivity
getNextSetupStepWithDescriptionFromState state =
    case state.volatileHost of
        Nothing ->
            { task =
                { taskId = InterfaceToHost.taskIdFromString "create_volatile_host"
                , task = InterfaceToHost.CreateVolatileHost
                }
            , taskDescription = "Create volatile host."
            }
                |> ContinueSetupWithTask

        Just (Initial { volatileHostId }) ->
            { task =
                { taskId = InterfaceToHost.taskIdFromString "set_up_volatile_host"
                , task =
                    InterfaceToHost.RunInVolatileHost
                        { hostId = volatileHostId
                        , script = VolatileHostWindowsApi.setupScript
                        }
                }
            , taskDescription = "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."
            }
                |> ContinueSetupWithTask

        Just (SetupCompleted { volatileHostId }) ->
            case state.windowId of
                Nothing ->
                    let
                        task =
                            InterfaceToHost.RunInVolatileHost
                                { hostId = volatileHostId
                                , script = VolatileHostWindowsApi.GetForegroundWindow |> VolatileHostWindowsApi.buildScriptToGetResponseFromVolatileHost
                                }
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
                                    InterfaceToHost.RunInVolatileHost
                                        { hostId = volatileHostId
                                        , script = windowId |> VolatileHostWindowsApi.GetWindowText |> VolatileHostWindowsApi.buildScriptToGetResponseFromVolatileHost
                                        }
                            in
                            { task = { taskId = InterfaceToHost.taskIdFromString "get_window_title", task = task }
                            , taskDescription = "Get window title"
                            }
                                |> ContinueSetupWithTask

                        Just { windowTitle } ->
                            OperateSimpleBot
                                { buildTaskFromTaskOnWindow =
                                    \taskOnWindow ->
                                        InterfaceToHost.RunInVolatileHost
                                            { hostId = volatileHostId
                                            , script = VolatileHostWindowsApi.TaskOnWindow { windowId = windowId, task = taskOnWindow } |> VolatileHostWindowsApi.buildScriptToGetResponseFromVolatileHost
                                            }
                                }


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


volatileHostMouseButtonFromMouseButton : MouseButton -> VolatileHostWindowsApi.MouseButton
volatileHostMouseButtonFromMouseButton mouseButton =
    case mouseButton of
        MouseButtonLeft ->
            VolatileHostWindowsApi.MouseButtonLeft

        MouseButtonRight ->
            VolatileHostWindowsApi.MouseButtonRight


volatileHostKeyboardKeyFromKeyboardKey : KeyboardKey -> VolatileHostWindowsApi.KeyboardKey
volatileHostKeyboardKeyFromKeyboardKey keyboardKey =
    case keyboardKey of
        KeyboardKeyFromVirtualKeyCode keyCode ->
            VolatileHostWindowsApi.KeyboardKeyFromVirtualKeyCode keyCode

        -- https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
        VK_SPACE ->
            VolatileHostWindowsApi.KeyboardKeyFromVirtualKeyCode 0x20

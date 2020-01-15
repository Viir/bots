{- This module contains a framework to build simple bots to work in web browsers.
   This framework automatically starts a new web browser window.
   To use this framework, import this module and use the `initState` and `processEvent` functions.
-}


module Limbara.SimpleLimbara exposing
    ( BotEvent(..)
    , BotRequest(..)
    , RunJavascriptInCurrentPageResponseStructure
    , SetupState
    , StateIncludingSetup
    , VolatileHostState(..)
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import Limbara.Limbara as Limbara
import Limbara.LimbaraVolatileHostSetup as LimbaraVolatileHostSetup


type BotEvent
    = SetBotConfiguration String
    | ArrivedAtTime { timeInMilliseconds : Int }
    | RunJavascriptInCurrentPageResponse RunJavascriptInCurrentPageResponseStructure


type BotRequest
    = RunJavascriptInCurrentPageRequest RunJavascriptInCurrentPageRequestStructure


type alias RunJavascriptInCurrentPageRequestStructure =
    { requestId : String
    , javascript : String
    , timeToWaitForCallbackMilliseconds : Int
    }


type alias RunJavascriptInCurrentPageResponseStructure =
    { directReturnValueAsString : String
    , callbackReturnValueAsString : Maybe String
    }


type alias StateIncludingSetup simpleBotState =
    { setup : SetupState
    , botState : BotState simpleBotState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    }


type alias BotState simpleBotState =
    { simpleBotState : simpleBotState
    , statusMessage : Maybe String
    }


type alias SimpleBotProcessEventResult simpleBotState =
    { newState : simpleBotState
    , request : Maybe BotRequest
    , statusMessage : String
    }


type alias SetupState =
    { volatileHost : Maybe ( InterfaceToHost.VolatileHostId, VolatileHostState )
    , lastRunScriptResult : Maybe (Result String (Maybe String))
    , webBrowserStarted : Bool
    }


type VolatileHostState
    = Initial
    | LimbaraSetupCompleted


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { taskFromBotRequest : BotRequest -> InterfaceToHost.Task }
    | FinishSession String


initSetup : SetupState
initSetup =
    { volatileHost = Nothing
    , lastRunScriptResult = Nothing
    , webBrowserStarted = False
    }


initState : simpleBotState -> StateIncludingSetup simpleBotState
initState simpleBotState =
    { setup = initSetup
    , botState =
        { simpleBotState = simpleBotState
        , statusMessage = Nothing
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    }


processEvent :
    (BotEvent -> simpleBotState -> SimpleBotProcessEventResult simpleBotState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEvent simpleBotProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotRequest ) =
            stateBeforeIntegratingEvent |> integrateFromHostEvent simpleBotProcessEvent fromHostEvent

        ( state, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    processEventNotWaitingForTask maybeBotRequest stateBefore

                Just taskInProgress ->
                    ( stateBefore
                    , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
                      , startTasks = []
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        response =
            case responseBeforeAddingStatusMessage of
                InterfaceToHost.ContinueSession continueSession ->
                    { continueSession
                        | statusDescriptionText = statusMessagePrefix ++ continueSession.statusDescriptionText
                    }
                        |> InterfaceToHost.ContinueSession

                InterfaceToHost.FinishSession finishSession ->
                    { finishSession
                        | statusDescriptionText = statusMessagePrefix ++ finishSession.statusDescriptionText
                    }
                        |> InterfaceToHost.FinishSession
    in
    ( state, response )


processEventNotWaitingForTask : Maybe BotRequest -> StateIncludingSetup simpleBotState -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEventNotWaitingForTask maybeBotRequest stateBefore =
    case stateBefore.setup |> getNextSetupTask of
        ContinueSetup setupState setupTask setupTaskDescription ->
            let
                taskIndex =
                    stateBefore.lastTaskIndex + 1

                taskIdString =
                    "setup-" ++ (taskIndex |> String.fromInt)
            in
            ( { stateBefore
                | setup = setupState
                , lastTaskIndex = taskIndex
                , taskInProgress =
                    Just
                        { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                        , taskIdString = taskIdString
                        , taskDescription = setupTaskDescription
                        }
              }
            , { startTasks = [ { taskId = InterfaceToHost.taskIdFromString taskIdString, task = setupTask } ]
              , statusDescriptionText = "Continue setup: " ++ setupTaskDescription
              , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 1000 }
              }
                |> InterfaceToHost.ContinueSession
            )

        OperateBot operateBot ->
            let
                taskId =
                    "operate-bot"

                ( state, startTasks ) =
                    maybeBotRequest
                        |> Maybe.map
                            (\botRequest ->
                                let
                                    taskFromBotRequest =
                                        botRequest |> operateBot.taskFromBotRequest
                                in
                                ( { stateBefore
                                    | taskInProgress =
                                        Just
                                            { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                                            , taskIdString = taskId
                                            , taskDescription = "Task from bot request."
                                            }
                                  }
                                , [ { taskId = InterfaceToHost.taskIdFromString taskId, task = taskFromBotRequest } ]
                                )
                            )
                        |> Maybe.withDefault ( stateBefore, [] )
            in
            ( state
            , { startTasks = startTasks
              , statusDescriptionText = "Operate bot."
              , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
              }
                |> InterfaceToHost.ContinueSession
            )

        FinishSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Finish session (" ++ reason ++ ")" }
            )


integrateFromHostEvent :
    (BotEvent -> simpleBotState -> SimpleBotProcessEventResult simpleBotState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, Maybe BotRequest )
integrateFromHostEvent simpleBotProcessEvent fromHostEvent stateBefore =
    let
        ( stateBeforeIntegrateBotEvent, maybeBotEvent ) =
            case fromHostEvent of
                InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
                    ( { stateBefore | timeInMilliseconds = timeInMilliseconds }
                    , Just (ArrivedAtTime { timeInMilliseconds = timeInMilliseconds })
                    )

                InterfaceToHost.CompletedTask taskComplete ->
                    let
                        ( setupState, maybeBotEventFromTaskComplete ) =
                            stateBefore.setup
                                |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
                    in
                    ( { stateBefore | setup = setupState, taskInProgress = Nothing }, maybeBotEventFromTaskComplete )

                InterfaceToHost.SetBotConfiguration newBotConfiguration ->
                    ( stateBefore
                    , Just (SetBotConfiguration newBotConfiguration)
                    )

                InterfaceToHost.SetSessionTimeLimit _ ->
                    ( stateBefore, Nothing )
    in
    maybeBotEvent
        |> Maybe.map
            (\botEvent ->
                let
                    botStateBefore =
                        stateBeforeIntegrateBotEvent.botState

                    simpleBotEventResult =
                        botStateBefore.simpleBotState |> simpleBotProcessEvent botEvent

                    botState =
                        { botStateBefore
                            | simpleBotState = simpleBotEventResult.newState
                            , statusMessage = Just simpleBotEventResult.statusMessage
                        }
                in
                ( { stateBeforeIntegrateBotEvent | botState = botState }, simpleBotEventResult.request )
            )
        |> Maybe.withDefault ( stateBeforeIntegrateBotEvent, Nothing )


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateTaskResult ( time, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileHostResponse createVolatileHostResult ->
            case createVolatileHostResult of
                Err _ ->
                    ( setupStateBefore, Nothing )

                Ok createVolatileHostComplete ->
                    ( { setupStateBefore | volatileHost = Just ( createVolatileHostComplete.hostId, Initial ) }, Nothing )

        InterfaceToHost.RunInVolatileHostResponse runInVolatileHostResponse ->
            let
                runScriptResult =
                    runInVolatileHostResponse
                        |> Result.mapError
                            (\error ->
                                case error of
                                    InterfaceToHost.HostNotFound ->
                                        "HostNotFound"
                            )
                        |> Result.andThen
                            (\fromHostResult ->
                                case fromHostResult.exceptionToString of
                                    Nothing ->
                                        Ok fromHostResult.returnValueToString

                                    Just exception ->
                                        Err ("Exception from host: " ++ exception)
                            )

                volatileHost =
                    case runInVolatileHostResponse of
                        Err _ ->
                            setupStateBefore.volatileHost

                        Ok runInVolatileHostComplete ->
                            setupStateBefore.volatileHost
                                |> Maybe.map (Tuple.mapSecond (updateVolatileHostState runInVolatileHostComplete))

                maybeResponseFromVolatileHost =
                    runScriptResult
                        |> Result.toMaybe
                        |> Maybe.andThen identity
                        |> Maybe.map Limbara.deserializeResponseFromVolatileHost
                        |> Maybe.andThen Result.toMaybe

                setupStateWithScriptRunResult =
                    { setupStateBefore
                        | lastRunScriptResult = Just runScriptResult
                        , volatileHost = volatileHost
                    }
            in
            case maybeResponseFromVolatileHost of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileHost ->
                    setupStateWithScriptRunResult
                        |> integrateLimbaraResponseFromVolatileHost ( time, responseFromVolatileHost )

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateLimbaraResponseFromVolatileHost : ( Int, Limbara.ResponseFromVolatileHost ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateLimbaraResponseFromVolatileHost ( time, response ) stateBefore =
    case response of
        Limbara.WebBrowserStarted ->
            ( { stateBefore | webBrowserStarted = True }, Nothing )

        Limbara.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            let
                botEvent =
                    RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse
            in
            ( stateBefore, Just botEvent )


getNextSetupTask : SetupState -> SetupTask
getNextSetupTask stateBefore =
    case stateBefore.volatileHost of
        Nothing ->
            ContinueSetup stateBefore InterfaceToHost.CreateVolatileHost "Create volatile host."

        Just ( volatileHostId, volatileHostState ) ->
            case volatileHostState of
                Initial ->
                    ContinueSetup stateBefore
                        (InterfaceToHost.RunInVolatileHost
                            { hostId = volatileHostId
                            , script = LimbaraVolatileHostSetup.limbaraSetupScript
                            }
                        )
                        "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

                LimbaraSetupCompleted ->
                    getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId


getSetupTaskWhenVolatileHostSetupCompleted : SetupState -> InterfaceToHost.VolatileHostId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId =
    if stateBefore.webBrowserStarted |> not then
        ContinueSetup stateBefore
            (InterfaceToHost.RunInVolatileHost
                { hostId = volatileHostId
                , script = Limbara.buildScriptToGetResponseFromVolatileHost Limbara.StartWebBrowserRequest
                }
            )
            "Start web browser. This can take a while since it might need to download the web browser software first."

    else
        OperateBot
            { taskFromBotRequest =
                \request ->
                    let
                        requestToVolatileHost =
                            case request of
                                RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest ->
                                    Limbara.RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest
                    in
                    InterfaceToHost.RunInVolatileHost
                        { hostId = volatileHostId
                        , script = Limbara.buildScriptToGetResponseFromVolatileHost requestToVolatileHost
                        }
            }


updateVolatileHostState : InterfaceToHost.RunInVolatileHostComplete -> VolatileHostState -> VolatileHostState
updateVolatileHostState runInVolatileHostComplete stateBefore =
    case runInVolatileHostComplete.returnValueToString of
        Nothing ->
            stateBefore

        Just returnValueString ->
            case stateBefore of
                Initial ->
                    if returnValueString |> String.contains "Limbara Setup Completed" then
                        LimbaraSetupCompleted

                    else
                        stateBefore

                LimbaraSetupCompleted ->
                    stateBefore


runScriptResultDisplayString : Result String (Maybe String) -> String
runScriptResultDisplayString result =
    case result of
        Err error ->
            "Error: " ++ error

        Ok successResult ->
            "Success: " ++ (successResult |> Maybe.withDefault "null")


statusReportFromState : StateIncludingSetup s -> String
statusReportFromState state =
    let
        lastScriptRunResult =
            "Last script run result is: "
                ++ (state.setup.lastRunScriptResult |> Maybe.map (runScriptResultDisplayString >> stringEllipsis 540 "....") |> Maybe.withDefault "Nothing")
    in
    [ state.botState.statusMessage |> Maybe.withDefault ""
    , "--------"
    , "Web browser framework status:"
    , lastScriptRunResult
    ]
        |> String.join "\n"


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

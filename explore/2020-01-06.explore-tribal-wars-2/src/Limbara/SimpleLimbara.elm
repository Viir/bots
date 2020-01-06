{- This module contains a framework to build simple bots to work in web browsers.
   This framework automatically starts a new web browser window.
   To use this framework, import this module and use the `initState` and `processEvent` functions.
-}


module Limbara.SimpleLimbara exposing
    ( BotEvent(..)
    , BotEventAtTime
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


type alias BotEventAtTime =
    { timeInMilliseconds : Int
    , event : BotEvent
    }


type BotEvent
    = SetBotConfiguration String
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
    (BotEventAtTime -> simpleBotState -> { newState : simpleBotState, request : BotRequest, statusMessage : String })
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEvent simpleBotProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotEvent ) =
            stateBeforeIntegratingEvent |> integrateFromHostEvent fromHostEvent

        ( state, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    processEventNotWaitingForTask simpleBotProcessEvent maybeBotEvent stateBefore

                Just taskInProgress ->
                    ( stateBefore
                    , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 300 }
                      , startTasks = []
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\n\nCurrent activity: "

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


processEventNotWaitingForTask :
    (BotEventAtTime -> simpleBotState -> { newState : simpleBotState, request : BotRequest, statusMessage : String })
    -> Maybe BotEventAtTime
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEventNotWaitingForTask simpleBotProcessEvent maybeBotEvent stateBefore =
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
                botStateBefore =
                    stateBefore.botState

                maybeSimpleBotEventResult =
                    maybeBotEvent
                        |> Maybe.map
                            (\botEvent -> botStateBefore.simpleBotState |> simpleBotProcessEvent botEvent)

                ( botState, maybeRequestFromBot ) =
                    case maybeSimpleBotEventResult of
                        Nothing ->
                            ( stateBefore.botState, Nothing )

                        Just simpleBotEventResult ->
                            ( { botStateBefore
                                | simpleBotState = simpleBotEventResult.newState
                                , statusMessage = Just simpleBotEventResult.statusMessage

                                --, request = simpleBotEventResult.request
                              }
                            , Just simpleBotEventResult.request
                            )

                taskId =
                    "operate-bot"

                operateBotTask =
                    maybeRequestFromBot
                        |> Maybe.withDefault (RunJavascriptInCurrentPageRequest { requestId = "idle-task", javascript = "''", timeToWaitForCallbackMilliseconds = 0 })
                        |> operateBot.taskFromBotRequest
            in
            ( { stateBefore
                | botState = botState
                , taskInProgress =
                    Just
                        { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                        , taskIdString = taskId
                        , taskDescription = "Operate bot task: "
                        }
              }
            , { startTasks = [ { taskId = InterfaceToHost.taskIdFromString taskId, task = operateBotTask } ]
              , statusDescriptionText = "Operate bot:\n" ++ (botState.statusMessage |> Maybe.withDefault "")
              , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
              }
                |> InterfaceToHost.ContinueSession
            )

        FinishSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Finish session (" ++ reason ++ ")" }
            )


integrateFromHostEvent : InterfaceToHost.BotEvent -> StateIncludingSetup a -> ( StateIncludingSetup a, Maybe BotEventAtTime )
integrateFromHostEvent fromHostEvent stateBefore =
    case fromHostEvent of
        InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
            ( { stateBefore | timeInMilliseconds = timeInMilliseconds }, Nothing )

        InterfaceToHost.CompletedTask taskComplete ->
            let
                ( setupState, maybeBotEvent ) =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
                        |> Tuple.mapSecond
                            (Maybe.map
                                (\botEvent ->
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds, event = botEvent }
                                )
                            )
            in
            ( { stateBefore | setup = setupState, taskInProgress = Nothing }, maybeBotEvent )

        InterfaceToHost.SetBotConfiguration newBotConfiguration ->
            ( stateBefore
            , Just { timeInMilliseconds = stateBefore.timeInMilliseconds, event = SetBotConfiguration newBotConfiguration }
            )

        InterfaceToHost.SetSessionTimeLimit _ ->
            ( stateBefore, Nothing )


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
            "Last Limbara script run result is: "
                ++ (state.setup.lastRunScriptResult |> Maybe.map (runScriptResultDisplayString >> stringEllipsis 540 "....") |> Maybe.withDefault "Nothing")
    in
    [ lastScriptRunResult ]
        |> List.intersperse "\n"
        |> List.foldl (++) ""


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

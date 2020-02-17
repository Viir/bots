{- This module contains a framework to build bots to work in web browsers.
   This framework automatically starts a new web browser window.
   To use this framework, import this module and use the `initState` and `processEvent` functions.
-}


module WebBrowser.BotFramework exposing
    ( BotEvent(..)
    , BotRequest(..)
    , BotResponse(..)
    , RunJavascriptInCurrentPageResponseStructure
    , SetupState
    , StateIncludingSetup
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200213 as InterfaceToHost
import WebBrowser.VolatileHostInterface as VolatileHostInterface
import WebBrowser.VolatileHostScript as VolatileHostScript


type BotEvent
    = SetBotConfiguration String
    | ArrivedAtTime { timeInMilliseconds : Int }
    | RunJavascriptInCurrentPageResponse RunJavascriptInCurrentPageResponseStructure


type alias BotProcessEventResult botState =
    { newState : botState
    , response : BotResponse
    , statusMessage : String
    }


type BotResponse
    = ContinueSession (Maybe BotRequest)
    | FinishSession


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


type alias StateIncludingSetup botState =
    { setup : SetupState
    , botState : BotState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    }


type alias BotState botState =
    { botState : botState
    , statusMessage : Maybe String
    }


type alias SetupState =
    { createVolatileHostResult : Maybe (Result InterfaceToHost.CreateVolatileHostErrorStructure InterfaceToHost.CreateVolatileHostComplete)
    , lastRunScriptResult : Maybe (Result String (Maybe String))
    , webBrowserStarted : Bool
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { taskFromBotRequest : BotRequest -> InterfaceToHost.Task }
    | FailSetup String


initSetup : SetupState
initSetup =
    { createVolatileHostResult = Nothing
    , lastRunScriptResult = Nothing
    , webBrowserStarted = False
    }


initState : botState -> StateIncludingSetup botState
initState botState =
    { setup = initSetup
    , botState =
        { botState = botState
        , statusMessage = Nothing
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    }


processEvent :
    (BotEvent -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, InterfaceToHost.BotResponse )
processEvent botProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotRequest ) =
            stateBeforeIntegratingEvent |> integrateFromHostEvent botProcessEvent fromHostEvent

        botRequestIfContinueSession =
            case maybeBotRequest of
                Nothing ->
                    Just Nothing

                Just FinishSession ->
                    Nothing

                Just (ContinueSession continueSessionRequest) ->
                    Just continueSessionRequest

        ( state, responseBeforeAddingStatusMessage ) =
            case botRequestIfContinueSession of
                Nothing ->
                    ( stateBefore
                    , { statusDescriptionText = "The bot finished the session."
                      }
                        |> InterfaceToHost.FinishSession
                    )

                Just maybeBotRequestContinueSession ->
                    case stateBefore.taskInProgress of
                        Nothing ->
                            processEventNotWaitingForTask maybeBotRequestContinueSession stateBefore

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


processEventNotWaitingForTask : Maybe BotRequest -> StateIncludingSetup botState -> ( StateIncludingSetup botState, InterfaceToHost.BotResponse )
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

        FailSetup reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Setup failed: " ++ reason }
            )


integrateFromHostEvent :
    (BotEvent -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, Maybe BotResponse )
integrateFromHostEvent botProcessEvent fromHostEvent stateBefore =
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

                    botEventResult =
                        botStateBefore.botState |> botProcessEvent botEvent

                    botState =
                        { botStateBefore
                            | botState = botEventResult.newState
                            , statusMessage = Just botEventResult.statusMessage
                        }
                in
                ( { stateBeforeIntegrateBotEvent | botState = botState }, Just botEventResult.response )
            )
        |> Maybe.withDefault ( stateBeforeIntegrateBotEvent, Nothing )


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateTaskResult ( time, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileHostResponse createVolatileHostResponse ->
            ( { setupStateBefore | createVolatileHostResult = Just createVolatileHostResponse }, Nothing )

        InterfaceToHost.RequestToVolatileHostResponse requestToVolatileHostResponse ->
            let
                runScriptResult =
                    requestToVolatileHostResponse
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

                maybeResponseFromVolatileHost =
                    runScriptResult
                        |> Result.toMaybe
                        |> Maybe.andThen identity
                        |> Maybe.map VolatileHostInterface.deserializeResponseFromVolatileHost
                        |> Maybe.andThen Result.toMaybe

                setupStateWithScriptRunResult =
                    { setupStateBefore | lastRunScriptResult = Just runScriptResult }
            in
            case maybeResponseFromVolatileHost of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileHost ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileHost ( time, responseFromVolatileHost )

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateResponseFromVolatileHost : ( Int, VolatileHostInterface.ResponseFromVolatileHost ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateResponseFromVolatileHost ( time, response ) stateBefore =
    case response of
        VolatileHostInterface.WebBrowserStarted ->
            ( { stateBefore | webBrowserStarted = True }, Nothing )

        VolatileHostInterface.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            let
                botEvent =
                    RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse
            in
            ( stateBefore, Just botEvent )


getNextSetupTask : SetupState -> SetupTask
getNextSetupTask stateBefore =
    case stateBefore.createVolatileHostResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileHost { script = VolatileHostScript.setupScript })
                "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FailSetup ("Set up the volatile host failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileHostComplete) ->
            getSetupTaskWhenVolatileHostSetupCompleted stateBefore createVolatileHostComplete.hostId


getSetupTaskWhenVolatileHostSetupCompleted : SetupState -> InterfaceToHost.VolatileHostId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId =
    if stateBefore.webBrowserStarted |> not then
        ContinueSetup stateBefore
            (InterfaceToHost.RequestToVolatileHost
                { hostId = volatileHostId
                , request = VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost VolatileHostInterface.StartWebBrowserRequest
                }
            )
            "Starting the web browser. This can take a while because I might need to download the web browser software first."

    else
        OperateBot
            { taskFromBotRequest =
                \request ->
                    let
                        requestToVolatileHost =
                            case request of
                                RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest ->
                                    VolatileHostInterface.RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest
                    in
                    InterfaceToHost.RequestToVolatileHost
                        { hostId = volatileHostId
                        , request = VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost requestToVolatileHost
                        }
            }


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

{- A framework to build bots to work in web browsers.
   This framework automatically starts a new web browser window.
   To use this framework, import this module and use the `webBrowserBotMain` function.
-}


module WebBrowser.BotFramework exposing
    ( BotEvent(..)
    , BotRequest(..)
    , BotResponse(..)
    , GenericBotState
    , RunJavascriptInCurrentPageResponseStructure
    , SetupState
    , StateIncludingSetup
    , initState
    , processEvent
    , webBrowserBotMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import CompilationInterface.SourceFiles
import WebBrowser.VolatileProcessInterface as VolatileProcessInterface


type alias BotConfig botState =
    { init : botState
    , processEvent : BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState
    }


type BotEvent
    = SetBotSettings String
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
    | StartWebBrowser { userProfileId : String, pageGoToUrl : Maybe String }
    | CloseWebBrowser { userProfileId : String }


type alias RunJavascriptInCurrentPageRequestStructure =
    { requestId : String
    , javascript : String
    , timeToWaitForCallbackMilliseconds : Int
    }


type alias RunJavascriptInCurrentPageResponseStructure =
    { requestId : String
    , webBrowserAvailable : Bool
    , directReturnValueAsString : String
    , callbackReturnValueAsString : Maybe String
    }


type alias StateIncludingSetup botState =
    { setup : SetupState
    , pendingRequestToRestartWebBrowser : Maybe RequestToRestartWebBrowserStructure
    , botState : BotState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    }


type alias RequestToRestartWebBrowserStructure =
    { userProfileId : String
    , pageGoToUrl : Maybe String
    }


type alias BotState botState =
    { botState : botState
    , lastProcessEventResult : Maybe (BotProcessEventResult botState)
    , remainingBotRequests : List BotRequest
    }


type alias SetupState =
    { createVolatileProcessResult : Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , lastRunScriptResult : Maybe (Result String (Maybe String))
    , webBrowserRunning : Bool
    }


type alias GenericBotState =
    { webBrowserRunning : Bool }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { taskFromBotRequestRunJavascript : RunJavascriptInCurrentPageRequestStructure -> InterfaceToHost.Task }
    | FailSetup String


type InternalBotEventResponse
    = InternalContinueSession InternalContinueSessionStructure
    | InternalFinishSession { statusDescriptionText : String }


type alias InternalContinueSessionStructure =
    { statusDescriptionText : String
    , startTask : Maybe { areaId : String, taskDescription : String, task : InterfaceToHost.Task }
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


webBrowserBotMain : BotConfig state -> InterfaceToHost.BotConfig (StateIncludingSetup state)
webBrowserBotMain webBrowserBotConfig =
    { init = initState webBrowserBotConfig.init
    , processEvent = processEvent webBrowserBotConfig.processEvent
    }


initState : botState -> StateIncludingSetup botState
initState botState =
    { setup = initSetup
    , pendingRequestToRestartWebBrowser = Nothing
    , botState =
        { botState = botState
        , lastProcessEventResult = Nothing
        , remainingBotRequests = []
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    }


initSetup : SetupState
initSetup =
    { createVolatileProcessResult = Nothing
    , lastRunScriptResult = Nothing
    , webBrowserRunning = False
    }


processEvent :
    (BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, InterfaceToHost.BotEventResponse )
processEvent botProcessEvent fromHostEvent stateBefore =
    let
        ( state, response ) =
            processEventLessMappingTasks botProcessEvent fromHostEvent stateBefore
    in
    case response of
        InternalFinishSession finishSession ->
            ( state, InterfaceToHost.FinishSession finishSession )

        InternalContinueSession continueSession ->
            case continueSession.startTask of
                Nothing ->
                    ( state
                    , InterfaceToHost.ContinueSession
                        { statusDescriptionText = continueSession.statusDescriptionText
                        , startTasks = []
                        , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                        }
                    )

                Just startTask ->
                    let
                        taskIdString =
                            startTask.areaId ++ "-" ++ String.fromInt stateBefore.lastTaskIndex

                        startTasks =
                            [ { taskId = InterfaceToHost.TaskIdFromString taskIdString
                              , task = startTask.task
                              }
                            ]

                        taskInProgress =
                            { startTimeInMilliseconds = state.timeInMilliseconds
                            , taskIdString = taskIdString
                            , taskDescription = startTask.taskDescription
                            }
                    in
                    ( { state
                        | lastTaskIndex = state.lastTaskIndex + List.length startTasks
                        , taskInProgress = Just taskInProgress
                      }
                    , InterfaceToHost.ContinueSession
                        { statusDescriptionText = continueSession.statusDescriptionText
                        , startTasks = startTasks
                        , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                        }
                    )


processEventLessMappingTasks :
    (BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, InternalBotEventResponse )
processEventLessMappingTasks botProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateFromHostEvent botProcessEvent fromHostEvent

        botRequestedFinishSession =
            stateBefore.botState.lastProcessEventResult
                |> Maybe.map
                    (\lastProcessEventResult ->
                        case lastProcessEventResult.response of
                            ContinueSession _ ->
                                False

                            FinishSession ->
                                True
                    )
                |> Maybe.withDefault False

        ( state, responseBeforeAddingStatusMessageAndSubscribeToTime ) =
            if botRequestedFinishSession then
                ( stateBefore
                , { statusDescriptionText = "The bot finished the session."
                  }
                    |> InternalFinishSession
                )

            else
                case stateBefore.taskInProgress of
                    Nothing ->
                        processEventNotWaitingForTask stateBefore

                    Just taskInProgress ->
                        ( stateBefore
                        , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                          , notifyWhenArrivedAtTime = Nothing
                          , startTask = Nothing
                          }
                            |> InternalContinueSession
                        )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        notifyWhenArrivedAtTime =
            stateBefore.timeInMilliseconds + 500

        response =
            case responseBeforeAddingStatusMessageAndSubscribeToTime of
                InternalContinueSession continueSession ->
                    { continueSession
                        | statusDescriptionText = statusMessagePrefix ++ continueSession.statusDescriptionText
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = notifyWhenArrivedAtTime }
                    }
                        |> InternalContinueSession

                InternalFinishSession finishSession ->
                    { finishSession
                        | statusDescriptionText = statusMessagePrefix ++ finishSession.statusDescriptionText
                    }
                        |> InternalFinishSession
    in
    ( state, response )


processEventNotWaitingForTask : StateIncludingSetup botState -> ( StateIncludingSetup botState, InternalBotEventResponse )
processEventNotWaitingForTask stateBefore =
    case
        stateBefore.setup
            |> getNextSetupTask stateBefore.pendingRequestToRestartWebBrowser
    of
        ContinueSetup setupState setupTask setupTaskDescription ->
            ( { stateBefore | setup = setupState }
            , { startTask =
                    Just
                        { areaId = "setup"
                        , task = setupTask
                        , taskDescription = "setup: " ++ setupTaskDescription
                        }
              , statusDescriptionText = "Continue setup: " ++ setupTaskDescription
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InternalContinueSession
            )

        OperateBot operateBot ->
            let
                botStateBefore =
                    stateBefore.botState

                ( state, startTask ) =
                    case botStateBefore.remainingBotRequests of
                        botRequest :: remainingBotRequests ->
                            let
                                ( stateUpdatedForBotRequest, maybeTaskFromBotRequest ) =
                                    case botRequest of
                                        RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest ->
                                            ( stateBefore
                                            , runJavascriptInCurrentPageRequest
                                                |> operateBot.taskFromBotRequestRunJavascript
                                                |> Just
                                            )

                                        StartWebBrowser startWebBrowser ->
                                            let
                                                releaseVolatileHostTask =
                                                    case stateBefore.setup.createVolatileProcessResult of
                                                        Just (Ok createVolatileProcessSuccess) ->
                                                            Just
                                                                (InterfaceToHost.ReleaseVolatileProcess
                                                                    { processId = createVolatileProcessSuccess.processId }
                                                                )

                                                        _ ->
                                                            Nothing
                                            in
                                            ( { stateBefore
                                                | pendingRequestToRestartWebBrowser = Just startWebBrowser
                                                , setup = initSetup
                                              }
                                            , releaseVolatileHostTask
                                            )

                                        CloseWebBrowser closeWebBrowser ->
                                            let
                                                closeWebBrowserTask =
                                                    case stateBefore.setup.createVolatileProcessResult of
                                                        Just (Ok createVolatileProcessSuccess) ->
                                                            Just
                                                                (InterfaceToHost.RequestToVolatileProcess
                                                                    (InterfaceToHost.RequestNotRequiringInputFocus
                                                                        { processId = createVolatileProcessSuccess.processId
                                                                        , request =
                                                                            VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                                                                (VolatileProcessInterface.CloseWebBrowserRequest { userProfileId = closeWebBrowser.userProfileId })
                                                                        }
                                                                    )
                                                                )

                                                        _ ->
                                                            Nothing
                                            in
                                            ( stateBefore
                                            , closeWebBrowserTask
                                            )

                                botState =
                                    { botStateBefore | remainingBotRequests = remainingBotRequests }
                            in
                            ( { stateUpdatedForBotRequest | botState = botState }
                            , maybeTaskFromBotRequest
                                |> Maybe.map
                                    (\task ->
                                        { areaId = "operate-bot"
                                        , task = task
                                        , taskDescription = "Task from bot request."
                                        }
                                    )
                            )

                        _ ->
                            ( stateBefore, Nothing )
            in
            ( state
            , { startTask = startTask
              , statusDescriptionText = "Operate bot."
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InternalContinueSession
            )

        FailSetup reason ->
            ( stateBefore
            , InternalFinishSession { statusDescriptionText = "Setup failed: " ++ reason }
            )


integrateFromHostEvent :
    (BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> StateIncludingSetup botState
integrateFromHostEvent botProcessEvent fromHostEvent stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = fromHostEvent.timeInMilliseconds }

        ( stateBeforeIntegrateBotEvent, maybeBotEvent ) =
            case fromHostEvent.eventAtTime of
                InterfaceToHost.TimeArrivedEvent ->
                    ( stateBefore
                    , Just (ArrivedAtTime { timeInMilliseconds = fromHostEvent.timeInMilliseconds })
                    )

                InterfaceToHost.TaskCompletedEvent taskComplete ->
                    let
                        ( setupState, maybeBotEventFromTaskComplete ) =
                            stateBefore.setup
                                |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )

                        webBrowserStartedInThisUpdate =
                            not stateBefore.setup.webBrowserRunning && setupState.webBrowserRunning

                        pendingRequestToRestartWebBrowser =
                            if webBrowserStartedInThisUpdate then
                                Nothing

                            else
                                stateBefore.pendingRequestToRestartWebBrowser
                    in
                    ( { stateBefore
                        | setup = setupState
                        , taskInProgress = Nothing
                        , pendingRequestToRestartWebBrowser = pendingRequestToRestartWebBrowser
                      }
                    , maybeBotEventFromTaskComplete
                    )

                InterfaceToHost.BotSettingsChangedEvent botSettings ->
                    ( stateBefore
                    , Just (SetBotSettings botSettings)
                    )

                InterfaceToHost.SessionDurationPlannedEvent _ ->
                    ( stateBefore, Nothing )
    in
    maybeBotEvent
        |> Maybe.map
            (\botEvent ->
                let
                    botStateBefore =
                        stateBeforeIntegrateBotEvent.botState

                    botEventResult =
                        botStateBefore.botState
                            |> botProcessEvent botEvent { webBrowserRunning = stateBefore.setup.webBrowserRunning }

                    newBotRequests =
                        case botEventResult.response of
                            ContinueSession maybeBotRequest ->
                                [ maybeBotRequest ] |> List.filterMap identity

                            FinishSession ->
                                []

                    remainingBotRequests =
                        stateBeforeIntegrateBotEvent.botState.remainingBotRequests ++ newBotRequests

                    botState =
                        { botStateBefore
                            | botState = botEventResult.newState
                            , lastProcessEventResult = Just botEventResult
                            , remainingBotRequests = remainingBotRequests
                        }
                in
                { stateBeforeIntegrateBotEvent | botState = botState }
            )
        |> Maybe.withDefault stateBeforeIntegrateBotEvent


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateTaskResult ( time, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResponse ->
            ( { setupStateBefore | createVolatileProcessResult = Just createVolatileProcessResponse }, Nothing )

        InterfaceToHost.RequestToVolatileProcessResponse requestToVolatileHostResponse ->
            let
                runScriptResult =
                    requestToVolatileHostResponse
                        |> Result.mapError
                            (\error ->
                                case error of
                                    InterfaceToHost.ProcessNotFound ->
                                        "ProcessNotFound"

                                    InterfaceToHost.FailedToAcquireInputFocus ->
                                        "FailedToAcquireInputFocus"
                            )
                        |> Result.andThen
                            (\fromVolatileProcessResult ->
                                case fromVolatileProcessResult.exceptionToString of
                                    Nothing ->
                                        Ok fromVolatileProcessResult.returnValueToString

                                    Just exception ->
                                        Err ("Exception from volatile process: " ++ exception)
                            )

                webBrowserWasClosed =
                    case requestToVolatileHostResponse of
                        Ok fromVolatileProcessResult ->
                            case fromVolatileProcessResult.exceptionToString of
                                Nothing ->
                                    False

                                Just exception ->
                                    String.contains "Most likely the Page has been closed" exception

                        Err _ ->
                            False

                maybeResponseFromVolatileProcess =
                    runScriptResult
                        |> Result.toMaybe
                        |> Maybe.andThen identity
                        |> Maybe.map VolatileProcessInterface.deserializeResponseFromVolatileProcess
                        |> Maybe.andThen Result.toMaybe

                setupStateWithScriptRunResult =
                    { setupStateBefore
                        | lastRunScriptResult = Just runScriptResult
                        , webBrowserRunning =
                            if webBrowserWasClosed then
                                False

                            else
                                setupStateBefore.webBrowserRunning
                    }
            in
            case maybeResponseFromVolatileProcess of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileProcess ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileProcess ( time, responseFromVolatileProcess )

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateResponseFromVolatileProcess : ( Int, VolatileProcessInterface.ResponseFromVolatileProcess ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateResponseFromVolatileProcess ( _, response ) stateBefore =
    case response of
        VolatileProcessInterface.WebBrowserStarted ->
            ( { stateBefore | webBrowserRunning = True }, Nothing )

        VolatileProcessInterface.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            let
                botEvent =
                    RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse
            in
            ( stateBefore, Just botEvent )

        VolatileProcessInterface.WebBrowserClosed ->
            ( { stateBefore | webBrowserRunning = False }, Nothing )


getNextSetupTask : Maybe RequestToRestartWebBrowserStructure -> SetupState -> SetupTask
getNextSetupTask startWebBrowserRequest stateBefore =
    case stateBefore.createVolatileProcessResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileProcess { programCode = CompilationInterface.SourceFiles.file____WebBrowser_VolatileProcess_cx.utf8 })
                "Set up the volatile process. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FailSetup ("Set up the volatile process failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileProcessComplete) ->
            getSetupTaskWhenVolatileHostSetupCompleted
                startWebBrowserRequest
                stateBefore
                createVolatileProcessComplete.processId


getSetupTaskWhenVolatileHostSetupCompleted : Maybe RequestToRestartWebBrowserStructure -> SetupState -> InterfaceToHost.VolatileProcessId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted maybeStartWebBrowserRequest stateBefore volatileProcessId =
    case maybeStartWebBrowserRequest of
        Just startWebBrowserRequest ->
            ContinueSetup stateBefore
                (InterfaceToHost.RequestToVolatileProcess
                    (InterfaceToHost.RequestNotRequiringInputFocus
                        { processId = volatileProcessId
                        , request =
                            VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                (VolatileProcessInterface.StartWebBrowserRequest
                                    { pageGoToUrl = startWebBrowserRequest.pageGoToUrl
                                    , userProfileId = startWebBrowserRequest.userProfileId
                                    , remoteDebuggingPort = 13485
                                    }
                                )
                        }
                    )
                )
                "Starting the web browser. This can take a while because I might need to download the web browser software first."

        Nothing ->
            OperateBot
                { taskFromBotRequestRunJavascript =
                    \runJavascriptInCurrentPageRequest ->
                        let
                            requestToVolatileProcess =
                                VolatileProcessInterface.RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest
                        in
                        InterfaceToHost.RequestToVolatileProcess
                            (InterfaceToHost.RequestNotRequiringInputFocus
                                { processId = volatileProcessId
                                , request = VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess requestToVolatileProcess
                                }
                            )
                }


runScriptResultDisplayString : Result String (Maybe String) -> String
runScriptResultDisplayString result =
    case result of
        Err _ ->
            "Error"

        Ok _ ->
            "Success"


statusReportFromState : StateIncludingSetup s -> String
statusReportFromState state =
    let
        lastScriptRunResult =
            "Last script run result is: "
                ++ (state.setup.lastRunScriptResult
                        |> Maybe.map runScriptResultDisplayString
                        |> Maybe.withDefault "Nothing"
                   )
    in
    [ state.botState.lastProcessEventResult |> Maybe.map .statusMessage |> Maybe.withDefault ""
    , "--------"
    , "Web browser framework status:"
    , lastScriptRunResult
    ]
        |> String.join "\n"

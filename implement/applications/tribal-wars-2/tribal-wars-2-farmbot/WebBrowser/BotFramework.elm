{- This module contains a framework to build bots to work in web browsers.
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
import WebBrowser.VolatileProcessInterface as VolatileProcessInterface
import WebBrowser.VolatileProcessProgram as VolatileProcessProgram


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
processEvent botProcessEvent fromHostEvent stateBeforeIntegratingEvent =
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
                    |> InterfaceToHost.FinishSession
                )

            else
                case stateBefore.taskInProgress of
                    Nothing ->
                        processEventNotWaitingForTask stateBefore

                    Just taskInProgress ->
                        ( stateBefore
                        , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                          , notifyWhenArrivedAtTime = Nothing
                          , startTasks = []
                          }
                            |> InterfaceToHost.ContinueSession
                        )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        notifyWhenArrivedAtTime =
            stateBefore.timeInMilliseconds + 500

        response =
            case responseBeforeAddingStatusMessageAndSubscribeToTime of
                InterfaceToHost.ContinueSession continueSession ->
                    { continueSession
                        | statusDescriptionText = statusMessagePrefix ++ continueSession.statusDescriptionText
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = notifyWhenArrivedAtTime }
                    }
                        |> InterfaceToHost.ContinueSession

                InterfaceToHost.FinishSession finishSession ->
                    { finishSession
                        | statusDescriptionText = statusMessagePrefix ++ finishSession.statusDescriptionText
                    }
                        |> InterfaceToHost.FinishSession
    in
    ( state, response )


processEventNotWaitingForTask : StateIncludingSetup botState -> ( StateIncludingSetup botState, InterfaceToHost.BotEventResponse )
processEventNotWaitingForTask stateBefore =
    case
        stateBefore.setup
            |> getNextSetupTask stateBefore.pendingRequestToRestartWebBrowser
    of
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
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InterfaceToHost.ContinueSession
            )

        OperateBot operateBot ->
            let
                botStateBefore =
                    stateBefore.botState

                ( state, startTasks ) =
                    case botStateBefore.remainingBotRequests of
                        botRequest :: remainingBotRequests ->
                            let
                                ( stateUpdatedForBotRequest, tasksFromBotRequest ) =
                                    case botRequest of
                                        RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest ->
                                            ( stateBefore
                                            , [ runJavascriptInCurrentPageRequest |> operateBot.taskFromBotRequestRunJavascript ]
                                            )

                                        StartWebBrowser startWebBrowser ->
                                            let
                                                releaseVolatileHostTasks =
                                                    case stateBefore.setup.createVolatileProcessResult of
                                                        Just (Ok createVolatileProcessSuccess) ->
                                                            [ InterfaceToHost.ReleaseVolatileProcess
                                                                { processId = createVolatileProcessSuccess.processId }
                                                            ]

                                                        _ ->
                                                            []
                                            in
                                            ( { stateBefore
                                                | pendingRequestToRestartWebBrowser = Just startWebBrowser
                                                , setup = initSetup
                                              }
                                            , releaseVolatileHostTasks
                                            )

                                        CloseWebBrowser closeWebBrowser ->
                                            let
                                                closeWebBrowserTasks =
                                                    case stateBefore.setup.createVolatileProcessResult of
                                                        Just (Ok createVolatileProcessSuccess) ->
                                                            [ InterfaceToHost.RequestToVolatileProcess
                                                                (InterfaceToHost.RequestNotRequiringInputFocus
                                                                    { processId = createVolatileProcessSuccess.processId
                                                                    , request =
                                                                        VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileProcess
                                                                            (VolatileProcessInterface.CloseWebBrowserRequest { userProfileId = closeWebBrowser.userProfileId })
                                                                    }
                                                                )
                                                            ]

                                                        _ ->
                                                            []
                                            in
                                            ( stateBefore
                                            , closeWebBrowserTasks
                                            )

                                botState =
                                    { botStateBefore | remainingBotRequests = remainingBotRequests }

                                tasksWithIds =
                                    tasksFromBotRequest
                                        |> List.indexedMap
                                            (\taskIndex task ->
                                                let
                                                    taskIdString =
                                                        "operate-bot-" ++ (taskIndex |> String.fromInt)
                                                in
                                                ( { taskId = InterfaceToHost.taskIdFromString taskIdString, task = task }, taskIdString )
                                            )

                                taskInProgress =
                                    tasksWithIds
                                        |> List.reverse
                                        |> List.head
                                        |> Maybe.map
                                            (\( _, taskIdString ) ->
                                                { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                                                , taskIdString = taskIdString
                                                , taskDescription = "Task from bot request."
                                                }
                                            )
                            in
                            ( { stateUpdatedForBotRequest
                                | taskInProgress = taskInProgress
                                , botState = botState
                              }
                            , tasksWithIds |> List.map Tuple.first
                            )

                        _ ->
                            ( stateBefore, [] )
            in
            ( state
            , { startTasks = startTasks
              , statusDescriptionText = "Operate bot."
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InterfaceToHost.ContinueSession
            )

        FailSetup reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Setup failed: " ++ reason }
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
                (InterfaceToHost.CreateVolatileProcess { programCode = VolatileProcessProgram.programCode })
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


runScriptResultDisplayString : Result String (Maybe String) -> { string : String, isErr : Bool }
runScriptResultDisplayString result =
    case result of
        Err error ->
            { string = "Error: " ++ error, isErr = True }

        Ok successResult ->
            { string = "Success: " ++ (successResult |> Maybe.withDefault "null"), isErr = False }


statusReportFromState : StateIncludingSetup s -> String
statusReportFromState state =
    let
        lastScriptRunResult =
            "Last script run result is: "
                ++ (state.setup.lastRunScriptResult
                        |> Maybe.map runScriptResultDisplayString
                        |> Maybe.map
                            (\resultDisplayInfo ->
                                resultDisplayInfo.string
                                    |> stringEllipsis
                                        (if resultDisplayInfo.isErr then
                                            640

                                         else
                                            140
                                        )
                                        "...."
                            )
                        |> Maybe.withDefault "Nothing"
                   )
    in
    [ state.botState.lastProcessEventResult |> Maybe.map .statusMessage |> Maybe.withDefault ""
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

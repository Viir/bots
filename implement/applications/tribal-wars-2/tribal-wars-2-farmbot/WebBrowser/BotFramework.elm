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

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import WebBrowser.VolatileHostInterface as VolatileHostInterface
import WebBrowser.VolatileHostScript as VolatileHostScript


type BotEvent
    = SetAppSettings String
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
    | RestartWebBrowser { pageGoToUrl : Maybe String }


type alias RunJavascriptInCurrentPageRequestStructure =
    { requestId : String
    , javascript : String
    , timeToWaitForCallbackMilliseconds : Int
    }


type alias RunJavascriptInCurrentPageResponseStructure =
    { requestId : String
    , directReturnValueAsString : String
    , callbackReturnValueAsString : Maybe String
    }


type alias StateIncludingSetup botState =
    { setup : SetupState
    , pendingRequestToRestartWebBrowser : Maybe { pageGoToUrl : Maybe String }
    , botState : BotState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    }


type alias BotState botState =
    { botState : botState
    , lastProcessEventResult : Maybe (BotProcessEventResult botState)
    , remainingBotRequests : List BotRequest
    }


type alias SetupState =
    { createVolatileHostResult : Maybe (Result InterfaceToHost.CreateVolatileHostErrorStructure InterfaceToHost.CreateVolatileHostComplete)
    , lastRunScriptResult : Maybe (Result String (Maybe String))
    , webBrowserStarted : Bool
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { taskFromBotRequestRunJavascript : RunJavascriptInCurrentPageRequestStructure -> InterfaceToHost.Task }
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


processEvent :
    (BotEvent -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.AppEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, InterfaceToHost.AppResponse )
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
                , { statusDescriptionText = "The app finished the session."
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


processEventNotWaitingForTask : StateIncludingSetup botState -> ( StateIncludingSetup botState, InterfaceToHost.AppResponse )
processEventNotWaitingForTask stateBefore =
    case
        stateBefore.setup
            |> getNextSetupTask
                { pageGoToUrl = stateBefore.pendingRequestToRestartWebBrowser |> Maybe.andThen .pageGoToUrl }
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

                                        RestartWebBrowser restartWebBrowser ->
                                            let
                                                releaseVolatileHostTasks =
                                                    case stateBefore.setup.createVolatileHostResult of
                                                        Just (Ok createVolatileHostSuccess) ->
                                                            [ InterfaceToHost.ReleaseVolatileHost { hostId = createVolatileHostSuccess.hostId } ]

                                                        _ ->
                                                            []
                                            in
                                            ( { stateBefore
                                                | pendingRequestToRestartWebBrowser = Just restartWebBrowser
                                                , setup = initSetup
                                              }
                                            , releaseVolatileHostTasks
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
    (BotEvent -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.AppEvent
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
                            not stateBefore.setup.webBrowserStarted && setupState.webBrowserStarted

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

                InterfaceToHost.AppSettingsChangedEvent appSettings ->
                    ( stateBefore
                    , Just (SetAppSettings appSettings)
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
                        botStateBefore.botState |> botProcessEvent botEvent

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
integrateResponseFromVolatileHost ( _, response ) stateBefore =
    case response of
        VolatileHostInterface.WebBrowserStarted ->
            ( { stateBefore | webBrowserStarted = True }, Nothing )

        VolatileHostInterface.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            let
                botEvent =
                    RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse
            in
            ( stateBefore, Just botEvent )


getNextSetupTask : { pageGoToUrl : Maybe String } -> SetupState -> SetupTask
getNextSetupTask startWebBrowserParameters stateBefore =
    case stateBefore.createVolatileHostResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileHost { script = VolatileHostScript.setupScript })
                "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FailSetup ("Set up the volatile host failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileHostComplete) ->
            getSetupTaskWhenVolatileHostSetupCompleted startWebBrowserParameters stateBefore createVolatileHostComplete.hostId


getSetupTaskWhenVolatileHostSetupCompleted : { pageGoToUrl : Maybe String } -> SetupState -> InterfaceToHost.VolatileHostId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted { pageGoToUrl } stateBefore volatileHostId =
    if stateBefore.webBrowserStarted |> not then
        ContinueSetup stateBefore
            (InterfaceToHost.RequestToVolatileHost
                { hostId = volatileHostId
                , request =
                    VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                        (VolatileHostInterface.StartWebBrowserRequest { pageGoToUrl = pageGoToUrl })
                }
            )
            "Starting the web browser. This can take a while because I might need to download the web browser software first."

    else
        OperateBot
            { taskFromBotRequestRunJavascript =
                \runJavascriptInCurrentPageRequest ->
                    let
                        requestToVolatileHost =
                            VolatileHostInterface.RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest
                    in
                    InterfaceToHost.RequestToVolatileHost
                        { hostId = volatileHostId
                        , request = VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost requestToVolatileHost
                        }
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

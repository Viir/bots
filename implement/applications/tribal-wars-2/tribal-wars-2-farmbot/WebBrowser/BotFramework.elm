{- A framework to build bots to work in web browsers.
   This framework automatically starts a new web browser window.
   To use this framework, import this module and use the `webBrowserBotMain` function.
-}


module WebBrowser.BotFramework exposing (..)

import BotLab.BotInterface_To_Host_2022_10_23 as InterfaceToHost
import Dict
import Json.Decode
import Json.Encode


type alias BotConfig botState =
    { init : botState
    , processEvent : BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState
    }


type BotEvent
    = SetBotSettings String
    | ArrivedAtTime { timeInMilliseconds : Int }
    | ChromeDevToolsProtocolRuntimeEvaluateResponse ChromeDevToolsProtocolRuntimeEvaluateResponseStruct


type alias BotProcessEventResult botState =
    { newState : botState
    , response : BotResponse
    , statusMessage : String
    }


type BotResponse
    = ContinueSession ContinueSessionStruct
    | FinishSession


type alias ContinueSessionStruct =
    { request : Maybe BotRequest
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type BotRequest
    = ChromeDevToolsProtocolRuntimeEvaluateRequest ChromeDevToolsProtocolRuntimeEvaluateRequestStruct
    | StartWebBrowserRequest StartWebBrowserRequestStruct
    | CloseWebBrowserRequest


type alias StartWebBrowserRequestStruct =
    { content : Maybe BrowserPageContent
    }


type BrowserPageContent
    = WebSiteContent String
    | HtmlContent String


type alias ChromeDevToolsProtocolRuntimeEvaluateRequestStruct =
    { requestId : String
    , expression : String
    }


type alias ChromeDevToolsProtocolRuntimeEvaluateResponseStruct =
    { requestId : String
    , webBrowserAvailable : Bool
    , returnValueJsonSerialized : String
    }


type alias StateIncludingSetup botState =
    { setup : SetupState
    , pendingRequestToStartWebBrowser : Maybe StartWebBrowserRequestStruct
    , botState : BotState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , tasksInProgress : Dict.Dict String { startTimeInMilliseconds : Int, taskDescription : String }
    }


type alias BotState botState =
    { botState : botState
    , lastProcessEventStatusText : Maybe String
    , queuedBotRequests : List BotRequest
    }


type alias SetupState =
    { openWebBrowserResult : Maybe (Result String InterfaceToHost.OpenWindowSuccess)
    , lastRunScriptResult : Maybe (Result String (Maybe String))
    , webBrowserRunning : Bool
    }


type alias GenericBotState =
    { webBrowserRunning : Bool }


type alias InternalBotEventResponse =
    ContinueOrFinishResponse InternalContinueSessionStructure { statusText : String }


type ContinueOrFinishResponse continue finish
    = ContinueResponse continue
    | FinishResponse finish


type alias InternalContinueSessionStructure =
    { statusText : String
    , startTasks : List { areaId : String, taskDescription : String, taskId : Maybe String, task : InterfaceToHost.Task }
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type RuntimeEvaluateResponse
    = ExceptionEvaluateResponse Json.Encode.Value
    | StringResultEvaluateResponse String
    | OtherResultEvaluateResponse Json.Encode.Value


webBrowserBotMain : BotConfig state -> InterfaceToHost.BotConfig (StateIncludingSetup state)
webBrowserBotMain webBrowserBotConfig =
    { init = initState webBrowserBotConfig.init
    , processEvent = processEvent webBrowserBotConfig.processEvent
    }


initState : botState -> StateIncludingSetup botState
initState botState =
    { setup = initSetup
    , pendingRequestToStartWebBrowser = Nothing
    , botState =
        { botState = botState
        , lastProcessEventStatusText = Nothing
        , queuedBotRequests = []
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , tasksInProgress = Dict.empty
    }


initSetup : SetupState
initSetup =
    { openWebBrowserResult = Nothing
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
        ( state, responseBeforeStatusText ) =
            processEventLessComposingStatusText botProcessEvent fromHostEvent stateBefore

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        response =
            case responseBeforeStatusText of
                InterfaceToHost.ContinueSession continueSession ->
                    { continueSession
                        | statusText = statusMessagePrefix ++ continueSession.statusText
                    }
                        |> InterfaceToHost.ContinueSession

                InterfaceToHost.FinishSession finishSession ->
                    { finishSession
                        | statusText = statusMessagePrefix ++ finishSession.statusText
                    }
                        |> InterfaceToHost.FinishSession
    in
    ( state, response )


processEventLessComposingStatusText :
    (BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, InterfaceToHost.BotEventResponse )
processEventLessComposingStatusText botProcessEvent fromHostEvent stateBefore =
    let
        ( state, response ) =
            processEventLessMappingTasks botProcessEvent fromHostEvent stateBefore
    in
    case response of
        FinishResponse finishSession ->
            ( state, InterfaceToHost.FinishSession finishSession )

        ContinueResponse continueSession ->
            let
                startTasksNavigateAfterOpenWindow =
                    case stateBefore.pendingRequestToStartWebBrowser of
                        Nothing ->
                            []

                        Just pendingRequestToStartWebBrowser ->
                            case state.setup.openWebBrowserResult of
                                Just (Ok openWindowOk) ->
                                    if state.pendingRequestToStartWebBrowser /= Nothing then
                                        []

                                    else
                                        let
                                            content =
                                                Maybe.withDefault
                                                    browserDefaultContent
                                                    pendingRequestToStartWebBrowser.content
                                        in
                                        [ { taskId = "navigate-after-open-window"
                                          , task =
                                                InterfaceToHost.InvokeMethodOnWindowRequest
                                                    openWindowOk.windowId
                                                    (InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethod
                                                        { expression = expressionToLoadContent content
                                                        , awaitPromise = True
                                                        }
                                                    )
                                          , taskDescription = "Open web site after opening browser window"
                                          }
                                        ]

                                _ ->
                                    []

                startTasksLessNavigateAfterOpenWindow =
                    continueSession.startTasks
                        |> List.map
                            (\startTask ->
                                let
                                    defaultTaskId =
                                        startTask.areaId ++ "-" ++ String.fromInt stateBefore.lastTaskIndex
                                in
                                { taskId = startTask.taskId |> Maybe.withDefault defaultTaskId
                                , task = startTask.task
                                , taskDescription = startTask.taskDescription
                                }
                            )

                startTasks =
                    startTasksNavigateAfterOpenWindow
                        ++ startTasksLessNavigateAfterOpenWindow

                newTasksInProgress =
                    startTasks
                        |> List.map
                            (\startTask ->
                                ( startTask.taskId
                                , { startTimeInMilliseconds = state.timeInMilliseconds
                                  , taskDescription = startTask.taskDescription
                                  }
                                )
                            )
                        |> Dict.fromList
            in
            ( { state
                | lastTaskIndex = state.lastTaskIndex + List.length startTasks
                , tasksInProgress = state.tasksInProgress |> Dict.union newTasksInProgress
              }
            , InterfaceToHost.ContinueSession
                { statusText = continueSession.statusText
                , startTasks = startTasks |> List.map (\startTask -> { taskId = startTask.taskId, task = startTask.task })
                , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                }
            )


expressionToLoadContent : BrowserPageContent -> String
expressionToLoadContent content =
    case content of
        WebSiteContent location ->
            "window.location = \"" ++ location ++ "\""

        HtmlContent html ->
            "window.document.documentElement.innerHTML = \"" ++ html ++ "\""


browserDefaultContent : BrowserPageContent
browserDefaultContent =
    HtmlContent
        "<html>The bot did not specify a site to load. Please enter the site manually in the address bar.</html>"


processEventLessMappingTasks :
    (BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, InternalBotEventResponse )
processEventLessMappingTasks botProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotResponse ) =
            stateBeforeIntegratingEvent
                |> integrateFromHostEvent botProcessEvent fromHostEvent

        botRequestedFinishSession =
            maybeBotResponse
                |> Maybe.map
                    (\lastProcessEventResult ->
                        case lastProcessEventResult.response of
                            ContinueSession _ ->
                                False

                            FinishSession ->
                                True
                    )
                |> Maybe.withDefault False

        ( state, responseBeforeSubscribeToTime ) =
            if botRequestedFinishSession then
                ( stateBefore
                , { statusText = "The bot finished the session." }
                    |> FinishResponse
                )

            else
                case stateBefore.tasksInProgress |> Dict.toList |> List.head of
                    Nothing ->
                        processEventNotWaitingForTask stateBefore

                    Just ( taskInProgressId, taskInProgress ) ->
                        ( stateBefore
                        , { statusText = "Waiting for completion of task '" ++ taskInProgressId ++ "': " ++ taskInProgress.taskDescription
                          , notifyWhenArrivedAtTime = Nothing
                          , startTasks = []
                          }
                            |> ContinueResponse
                        )

        notifyWhenArrivedAtTimeFromBot =
            case maybeBotResponse |> Maybe.map .response of
                Nothing ->
                    Nothing

                Just (ContinueSession continueSession) ->
                    continueSession.notifyWhenArrivedAtTime

                Just FinishSession ->
                    Nothing

        notifyWhenArrivedAtTime =
            notifyWhenArrivedAtTimeFromBot
                |> Maybe.map .timeInMilliseconds
                |> Maybe.withDefault (stateBefore.timeInMilliseconds + 1000)
                |> min (stateBefore.timeInMilliseconds + 4000)

        response =
            case responseBeforeSubscribeToTime of
                ContinueResponse continueSession ->
                    { continueSession
                        | notifyWhenArrivedAtTime = Just { timeInMilliseconds = notifyWhenArrivedAtTime }
                    }
                        |> ContinueResponse

                FinishResponse _ ->
                    responseBeforeSubscribeToTime
    in
    ( state, response )


processEventNotWaitingForTask : StateIncludingSetup botState -> ( StateIncludingSetup botState, InternalBotEventResponse )
processEventNotWaitingForTask stateBefore =
    let
        botStateBefore =
            stateBefore.botState

        ( state, startTasks ) =
            case botStateBefore.queuedBotRequests of
                botRequest :: remainingBotRequests ->
                    let
                        closeWindowTasks =
                            case stateBefore.setup.openWebBrowserResult of
                                Just (Ok openWebBrowserOk) ->
                                    [ ( Just "close-window"
                                      , InterfaceToHost.InvokeMethodOnWindowRequest
                                            openWebBrowserOk.windowId
                                            InterfaceToHost.CloseWindowMethod
                                      )
                                    ]

                                _ ->
                                    []

                        ( stateUpdatedForBotRequest, tasksFromBotRequest ) =
                            case botRequest of
                                ChromeDevToolsProtocolRuntimeEvaluateRequest runtimeEvaluateRequest ->
                                    case stateBefore.setup.openWebBrowserResult of
                                        Just (Ok openWebBrowserOk) ->
                                            let
                                                taskId =
                                                    runJsInPageRequestTaskIdPrefix ++ runtimeEvaluateRequest.requestId
                                            in
                                            ( stateBefore
                                            , [ ( Just taskId
                                                , InterfaceToHost.InvokeMethodOnWindowRequest
                                                    openWebBrowserOk.windowId
                                                    (InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethod
                                                        { expression = runtimeEvaluateRequest.expression
                                                        , awaitPromise = True
                                                        }
                                                    )
                                                )
                                              ]
                                            )

                                        _ ->
                                            -- TODO: Change handling: Probably include current WebBrowserState with event to bot..
                                            ( stateBefore
                                            , []
                                            )

                                StartWebBrowserRequest startWebBrowser ->
                                    let
                                        openWindowTask =
                                            ( Just "open-window"
                                            , InterfaceToHost.OpenWindowRequest
                                                { windowType = Just InterfaceToHost.WebBrowserWindow
                                                , userGuide = "Web browser window to load the Tribal Wars 2 game."
                                                }
                                            )
                                    in
                                    ( { stateBefore
                                        | pendingRequestToStartWebBrowser = Just startWebBrowser
                                        , setup = initSetup
                                      }
                                    , openWindowTask :: closeWindowTasks
                                    )

                                CloseWebBrowserRequest ->
                                    ( stateBefore
                                    , closeWindowTasks
                                    )

                        botState =
                            { botStateBefore | queuedBotRequests = remainingBotRequests }
                    in
                    ( { stateUpdatedForBotRequest | botState = botState }
                    , tasksFromBotRequest
                        |> List.map
                            (\( taskId, task ) ->
                                { areaId = "operate-bot"
                                , task = task
                                , taskId = taskId
                                , taskDescription = "Task from bot request."
                                }
                            )
                    )

                _ ->
                    ( stateBefore, [] )
    in
    ( state
    , { startTasks = startTasks
      , statusText = "Operate bot."
      , notifyWhenArrivedAtTime = Nothing
      }
        |> ContinueResponse
    )


integrateFromHostEvent :
    (BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botState
    -> ( StateIncludingSetup botState, Maybe (BotProcessEventResult botState) )
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
                                |> integrateTaskResult
                                    ( stateBefore.timeInMilliseconds
                                    , taskComplete.taskId
                                    , taskComplete.taskResult
                                    )

                        webBrowserStartedInThisUpdate =
                            not stateBefore.setup.webBrowserRunning && setupState.webBrowserRunning

                        pendingRequestToStartWebBrowser =
                            if webBrowserStartedInThisUpdate then
                                Nothing

                            else
                                stateBefore.pendingRequestToStartWebBrowser
                    in
                    ( { stateBefore
                        | setup = setupState
                        , tasksInProgress = Dict.remove taskComplete.taskId stateBefore.tasksInProgress
                        , pendingRequestToStartWebBrowser = pendingRequestToStartWebBrowser
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
    case maybeBotEvent of
        Nothing ->
            ( stateBeforeIntegrateBotEvent, Nothing )

        Just botEvent ->
            let
                botStateBefore =
                    stateBeforeIntegrateBotEvent.botState

                botEventResult =
                    botStateBefore.botState
                        |> botProcessEvent botEvent { webBrowserRunning = stateBefore.setup.webBrowserRunning }

                newBotRequests =
                    case botEventResult.response of
                        ContinueSession continueSession ->
                            continueSession.request |> Maybe.map List.singleton |> Maybe.withDefault []

                        FinishSession ->
                            []

                queuedBotRequests =
                    stateBeforeIntegrateBotEvent.botState.queuedBotRequests ++ newBotRequests

                botState =
                    { botStateBefore
                        | botState = botEventResult.newState
                        , lastProcessEventStatusText = Just botEventResult.statusMessage
                        , queuedBotRequests = queuedBotRequests
                    }
            in
            ( { stateBeforeIntegrateBotEvent | botState = botState }
            , Just botEventResult
            )


integrateTaskResult :
    ( Int, String, InterfaceToHost.TaskResultStructure )
    -> SetupState
    -> ( SetupState, Maybe BotEvent )
integrateTaskResult ( time, taskId, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse _ ->
            ( setupStateBefore, Nothing )

        InterfaceToHost.RequestToVolatileProcessResponse _ ->
            ( setupStateBefore, Nothing )

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )

        InterfaceToHost.OpenWindowResponse openWindowResponse ->
            ( { setupStateBefore
                | webBrowserRunning = True
                , openWebBrowserResult = Just openWindowResponse
              }
            , Nothing
            )

        InterfaceToHost.InvokeMethodOnWindowResponse invokeMethodOnWindowResponse ->
            case invokeMethodOnWindowResponse of
                Err _ ->
                    ( { setupStateBefore
                        | webBrowserRunning = False
                        , openWebBrowserResult = Nothing
                      }
                    , Nothing
                    )

                Ok invokeMethodOnWindowOk ->
                    case invokeMethodOnWindowOk of
                        InterfaceToHost.InvokeMethodOnWindowResultWithoutValue ->
                            ( setupStateBefore
                            , Nothing
                            )

                        InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethodResult (Err _) ->
                            ( setupStateBefore
                            , Nothing
                            )

                        InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethodResult (Ok runJsOk) ->
                            let
                                botEvent =
                                    if String.startsWith runJsInPageRequestTaskIdPrefix taskId then
                                        Just
                                            (ChromeDevToolsProtocolRuntimeEvaluateResponse
                                                { requestId = String.dropLeft (String.length runJsInPageRequestTaskIdPrefix) taskId
                                                , webBrowserAvailable = True
                                                , returnValueJsonSerialized = runJsOk.returnValueJsonSerialized
                                                }
                                            )

                                    else
                                        Nothing
                            in
                            ( setupStateBefore
                            , botEvent
                            )


decodeRuntimeEvaluateResponse : Json.Decode.Decoder RuntimeEvaluateResponse
decodeRuntimeEvaluateResponse =
    {-
        2022-10-23 Return value seen from the API:

        {
           "result": {
               "type": "string",
               "subtype": null,
               "className": null,
               "value": "{\"location\":\"data:text/html,bot%20web%20browser\",\"tribalWars2\":{\"NotInTribalWars\":true}}",
               "unserializableValue": null,
               "description": null,
               "objectId": null,
               "preview": null,
               "customPreview": null
           },
           "exceptionDetails": null
       }
    -}
    Json.Decode.oneOf
        [ Json.Decode.field "exceptionDetails" Json.Decode.value
            |> Json.Decode.andThen
                (\exceptionDetails ->
                    if exceptionDetails == Json.Encode.null then
                        Json.Decode.fail "exceptionDetails is null"

                    else
                        Json.Decode.succeed exceptionDetails
                )
            |> Json.Decode.map ExceptionEvaluateResponse
        , Json.Decode.field "result"
            (Json.Decode.oneOf
                [ (Json.Decode.field "type" Json.Decode.string
                    |> Json.Decode.andThen
                        (\typeName ->
                            if typeName /= "string" then
                                Json.Decode.fail ("type is not string: '" ++ typeName ++ "'")

                            else
                                Json.Decode.field "value" Json.Decode.string
                        )
                  )
                    |> Json.Decode.map StringResultEvaluateResponse
                , Json.Decode.value
                    |> Json.Decode.andThen
                        (\resultJson ->
                            if resultJson == Json.Encode.null then
                                Json.Decode.fail "result is null"

                            else
                                Json.Decode.succeed resultJson
                        )
                    |> Json.Decode.map OtherResultEvaluateResponse
                ]
            )
        ]


runJsInPageRequestTaskIdPrefix : String
runJsInPageRequestTaskIdPrefix =
    "run-js-"


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
    [ state.botState.lastProcessEventStatusText |> Maybe.withDefault ""
    , "--------"
    , "Web browser framework status:"
    , lastScriptRunResult
    ]
        |> String.join "\n"

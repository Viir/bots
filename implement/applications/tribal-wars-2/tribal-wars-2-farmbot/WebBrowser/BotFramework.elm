{- A framework to build bots to work in web browsers.
   This framework automatically starts a new web browser window.
   To use this framework, import this module and use the `webBrowserBotMain` function.
-}


module WebBrowser.BotFramework exposing (..)

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import Dict
import Json.Decode
import Json.Encode


type alias BotConfig botSettings botState =
    { init : botState
    , parseBotSettings : String -> Result String botSettings
    , processEvent : botSettings -> BotEvent -> GenericBotState -> botState -> BotProcessEventResult botState
    }


type BotEvent
    = ArrivedAtTime { timeInMilliseconds : Int }
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


{-| Use 'Nothing' to inherit the defaults from the environment.
-}
type alias StartWebBrowserRequestStruct =
    { content : Maybe BrowserPageContent

    -- https://chromium.googlesource.com/chromium/src/+/master/docs/user_data_dir.md
    , userDataDir : Maybe String
    , language : Maybe String
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
    , returnValueJsonSerialized : String
    }


type alias StateIncludingSetup botSettings botState =
    { webBrowser : Maybe WebBrowserState
    , botState : BotState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , tasksInProgress : Dict.Dict String { startTimeInMilliseconds : Int, taskDescription : String }
    , startWebBrowserCount : Int
    , botSettings : Maybe botSettings
    }


type alias BotState botState =
    { botState : botState
    , lastProcessEventStatusText : Maybe String
    }


type WebBrowserState
    = OpeningWebBrowserState StartWebBrowserRequestStruct
    | OpeningFailedWebBrowserState String
    | RunningWebBrowserState RunningWebBrowserStateStruct
    | RunningFailedWebBrowserState String RunningWebBrowserStateStruct


type alias RunningWebBrowserStateStruct =
    { openWindowResult : InterfaceToHost.OpenWindowSuccess
    , startTimeMilliseconds : Int
    }


type alias GenericBotState =
    { webBrowser : Maybe WebBrowserState }


type alias InternalBotEventResponse =
    ContinueOrFinishResponse InternalContinueSessionStructure ()


type alias ContinueSessionStructure =
    { startTasks : List InterfaceToHost.StartTaskStructure
    , notifyWhenArrivedAtTimeMilliseconds : Maybe Int
    }


type ContinueOrFinishResponse continue finish
    = ContinueResponse continue
    | FinishResponse finish


type alias InternalContinueSessionStructure =
    { startTasks : List InternalStartTask
    , notifyWhenArrivedAtTimeMilliseconds : Maybe Int
    }


type alias InternalStartTask =
    { areaId : String
    , taskDescription : String
    , taskId : Maybe String
    , task : InterfaceToHost.Task
    }


type RuntimeEvaluateResponse
    = ExceptionEvaluateResponse Json.Encode.Value
    | StringResultEvaluateResponse String
    | OtherResultEvaluateResponse Json.Encode.Value


type SetupOrOperationTask setup operation
    = SetupTask setup
    | OperationTask operation


type EventMainBranch
    = ReturnToHostBranch (Result String String)
    | ContinueToBotBranch BotEventInternal


type BotEventInternal
    = TimeArrivedInternal
    | SessionDurationPlannedInternal { timeInMilliseconds : Int }
    | TaskCompletedInternal InterfaceToHost.CompletedTaskStructure


webBrowserBotMain : BotConfig botSettings state -> InterfaceToHost.BotConfig (StateIncludingSetup botSettings state)
webBrowserBotMain webBrowserBotConfig =
    { init = initState webBrowserBotConfig.init
    , processEvent = processEvent webBrowserBotConfig
    }


initState : botState -> StateIncludingSetup botSettings botState
initState botState =
    { webBrowser = Nothing
    , botState =
        { botState = botState
        , lastProcessEventStatusText = Nothing
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , tasksInProgress = Dict.empty
    , startWebBrowserCount = 0
    , botSettings = Nothing
    }


processEvent :
    BotConfig botSettings botState
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup botSettings botState
    -> ( StateIncludingSetup botSettings botState, InterfaceToHost.BotEventResponse )
processEvent botConfig fromHostEvent stateBeforeUpdateTime =
    let
        ( stateBefore, responseClass ) =
            eventMainBranch botConfig
                fromHostEvent.eventAtTime
                { stateBeforeUpdateTime | timeInMilliseconds = fromHostEvent.timeInMilliseconds }
    in
    case responseClass of
        ReturnToHostBranch (Ok continueSessionStatusText) ->
            ( stateBefore
            , InterfaceToHost.ContinueSession
                { statusText = continueSessionStatusText
                , startTasks = []
                , notifyWhenArrivedAtTime = Just { timeInMilliseconds = 0 }
                }
            )

        ReturnToHostBranch (Err finishSessionStatusText) ->
            ( stateBefore
            , InterfaceToHost.FinishSession
                { statusText = finishSessionStatusText }
            )

        ContinueToBotBranch internalEvent ->
            processEventLessBotSettingsChanged
                botConfig
                internalEvent
                stateBefore


eventMainBranch :
    BotConfig botSettings botState
    -> InterfaceToHost.BotEventAtTime
    -> StateIncludingSetup botSettings botState
    -> ( StateIncludingSetup botSettings botState, EventMainBranch )
eventMainBranch botConfig eventAtTime stateBefore =
    case eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            ( stateBefore
            , ContinueToBotBranch TimeArrivedInternal
            )

        InterfaceToHost.BotSettingsChangedEvent botSettingsString ->
            case botConfig.parseBotSettings botSettingsString of
                Err err ->
                    ( stateBefore
                    , ReturnToHostBranch
                        (Err ("Failed to parse these bot settings: " ++ err))
                    )

                Ok ok ->
                    ( { stateBefore | botSettings = Just ok }
                    , ReturnToHostBranch (Ok "Succeeded parsing these bot-settings.")
                    )

        InterfaceToHost.TaskCompletedEvent taskCompleted ->
            ( stateBefore
            , ContinueToBotBranch (TaskCompletedInternal taskCompleted)
            )

        InterfaceToHost.SessionDurationPlannedEvent durationPlanned ->
            ( stateBefore
            , ContinueToBotBranch (SessionDurationPlannedInternal durationPlanned)
            )


processEventLessBotSettingsChanged :
    BotConfig botSettings botState
    -> BotEventInternal
    -> StateIncludingSetup botSettings botState
    -> ( StateIncludingSetup botSettings botState, InterfaceToHost.BotEventResponse )
processEventLessBotSettingsChanged botConfig fromHostEvent stateBefore =
    let
        ( state, responseBeforeStatusText ) =
            processEventLessComposingStatusText botConfig
                fromHostEvent
                stateBefore

        statusText =
            statusReportFromState state

        response =
            case responseBeforeStatusText of
                ContinueResponse continueSession ->
                    let
                        notifyWhenArrivedAtTimeMilliseconds =
                            continueSession.notifyWhenArrivedAtTimeMilliseconds
                                |> Maybe.withDefault state.timeInMilliseconds
                                |> max (state.timeInMilliseconds + 500)
                                |> min (state.timeInMilliseconds + 4000)
                    in
                    InterfaceToHost.ContinueSession
                        { statusText = statusText
                        , startTasks = continueSession.startTasks
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = notifyWhenArrivedAtTimeMilliseconds }
                        }

                FinishResponse () ->
                    InterfaceToHost.FinishSession
                        { statusText = statusText }
    in
    ( state, response )


processEventLessComposingStatusText :
    BotConfig botSettings botState
    -> BotEventInternal
    -> StateIncludingSetup botSettings botState
    -> ( StateIncludingSetup botSettings botState, ContinueOrFinishResponse ContinueSessionStructure () )
processEventLessComposingStatusText botConfig fromHostEvent stateBefore =
    let
        ( state, response ) =
            processEventLessMappingTasks botConfig fromHostEvent stateBefore
    in
    case response of
        FinishResponse finishSession ->
            ( state
            , FinishResponse finishSession
            )

        ContinueResponse continueSession ->
            let
                startTasks =
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
            , ContinueResponse
                { startTasks = startTasks |> List.map (\startTask -> { taskId = startTask.taskId, task = startTask.task })
                , notifyWhenArrivedAtTimeMilliseconds = continueSession.notifyWhenArrivedAtTimeMilliseconds
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
    BotConfig botSettings botState
    -> BotEventInternal
    -> StateIncludingSetup botSettings botState
    -> ( StateIncludingSetup botSettings botState, InternalBotEventResponse )
processEventLessMappingTasks botConfig fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotResponse ) =
            stateBeforeIntegratingEvent
                |> integrateFromHostEvent botConfig fromHostEvent
    in
    case maybeBotResponse of
        Nothing ->
            ( stateBefore
            , ContinueResponse
                { notifyWhenArrivedAtTimeMilliseconds = Nothing
                , startTasks = []
                }
            )

        Just (SetupTask setupTask) ->
            ( stateBefore
            , ContinueResponse
                { notifyWhenArrivedAtTimeMilliseconds = Nothing
                , startTasks = [ setupTask ]
                }
            )

        Just (OperationTask botResponse) ->
            case botResponse.response of
                FinishSession ->
                    ( stateBefore
                    , FinishResponse ()
                    )

                ContinueSession continue ->
                    let
                        notifyWhenArrivedAtTimeMilliseconds =
                            continue.notifyWhenArrivedAtTime
                                |> Maybe.map .timeInMilliseconds
                    in
                    case continue.request of
                        Nothing ->
                            ( stateBefore
                            , ContinueResponse
                                { notifyWhenArrivedAtTimeMilliseconds = notifyWhenArrivedAtTimeMilliseconds
                                , startTasks = []
                                }
                            )

                        Just botRequest ->
                            stateBefore
                                |> startTasksFromBotRequest botRequest
                                |> Tuple.mapSecond
                                    (\startTasks ->
                                        ContinueResponse
                                            { notifyWhenArrivedAtTimeMilliseconds = notifyWhenArrivedAtTimeMilliseconds
                                            , startTasks = startTasks
                                            }
                                    )


startTasksFromBotRequest :
    BotRequest
    -> StateIncludingSetup botSettings bot
    -> ( StateIncludingSetup botSettings bot, List InternalStartTask )
startTasksFromBotRequest botRequest stateBefore =
    let
        closeWindowTaskFromWindowId windowId =
            ( Just "close-window"
            , InterfaceToHost.InvokeMethodOnWindowRequest windowId InterfaceToHost.CloseWindowMethod
            )

        closeWindowTasks =
            case stateBefore.webBrowser of
                Just (RunningWebBrowserState running) ->
                    [ closeWindowTaskFromWindowId running.openWindowResult.windowId ]

                Just (RunningFailedWebBrowserState _ running) ->
                    [ closeWindowTaskFromWindowId running.openWindowResult.windowId ]

                _ ->
                    []

        ( stateUpdatedForBotRequest, tasksFromBotRequest ) =
            case botRequest of
                ChromeDevToolsProtocolRuntimeEvaluateRequest runtimeEvaluateRequest ->
                    case stateBefore.webBrowser of
                        Just (RunningWebBrowserState runningWebBrowser) ->
                            let
                                taskId =
                                    runJsInPageRequestTaskIdPrefix ++ runtimeEvaluateRequest.requestId
                            in
                            ( stateBefore
                            , [ ( Just taskId
                                , InterfaceToHost.InvokeMethodOnWindowRequest
                                    runningWebBrowser.openWindowResult.windowId
                                    (InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethod
                                        { expression = runtimeEvaluateRequest.expression
                                        , awaitPromise = True
                                        }
                                    )
                                )
                              ]
                            )

                        _ ->
                            {- TODO:
                               Change handling: Maybe change return type of bot function to not support ChromeDevToolsProtocolRuntimeEvaluateRequest in that case.
                            -}
                            ( stateBefore
                            , []
                            )

                StartWebBrowserRequest startWebBrowser ->
                    let
                        openWindowTask =
                            ( Just "open-window"
                            , InterfaceToHost.OpenWindowRequest
                                { windowType =
                                    Just
                                        (InterfaceToHost.WebBrowserWindow
                                            { userDataFolder = startWebBrowser.userDataDir
                                            , language = startWebBrowser.language
                                            , isInPrivateModeEnabled = Nothing
                                            , additionalBrowserArguments = ""
                                            }
                                        )
                                , userGuide = "Web browser window to load the game."
                                }
                            )
                    in
                    ( { stateBefore
                        | webBrowser = Just (OpeningWebBrowserState startWebBrowser)
                        , startWebBrowserCount = stateBefore.startWebBrowserCount + 1
                      }
                    , openWindowTask :: closeWindowTasks
                    )

                CloseWebBrowserRequest ->
                    ( stateBefore
                    , closeWindowTasks
                    )
    in
    ( stateUpdatedForBotRequest
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


integrateFromHostEvent :
    BotConfig botSettings botState
    -> BotEventInternal
    -> StateIncludingSetup botSettings botState
    -> ( StateIncludingSetup botSettings botState, Maybe (SetupOrOperationTask InternalStartTask (BotProcessEventResult botState)) )
integrateFromHostEvent botConfig event stateBefore =
    let
        ( stateBeforeIntegrateBotEvent, maybeTask ) =
            case event of
                TimeArrivedInternal ->
                    ( stateBefore
                    , Just (OperationTask (ArrivedAtTime { timeInMilliseconds = stateBefore.timeInMilliseconds }))
                    )

                TaskCompletedInternal taskComplete ->
                    let
                        ( webBrowserState, maybeBotEventFromTaskComplete ) =
                            stateBefore.webBrowser
                                |> Maybe.map
                                    (integrateTaskResult
                                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                                        , taskId = taskComplete.taskId
                                        , taskResult = taskComplete.taskResult
                                        }
                                        >> Tuple.mapFirst Just
                                    )
                                |> Maybe.withDefault ( Nothing, Nothing )
                    in
                    ( { stateBefore
                        | webBrowser = webBrowserState
                        , tasksInProgress = Dict.remove taskComplete.taskId stateBefore.tasksInProgress
                      }
                    , maybeBotEventFromTaskComplete
                    )

                SessionDurationPlannedInternal _ ->
                    ( stateBefore, Nothing )
    in
    case maybeTask of
        Nothing ->
            ( stateBeforeIntegrateBotEvent
            , Nothing
            )

        Just (SetupTask setupTask) ->
            ( stateBeforeIntegrateBotEvent
            , Just (SetupTask setupTask)
            )

        Just (OperationTask botEvent) ->
            let
                botStateBefore =
                    stateBeforeIntegrateBotEvent.botState

                botProcessEvent =
                    buildBotProcessEventWithDefaultConfig botConfig stateBefore.botSettings

                botEventResult =
                    botStateBefore.botState
                        |> botProcessEvent botEvent { webBrowser = stateBefore.webBrowser }

                botState =
                    { botStateBefore
                        | botState = botEventResult.newState
                        , lastProcessEventStatusText = Just botEventResult.statusMessage
                    }
            in
            ( { stateBeforeIntegrateBotEvent | botState = botState }
            , Just (OperationTask botEventResult)
            )


integrateTaskResult :
    { timeInMilliseconds : Int, taskId : String, taskResult : InterfaceToHost.TaskResultStructure }
    -> WebBrowserState
    -> ( WebBrowserState, Maybe (SetupOrOperationTask InternalStartTask BotEvent) )
integrateTaskResult { timeInMilliseconds, taskId, taskResult } webBrowserStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse _ ->
            ( webBrowserStateBefore, Nothing )

        InterfaceToHost.RequestToVolatileProcessResponse _ ->
            ( webBrowserStateBefore, Nothing )

        InterfaceToHost.CompleteWithoutResult ->
            ( webBrowserStateBefore, Nothing )

        InterfaceToHost.RandomBytesResponse _ ->
            ( webBrowserStateBefore, Nothing )

        InterfaceToHost.OpenWindowResponse openWindowResult ->
            case webBrowserStateBefore of
                OpeningWebBrowserState opening ->
                    case openWindowResult of
                        Err err ->
                            ( OpeningFailedWebBrowserState err
                            , Nothing
                            )

                        Ok openWindowOk ->
                            ( RunningWebBrowserState
                                { startTimeMilliseconds = timeInMilliseconds
                                , openWindowResult = openWindowOk
                                }
                            , let
                                content =
                                    Maybe.withDefault
                                        browserDefaultContent
                                        opening.content
                              in
                              Just
                                (SetupTask
                                    { areaId = "setup-web-browser"
                                    , taskId = Just "navigate-after-open-window"
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
                                )
                            )

                _ ->
                    ( webBrowserStateBefore, Nothing )

        InterfaceToHost.InvokeMethodOnWindowResponse _ invokeMethodOnWindowResponse ->
            case invokeMethodOnWindowResponse of
                Err err ->
                    case webBrowserStateBefore of
                        RunningWebBrowserState running ->
                            let
                                errorText =
                                    case err of
                                        InterfaceToHost.WindowNotFoundError _ ->
                                            "Window not found"

                                        InterfaceToHost.MethodNotAvailableError ->
                                            "Method not available"

                                        InterfaceToHost.ReadFromWindowError readErr ->
                                            "Failed to read from window: " ++ readErr
                            in
                            ( RunningFailedWebBrowserState errorText running
                            , Nothing
                            )

                        _ ->
                            ( webBrowserStateBefore
                            , Nothing
                            )

                Ok invokeMethodOnWindowOk ->
                    case invokeMethodOnWindowOk of
                        InterfaceToHost.InvokeMethodOnWindowResultWithoutValue ->
                            ( webBrowserStateBefore
                            , Nothing
                            )

                        InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethodResult (Err _) ->
                            ( webBrowserStateBefore
                            , Nothing
                            )

                        InterfaceToHost.ReadFromWindowMethodResult _ ->
                            ( webBrowserStateBefore
                            , Nothing
                            )

                        InterfaceToHost.ChromeDevToolsProtocolRuntimeEvaluateMethodResult (Ok runJsOk) ->
                            let
                                botEvent =
                                    if String.startsWith runJsInPageRequestTaskIdPrefix taskId then
                                        Just
                                            (ChromeDevToolsProtocolRuntimeEvaluateResponse
                                                { requestId = String.dropLeft (String.length runJsInPageRequestTaskIdPrefix) taskId
                                                , returnValueJsonSerialized = runJsOk.returnValueJsonSerialized
                                                }
                                            )

                                    else
                                        Nothing
                            in
                            ( webBrowserStateBefore
                            , botEvent |> Maybe.map OperationTask
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


statusReportFromState : StateIncludingSetup settings state -> String
statusReportFromState state =
    let
        webBrowserStatus =
            case state.webBrowser of
                Nothing ->
                    "Not started"

                Just (OpeningWebBrowserState _) ->
                    "Opening..."

                Just (OpeningFailedWebBrowserState err) ->
                    "Opening failed: " ++ err

                Just (RunningWebBrowserState running) ->
                    "Running "
                        ++ running.openWindowResult.windowId
                        ++ " since "
                        ++ String.fromInt ((state.timeInMilliseconds - running.startTimeMilliseconds) // 1000)
                        ++ " seconds"

                Just (RunningFailedWebBrowserState err _) ->
                    "Running failed: " ++ err
    in
    [ state.botState.lastProcessEventStatusText |> Maybe.withDefault ""
    , "--------"
    , "Web browser status:"
    , webBrowserStatus
        ++ " (started "
        ++ String.fromInt state.startWebBrowserCount
        ++ " times)"
    ]
        |> String.join "\n"


buildBotProcessEventWithDefaultConfig :
    BotConfig settings state
    -> Maybe settings
    -> BotEvent
    -> GenericBotState
    -> state
    -> BotProcessEventResult state
buildBotProcessEventWithDefaultConfig botConfig maybeParsedSettings =
    let
        parseSettingsResult =
            maybeParsedSettings
                |> Maybe.map Ok
                |> Maybe.withDefault (botConfig.parseBotSettings "")
    in
    case parseSettingsResult of
        Err err ->
            \_ _ botState ->
                { newState = botState
                , response = FinishSession
                , statusMessage = "Failed to use an empty settings-string:\n" ++ err
                }

        Ok parsedSettings ->
            botConfig.processEvent parsedSettings

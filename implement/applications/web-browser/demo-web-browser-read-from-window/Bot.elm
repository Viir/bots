{- Demo 2023-05-15 Read from Window - Web Browser

-}
{-
   catalog-tags:demo
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2023_05_15 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree
    exposing
        ( DecisionPathNode
        , describeBranch
        , endDecisionPath
        , unpackToDecisionStagesDescriptionsAndLeaf
        )
import Dict
import Json.Decode
import Json.Encode
import Result.Extra
import WebBrowser.BotFramework as BotFramework exposing (BotEvent, BotResponse)


initBotSettings : BotSettings
initBotSettings =
    { targetScalingFactorPercent = Nothing
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "target-scale-percent"
           , { description = "Targeted scaling factor in percent"
             , valueParser =
                AppSettings.valueTypeInteger
                    (\scalingFactor settings ->
                        { settings | targetScalingFactorPercent = Just scalingFactor }
                    )
             }
           )
         ]
            |> Dict.fromList
        )
        initBotSettings


type alias BotState =
    { timeInMilliseconds : Int
    , lastRequestToPageId : Int
    , pendingRequestToPageRequestId : Maybe String
    , lastRunJavascriptResult :
        Maybe
            { timeInMilliseconds : Int
            , response : BotFramework.ChromeDevToolsProtocolRuntimeEvaluateResponseStruct
            , parseResult : Result String ResponseFromBrowser
            }
    , lastPageLocation : Maybe String
    , lastSetZoomFactorRequest : Maybe { timeInMilliseconds : Int }
    , lastGetDevicePixelRatioEvent :
        Maybe
            { timeInMilliseconds : Int
            , devicePixelRatioMikro : Int
            }
    , lastReadFromWindowResponse :
        Maybe
            { timeInMilliseconds : Int
            , result : Result String InterfaceToHost.ReadFromWindowCompleteStruct
            }
    , parseResponseError : Maybe String
    }


type alias BotSettings =
    { targetScalingFactorPercent : Maybe Int
    }


type alias EventContext =
    { webBrowser : Maybe BotFramework.WebBrowserState
    , settings : BotSettings
    }


type alias State =
    BotFramework.StateIncludingSetup BotSettings BotState


type ResponseFromBrowser
    = GetDevicePixelRatioEvent { devicePixelRatioMikro : Int }


initState : BotState
initState =
    { timeInMilliseconds = 0
    , lastRequestToPageId = 0
    , pendingRequestToPageRequestId = Nothing
    , lastRunJavascriptResult = Nothing
    , lastPageLocation = Nothing
    , lastGetDevicePixelRatioEvent = Nothing
    , lastReadFromWindowResponse = Nothing
    , parseResponseError = Nothing
    , lastSetZoomFactorRequest = Nothing
    }


botMain : InterfaceToHost.BotConfig State
botMain =
    BotFramework.webBrowserBotMain
        { init = initState
        , processEvent = processWebBrowserBotEvent
        , parseBotSettings = parseBotSettings
        }


processWebBrowserBotEvent :
    BotSettings
    -> BotEvent
    -> BotFramework.GenericBotState
    -> BotState
    -> { newState : BotState, response : BotResponse, statusMessage : String }
processWebBrowserBotEvent botSettings event genericBotState stateBeforeIntegrateEvent =
    case
        stateBeforeIntegrateEvent
            |> integrateWebBrowserBotEvent event
    of
        Err integrateEventError ->
            { newState = stateBeforeIntegrateEvent
            , response = BotFramework.FinishSession
            , statusMessage = "Error: " ++ integrateEventError
            }

        Ok stateBefore ->
            let
                ( activityDecision, maybeUpdatedState ) =
                    let
                        ( botResponse, botStateBeforeRememberStartBrowser ) =
                            maintainGameClientAndDecideNextAction
                                { webBrowser = genericBotState.webBrowser
                                , settings = botSettings
                                }
                                stateBefore

                        botState =
                            case
                                botResponse
                                    |> Common.DecisionTree.unpackToDecisionStagesDescriptionsAndLeaf
                                    |> Tuple.second
                            of
                                BotFramework.ContinueSession continueSession ->
                                    case continueSession.request of
                                        Just (BotFramework.StartWebBrowserRequest startWebBrowser) ->
                                            let
                                                lastPageLocation =
                                                    case startWebBrowser.content of
                                                        Just (BotFramework.WebSiteContent location) ->
                                                            Just location

                                                        _ ->
                                                            botStateBeforeRememberStartBrowser.lastPageLocation
                                            in
                                            { stateBefore | lastPageLocation = lastPageLocation }

                                        _ ->
                                            botStateBeforeRememberStartBrowser

                                _ ->
                                    botStateBeforeRememberStartBrowser
                    in
                    ( botResponse
                    , Just botState
                    )

                ( activityDecisionStages, responseToFramework ) =
                    activityDecision
                        |> unpackToDecisionStagesDescriptionsAndLeaf

                newState =
                    maybeUpdatedState |> Maybe.withDefault stateBefore
            in
            { newState = newState
            , response = responseToFramework
            , statusMessage = statusMessageFromState botSettings newState { activityDecisionStages = activityDecisionStages }
            }


maintainGameClientAndDecideNextAction : EventContext -> BotState -> ( DecisionPathNode BotResponse, BotState )
maintainGameClientAndDecideNextAction eventContext stateBefore =
    let
        continueWithReadDevicePixelRatio =
            ( describeBranch "Read device pixel ratio"
                (endDecisionPath
                    (BotFramework.ContinueSession
                        { request =
                            Just
                                (BotFramework.ChromeDevToolsProtocolRuntimeEvaluateRequest
                                    { expression = getDevicePixelRatioScript
                                    , requestId = "getDevicePixelRatio"
                                    }
                                )
                        , notifyWhenArrivedAtTime = Nothing
                        }
                    )
                )
            , stateBefore
            )

        continueWithReadFromWindow =
            ( describeBranch "Read from window"
                (endDecisionPath
                    (BotFramework.ContinueSession
                        { request = Just BotFramework.ReadFromWebBrowserWindowRequest
                        , notifyWhenArrivedAtTime = Nothing
                        }
                    )
                )
            , stateBefore
            )
    in
    case eventContext.webBrowser of
        Nothing ->
            ( describeBranch "Start web browser"
                (endDecisionPath
                    (BotFramework.ContinueSession
                        { request =
                            Just
                                (BotFramework.StartWebBrowserRequest
                                    { content = Nothing
                                    , userDataDir = Nothing
                                    , language = Nothing
                                    }
                                )
                        , notifyWhenArrivedAtTime = Nothing
                        }
                    )
                )
            , stateBefore
            )

        Just _ ->
            case stateBefore.lastGetDevicePixelRatioEvent of
                Nothing ->
                    continueWithReadDevicePixelRatio

                Just lastGetDevicePixelRatioEvent ->
                    case stateBefore.lastReadFromWindowResponse of
                        Nothing ->
                            continueWithReadFromWindow

                        Just lastReadFromWindowResponse ->
                            case lastReadFromWindowResponse.result of
                                Err _ ->
                                    continueWithReadFromWindow

                                Ok readFromWindowOk ->
                                    let
                                        pixelRatioPercent =
                                            lastGetDevicePixelRatioEvent.devicePixelRatioMikro // 10000

                                        continueIfZoomOk =
                                            let
                                                lastReadFromWindowAgeMilli =
                                                    stateBefore.timeInMilliseconds - lastReadFromWindowResponse.timeInMilliseconds
                                            in
                                            if
                                                lastGetDevicePixelRatioEvent.timeInMilliseconds
                                                    < (stateBefore.lastSetZoomFactorRequest
                                                        |> Maybe.map .timeInMilliseconds
                                                        |> Maybe.withDefault 0
                                                        |> max lastReadFromWindowResponse.timeInMilliseconds
                                                      )
                                            then
                                                continueWithReadDevicePixelRatio

                                            else if lastReadFromWindowAgeMilli < 4000 then
                                                ( endDecisionPath
                                                    (BotFramework.ContinueSession
                                                        { request = Nothing
                                                        , notifyWhenArrivedAtTime = Nothing
                                                        }
                                                    )
                                                , stateBefore
                                                )

                                            else
                                                continueWithReadFromWindow
                                    in
                                    if
                                        lastReadFromWindowResponse.timeInMilliseconds
                                            < (stateBefore.lastSetZoomFactorRequest
                                                |> Maybe.map .timeInMilliseconds
                                                |> Maybe.withDefault 0
                                              )
                                    then
                                        continueIfZoomOk

                                    else
                                        case eventContext.settings.targetScalingFactorPercent of
                                            Nothing ->
                                                continueIfZoomOk

                                            Just targetScalingFactorPercent ->
                                                let
                                                    scalingFactorDiffPercent =
                                                        abs (pixelRatioPercent - targetScalingFactorPercent)
                                                in
                                                if scalingFactorDiffPercent <= 1 then
                                                    continueIfZoomOk

                                                else
                                                    let
                                                        zoomFactorMikro =
                                                            ((targetScalingFactorPercent * 10000) * 96)
                                                                // readFromWindowOk.windowDpi
                                                    in
                                                    ( endDecisionPath
                                                        (BotFramework.ContinueSession
                                                            { request =
                                                                Just
                                                                    (BotFramework.SetZoomFactorRequest
                                                                        { zoomFactorMikro = zoomFactorMikro }
                                                                    )
                                                            , notifyWhenArrivedAtTime = Nothing
                                                            }
                                                        )
                                                    , { stateBefore
                                                        | lastSetZoomFactorRequest =
                                                            Just { timeInMilliseconds = stateBefore.timeInMilliseconds }
                                                      }
                                                    )


integrateWebBrowserBotEvent : BotEvent -> BotState -> Result String BotState
integrateWebBrowserBotEvent event stateBefore =
    case event of
        BotFramework.ArrivedAtTime { timeInMilliseconds } ->
            Ok { stateBefore | timeInMilliseconds = timeInMilliseconds }

        BotFramework.ChromeDevToolsProtocolRuntimeEvaluateResponse runtimeEvaluateResponse ->
            Ok
                (integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runtimeEvaluateResponse stateBefore)

        BotFramework.ReadFromWindowResponse readFromWindowResponse ->
            Ok
                { stateBefore
                    | lastReadFromWindowResponse =
                        Just
                            { timeInMilliseconds = stateBefore.timeInMilliseconds
                            , result = readFromWindowResponse
                            }
                }


integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse :
    BotFramework.ChromeDevToolsProtocolRuntimeEvaluateResponseStruct
    -> BotState
    -> BotState
integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runtimeEvaluateResponse stateBefore =
    let
        pendingRequestToPageRequestId =
            if Just runtimeEvaluateResponse.requestId == stateBefore.pendingRequestToPageRequestId then
                Nothing

            else
                stateBefore.pendingRequestToPageRequestId

        parseResult =
            runtimeEvaluateResponse.returnValueJsonSerialized
                |> Json.Decode.decodeString BotFramework.decodeRuntimeEvaluateResponse
                |> Result.mapError Json.Decode.errorToString
                |> Result.andThen
                    (\evalResult ->
                        case evalResult of
                            BotFramework.StringResultEvaluateResponse stringResult ->
                                stringResult
                                    |> Json.Decode.decodeString decodeResponseFromBrowser
                                    |> Result.mapError Json.Decode.errorToString

                            BotFramework.ExceptionEvaluateResponse exception ->
                                Err ("Web browser responded with exception: " ++ Json.Encode.encode 0 exception)

                            BotFramework.OtherResultEvaluateResponse other ->
                                Err ("Web browser responded with non-string result: " ++ Json.Encode.encode 0 other)
                    )

        stateAfterIntegrateResponse =
            { stateBefore
                | pendingRequestToPageRequestId = pendingRequestToPageRequestId
                , lastRunJavascriptResult =
                    Just
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , response = runtimeEvaluateResponse
                        , parseResult = parseResult
                        }
            }
    in
    case parseResult of
        Err error ->
            { stateAfterIntegrateResponse | parseResponseError = Just error }

        Ok parseSuccess ->
            let
                stateAfterParseSuccess =
                    { stateAfterIntegrateResponse | parseResponseError = Nothing }
            in
            case parseSuccess of
                GetDevicePixelRatioEvent getDevicePixelRatioEvent ->
                    { stateAfterParseSuccess
                        | lastGetDevicePixelRatioEvent =
                            Just
                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                , devicePixelRatioMikro = getDevicePixelRatioEvent.devicePixelRatioMikro
                                }
                    }


decodeResponseFromBrowser : Json.Decode.Decoder ResponseFromBrowser
decodeResponseFromBrowser =
    Json.Decode.oneOf
        [ decodeGetDevicePixelRatioResponse |> Json.Decode.map GetDevicePixelRatioEvent
        ]


getDevicePixelRatioScript : String
getDevicePixelRatioScript =
    """
(function getDevicePixelRatio() {

        return JSON.stringify({ getDevicePixelRatio: window.devicePixelRatio });
})()"""


decodeGetDevicePixelRatioResponse : Json.Decode.Decoder { devicePixelRatioMikro : Int }
decodeGetDevicePixelRatioResponse =
    Json.Decode.field "getDevicePixelRatio" Json.Decode.float
        |> Json.Decode.map (\ratio -> { devicePixelRatioMikro = round (ratio * 1000 * 1000) })


statusMessageFromState : BotSettings -> BotState -> { activityDecisionStages : List String } -> String
statusMessageFromState _ state { activityDecisionStages } =
    let
        jsRunResult =
            "lastRunJavascriptResult:\n"
                ++ (state.lastRunJavascriptResult |> Maybe.map .response |> describeMaybe describeRunJavascriptInCurrentPageResponseStructure)

        parseResponseErrorReport =
            case state.parseResponseError of
                Nothing ->
                    ""

                Just parseResponseError ->
                    parseResponseError

        debugInspectionLines =
            [ jsRunResult ]

        enableDebugInspection =
            False

        devicePixelRatioMikro =
            state.lastGetDevicePixelRatioEvent
                |> Maybe.map (.devicePixelRatioMikro >> String.fromInt)
                |> Maybe.withDefault "Nothing"

        activityDescription =
            activityDecisionStages
                |> List.indexedMap
                    (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                |> String.join "\n"

        readFromWindowReport =
            state.lastReadFromWindowResponse
                |> Maybe.map .result
                |> Maybe.map
                    (Result.Extra.unpack
                        identity
                        (\readFromWindowResponse ->
                            "2x2: "
                                ++ String.fromInt (List.length readFromWindowResponse.imageData.screenshotCrops_binned_2x2)
                                ++ " crops"
                        )
                    )
                |> Maybe.withDefault "Nothing"
    in
    [ [ parseResponseErrorReport ]
    , [ "devicePixelRatioMikro: " ++ devicePixelRatioMikro ]
    , [ "readFromWindow: " ++ readFromWindowReport ]
    , if enableDebugInspection then
        debugInspectionLines

      else
        []
    , [ "", "Current activity:" ]
    , [ activityDescription ]
    ]
        |> List.concat
        |> String.join "\n"


describeRunJavascriptInCurrentPageResponseStructure :
    BotFramework.ChromeDevToolsProtocolRuntimeEvaluateResponseStruct
    -> String
describeRunJavascriptInCurrentPageResponseStructure response =
    "{ returnValueJsonSerialized = "
        ++ describeString 300 response.returnValueJsonSerialized
        ++ "\n}"


describeString : Int -> String -> String
describeString maxLength =
    stringEllipsis maxLength "..."
        >> Json.Encode.string
        >> Json.Encode.encode 0


describeMaybe : (just -> String) -> Maybe just -> String
describeMaybe describeJust maybe =
    case maybe of
        Nothing ->
            "Nothing"

        Just just ->
            describeJust just


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

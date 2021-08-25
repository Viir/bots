module WebBrowser.VolatileProcessInterface exposing (..)

import Json.Decode
import Json.Decode.Extra
import Json.Encode


type RequestToVolatileProcess
    = StartWebBrowserRequest { pageGoToUrl : Maybe String, userProfileId : String, remoteDebuggingPort : Int }
    | RunJavascriptInCurrentPageRequest RunJavascriptInCurrentPageRequestStructure


type alias RunJavascriptInCurrentPageRequestStructure =
    { requestId : String
    , javascript : String
    , timeToWaitForCallbackMilliseconds : Int
    }


type ResponseFromVolatileProcess
    = WebBrowserStarted
    | RunJavascriptInCurrentPageResponse RunJavascriptInCurrentPageResponseStructure


type alias RunJavascriptInCurrentPageResponseStructure =
    { requestId : String
    , webBrowserAvailable : Bool
    , directReturnValueAsString : String
    , callbackReturnValueAsString : Maybe String
    }


deserializeResponseFromVolatileProcess : String -> Result Json.Decode.Error ResponseFromVolatileProcess
deserializeResponseFromVolatileProcess =
    Json.Decode.decodeString decodeResponseFromVolatileProcess


decodeResponseFromVolatileProcess : Json.Decode.Decoder ResponseFromVolatileProcess
decodeResponseFromVolatileProcess =
    Json.Decode.oneOf
        [ Json.Decode.field "WebBrowserStarted" (Json.Decode.succeed WebBrowserStarted)
        , Json.Decode.field "RunJavascriptInCurrentPageResponse" decodeRunJavascriptInCurrentPageResponse
            |> Json.Decode.map RunJavascriptInCurrentPageResponse
        ]


encodeRequestToVolatileProcess : RequestToVolatileProcess -> Json.Encode.Value
encodeRequestToVolatileProcess request =
    case request of
        StartWebBrowserRequest startWebBrowserRequest ->
            Json.Encode.object
                [ ( "StartWebBrowserRequest"
                  , Json.Encode.object
                        [ ( "pageGoToUrl"
                          , startWebBrowserRequest.pageGoToUrl |> Maybe.map Json.Encode.string |> Maybe.withDefault Json.Encode.null
                          )
                        , ( "userProfileId"
                          , startWebBrowserRequest.userProfileId |> Json.Encode.string
                          )
                        , ( "remoteDebuggingPort"
                          , startWebBrowserRequest.remoteDebuggingPort |> Json.Encode.int
                          )
                        ]
                  )
                ]

        RunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest ->
            Json.Encode.object [ ( "RunJavascriptInCurrentPageRequest", runJavascriptInCurrentPageRequest |> encodeRunJavascriptInCurrentPageRequest ) ]


encodeRunJavascriptInCurrentPageRequest : RunJavascriptInCurrentPageRequestStructure -> Json.Encode.Value
encodeRunJavascriptInCurrentPageRequest runJavascriptInCurrentPageRequest =
    Json.Encode.object
        [ ( "requestId", runJavascriptInCurrentPageRequest.requestId |> Json.Encode.string )
        , ( "javascript", runJavascriptInCurrentPageRequest.javascript |> Json.Encode.string )
        , ( "timeToWaitForCallbackMilliseconds", runJavascriptInCurrentPageRequest.timeToWaitForCallbackMilliseconds |> Json.Encode.int )
        ]


decodeRunJavascriptInCurrentPageResponse : Json.Decode.Decoder RunJavascriptInCurrentPageResponseStructure
decodeRunJavascriptInCurrentPageResponse =
    Json.Decode.map4 RunJavascriptInCurrentPageResponseStructure
        (Json.Decode.field "requestId" Json.Decode.string)
        (Json.Decode.field "webBrowserAvailable" Json.Decode.bool)
        (Json.Decode.field "directReturnValueAsString" Json.Decode.string)
        (Json.Decode.Extra.optionalField "callbackReturnValueAsString" Json.Decode.string)


buildRequestStringToGetResponseFromVolatileProcess : RequestToVolatileProcess -> String
buildRequestStringToGetResponseFromVolatileProcess =
    encodeRequestToVolatileProcess
        >> Json.Encode.encode 0

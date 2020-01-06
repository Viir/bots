module Limbara.Limbara exposing
    ( RequestToVolatileHost(..)
    , ResponseFromVolatileHost(..)
    , buildScriptToGetResponseFromVolatileHost
    , deserializeResponseFromVolatileHost
    )

import Json.Decode
import Json.Decode.Extra
import Json.Encode


type RequestToVolatileHost
    = StartWebBrowserRequest
    | RunJavascriptInCurrentPageRequest RunJavascriptInCurrentPageRequestStructure


type alias RunJavascriptInCurrentPageRequestStructure =
    { requestId : String
    , javascript : String
    , timeToWaitForCallbackMilliseconds : Int
    }


type ResponseFromVolatileHost
    = WebBrowserStarted
    | RunJavascriptInCurrentPageResponse RunJavascriptInCurrentPageResponseStructure


type alias RunJavascriptInCurrentPageResponseStructure =
    { directReturnValueAsString : String
    , callbackReturnValueAsString : Maybe String
    }


deserializeResponseFromVolatileHost : String -> Result Json.Decode.Error ResponseFromVolatileHost
deserializeResponseFromVolatileHost =
    Json.Decode.decodeString decodeResponseFromVolatileHost


decodeResponseFromVolatileHost : Json.Decode.Decoder ResponseFromVolatileHost
decodeResponseFromVolatileHost =
    Json.Decode.oneOf
        [ Json.Decode.field "WebBrowserStarted" (Json.Decode.succeed WebBrowserStarted)
        , Json.Decode.field "RunJavascriptInCurrentPageResponse" decodeRunJavascriptInCurrentPageResponse
            |> Json.Decode.map RunJavascriptInCurrentPageResponse
        ]


encodeRequestToVolatileHost : RequestToVolatileHost -> Json.Encode.Value
encodeRequestToVolatileHost request =
    case request of
        StartWebBrowserRequest ->
            Json.Encode.object [ ( "StartWebBrowserRequest", Json.Encode.object [] ) ]

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
    Json.Decode.map2 RunJavascriptInCurrentPageResponseStructure
        (Json.Decode.field "directReturnValueAsString" Json.Decode.string)
        (Json.Decode.Extra.optionalField "callbackReturnValueAsString" Json.Decode.string)


buildScriptToGetResponseFromVolatileHost : RequestToVolatileHost -> String
buildScriptToGetResponseFromVolatileHost request =
    "serialRequest("
        ++ (request
                |> encodeRequestToVolatileHost
                |> Json.Encode.encode 0
                |> Json.Encode.string
                |> Json.Encode.encode 0
           )
        ++ ")"

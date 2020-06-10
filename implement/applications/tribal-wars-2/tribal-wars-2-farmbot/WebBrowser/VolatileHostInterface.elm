module WebBrowser.VolatileHostInterface exposing
    ( RequestToVolatileHost(..)
    , ResponseFromVolatileHost(..)
    , buildRequestStringToGetResponseFromVolatileHost
    , deserializeResponseFromVolatileHost
    )

import Json.Decode
import Json.Decode.Extra
import Json.Encode


type RequestToVolatileHost
    = StartWebBrowserRequest { pageGoToUrl : Maybe String }
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
    { requestId : String
    , directReturnValueAsString : String
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
        StartWebBrowserRequest startWebBrowserRequest ->
            Json.Encode.object
                [ ( "StartWebBrowserRequest"
                  , Json.Encode.object
                        [ ( "pageGoToUrl"
                          , startWebBrowserRequest.pageGoToUrl |> Maybe.map Json.Encode.string |> Maybe.withDefault Json.Encode.null
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
    Json.Decode.map3 RunJavascriptInCurrentPageResponseStructure
        (Json.Decode.field "requestId" Json.Decode.string)
        (Json.Decode.field "directReturnValueAsString" Json.Decode.string)
        (Json.Decode.Extra.optionalField "callbackReturnValueAsString" Json.Decode.string)


buildRequestStringToGetResponseFromVolatileHost : RequestToVolatileHost -> String
buildRequestStringToGetResponseFromVolatileHost =
    encodeRequestToVolatileHost
        >> Json.Encode.encode 0

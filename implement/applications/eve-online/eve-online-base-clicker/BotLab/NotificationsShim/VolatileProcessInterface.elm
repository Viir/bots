module BotLab.NotificationsShim.VolatileProcessInterface exposing (..)

import Json.Decode
import Json.Encode


type RequestToVolatileHost
    = EffectConsoleBeepSequence (List ConsoleBeepStructure)


type ResponseFromVolatileHost
    = CompletedEffectSequenceOnWindow


type alias ConsoleBeepStructure =
    { frequency : Int
    , durationInMs : Int
    }


deserializeResponseFromVolatileHost : String -> Result Json.Decode.Error ResponseFromVolatileHost
deserializeResponseFromVolatileHost =
    Json.Decode.decodeString decodeResponseFromVolatileHost


decodeResponseFromVolatileHost : Json.Decode.Decoder ResponseFromVolatileHost
decodeResponseFromVolatileHost =
    Json.Decode.oneOf
        [ Json.Decode.field "CompletedEffectSequenceOnWindow" (jsonDecodeSucceedWhenNotNull CompletedEffectSequenceOnWindow)
        ]


encodeRequestToVolatileHost : RequestToVolatileHost -> Json.Encode.Value
encodeRequestToVolatileHost request =
    case request of
        EffectConsoleBeepSequence effectConsoleBeepSequence ->
            Json.Encode.object [ ( "EffectConsoleBeepSequence", effectConsoleBeepSequence |> Json.Encode.list encodeConsoleBeep ) ]


decodeRequestToVolatileHost : Json.Decode.Decoder RequestToVolatileHost
decodeRequestToVolatileHost =
    Json.Decode.oneOf
        [ Json.Decode.field "EffectConsoleBeepSequence" (Json.Decode.list decodeConsoleBeep |> Json.Decode.map EffectConsoleBeepSequence)
        ]


buildRequestStringToGetResponseFromVolatileHost : RequestToVolatileHost -> String
buildRequestStringToGetResponseFromVolatileHost =
    encodeRequestToVolatileHost
        >> Json.Encode.encode 0


encodeConsoleBeep : ConsoleBeepStructure -> Json.Encode.Value
encodeConsoleBeep consoleBeep =
    Json.Encode.object
        [ ( "frequency", consoleBeep.frequency |> Json.Encode.int )
        , ( "durationInMs", consoleBeep.durationInMs |> Json.Encode.int )
        ]


decodeConsoleBeep : Json.Decode.Decoder ConsoleBeepStructure
decodeConsoleBeep =
    Json.Decode.map2 ConsoleBeepStructure
        (Json.Decode.field "frequency" Json.Decode.int)
        (Json.Decode.field "durationInMs" Json.Decode.int)


jsonDecodeSucceedWhenNotNull : a -> Json.Decode.Decoder a
jsonDecodeSucceedWhenNotNull valueIfNotNull =
    Json.Decode.value
        |> Json.Decode.andThen
            (\asValue ->
                if asValue == Json.Encode.null then
                    Json.Decode.fail "Is null."

                else
                    Json.Decode.succeed valueIfNotNull
            )

-- Do not change anything in this file, as it is used to tell the bot running app which framework your bot depends on.


module Sanderling_Interface_20190514 exposing
    ( BotEffect(..)
    , BotEvent(..)
    , BotEventAtTime
    , BotRequest(..)
    , Location
    , MemoryMeasurement
    , MouseButton(..)
    , deserializeBotEventAtTime
    , mouseClickAtLocation
    , wrapBotStepForSerialInterface
    , wrapInitForSerialInterface
    )

import Json.Decode
import Json.Decode.Extra
import Json.Encode


type alias BotEventAtTime =
    { timeInMilliseconds : Int
    , event : BotEvent
    }


{-| `SetSessionTimeLimitInMilliseconds` uses the same clock as `BotEventAtTime.timeInMilliseconds`.
-}
type BotEvent
    = MemoryMeasurementFinished (Result String MemoryMeasurement)
    | SetSessionTimeLimitInMilliseconds Int


type BotStepResult
    = DecodeError String
    | DecodeSuccess (List BotRequest)


{-| `TakeMemoryMeasurementAtTimeInMilliseconds` uses the same clock as `BotEventAtTime.timeInMilliseconds`.
-}
type BotRequest
    = TakeMemoryMeasurementAtTimeInMilliseconds Int
    | ReportStatus String
    | Effect BotEffect
    | FinishSession


type alias MemoryMeasurement =
    { reducedWithNamedNodesJson : Maybe String
    }


type BotEffect
    = SimpleEffect SimpleBotEffect


type SimpleBotEffect
    = SimpleMouseClickAtLocation MouseClickAtLocation


type alias MouseClickAtLocation =
    { location : Location
    , mouseButton : MouseButton
    }


type MouseButton
    = MouseButtonLeft
    | MouseButtonRight


type alias Location =
    { x : Int, y : Int }


wrapBotStepForSerialInterface : (BotEventAtTime -> state -> ( state, List BotRequest )) -> String -> state -> ( state, String )
wrapBotStepForSerialInterface botStep serializedBotEventAtTime stateBefore =
    let
        ( state, response ) =
            case serializedBotEventAtTime |> deserializeBotEventAtTime of
                Err error ->
                    ( stateBefore
                    , ("Failed to deserialize event: " ++ (error |> Json.Decode.errorToString))
                        |> DecodeError
                    )

                Ok botEventAtTime ->
                    stateBefore
                        |> botStep botEventAtTime
                        |> Tuple.mapSecond DecodeSuccess
    in
    ( state, response |> encodeResponseOverSerialInterface |> Json.Encode.encode 0 )


wrapInitForSerialInterface : ( state, List BotRequest ) -> ( state, String )
wrapInitForSerialInterface =
    Tuple.mapSecond (Json.Encode.list encodeBotRequest >> Json.Encode.encode 0)


deserializeBotEventAtTime : String -> Result Json.Decode.Error BotEventAtTime
deserializeBotEventAtTime =
    Json.Decode.decodeString decodeBotEventAtTime


decodeBotEventAtTime : Json.Decode.Decoder BotEventAtTime
decodeBotEventAtTime =
    Json.Decode.map2 BotEventAtTime
        (Json.Decode.field "timeInMilliseconds" Json.Decode.int)
        (Json.Decode.field "event" decodeBotEvent)


decodeBotEvent : Json.Decode.Decoder BotEvent
decodeBotEvent =
    Json.Decode.oneOf
        [ Json.Decode.field "memoryMeasurementFinished" (decodeResult Json.Decode.string decodeMemoryMeasurement)
            |> Json.Decode.map MemoryMeasurementFinished
        , Json.Decode.field "setSessionTimeLimitInMilliseconds" Json.Decode.int
            |> Json.Decode.map SetSessionTimeLimitInMilliseconds
        ]


decodeMemoryMeasurement : Json.Decode.Decoder MemoryMeasurement
decodeMemoryMeasurement =
    Json.Decode.map MemoryMeasurement
        (Json.Decode.Extra.optionalField "reducedWithNamedNodesJson" Json.Decode.string)


encodeResponseOverSerialInterface : BotStepResult -> Json.Encode.Value
encodeResponseOverSerialInterface stepResult =
    case stepResult of
        DecodeError errorString ->
            Json.Encode.object [ ( "decodeError", errorString |> Json.Encode.string ) ]

        DecodeSuccess botRequests ->
            Json.Encode.object
                [ ( "decodeSuccess"
                  , Json.Encode.object [ ( "botRequests", botRequests |> Json.Encode.list encodeBotRequest ) ]
                  )
                ]


encodeBotRequest : BotRequest -> Json.Encode.Value
encodeBotRequest botRequest =
    case botRequest of
        TakeMemoryMeasurementAtTimeInMilliseconds timeInMilliseconds ->
            Json.Encode.object [ ( "takeMemoryMeasurementAtTimeInMilliseconds", timeInMilliseconds |> Json.Encode.int ) ]

        ReportStatus status ->
            Json.Encode.object [ ( "reportStatus", status |> Json.Encode.string ) ]

        Effect botEffect ->
            Json.Encode.object [ ( "effect", botEffect |> encodeBotEffect ) ]

        FinishSession ->
            Json.Encode.object [ ( "finishSession", Json.Encode.object [] ) ]


encodeBotEffect : BotEffect -> Json.Encode.Value
encodeBotEffect botEffect =
    case botEffect of
        SimpleEffect simpleBotEffect ->
            Json.Encode.object [ ( "simpleEffect", simpleBotEffect |> encodeSimpleBotEffect ) ]


encodeSimpleBotEffect : SimpleBotEffect -> Json.Encode.Value
encodeSimpleBotEffect simpleBotEffect =
    case simpleBotEffect of
        SimpleMouseClickAtLocation mouseClickAtLocation_ ->
            Json.Encode.object [ ( "simpleMouseClickAtLocation", mouseClickAtLocation_ |> encodeMouseClickAtLocation ) ]


encodeMouseClickAtLocation : MouseClickAtLocation -> Json.Encode.Value
encodeMouseClickAtLocation mouseClickAtLocation_ =
    Json.Encode.object
        [ ( "location", mouseClickAtLocation_.location |> encodeLocation )
        , ( "mouseButton", mouseClickAtLocation_.mouseButton |> encodeMouseButton )
        ]


encodeLocation : Location -> Json.Encode.Value
encodeLocation location =
    Json.Encode.object
        [ ( "x", location.x |> Json.Encode.int )
        , ( "y", location.y |> Json.Encode.int )
        ]


encodeMouseButton : MouseButton -> Json.Encode.Value
encodeMouseButton mouseButton =
    (case mouseButton of
        MouseButtonLeft ->
            "left"

        MouseButtonRight ->
            "right"
    )
        |> Json.Encode.string


mouseClickAtLocation : Location -> MouseButton -> BotEffect
mouseClickAtLocation location mouseButton =
    SimpleMouseClickAtLocation { location = location, mouseButton = mouseButton } |> SimpleEffect


decodeResult : Json.Decode.Decoder error -> Json.Decode.Decoder ok -> Json.Decode.Decoder (Result error ok)
decodeResult errorDecoder okDecoder =
    Json.Decode.oneOf
        [ Json.Decode.field "err" errorDecoder |> Json.Decode.map Err
        , Json.Decode.field "ok" okDecoder |> Json.Decode.map Ok
        ]

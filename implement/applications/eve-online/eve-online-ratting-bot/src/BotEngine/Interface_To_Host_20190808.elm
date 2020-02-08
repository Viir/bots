{- Do not change this file. The engine uses this file to see on which framework your bot depends.
   The encoding and decoding of interface messages here mirrors the implementation of the bot running engine.
-}


module BotEngine.Interface_To_Host_20190808 exposing
    ( BotEvent(..)
    , BotResponse(..)
    , ProcessSerializedEventResponse(..)
    , RunInVolatileHostComplete
    , RunInVolatileHostError(..)
    , StartTaskStructure
    , Task(..)
    , TaskId
    , TaskResultStructure(..)
    , VolatileHostId
    , deserializeBotEvent
    , elmEntryPoint
    , taskIdFromString
    , wrapForSerialInterface_processEvent
    )

import Json.Decode
import Json.Encode


type BotEvent
    = ArrivedAtTime { timeInMilliseconds : Int }
    | SetBotConfiguration String
    | CompletedTask CompletedTaskStructure
    | SetSessionTimeLimit { timeInMilliseconds : Int }


type BotResponse
    = ContinueSession BotResponseContinueSession
    | FinishSession BotResponseFinishSession


type alias CompletedTaskStructure =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = CreateVolatileHostResponse (Result CreateVolatileHostError CreateVolatileHostComplete)
    | RunInVolatileHostResponse (Result RunInVolatileHostError RunInVolatileHostComplete)
    | CompleteWithoutResult


type alias CreateVolatileHostError =
    ()


type alias CreateVolatileHostComplete =
    { hostId : VolatileHostId }


type RunInVolatileHostError
    = HostNotFound


type alias RunInVolatileHostComplete =
    { exceptionToString : Maybe String
    , returnValueToString : Maybe String
    , durationInMilliseconds : Int
    }


type alias ReleaseVolatileHostStructure =
    { hostId : VolatileHostId }


type ProcessSerializedEventResponse
    = DecodeEventError String
    | DecodeEventSuccess BotResponse


type alias BotResponseContinueSession =
    { statusDescriptionText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias BotResponseFinishSession =
    { statusDescriptionText : String
    }


{-| Tasks can yield some result to return to the bot. That is why we use the identifier.
-}
type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type Task
    = CreateVolatileHost
    | RunInVolatileHost RunInVolatileHostStructure
    | ReleaseVolatileHost ReleaseVolatileHostStructure


type alias RunInVolatileHostStructure =
    { hostId : VolatileHostId
    , script : String
    }


type TaskId
    = TaskIdFromString String


type VolatileHostId
    = VolatileHostIdFromString String


wrapForSerialInterface_processEvent : (BotEvent -> state -> ( state, BotResponse )) -> String -> state -> ( state, String )
wrapForSerialInterface_processEvent processEvent serializedBotEventAtTime stateBefore =
    let
        ( state, response ) =
            case serializedBotEventAtTime |> deserializeBotEvent of
                Err error ->
                    ( stateBefore
                    , ("Failed to deserialize event: " ++ (error |> Json.Decode.errorToString))
                        |> DecodeEventError
                    )

                Ok botEvent ->
                    stateBefore
                        |> processEvent botEvent
                        |> Tuple.mapSecond DecodeEventSuccess
    in
    ( state, response |> encodeProcessSerializedEventResponse |> Json.Encode.encode 0 )


stringFromTaskId : TaskId -> String
stringFromTaskId taskId =
    case taskId of
        TaskIdFromString asString ->
            asString


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


stringFromVolatileHostId : VolatileHostId -> String
stringFromVolatileHostId volatileHostId =
    case volatileHostId of
        VolatileHostIdFromString asString ->
            asString


volatileHostIdFromString : String -> VolatileHostId
volatileHostIdFromString =
    VolatileHostIdFromString


deserializeBotEvent : String -> Result Json.Decode.Error BotEvent
deserializeBotEvent =
    Json.Decode.decodeString decodeBotEvent


decodeBotEvent : Json.Decode.Decoder BotEvent
decodeBotEvent =
    Json.Decode.oneOf
        [ Json.Decode.field "ArrivedAtTime" jsonDecodeRecordTimeInMilliseconds
            |> Json.Decode.map ArrivedAtTime
        , Json.Decode.field "SetBotConfiguration" Json.Decode.string
            |> Json.Decode.map SetBotConfiguration
        , Json.Decode.field "CompletedTask" decodeCompletedTaskStructure
            |> Json.Decode.map CompletedTask
        , Json.Decode.field "SetSessionTimeLimit" jsonDecodeRecordTimeInMilliseconds
            |> Json.Decode.map SetSessionTimeLimit
        ]


decodeCompletedTaskStructure : Json.Decode.Decoder CompletedTaskStructure
decodeCompletedTaskStructure =
    Json.Decode.map2 CompletedTaskStructure
        (Json.Decode.field "taskId" jsonDecodeTaskId)
        (Json.Decode.field "taskResult" decodeTaskResult)


decodeTaskResult : Json.Decode.Decoder TaskResultStructure
decodeTaskResult =
    Json.Decode.oneOf
        [ Json.Decode.field "CreateVolatileHostResponse" (jsonDecodeResult (jsonDecodeSucceedWhenNotNull ()) decodeCreateVolatileHostComplete)
            |> Json.Decode.map CreateVolatileHostResponse
        , Json.Decode.field "RunInVolatileHostResponse" (jsonDecodeResult decodeRunInVolatileHostError decodeRunInVolatileHostComplete)
            |> Json.Decode.map RunInVolatileHostResponse
        , Json.Decode.field "CompleteWithoutResult" (jsonDecodeSucceedWhenNotNull CompleteWithoutResult)
        ]


decodeCreateVolatileHostComplete : Json.Decode.Decoder CreateVolatileHostComplete
decodeCreateVolatileHostComplete =
    Json.Decode.map CreateVolatileHostComplete
        (Json.Decode.field "hostId" jsonDecodeVolatileHostId)


decodeRunInVolatileHostComplete : Json.Decode.Decoder RunInVolatileHostComplete
decodeRunInVolatileHostComplete =
    Json.Decode.map3 RunInVolatileHostComplete
        (Json.Decode.field "exceptionToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "returnValueToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "durationInMilliseconds" Json.Decode.int)


decodeRunInVolatileHostError : Json.Decode.Decoder RunInVolatileHostError
decodeRunInVolatileHostError =
    Json.Decode.oneOf
        [ Json.Decode.field "hostNotFound" (jsonDecodeSucceedWhenNotNull HostNotFound)
        ]


encodeProcessSerializedEventResponse : ProcessSerializedEventResponse -> Json.Encode.Value
encodeProcessSerializedEventResponse stepResult =
    case stepResult of
        DecodeEventError errorString ->
            Json.Encode.object [ ( "DecodeEventError", errorString |> Json.Encode.string ) ]

        DecodeEventSuccess response ->
            Json.Encode.object
                [ ( "DecodeEventSuccess", response |> encodeBotResponse ) ]


encodeBotResponse : BotResponse -> Json.Encode.Value
encodeBotResponse botResponse =
    case botResponse of
        ContinueSession continueSession ->
            Json.Encode.object [ ( "ContinueSession", continueSession |> encodeContinueSession ) ]

        FinishSession finishSession ->
            Json.Encode.object [ ( "FinishSession", finishSession |> encodeFinishSession ) ]


encodeContinueSession : BotResponseContinueSession -> Json.Encode.Value
encodeContinueSession continueSession =
    [ ( "statusDescriptionText", continueSession.statusDescriptionText |> Json.Encode.string )
    , ( "startTasks", continueSession.startTasks |> Json.Encode.list encodeStartTask )
    , ( "notifyWhenArrivedAtTime", continueSession.notifyWhenArrivedAtTime |> jsonEncodeMaybeNothingAsNull jsonEncodeRecordTimeInMilliseconds )
    ]
        |> Json.Encode.object


encodeFinishSession : BotResponseFinishSession -> Json.Encode.Value
encodeFinishSession finishSession =
    [ ( "statusDescriptionText", finishSession.statusDescriptionText |> Json.Encode.string )
    ]
        |> Json.Encode.object


encodeStartTask : StartTaskStructure -> Json.Encode.Value
encodeStartTask startTaskAfterTime =
    Json.Encode.object
        [ ( "taskId", startTaskAfterTime.taskId |> jsonEncodeTaskId )
        , ( "task", startTaskAfterTime.task |> encodeTask )
        ]


encodeTask : Task -> Json.Encode.Value
encodeTask task =
    case task of
        CreateVolatileHost ->
            Json.Encode.object [ ( "createVolatileHost", Json.Encode.object [] ) ]

        RunInVolatileHost runInVolatileHost ->
            Json.Encode.object
                [ ( "runInVolatileHost"
                  , Json.Encode.object
                        [ ( "hostId", runInVolatileHost.hostId |> jsonEncodeVolatileHostId )
                        , ( "script", runInVolatileHost.script |> Json.Encode.string )
                        ]
                  )
                ]

        ReleaseVolatileHost releaseVolatileHost ->
            Json.Encode.object
                [ ( "releaseVolatileHost"
                  , Json.Encode.object
                        [ ( "hostId", releaseVolatileHost.hostId |> jsonEncodeVolatileHostId )
                        ]
                  )
                ]


jsonEncodeRecordTimeInMilliseconds : { timeInMilliseconds : Int } -> Json.Encode.Value
jsonEncodeRecordTimeInMilliseconds { timeInMilliseconds } =
    [ ( "timeInMilliseconds", timeInMilliseconds |> Json.Encode.int ) ]
        |> Json.Encode.object


jsonDecodeRecordTimeInMilliseconds : Json.Decode.Decoder { timeInMilliseconds : Int }
jsonDecodeRecordTimeInMilliseconds =
    Json.Decode.oneOf
        [ Json.Decode.field "timeInMilliseconds" Json.Decode.int
            |> Json.Decode.map (\timeInMilliseconds -> { timeInMilliseconds = timeInMilliseconds })
        ]


jsonDecodeResult : Json.Decode.Decoder error -> Json.Decode.Decoder ok -> Json.Decode.Decoder (Result error ok)
jsonDecodeResult errorDecoder okDecoder =
    Json.Decode.oneOf
        [ Json.Decode.field "Err" errorDecoder |> Json.Decode.map Err
        , Json.Decode.field "Ok" okDecoder |> Json.Decode.map Ok
        ]


jsonEncodeMaybeNothingAsNull : (a -> Json.Encode.Value) -> Maybe a -> Json.Encode.Value
jsonEncodeMaybeNothingAsNull encoder =
    Maybe.map encoder >> Maybe.withDefault Json.Encode.null


jsonDecodeNullAsMaybeNothing : Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
jsonDecodeNullAsMaybeNothing =
    Json.Decode.nullable


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


jsonEncodeTaskId : TaskId -> Json.Encode.Value
jsonEncodeTaskId taskId =
    case taskId of
        TaskIdFromString fromString ->
            [ ( "TaskIdFromString", fromString |> Json.Encode.string ) ] |> Json.Encode.object


jsonDecodeTaskId : Json.Decode.Decoder TaskId
jsonDecodeTaskId =
    Json.Decode.oneOf
        [ Json.Decode.field "TaskIdFromString" Json.Decode.string |> Json.Decode.map TaskIdFromString
        ]


jsonEncodeVolatileHostId : VolatileHostId -> Json.Encode.Value
jsonEncodeVolatileHostId volatileHostId =
    case volatileHostId of
        VolatileHostIdFromString fromString ->
            [ ( "VolatileHostIdFromString", fromString |> Json.Encode.string ) ] |> Json.Encode.object


jsonDecodeVolatileHostId : Json.Decode.Decoder VolatileHostId
jsonDecodeVolatileHostId =
    Json.Decode.oneOf
        [ Json.Decode.field "VolatileHostIdFromString" Json.Decode.string |> Json.Decode.map VolatileHostIdFromString
        ]


{-| Support function-level dead code elimination (<https://elm-lang.org/blog/small-assets-without-the-headache>).
Elm code needed to inform the Elm compiler about our entry points.
-}
elmEntryPoint :
    botState
    -> (String -> botState -> ( botState, String ))
    -> (botState -> String)
    -> (String -> botState)
    -> Program Int botState String
elmEntryPoint initState processEventInterface serializeState deserializeState =
    Platform.worker
        { init = \_ -> ( initState, Cmd.none )
        , update =
            \_ stateBefore ->
                processEventInterface "" (stateBefore |> serializeState |> deserializeState) |> Tuple.mapSecond (always Cmd.none)
        , subscriptions = \_ -> Sub.none
        }

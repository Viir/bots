{- Do not change this file. The engine uses this file to see on which framework your app depends.
   The encoding and decoding of interface messages here mirrors the implementation of the botengine.
-}


module BotEngine.Interface_To_Host_20200824 exposing
    ( AppEvent
    , AppEventAtTime(..)
    , AppResponse(..)
    , CreateVolatileHostComplete
    , CreateVolatileHostErrorStructure
    , ProcessSerializedEventResponse(..)
    , RequestToVolatileHostComplete
    , RequestToVolatileHostError(..)
    , StartTaskStructure
    , Task(..)
    , TaskId
    , TaskResultStructure(..)
    , VolatileHostId
    , decodeAppEvent
    , decodeAppEventAtTime
    , deserializeAppEvent
    , elmEntryPoint
    , taskIdFromString
    , wrapForSerialInterface_processEvent
    )

import Json.Decode
import Json.Encode


type alias AppEvent =
    { timeInMilliseconds : Int
    , eventAtTime : AppEventAtTime
    }


type AppEventAtTime
    = TimeArrivedEvent
    | AppSettingsChangedEvent String
    | SessionDurationPlannedEvent { timeInMilliseconds : Int }
    | TaskCompletedEvent CompletedTaskStructure


type AppResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession FinishSessionStructure


type alias CompletedTaskStructure =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = CreateVolatileHostResponse (Result CreateVolatileHostErrorStructure CreateVolatileHostComplete)
    | RequestToVolatileHostResponse (Result RequestToVolatileHostError RequestToVolatileHostComplete)
    | CompleteWithoutResult


type alias CreateVolatileHostErrorStructure =
    { exceptionToString : String
    }


type alias CreateVolatileHostComplete =
    { hostId : VolatileHostId }


type RequestToVolatileHostError
    = HostNotFound


type alias RequestToVolatileHostComplete =
    { exceptionToString : Maybe String
    , returnValueToString : Maybe String
    , durationInMilliseconds : Int
    }


type alias ReleaseVolatileHostStructure =
    { hostId : VolatileHostId }


type ProcessSerializedEventResponse
    = DecodeEventError String
    | DecodeEventSuccess AppResponse


type alias ContinueSessionStructure =
    { statusDescriptionText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias FinishSessionStructure =
    { statusDescriptionText : String
    }


{-| Tasks can yield some result to return to the app. That is why we use the identifier.
-}
type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type Task
    = CreateVolatileHost CreateVolatileHostStructure
    | RequestToVolatileHost RequestToVolatileHostStructure
    | ReleaseVolatileHost ReleaseVolatileHostStructure


type alias CreateVolatileHostStructure =
    { script : String }


type alias RequestToVolatileHostStructure =
    { hostId : VolatileHostId
    , request : String
    }


type TaskId
    = TaskIdFromString String


type VolatileHostId
    = VolatileHostIdFromString String


wrapForSerialInterface_processEvent : (AppEvent -> state -> ( state, AppResponse )) -> String -> state -> ( state, String )
wrapForSerialInterface_processEvent processEvent serializedAppEventAtTime stateBefore =
    let
        ( state, response ) =
            case serializedAppEventAtTime |> deserializeAppEvent of
                Err error ->
                    ( stateBefore
                    , ("Failed to deserialize event: " ++ (error |> Json.Decode.errorToString))
                        |> DecodeEventError
                    )

                Ok appEvent ->
                    stateBefore
                        |> processEvent appEvent
                        |> Tuple.mapSecond DecodeEventSuccess
    in
    ( state, response |> encodeProcessSerializedEventResponse |> Json.Encode.encode 0 )


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


deserializeAppEvent : String -> Result Json.Decode.Error AppEvent
deserializeAppEvent =
    Json.Decode.decodeString decodeAppEvent


decodeAppEvent : Json.Decode.Decoder AppEvent
decodeAppEvent =
    Json.Decode.map2 AppEvent
        (Json.Decode.field "timeInMilliseconds" Json.Decode.int)
        (Json.Decode.field "eventAtTime" decodeAppEventAtTime)


decodeAppEventAtTime : Json.Decode.Decoder AppEventAtTime
decodeAppEventAtTime =
    Json.Decode.oneOf
        [ Json.Decode.field "TimeArrivedEvent" (Json.Decode.index 0 (Json.Decode.succeed TimeArrivedEvent))
        , Json.Decode.field "AppSettingsChangedEvent" (Json.Decode.index 0 Json.Decode.string)
            |> Json.Decode.map AppSettingsChangedEvent
        , Json.Decode.field "SessionDurationPlannedEvent" (Json.Decode.index 0 jsonDecodeRecordTimeInMilliseconds)
            |> Json.Decode.map SessionDurationPlannedEvent
        , Json.Decode.field "TaskCompletedEvent" (Json.Decode.index 0 decodeCompletedTaskStructure)
            |> Json.Decode.map TaskCompletedEvent
        ]


decodeCompletedTaskStructure : Json.Decode.Decoder CompletedTaskStructure
decodeCompletedTaskStructure =
    Json.Decode.map2 CompletedTaskStructure
        (Json.Decode.field "taskId" jsonDecodeTaskId)
        (Json.Decode.field "taskResult" decodeTaskResult)


decodeTaskResult : Json.Decode.Decoder TaskResultStructure
decodeTaskResult =
    Json.Decode.oneOf
        [ Json.Decode.field "CreateVolatileHostResponse" (jsonDecodeResult decodeCreateVolatileHostError decodeCreateVolatileHostComplete)
            |> Json.Decode.map CreateVolatileHostResponse
        , Json.Decode.field "RequestToVolatileHostResponse" (jsonDecodeResult decodeRequestToVolatileHostError decodeRequestToVolatileHostComplete)
            |> Json.Decode.map RequestToVolatileHostResponse
        , Json.Decode.field "CompleteWithoutResult" (jsonDecodeSucceedWhenNotNull CompleteWithoutResult)
        ]


decodeCreateVolatileHostError : Json.Decode.Decoder CreateVolatileHostErrorStructure
decodeCreateVolatileHostError =
    Json.Decode.map CreateVolatileHostErrorStructure
        (Json.Decode.field "exceptionToString" Json.Decode.string)


decodeCreateVolatileHostComplete : Json.Decode.Decoder CreateVolatileHostComplete
decodeCreateVolatileHostComplete =
    Json.Decode.map CreateVolatileHostComplete
        (Json.Decode.field "hostId" jsonDecodeVolatileHostId)


decodeRequestToVolatileHostComplete : Json.Decode.Decoder RequestToVolatileHostComplete
decodeRequestToVolatileHostComplete =
    Json.Decode.map3 RequestToVolatileHostComplete
        (Json.Decode.field "exceptionToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "returnValueToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "durationInMilliseconds" Json.Decode.int)


decodeRequestToVolatileHostError : Json.Decode.Decoder RequestToVolatileHostError
decodeRequestToVolatileHostError =
    Json.Decode.oneOf
        [ Json.Decode.field "HostNotFound" (jsonDecodeSucceedWhenNotNull HostNotFound)
        ]


encodeProcessSerializedEventResponse : ProcessSerializedEventResponse -> Json.Encode.Value
encodeProcessSerializedEventResponse stepResult =
    case stepResult of
        DecodeEventError errorString ->
            Json.Encode.object [ ( "DecodeEventError", errorString |> Json.Encode.string ) ]

        DecodeEventSuccess response ->
            Json.Encode.object
                [ ( "DecodeEventSuccess", response |> encodeAppResponse ) ]


encodeAppResponse : AppResponse -> Json.Encode.Value
encodeAppResponse appResponse =
    case appResponse of
        ContinueSession continueSession ->
            Json.Encode.object [ ( "ContinueSession", continueSession |> encodeContinueSession ) ]

        FinishSession finishSession ->
            Json.Encode.object [ ( "FinishSession", finishSession |> encodeFinishSession ) ]


encodeContinueSession : ContinueSessionStructure -> Json.Encode.Value
encodeContinueSession continueSession =
    [ ( "statusDescriptionText", continueSession.statusDescriptionText |> Json.Encode.string )
    , ( "startTasks", continueSession.startTasks |> Json.Encode.list encodeStartTask )
    , ( "notifyWhenArrivedAtTime", continueSession.notifyWhenArrivedAtTime |> jsonEncodeMaybeNothingAsNull jsonEncodeRecordTimeInMilliseconds )
    ]
        |> Json.Encode.object


encodeFinishSession : FinishSessionStructure -> Json.Encode.Value
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
        CreateVolatileHost createVolatileHost ->
            Json.Encode.object
                [ ( "CreateVolatileHost"
                  , Json.Encode.object [ ( "script", createVolatileHost.script |> Json.Encode.string ) ]
                  )
                ]

        RequestToVolatileHost requestToVolatileHost ->
            Json.Encode.object
                [ ( "RequestToVolatileHost"
                  , Json.Encode.object
                        [ ( "hostId", requestToVolatileHost.hostId |> jsonEncodeVolatileHostId )
                        , ( "request", requestToVolatileHost.request |> Json.Encode.string )
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
    appState
    -> (String -> appState -> ( appState, String ))
    -> (appState -> String)
    -> (String -> appState)
    -> Program Int appState String
elmEntryPoint initState processEventInterface serializeState deserializeState =
    Platform.worker
        { init = \_ -> ( initState, Cmd.none )
        , update =
            \_ stateBefore ->
                processEventInterface "" (stateBefore |> serializeState |> deserializeState) |> Tuple.mapSecond (always Cmd.none)
        , subscriptions = \_ -> Sub.none
        }

{- Do not change this file. The engine uses this file to see on which framework your app depends.
   The encoding and decoding of interface messages here mirrors the hosting engine's implementation in the `botengine.exe` program.
   The app uses the types and deserialization functions to decode the event data coming from the engine.
   You can see each event's concrete representation as a string in the event details view in devtools (https://to.botengine.org/guide/observing-and-inspecting-an-app).
-}


module BotEngine.Interface_To_Host_20201207 exposing (..)

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
    | FailedToAcquireInputFocus


type alias RequestToVolatileHostComplete =
    { exceptionToString : Maybe String
    , returnValueToString : Maybe String
    , durationInMilliseconds : Int
    , acquireInputFocusDurationMilliseconds : Int
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
    | RequestToVolatileHost RequestToVolatileHostConsideringInputFocusStructure
    | ReleaseVolatileHost ReleaseVolatileHostStructure


type alias CreateVolatileHostStructure =
    { script : String }


type RequestToVolatileHostConsideringInputFocusStructure
    = RequestRequiringInputFocus RequestToVolatileHostRequiringInputFocusStructure
    | RequestNotRequiringInputFocus RequestToVolatileHostStructure


type alias RequestToVolatileHostRequiringInputFocusStructure =
    { request : RequestToVolatileHostStructure
    , acquireInputFocus : AcquireInputFocusStructure
    }


type alias RequestToVolatileHostStructure =
    { hostId : VolatileHostId
    , request : String
    }


type alias AcquireInputFocusStructure =
    { maximumDelayMilliseconds : Int
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
    ( state, response |> jsonEncodeProcessSerializedEventResponse |> Json.Encode.encode 0 )


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


deserializeAppEvent : String -> Result Json.Decode.Error AppEvent
deserializeAppEvent =
    Json.Decode.decodeString jsonDecodeAppEvent


jsonDecodeAppEvent : Json.Decode.Decoder AppEvent
jsonDecodeAppEvent =
    Json.Decode.map2 AppEvent
        (Json.Decode.field "timeInMilliseconds" Json.Decode.int)
        (Json.Decode.field "eventAtTime" jsonDecodeAppEventAtTime)


jsonDecodeAppEventAtTime : Json.Decode.Decoder AppEventAtTime
jsonDecodeAppEventAtTime =
    Json.Decode.oneOf
        [ Json.Decode.field "TimeArrivedEvent" (Json.Decode.index 0 (Json.Decode.succeed TimeArrivedEvent))
        , Json.Decode.field "AppSettingsChangedEvent" (Json.Decode.index 0 Json.Decode.string)
            |> Json.Decode.map AppSettingsChangedEvent
        , Json.Decode.field "SessionDurationPlannedEvent" (Json.Decode.index 0 jsonDecodeRecordTimeInMilliseconds)
            |> Json.Decode.map SessionDurationPlannedEvent
        , Json.Decode.field "TaskCompletedEvent" (Json.Decode.index 0 jsonDecodeCompletedTaskStructure)
            |> Json.Decode.map TaskCompletedEvent
        ]


jsonDecodeCompletedTaskStructure : Json.Decode.Decoder CompletedTaskStructure
jsonDecodeCompletedTaskStructure =
    Json.Decode.map2 CompletedTaskStructure
        (Json.Decode.field "taskId" jsonDecodeTaskId)
        (Json.Decode.field "taskResult" jsonDecodeTaskResult)


jsonDecodeTaskResult : Json.Decode.Decoder TaskResultStructure
jsonDecodeTaskResult =
    Json.Decode.oneOf
        [ Json.Decode.field "CreateVolatileHostResponse"
            (jsonDecodeResult jsonDecodeCreateVolatileHostError jsonDecodeCreateVolatileHostComplete)
            |> Json.Decode.map CreateVolatileHostResponse
        , Json.Decode.field "RequestToVolatileHostResponse"
            (jsonDecodeResult jsonDecodeRequestToVolatileHostError jsonDecodeRequestToVolatileHostComplete)
            |> Json.Decode.map RequestToVolatileHostResponse
        , Json.Decode.field "CompleteWithoutResult" (jsonDecodeSucceedWhenNotNull CompleteWithoutResult)
        ]


jsonDecodeCreateVolatileHostError : Json.Decode.Decoder CreateVolatileHostErrorStructure
jsonDecodeCreateVolatileHostError =
    Json.Decode.map CreateVolatileHostErrorStructure
        (Json.Decode.field "exceptionToString" Json.Decode.string)


jsonDecodeCreateVolatileHostComplete : Json.Decode.Decoder CreateVolatileHostComplete
jsonDecodeCreateVolatileHostComplete =
    Json.Decode.map CreateVolatileHostComplete
        (Json.Decode.field "hostId" jsonDecodeVolatileHostId)


jsonDecodeRequestToVolatileHostComplete : Json.Decode.Decoder RequestToVolatileHostComplete
jsonDecodeRequestToVolatileHostComplete =
    Json.Decode.map4 RequestToVolatileHostComplete
        (Json.Decode.field "exceptionToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "returnValueToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "durationInMilliseconds" Json.Decode.int)
        (Json.Decode.field "acquireInputFocusDurationMilliseconds" Json.Decode.int)


jsonDecodeRequestToVolatileHostError : Json.Decode.Decoder RequestToVolatileHostError
jsonDecodeRequestToVolatileHostError =
    Json.Decode.oneOf
        [ Json.Decode.field "HostNotFound" (jsonDecodeSucceedWhenNotNull HostNotFound)
        , Json.Decode.field "FailedToAcquireInputFocus" (jsonDecodeSucceedWhenNotNull FailedToAcquireInputFocus)
        ]


jsonEncodeProcessSerializedEventResponse : ProcessSerializedEventResponse -> Json.Encode.Value
jsonEncodeProcessSerializedEventResponse stepResult =
    case stepResult of
        DecodeEventError errorString ->
            Json.Encode.object [ ( "DecodeEventError", errorString |> Json.Encode.string ) ]

        DecodeEventSuccess response ->
            Json.Encode.object
                [ ( "DecodeEventSuccess", response |> jsonEncodeAppResponse ) ]


jsonDecodeProcessSerializedEventResponse : Json.Decode.Decoder ProcessSerializedEventResponse
jsonDecodeProcessSerializedEventResponse =
    Json.Decode.oneOf
        [ Json.Decode.field "DecodeEventError" Json.Decode.string |> Json.Decode.map DecodeEventError
        , Json.Decode.field "DecodeEventSuccess" jsonDecodeAppResponse |> Json.Decode.map DecodeEventSuccess
        ]


jsonEncodeAppResponse : AppResponse -> Json.Encode.Value
jsonEncodeAppResponse appResponse =
    case appResponse of
        ContinueSession continueSession ->
            Json.Encode.object [ ( "ContinueSession", continueSession |> jsonEncodeContinueSession ) ]

        FinishSession finishSession ->
            Json.Encode.object [ ( "FinishSession", finishSession |> jsonEncodeFinishSession ) ]


jsonDecodeAppResponse : Json.Decode.Decoder AppResponse
jsonDecodeAppResponse =
    Json.Decode.oneOf
        [ Json.Decode.field "ContinueSession" jsonDecodeContinueSession |> Json.Decode.map ContinueSession
        , Json.Decode.field "FinishSession" jsonDecodeFinishSession |> Json.Decode.map FinishSession
        ]


jsonEncodeContinueSession : ContinueSessionStructure -> Json.Encode.Value
jsonEncodeContinueSession continueSession =
    [ ( "statusDescriptionText", continueSession.statusDescriptionText |> Json.Encode.string )
    , ( "startTasks", continueSession.startTasks |> Json.Encode.list jsonEncodeStartTask )
    , ( "notifyWhenArrivedAtTime", continueSession.notifyWhenArrivedAtTime |> jsonEncodeMaybeNothingAsNull jsonEncodeRecordTimeInMilliseconds )
    ]
        |> Json.Encode.object


jsonDecodeContinueSession : Json.Decode.Decoder ContinueSessionStructure
jsonDecodeContinueSession =
    Json.Decode.map3 ContinueSessionStructure
        (Json.Decode.field "statusDescriptionText" Json.Decode.string)
        (Json.Decode.field "startTasks" (Json.Decode.list jsonDecodeStartTask))
        (Json.Decode.field "notifyWhenArrivedAtTime" (jsonDecodeNullAsMaybeNothing jsonDecodeRecordTimeInMilliseconds))


jsonEncodeFinishSession : FinishSessionStructure -> Json.Encode.Value
jsonEncodeFinishSession finishSession =
    [ ( "statusDescriptionText", finishSession.statusDescriptionText |> Json.Encode.string )
    ]
        |> Json.Encode.object


jsonDecodeFinishSession : Json.Decode.Decoder FinishSessionStructure
jsonDecodeFinishSession =
    Json.Decode.map FinishSessionStructure
        (Json.Decode.field "statusDescriptionText" Json.Decode.string)


jsonEncodeStartTask : StartTaskStructure -> Json.Encode.Value
jsonEncodeStartTask startTaskAfterTime =
    Json.Encode.object
        [ ( "taskId", startTaskAfterTime.taskId |> jsonEncodeTaskId )
        , ( "task", startTaskAfterTime.task |> jsonEncodeTask )
        ]


jsonDecodeStartTask : Json.Decode.Decoder StartTaskStructure
jsonDecodeStartTask =
    Json.Decode.map2 StartTaskStructure
        (Json.Decode.field "taskId" jsonDecodeTaskId)
        (Json.Decode.field "task" jsonDecodeTask)


jsonEncodeTask : Task -> Json.Encode.Value
jsonEncodeTask task =
    case task of
        CreateVolatileHost createVolatileHost ->
            Json.Encode.object
                [ ( "CreateVolatileHost"
                  , Json.Encode.object [ ( "script", createVolatileHost.script |> Json.Encode.string ) ]
                  )
                ]

        RequestToVolatileHost requestToVolatileHostConsideringInputFocus ->
            Json.Encode.object
                [ ( "RequestToVolatileHost"
                  , case requestToVolatileHostConsideringInputFocus of
                        RequestRequiringInputFocus requiringInputFocus ->
                            Json.Encode.object
                                [ ( "RequestRequiringInputFocus"
                                  , jsonEncodeRequestToVolatileHostRequiringInputFocus requiringInputFocus
                                  )
                                ]

                        RequestNotRequiringInputFocus requestToVolatileHost ->
                            Json.Encode.object
                                [ ( "RequestNotRequiringInputFocus"
                                  , jsonEncodeRequestToVolatileHost requestToVolatileHost
                                  )
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


jsonDecodeTask : Json.Decode.Decoder Task
jsonDecodeTask =
    Json.Decode.oneOf
        [ Json.Decode.field "CreateVolatileHost"
            (Json.Decode.field "script" Json.Decode.string |> Json.Decode.map CreateVolatileHostStructure)
            |> Json.Decode.map CreateVolatileHost
        , Json.Decode.field "RequestToVolatileHost"
            (Json.Decode.oneOf
                [ Json.Decode.field "RequestRequiringInputFocus" jsonDecodeRequestToVolatileHostRequiringInputFocus |> Json.Decode.map RequestRequiringInputFocus
                , Json.Decode.field "RequestNotRequiringInputFocus" jsonDecodeRequestToVolatileHost |> Json.Decode.map RequestNotRequiringInputFocus
                ]
            )
            |> Json.Decode.map RequestToVolatileHost
        , Json.Decode.field "ReleaseVolatileHost" jsonDecodeReleaseVolatileHost |> Json.Decode.map ReleaseVolatileHost
        , Json.Decode.field "releaseVolatileHost" jsonDecodeReleaseVolatileHost |> Json.Decode.map ReleaseVolatileHost
        ]


jsonDecodeReleaseVolatileHost : Json.Decode.Decoder ReleaseVolatileHostStructure
jsonDecodeReleaseVolatileHost =
    Json.Decode.map ReleaseVolatileHostStructure (Json.Decode.field "hostId" jsonDecodeVolatileHostId)


jsonEncodeRequestToVolatileHostRequiringInputFocus : RequestToVolatileHostRequiringInputFocusStructure -> Json.Encode.Value
jsonEncodeRequestToVolatileHostRequiringInputFocus requestToVolatileHost =
    Json.Encode.object
        [ ( "request", requestToVolatileHost.request |> jsonEncodeRequestToVolatileHost )
        , ( "acquireInputFocus"
          , requestToVolatileHost.acquireInputFocus |> jsonEncodeAcquireInputFocusStructure
          )
        ]


jsonDecodeRequestToVolatileHostRequiringInputFocus : Json.Decode.Decoder RequestToVolatileHostRequiringInputFocusStructure
jsonDecodeRequestToVolatileHostRequiringInputFocus =
    Json.Decode.map2 RequestToVolatileHostRequiringInputFocusStructure
        (Json.Decode.field "request" jsonDecodeRequestToVolatileHost)
        (Json.Decode.field "acquireInputFocus" jsonDecodeAcquireInputFocus)


jsonEncodeRequestToVolatileHost : RequestToVolatileHostStructure -> Json.Encode.Value
jsonEncodeRequestToVolatileHost requestToVolatileHost =
    Json.Encode.object
        [ ( "hostId", requestToVolatileHost.hostId |> jsonEncodeVolatileHostId )
        , ( "request", requestToVolatileHost.request |> Json.Encode.string )
        ]


jsonDecodeRequestToVolatileHost : Json.Decode.Decoder RequestToVolatileHostStructure
jsonDecodeRequestToVolatileHost =
    Json.Decode.map2 RequestToVolatileHostStructure
        (Json.Decode.field "hostId" jsonDecodeVolatileHostId)
        (Json.Decode.field "request" Json.Decode.string)


jsonEncodeAcquireInputFocusStructure : AcquireInputFocusStructure -> Json.Encode.Value
jsonEncodeAcquireInputFocusStructure acquireInputFocus =
    Json.Encode.object
        [ ( "maximumDelayMilliseconds", Json.Encode.int acquireInputFocus.maximumDelayMilliseconds ) ]


jsonDecodeAcquireInputFocus : Json.Decode.Decoder AcquireInputFocusStructure
jsonDecodeAcquireInputFocus =
    Json.Decode.map AcquireInputFocusStructure
        (Json.Decode.field "maximumDelayMilliseconds" Json.Decode.int)


jsonEncodeRecordTimeInMilliseconds : { timeInMilliseconds : Int } -> Json.Encode.Value
jsonEncodeRecordTimeInMilliseconds { timeInMilliseconds } =
    [ ( "timeInMilliseconds", timeInMilliseconds |> Json.Encode.int ) ]
        |> Json.Encode.object


jsonDecodeRecordTimeInMilliseconds : Json.Decode.Decoder { timeInMilliseconds : Int }
jsonDecodeRecordTimeInMilliseconds =
    Json.Decode.field "timeInMilliseconds" Json.Decode.int
        |> Json.Decode.map (\timeInMilliseconds -> { timeInMilliseconds = timeInMilliseconds })


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

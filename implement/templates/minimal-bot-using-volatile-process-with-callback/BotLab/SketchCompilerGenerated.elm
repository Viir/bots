module BotLab.SketchCompilerGenerated exposing (..)

import Bot as CommonNameForAppRootModule
import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost exposing (..)
import Json.Decode
import Json.Encode


type ProcessSerializedEventResponse
    = DecodeEventError String
    | DecodeEventSuccess BotEventResponse


interfaceToHost_initState : CommonNameForAppRootModule.State
interfaceToHost_initState =
    CommonNameForAppRootModule.botMain.init


interfaceToHost_processEvent : String -> CommonNameForAppRootModule.State -> ( CommonNameForAppRootModule.State, String )
interfaceToHost_processEvent =
    wrapForSerialInterface_processEvent CommonNameForAppRootModule.botMain.processEvent


interfaceToHost_serializeState : CommonNameForAppRootModule.State -> String
interfaceToHost_serializeState =
    always ""


wrapForSerialInterface_processEvent : (BotEvent -> state -> ( state, BotEventResponse )) -> String -> state -> ( state, String )
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


interfaceToHost_deserializeState : String -> CommonNameForAppRootModule.State
interfaceToHost_deserializeState =
    always interfaceToHost_initState


main : Program Int CommonNameForAppRootModule.State String
main =
    elmEntryPoint
        interfaceToHost_initState
        interfaceToHost_processEvent
        interfaceToHost_serializeState
        (interfaceToHost_deserializeState >> always interfaceToHost_initState)


deserializeAppEvent : String -> Result Json.Decode.Error InterfaceToHost.BotEvent
deserializeAppEvent =
    Json.Decode.decodeString jsonDecodeAppEvent


jsonDecodeAppEvent : Json.Decode.Decoder InterfaceToHost.BotEvent
jsonDecodeAppEvent =
    Json.Decode.map2 InterfaceToHost.BotEvent
        (Json.Decode.field "timeInMilliseconds" Json.Decode.int)
        (Json.Decode.field "eventAtTime" jsonDecodeAppEventAtTime)


jsonDecodeAppEventAtTime : Json.Decode.Decoder InterfaceToHost.BotEventAtTime
jsonDecodeAppEventAtTime =
    Json.Decode.oneOf
        [ Json.Decode.field "TimeArrivedEvent" (Json.Decode.index 0 (Json.Decode.succeed InterfaceToHost.TimeArrivedEvent))
        , Json.Decode.field "BotSettingsChangedEvent" (Json.Decode.index 0 Json.Decode.string)
            |> Json.Decode.map InterfaceToHost.BotSettingsChangedEvent
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
        [ Json.Decode.field "CreateVolatileProcessResponse"
            (jsonDecodeResult jsonDecodeCreateVolatileProcessError jsonDecodeCreateVolatileProcessComplete)
            |> Json.Decode.map CreateVolatileProcessResponse
        , Json.Decode.field "RequestToVolatileProcessResponse"
            (jsonDecodeResult jsonDecodeRequestToVolatileProcessError jsonDecodeRequestToVolatileProcessComplete)
            |> Json.Decode.map RequestToVolatileProcessResponse
        , Json.Decode.field "CompleteWithoutResult" (jsonDecodeSucceedWhenNotNull CompleteWithoutResult)
        ]


jsonDecodeCreateVolatileProcessError : Json.Decode.Decoder CreateVolatileProcessErrorStructure
jsonDecodeCreateVolatileProcessError =
    Json.Decode.map CreateVolatileProcessErrorStructure
        (Json.Decode.field "exceptionToString" Json.Decode.string)


jsonDecodeCreateVolatileProcessComplete : Json.Decode.Decoder CreateVolatileProcessComplete
jsonDecodeCreateVolatileProcessComplete =
    Json.Decode.map CreateVolatileProcessComplete
        (Json.Decode.field "processId" jsonDecodeVolatileProcessId)


jsonDecodeRequestToVolatileProcessComplete : Json.Decode.Decoder RequestToVolatileProcessComplete
jsonDecodeRequestToVolatileProcessComplete =
    Json.Decode.map4 RequestToVolatileProcessComplete
        (Json.Decode.field "exceptionToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "returnValueToString" (jsonDecodeNullAsMaybeNothing Json.Decode.string))
        (Json.Decode.field "durationInMilliseconds" Json.Decode.int)
        (Json.Decode.field "acquireInputFocusDurationMilliseconds" Json.Decode.int)


jsonDecodeRequestToVolatileProcessError : Json.Decode.Decoder RequestToVolatileProcessError
jsonDecodeRequestToVolatileProcessError =
    Json.Decode.oneOf
        [ Json.Decode.field "ProcessNotFound" (jsonDecodeSucceedWhenNotNull ProcessNotFound)
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


jsonEncodeAppResponse : BotEventResponse -> Json.Encode.Value
jsonEncodeAppResponse appResponse =
    case appResponse of
        ContinueSession continueSession ->
            Json.Encode.object [ ( "ContinueSession", continueSession |> jsonEncodeContinueSession ) ]

        FinishSession finishSession ->
            Json.Encode.object [ ( "FinishSession", finishSession |> jsonEncodeFinishSession ) ]


jsonDecodeAppResponse : Json.Decode.Decoder BotEventResponse
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
        CreateVolatileProcess createVolatileProcess ->
            Json.Encode.object
                [ ( "CreateVolatileProcess"
                  , Json.Encode.object [ ( "programCode", createVolatileProcess.programCode |> Json.Encode.string ) ]
                  )
                ]

        RequestToVolatileProcess requestToVolatileProcessConsideringInputFocus ->
            Json.Encode.object
                [ ( "RequestToVolatileProcess"
                  , case requestToVolatileProcessConsideringInputFocus of
                        RequestRequiringInputFocus requiringInputFocus ->
                            Json.Encode.object
                                [ ( "RequestRequiringInputFocus"
                                  , jsonEncodeRequestToVolatileProcessRequiringInputFocus requiringInputFocus
                                  )
                                ]

                        RequestNotRequiringInputFocus requestToVolatileProcess ->
                            Json.Encode.object
                                [ ( "RequestNotRequiringInputFocus"
                                  , jsonEncodeRequestToVolatileProcess requestToVolatileProcess
                                  )
                                ]
                  )
                ]

        ReleaseVolatileProcess releaseVolatileProcess ->
            Json.Encode.object
                [ ( "ReleaseVolatileProcess"
                  , Json.Encode.object
                        [ ( "processId", releaseVolatileProcess.processId |> jsonEncodeVolatileProcessId )
                        ]
                  )
                ]


jsonDecodeTask : Json.Decode.Decoder Task
jsonDecodeTask =
    Json.Decode.oneOf
        [ Json.Decode.field "CreateVolatileProcess"
            (Json.Decode.field "programCode" Json.Decode.string |> Json.Decode.map CreateVolatileProcessStructure)
            |> Json.Decode.map CreateVolatileProcess
        , Json.Decode.field "RequestToVolatileProcess"
            (Json.Decode.oneOf
                [ Json.Decode.field "RequestRequiringInputFocus" jsonDecodeRequestToVolatileProcessRequiringInputFocus |> Json.Decode.map RequestRequiringInputFocus
                , Json.Decode.field "RequestNotRequiringInputFocus" jsonDecodeRequestToVolatileProcess |> Json.Decode.map RequestNotRequiringInputFocus
                ]
            )
            |> Json.Decode.map RequestToVolatileProcess
        , Json.Decode.field "ReleaseVolatileProcess" jsonDecodeReleaseVolatileProcess |> Json.Decode.map ReleaseVolatileProcess
        ]


jsonDecodeReleaseVolatileProcess : Json.Decode.Decoder ReleaseVolatileProcessStructure
jsonDecodeReleaseVolatileProcess =
    Json.Decode.map ReleaseVolatileProcessStructure (Json.Decode.field "processId" jsonDecodeVolatileProcessId)


jsonEncodeRequestToVolatileProcessRequiringInputFocus : RequestToVolatileProcessRequiringInputFocusStructure -> Json.Encode.Value
jsonEncodeRequestToVolatileProcessRequiringInputFocus requestToVolatileProcess =
    Json.Encode.object
        [ ( "request", requestToVolatileProcess.request |> jsonEncodeRequestToVolatileProcess )
        , ( "acquireInputFocus"
          , requestToVolatileProcess.acquireInputFocus |> jsonEncodeAcquireInputFocusStructure
          )
        ]


jsonDecodeRequestToVolatileProcessRequiringInputFocus : Json.Decode.Decoder RequestToVolatileProcessRequiringInputFocusStructure
jsonDecodeRequestToVolatileProcessRequiringInputFocus =
    Json.Decode.map2 RequestToVolatileProcessRequiringInputFocusStructure
        (Json.Decode.field "request" jsonDecodeRequestToVolatileProcess)
        (Json.Decode.field "acquireInputFocus" jsonDecodeAcquireInputFocus)


jsonEncodeRequestToVolatileProcess : RequestToVolatileProcessStructure -> Json.Encode.Value
jsonEncodeRequestToVolatileProcess requestToVolatileProcess =
    Json.Encode.object
        [ ( "processId", requestToVolatileProcess.processId |> jsonEncodeVolatileProcessId )
        , ( "request", requestToVolatileProcess.request |> Json.Encode.string )
        ]


jsonDecodeRequestToVolatileProcess : Json.Decode.Decoder RequestToVolatileProcessStructure
jsonDecodeRequestToVolatileProcess =
    Json.Decode.map2 RequestToVolatileProcessStructure
        (Json.Decode.field "processId" jsonDecodeVolatileProcessId)
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


jsonEncodeVolatileProcessId : VolatileProcessId -> Json.Encode.Value
jsonEncodeVolatileProcessId volatileProcessId =
    case volatileProcessId of
        VolatileProcessIdFromString fromString ->
            [ ( "VolatileProcessIdFromString", fromString |> Json.Encode.string ) ] |> Json.Encode.object


jsonDecodeVolatileProcessId : Json.Decode.Decoder VolatileProcessId
jsonDecodeVolatileProcessId =
    Json.Decode.field "VolatileProcessIdFromString" Json.Decode.string |> Json.Decode.map VolatileProcessIdFromString


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

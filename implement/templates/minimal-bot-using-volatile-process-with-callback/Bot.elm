module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import CompilationInterface.SourceFiles


type alias State =
    {}


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = {}
    , processEvent = processEvent
    }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotEventResponse )
processEvent botEvent stateBefore =
    case botEvent.eventAtTime of
        InterfaceToHost.BotSettingsChangedEvent _ ->
            ( stateBefore
            , InterfaceToHost.ContinueSession
                { statusDescriptionText = "Create volatile process."
                , startTasks =
                    [ { taskId = InterfaceToHost.taskIdFromString "c"
                      , task =
                            InterfaceToHost.CreateVolatileProcess
                                { programCode = CompilationInterface.SourceFiles.file____VolatileProcess_csx.utf8 }
                      }
                    ]
                , notifyWhenArrivedAtTime = Nothing
                }
            )

        InterfaceToHost.TaskCompletedEvent taskCompleted ->
            case taskCompleted.taskResult of
                InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResponse ->
                    case createVolatileProcessResponse of
                        Err error ->
                            ( stateBefore
                            , InterfaceToHost.FinishSession
                                { statusDescriptionText = "Failed to create volatile process: " ++ error.exceptionToString }
                            )

                        Ok createVolatileProcessOk ->
                            ( stateBefore
                            , InterfaceToHost.ContinueSession
                                { statusDescriptionText = "Request to volatile process."
                                , startTasks =
                                    [ { taskId = InterfaceToHost.taskIdFromString "r"
                                      , task =
                                            InterfaceToHost.RequestToVolatileProcess
                                                (InterfaceToHost.RequestNotRequiringInputFocus
                                                    { processId = createVolatileProcessOk.processId
                                                    , request = "request content"
                                                    }
                                                )
                                      }
                                    ]
                                , notifyWhenArrivedAtTime = Nothing
                                }
                            )

                InterfaceToHost.RequestToVolatileProcessResponse requestToVolatileProcessResponse ->
                    case requestToVolatileProcessResponse of
                        Err _ ->
                            ( stateBefore
                            , InterfaceToHost.FinishSession
                                { statusDescriptionText = "Failed request to volatile process." }
                            )

                        Ok requestToVolatileProcessOk ->
                            let
                                statusDescriptionText =
                                    case requestToVolatileProcessOk.returnValueToString of
                                        Nothing ->
                                            "Got no returnValueToString. exceptionToString: "
                                                ++ Maybe.withDefault "Nothing" requestToVolatileProcessOk.exceptionToString

                                        Just returnValueToString ->
                                            "Session complete: Got this response from the volatile process: "
                                                ++ returnValueToString
                            in
                            ( stateBefore
                            , InterfaceToHost.FinishSession { statusDescriptionText = statusDescriptionText }
                            )

                _ ->
                    ( stateBefore
                    , InterfaceToHost.FinishSession { statusDescriptionText = "Not implemented yet." }
                    )

        _ ->
            ( stateBefore
            , InterfaceToHost.ContinueSession
                { statusDescriptionText = "Unused event."
                , startTasks = []
                , notifyWhenArrivedAtTime = Nothing
                }
            )

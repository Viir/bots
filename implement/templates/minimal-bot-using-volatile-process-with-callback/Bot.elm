module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
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
                { statusText = "Create volatile process."
                , startTasks =
                    [ { taskId = "c"
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
                                { statusText = "Failed to create volatile process: " ++ error.exceptionToString }
                            )

                        Ok createVolatileProcessOk ->
                            ( stateBefore
                            , InterfaceToHost.ContinueSession
                                { statusText = "Request to volatile process."
                                , startTasks =
                                    [ { taskId = "r"
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
                                { statusText = "Failed request to volatile process." }
                            )

                        Ok requestToVolatileProcessOk ->
                            let
                                statusText =
                                    case requestToVolatileProcessOk.returnValueToString of
                                        Nothing ->
                                            "Got no returnValueToString. exceptionToString: "
                                                ++ Maybe.withDefault "Nothing" requestToVolatileProcessOk.exceptionToString

                                        Just returnValueToString ->
                                            "Session complete: Got this response from the volatile process: "
                                                ++ returnValueToString
                            in
                            ( stateBefore
                            , InterfaceToHost.FinishSession { statusText = statusText }
                            )

                _ ->
                    ( stateBefore
                    , InterfaceToHost.FinishSession { statusText = "Not implemented yet." }
                    )

        _ ->
            ( stateBefore
            , InterfaceToHost.ContinueSession
                { statusText = "Unused event."
                , startTasks = []
                , notifyWhenArrivedAtTime = Nothing
                }
            )

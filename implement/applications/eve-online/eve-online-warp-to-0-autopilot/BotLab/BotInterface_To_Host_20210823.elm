module BotLab.BotInterface_To_Host_20210823 exposing (..)

{-| Types for the interface to the botlab client.
-}


type alias BotConfig state =
    { init : state
    , processEvent : BotEvent -> state -> ( state, BotEventResponse )
    }


type alias BotEvent =
    { timeInMilliseconds : Int
    , eventAtTime : BotEventAtTime
    }


type BotEventAtTime
    = TimeArrivedEvent
    | BotSettingsChangedEvent String
    | SessionDurationPlannedEvent { timeInMilliseconds : Int }
    | TaskCompletedEvent CompletedTaskStructure


type BotEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession FinishSessionStructure


type alias CompletedTaskStructure =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = CreateVolatileProcessResponse (Result CreateVolatileProcessErrorStructure CreateVolatileProcessComplete)
    | RequestToVolatileProcessResponse (Result RequestToVolatileProcessError RequestToVolatileProcessComplete)
    | CompleteWithoutResult


type alias CreateVolatileProcessErrorStructure =
    { exceptionToString : String
    }


type alias CreateVolatileProcessComplete =
    { processId : VolatileProcessId }


type RequestToVolatileProcessError
    = ProcessNotFound
    | FailedToAcquireInputFocus


type alias RequestToVolatileProcessComplete =
    { exceptionToString : Maybe String
    , returnValueToString : Maybe String
    , durationInMilliseconds : Int
    , acquireInputFocusDurationMilliseconds : Int
    }


type alias ReleaseVolatileProcessStructure =
    { processId : VolatileProcessId }


type alias ContinueSessionStructure =
    { statusDescriptionText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias FinishSessionStructure =
    { statusDescriptionText : String
    }


{-| Tasks can yield some result to return to the bot. That is why we use the identifier.
-}
type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type Task
    = CreateVolatileProcess CreateVolatileProcessStructure
    | RequestToVolatileProcess RequestToVolatileProcessConsideringInputFocusStructure
    | ReleaseVolatileProcess ReleaseVolatileProcessStructure


type alias CreateVolatileProcessStructure =
    { programCode : String }


type RequestToVolatileProcessConsideringInputFocusStructure
    = RequestRequiringInputFocus RequestToVolatileProcessRequiringInputFocusStructure
    | RequestNotRequiringInputFocus RequestToVolatileProcessStructure


type alias RequestToVolatileProcessRequiringInputFocusStructure =
    { request : RequestToVolatileProcessStructure
    , acquireInputFocus : AcquireInputFocusStructure
    }


type alias RequestToVolatileProcessStructure =
    { processId : VolatileProcessId
    , request : String
    }


type alias AcquireInputFocusStructure =
    { maximumDelayMilliseconds : Int
    }


type TaskId
    = TaskIdFromString String


type VolatileProcessId
    = VolatileProcessIdFromString String


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString

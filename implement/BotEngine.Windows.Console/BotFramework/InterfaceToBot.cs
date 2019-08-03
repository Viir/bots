namespace BotEngine.Windows.Console.BotFramework.InterfaceToBot
{
    public class BotEvent
    {
        public TimeStructure ArrivedAtTime;

        public ResultFromTaskWithId TaskComplete;

        public TimeStructure SetSessionTimeLimit;

        public string SetBotConfiguration;
    }

    public class BotResponse
    {
        public string DecodeEventError;

        public DecodeEventSuccessStructure DecodeEventSuccess;

        public class DecodeEventSuccessStructure
        {
            public ContinueSessionStructure ContinueSession;

            public FinishSessionStructure FinishSession;

            public class ContinueSessionStructure
            {
                public string statusDescriptionForOperator;

                public StartTask[] startTasks;

                public TimeStructure notifyWhenArrivedAtTime;
            }

            public class FinishSessionStructure
            {
                public string statusDescriptionForOperator;
            }
        }
    }

    public class Result<ErrT, OkT>
    {
        public ErrT Err;

        public OkT Ok;
    }

    public class ResultFromTaskWithId
    {
        public string taskId;

        public TaskResult taskResult;
    }

    public class TaskResult
    {
        public Result<object, CreateVolatileHostComplete> CreateVolatileHostResponse;

        public Result<RunInVolatileHostError, RunInVolatileHostComplete> RunInVolatileHostResponse;

        public object CompleteWithoutResult;

        public class CreateVolatileHostComplete
        {
            public string hostId;
        }

        public class RunInVolatileHostError
        {
            public object hostNotFound;
        }

        public class RunInVolatileHostComplete
        {
            public string exceptionToString;

            public string returnValueToString;

            public long durationInMilliseconds;
        }
    }

    public class StartTask
    {
        public string taskId;

        public Task task;
    }

    public class Task
    {
        public object CreateVolatileHost;

        public RunInVolatileHostStructure RunInVolatileHost;

        public ReleaseVolatileHostStructure ReleaseVolatileHost;

        public class RunInVolatileHostStructure
        {
            public string hostId;

            public string script;
        }

        public class ReleaseVolatileHostStructure
        {
            public string hostId;
        }
    }

    public class TimeStructure
    {
        public long timeInMilliseconds;
    }
}

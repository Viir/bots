namespace BotEngine.Windows.Console.BotFramework.InterfaceToBot
{
    public class BotEventAtTime
    {
        public long timeInMilliseconds;

        public BotEvent @event;
    }

    public class BotEvent
    {
        public long? setSessionTimeLimitInMilliseconds;

        public ResultFromTaskWithId taskComplete;

        public string setBotConfiguration;
    }

    public class BotResponse
    {
        public string decodeEventError;

        public DecodeEventSuccess decodeEventSuccess;

        public class DecodeEventSuccess
        {
            public BotRequest[] botRequests;
        }
    }

    public class BotRequest
    {
        public string setStatusMessage;

        public object finishSession;

        //  TODO: Consider make consistent with Kalmit: move ID from task to request.
        public StartTask startTask;
    }

    public class Result<Err, Ok>
    {
        public Err err;

        public Ok ok;
    }

    public class ResultFromTaskWithId
    {
        public string taskId;

        public TaskResult taskResult;
    }

    public class TaskResult
    {
        public Result<object, CreateVolatileHostComplete> createVolatileHostResponse;

        public Result<RunInVolatileHostError, RunInVolatileHostComplete> runInVolatileHostResponse;

        public object completeWithoutResult;

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
        public object createVolatileHost;

        public RunInVolatileHost runInVolatileHost;

        public ReleaseVolatileHost releaseVolatileHost;

        public Delay delay;

        public class RunInVolatileHost
        {
            public string hostId;

            public string script;
        }

        public class ReleaseVolatileHost
        {
            public string hostId;
        }

        public class Delay
        {
            public long milliseconds;
        }
    }
}

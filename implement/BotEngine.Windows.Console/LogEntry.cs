using System;

namespace BotEngine.Windows.Console
{
    public class LogEntry
    {
        public DateTimeOffset time;

        public LoadBotResult loadBotResult;

        public StartBotResult startBotProcessResult;

        public ProcessBotEventReport processBotEventReport;

        public LogEntryFromBot logEntryFromBot;

        public class LoadBotResult
        {
            public string botSource;

            public string botId;
        }

        public class StartBotResult
        {
            public string sessionId;

            public Exception exception;
        }

        public class LogEntryFromBot
        {
            public string logEntry;
        }

        public class ProcessBotEventReport
        {
            public DateTimeOffset time;

            public long? processingTimeInMilliseconds;

            public string serializedResponse;

            public Exception exception;

            public string compositionRecordHash;
        }
    }
}

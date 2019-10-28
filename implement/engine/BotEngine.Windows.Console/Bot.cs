using Kalmit.ProcessStore;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using DotNetConsole = System.Console;
using InterfaceToBot = BotEngine.Windows.Console.BotFramework.InterfaceToBot;

namespace BotEngine.Windows.Console
{
    class Bot
    {
        static public (byte[] kalmitElmApp, string error) BuildKalmitElmAppFromBotCode(byte[] botCode)
        {
            return (botCode, null);
        }

        static public int RunBotSession(
            byte[] kalmitElmApp,
            Func<byte[], byte[]> getFileFromHashSHA256,
            string processStoreDirectory,
            Action<string> logEntry,
            Action<LogEntry.ProcessBotEventReport> logProcessBotEventReport,
            string botConfiguration,
            string sessionId,
            string botSource,
            BotSourceModel.LiteralNodeObject botCode)
        {
            var botId = Kalmit.CommonConversion.StringBase16FromByteArray(Kalmit.CommonConversion.HashSHA256(kalmitElmApp));

            var botSessionClock = System.Diagnostics.Stopwatch.StartNew();

            /*
             * Implementat store and process based on Kalmit Web Host
             * from https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.WebHost/Startup.cs
             * */

            var process = new Kalmit.PersistentProcess.PersistentProcessWithHistoryOnFileFromElm019Code(
                new EmptyProcessStore(),
                kalmitElmApp,
                kalmitProcessLogEntry => logEntry("kalmitProcessLogEntry: " + kalmitProcessLogEntry),
                new Kalmit.ElmAppInterfaceConfig { RootModuleFilePath = "src/Main.elm", RootModuleName = "Main" });

            var processStore = new ProcessStoreInFileDirectory(
                processStoreDirectory,
                () =>
                {
                    var time = DateTimeOffset.UtcNow;
                    var directoryName = time.ToString("yyyy-MM-dd");
                    return System.IO.Path.Combine(directoryName, directoryName + "T" + time.ToString("HH") + ".composition.jsonl");
                });

            (DateTimeOffset time, string statusDescriptionText, InterfaceToBot.BotResponse.DecodeEventSuccessStructure response)? lastBotStep = null;

            var botSessionTaskCancellationToken = new System.Threading.CancellationTokenSource();
            var activeBotTasks = new ConcurrentDictionary<InterfaceToBot.StartTask, System.Threading.Tasks.Task>();

            bool pauseBot = false;
            (string text, DateTimeOffset time) lastConsoleUpdate = (null, DateTimeOffset.MinValue);

            void updatePauseContinue()
            {
                if (DotNetConsole.KeyAvailable)
                {
                    var inputKey = DotNetConsole.ReadKey();

                    if (inputKey.Key == ConsoleKey.Enter)
                    {
                        pauseBot = false;
                        displayStatusInConsole();
                    }
                }

                if (Windows.IsKeyDown(Windows.VK_CONTROL) && Windows.IsKeyDown(Windows.VK_MENU))
                {
                    pauseBot = true;
                    displayStatusInConsole();
                }
            }

            void cleanUpBotTasksAndPropagateExceptions()
            {
                foreach (var (request, engineTask) in activeBotTasks.ToList())
                {
                    if (engineTask.Exception != null)
                        throw new Exception("Bot task '" + request.taskId?.TaskIdFromString + "' has failed with exception", engineTask.Exception);

                    if (engineTask.IsCompleted)
                        activeBotTasks.TryRemove(request, out var _);
                }
            }

            var displayLock = new object();

            void displayStatusInConsole()
            {
                lock (displayLock)
                {
                    cleanUpBotTasksAndPropagateExceptions();

                    var textToDisplay = string.Join("\n", textLinesToDisplayInConsole());

                    var time = DateTimeOffset.UtcNow;

                    if (lastConsoleUpdate.text == textToDisplay && time < lastConsoleUpdate.time + TimeSpan.FromSeconds(1))
                        return;

                    if (botSessionTaskCancellationToken.IsCancellationRequested)
                        return;

                    DotNetConsole.Clear();
                    DotNetConsole.WriteLine(textToDisplay);

                    lastConsoleUpdate = (textToDisplay, time);
                }
            }

            IEnumerable<string> textLinesToDisplayInConsole()
            {
                //  TODO: Add display bot configuration.

                yield return
                    "Bot " + UserInterface.BotIdDisplayText(botId) +
                    " in session '" + sessionId + "'" +
                     (pauseBot ?
                     " is paused. Press the enter key to continue." :
                     " is running. Press CTRL + ALT keys to pause the bot.");

                if (!lastBotStep.HasValue)
                    yield break;

                var lastBotStepAgeInSeconds = (int)((DateTimeOffset.UtcNow - lastBotStep.Value.time).TotalSeconds);

                var activeBotTasksSnapshot = activeBotTasks.ToList();

                var activeBotTasksDescription =
                    TruncateWithEllipsis(string.Join(", ", activeBotTasksSnapshot.Select(task => task.Key.taskId.TaskIdFromString)), 60);

                yield return
                    "Last bot event was " + lastBotStepAgeInSeconds + " seconds ago at " + lastBotStep.Value.time.ToString("HH-mm-ss.fff") + ". " +
                    "There are " + activeBotTasksSnapshot.Count + " tasks in progress (" + activeBotTasksDescription + ").";

                yield return "Status message from bot:\n";

                yield return lastBotStep.Value.statusDescriptionText;

                yield return "";
            }

            string TruncateWithEllipsis(string originalString, int lengthLimit)
            {
                if (lengthLimit < originalString?.Length)
                    return originalString.Substring(0, lengthLimit) + "...";

                return originalString;
            }

            long lastRequestToReactorTimeInSeconds = 0;

            async System.Threading.Tasks.Task requestToReactor(RequestToReactorUseBotStruct useBot)
            {
                lastRequestToReactorTimeInSeconds = (long)botSessionClock.Elapsed.TotalSeconds;

                var toReactorStruct = new RequestToReactorStruct { UseBot = useBot };

                var serializedToReactorStruct = Newtonsoft.Json.JsonConvert.SerializeObject(toReactorStruct);

                var reactorClient = new System.Net.Http.HttpClient();

                reactorClient.DefaultRequestHeaders.UserAgent.Add(
                    new System.Net.Http.Headers.ProductInfoHeaderValue(new System.Net.Http.Headers.ProductHeaderValue("windows-console", BotEngine.AppVersionId)));

                var content = new System.Net.Http.ByteArrayContent(System.Text.Encoding.UTF8.GetBytes(serializedToReactorStruct));

                var response = await reactorClient.PostAsync("https://reactor.botengine.org/api/", content);

                var responseString = await response.Content.ReadAsStringAsync();
            }

            System.Threading.Tasks.Task fireAndForgetReportToReactor(RequestToReactorUseBotStruct report)
            {
                lastRequestToReactorTimeInSeconds = (long)botSessionClock.Elapsed.TotalSeconds;

                return System.Threading.Tasks.Task.Run(() =>
                {
                    try
                    {
                        requestToReactor(report).Wait();
                    }
                    catch { }
                });
            }

            var botSourceIsPublic = BotSourceIsPublic(botSource);
            var botPropertiesFromCode = BotSourceModel.BotCode.ReadPropertiesFromBotCode(botCode);

            fireAndForgetReportToReactor(new RequestToReactorUseBotStruct
            {
                StartSession = new RequestToReactorUseBotStruct.StartSessionStruct
                {
                    botId = botId,
                    sessionId = sessionId,
                    botSource = botSourceIsPublic ? botSource : null,
                    botPropertiesFromCode = botSourceIsPublic ? botPropertiesFromCode : null,
                }
            });

            var queuedBotEvents = new ConcurrentQueue<InterfaceToBot.BotEvent>();

            var createVolatileHostAttempts = 0;

            var volatileHosts = new ConcurrentDictionary<string, Kalmit.CSharpScriptContext>();

            InterfaceToBot.Result<InterfaceToBot.TaskResult.RunInVolatileHostError, InterfaceToBot.TaskResult.RunInVolatileHostComplete> ExecuteRequestToRunInVolatileHost(
                InterfaceToBot.Task.RunInVolatileHostStructure runInVolatileHost)
            {
                if (!volatileHosts.TryGetValue(runInVolatileHost.hostId.VolatileHostIdFromString, out var volatileHost))
                {
                    return new InterfaceToBot.Result<InterfaceToBot.TaskResult.RunInVolatileHostError, InterfaceToBot.TaskResult.RunInVolatileHostComplete>
                    {
                        Err = new InterfaceToBot.TaskResult.RunInVolatileHostError
                        {
                            hostNotFound = new object(),
                        }
                    };
                }

                var stopwatch = System.Diagnostics.Stopwatch.StartNew();

                var fromHostResult = volatileHost.RunScript(runInVolatileHost.script);

                stopwatch.Stop();

                return new InterfaceToBot.Result<InterfaceToBot.TaskResult.RunInVolatileHostError, InterfaceToBot.TaskResult.RunInVolatileHostComplete>
                {
                    Ok = new InterfaceToBot.TaskResult.RunInVolatileHostComplete
                    {
                        exceptionToString = fromHostResult.Exception?.ToString(),
                        returnValueToString = fromHostResult.ReturnValue?.ToString(),
                        durationInMilliseconds = stopwatch.ElapsedMilliseconds,
                    }
                };
            }

            void processBotEvent(InterfaceToBot.BotEvent botEvent)
            {
                var eventTime = DateTimeOffset.UtcNow;
                Exception processEventException = null;
                string serializedEvent = null;
                string serializedResponse = null;
                string compositionRecordHash = null;
                long? processingTimeInMilliseconds = null;

                try
                {
                    serializedEvent = SerializeToJsonForBot(botEvent);

                    var processingTimeStopwatch = System.Diagnostics.Stopwatch.StartNew();

                    var processEventResult = process.ProcessEvents(
                        new[]
                        {
                            serializedEvent
                        });

                    processingTimeStopwatch.Stop();

                    processingTimeInMilliseconds = processingTimeStopwatch.ElapsedMilliseconds;

                    compositionRecordHash = Kalmit.CommonConversion.StringBase16FromByteArray(processEventResult.Item2.serializedCompositionRecordHash);

                    processStore.AppendSerializedCompositionRecord(processEventResult.Item2.serializedCompositionRecord);

                    serializedResponse = processEventResult.responses.Single();

                    var botResponse = Newtonsoft.Json.JsonConvert.DeserializeObject<InterfaceToBot.BotResponse>(serializedResponse);

                    if (botResponse.DecodeEventSuccess == null)
                    {
                        throw new Exception("Bot reported decode error: " + botResponse.DecodeEventError);
                    }

                    var statusDescriptionText =
                        botResponse.DecodeEventSuccess?.ContinueSession?.statusDescriptionText ??
                        botResponse.DecodeEventSuccess?.FinishSession?.statusDescriptionText;

                    lastBotStep = (eventTime, statusDescriptionText, botResponse.DecodeEventSuccess);

                    foreach (var startTask in botResponse.DecodeEventSuccess?.ContinueSession?.startTasks ?? Array.Empty<InterfaceToBot.StartTask>())
                    {
                        var engineTask = System.Threading.Tasks.Task.Run(() => startTaskAndProcessEvent(startTask), botSessionTaskCancellationToken.Token);

                        activeBotTasks[startTask] = engineTask;
                    }
                }
                catch (Exception exception)
                {
                    processEventException = exception;
                }

                logProcessBotEventReport(new LogEntry.ProcessBotEventReport
                {
                    time = eventTime,
                    processingTimeInMilliseconds = processingTimeInMilliseconds,
                    exception = processEventException,
                    serializedResponse = serializedResponse,
                    compositionRecordHash = compositionRecordHash,
                });

                if (processEventException != null)
                    throw new Exception("Failed to process bot event.", processEventException);

                displayStatusInConsole();
            }

            //  TODO: Get the bot requests from the `init` function.

            processBotEvent(new InterfaceToBot.BotEvent { SetBotConfiguration = botConfiguration ?? "" });

            while (true)
            {
                displayStatusInConsole();

                updatePauseContinue();

                var millisecondsToNextNotification =
                    (lastBotStep?.response?.ContinueSession?.notifyWhenArrivedAtTime?.timeInMilliseconds - botSessionClock.ElapsedMilliseconds) ?? 1000;

                System.Threading.Thread.Sleep((int)Math.Min(1000, Math.Max(10, millisecondsToNextNotification)));

                var lastRequestToReactorAgeInSeconds = (long)botSessionClock.Elapsed.TotalSeconds - lastRequestToReactorTimeInSeconds;

                if (10 <= lastRequestToReactorAgeInSeconds)
                    fireAndForgetReportToReactor(new RequestToReactorUseBotStruct
                    {
                        ContinueSession = new RequestToReactorUseBotStruct.ContinueSessionStruct
                        { sessionId = sessionId, statusDescriptionText = lastBotStep?.statusDescriptionText }
                    });

                if (pauseBot)
                    continue;

                var botStepTime = DateTimeOffset.UtcNow;

                var lastBotStepAgeMilli =
                    botStepTime.ToUnixTimeMilliseconds() - lastBotStep?.time.ToUnixTimeMilliseconds();

                if (lastBotStep?.response?.FinishSession != null)
                {
                    logEntry("Bot has finished.");
                    botSessionTaskCancellationToken.Cancel();

                    fireAndForgetReportToReactor(new RequestToReactorUseBotStruct
                    {
                        FinishSession = new RequestToReactorUseBotStruct.ContinueSessionStruct
                        { sessionId = sessionId, statusDescriptionText = lastBotStep?.statusDescriptionText }
                    }).Wait(TimeSpan.FromSeconds(3));

                    return 0;
                }

                if (lastBotStep?.response?.ContinueSession?.notifyWhenArrivedAtTime?.timeInMilliseconds <= botSessionClock.ElapsedMilliseconds
                    || !(lastBotStepAgeMilli < 10_000))
                {
                    processBotEvent(new InterfaceToBot.BotEvent
                    {
                        ArrivedAtTime = new InterfaceToBot.TimeStructure { timeInMilliseconds = botSessionClock.ElapsedMilliseconds },
                    });
                }

                if (queuedBotEvents.TryDequeue(out var botEvent))
                {
                    processBotEvent(botEvent);
                }
            }

            void startTaskAndProcessEvent(InterfaceToBot.StartTask startTask)
            {
                var taskResult = performTask(startTask.task);

                queuedBotEvents.Enqueue(
                    new InterfaceToBot.BotEvent
                    {
                        CompletedTask = new InterfaceToBot.CompletedTaskStructure
                        {
                            taskId = startTask.taskId,
                            taskResult = taskResult,
                        },
                    });
            }

            InterfaceToBot.TaskResult performTask(InterfaceToBot.Task task)
            {
                if (task?.CreateVolatileHost != null)
                {
                    var volatileHostId = System.Threading.Interlocked.Increment(ref createVolatileHostAttempts).ToString();

                    volatileHosts[volatileHostId] = new Kalmit.CSharpScriptContext(getFileFromHashSHA256);

                    return new InterfaceToBot.TaskResult
                    {
                        CreateVolatileHostResponse = new InterfaceToBot.Result<object, InterfaceToBot.TaskResult.CreateVolatileHostComplete>
                        {
                            Ok = new InterfaceToBot.TaskResult.CreateVolatileHostComplete
                            {
                                hostId = new InterfaceToBot.VolatileHostId { VolatileHostIdFromString = volatileHostId },
                            },
                        },
                    };
                }

                if (task?.ReleaseVolatileHost != null)
                {
                    volatileHosts.TryRemove(task?.ReleaseVolatileHost.hostId.VolatileHostIdFromString, out var volatileHost);

                    return new InterfaceToBot.TaskResult { CompleteWithoutResult = new object() };
                }

                if (task?.RunInVolatileHost != null)
                {
                    var result = ExecuteRequestToRunInVolatileHost(task?.RunInVolatileHost);

                    return new InterfaceToBot.TaskResult
                    {
                        RunInVolatileHostResponse = result,
                    };
                }

                return null;
            }
        }

        static string SerializeToJsonForBot<T>(T value) =>
            Newtonsoft.Json.JsonConvert.SerializeObject(
                value,
                //  Use settings for consistency with Kalmit/elm-fullstack
                new Newtonsoft.Json.JsonSerializerSettings
                {
                    NullValueHandling = Newtonsoft.Json.NullValueHandling.Include,

                    //	https://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
                    ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
                });

        static public bool BotSourceIsPublic(string botSource) =>
            new[] { "http:", "https:" }.Any(publicPattern => botSource?.ToLowerInvariant()?.StartsWith(publicPattern) ?? false);

        class RequestToReactorStruct
        {
            public RequestToReactorUseBotStruct UseBot;
        }

        class RequestToReactorUseBotStruct
        {
            public StartSessionStruct StartSession;

            public ContinueSessionStruct ContinueSession;

            public ContinueSessionStruct FinishSession;

            public class StartSessionStruct
            {
                public string sessionId;

                public string botId;

                public string botSource;

                public BotSourceModel.BotPropertiesFromCode botPropertiesFromCode;
            }

            public class ContinueSessionStruct
            {
                public string sessionId;

                public string statusDescriptionText;
            }
        }
    }

    class EmptyProcessStore : IProcessStoreReader
    {
        public IEnumerable<byte[]> EnumerateSerializedCompositionsRecordsReverse() => Array.Empty<byte[]>();

        public ReductionRecord GetReduction(byte[] reducedCompositionHash) => null;
    }
}

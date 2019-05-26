using BotEngine.Windows.Console.BotFramework;
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
            /*
             * Build Kalmit Elm app.
             * Based on API from https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.Common/ElmApp.cs
             * */

            var botCodeFiles =
                Kalmit.ZipArchive.EntriesFromZipArchive(botCode)
                .Select(fileNameAndContent => (name: fileNameAndContent.name.Replace("\\", "/"), fileNameAndContent.content))
                .ToImmutableList();

            var elmAppMap = new Kalmit.ElmAppEntryConfig
            {
                /*
                 * Use convention for entry point file path, module name and function names.
                 * For an example of a concrete collection of files satisfying these constraints, see https://github.com/Viir/bots/tree/d18b54d146a23eea5070444d1d73626f05c0de7b/implement/bot/eve-online/eve-online-warp-to-0-autopilot
                 * 
                 * */
                WithCustomSerialization = new Kalmit.ElmAppEntryConfig.ElmAppEntryConfigWithCustomSerialization
                {
                    pathToFileWithElmEntryPoint = "src/Main.elm",
                    pathToSerializedEventFunction = "Main.botStepInterface",

                    //  TODO: Get the bot requests from the `init` function: Switch to `initInterface`. (https://github.com/Viir/Kalmit/issues/5)
                    pathToInitialStateFunction = "Main.initStateInterface",
                    pathToDeserializeStateFunction = "Main.deserializeState",
                    pathToSerializeStateFunction = "Main.serializeState",
                },
            };

            /*
             * TODO: Analyse 'botCodeFiles' to see if expected functions are present.
             * Generate error messages.
             * */

            var elmAppMapFile =
                System.Text.Encoding.UTF8.GetBytes(Newtonsoft.Json.JsonConvert.SerializeObject(elmAppMap));

            var kalmitElmAppFiles =
                botCodeFiles
                .Select(fileNameAndContent => (name: "elm-app/" + fileNameAndContent.name, fileNameAndContent.content))
                .Concat(ImmutableList.Create((name: "elm-app.map.json", elmAppMapFile)))
                .ToImmutableList();

            var kalmitElmApp = Kalmit.ZipArchive.ZipArchiveFromEntries(
                kalmitElmAppFiles,
                System.IO.Compression.CompressionLevel.NoCompression);

            return (kalmitElmApp, null);
        }

        static public int RunBotSession(
            byte[] kalmitElmApp,
            Func<byte[], byte[]> getFileFromHashSHA256,
            string processStoreDirectory,
            Action<string> logEntry,
            Action<LogEntry.ProcessBotEventReport> logProcessBotEventReport)
        {
            var botSessionClock = System.Diagnostics.Stopwatch.StartNew();

            /*
             * Implementat store and process based on Kalmit Web Host
             * from https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.WebHost/Startup.cs
             * */

            var process = new Kalmit.PersistentProcess.PersistentProcessWithHistoryOnFileFromElm019Code(
                new EmptyProcessStore(), kalmitElmApp);

            var processStore = new ProcessStoreInFileDirectory(
                processStoreDirectory,
                () =>
                {
                    var time = DateTimeOffset.UtcNow;
                    var directoryName = time.ToString("yyyy-MM-dd");
                    return System.IO.Path.Combine(directoryName, directoryName + "T" + time.ToString("HH") + ".composition.jsonl");
                });

            (DateTimeOffset time, string statusMessage, ImmutableList<InterfaceToBot.BotRequest>)? lastBotStep = null;

            ImmutableList<InterfaceToBot.BotRequest> remainingBotRequests = null;

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

            void displayStatusInConsole()
            {
                var textToDisplay = string.Join("\n", textLinesToDisplayInConsole());

                var time = DateTimeOffset.UtcNow;

                if (lastConsoleUpdate.text == textToDisplay && time < lastConsoleUpdate.time + TimeSpan.FromSeconds(1))
                    return;

                DotNetConsole.Clear();
                DotNetConsole.WriteLine(textToDisplay);

                lastConsoleUpdate = (textToDisplay, time);
            }

            IEnumerable<string> textLinesToDisplayInConsole()
            {
                if (pauseBot)
                    yield return "Bot is paused. Press the enter key to continue.";
                else
                    yield return "Bot is running. Press CTRL + ALT keys to pause the bot.";

                if (!lastBotStep.HasValue)
                    yield break;

                var lastBotStepAgeInSeconds = (int)((DateTimeOffset.UtcNow - lastBotStep.Value.time).TotalSeconds);

                yield return "Last bot event was " + lastBotStepAgeInSeconds + " seconds ago at " + lastBotStep.Value.time.ToString("HH-mm-ss.fff") + ".";

                yield return "Status message from bot:\n";

                yield return lastBotStep.Value.statusMessage;

                yield return "";
            }

            var createVolatileHostAttempts = 0;

            var volatileHosts = new ConcurrentDictionary<string, CSharpScriptContext>();

            InterfaceToBot.Result<InterfaceToBot.TaskResult.RunInVolatileHostError, InterfaceToBot.TaskResult.RunInVolatileHostComplete> ExecuteRequestToRunInVolatileHost(
                InterfaceToBot.Task.RunInVolatileHost runInVolatileHost)
            {
                if (!volatileHosts.TryGetValue(runInVolatileHost.hostId, out var volatileHost))
                {
                    return new InterfaceToBot.Result<InterfaceToBot.TaskResult.RunInVolatileHostError, InterfaceToBot.TaskResult.RunInVolatileHostComplete>
                    {
                        err = new InterfaceToBot.TaskResult.RunInVolatileHostError
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
                    ok = new InterfaceToBot.TaskResult.RunInVolatileHostComplete
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

                try
                {
                    var botEventAtTime = new InterfaceToBot.BotEventAtTime
                    {
                        timeInMilliseconds = botSessionClock.ElapsedMilliseconds,
                        @event = botEvent,
                    };

                    serializedEvent = SerializeToJsonForBot(botEventAtTime);

                    var processEventResult = process.ProcessEvents(
                        new[]
                        {
                            serializedEvent
                        });

                    compositionRecordHash = Kalmit.CommonConversion.StringBase16FromByteArray(processEventResult.Item2.serializedCompositionRecordHash);

                    processStore.AppendSerializedCompositionRecord(processEventResult.Item2.serializedCompositionRecord);

                    serializedResponse = processEventResult.responses.Single();

                    var botResponse = Newtonsoft.Json.JsonConvert.DeserializeObject<InterfaceToBot.BotResponse>(serializedResponse);

                    if (botResponse.decodeEventSuccess == null)
                    {
                        throw new Exception("Bot reported decode error: " + botResponse.decodeEventError);
                    }

                    var botRequests =
                        botResponse.decodeEventSuccess.botRequests.ToImmutableList();

                    var setStatusMessageRequests =
                        botRequests
                        .Where(request => request.setStatusMessage != null)
                        .ToImmutableList();

                    var statusMessage =
                        setStatusMessageRequests?.Select(request => request.setStatusMessage)?.LastOrDefault() ?? lastBotStep?.statusMessage;

                    lastBotStep = (eventTime, statusMessage, botRequests);

                    var stepRemainingRequests =
                        botRequests
                        .Except(setStatusMessageRequests);

                    remainingBotRequests =
                        (remainingBotRequests ?? ImmutableList<InterfaceToBot.BotRequest>.Empty)
                        .AddRange(stepRemainingRequests);
                }
                catch (Exception exception)
                {
                    processEventException = exception;
                }

                logProcessBotEventReport(new LogEntry.ProcessBotEventReport
                {
                    time = eventTime,
                    exception = processEventException,
                    serializedResponse = serializedResponse,
                    compositionRecordHash = compositionRecordHash,
                });

                if (processEventException != null)
                    throw new Exception("Failed to process bot event.", processEventException);

                displayStatusInConsole();
            }

            //  TODO: Get the bot requests from the `init` function.

            while (true)
            {
                displayStatusInConsole();

                updatePauseContinue();

                System.Threading.Thread.Sleep(111);

                if (pauseBot)
                    continue;

                var botStepTime = DateTimeOffset.UtcNow;

                var lastBotStepAgeMilli =
                    botStepTime.ToUnixTimeMilliseconds() - lastBotStep?.time.ToUnixTimeMilliseconds();

                var finishSessionRequest =
                    remainingBotRequests
                    ?.FirstOrDefault(request => request.finishSession != null);

                if (finishSessionRequest != null)
                {
                    logEntry("Bot has finished.");
                    return 0;
                }

                var botRequestToExecute =
                    remainingBotRequests
                    ?.FirstOrDefault();

                if (botRequestToExecute == null)
                {
                    if (!(lastBotStepAgeMilli < 10_000))
                    {
                        processBotEvent(new InterfaceToBot.BotEvent
                        {
                            setSessionTimeLimitInMilliseconds = 0,
                        });
                    }

                    continue;
                }

                var requestTask = botRequestToExecute.startTask;

                if (requestTask?.task?.createVolatileHost != null)
                {
                    var volatileHostId = System.Threading.Interlocked.Increment(ref createVolatileHostAttempts).ToString();

                    volatileHosts[volatileHostId] = new CSharpScriptContext(getFileFromHashSHA256);

                    processBotEvent(new InterfaceToBot.BotEvent
                    {
                        taskResult = new InterfaceToBot.ResultFromTaskWithId
                        {
                            taskId = requestTask?.taskId,
                            taskResult = new InterfaceToBot.TaskResult
                            {
                                createVolatileHostResponse = new InterfaceToBot.Result<object, InterfaceToBot.TaskResult.CreateVolatileHostComplete>
                                {
                                    ok = new InterfaceToBot.TaskResult.CreateVolatileHostComplete
                                    {
                                        hostId = volatileHostId,
                                    },
                                },
                            },
                        },
                    });
                }

                if (requestTask?.task?.releaseVolatileHost != null)
                {
                    volatileHosts.TryRemove(requestTask?.task?.releaseVolatileHost.hostId, out var volatileHost);
                }

                if (requestTask?.task?.runInVolatileHost != null)
                {
                    var result = ExecuteRequestToRunInVolatileHost(requestTask?.task?.runInVolatileHost);

                    processBotEvent(new InterfaceToBot.BotEvent
                    {
                        taskResult = new InterfaceToBot.ResultFromTaskWithId
                        {
                            taskId = requestTask?.taskId,
                            taskResult = new InterfaceToBot.TaskResult
                            {
                                runInVolatileHostResponse = result,
                            },
                        }
                    });
                }

                if (requestTask?.task?.delay != null)
                {
                    var delayStopwatch = System.Diagnostics.Stopwatch.StartNew();

                    while (true)
                    {
                        var remainingWaitTime = requestTask.task.delay.milliseconds - delayStopwatch.ElapsedMilliseconds;

                        if (remainingWaitTime <= 0)
                            break;

                        System.Threading.Thread.Sleep((int)Math.Min(100, remainingWaitTime));

                        updatePauseContinue();
                        displayStatusInConsole();
                    }

                    processBotEvent(new InterfaceToBot.BotEvent
                    {
                        taskResult = new InterfaceToBot.ResultFromTaskWithId
                        {
                            taskId = requestTask?.taskId,
                            taskResult = new InterfaceToBot.TaskResult
                            {
                                completeWithoutResult = new object(),
                            },
                        }
                    });
                }

                remainingBotRequests = remainingBotRequests.Remove(botRequestToExecute);
            }
        }

        static string SerializeToJsonForBot<T>(T value) =>
            Newtonsoft.Json.JsonConvert.SerializeObject(
                value,
                //  Use settings to get same derivation as at https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L91-L97
                new Newtonsoft.Json.JsonSerializerSettings
                {
                    //  Bot code does not expect properties with null values, see https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
                    NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,

                    //	https://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
                    ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
                });
    }

    class EmptyProcessStore : IProcessStoreReader
    {
        public IEnumerable<byte[]> EnumerateSerializedCompositionsRecordsReverse() => Array.Empty<byte[]>();

        public ReductionRecord GetReduction(byte[] reducedCompositionHash) => null;
    }
}

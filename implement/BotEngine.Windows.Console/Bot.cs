using Kalmit.ProcessStore;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using InterfaceToBot = BotEngine.Windows.Console.BotFramework.InterfaceToBot;
using DotNetConsole = System.Console;
using BotEngine.Windows.Console.BotFramework;

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
                 * For an example of a concrete collection of files satisfying these constraints, see https://github.com/Viir/bots/tree/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework
                 * 
                 * TODO: Use an example with less additional files.
                 * */
                WithCustomSerialization = new Kalmit.ElmAppEntryConfig.ElmAppEntryConfigWithCustomSerialization
                {
                    pathToFileWithElmEntryPoint = "src/Main.elm",
                    pathToSerializedEventFunction = "Main.botStepInterface",
                    pathToInitialStateFunction = "Main.initState",
                    pathToDeserializeStateFunction = "Main.deserializeState",
                    pathToSerializeStateFunction = "Main.serializeState",
                },
            };

            /*
             * TODO: Analyse 'botCodeFiles' to see if expected functions are present.
             * Generate error messages.
             * */

            var elmAppMapFile =
                NewtonsoftJson.SerializeToUtf8(elmAppMap);

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
            string processStoreDirectory,
            Action<string> logEntry,
            Action<LogEntry.ProcessBotEventReport> logProcessBotEventReport)
        {
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

            /*
             * For now, expect exactly interface Sanderling 2019-05-14.
             * This is to be replaced to identify the framework version selected by the bot author.
             * */

            var eveOnlineClientProcesses =
                System.Diagnostics.Process.GetProcessesByName("ExeFile");

            var eveOnlineClientProcess = eveOnlineClientProcesses.FirstOrDefault();

            if (eveOnlineClientProcess == null)
            {
                logEntry("I did not find any windows process which looks like an EVE Online client. I stop the bot.");
                return 0;
            }

            logEntry("I found process '" + eveOnlineClientProcess.Id + "' which looks like an EVE Online client. I will use this one with the bot.");

            //  Read memory based on https://github.com/Viir/bots/blob/59607e9c0e90f52cd35df2205401363c72787c1b/eve-online/setup-sanderling.csx

            var memoryReader = SanderlingSetup.MemoryReaderFromLiveProcessId(eveOnlineClientProcess.Id);

            logEntry("I search for the root of the UI tree now. This can take several seconds.");
            var uiTreeRoot = SanderlingSetup.UITreeRootFromMemoryReader(memoryReader);

            var testReadMemory = SanderlingSetup.PartialPythonModelFromUITreeRoot(memoryReader, uiTreeRoot);

            if (testReadMemory == null)
            {
                logEntry("I did not found the root of the UI tree. I stop the bot.");
                return 1;
            }

            var allNodesFromMemoryMeasurementPartialPythonModel =
                SanderlingSetup.EnumerateNodeFromTreeDFirst(
                    testReadMemory,
                    node => node.GetListChild()?.Cast<Optimat.EveOnline.AuswertGbs.UINodeInfoInTree>())
                .ToImmutableList();

            logEntry("I found the UI tree, and " + allNodesFromMemoryMeasurementPartialPythonModel.Count + " nodes in there.");

            (DateTimeOffset time, string statusReport, ImmutableList<InterfaceToBot.BotRequest>)?
                lastBotStep = null;

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

                yield return "In the last update, " + lastBotStepAgeInSeconds + " seconds ago at " + lastBotStep.Value.time.ToString("HH-mm-ss.fff") +
                    ", the bot reported the following status:\n" + lastBotStep.Value.statusReport;
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
                        timeInMilliseconds = eventTime.ToUnixTimeMilliseconds(),
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

                    var botResponse = NewtonsoftJson.DeserializeFromString<InterfaceToBot.BotResponse>(serializedResponse);

                    if (botResponse.decodeSuccess == null)
                    {
                        throw new Exception("Bot reported decode error: " + botResponse.decodeError);
                    }

                    var botRequests =
                        botResponse.decodeSuccess.botRequests.ToImmutableList();

                    var reportStatusRequests =
                        botRequests
                        .Where(request => request.reportStatus != null)
                        .ToImmutableList();

                    var stepStatusReport =
                        string.Join("\n", reportStatusRequests.Select(botRequest => botRequest.reportStatus));

                    lastBotStep = (eventTime, stepStatusReport, botRequests);

                    var requestedEffects =
                        botRequests
                        .Where(botRequest => botRequest.effect != null)
                        .ToImmutableList();

                    foreach (var botRequestEffect in requestedEffects)
                    {
                        ExecuteBotEffect(botRequestEffect.effect, eveOnlineClientProcess.MainWindowHandle);
                    }

                    var stepRemainingRequests =
                        botRequests
                        .Except(reportStatusRequests)
                        .Except(requestedEffects);

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

            InterfaceToBot.Result<string, InterfaceToBot.MemoryMeasurement> memoryMeasurementFinishedResult()
            {
                try
                {
                    var partialPython = SanderlingSetup.PartialPythonModelFromUITreeRoot(memoryReader, uiTreeRoot);

                    var reducedWithNameNodes = SanderlingSetup.SanderlingMemoryMeasurementFromPartialPythonModel(partialPython);

                    return new InterfaceToBot.Result<string, InterfaceToBot.MemoryMeasurement>
                    {
                        ok = new InterfaceToBot.MemoryMeasurement
                        {
                            reducedWithNamedNodesJson = SerializeToJsonForBot(reducedWithNameNodes),
                        }
                    };
                }
                catch (Exception e)
                {
                    return new InterfaceToBot.Result<string, InterfaceToBot.MemoryMeasurement>
                    {
                        err = e.ToString(),
                    };
                }
            }

            void takeMemoryMeasurement()
            {
                var botEvent = new InterfaceToBot.BotEvent
                {
                    memoryMeasurementFinished = memoryMeasurementFinishedResult(),
                };

                processBotEvent(botEvent);
            }

            //  TODO: Get the bot requests from the `init` function.

            while (true)
            {
                displayStatusInConsole();

                updatePauseContinue();

                System.Threading.Thread.Sleep(111);

                if (pauseBot)
                    continue;

                if (eveOnlineClientProcess.HasExited)
                {
                    logEntry("Process '" + eveOnlineClientProcess.Id + "' has exited. I stop the bot.");
                    return 0;
                }

                var botStepTime = DateTimeOffset.UtcNow;

                var lastBotStepAgeMilli =
                    botStepTime.ToUnixTimeSeconds() - lastBotStep?.time.ToUnixTimeSeconds();

                var finishSessionRequest =
                    remainingBotRequests
                    ?.FirstOrDefault(request => request.finishSession != null);

                if (finishSessionRequest != null)
                {
                    logEntry("Bot has requested to finish the session. I stop.");
                    return 0;
                }

                var botRequestToExecute =
                    remainingBotRequests
                    ?.FirstOrDefault(botRequest =>
                    {
                        if (botRequest.takeMemoryMeasurementAtTimeInMilliseconds != null)
                            return botRequest.takeMemoryMeasurementAtTimeInMilliseconds.Value <= botStepTime.ToUnixTimeMilliseconds();

                        return false;
                    });

                if (botRequestToExecute == null)
                {
                    if (!(lastBotStepAgeMilli < 10_000))
                    {
                        takeMemoryMeasurement();
                    }

                    continue;
                }

                if (botRequestToExecute.takeMemoryMeasurementAtTimeInMilliseconds != null)
                {
                    takeMemoryMeasurement();
                }

                remainingBotRequests =
                    remainingBotRequests.Remove(botRequestToExecute);
            }
        }

        static void ExecuteBotEffect(
            InterfaceToBot.BotEffect botEffect,
            IntPtr windowHandle)
        {
            if (botEffect.simpleEffect != null)
            {
                if (botEffect.simpleEffect.simpleMouseClickAtLocation != null)
                {
                    //  Build motion description based on https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling/Motor/Extension.cs#L24-L131

                    var mousePosition = new Bib3.Geometrik.Vektor2DInt(
                        botEffect.simpleEffect.simpleMouseClickAtLocation.location.x,
                        botEffect.simpleEffect.simpleMouseClickAtLocation.location.y);

                    var mouseButton =
                        botEffect.simpleEffect.simpleMouseClickAtLocation.mouseButton == InterfaceToBot.MouseButton.right
                        ? Motor.MouseButtonIdEnum.Right : Motor.MouseButtonIdEnum.Left;

                    var mouseButtons = new Motor.MouseButtonIdEnum[]
                    {
                        mouseButton,
                    };

                    var windowMotor = new Sanderling.Motor.WindowMotor(windowHandle);

                    var motionSequence = new Motor.Motion[]{
                        new Motor.Motion(
                            mousePosition: mousePosition,
                            mouseButtonDown: mouseButtons,
                            windowToForeground: true),
                        new Motor.Motion(
                            mousePosition: mousePosition,
                            mouseButtonUp: mouseButtons,
                            windowToForeground: true),
                    };

                    windowMotor.ActSequenceMotion(motionSequence);
                }
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

using McMaster.Extensions.CommandLineUtils;
using System;
using System.Collections.Immutable;
using System.Linq;
using System.Text.RegularExpressions;
using DotNetConsole = System.Console;

namespace BotEngine.Windows.Console
{
    class BotEngine
    {
        static string appVersionId => "2019-05-29";

        static string uiTimeFormatToString => "yyyy-MM-ddTHH-mm-ss";

        public static int Main(string[] args)
        {
            DotNetConsole.Title = "BotEngine v" + appVersionId;

            //  Build interface based on sample from https://github.com/natemcmaster/CommandLineUtils/blob/be230400aaae2f00b29dac005c1b59a386a42165/docs/samples/subcommands/builder-api/Program.cs

            var app = new CommandLineApplication
            {
                Name = "BotEngine",
                Description = "Run bots from the commandline.",
            };

            app.HelpOption(inherited: true);

            app.VersionOption(template: "-v|--version", shortFormVersion: "BotEngine console version " + appVersionId);

            app.Command("start-bot", startBotCmd =>
            {
                startBotCmd.Description = "Start a bot on this machine. The bot will continue running until you stop it or it stops itself.";
                startBotCmd.ThrowOnUnexpectedArgument = false;

                startBotCmd.OnExecute(() =>
                {
                    void dotnetConsoleWriteProblemCausingAbort(string line)
                    {
                        DotNetConsole.WriteLine("");

                        var colorBefore = DotNetConsole.ForegroundColor;

                        DotNetConsole.ForegroundColor = ConsoleColor.Yellow;

                        DotNetConsole.WriteLine(line);

                        DotNetConsole.ForegroundColor = colorBefore;
                    }

                    var sessionStartTime = DateTimeOffset.UtcNow;
                    var sessionId = sessionStartTime.ToString("yyyy-MM-ddTHH-mm-ss");

                    Exception sessionException = null;

                    var botSessionDirectory =
                        System.IO.Path.Combine(
                            GetExecutingAssemblyLocationDirectory, "bot-session", sessionId);

                    var logFileName = "session." + sessionId + ".jsonl";

                    var logFilePath = System.IO.Path.Combine(botSessionDirectory, logFileName);

                    Action<LogEntry> appendLogEntry = null;

                    {
                        System.IO.Stream logStream = null;

                        try
                        {
                            System.IO.Directory.CreateDirectory(botSessionDirectory);

                            logStream = new System.IO.FileStream(logFilePath, System.IO.FileMode.Create, System.IO.FileAccess.Write);

                            DotNetConsole.WriteLine($"I am recording a log of this session to file '{ logFilePath }'");

                            appendLogEntry = logEntry =>
                            {
                                logEntry.time = DateTimeOffset.UtcNow;

                                var settings = new Newtonsoft.Json.JsonSerializerSettings
                                {
                                    NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,
                                };

                                var serializedLogEntry =
                                    System.Text.Encoding.UTF8.GetBytes(
                                        Newtonsoft.Json.JsonConvert.SerializeObject(logEntry, settings));

                                var serializedLogEntryWithNewline =
                                    serializedLogEntry.Concat(new byte[] { 13, 10 }).ToArray();

                                logStream.Write(serializedLogEntryWithNewline);

                                logStream.Flush();
                            };
                        }
                        catch (Exception e)
                        {
                            dotnetConsoleWriteProblemCausingAbort("Failed to open log file: " + e?.ToString());
                            return 1;
                        }
                    }

                    try
                    {
                        var botSourceParamName = "--bot-source";

                        var botSourceParamInstruction = "Add the '" + botSourceParamName + "' argument to specify the directory containing a bot. Following is an example: " + botSourceParamName + @"=""C:\bots\bot-to-start""";

                        (bool isPresent, string argumentValue) argumentFromParameterName(string parameterName)
                        {
                            var match =
                                args
                                .Select(arg => Regex.Match(arg, parameterName + "(=(.*)|)", RegexOptions.IgnoreCase))
                                .FirstOrDefault(match => match.Success);

                            if (match == null)
                                return (false, null);

                            if (match.Groups[1].Length < 1)
                                return (true, null);

                            return (true, match?.Groups[2].Value);
                        }

                        var botSourceMatch = argumentFromParameterName(botSourceParamName);

                        if (!botSourceMatch.isPresent)
                        {
                            dotnetConsoleWriteProblemCausingAbort("Where from should I load the bot? " + botSourceParamInstruction);
                            return 11;
                        }

                        var botSourcePath =
                            botSourceMatch.argumentValue
                            /*
                             * Avoid problem observed 2019-05-17:
                             * When using a command line argument like this:
                             * start-bot  --bot-source="C:\directory-containing-bot-code\"
                             * We get
                             * --bot-source=C:\directory-containing-bot-code"
                             * from `CommandLineApplication.RemainingArguments`
                             * */
                            ?.TrimEnd('"');

                        //  TODO: Also support loading bot from single file.

                        var botSourceGuide = "Please choose a directory containing a bot.";

                        if (!System.IO.Directory.Exists(botSourcePath))
                        {
                            dotnetConsoleWriteProblemCausingAbort("I did not find a directory at '" + botSourcePath + "'. " + botSourceGuide);
                            return 12;
                        }

                        var allFilePathsAtBotSource =
                            System.IO.Directory.GetFiles(
                                botSourcePath, "*", System.IO.SearchOption.AllDirectories);

                        DotNetConsole.WriteLine(
                            "I found " + allFilePathsAtBotSource.Length +
                            " files in '" + botSourcePath + "'.");

                        if (allFilePathsAtBotSource.Length < 1)
                        {
                            dotnetConsoleWriteProblemCausingAbort(botSourceGuide);
                            return 13;
                        }

                        var botCodeFiles =
                            allFilePathsAtBotSource
                            .Where(Kalmit.ElmApp.FilePathMatchesPatternOfFilesInElmApp)
                            .Select(botCodeFilePath =>
                            {
                                return
                                    (name: System.IO.Path.GetRelativePath(botSourcePath, botCodeFilePath),
                                    content: System.IO.File.ReadAllBytes(botCodeFilePath));
                            })
                            .OrderBy(botCodeFile => botCodeFile.name)
                            .ToImmutableList();

                        {
                            //  At the moment, all supported bot formats require this file.
                            var fileNameExpectedAtRoot = "elm.json";

                            if (!botCodeFiles.Any(botCodeFile => botCodeFile.name.ToLowerInvariant() == fileNameExpectedAtRoot))
                            {
                                dotnetConsoleWriteProblemCausingAbort(
                                    "There is a problem with the bot source: I did not find an '" + fileNameExpectedAtRoot + "' file directly in this directory."
                                    //  TODO: Link to guide about supported bot code format.
                                    );

                                /*
                                 * Account for the possibility that the user has accidentally picked a parent directory:
                                 * See if a subdirectory contains such a file.
                                 * */
                                var filePathEndingsToLookFor = new[] { "\\" + fileNameExpectedAtRoot, "/" + fileNameExpectedAtRoot };

                                var maybeAlternativeFilePath =
                                    botCodeFiles
                                    .Where(botCodeFile =>
                                        filePathEndingsToLookFor.Any(filePathEndingToLookFor =>
                                            botCodeFile.name.ToLowerInvariant().EndsWith(filePathEndingToLookFor)))
                                    .OrderBy(botCodeFile => botCodeFile.name.Length)
                                    .FirstOrDefault()
                                    .name;

                                if (maybeAlternativeFilePath != null)
                                    DotNetConsole.WriteLine(
                                        "Did you mean the subdirectory '" + System.IO.Path.GetDirectoryName(maybeAlternativeFilePath) + "'?");

                                return 14;
                            }
                        }

                        var botCode =
                            Kalmit.ZipArchive.ZipArchiveFromEntries(
                                botCodeFiles,
                                System.IO.Compression.CompressionLevel.NoCompression);

                        var (botId, botCodeFileName) = WriteValueToCacheBySHA256(botCode);

                        appendLogEntry(
                            new LogEntry
                            {
                                loadBotResult = new LogEntry.LoadBotResult
                                {
                                    botSource = botSourcePath,
                                    botId = botId,
                                }
                            });

                        DotNetConsole.WriteLine("I loaded bot " + botId + ".");

                        //  TODO: Notify user in case bot code is not formatted, offer formatting.

                        //  Build the elm-app zip-archive as expected from Kalmit

                        var buildKalmitElmAppResult = Bot.BuildKalmitElmAppFromBotCode(botCode);

                        var processStoreDirectory = System.IO.Path.Combine(
                            botSessionDirectory, "kalmit-process-store");

                        DotNetConsole.WriteLine("Starting the bot....");

                        Bot.RunBotSession(
                            buildKalmitElmAppResult.kalmitElmApp,
                            GetFileFromHashSHA256,
                            processStoreDirectory,
                            logEntry =>
                            {
                                appendLogEntry(new LogEntry
                                {
                                    logEntryFromBot = new LogEntry.LogEntryFromBot
                                    {
                                        logEntry = logEntry,
                                    },
                                });

                                DotNetConsole.WriteLine(logEntry);
                            },
                            processBotEventReport =>
                            {
                                appendLogEntry(new LogEntry
                                {
                                    processBotEventReport = processBotEventReport,
                                });
                            });
                    }
                    catch (Exception e)
                    {
                        sessionException = e;
                    }

                    if (sessionException != null)
                        dotnetConsoleWriteProblemCausingAbort("start-bot failed with exception: " + sessionException);

                    appendLogEntry(new LogEntry
                    {
                        startBotProcessResult = new LogEntry.StartBotResult
                        {
                            sessionId = sessionId,
                            exception = sessionException,
                        },
                    });

                    DotNetConsole.WriteLine("[" + DateTimeOffset.UtcNow.ToString(uiTimeFormatToString) + "] Bot session ended.");
                    return sessionException == null ? 0 : 30;
                });
            });

            app.OnExecute(() =>
            {
                DotNetConsole.WriteLine("Please specify a subcommand.");
                app.ShowHelp();
                return 1;
            });

            return app.Execute(args);
        }

        static byte[] GetFileFromHashSHA256(byte[] hashSHA256)
        {
            var fileName = GetHashFileNameInCacheSHA256(hashSHA256);

            var fromCache = ReadValueFromCacheSHA256(fileName);

            if (fromCache != null)
                return fromCache;

            var addressBase = "https://botengine.blob.core.windows.net/blob-library/by-sha256/";

            var address = addressBase + fileName;

            var fromWeb = new System.Net.WebClient().DownloadData(address);

            if (!(GetValueFileNameInCacheSHA256(fromWeb) == fileName))
                return null;

            WriteValueToCacheBySHA256(fromWeb);

            return fromWeb;
        }

        static string CacheDirectoryPath => System.IO.Path.Combine(
            GetExecutingAssemblyLocationDirectory, ".cache");

        static string CacheByIdentityDirectoryPath = System.IO.Path.Combine(
            CacheDirectoryPath, "by-sha256");

        static string GetExecutingAssemblyLocationDirectory =>
            System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);

        static byte[] ReadValueFromCacheSHA256(string expectedFileName)
        {
            foreach (var filePath in System.IO.Directory.GetFiles(CacheByIdentityDirectoryPath, expectedFileName, searchOption: System.IO.SearchOption.AllDirectories))
            {
                var fileName = System.IO.Path.GetFileName(filePath);

                if (fileName == expectedFileName)
                {
                    var file = System.IO.File.ReadAllBytes(filePath);

                    if (!(GetValueFileNameInCacheSHA256(file) == expectedFileName))
                    {
                        System.IO.File.Delete(filePath);
                        return null;
                    }

                    return file;
                }
            }

            return null;
        }

        static string GetHashFileNameInCacheSHA256(byte[] hashSHA256) =>
            Kalmit.CommonConversion.StringBase16FromByteArray(hashSHA256).ToUpperInvariant();

        static string GetValueFileNameInCacheSHA256(byte[] value) =>
            GetHashFileNameInCacheSHA256(Kalmit.CommonConversion.HashSHA256(value));

        static (string fileName, string filePath) WriteValueToCacheBySHA256(byte[] value)
        {
            var fileName =
                GetValueFileNameInCacheSHA256(value);

            var filePath = System.IO.Path.Combine(
                CacheByIdentityDirectoryPath, fileName.Substring(0, 2), fileName);

            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(filePath));
            System.IO.File.WriteAllBytes(filePath, value);

            return (fileName, filePath);
        }
    }
}

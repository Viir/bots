module WebBrowser.VolatileHostScript exposing (setupScript)


setupScript : String
setupScript =
    """
// "Newtonsoft.Json"
#r "sha256:B9B4E633EA6C728BAD5F7CBBEF7F8B842F7E10181731DBE5EC3CD995A6F60287"

//  https://www.nuget.org/packages/PuppeteerSharp/2.0.0
#r "sha256:0F75836442D45E36BB4F797F882B6A778BD0D1D4219D204F15A5590B609FD7FF"

//  https://www.nuget.org/packages/Microsoft.Extensions.Logging.Abstractions/3.1.0
#r "sha256:04C07F84D516A134D6CFC3787E725427629126B1C250E1B013552177EF6CC4ED"

//  https://www.nuget.org/packages/Microsoft.Extensions.Logging/3.1.0
#r "sha256:6A627F66DD2DBBD52A66D80694B8B6341AFE9F6473C80A24EEC87C556BA41C72"

//  https://www.nuget.org/packages/Microsoft.Extensions.Options/3.1.0
#r "sha256:4DF9324EB5C1DB407F821764A19A9418440C1AB796C794E6EC0F59F208CD3F5D"


#r "mscorlib"
#r "netstandard"
#r "System"
#r "System.Collections.Immutable"
#r "System.ComponentModel.Primitives"
#r "System.IO.Compression"
#r "System.Net"
#r "System.Net.WebClient"
#r "System.Private.Uri"
#r "System.Linq"
#r "System.Security.Cryptography.Algorithms"
#r "System.Security.Cryptography.Primitives"
#r "Microsoft.Win32.Primitives"

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Security.Cryptography;
using System.Runtime.InteropServices;


byte[] SHA256FromByteArray(byte[] array)
{
    using (var hasher = new SHA256Managed())
        return hasher.ComputeHash(buffer: array);
}

string ToStringBase16(byte[] array) => BitConverter.ToString(array).Replace("-", "");


class Request
{
    public RunJavascriptInCurrentPageRequestStructure RunJavascriptInCurrentPageRequest;

    public StartWebBrowserRequestStructure StartWebBrowserRequest;

    public class RunJavascriptInCurrentPageRequestStructure
    {
        public string requestId;

        public string javascript;

        public int timeToWaitForCallbackMilliseconds;
    }

    public class StartWebBrowserRequestStructure
    {
        public string pageGoToUrl;

        public string userProfileId;

        public int remoteDebuggingPort;
    }
}

class Response
{
    public RunJavascriptInCurrentPageResponseStructure RunJavascriptInCurrentPageResponse;

    public object WebBrowserStarted;

    public class RunJavascriptInCurrentPageResponseStructure
    {
        public string requestId;

        public bool webBrowserAvailable;

        public string directReturnValueAsString;

        public string callbackReturnValueAsString;
    }
}

string serialRequest(string serializedRequest)
{
    var requestStructure = Newtonsoft.Json.JsonConvert.DeserializeObject<Request>(serializedRequest);

    var response = request(requestStructure);

    return SerializeToJsonForBot(response);
}

Response request(Request request)
{
    if (request.StartWebBrowserRequest != null)
    {
        KillOtherInstancesAndStartBrowser(
            pageGoToUrl: request.StartWebBrowserRequest.pageGoToUrl,
            userProfileId: request.StartWebBrowserRequest.userProfileId,
            remoteDebuggingPort: request.StartWebBrowserRequest.remoteDebuggingPort).Wait();

        return new Response
        {
            WebBrowserStarted = new object(),
        };
    }

    if (request.RunJavascriptInCurrentPageRequest != null)
    {
        return new Response
        {
            RunJavascriptInCurrentPageResponse = RunJavascriptInCurrentPage(request.RunJavascriptInCurrentPageRequest).Result,
        };
    }

    return null;
}

static string UserDataDirPath(string userProfileId) =>
    System.IO.Path.Combine(
        Environment.GetEnvironmentVariable("LOCALAPPDATA"), "bot", "web-browser", "user-profile", userProfileId, "user-data");

PuppeteerSharp.Browser browser;
PuppeteerSharp.Page browserPage;

Action<string> callbackFromBrowserDelegate;

async System.Threading.Tasks.Task KillOtherInstancesAndStartBrowser(
    string pageGoToUrl,
    string userProfileId,
    int remoteDebuggingPort)
{
    await new PuppeteerSharp.BrowserFetcher().DownloadAsync(PuppeteerSharp.BrowserFetcher.DefaultRevision);

    KillPreviousWebBrowserProcesses(userProfileId);

    browser = await PuppeteerSharp.Puppeteer.LaunchAsync(new PuppeteerSharp.LaunchOptions
    {
        Args = new[] { "--remote-debugging-port=" + remoteDebuggingPort.ToString() },
        Headless = false,
        UserDataDir = UserDataDirPath(userProfileId),
        DefaultViewport = null,
    });

    browserPage = (await browser.PagesAsync()).FirstOrDefault() ?? await browser.NewPageAsync();

    //  TODO: Better name for ____callback____?

    await browserPage.ExposeFunctionAsync("____callback____", (string returnValue) =>
    {
        callbackFromBrowserDelegate?.Invoke(returnValue);
        return 0;
    });

    if(0 < pageGoToUrl?.Length)
    {
        await browserPage.GoToAsync(pageGoToUrl);
    }
}

async System.Threading.Tasks.Task<Response.RunJavascriptInCurrentPageResponseStructure> RunJavascriptInCurrentPage(
    Request.RunJavascriptInCurrentPageRequestStructure request)
{
    bool callbackCalled = false;
    string callbackReturnValue = null;

    if(browserPage == null)
    {
        return new Response.RunJavascriptInCurrentPageResponseStructure
        {
            requestId = request.requestId,
            webBrowserAvailable = false,
        };
    }

    callbackFromBrowserDelegate = new Action<string>(returnValue =>
    {
        callbackReturnValue = returnValue;
        callbackCalled = true;
    });

    var directReturnValueAsString = (await browserPage.EvaluateExpressionAsync(request.javascript))?.ToString();

    var waitStopwatch = System.Diagnostics.Stopwatch.StartNew();

    while (!callbackCalled && waitStopwatch.Elapsed.TotalMilliseconds < request.timeToWaitForCallbackMilliseconds)
        System.Threading.Thread.Sleep(11);

    return new Response.RunJavascriptInCurrentPageResponseStructure
    {
        requestId = request.requestId,
        webBrowserAvailable = true,
        directReturnValueAsString = directReturnValueAsString,
        callbackReturnValueAsString = callbackReturnValue,
    };
}

void KillPreviousWebBrowserProcesses(string userProfileId)
{
    var matchingProcesses =
        System.Diagnostics.Process.GetProcesses()
        .Select(process =>
        {
            if(!ProcessIsWebBrowser(process))
                return null;

            ProcessCommandLine.Retrieve(process, out var commandLine);

            if(commandLine == null)
                return null;

            var userDataDir =
                GetUserDataDirFromChromeCommandLine(commandLine);

            if(!(userDataDir?.ToLowerInvariant()?.Contains(userProfileId.ToLowerInvariant()) ?? false))
                return null;

            return process;
        })
        .Where(process => process != null)
        .ToList();

    foreach (var process in matchingProcesses)
    {
        if (process.HasExited)
            continue;

        process.Kill();
    }
}

bool ProcessIsWebBrowser(System.Diagnostics.Process process)
{
    try
    {
        return process.MainModule.FileName.Contains(".local-chromium");
    }
    catch
    {
        return false;
    }
}

static string GetUserDataDirFromChromeCommandLine(string commandLine)
{
    var regexMatch =
        System.Text.RegularExpressions.Regex.Match(commandLine, "--user-data-dir=\\"(?<directory>[^\\"]+)");

    if (!regexMatch.Success)
        return null;

    return regexMatch.Groups["directory"].Value;
}

/*
https://stackoverflow.com/questions/2633628/can-i-get-command-line-arguments-of-other-processes-from-net-c/46006415#46006415
https://github.com/sonicmouse/ProcCmdLine/blob/524a662d1466c7342f54bcecfcd4a687005e573a/ManagedProcessCommandLine/ProcessCommandLine.cs
*/
public static class ProcessCommandLine
{
    private static class Win32Native
    {
        public const uint PROCESS_BASIC_INFORMATION = 0;

        [Flags]
        public enum OpenProcessDesiredAccessFlags : uint
        {
            PROCESS_VM_READ = 0x0010,
            PROCESS_QUERY_INFORMATION = 0x0400,
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct ProcessBasicInformation
        {
            public IntPtr Reserved1;
            public IntPtr PebBaseAddress;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2)]
            public IntPtr[] Reserved2;
            public IntPtr UniqueProcessId;
            public IntPtr Reserved3;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct UnicodeString
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        // This is not the real struct!
        // I faked it to get ProcessParameters address.
        // Actual struct definition:
        // https://docs.microsoft.com/en-us/windows/win32/api/winternl/ns-winternl-peb
        [StructLayout(LayoutKind.Sequential)]
        public struct PEB
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
            public IntPtr[] Reserved;
            public IntPtr ProcessParameters;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RtlUserProcessParameters
        {
            public uint MaximumLength;
            public uint Length;
            public uint Flags;
            public uint DebugFlags;
            public IntPtr ConsoleHandle;
            public uint ConsoleFlags;
            public IntPtr StandardInput;
            public IntPtr StandardOutput;
            public IntPtr StandardError;
            public UnicodeString CurrentDirectory;
            public IntPtr CurrentDirectoryHandle;
            public UnicodeString DllPath;
            public UnicodeString ImagePathName;
            public UnicodeString CommandLine;
        }

        [DllImport("ntdll.dll")]
        public static extern uint NtQueryInformationProcess(
            IntPtr ProcessHandle,
            uint ProcessInformationClass,
            IntPtr ProcessInformation,
            uint ProcessInformationLength,
            out uint ReturnLength);

        [DllImport("kernel32.dll")]
        public static extern IntPtr OpenProcess(
            OpenProcessDesiredAccessFlags dwDesiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool bInheritHandle,
            uint dwProcessId);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ReadProcessMemory(
            IntPtr hProcess, IntPtr lpBaseAddress, IntPtr lpBuffer,
            uint nSize, out uint lpNumberOfBytesRead);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("shell32.dll", SetLastError = true,
            CharSet = CharSet.Unicode, EntryPoint = "CommandLineToArgvW")]
        public static extern IntPtr CommandLineToArgv(string lpCmdLine, out int pNumArgs);
    }

    private static bool ReadStructFromProcessMemory<TStruct>(
        IntPtr hProcess, IntPtr lpBaseAddress, out TStruct val)
    {
        val = default;
        var structSize = Marshal.SizeOf<TStruct>();
        var mem = Marshal.AllocHGlobal(structSize);
        try
        {
            if (Win32Native.ReadProcessMemory(
                hProcess, lpBaseAddress, mem, (uint)structSize, out var len) &&
                (len == structSize))
            {
                val = Marshal.PtrToStructure<TStruct>(mem);
                return true;
            }
        }
        finally
        {
            Marshal.FreeHGlobal(mem);
        }
        return false;
    }

    public static string ErrorToString(int error) =>
        new string[]
        {
        "Success",
        "Failed to open process for reading",
        "Failed to query process information",
        "PEB address was null",
        "Failed to read PEB information",
        "Failed to read process parameters",
        "Failed to read parameter from process"
        }[Math.Abs(error)];

    public enum Parameter
    {
        CommandLine,
        WorkingDirectory,
    }

    public static int Retrieve(
        System.Diagnostics.Process process,
        out string parameterValue,
        Parameter parameter = Parameter.CommandLine)
    {
        int rc = 0;
        parameterValue = null;
        var hProcess = Win32Native.OpenProcess(
            Win32Native.OpenProcessDesiredAccessFlags.PROCESS_QUERY_INFORMATION |
            Win32Native.OpenProcessDesiredAccessFlags.PROCESS_VM_READ, false, (uint)process.Id);
        if (hProcess != IntPtr.Zero)
        {
            try
            {
                var sizePBI = Marshal.SizeOf<Win32Native.ProcessBasicInformation>();
                var memPBI = Marshal.AllocHGlobal(sizePBI);
                try
                {
                    var ret = Win32Native.NtQueryInformationProcess(
                        hProcess, Win32Native.PROCESS_BASIC_INFORMATION, memPBI,
                        (uint)sizePBI, out var len);
                    if (0 == ret)
                    {
                        var pbiInfo = Marshal.PtrToStructure<Win32Native.ProcessBasicInformation>(memPBI);
                        if (pbiInfo.PebBaseAddress != IntPtr.Zero)
                        {
                            if (ReadStructFromProcessMemory<Win32Native.PEB>(hProcess,
                                pbiInfo.PebBaseAddress, out var pebInfo))
                            {
                                if (ReadStructFromProcessMemory<Win32Native.RtlUserProcessParameters>(
                                    hProcess, pebInfo.ProcessParameters, out var ruppInfo))
                                {
                                    string ReadUnicodeString(Win32Native.UnicodeString unicodeString)
                                    {
                                        var clLen = unicodeString.MaximumLength;
                                        var memCL = Marshal.AllocHGlobal(clLen);
                                        try
                                        {
                                            if (Win32Native.ReadProcessMemory(hProcess,
                                                unicodeString.Buffer, memCL, clLen, out len))
                                            {
                                                rc = 0;
                                                return Marshal.PtrToStringUni(memCL);
                                            }
                                            else
                                            {
                                                // couldn't read parameter line buffer
                                                rc = -6;
                                            }
                                        }
                                        finally
                                        {
                                            Marshal.FreeHGlobal(memCL);
                                        }
                                        return null;
                                    }

                                    switch (parameter)
                                    {
                                        case Parameter.CommandLine:
                                            parameterValue = ReadUnicodeString(ruppInfo.CommandLine);
                                            break;
                                        case Parameter.WorkingDirectory:
                                            parameterValue = ReadUnicodeString(ruppInfo.CurrentDirectory);
                                            break;
                                    }
                                }
                                else
                                {
                                    // couldn't read ProcessParameters
                                    rc = -5;
                                }
                            }
                            else
                            {
                                // couldn't read PEB information
                                rc = -4;
                            }
                        }
                        else
                        {
                            // PebBaseAddress is null
                            rc = -3;
                        }
                    }
                    else
                    {
                        // NtQueryInformationProcess failed
                        rc = -2;
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(memPBI);
                }
            }
            finally
            {
                Win32Native.CloseHandle(hProcess);
            }
        }
        else
        {
            // couldn't open process for VM read
            rc = -1;
        }
        return rc;
    }

    public static IReadOnlyList<string> CommandLineToArgs(string commandLine)
    {
        if (string.IsNullOrEmpty(commandLine)) { return Array.Empty<string>(); }

        var argv = Win32Native.CommandLineToArgv(commandLine, out var argc);
        if (argv == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        try
        {
            var args = new string[argc];
            for (var i = 0; i < args.Length; ++i)
            {
                var p = Marshal.ReadIntPtr(argv, i * IntPtr.Size);
                args[i] = Marshal.PtrToStringUni(p);
            }
            return args.ToList().AsReadOnly();
        }
        finally
        {
            Marshal.FreeHGlobal(argv);
        }
    }
}

string SerializeToJsonForBot<T>(T value) =>
    Newtonsoft.Json.JsonConvert.SerializeObject(
        value,
        //  Use settings to get same derivation as at https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L91-L97
        new Newtonsoft.Json.JsonSerializerSettings
        {
            //  Bot code does not expect properties with null values, see https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
            NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,

            // https://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
            ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
        });

static async System.Threading.Tasks.Task startBrowserAndSaveScreenshotToFile(string outputFilePath)
{
    await new PuppeteerSharp.BrowserFetcher().DownloadAsync(PuppeteerSharp.BrowserFetcher.DefaultRevision);
    var browser = await PuppeteerSharp.Puppeteer.LaunchAsync(new PuppeteerSharp.LaunchOptions
    {
        Headless = false
    });
    var page = await browser.NewPageAsync();
    await page.GoToAsync("http://www.google.com");
    await page.ScreenshotAsync(outputFilePath);
}

string InterfaceToHost_Request(string request)
{
    return serialRequest(request);
}

"""

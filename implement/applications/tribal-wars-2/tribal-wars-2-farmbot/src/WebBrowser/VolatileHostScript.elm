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
    }
}

class Response
{
    public RunJavascriptInCurrentPageResponseStructure RunJavascriptInCurrentPageResponse;

    public object WebBrowserStarted;

    public class RunJavascriptInCurrentPageResponseStructure
    {
        public string requestId;

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
        KillPreviousWebBrowserProcesses();

        StartBrowser(request.StartWebBrowserRequest.pageGoToUrl).Wait();

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

static string UserDataDirPath() =>
    System.IO.Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA"), "bot", "web-browser", "user-data");

PuppeteerSharp.Browser browser;
PuppeteerSharp.Page browserPage;

Action<string> callbackFromBrowserDelegate;

async System.Threading.Tasks.Task StartBrowser(string pageGoToUrl)
{
    await new PuppeteerSharp.BrowserFetcher().DownloadAsync(PuppeteerSharp.BrowserFetcher.DefaultRevision);
    browser = await PuppeteerSharp.Puppeteer.LaunchAsync(new PuppeteerSharp.LaunchOptions
    {
        Headless = false,
        UserDataDir = UserDataDirPath(),
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
        directReturnValueAsString = directReturnValueAsString,
        callbackReturnValueAsString = callbackReturnValue,
    };
}

void KillPreviousWebBrowserProcesses()
{
    var matchingProcesses =
        System.Diagnostics.Process.GetProcesses()
        /*
        2020-02-17
        .Where(process => process.StartInfo.Arguments.Contains(UserDataDirPath(), StringComparison.InvariantCultureIgnoreCase))
        */
        .Where(ProcessIsWebBrowser)
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

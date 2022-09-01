using System;
using System.Linq;

namespace web_browser_csharp;

class Program
{
    static PuppeteerSharp.Browser browser;
    static PuppeteerSharp.Page browserPage;

    static Action<string> callbackFromBrowserDelegate;

    static string UserDataDirPath(string userProfileId) =>
        System.IO.Path.Combine(
            Environment.GetEnvironmentVariable("LOCALAPPDATA"), "bot", "web-browser", "user-profile", userProfileId, "user-data");

    static string BrowserDownloadDirPath() =>
        System.IO.Path.Combine(
            Environment.GetEnvironmentVariable("LOCALAPPDATA"), "bot", "web-browser", "download");

    static void Main(string[] args)
    {
        /*
        2020-02-17 Observation before introducing the killing of previous web browser processes:
        LaunchAsync failed if a process from the last run was still present.
        (See report of this issue at https://forum.botlab.org/t/farm-manager-tribal-wars-2-farmbot/3038/32?u=viir)

        Unhandled exception. System.AggregateException: One or more errors occurred. (Failed to launch Chromium! [28592:33396:0217/074915.470:ERROR:cache_util_win.cc(21)] Unable to move the cache: Access is denied. (0x5)
        [28592:33396:0217/074915.471:ERROR:cache_util.cc(141)] Unable to move cache folder C:\Users\John\AppData\Local\bot\web-browser\user-data\ShaderCache\GPUCache to C:\Users\John\AppData\Local\bot\web-browser\user-data\ShaderCache\old_GPUCache_000
        [28592:33396:0217/074915.471:ERROR:disk_cache.cc(178)] Unable to create cache
        [28592:33396:0217/074915.471:ERROR:shader_disk_cache.cc(601)] Shader Cache Creation failed: -2
        [28592:33396:0217/074915.473:ERROR:browser_gpu_channel_host_factory.cc(138)] Failed to launch GPU process.
        )
        ---> PuppeteerSharp.ChromiumProcessException: Failed to launch Chromium! [28592:33396:0217/074915.470:ERROR:cache_util_win.cc(21)] Unable to move the cache: Access is denied. (0x5)
        [28592:33396:0217/074915.471:ERROR:cache_util.cc(141)] Unable to move cache folder C:\Users\John\AppData\Local\bot\web-browser\user-data\ShaderCache\GPUCache to C:\Users\John\AppData\Local\bot\web-browser\user-data\ShaderCache\old_GPUCache_000
        [28592:33396:0217/074915.471:ERROR:disk_cache.cc(178)] Unable to create cache
        [28592:33396:0217/074915.471:ERROR:shader_disk_cache.cc(601)] Shader Cache Creation failed: -2
        [28592:33396:0217/074915.473:ERROR:browser_gpu_channel_host_factory.cc(138)] Failed to launch GPU process.

        at PuppeteerSharp.ChromiumProcess.State.StartingState.StartCoreAsync(ChromiumProcess p)
        at PuppeteerSharp.ChromiumProcess.State.StartingState.StartCoreAsync(ChromiumProcess p)
        at PuppeteerSharp.Launcher.LaunchAsync(LaunchOptions options)
        at PuppeteerSharp.Launcher.LaunchAsync(LaunchOptions options)
        */

        KillPreviousWebBrowserProcesses();

        StartWebBrowser().Wait();
    }

    static void KillPreviousWebBrowserProcesses()
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

    static bool ProcessIsWebBrowser(System.Diagnostics.Process process)
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

    static async System.Threading.Tasks.Task StartWebBrowser()
    {
        var browserRevision = PuppeteerSharp.BrowserFetcher.DefaultChromiumRevision;

        var browserFetcher = new PuppeteerSharp.BrowserFetcher(new PuppeteerSharp.BrowserFetcherOptions
        {
            Path = BrowserDownloadDirPath()
        });

        await browserFetcher.DownloadAsync(browserRevision);

        browser = await PuppeteerSharp.Puppeteer.LaunchAsync(new PuppeteerSharp.LaunchOptions
        {
            Headless = false,
            UserDataDir = UserDataDirPath("default"),
            DefaultViewport = null,
            ExecutablePath = browserFetcher.RevisionInfo(browserRevision).ExecutablePath,
        });
        browserPage = (await browser.PagesAsync()).FirstOrDefault() ?? await browser.NewPageAsync();

        await browserPage.ExposeFunctionAsync("____callback____", (string returnValue) =>
        {
            callbackFromBrowserDelegate?.Invoke(returnValue);
            return 0;
        });
    }

}

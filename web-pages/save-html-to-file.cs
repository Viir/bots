using System;
using System.Linq;
using PuppeteerSharp;

Host.Log("This is a tool to save HTML of a web page to a file.");

var browserPage = WebBrowser.OpenNewBrowserPage();

browserPage.SetViewportAsync(new ViewPortOptions { Width = 1112, Height = 726, }).Wait();

browserPage.Browser.PagesAsync().Result.Except(new []{browserPage}).Select(page => { page.CloseAsync().Wait(); return 4;}).ToList();

Host.Log("Looks like opening the web browser was successful. Please set up the web page in the browser window I opened. I will now pause this script. When you press the 'Continue' button, I will save the HTML of the current web page to a file.");

Host.Break();

Host.Log("Starting to get HTML");

var html = browserPage.EvaluateExpressionAsync<string>("document.documentElement.outerHTML").Result;

Host.Log("Got HTML with length of " + html?.Length);

var destDirectory = System.IO.Path.Combine(System.AppDomain.CurrentDomain.BaseDirectory, "saved-html");

var destFilePath = System.IO.Path.Combine(destDirectory, DateTime.UtcNow.ToString("yyyy-MM-ddThh-mm-ss") + ".html");

System.IO.Directory.CreateDirectory(destDirectory);

Host.Log("Starting to save HTML to file at '" + destFilePath + "'.");

System.IO.File.WriteAllText(destFilePath, html, System.Text.Encoding.UTF8);

Host.Log("Saved HTML to file at '" + destFilePath + "'.");


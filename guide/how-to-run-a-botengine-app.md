# How to Run a BotEngine App

## Starting an App

Download the BotEngine Windows console app from 
[https://botengine.blob.core.windows.net/blob-library/by-name/2020-08-24-botengine-console.zip](https://botengine.blob.core.windows.net/blob-library/by-name/2020-08-24-botengine-console.zip).

Extract this Zip-Archive. This will give you a file named `BotEngine.exe`. To start an app, call this program with a command like the following:

```cmd
C:\path\to\the\BotEngine.exe  run  "https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings"
```

You can enter this command in the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe). This app comes by default with any Windows 10 installation.

The engine then loads the app program from the specified location and runs it until you stop it or the app stops itself.

### The `app-source` Parameter

The `app-source` parameter at the end of the command tells the engine where to load the program code from. It can point to different kinds of sources:

+ A directory on the local file system. Example: `C:\directory-containing-app-code`.
+ A directory in a repository on [Github](https://github.com). Example: `https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings`

Developers use Github to collaborate and share code. Using the local file system as the source can be more convenient when you make changes to the app code which you only want to test yourself.

## Operating the App

While an app is running, the engine displays status information in the console window. This display is updated as the app continues operating.
Most of the time, you don't need to watch this. After all, that is the point of automation right?

To go back in time and see past status information from the app, you can use the time-travel functionality in the devtools: https://to.botengine.org/guide/observing-and-inspecting-an-app

But in case an app gets stuck, you want to take a look at this status display. Among general information from the engine, this display can also contain information as coded by the author. This way, the app can tell about the goal of its current actions or inform you about problems. For example, this [auto-pilot bot](https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/applications/eve-online/eve-online-warp-to-0-autopilot) shows diverse messages to inform you what it is doing at the moment. When you run this bot, the console window might show a text like the following:

```
App ebb5faf0d1... in session '' ('2020-09-02T19-04-33-d96095') is running. Press SHIFT + CTRL + ALT keys to pause the app.
Last app event was 0 seconds ago at 19-06-36.653. There are 0 tasks in progress.
Status message from app:

jumps completed: 0
current solar system: Kemerk
+ I see ship UI and overview, undocking complete.
++ I see no route in the info panel. I will start when a route is set.
+++ Wait
```

You can pause the app by pressing the `SHIFT` + `CTRL` + `ALT` keys. To let the app continue, focus the console window and press the enter key. The key combination `CTRL` + `C` stops the app and the botengine process.

## Configuring an App

Some apps offer customization using settings. When starting an app from the command line, you can use the `--app-settings` parameter to apply settings. The complete command line can then look as follows:

```cmd
C:\path\to\the\botengine.exe  run  --app-settings="My app settings"  "https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings"
```

The supported settings depend entirely on the app that you chose. To learn which settings are supported in your case, read the description for the app or contact its author.

## Viewing App Description

Authors often include a human-readable description with the app code, for example, in this app: https://github.com/Viir/bots/blob/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings/BotEngineApp.elm

You can display this description using the `botengine  describe` command:

```cmd
C:\path\to\the\BotEngine.exe  describe  "https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings"
```

The `describe` command works with any app source that is supported by the `run` command.

The information you get this way includes the description given by the author of the app. This description often contains a guide on how to use the app.


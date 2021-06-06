# How to Run a BotEngine App

## Comparing Live Run and Simulated Run

Running an app can serve various goals. We categorize those goals broadly into two groups as follows:

1. **To achieve an effect in some other system or app, like a game client.** In this case, we want the app to interact with the world around it. The app reads information from and sends inputs to another app. We call this a 'live' or 'productive' run.

2. **To understand how the app works or to test if it works as expected.** In this case, we isolate the app in a simulation, which means it cannot send any inputs and not affect any other app. We call this a 'simulated' or 'test' run.

Every time we start to run an app, we choose one of these two modes, depending on whether we want it to work in a live environment or test it.
From the app's perspective, there is no difference between a live run and a simulated run. The app does not know if it is running in a simulation.

## Prerequisites - Installing and Registering the Botengine Command

Before running any app for the first time, we install the botengine program on Windows and register the `botengine` command. If you are not sure you have done this for your system, check the installation guide at https://to.botengine.org/failed-run-did-not-find-botengine-program

## Running an App Live

Here is a video showing how to start a live run of an app, also covering the initial download and installation: https://to.botengine.org/guide/video/how-to-run-a-botengine-app-live

After following the installation guide, our Windows system is ready to run apps.

A common way to run an app is to use a script file downloaded from the [catalog website](https://catalog.botengine.org/)

Besides running a `.bat` script file, an alternative way to run an app live is entering a command like the following:

```cmd
botengine  run  "https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings"
```

You can enter this command in the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe) or in [PowerShell](https://en.wikipedia.org/wiki/PowerShell). Both 'Command Prompt' and PowerShell are included in any Windows 10 installation by default.

The engine then loads the app program from the specified location and runs it until you stop it or the app stops itself.

### The `app-source` Parameter

The `app-source` parameter at the end of the command tells the engine where to load the program code from. It can point to different kinds of sources:

+ A directory on the local file system. Example: `C:\directory-containing-app-code`.
+ A directory in a repository on [Github](https://github.com). Example: `https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings`

Developers use Github to collaborate and share code. Using the local file system as the source can be more convenient when you make changes to the app code which you only want to test yourself.

### Operating the App

When running an app live, the engine displays status information in the console window. This display is updated as the app continues operating.
Most of the time, you don't need to watch this. After all, that is the point of automation right?

To go back in time and see past status information from the app, you can use the time-travel functionality in the devtools: https://to.botengine.org/guide/observing-and-inspecting-an-app

But in case an app gets stuck, you want to take a look at this status display. Among general information from the engine, this display can also contain information as coded by the author. This way, the app can tell about the goal of its current actions or inform you about problems. For example, this [auto-pilot bot](https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/applications/eve-online/eve-online-warp-to-0-autopilot) shows diverse messages to inform you what it is doing at the moment. When you run this bot, the console window might show a text like the following:

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

### Configuring the App

Some apps offer customization using settings. When starting an app from the command line, you can use the `--app-settings` parameter to apply settings. The complete command line can then look as follows:

```cmd
botengine  run  --app-settings="My app settings"  "https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings"
```

The supported settings depend entirely on the app that you chose. To learn which settings are supported in your case, read the description for the app or contact its author.

## Viewing App Description

Authors often include a human-readable description with the app code, for example, in this app: https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings/BotEngineApp.elm

You can display this description using the `botengine  describe` command:

```cmd
botengine  describe  "https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings"
```

The `describe` command works with any app source that is supported by the `run` command.

The information you get this way includes the description given by the author of the app. This description often contains a guide on how to use the app.

Here is the output we get when running this command in PowerShell:

```txt
PS C:\Users\John> botengine  describe  "https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings"
This path looks like a URL. I try to load from a remote git repository.
I found 5 files in 'https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings'.
This path points to composition 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701
This path points to commit e9cf4964fbed5d314c76386f1eef75474c5f59dd
The first parent commit with 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701 is https://github.com/Viir/bots/tree/38f0f74d4784b648e4cd9b5d57b02e62813f0bd1/implement/templates/remember-app-settings
Participants from commit 38f0f74d4784b648e4cd9b5d57b02e62813f0bd1:
Author: Michael Rätzel <viir@viir.de>
Committer: Michael Rätzel <viir@viir.de>
Composition 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701 has the structure of an app program code.
Description of app 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701:
framework ID: 1768122f3a17d67ee499ca42ad83baecac7e649a8ea52b3ffe0adcb47a216f87
I found the following description in the app code:
{- This bot demonstrates how to remember the app settings string.
   It takes any settings string received from the user and stores it in the app state.
   This app also updates the status message to show the last received settings string, so you can check that a method (e.g., via command line) of applying the settings works.
-}
app-catalog-tags: template, app-settings, demo-interface-to-host
authors forum usernames: viir
```

## Running an App in a Simulation

To learn about testing an app using simulations, see the dedicated guide at https://to.botengine.org/guide/testing-an-app-using-simulations

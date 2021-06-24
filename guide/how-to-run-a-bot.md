# How to Run a Bot

## Comparing Live Run and Simulated Run

Running a bot can serve various goals. We categorize those goals broadly into two groups as follows:

1. **To achieve an effect in some other system or software, like a game client.** In this case, we want the bot to interact with the world around it. The bot reads information from and sends inputs to another software. We call this a 'live' or 'productive' run.

2. **To understand how the bot works or to test if it works as expected.** In this case, we isolate the bot in a simulation, which means it cannot send any inputs and not affect any other software. We call this a 'simulated' or 'test' run.

Every time we start to run an bot, we choose one of these two modes, depending on whether we want it to work in a live environment or test it.
From the bot's perspective, there is no difference between a live run and a simulated run. The bot does not know if it is running in a simulation.

## Prerequisites - Installing and Registering the `botlab` Command

Before running any bot for the first time, we install the BotLab client on Windows and register the `botlab` command. If you are not sure you have done this for your system, check the installation guide at https://to.botlab.org/guide/how-to-install-the-botlab-client-and-register-the-botlab-command

## Running a Bot Live

Here is a video showing how to start a live run of a bot, also covering the initial download and installation: https://to.botlab.org/guide/video/how-to-run-a-bot-live

After following the installation guide, our Windows system is ready to run bots.

A common way to run a bot is to use a script file downloaded from the [catalog website](https://catalog.botlab.org/)

Besides running a `.bat` script file, an alternative way to run a bot live is entering a command like the following:

```cmd
botlab  run  "https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings"
```

You can enter this command in the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe) or in [PowerShell](https://en.wikipedia.org/wiki/PowerShell). Both 'Command Prompt' and PowerShell are included in any Windows 10 installation by default.

The engine then loads the bot program from the specified location and runs it until you stop it or the bot stops itself.

### The `program-source` Parameter

The `program-source` parameter at the end of the command tells the engine where to load the program code from. It can point to different kinds of sources:

+ A directory on the local file system. Example: `C:\directory-containing-program-code`.
+ A directory in a repository on [Github](https://github.com). Example: `https://github.com/Viir/bots/tree/25cd2fbc264b97bd15257bca6f3414e75f206b67/implement/templates/remember-app-settings`

Developers use Github to collaborate and share code. Using the local file system as the source can be more convenient when you make changes to the program code which you only want to test yourself.

### Operating the Bot

When running a bot live, the engine displays status information in the console window. This display is updated as the bot continues operating.
Most of the time, you don't need to watch this. After all, that is the point of automation right?

To go back in time and see past status information from the bot, you can use the time-travel functionality in the devtools: https://to.botlab.org/guide/observing-and-inspecting-a-bot

But in case a bot gets stuck, you want to take a look at this status display. Among general information from the engine, this display can also contain information as coded by the author. This way, the bot can tell you about the goal of its current actions or inform you about problems. For example, this [auto-pilot bot](https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/applications/eve-online/eve-online-warp-to-0-autopilot) shows diverse messages to inform you what it is doing at the moment. When you run this bot, the console window might show a text like the following:

```
Bot ebb5faf0d1... in session '' ('2020-09-02T19-04-33-d96095') is running. Press SHIFT + CTRL + ALT keys to pause the bot.
Last bot event was 0 seconds ago at 19-06-36.653. There are 0 tasks in progress.
Status message from bot:

jumps completed: 0
current solar system: Kemerk
+ I see ship UI and overview, undocking complete.
++ I see no route in the info panel. I will start when a route is set.
+++ Wait
```

You can pause the bot by pressing the `SHIFT` + `CTRL` + `ALT` keys. To let the bot continue, focus the console window and press the enter key. The key combination `CTRL` + `C` stops the bot and the BotLab client process.

### Configuring the Bot

Some bots offer customization using settings. When starting a bot from the command line, you can use the `--app-settings` parameter to apply settings. The complete command line can then look as follows:

```cmd
botlab  run  --app-settings="My app settings"  "https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings"
```

The supported settings depend entirely on the bot that you chose. To learn which settings are supported in your case, read the description for the bot or contact its author.

## Viewing Bot Description

Authors often include a human-readable description with the program code, for example, in this bot: https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings/BotEngineApp.elm

You can display this description using the `botlab  describe` command:

```cmd
botlab  describe  "https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings"
```

The `describe` command works with any program source that is supported by the `run` command.

The information you get this way includes the description given by the author of the bot. This description often contains a guide on how to use the bot.

Here is the output we get when running this command in PowerShell:

```txt
PS C:\Users\John> botlab  describe  "https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings"
This path looks like a URL. I try to load from a remote git repository.
I found 5 files in 'https://github.com/Viir/bots/tree/e9cf4964fbed5d314c76386f1eef75474c5f59dd/implement/templates/remember-app-settings'.
This path points to composition 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701
This path points to commit e9cf4964fbed5d314c76386f1eef75474c5f59dd
The first parent commit with 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701 is https://github.com/Viir/bots/tree/38f0f74d4784b648e4cd9b5d57b02e62813f0bd1/implement/templates/remember-app-settings
Participants from commit 38f0f74d4784b648e4cd9b5d57b02e62813f0bd1:
Author: Michael Rätzel <viir@viir.de>
Committer: Michael Rätzel <viir@viir.de>
Composition 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701 has the structure of an bot program code.
Description of bot 54daa2a766f4845fd7cac0e1e092f251157e81f47a074c004f25e55738489701:
framework ID: 1768122f3a17d67ee499ca42ad83baecac7e649a8ea52b3ffe0adcb47a216f87
I found the following description in the program code:
{- This bot demonstrates how to remember the app settings string.
   It takes any settings string received from the user and stores it in the program state.
   This bot also updates the status message to show the last received settings string, so you can check that a method (e.g., via command line) of applying the settings works.
-}
catalog-tags: template, app-settings, demo-interface-to-host
authors forum usernames: viir
```

## Running a Bot in a Simulation

To learn about testing a bot using simulations, see the dedicated guide at https://to.botlab.org/guide/testing-a-bot-using-simulations

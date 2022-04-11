# How to Run a Bot

## Comparing Live Run and Simulated Run

Running a bot can serve various goals. We categorize those goals broadly into two groups as follows:

1. **To achieve an effect in some other system or software, like a game client.** In this case, we want the bot to interact with the world around it. The bot reads information from and sends inputs to another software. We call this a 'live' or 'productive' run.

2. **To understand how the bot works or to test if it works as expected.** In this case, we isolate the bot in a simulation, which means it cannot send any inputs and not affect any other software. We call this a 'simulated' or 'test' run.

Every time we start running a bot, we choose one of these two modes, depending on whether we want it to work in a live environment or test it. There is no difference between a live run and a simulated run from the bot's perspective. The bot does not know if it is running in a simulation.

## Prerequisites - Installing and Registering the `botlab` Command

Before running any bot for the first time, we install the BotLab client on Windows and register the `botlab` command. If you are not sure you have done this for your system, check the installation guide at https://to.botlab.org/guide/how-to-install-the-botlab-client-and-register-the-botlab-command

## Running a Bot Live

Here is a video showing how to start a live run of a bot, also covering the initial download and installation: https://to.botlab.org/guide/video/how-to-run-a-bot-live

After following the installation guide, our Windows system is ready to run bots.

A common way to run a bot is to use a script file downloaded from the [catalog website](https://catalog.botlab.org/)

Besides running a `.bat` script file, an alternative way to run a bot live is entering a command like the following:

```cmd
botlab  play  https://github.com/Viir/bots/tree/e1eac00ab6a818e722fd64d552a2615d78f9628b/implement/templates/remember-bot-settings
```

You can enter this command in the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe) or in [PowerShell](https://en.wikipedia.org/wiki/PowerShell). Both 'Command Prompt' and PowerShell are included in any Windows 10 installation by default.

The engine then loads the bot program from the specified location and runs it until you stop it or the bot stops itself.

### The `program-source` Parameter

The `program-source` parameter at the end of the command tells the engine where to load the program code from. It can point to different kinds of sources:

+ A directory on the local file system. Example: `C:\directory-containing-program-code`.
+ A directory in a repository on [Github](https://github.com). Example: `https://github.com/Viir/bots/tree/e1eac00ab6a818e722fd64d552a2615d78f9628b/implement/templates/remember-bot-settings`

Developers use Github to collaborate and share code. Using the local file system as the source can be more convenient when you make changes to the program code which you only want to test yourself.

### Operating the Bot

When running a bot live, the engine displays status information in the console window. This display is updated as the bot continues operating.
Most of the time, you don't need to watch this. After all, that is the point of automation right?

To go back in time and see past status information from the bot, you can use the time-travel functionality in the devtools: https://to.botlab.org/guide/observing-and-inspecting-a-bot

But in case a bot gets stuck, you want to take a look at this status display. Among general information from the engine, this display can also contain information as coded by the author. This way, the bot can tell you about the goal of its current actions or inform you about problems. For example, this [auto-pilot bot](https://github.com/Viir/bots/tree/e1eac00ab6a818e722fd64d552a2615d78f9628b/implement/applications/eve-online/eve-online-warp-to-0-autopilot) shows diverse messages to inform you what it is doing at the moment. When you run this bot, the botlab client might show a text like the following in the section 'Status text from bot':

```
jumps completed: 0
current solar system: Kemerk
+ I see ship UI and overview, undocking complete.
++ I see no route in the info panel. I will start when a route is set.
+++ Wait
```

You can pause the bot by pressing the `SHIFT` + `CTRL` + `ALT` keys. To let the bot continue, focus the console window and press the enter key. The key combination `CTRL` + `C` stops the bot and the BotLab client process.

### Configuring the Bot

Some bots offer customization using settings. When starting a bot from the command line, you can use the `--bot-settings` parameter to apply settings. The complete command line can then look as follows:

```cmd
botlab  play  --bot-settings="My bot settings"  https://github.com/Viir/bots/tree/e1eac00ab6a818e722fd64d552a2615d78f9628b/implement/templates/remember-bot-settings
```

The supported settings depend entirely on the bot that you chose. To learn which settings are supported in your case, read the description for the bot or contact its author.

## Viewing Bot Description

Authors often include a human-readable description with the program code, for example, in this bot: https://github.com/Viir/bots/tree/e1eac00ab6a818e722fd64d552a2615d78f9628b/implement/templates/remember-bot-settings/Bot.elm

You can display this description using the `botlab  describe` command:

```cmd
botlab  describe  https://github.com/Viir/bots/tree/e1eac00ab6a818e722fd64d552a2615d78f9628b/implement/templates/remember-bot-settings
```

The `describe` command works with any program source that is supported by the `run` command.

The information you get this way includes the description given by the author of the bot. This description often contains a guide on how to use the bot.

Here is the output we get when running this command in PowerShell:

```txt
This path looks like a URL into a remote git repository. Trying to load from there...
This path points to commit e1eac00ab6a818e722fd64d552a2615d78f9628b
The first parent commit with same tree is https://github.com/Viir/bots/tree/d8c31635334631840766c890ba2a544487816a23/implement/templates/remember-bot-settings
Participants from commit d8c31635334631840766c890ba2a544487816a23:
Author: Michael Rätzel <viir@viir.de>
Committer: Michael Rätzel <viir@viir.de>
Loaded composition  5b2552b4d02650a10015e3708bebba089c8ba5f1bb3776b43c582969d787e8da
I found 5 files in this artifact.
Checking if this composition is a bot program...

Composition 5b2552b4d02650a10015e3708bebba089c8ba5f1bb3776b43c582969d787e8da has the structure of a bot program code.
Description of bot 5b2552b4d02650a10015e3708bebba089c8ba5f1bb3776b43c582969d787e8da:
framework ID: b6a18fc059369ffc093e20fb0bda8ade6687fee3dd8fc3cbb0ef15fb2835b68c
I found the following description in the program code:
{- This program demonstrates how to remember the bot-settings string.

   It takes any settings string received from the user and stores it in the bot state.
   This bot also updates the status message to show the last received settings string, so you can check that a method (e.g., via command line) of applying the settings works.
-}
catalog-tags: template, bot-settings, demo-interface-to-host
authors forum usernames: viir
```

## Running a Bot in a Simulated Environment

To learn about testing a bot using simulated environments, see the dedicated guide at https://to.botlab.org/guide/testing-a-bot-using-simulated-environments

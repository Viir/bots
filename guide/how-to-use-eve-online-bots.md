# How to Use EVE Online Bots

In this guide, I show how to run EVE Online bots using the BotEngine console.

## What is a Bot?

A bot is a software which performs the following steps:

+ Learn about the current state of the game world by reading information from the game client. Usually, the bot does this by taking screenshots of the game client. In the case of EVE Online, we can also use [memory reading](https://github.com/Arcitectus/Sanderling) to get information from the game client.
+ Accomplish an in-game effect by sending inputs such as mouse clicks or key presses to the game client.

The bot runs as a continual process repeating these steps again and again until it reaches the configured goal or you stop it.

There also exists monitoring software which does not send any input to the game, but notifications to inform you about in-game events. You can use the BotEngine console to run these too.

## Prerequisites - Windows and .NET Framework

Before you can use the BotEngine console, you need to have the following software installed on your machine:
+ Windows 10 x64
+ `.NET Core 3.0 SDK Preview 5` for Windows x64. You can download the installer from https://dotnet.microsoft.com/download/thank-you/dotnet-sdk-3.0.100-preview5-windows-x64-installer
+ `.NET Framework 4.8 - Dev Pack` for Windows x64. You can download the installer from https://dotnet.microsoft.com/download/thank-you/net48-developer-pack

If no version of `.NET Core 3.0` is installed, the app might display an error message like the following on startup:

> The specified framework 'Microsoft.NETCore.App', version '3.0.0-preview5-27626-15' was not found.
>   - Check application dependencies and target a framework version installed at:
>       C:\Program Files\dotnet
>   - Installing .NET Core prerequisites might help resolve this problem:
>       https://go.microsoft.com/fwlink/?LinkID=798306&clcid=0x409
>   - The .NET Core framework and SDK can be installed from:
>       https://aka.ms/dotnet-download    
> [...]

## Starting a Bot

Download the BotEngine console from the following URL:
[https://botengine.blob.core.windows.net/blob-library/by-name/2019-08-14.BotEngine.Console.zip](https://botengine.blob.core.windows.net/blob-library/by-name/2019-08-14.BotEngine.Console.zip)

Extract this Zip-Archive to a directory. In this directory, you will find a file named `BotEngine.exe`. To start a bot, call this program with a command like the following:

```cmd
C:\path\to\the\botengine.exe  start-bot  --bot-source="https://github.com/Viir/bots/tree/a054948285918c5d8616e4f5941fcda015b7cee6/implement/bot/eve-online/eve-online-warp-to-0-autopilot"
```

You can use such a command, for example, in the Windows command line (cmd.exe).

The engine then loads the bot from the specified location and runs it until you stop it or the bot stops itself.

### `--Bot-Source` Parameter

The `--bot-source` parameter tells the engine where to load the bot code from. The `--bot-source` can point to following different kinds of sources:

+ A directory on the local file system. Example: `C:\directory-containing-bot-code`.
+ A directory in a repository on [Github](https://github.com). Example: `https://github.com/Viir/bots/tree/a054948285918c5d8616e4f5941fcda015b7cee6/implement/bot/eve-online/eve-online-warp-to-0-autopilot`

Developers use Github to collaborate and share code. Using the local file system as the source can be more convenient when you make changes to the bot code which you only want to test yourself.

## Operating the Bot

While a bot is running, the engine displays status information in the console window. This display is updated as the bot continues operating.
Most of the time, you don't need to watch this. After all, that is the point of automation right?

But in case a bot gets stuck, you want to take a look at this status display. Among general information from the engine, this display can also contain information as coded by the bot author. This way, the bot can tell about the goal of its current actions or inform you about problems. For example, this [warp to 0 auto-pilot bot](https://github.com/Viir/bots/tree/a054948285918c5d8616e4f5941fcda015b7cee6/implement/bot/eve-online/eve-online-warp-to-0-autopilot) shows diverse messages to inform you what it is doing at the moment. When you run this bot, the console window might show a text like the following:

```
Bot is running. Press CTRL + ALT keys to pause the bot.
Last bot event was 1 seconds ago at 15-09-48.781.
Status message from bot:

I see no route in the info panel. I will start when a route is set.
```

You can pause bot operation by pressing the `CTRL` + `ALT` keys. To let the bot continue, focus the console window and press the enter key. The key combination `CTRL` + `C` stops the bot and the botengine process.

## Configuring a Bot

Some bots support configuration. When starting a bot from the command line, you can use the `--bot-configuration` parameter to set the bot configuration. The complete command line can then look as follows:
```cmd
C:\path\to\the\botengine.exe  start-bot  --bot-source="https://github.com/Viir/bots/tree/a054948285918c5d8616e4f5941fcda015b7cee6/implement/bot/templates/demonstrate-bot-configuration" --bot-configuration="My bot configuration"
```

The supported bot configuration values depend entirely on the bot that you chose with the `--bot-source`. To learn which bot configuration values are supported in your case, look up the description for the bot or contact the developer of the bot. A good place to look for guidance on a specific bot is the `src/Bot.elm` file contained in the directory specified as `--bot-source`. Bot authors often write a guide at the beginning of that file, for example in [this EVE Online auto-pilot bot](https://github.com/Viir/bots/blob/a054948285918c5d8616e4f5941fcda015b7cee6/implement/bot/eve-online/eve-online-warp-to-0-autopilot/src/Bot.elm).

## Getting Help

If you have any questions, the [BotEngine forum](https://forum.botengine.org) is a good place to learn more.

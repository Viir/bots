# How to Run a Bot

## What is a Bot?

A bot is a software which performs the following steps:

+ Learn about the current state of the game world by reading information from the game client. Usually, the bot does this by taking screenshots of the game client. In the case of EVE Online, we can also use [memory reading](https://github.com/Arcitectus/Sanderling) to get information from the game client.
+ Accomplish an in-game effect by sending inputs such as mouse clicks or key presses to the game client.

The bot runs as a continual process repeating these steps again and again until it reaches the configured goal or you stop it.

There also exists monitoring software which does not send any input to the game, but notifications to inform you about in-game events. You can use the BotEngine console to run these too.

## Starting a Bot

Download the BotEngine Windows console app from 
[https://botengine.blob.core.windows.net/blob-library/by-name/2020-02-16-botengine-console.zip](https://botengine.blob.core.windows.net/blob-library/by-name/2020-02-16-botengine-console.zip).

Extract this Zip-Archive. This will give you a file named `BotEngine.exe`. To start a bot, call this program with a command like the following:

```cmd
C:\path\to\the\BotEngine.exe  run-bot  "https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/applications/eve-online/eve-online-warp-to-0-autopilot"
```

You can enter this command in the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe). This app comes by default with any Windows 10 installation.

The engine then loads the bot from the specified location and runs it until you stop it or the bot stops itself.

### The `bot-source` Parameter

The `bot-source` parameter at the end of the command tells the engine where to load the bot code from. It can point to different kinds of sources:

+ A directory on the local file system. Example: `C:\directory-containing-bot-code`.
+ A directory in a repository on [Github](https://github.com). Example: `https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/applications/eve-online/eve-online-warp-to-0-autopilot`

Developers use Github to collaborate and share code. Using the local file system as the source can be more convenient when you make changes to the bot code which you only want to test yourself.

## Operating the Bot

While a bot is running, the engine displays status information in the console window. This display is updated as the bot continues operating.
Most of the time, you don't need to watch this. After all, that is the point of automation right?

But in case a bot gets stuck, you want to take a look at this status display. Among general information from the engine, this display can also contain information as coded by the bot author. This way, the bot can tell about the goal of its current actions or inform you about problems. For example, this [warp to 0 auto-pilot bot](https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/applications/eve-online/eve-online-warp-to-0-autopilot) shows diverse messages to inform you what it is doing at the moment. When you run this bot, the console window might show a text like the following:

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
C:\path\to\the\botengine.exe  run-bot  --bot-configuration="My bot configuration"  "https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/templates/remember-bot-configuration"
```

The supported bot configuration values depend entirely on the bot that you chose. To learn which bot configuration values are supported in your case, look up the description for the bot or contact the developer of the bot. A good place to look for guidance on a specific bot is the `src/Bot.elm` file contained in the directory specified as `bot-source`. Bot authors often write a guide at the beginning of that file, for example in [this EVE Online mining bot](https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/applications/eve-online/eve-online-mining-bot/src/Bot.elm).

## Viewing Bot Description

To learn more about a bot, you can view its description, using the `describe-bot` command:

```cmd
C:\path\to\the\BotEngine.exe  describe-bot  "https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/applications/eve-online/eve-online-warp-to-0-autopilot"
```

The `describe-bot` command works with any bot source that is supported by the `run-bot` command.

The information you get this way includes the description given by the author of the app. This description often contains a guide on how to use the app.

## Online Bot Sessions

When running a bot, you can choose to start it in an online bot session. Online bot sessions provide several advantages over offline sessions:

+ Monitoring from any device: No need to go to your PC to check the status of your bot. You can use your smartphone or any other device with a web browser to see the status of your bot.
+ Organize and keep track of your operations and experiments: Easily see which bots you already tested and when you used them the last time.
+ Longer bot running time: Run a bot continuously in one session for up to 72 hours.

To see a list of your most recent online bot sessions, log in at https://reactor.botengine.org

Below is a screenshot of the website you can use to view your online bot sessions and monitor your bots:
![monitor your bots using online bot sessions](./image/2019-12-11.online-bot-session.png)

Online bot sessions cost 2000 credits per hour. To add credits to your account, follow the instructions at [https://reactor.botengine.org/billing/add-credits](https://reactor.botengine.org/billing/add-credits)

For more about purchasing and using credits, see the guide at [https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837](https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837)

### Starting an Online Bot Session

To start an online bot session, use the `--key-to-start-online-session` parameter with the `run-bot` command.

The complete parameter looks like this:

`--key-to-start-online-session=33168cd96cc3c1842b6fb`

Replace the part after the equals sign ('=') with your secret key.

To get your key, go to https://reactor.botengine.org and log in to your account. After logging in, you see the key under `Bot session keys`. Please don't share this key with anyone, and don't post it on the forum.

Below is an example of a full command to run a bot in an online session:
```cmd
botengine  run-bot  --key-to-start-online-session=33168cd96cc3c1842b6fb  "https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/templates/remember-bot-configuration"
```

## Getting Help

If you have any questions, the [BotEngine forum](https://forum.botengine.org) is a good place to learn more.

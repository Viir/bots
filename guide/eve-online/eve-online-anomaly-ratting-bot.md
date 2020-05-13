# EVE Online Anomaly Ratting Bot

This bot uses the probe scanner to warp to anomalies and kills rats using drones and weapon modules. 

## Features

+ **safe**: does not inject into or write to the EVE Online client. That is why using it with EVE Online is not detectable.
+ **accurate & robust**: This bot uses Sanderling memory reading to get information about the game state and user interface.

## Starting the Bot

+ Download the BotEngine Windows console app from 
[https://botengine.blob.core.windows.net/blob-library/by-name/2020-05-11-botengine-console.zip](https://botengine.blob.core.windows.net/blob-library/by-name/2020-05-11-botengine-console.zip). Extract this Zip-Archive. This will give you a file named `BotEngine.exe`.
+ Start the EVE Online client and log in to the game.
+ To start the autopilot bot, run the `BotEngine.exe` program with the following command:

```cmd
C:\path\to\the\BotEngine.exe  run  "https://github.com/Viir/bots/tree/8db3758e0bb81a0a1a6016b1a049f5f55a1b6b4a/implement/applications/eve-online/eve-online-anomaly-ratting-bot"
```
You can enter this command in the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe). This app comes by default with any Windows 10 installation.

After you have entered this command, the bot needs a few seconds to start and find the EVE Online client process. It also shows status messages to inform what it is doing at the moment and when the startup is complete.

![EVE Online App Starting](./image/2019-10-08.eve-online-autopilot-bot-startup.png)


Follow these steps to configure the game client:

+ Set the UI language to English.
+ Enable the info panel 'System info'.
+ Undock, open probe scanner, overview window and drones window.
+ Set the Overview window to sort objects in space by distance with the nearest entry at the top.
+ In the ship UI, arrange the modules:
  + Place to use in combat (to activate on targets) in the top row.
  + Place modules that should always be active in the middle row.
  + Hide passive modules by disabling the check-box `Display Passive Modules`.
+ Configure the keyboard key 'W' to make the ship orbit.

To meet bot developers and discuss development for EVE Online, see the [BotEngine forum](https://forum.botengine.org/tags/eve-online).

## Pricing and Online Bot Sessions

You can test the bot for free. When you want the bot to run more than 15 minutes per session, use an online-bot session as explained at [https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#online-bot-sessions](https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#online-bot-sessions)

Online bot sessions cost 2000 credits per hour. To add credits to your account, follow the instructions at [https://reactor.botengine.org/billing/add-credits](https://reactor.botengine.org/billing/add-credits)

For more about purchasing and using credits, see the guide at [https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837](https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837)


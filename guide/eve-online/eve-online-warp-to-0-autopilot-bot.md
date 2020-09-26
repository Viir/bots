# EVE Online Warp-To-0 Autopilot Bot

When playing EVE Online, you might spend significant time traveling between solar systems. This activity is so common that there is even an in-game autopilot to automate this process. But that autopilot has a critical flaw: It is quite inefficient and will cause long travel times. You can travel faster by manually commanding your ship.

Fortunately, this process can be automated using a bot. The bot we are using here follows the route set in the in-game autopilot and uses the context menu to initiate warp and dock commands.

## Starting the Autopilot Bot

To start the bot, download the script from https://catalog.botengine.org/c1764788c5da36c92d26cf0db5e3d1921b4e8801a80ce08ff5716d98996f5f55 and then run it.

In case the botengine program is not yet installed on your system, the script will redirect you to the installation guide at https://to.botengine.org/failed-run-did-not-find-botengine-program

After completing the installation, run the script again to start the bot.

The bot needs a few seconds to start and find the EVE Online client process. It also shows status messages to inform what it is doing at the moment and when the startup is complete.

![EVE Online Warp-To-0 Autopilot Starting](./image/2019-10-08.eve-online-autopilot-bot-startup.png)

When the startup sequence has completed, the bot might display this message:

> I see no route in the info panel. I will start when a route is set.

We need to set the destination in the in-game autopilot so that the route is visible in the `Route` info panel. But we do not start the in-game autopilot because it would interfere with our bot.
Also, this bot does not undock, so we need to undock our ship manually for the bot to start piloting. As long as the ship is docked, the bot displays the following message:

> I cannot see if the ship is warping or jumping. I wait for the ship UI to appear on the screen.

As soon as we undock, the bot will start to send mouse clicks to the game client to initiate warp and jump maneuvers.

The bot only works when the UI language is set to English. The bot reads the text in menu entries to decide where to click, and it only knows the English translations.

Alright, I think that is all there is to know about the basic autopilot bot. If you have questions about this bot or are searching for other bots, don't hesitate to ask on the [BotEngine forum](https://forum.botengine.org/).


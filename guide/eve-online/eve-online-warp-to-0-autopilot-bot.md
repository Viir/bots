# EVE Online Warp-To-0 Autopilot Bot

When playing EVE Online, you might spend significant time traveling between solar systems. This activity is so common that there is even an in-game autopilot to automate this process. But that autopilot has a critical flaw: It is quite inefficient and will cause long travel times. You can travel faster by manually commanding your ship.

Fortunately, this process can be automated using a bot. The bot we are using here follows the route set in the in-game autopilot and uses the context menu to initiate warp and dock commands.

## Starting the Autopilot Bot

If the BotLab client is not already installed on your machine, follow the guide at <https://to.botlab.org/guide/how-to-install-the-botlab-client>
The BotLab client is a tool for developing bots and also makes running bots easier with graphical user interfaces for configuration.

In the BotLab client, load the bot by entering the following link in the 'Select Bot' view:
<https://catalog.botlab.org/3a1493007de31d79>

There is a detailed walkthrough video on how to load and run a bot at <https://to.botlab.org/guide/video/how-to-run-a-bot-live>

Before starting the bot, set up the game client as follows:

+ Set the UI language to English.
+ Set the in-game autopilot route.
+ Make sure the autopilot info panel is expanded, so that the route is visible.

The bot needs a few seconds to start and find the EVE Online client process. It also shows status messages to inform what it is doing at the moment and when the startup is complete.

![EVE Online Bot Starting](./image/2023-03-08-botlab-gui-eve-online-bot-startup.png)

When the startup sequence has completed, the bot might display this message:

> I see no route in the info panel. I will start when a route is set.

We need to set the destination in the in-game autopilot so that the route is visible in the `Route` info panel. But we do not start the in-game autopilot because it would interfere with our bot.
Also, this bot does not undock, so we need to undock our ship manually for the bot to start piloting. As long as the ship is docked, the bot displays the following message:

> I cannot see if the ship is warping or jumping. I wait for the ship UI to appear on the screen.

As soon as we undock, the bot will start to send mouse clicks to the game client to initiate warp and jump maneuvers.

## Configuration Settings

Settings are optional; you only need them in case the defaults don't fit your use-case.

+ `activate-module-always` : Text found in tooltips of ship modules that should always be active. For example: "cloaking device".

Alright, I think that is all there is to know about the basic autopilot bot. If you have questions about this bot or are searching for other bots, don't hesitate to ask on the [BotLab forum](https://forum.botlab.org/).


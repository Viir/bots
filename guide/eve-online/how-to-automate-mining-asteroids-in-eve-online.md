# How to Automate Mining Asteroids in EVE Online

For this guide, I picked a mining bot optimal for beginners, which means easy to set up and use. After several iterations in development, this bot has matured to be robust regarding interruptions and changes in the game environment.

Maybe you have seen some bots or 'macros' which follow a fixed sequence of actions to perform an in-game task. The bot we will use here does not just follow a rigid series of steps but frequently looks at the current state of the game to decide the next action. This also means it can detect if it failed to perform a particular subtask, (for example, warping to the mining site) and try again. So it also does not matter if your ship is docked or in space when you start the bot.

Before going into the setup, a quick overview of this bot and what it does:

+ When the ore hold is not full, warps to an asteroid belt.
+ Mines from asteroids.
+ When the ore hold is full, warps and docks to a station to unload the ore into the item hangar. (It remembers the station in which it was last docked, and docks again at the same station.)
+ At least so far, does not use drones or any defence against rats. (Maybe we will add this later.)

If you haven't yet, follow the [guide on using a warp-to-0 autopilot bot](./how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md), because it covers the details of setting up and using an EVE Online bot:
https://github.com/Viir/bots/blob/master/guide/eve-online/how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md

When you have successfully used the warp-to-0 autopilot bot, you can continue here to upgrade to the mining bot.

Despite being quite robust, this mining bot is far from being as smart as a human. For example, its perception is more limited than ours, so we need to set up the game to make sure that the bot can see everything it needs to. Following is the list of setup instructions for the EVE Online client:

+ Enable `Run clients with 64 bit` in the EVE Online client settings.
+ Set the UI language to English.
+ In the Overview window, make asteroids visible and hide everything else.
+ Set the Overview window to sort objects in space by distance with the nearest entry at the top.
+ Activate a ship with an ore hold.
+ In the Inventory window, select the 'List' view.
+ Enable the info panel 'System info'. The bot uses this to warp to asteroid belts and stations.
+ Arrange windows not to occlude ship modules or info panels.
+ In the ship UI, disable 'Display Passive Modules' and disable 'Display Empty Slots'.
+ Set up the inventory window so that the 'Ore Hold' is always selected.
+ In the ship UI, arrange the mining modules to appear all in the upper row of modules. The bot activates all modules in the top row.

To start the mining bot, you use almost the same command as shown in the guide on the warp-to-0 autopilot bot. The only difference is that to start the mining bot, you supply this value for the `bot-source` parameter:

[https://github.com/Viir/bots/tree/1dd1b09b40f47c63dda38f71297872e0c708b612/implement/applications/eve-online/eve-online-mining-bot](https://github.com/Viir/bots/tree/1dd1b09b40f47c63dda38f71297872e0c708b612/implement/applications/eve-online/eve-online-mining-bot)

In case the bot does not work as expected, the first place to look is in the status message of the bot. Depending on what the bot is seeing and doing at the moment, it can display many different status messages.
For example, if you disable the location ('System info') info panel in the EVE Online client, the bot displays the following message:

> I cannot see the location info panel.

As soon as you enable this info panel again, the bot will also continue working.

The bot repeats the cycle of mining and unloading until you tell it to pause (`CTRL`+`ALT` keys) or stop it.

In case I forgot to add something here or you have any questions, don't hesitate to ask on the [BotEngine forum](https://forum.botengine.org/).

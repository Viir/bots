# EVE Online Mining Bot

For this guide, I picked a mining bot optimal for beginners, which means easy to set up and use. After several iterations in development, this bot has matured to be robust regarding interruptions and changes in the game environment.

Maybe you have seen some bots or 'macros' which follow a fixed sequence of actions to perform an in-game task. The bot we will use here does not just follow a rigid series of steps but frequently looks at the current state of the game to decide the next action. This also means it can detect if it failed to perform a particular subtask, (for example, warping to the mining site) and try again. So it also does not matter if your ship is docked or in space when you start the bot.

Before going into the setup, a quick overview of this bot and what it does:

+ When the ore hold is not full, warps to an asteroid belt.
+ Mines from asteroids.
+ When the ore hold is full, warps and docks to a station to unload the ore into the item hangar. (It remembers the station in which it was last docked, and docks again at the same station.)
+ Runs away if shield hitpoints drop too low (The default threshold is 50%).
+ Uses drones to defend against rats if available.
+ Displays statistics such as the total volume of unloaded ore, so that you can easily track performance.
+ Closes message boxes that could pop up sometimes during gameplay.

If you haven't yet, follow the [guide on using a warp-to-0 autopilot bot](./how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md), because it covers the details of setting up and using an EVE Online bot:
https://github.com/Viir/bots/blob/master/guide/eve-online/how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md

When you have successfully used the warp-to-0 autopilot bot, you can continue here to upgrade to the mining bot.

Despite being quite robust, this mining bot is far from being as smart as a human. For example, its perception is more limited than ours, so we need to set up the game to make sure that the bot can see everything it needs to. Following is the list of setup instructions for the EVE Online client:

+ Set the UI language to English.
+ In Overview window, make asteroids visible.
+ Set the Overview window to sort objects in space by distance with the nearest entry at the top.
+ Open one inventory window.
+ In the ship UI, arrange the modules:
    + Place all mining modules (to activate on targets) in the top row.
    + Place modules that should always be active in the middle row.
    + Hide passive modules by disabling the check-box `Display Passive Modules`.
+ If you want to use drones for defense against rats, place them in the drone bay, and open the 'Drones' window.

To start the mining bot, you use almost the same command as shown in the guide on the warp-to-0 autopilot bot. The only difference is that to start the mining bot, you supply a different bot source. This is the whole command to run the mining bot:

```cmd
botengine  run-bot  https://github.com/Viir/bots/tree/f509334861949dca1e061281a3ebb81dbc6adbdc/implement/applications/eve-online/eve-online-mining-bot
```

In case the bot does not work as expected, the first place to look is in the status message of the bot. Depending on what the bot is seeing and doing at the moment, it can display many different status messages.
For example, if you disable the location ('System info') info panel in the EVE Online client, the bot displays the following message:

> I cannot see the location info panel.

As soon as you enable this info panel again, the bot will also continue working.

The bot repeats the cycle of mining and unloading until you tell it to pause (`SHIFT` + `CTRL`+`ALT` keys) or stop it.

To give an overview of the performance of the bot, it displays statistics like this:

> Session performance: times unloaded: 13, volume unloaded / m³: 351706

If you want to learn how this bot or other apps for EVE Online are developed, have a look at the directory of development guides at https://to.botengine.org/guide/overview

In case I forgot to add something here or you have any questions, don't hesitate to ask on the [BotEngine forum](https://forum.botengine.org/).

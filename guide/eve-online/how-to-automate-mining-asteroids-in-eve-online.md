# EVE Online Mining Bot

For this guide, I picked a mining bot optimal for beginners, which means easy to set up and use. After several iterations in development, this bot has matured to be robust regarding interruptions and changes in the game environment.

Maybe you have seen some bots or 'macros' which follow a fixed sequence of actions to perform an in-game task. The bot we will use here does not just follow a rigid series of steps but frequently looks at the current state of the game to decide the next action. This also means it can detect if it failed to perform a particular subtask, (for example, warping to the mining site) and try again. So it also does not matter if your ship is docked or in space when you start the bot.

Before going into the setup, a quick overview of this bot and what it does:

+ When the ore hold is not full, warps to an asteroid belt.
+ Uses drones to defend against rats if available.
+ Mines from asteroids.
+ When the ore hold is full, warps and docks to a station to unload the ore into the item hangar. (It remembers the station in which it was last docked, and docks again at the same station.)
+ Runs away if shield hitpoints drop too low (The default threshold is 50%).
+ Displays statistics such as the total volume of unloaded ore, so that you can easily track performance.
+ Closes message boxes that could pop up sometimes during gameplay.

## Setting up the Game Client

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

## Starting the Mining Bot

To start the mining bot, download the script from https://catalog.botengine.org/98f087642be528715e4087c39c294fab4f42c4ad14ba150626a8491ac1a42447 and then run it.

In case the botengine program is not yet installed on your system, the script will redirect you to the installation guide at https://to.botengine.org/failed-run-bot-did-not-find-botengine-program

After completing the installation, run the script again to start the mining bot.

From here on, the bot works automatically. It detects the topmost game client window and starts working in that game client.

In case the bot does not work as expected, the first place to look is in the status message of the bot. Depending on what the bot is seeing and doing at the moment, it can display many different status messages.
For example, if you disable the location ('System info') info panel in the EVE Online client, the bot displays the following message:

> I cannot see the location info panel.

As soon as you enable this info panel again, the bot will also continue working.

The bot repeats the cycle of mining and unloading until you tell it to pause (`SHIFT` + `CTRL` + `ALT` keys) or stop it.

To give an overview of the performance of the bot, it displays statistics like this:

> Session performance: times unloaded: 13, volume unloaded / m³: 351706

If you want to learn how this bot or other apps for EVE Online are developed, have a look at the directory of development guides at https://to.botengine.org/guide/overview

In case I forgot to add something here or you have any questions, don't hesitate to ask on the [BotEngine forum](https://forum.botengine.org/).

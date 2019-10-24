# How to Automate Mining Asteroids in EVE Online

This guide walks you through the steps to set up an asteroid mining bot in EVE Online.

In this guide, I use a particular mining bot that is known to be easy to set up for beginners. You might find more powerfull or flexible mining bots on the bot catalog, but this one here is optimal for beginners.

If you haven't yet, follow the [guide on using a warp-to-0 autopilot bot](./how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md), because it covers the details of setting up and using an EVE Online bot:
https://github.com/Viir/bots/blob/master/guide/eve-online/how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md

When you have successfully used the warp-to-0 autopilot bot, you can continue here to upgrade to the mining bot.

Before starting this particular mining bot, set up the EVE Online client as follows:

+ Disable `Run clients with 64 bit` in the EVE Online client settings, as explained in the travel bot guide.
+ Set the UI language to English.
+ In the Overview window, make asteroids visible and hide everything else.
+ Set the Overview window to sort objects in space by distance with the nearest entry at the top.
+ Activate a ship with an ore hold.
+ In the Inventory window, select the 'List' view.
+ Enable the info panel 'System info'. The bot needs this to find your bookmarks or asteroid belts and stations.
+ Arrange windows not to occlude ship modules or info panels.
+ In the ship UI, disable 'Display Passive Modules' and disable 'Display Empty Slots'.
+ Set up the inventory window so that the 'Ore Hold' is always selected.
+ In the ship UI, arrange the mining modules to appear all in the upper row of modules. The bot activates all modules in the top row.
+  Create bookmark 'mining' for the mining site, for example, an asteroid belt.
+ Create bookmark 'unload' for the station to store the mined ore in.

To start the mining bot, you use almost the same command as for the travel bot. The only difference is that you supply this value for the `bot-source` parameter:

```text
https://github.com/Viir/bots/tree/cccdd729f42c752740b88b4e41e26161b9f8c434/implement/applications/eve-online/eve-online-mining-bot
```

In case the bot does not work as expected, the first place to look is in the status message of the bot. Depending on what the bot is seeing and doing at the moment, it can display many different status messages.

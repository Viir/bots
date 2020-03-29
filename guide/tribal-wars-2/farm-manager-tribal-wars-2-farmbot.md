# Farm Manager - Tribal Wars 2 Farmbot

This bot farms barbarian villages in Tribal Wars 2.
It automatically detects barbarian villages, available troops and configured army presets to attack.

## Features

### Easy to Configure

+ Automatically reads the required information from the game: Locations of farms, available units, army presets, current attacks per village, etc.
+ Use the in-game army presets to configure which villages should attack and which units to use.

### Efficient

+ Supports multiple army presets per village to make the best use of your troops.
+ Takes into account the limit of 50 attacks per village.
+ Fast enough to send 800 attacks per hour.
+ Option to avoid barbarian villages under a certain amount of points.

### Safe

+ Supports random breaks between farming cycles.
+ Uses a normal web browser to interact with the game server for maximum security.
+ Stops the farming when the configured time limit is met to avoid perpetual activity on your account.

## Starting the Farmbot

To start the farmbot, download the script from [https://botengine.blob.core.windows.net/blob-library/by-name/2020-03-25-run-app-00736DF1E9-tribal-wars-2-farmbot.bat](https://botengine.blob.core.windows.net/blob-library/by-name/2020-03-25-run-app-00736DF1E9-tribal-wars-2-farmbot.bat) and then run it.

In case the botengine program is not yet installed on your system, the script will redirect you to the installation guide at [https://to.botengine.org/failed-run-bot-did-not-find-botengine-program](https://to.botengine.org/failed-run-bot-did-not-find-botengine-program)

After completing the installation, run the script again to start the farmbot.
The first time you start the bot, it will download a web browser component. This can take some time, depending on your internet connection.

![Tribal Wars 2 Farmbot Starting](./image/2020-01-25.tribal-wars-2-farmbot-before-login.png)

When the browser download is finished, the bot opens a 'chromium' web browser window, which is a variant of googles chrome web browser. In the Windows taskbar, it appears with an icon that is a blueish version of the google chrome logo:

![Chromium Window Appears](./image/2020-01-25.tribal-wars-2-farmbot-chromium-taskbar.png)

In the browser window opened by the bot, navigate to the Tribal Wars 2 website and log in to your world so that you see your villages.
Then the browsers address bar will probably show an URL like https://es.tribalwars2.com/game.php?world=es77&character_id=12345

Now the bot will probably display a message like this:

> Found no army presets matching the filter 'farm'.

Or, in case your account has no army presets configured at all, it shows this message:

> Did not find any army presets. Maybe loading is not completed yet.

In any case, we need to configure at least one army preset before the bot can start farming.

### Configuring Army Presets

The bot only uses an army preset if it matches the following three criteria:

+ The preset name contains the string 'farm'.
+ The preset is enabled for the currently selected village.
+ The village has enough units available for the preset.

If multiple army presets match these criteria, it uses the first one by alphabetical order.

If no army preset matches this filter, it switches to the next village.

You can use the in-game user interface to configure an army preset and enable it for villages:

![Configuring Army Presets in-game](./image/2020-01-25.tribal-wars-2-farmbot-configure-army-preset.png)

Besides the army presets, no configuration is required.
The bot searches for barbarian villages and then attacks them using the matching presets. You can also see it jumping to the barbarian villages on the map.

In the console window, you can read about the number of sent attacks and what the bot is currently doing:

```text
[...]
Sent 129 attacks in this session, 129 in the current cycle.
Checked 1413 coordinates and found 364 villages, 129 of wich are barbarian villages.
Found 3 own villages.

Current activity:  
+ Currently selected village is 871 (482|523 'Segundo pueblo de skal'. Last update 6 s ago. 537 available units. 11 outgoing commands.)
++ Best matching army preset for this village is 'farm beta'.
+++ Farm at 567|524.
++++ Send attack using preset 'Farm 1'.
[...]
```

When all your villages are out of units or at the attack limit, the bot stops with this message:

> Finish session because I finished all 1 configured farm cycles.

## Configuration Settings

All settings are optional; you only need them in case the defaults don't fit your use-case.
You can adjust three settings:

+ 'number-of-farm-cycles' : Number of farm cycles before the bot stops. The default is only one (`1`) cycle.
+ 'break-duration' : Duration of breaks between farm cycles, in minutes. You can also specify a range like `60-120`. It will then pick a random value in this range.
+ 'farm-barb-min-points': Minimum points of barbarian villages to attack.

To use settings, run the bot using the Windows app called ['Command Prompt' (cmd.exe)](https://en.wikipedia.org/wiki/Cmd.exe). This app comes by default with any Windows 10 installation.

To run the bot with default settings, you would use this command:

```cmd
botengine  run-bot  "https://github.com/Viir/bots/tree/ed9cd75aa0e0c11090a2ce2af1d69b3ea3ca153f/implement/applications/tribal-wars-2/tribal-wars-2-farmbot"
```

![Command to start Tribal Wars 2 Farmbot without settings](./image/2020-03-29-run-bot-tribal-wars-2-without-settings-cmd.png)

To run the bot with different settings, expand that command by adding the `--app-settings` argument.
Here is an example of `app-settings` for three farm cycles with breaks of 20 to 40 minutes in between:

```text
--app-settings="number-of-farm-cycles = 3, break-duration = 20 - 40"
```

To apply these settings to the bot, add them into the `run-bot` command used to start the bot:

```cmd
botengine  run-bot  --app-settings="number-of-farm-cycles = 3, break-duration = 20 - 40"  "https://github.com/Viir/bots/tree/ed9cd75aa0e0c11090a2ce2af1d69b3ea3ca153f/implement/applications/tribal-wars-2/tribal-wars-2-farmbot"
```

![Command to start Tribal Wars 2 Farmbot with settings](./image/2020-03-29-run-bot-tribal-wars-2-with-settings-cmd.png)

When you have applied settings for multiple farm cycles, the bot displays this message during the breaks between farm cycles:

> Next farm cycle starts in 17 minutes. Last cycle completed 16 minutes ago. 

## Pricing and Online Bot Sessions

You can test the bot for free. When you want the bot to run more than 15 minutes per session, use an online-bot session as explained at [https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#online-bot-sessions](https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#online-bot-sessions)

Online bot sessions cost 2000 credits per hour. To add credits to your account, follow the instructions at [https://app.botengine.org/billing/add-credits](https://app.botengine.org/billing/add-credits)

For more about purchasing and using credits, see the guide at [https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837](https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837)

## Frequently Asked Questions

### How can I make the bot remember the locations of the barbarian villages?

To make it remember the farm locations, configure more farm cycles. The bot remembers all those coordinates within the same session, so it can reuse this knowledge, starting with the second farm cycle. It sends only one attack per target per farm cycle, so the remembering does not affect the first farm cycle. If you don't use any configuration, the bot only performs one farm cycle and then stops.

### How much time does this bot need to send all attacks on my account?

Sending one attack takes less than four seconds. The bot can cover 800 farms per hour. The first farm cycle per session is a special case: For the first cycle, it needs additional time to find the farm villages. The game limits us to 50 concurrent attacks per village, and the bot switches to the next village when the currently selected village hits that limit. One farm cycle is complete when all your villages are at the limit, either because of the attack limit or because no matching units are remaining.


## Getting Help

If you have any questions, the [BotEngine forum](https://forum.botengine.org) is a good place to learn more. You can also contact me at [support@botengine.org](mailto:support@botengine.org?subject=Tribal%20Wars%202%20Farmbot%20-%20your%20issue%20here)

When asking for help with the bot, include the complete text from the console window or a screenshot. Make sure screenshots are well readable. Don't try to insert a screenshot directly into the forum, as it will be compressed and unreadable. When posting on the forum, you can link screenshots hosted at other sites like Github or imgur.

# Running Bots on Multiple Game Clients

Do you want to use a bot with multiple game clients? There is no general limit to the number of game clients; supporting multiple clients depends on your bot's programming.
Many bots support multiple clients, but it is not always obvious how to set this up if you use a bot made by somebody else. However, many bots follow the same approach to multi-client support, so you can check if it also applies to the bot you are using.

Most bots use a variant of multi-client support with these traits:

+ One bot instance per game client instance.
+ Select the game client window on startup.
+ Default to select the topmost game client window.

These bullet points need some further explanation. Let's see what they mean in detail.

### One Bot Instance per Game Client Instance

You start a new instance of the bot for each game client you want to use. This approach has several implications. For example, it means that you can use different bots for each game client, and you can start, pause, and stop them at different times. It also means you can see the performance metrics for each instance individually.

### Select the Game Client Window on Startup

When the bot starts, it expects an instance of the game client already present. The bot selects a window to work on only at startup. It remembers the window's ID and keeps working on the same window for the rest of the session. Note that the bots need some time to startup and complete the window selection. When the bot reports what it sees in the game client or sends input, you know it has completed the window selection.

### Default to Select the Topmost Game Client Window

There are many windows open on the desktop, and there can be multiple instances of the game client. The default way to select the right one allows for using multiple game clients without any configuration. The bot uses a property of the window called 'Z-index' to sort them. The Z-index is tracked by the operating system and establishes an ordering of the windows, based on how far they are from the window with input focus, also called the 'topmost' window.
When you select a window for [input focus](https://en.wikipedia.org/wiki/Focus_(computing)), it becomes the topmost window and has the highest priority for the bot's selection. Focusing a window can be as simple as clicking on it. There are also keyboard commands to switch between windows, such as `Alt` + `Tab` in Microsoft Windows.

Some bots offer optional settings to limit the selection of the game client window. For example, some bots for the game EVE Online provide an app-setting to pick a pilot name. Such options reduce the dependency on maintaining the window order on startup.

## Process to Start Bots on Multiple Game Clients

When using a bot that follows the three choices above, this is the process to start your bots:

+ Focus the game client window to be used with bot instance A.
+ Start bot instance A and wait until the bot has selected the window.
+ Pause bot instance A.
+ Focus the game client window to be used with bot instance B.
+ Start bot instance B and wait until the bot has selected the window.
+ Unpause bot instance A.

The order in which you started the game clients is not relevant. It also does not matter if you had a different bot running on a game client window.

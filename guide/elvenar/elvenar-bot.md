# Elvenar Bot

This bot collects coins in the Elvenar game client window.
It locates the coins over residential buildings in the Elvenar window and then clicks on them to collect them 🪙

## Setup and starting the bot

If the BotLab client is not already installed on your machine, follow the guide at <https://to.botlab.org/guide/how-to-install-the-botlab-client>
The BotLab client is a tool for developing bots and also makes running bots easier with graphical user interfaces for configuration.

In the BotLab client, load the bot by entering the following link in the 'Select Bot' view:
<https://catalog.botlab.org/782cb0fcbfe7c58f>

There is a detailed walkthrough video on how to load and run a bot at <https://to.botlab.org/guide/video/how-to-run-a-bot-live>

Follow these steps to start a new bot session:

+ Load Elvenar in a web browser.
+ Ensure the product of the display 'scale' setting in Windows and the 'zoom' setting in the web browser is 125%. If the 'scale' in Windows settings is 100%, zoom the web browser tab to 125%. If the 'scale' in Windows settings is 125%, zoom the web browser tab to 100%.
+ Elvenar offers you five different zoom levels. Zoom to the middle level to ensure the bot will correctly recognize the icons in the game. (You can change zoom levels using the mouse wheel or via the looking glass icons in the settings menu)
+ Start the bot and immediately click on the web browser containing Elvenar.

From here on, the bot works automatically, periodically checking for and collecting coins.

> The bot picks the topmost window in the display order, the one in the front. This selection happens once when starting the bot. The bot then remembers the window address and continues working on the same window.
> To use this bot, bring the Elvenar game client window to the foreground after pressing the button to run the bot. When the bot displays the window title in the status text, it has completed the selection of the game window.

You can test this bot by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can quickly change its location within the window.

You can see the training data samples used to develop this bot at <https://github.com/Viir/bots/tree/71d857d01597a3dfa36c5724be79e85c44dfd3ae/implement/applications/elvenar/training-data>

## Getting Help

If you have any questions, the [BotLab forum](https://forum.botlab.org) is a good place to learn more. You can also contact me at [support@botlab.org](mailto:support@botlab.org?subject=Tribal%20Wars%202%20Farmbot%20-%20your%20issue%20here)

When asking for help with the bot, include one of these two artifacts to help us see what happened on your setup:

+ The summary from the `Report Problem or Share Session` dialog in the play session interface. Either upload the saved JSON file or copy the text in that file. To reach this dialog, use the buttons labeled `Get Help With This Bot Session` and then `Report Problem or Share Session`.
+ The play session recording archive from the session view in DevTools.

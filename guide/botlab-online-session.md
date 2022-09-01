# BotLab Online Session

When starting a play session with a bot, you can choose to start an online session. Online sessions provide several advantages over offline sessions:

+ Monitoring from other devices: No need to go to your PC to check the status of your bot. You can use your smartphone or any other device with a web browser to see the status of your bot.
+ Organize and keep track of your operations and experiments: Easily see which bots you already tested and when you used them the last time.
+ Longer running time: Run a bot continuously in one session for up to 72 hours.

To see a list of your most recent online sessions, log in at https://reactor.botlab.org

Below is a screenshot of the website to view your online sessions and monitor your bots:
![viewing details of an online play session with a bot](./image/2021-11-30-botlab-reactor-online-session-detail.png)

Online sessions cost 2000 credits per hour. When you log in to your account for the first time, you automatically get 1000 credits. Using these initial credits balance, you can test the online session feature without paying anything (Creating an account is free).
When you have used up the credits on your account, you can add more following the instructions at [https://reactor.botlab.org/billing/add-credits](https://reactor.botlab.org/billing/add-credits)

For more about purchasing and using credits, see the guide at https://forum.botlab.org/t/purchasing-and-using-botlab-credits-frequently-asked-questions-faq/837

### Starting an Online Session

To start a bot in an online session, use the configuration interface on the bots' catalog entry.
Enable the checkbox labeled `Start bot in online session` as shown in this screenshot:

![configure script for online session](./image/2021-11-30-botlab-catalog-configure-online-session.png)

Then use the button "Download script with this command line to run the bot". The script file you get here starts the bot in an online session.

When you start a configuration for an online session, you might get this prompt from the botlab client:

![botlab client prompt for online session key](./image/2021-11-30-botlab-client-enter-online-session-key.png)

Here you need to enter your online session key to continue.

To get your key, go to https://reactor.botlab.org and log in to your account. After logging in, you see a section titled `Online play session keys`. In this section, there is an entry for a key, containing a button labeled `Show key`. Clicking this button reveals your key. Please don't share this key with anyone, and don't post it on the forum.

![Web UI displaying online session key](./image/2021-11-30-botlab-reactor-show-online-session-key.png)

Copy the key from the web page and paste it into the botlab console window. Press the enter key to complete the input. BotLab then checks the key and continues to start the bot in an online session.

The BotLab client also stores the entered key in the Windows user account, so you don't have to enter it the next time you start an online session.

After starting an online session, you can also see it at https://reactor.botlab.org under `Most recent play sessions`:

![List of most recent online sessions](./image/2021-11-30-botlab-reactor-dashboard-recent-sessions.png)


Clicking on the session ID brings you to the details view of the session, where you can also see the status reported by the bot.

The sessions under `Most recent play sessions` are still available after stopping the BotLab client, so you can continue to view details of past sessions.

## Getting Help

If you have any questions, the [BotLab forum](https://forum.botlab.org) is a good place to learn more.

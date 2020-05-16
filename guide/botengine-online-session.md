# BotEngine Online Sessions

When running a botengine app, you can choose to start it in an online session. Online sessions provide several advantages over offline sessions:

+ Monitoring from other devices: No need to go to your PC to check the status of your app. You can use your smartphone or any other device with a web browser to see the status of your app.
+ Organize and keep track of your operations and experiments: Easily see which apps you already tested and when you used them the last time.
+ Longer running time: Run an app continuously in one session for up to 72 hours.

To see a list of your most recent online sessions, log in at https://reactor.botengine.org

Below is a screenshot of the website you can use to view your online sessions and monitor your apps:
![monitor your apps using online sessions](./image/2019-12-11.online-bot-session.png)

Online sessions cost 2000 credits per hour. To add credits to your account, follow the instructions at [https://reactor.botengine.org/billing/add-credits](https://reactor.botengine.org/billing/add-credits)

For more about purchasing and using credits, see the guide at [https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837](https://forum.botengine.org/t/purchasing-and-using-botengine-credits-frequently-asked-questions-faq/837)

### Starting an Online Session

In case you use the Command Prompt or PowerShell, you can start an online session by adding the `--online-session` option on the `botengine run` command. Here is an example:
```cmd
botengine  run  --online-session  "https://github.com/Viir/bots/tree/652ed9fc83aa3f04cb21c1cbf28911201bd53925/implement/templates/remember-app-settings"
```

If you don't use the Command Prompt, use the app configuration interface on the catalog: Enable the checkbox labeled "Start in online session" as shown in this screenshot:

![configure script for online session](./image/2020-05-16-configure-script-for-online-session.png)

Then use the button "Download script with this command line to run the app". The script file you get here starts the app in an online session.

If you have not set up your system for online sessions, the engine then stops with this error:

```text
I ran into a problem: I was started with a configuration to use an online session ('--online-session' option), but I did not find a stored default online session key. Use the 'online-session-key  store-default-key' command to store a key. For a detailed guide, see https://to.botengine.org/failed-run-online-session-did-not-find-key
```

To get your key, go to https://reactor.botengine.org and log in to your account. After logging in, you see a section titled `Online session keys`. In this section, there is an entry for a key, containing a button labeled `Show key`. Clicking this button reveals your key. Please don't share this key with anyone, and don't post it on the forum.

Besides the key itself, clicking the `Show key` button also reveals the complete command you can use to store the key on your system:

![Web UI displaying online session key and a command to store the key](./image/2020-03-18-botengine-web-ui-online-session-keys.png)

Copy that command from the web page into the Windows Command Prompt and execute it.

The program then confirms:

```text
I stored this as the default online session key. I will use this key when running an app in an online session.
```

Now you can use the `botengine run` command again to start the online session.

After the online session is started, you can also see it at https://reactor.botengine.org/ under `Most recent online sessions`:

![List of most recent online sessions](./image/2020-04-20-botengine-reactor-recent-online-sessions.png)


Clicking on the session ID brings you to the details view of the session, where you can also see the status reported by the app.

The sessions under `Most recent online sessions` are still available after stopping the Windows app, so you can continue to view details of past sessions.

## Getting Help

If you have any questions, the [BotEngine forum](https://forum.botengine.org) is a good place to learn more.

# Testing a Bot Using Simulated Environments

Simulated environments are a great time saver for testing and debugging a bot. A simulated environment lets us test a complete bot without starting a game client.

When we run a bot for productive use, we want it to interface with a real game client. For the bot to be useful, it needs to affect the game world or read and forward information from the game. This mode is what we call a 'live environment'.

During bot development, our goals are different. We are confronted with many possible bot programs and want to test and compare those. There are various ways to find a bot program. We could write it ourselves or copy it from some website. But no matter how we find a bot program, we want to test it before letting it run unattended for hours. We want to check if it works for our scenarios. We often want to run different bot programs in the same scenario to compare their fitness. Setting up a game client for each test would be a distraction and would slow us down.

But even after the setup, testing a new bot on a real game client can still require further work. If we let a new, previously untested bot run unattended, it might put in-game resources at risk.

We use simulated environments to test and compare bots faster and without risk. Simulated environments allow us to test different bots in the same situation without using a live game client.

How does this work? Remember that all information that a bot receives comes through events. This also implies that the sequence of events in a session determines all outputs of a bot.

In the case of productive use, the events encode information from the user (bot-settings) and the game client (e.g. screenshots). When we use a simulated environment, another program generates the events that the bot receives.

## Simulation from Session Replay

The simplest type of simulation is replaying a session. This is a kind of off-policy simulation, which means the bot's output is not fed back into the simulation.

To create a simulation by session replay, we only need the recording of a session as input. Here we can use a session archive as we get it from the [export function in DevTools](https://to.botlab.org/guide/how-to-report-an-issue-with-a-bot-or-request-a-new-feature).

We can start a session replay by using the `botlab  play` command with the `--environment` option. We use the `--environment` to point to the file containing the session recording archive. After the `--environment` option, we add the path to the bot program code, the same way as with the `botlab  play` command.
Here is an example of the final command as we can run it in the Windows Command Prompt:

```
botlab  play  --environment="C:\Users\John\Downloads\session-2020-08-04T06-44-41-3bfe2b.zip"  https://github.com/Viir/bots/tree/e733ebde1f86b878dd29ae9cb90e6a12d007c1f9/implement/applications/eve-online/eve-online-combat-anomaly-bot
```

![command to simulate-run in Command Prompt](./image/2020-08-08-simulate-run-cmd.png)

When running this command, the output looks similar to when running a bot live. The same way as when running live, we see a session ID that we can use later to find the details of this simulated session again. One difference you can see is that the BotLab client displays the number of remaining events to be processed:

![BotLab displays progress during simulate-run](./image/2020-08-08-simulate-run-progress.png)

The simulation runs faster than the original session because it never has to wait for another process, and the passing of time is encoded in the bot event data.

When the simulation is complete, we find the recording in the list of sessions shown in DevTools. (You might have to restart DevTools to make a new session visible). By selecting the session recording in DevTools, you can inspect it the same way as any other session recording. The guide on observing and inspecting a bot explains how this works: https://to.botlab.org/guide/observing-and-inspecting-a-bot

### Replacing Bot-Settings in a Session Replay

When developing a new feature for a bot, we sometimes want to add a new setting to let users configure that feature. But how do we test this with a session replay? The session replay contains an event with the bot-settings string, so the replay determines the settings. What we want in this case is not an exact replay but one with modified events.

Use the `--bot-settings` option to override these bot settings. BotLab then replaces the bot-settings string with the new value for each bot-settings event in the loaded session before giving it to the bot.

## Related Resources

You can see an example of simulations in action in this video: https://vimeo.com/user132945801/making-an-eve-online-bot-see-anomalies-and-other-pilots#t=583s

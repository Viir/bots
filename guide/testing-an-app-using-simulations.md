# Testing an App Using Simulations

Simulations are a great time saver when it comes to testing and debugging an app. Simulations let us test a complete app without the need to start a game client.

To understand how simulations work, it is helpful to remember that all information that an app receives comes through events. This also implies that the sequence of events in a session determines all outputs of an app.

When we run an app for productive use, we want it to read from a real game client. In this case, the events encode information from the user (app-settings) and the game client. To avoid the work to set up our testing scenario in a live game client, simulations let us generate the event data in an easier way.

## Simulation from Session Replay

The simplest type of simulation is replaying a session. This is a kind of off-policy simulation, which means the app's output is not fed back into the simulation.

To create a simulation by session replay, we only need the recording of a session as input. Here we can use a session archive as we get it from the export function in DevTools.

We can start a session replay by using the `botengine  simulate-run` command with the `--replay-session` option. We use the `--replay-session` to point to the file containing the session recording archive. After the `--replay-session` option, we add the path to the app program code, the same way as with the `botengine  run` command.
Here is an example of the final command as we can run it in the Windows Command Prompt:

```
botengine  simulate-run  --replay-session="C:\Users\John\Downloads\session-2020-08-04T06-44-41-3bfe2b.zip"  https://github.com/Viir/bots/tree/1ab3cf1de8bfbedd22641f1d9918f0188894e013/implement/applications/eve-online/eve-online-combat-anomaly-bot
```

![command to simulate-run in Command Prompt](./image/2020-08-08-simulate-run-cmd.png)

When running this command, the output looks similar to when running an app live. The same way as when running an app live, we see a session ID that we can use later to find the details of this simulated session again. One difference you can see is that the engine displays the number of remaining events to be processed:

![engine displays progress during simulate-run](./image/2020-08-08-simulate-run-progress.png)

The simulation runs faster than the original session because it never has to wait for another process, and the passing of time is encoded in the app event data.

When the simulation is complete, we find the recording in the list of sessions shown in DevTools. (You might have to restart DevTools to make new session recordings visible). By selecting the session recording in DevTools, you can inspect it the same way as any other session recording. The guide on observing and inspecting an app explains how this works: https://to.botengine.org/guide/observing-and-inspecting-an-app


# Observing and Inspecting an App

Observations are the basis for improving an app.

One way of observing an app is to watch the botengine window and the game client on a screen. That is what you see anyway when running a bot. The engine window displays the status text from the app and thus helps with the inspection.

But this mode of observing an app is limiting in two ways.

It is limiting because it requires us to process everything in real-time. But in most cases, information flows too fast for us to keep up. Things happen so quickly that we cannot even read all the status messages. We could pause the app to have more time to read, but that leads to other problems since every break distorts the app's perception of the environment.

The second limitation is the merely superficial representation we find in this mode. To understand how a bot works, we need to make visible more than just the status texts. When investigating an app's behavior, we want to follow the data-flow backward. Seeing the status text and the effects emitted by the app in response to an event is only the first step in this process.

While this simple way of observing is severely limiting, it can work. We can offset the incomplete observations with more experiments. Ten hours of tests could save us one hour of careful inspection.

But we don't have to make it so difficult for ourselves. These problems with observability are not new, and there are tools to help us overcome these limitations.

## DevTools and Time Travel

The first step to enable observability is to decouple the observation time from the app running time. Our development tools allow us to go back to any point in time and see everything as it was back then.

Let's see how this works in practice.
Before we can travel back in time, we need to run a botengine app (or get a session archive from somewhere else, as we will see later). You can use any of the example apps in the bots repository, miner, autopilot, or anomaly bot. When we run a bot, the engine saves a recording to disk by default.
After running an app, we can use the `botengine  devtools` command to open the development tools:

![Opening DevTools from the command-line](./image/2020-07-18-open-botengine-devtools.png)

Running this command opens a web browser window. We continue in the web browser, no need to look at the console window anymore.

![DevTools - choose a session to inspect](./image/2020-07-18-botengine-devtools-choose-session.png)

On that web page, we find a list of recent app-sessions, the last one at the top.

Clicking on one of the sessions' names brings us into the view of this particular session:

![DevTools - initial view of a session](./image/2020-07-18-botengine-devtools-session-init.png)

In the session view, we have a timeline of events in that session. Clicking on an event in the timeline opens the details for this event. The event details also contain the app's response to this event.

![DevTools - view of an app session event](./image/2020-07-18-botengine-devtools-session-selected-event.png)

Besides the complete response, we also see the status text, which is part of the response but repeated in a dedicated section for better readability.

Some events inform the app about the completion of reading from the game client. For these events, the event details also show a visualization of the reading. For EVE Online, the common way to read from the game client is using memory reading. That is why we don't see a screenshot here, but a (limited) visualization.

![DevTools - view of an app session event](./image/2020-07-18-botengine-devtools-session-selected-event-eve-online.png)

This visualization shows the display regions of UI elements and some of the display texts. Using the button "Download reading as JSON file", we can export this memory reading for further examination. The inspection tools found in the alternate UI for EVE Online help us with that. You can find those tools at https://botengine.blob.core.windows.net/blob-library/by-name/2020-08-11-eve-online-alternate-ui.html
(If you want to enable the Elm inspector ('debugger') tool too, you can use the variant at https://botengine.blob.core.windows.net/blob-library/by-name/2020-08-11-eve-online-alternate-ui-with-inspector.html)

## Sharing Observations

To collaborate on the development of a bot, we often need to communicate scenarios, situations in which we want the bot to work. One way to describe such a scenario is to use the recording of an actual session as it happened. To export any session displayed in the DevTools, use the "Download session archive" button. This gets you a zip-archive that you can then share with other people. Now you can get help from other developers for your exact situation, no matter if the solution requires a change in program code or just different app-settings.

To import such a session archive in DevTools, use the `botengine  devtools` command with the path to the zip-archive as an additional argument:

![Opening DevTools from the command-line](./image/2020-07-18-open-botengine-devtools-additional-source.png)

When you start DevTools this way, the session from the specified path will show up at the top of the list of sessions in the DevTools UI:

![DevTools - choose a session to inspect](./image/2020-07-18-botengine-devtools-choose-session-additional-source.png)


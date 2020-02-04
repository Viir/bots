# Developing Bots for EVE Online

Do you want to learn how to build a bot or intel tool for EVE Online or customize an existing one? This guide explains the process I use to make these apps.

In part, this is a summary of my ~~failings~~ learnings from development projects. But most importantly, this guide lives from and evolves with your questions, so thank you for the feedback!

Wondering what outcome to expect? Two examples are the [mining bot](https://github.com/Viir/bots/blob/master/guide/eve-online/how-to-automate-mining-asteroids-in-eve-online.md) and [warp-to-0 autopilot](https://github.com/Viir/bots/blob/master/guide/eve-online/how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md).

## Scope and Overall Direction

My way of working is just one out of many, reflecting the kinds of projects I work on and my preferences. Important to me are simplicity, sustainability, and robustness. That is why I select methods that are easy to explain and have a low maintenance effort.

For those who already have some experience in software development, I compiled the following overview of my technical decisions:

+ I do not write into the game client's memory or use injection. These techniques can allow for more direct control of the game. A downside of these methods is they enable CCP to detect the presence of the foreign program. Another reason I don't use injection is the more complex concept makes it harder to learn and maintain implementations. For my projects, I stay close to the user interface and control the game by sending mouse and keyboard input.

+ To get information about the game state and user interface, I use memory reading. Memory reading means reading directly from the memory of the game client process. So this guide does not cover the approach using image processing (sometimes called 'OCR') on screenshots. The implementation of memory reading comes from the Sanderling project; check out the [Sanderling repository](https://github.com/Arcitectus/Sanderling) to learn more about this part.

+ If I would make only a simple bot or even just a macro, I could as well use a programming language like C# or Python. I am using the Elm programming language because it is simpler to learn and works better for larger projects and AI programming. Especially the time-travel debugging is useful when working on bots.

+ One thing I learned from answering bot developer's questions is this: You want to make it easy for people to communicate what bot code they used and in which environment. If a bot does not work as expected, understanding the cause requires not only having the bot code but also knowing the scenario the bot was used in. The data a bot reads from its environment is the basis for its decisions, so I favor methods that make it easy to collect, organize, and share this data.

## The Simplest Custom Bot

In this section, we will follow the fastest way to your custom bot.
First, let's look at an EVE Online bot from the examples. Run this autopilot bot:

```cmd
botengine  run-bot  "https://github.com/Viir/bots/tree/c0a858667e1f366501ac09079b4ac0ad83bc60f4/implement/applications/eve-online/eve-online-warp-to-0-autopilot"
```

If you are not yet familiar with this method of running a bot, read that guide first: [./how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md](./how-to-automate-traveling-in-eve-online-using-a-warp-to-0-autopilot.md)

The `botengine run-bot` command loads the bot code from the given address to run it on your system. Before running this bot, you need to start an EVE Online client, no need to go beyond character selection.

When the bot has started, it will display this message:

> I see no route in the info panel. I will start when a route is set.

That is unless you have set a route in the autopilot.

To customize this bot, we change the bot code. The bot code is made up of the files behind the address we gave to the botengine program.
To edit the bot code files, we download them first. Use this link to download all the files packaged in a zip-archive: https://github.com/Viir/bots/archive/183be242cd434e8282d7b4fb36ec6bbbf0f58c8a.zip

Extract the downloaded zip-archive, and you will find the same subdirectory we used in the command to run the bot: `implement\applications\eve-online\eve-online-warp-to-0-autopilot`.

Now you can use the `botengine run-bot` command on this directory as well:

```cmd
botengine  run-bot  "C:\Users\John\Downloads\bots-183be242cd434e8282d7b4fb36ec6bbbf0f58c8a\implement\applications\eve-online\eve-online-warp-to-0-autopilot"
```

Running this command gives you the same bot with the same behavior because the bot code files are still the same. You can also see that the bot ID displayed in the console window is `16BA890853...` for both commands since the bot ID only depends on the bot code files.

To change the bot code, open the file `Bot.elm` in this directory in a text editor. For now, the Windows Notepad app is sufficient as an editor.

On [line 86](https://github.com/Viir/bots/blob/c0a858667e1f366501ac09079b4ac0ad83bc60f4/implement/applications/eve-online/eve-online-warp-to-0-autopilot/src/Bot.elm#L86), you find the text that we saw in the bots status message earlier, enclosed in double-quotes:

![EVE Online autopilot bot code in Notepad](./image/2020-01-26.eve-online-autopilot-bot-code-in-notepad.png)

Replace that text between the double-quotes with another text:

```Elm
botRequestsFromGameClientState : ParsedUserInterface -> ( List BotRequest, String )
botRequestsFromGameClientState parsedUserInterface =
    case parsedUserInterface |> infoPanelRouteFirstMarkerFromParsedUserInterface of
        Nothing ->
            ( []
            , "Hello World!"
            )
```

When running the bot again from the local directory, you will see your change reflected in the status message in the console window.

### Getting Faster

Now you could generate random sequences of program text and test which ones are more useful. If you do this long enough, you will discover one that is more useful than anything anyone has ever found before.
But the number of possible combinations is too large to proceed in such a simple way. We need a way to discard the useless combinations faster.
In the remainder of this guide, I show how to speed up this process of discovering and identifying useful combinations.

## Setting up the Programming Tools

This section introduces a setup to help us:

+ Understand a program: Syntax highlighting helps with reading. Navigation becomes easier with the ability to jump to definitions and find references.
+ Check our bot code for problems: Static analysis detects errors after typing and before running a bot.

To achieve this, we combine the following tools:

+ Elm command line program
+ Visual Studio Code
+ elmtooling.elm-ls-vscode

The following subsections explain in detail how to set up these tools.

To test and verify that the setup works, you need the source files of a bot on your system. You can use the files from https://github.com/Viir/bots/tree/c0a858667e1f366501ac09079b4ac0ad83bc60f4/implement/applications/eve-online/eve-online-warp-to-0-autopilot for this purpose.

### Elm command line program

The Elm command line program understands the [programming language](https://elm-lang.org/blog/the-perfect-bug-report) we use and [helps us](https://elm-lang.org/blog/compilers-as-assistants) find problems in the code we write.

Download the file from https://github.com/elm/compiler/releases/download/0.19.1/binary-for-windows-64-bit.gz

Extract the `binary-for-windows-64-bit.gz` file; this will get you a file named `binary-for-windows-64-bit`. Rename this to `elm.exe`, so the system will recognize it as an executable file. If you don't know how to extract `.gz` files, [7zip](https://www.7-zip.org) can do that.

Next, we perform a small test to verify the elm.exe program works on the bot code as intended. Since `elm.exe` is a command line program, we start it from the Windows Command Prompt (cmd.exe).
Before starting the elm.exe, you need to navigate to the bot code directory containing the `elm.json` file. You can use the `cd` command in the Command Prompt to switch to this directory, with a command like this:
```cmd
cd "C:\Users\John\Downloads\bots\implement\applications\bot\eve-online\eve-online-warp-to-0-autopilot"
```

Now you can use elm.exe on the bot code files with a command like the following:
```
"C:\Users\John\Downloads\binary-for-windows-64-bit\elm.exe" make src/Main.elm
```
If everything works so far, the elm.exe will write an output which ends like the following:
```
Success! Compiled 1 module.

    Main ---> index.html
```
That number of modules it mentions can vary;

To see the detection of errors in action, we can now make some destructive change to the `Bot.elm` file. For example, simulate a typing mistake, on [line 90](https://github.com/Viir/bots/blob/c0a858667e1f366501ac09079b4ac0ad83bc60f4/implement/applications/eve-online/eve-online-warp-to-0-autopilot/src/Bot.elm#L90), replace `shipUI` with `shipUi`.
After saving the changed file, invoke Elm with the same command again. Now we get a different output, informing us about a problem in the code:
![Elm compilation detected a problem in the bot code](./../image/2020-01-20.elm-detected-problem.png)

For development, we don't need to use the Elm program directly, but other tools depend on it. The tools we set up next automate the process of starting the Elm program and presenting the results inside a code editor.

### Visual Studio Code

Visual Studio Code is a software development tool from Microsoft, which also contains a code editor. This is not the same as 'Visual Studio', a commercial product from Microsoft. Visual Studio Code is free and open-source, and often abbreviated as 'VSCode' to better distinguish it from Visual Studio. To set it up, use the installer from https://code.visualstudio.com/download

### elmtooling.elm-ls-vscode

[elmtooling.elm-ls-vscode](https://marketplace.visualstudio.com/items?itemName=Elmtooling.elm-ls-vscode) is an extension for VSCode. It has multiple features to help with development in Elm programs such as our bots. An important one is the display of error messages inside the code editor. A more obvious feature is the syntax coloring in Elm files, as you will soon see.

To install this extension, open VSCode and open the 'Extensions' section (`Ctrl + Shift + X`).
Type 'elm' in the search box, and you will see the `Elm` extension as shown in the screenshot below:
![Elm extension installation in Visual Studio Code](./../image/2020-01-20.vscode-elm-extension-install.png)

Use the `Install` button to install this extension in VSCode.

Before this extension can work correctly, we need to tell it where to find the Elm program. Open the Visual Studio Code settings, using the menu entries `File` > `Preferences` > `Settings`.
In the settings interface, select the `Elm configuration` entry under `Extensions` in the tree on the left. Then you will see diverse settings for the elm extension on the right, as shown in the screenshot below. Scroll down to the `Elm Path` section and enter the file path to the elm.exe we downloaded earlier into the textbox. The screenshot below shows how this looks like:

![Elm extension settings in Visual Studio Code](./../image/2020-01-20.vscode-elm-extension-settings.png)

VSCode automatically saves this setting and remembers it the next time you open the program.

To use VSCode with Elm, open it with the directory containing the `elm.json` file as the working directory. Otherwise, the Elm functionality will not work.
A convenient way to do this is using the Windows Explorer context menu entry `Open with Code` on the bot directory, as shown in the screenshot below:

![Open a directory in Visual Studio Code from the Windows Explorer](./../image/vscode-open-directory-from-explorer.png)

Now we can test if our setup works correctly. In VSCode, open the `Bot.elm` file and make the same code change as done earlier to provoke an error message from Elm.
When you save the file (`Ctrl + S`), the VSCode extension starts Elm in the background to check the code. On the first time, it can take longer as required packages are downloaded. But usually, Elm should complete the check in a second. If the code is ok, you will not see any change. If there is a problem, this is displayed in multiple places, as you can see in the screenshot below:

+ In the file tree view, coloring files containing errors in red.
+ On the scroll bar in an open file. You can see this as a red dot in the screenshot. This indicator helps to scroll to interesting locations in large files quickly.
+ When the offending portion of the code is visible in an editor viewport, the error is pointed out with a red squiggly underline.

![Visual Studio Code displays diagnostics from Elm](./../image/2020-01-20.vscode-elm-display-error.png)

When you hover the mouse cursor over the highlighted text, a popup window shows more details. Here you find the message we get from Elm:

![Visual Studio Code displays diagnostics from Elm - details on hover](./../image/2020-01-20.vscode-elm-display-error-hover.png)

## Bot Code

In the previous section, we already changed the code in the `Bot.elm` file. This section explains how this file is structured, so we better understand what we are doing in there.

### Entry Point - `processEvent`

Each time an event happens, the framework calls the function [`processEvent`](https://github.com/Viir/bots/blob/c0a858667e1f366501ac09079b4ac0ad83bc60f4/implement/applications/eve-online/eve-online-warp-to-0-autopilot/src/Bot.elm#L48-L50). Because of this unique role, this function is sometimes also referred to as 'entry point'.

Let's look at how this function is implemented:
```Elm
processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.BotFramework.processEvent processEveOnlineBotEvent
```

This function delegates the interesting part to the function `processEveOnlineBotEvent`.

Let's look at the type signature of `processEveOnlineBotEvent`, the first lines of the function's source code:
```Elm
processEveOnlineBotEvent :
    BotEventAtTime
    -> BotState
    -> { newState : BotState, requests : List BotRequest, millisecondsToNextMemoryReading : Int, statusDescriptionText : String }
```

I will quickly break down the Elm syntax here: The part after the last arrow (`->`) is the return type. It describes the shape of values returned by the bot to the framework. The part between the colon (`:`) and the return type is the list of parameters. So we have two parameters, one of type `BotEventAtTime` and one of type `BotState`.

Let's have a closer look at the three different types here:

+ `BotEventAtTime`: This describes an event that happens during the operation of the bot. All information the bot ever receives is coming through the values given with this first parameter.
+ `BotState`: The `BotState` type is specific to the bot. With this type, we describe what the bot remembers between events. When the framework informs the bot about a new event, it also passes the `BotState` value which the bot returned after processing the previous event (The `newState` field in the return type). But what if this is the first event? Then there is no previous event? In this case, the framework takes the value from the function `initState`.

## Programming Language

#### Custom Types

Custom types are also called tagged union types or algebraic data types. In the documentation about Elm, the term 'Custom Type' seems to be more popular.

Let's look at how a custom type with a type parameter can be used to compose more specific types. I will take a popular example of such a type. This one is often used to describe what can be seen on the screen.

```Elm
type MaybeVisible feature
    = CanNotSeeIt
    | CanSee feature
```

In this type definition, we have a type parameter called `feature`. We can instantiate the `MaybeVisible` type by specifying what to use as `feature`. For example, we can use the type `Bool` as the `feature`:

```Elm
type alias MaybeVisibleBool =
    MaybeVisible Bool
```

The type `MaybeVisible Bool` can have three different values:

+ `CanNotSeeIt`
+ `CanSee True`
+ `CanSee False`

In the larger context, this combination could be used as follows:
```Elm
type alias EveOnlineVision =
    { shipOreHoldIsFull : MaybeVisible Bool
    }


describeWhatWeSee : EveOnlineVision -> String
describeWhatWeSee vision =
    case vision.shipOreHoldIsFull of
        CanNotSeeIt ->
            "I can not see if the ship's ore hold is full. Do we need to change the setup?"

        CanSee True ->
            "The ship's ore hold is full."

        CanSee False ->
            "The ship's ore hold is not full."
```

----

Any questions? The [BotEngine forum](https://forum.botengine.org) is the place to meet other developers and get help.

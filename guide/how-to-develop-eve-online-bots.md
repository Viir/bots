# How to Develop EVE Online Bots

This is a guide for beginners on how to develop EVE Online bots. You don't need prior experience in programming or software development, as I explain the process and tools from the ground up.
There is a separate guide on how to run EVE Online bots, read that first, as this guide assumes you already know how to load, start, and operate a bot. You can find that guide at [./how-to-use-eve-online-bots.md](./how-to-use-eve-online-bots.md).

This guide goes beyond just running and configuring bots. The tools I show here give you the power to automate anything in EVE Online. I will also summarize what I learned during bot development projects like the EVE Online mission running and anomaly ratting bots, or the Tribal Wars 2 farmbot. The goal is to present the methods and approaches which make the development process efficient and a pleasant experience.

## Setting up the Programming Tools

The goal of this section is to enable you to edit a bot and quickly find possible problems in the code.
To achieve this, we combine the following tools:

+ Elm command line program
+ Visual Studio Code
+ vscode-elm

The following subsections explain in detail how to set up these tools.

To test and verify that the setup works, you need the source files of a bot on your system. You can use the files from https://github.com/Viir/bots/tree/de00799cd5edf771f210c8265d249f1380bd6382/implement/bot/eve-online/eve-online-warp-to-0-autopilot for this purpose.

### Elm command line program

The Elm command line program understands the [programming language](https://elm-lang.org/blog/the-perfect-bug-report) we use and [helps us](https://elm-lang.org/blog/compilers-as-assistants) find problems in the code we write.

Download the file from https://github.com/elm/compiler/releases/download/0.19.0/binaries-for-windows.tar.gz

Extract the `binaries-for-windows.tar.gz` file to get the `elm.exe` file out of this archive. If you don't know how to extract `.tar.gz` files, [7zip](https://www.7-zip.org) can do that.

Next, we perform a small test to verify the elm.exe program works on the bot code as intended. Since `elm.exe` is a command line program, we start it from the Windows Command Prompt (cmd.exe).
Before starting the elm.exe, you need to navigate to the bot code directory containing the `elm.json` file. You can use the `cd` command in the Command Prompt to switch to this directory, with a command like this:
```cmd
cd "C:\Users\John\Downloads\bots\implement\bot\eve-online\eve-online-warp-to-0-autopilot"
```

Now you can use elm.exe on the bot code files with a command like the following:
```
C:\path-to-elm\binaries-for-windows\elm.exe make src/Main.elm
```
If everything works so far, the elm.exe will write an output which ends with a line like the following:
```
Success! Compiled 3 modules.
```
That number of modules it mentions can vary; it should be at least one.

To see the detection of errors in action, we can now make some destructive change to the `Main.elm` file. For example, simulate a typing mistake, on line 99, replace `shipUi` with `shipui`.
If after this change we invoke Elm with the same command again, we now get a different output, informing us about a problem in the code:
```
Detected errors in 1 module.
-- NAMING ERROR --------------------------------------------------- src/Main.elm

I cannot find a `shipui` variable:

99|                     if shipui |> isShipWarpingOrJumping then
                           ^^^^^^
These names seem close though:

    shipUi
    pi
    sin
    asin

Hint: Read <https://elm-lang.org/0.19.0/imports> to see how `import`
declarations work in Elm.
```

For development, we don't need to use the Elm program directly, but other tools depend on it. The tools we set up next automate the process of starting the Elm program and presenting the results inside a code editor.

### Visual Studio Code

Visual Studio Code is a software development tool from Microsoft, which also contains a code editor. This is not the same as 'Visual Studio', a commercial product from Microsoft. Visual Studio Code is abbreviated as 'VSCode' throughout this guide. To set it up, use the installer from https://code.visualstudio.com/download

### vscode-elm

[vscode-elm](https://marketplace.visualstudio.com/items?itemName=sbrink.elm) is an extension for VSCode. It has multiple features to help with development in Elm programs such as our bots. An important one is the display of error messages inside the code editor. Another useful feature is completion suggestions to help us figure out what to type where. A more obvious feature is the syntax coloring in Elm files, as you will soon see.

To install this extension, open VSCode and open the 'Extensions' section (`Ctrl + Shift + X`).
Type 'elm' in the search box, and you will see the `elm` extension as shown in the screenshot below:
![Elm extension installation in Visual Studio Code](./image/2019-05-16.vscode-elm-install-extension.png)

Use the `Install` button to install this extension in VSCode.

Before this extension can work correctly, we need to tell it where to find the Elm program. Open the Visual Studio Code settings, using the menu entries `File` > `Preferences` > `Settings`.
In the settings interface, select the `Elm configuration` entry under `Extensions` in the tree on the left. Then you will see diverse settings for the elm extension on the right, as shown in the screenshot below. Scroll down to the `Compiler` section and enter the file path to the elm.exe we downloaded earlier into the textbox. The screenshot below shows how this looks like:

![Elm extension settings in Visual Studio Code](./image/2019-05-16.vscode-elm-settings.png)

VSCode automatically saves this setting and remembers it the next time you open the program.

To use VSCode with Elm, open it with the directory containing the `elm.json` file as the working directory. Otherwise, the Elm functionality will not work.
A convenient way to do this is using the Windows Explorer context menu entry `Open with Code` on the bot directory, as shown in the screenshot below:

![Open a directory in Visual Studio Code from the Windows Explorer](./image/vscode-open-directory-from-explorer.png)

Now we can test if our setup works correctly. In VSCode, open the `Main.elm` file and make the same code change as done earlier to provoke an error message from Elm.
When you save the file (`Ctrl + S`), the VSCode extension starts Elm in the background to check the code. On the first time, it can take longer as required packages are downloaded. But usually, Elm should complete the check in a second. If the code is ok, you will not see any change. If there is a problem, this is displayed in multiple places, as you can see in the screenshot below:

+ In the file tree view, coloring files containing errors in red.
+ On the scroll bar in an open file. You can see this as a red dot in the screenshot. This indicator helps to scroll to interesting locations in large files quickly.
+ When the offending portion of the code is visible in an editor viewport, the error is pointed out with a red squiggly underline.

![Visual Studio Code displays diagnostics from Elm](./image/2019-05-16.vscode-elm-diagnostics-display.png)

When you hover the mouse cursor over the highlighted text, a popup window shows more details. Here you find the message we get from Elm:

![Visual Studio Code displays diagnostics from Elm - details on hover](./image/2019-05-16.vscode-elm-diagnostics-display-hover.png)

----

Any questions? The [BotEngine forum](https://forum.botengine.org) is the place to meet other developers and get help.

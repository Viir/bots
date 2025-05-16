# General Bot Programming Guide

BotLab offers a system to automate activities in video games. As part of this system, we translate descriptions of these activities into a formal language that enables efficient operation and evolution at scale.

This document is a guide to the formalization process, distilling common learnings on how to go about adapting bots.

## General Rules for Bot Program Code

In addition to using a formal and explicit form, distilled bot program code follows additional rules to ensure high reliability and reusability. BotLab automatically enforces these rules: When looking at existing or future bot programs, we can see that these apply without exception. 

We don't need to worry about code breaking these rules when running a bot, since BotLab tools apply them automatically. However, when working on adapting a bot, considering these rules from the start helps avoid wasting time on incompatible implementation plans.

Planning program structures is about modelling data flow and control flow, and the following rules ensure that both are transparent.

### No-Side-Effects Rule

There are no hidden effects from the bot to the game or the outside world: The bot program explicitly communicates all effects by returning them from the 'main' entry function called by the runtime. In this system of managed effects, an effect in the bot program code is modeled as a data structure, encoding the type of effect (e.g., move mouse cursor in game) and related parameters (new x-coordinate, y-coordinate) Any function in the bot program can create these, but to apply them they need to be returned eventually from the entry function.

There are no hidden effects in the outside world on the bot: The classic example of such a hidden effect is getting 'the current time' in some subroutine. To make this information flow from the outside world transparent and explicit, the runtime hands it to the bot program as an explicit parameter to the 'main' entry function of the bot program.

This rule also enables the repeatable, deterministic session replay we use to train and test new bots efficiently.

### No-Mutations Rule

The bot program code does not assign new values to existing names or declarations. The content of a declaration is only assigned once at creation and never changed. This rule has implications for how we update a bot's memory, the past observations it needs to remember to make decisions in the future.

To make changing the program state possible, one single assignment in the program code replaces the complete program state at once. The bot returns the new program state from its 'main' entry function.

The runtime calls the 'main' entry function of the bot program whenever there is new information to process, and the bot can then return the new program state and a list of effects to apply to the game client.

## Structuring the Development Process

When we adapt a bot program, it's because we want to see a different behavior of the bot. It means we have at least one example of a situation in which the existing bot program behaved differently from how we would like.

The development process starts by identifying at least one moment in which the bot should have taken a (different) action in the game.

Next, we list all factors that contribute to our preference for the desired action in the game.

## Planning Bot Program Changes

When adapting a bot program, we often don't start from zero, but with an existing program we want to build on. That existing program already encodes lots of behavior that we distilled from many learnings about the mechanics of the game world and the game client.
Therefore, in most cases, we search for an implementation that fits well with the current overall program structure.

Most bot program frameworks follow an architecture dividing programs into the following two phases:

+ Aggregate and consolidate bot memory.
+ Select an input to send to the game.

For example, this bot for EVE Online uses a function declared as `updateMemoryForNewReadingFromGame` to update the bot's memory about the game world: <https://github.com/Viir/bots/blob/bb872a5e3a1caa0d4b1a6f02f9f347bb806dfedd/implement/applications/eve-online/eve-online-combat-anomaly-bot/Bot.elm#L1970-L2100>

```Elm
updateMemoryForNewReadingFromGame : UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =

```

The way that this bot program is structured, all the aggregating of information that the bot should remember in future steps should go into this function.
Also, if we find that it should remember something that it has not so far, we might want to expand the `BotMemory` declaration to support that new kind of memory.

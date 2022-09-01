# Bot Development Language and Terms

This document explains terms and language specific to the use and development of bots.

## Play Session

Whether we run a bot or record a human playing, we get a play session in both cases.
Why do we not distinguish (everywhere) between sessions with a human and sessions with a bot as the player agent? Because in some cases, we prefer to have a human take over temporarily when a bot gets stuck. This implies that a single session can have both human and bot as the player agent at different times.

## Player Agent

A player agent can be either a bot or a human. We use bots as agents for productive use. For development, we sometimes let a human take the role of the agent. After a human has demonstrated how to perform a task, we can use the recording of that play session for training bots. (Process mining)

## Program

We categorize programs based on their interfaces, that is, their inputs and outputs.
We distinguish the following three types of interfaces:

+ Player Agent ('Bot')
+ Environment
+ Assistant

The standard interface between player agent and environment allows us to combine any agent with any environment for testing and comparing fitness.

### Bot Program

A bot defines the behavior of a player agent. We also call it a programmatic player. It receives impressions from the environment, typically via screenshots of the game client. It outputs effects to perform on the game client. These are effects that could result from human interaction, such as mouse clicks or keyboard inputs.

We use the bot program interface also to derive metrics and notifications in a play session.

### Environment Program

An environment program allows us to simulate a player's environment. In contrast to a live environment, a simulated environment enables reproducible and automated testing.
Reproducible environments, in turn, allow us to quickly compare the fitness of different bots in the same situation.

### Assistant Program

An assistant program helps with developing programs. Input for this program includes our complete workspace, including the program we are working on and past play sessions. With this context, the assistant makes recommendations specific to our project and the situations our bots encountered in the past. These recommendations can include changes to bot-settings or program codes.


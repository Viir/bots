# Bot Development Language and Terms

This document explains terms and language specific to the use and development of bots.

## Agent

Agent in a play session can be either a bot or a human. We use bots as agents for productive use. For development, we sometimes let a human take the role of the agent. After a human has demonstrated how to perform a task, we can use the recording of that session for training bots. (Process mining)

## Program

We categorize programs based on their interfaces, that is, their inputs and outputs.
We distinguish the following three types of interfaces:

+ Agent / Bot
+ Environment
+ Assistant

The standard interface between agent and environment allows us to combine any agent with any environment for testing and comparing fitness.

### Bot Program

A bot defines the behavior of an agent. We can also call it a programmatic agent. It receives impressions from the environment, typically via screenshots of the game client. It outputs effects to perform on the game client. These are effects that could result from human interaction, such as mouse clicks or keyboard inputs.

We use the bot program interface also to derive metrics and notifications in a play session.

### Environment Program

An environment program allows us to simulate a bots environment. In contrast to a live environment, a simulated environment enables repeatable and automated testing.

### Assistant Program

An assistant program helps with developing programs. Input for this program includes our complete workspace, including the program we are working on and past play sessions. With this context, the assistant makes recommendations specific to our project and the situations our bots encountered in the past. These recommendations can include changes to bot-settings or program codes.


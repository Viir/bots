# Common Player Agent Interface

## Motivation for a Common Player Agent Interface

The common interface for player agents results from the cost reduction it implies in bot development projects.

Bot developers typically spend the most effort on tests depending on the environment. This environment can be a live game client, as would be the case during productive use of the bot. Because setting up a live game client is often relatively expensive, most tests happen with environment programs that simulate a game client. The standard interface to the player agent enables the reuse of existing simulation programs for more bot development projects.


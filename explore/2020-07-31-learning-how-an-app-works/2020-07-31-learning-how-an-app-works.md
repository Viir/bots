# 2020-07-31 - Learning How An App Works

Its program code defines the behavior of a bot. No matter if you want to fix a bug or expand an app with a new feature, you need to make a change in the program code. But how do you know what to change and where?

People who already have experience with the programming language can read the program code and then use that experience to simulate the program execution in their head. But that does not work if you are new to the programming language.

Besides not know the rules of the language, there is another reason why reading the program code is an inefficient way to learn how a program works: The source code covers many different situations and, as a result, is relatively abstract. For example, the ordering in the program code is independent of the actual processing order at runtime.

How do we find out in which order things happen and what are the roles of specific parts?

To do this, we look at how the program execution happened in a specific scenario.

We already have a way to see each event and the resulting response of the app. The next step is to look into the computations happening for a single event and see which parts of the program code contributed to what parts of the app's response.

To use terms of the programming language: To illustrate the data flow, we could use a tree view that follows the data flow backward via the applications.

Let's take this function as an example: https://github.com/Viir/bots/blob/5f711e9043bd20810578b1185a81ef5764d45e7c/implement/applications/eve-online/eve-online-combat-anomaly-bot/BotEngineApp.elm#L175-L197
This function expresses an application of `branchDependingOnDockedOrInSpace`. This application has a return value.
I notice I am going too far when looking for a useful visualization of this case. At first, I was thinking of a complete variant that supports the inspection of everything everywhere. But I notice that I find it easier to think about a variant where we would only see inspection branches for applications of named functions. Even this limited version seems a vast improvement over today's state. I will continue with this simplified version for now. I think we can more fine-grained inspection support later.

So `branchDependingOnDockedOrInSpace` is applied, or instantiated, which means we have arguments and a return value. Besides that, we want a way to see the program code that is responsible for this part. How do we make the connection between the value and the next instantiations?
We can add an option to expand at the `branchDependingOnDockedOrInSpace` text in `anomalyBotDecisionRoot`. One of the branches to view here is the arguments given to `branchDependingOnDockedOrInSpace`. The arguments look different from the expression we see in `anomalyBotDecisionRoot`, because this expression contains applications that lead to more concrete values.

We could use an approach more focusing on the return value: For every component, like a record field or an element in a tuple, we can add a branch to show the originating expression. More generally, for every value, offer to show the originating expression.

To help with reading the parts that are program code, we could highlight the expressions used/forced at least once from those not evaluated/forced in the current scenario. Or we could collapse the ones which are not used by default.

How could the visual tree look like starting at an application of `anomalyBotDecisionRoot` and expanding a few branches?

+ `anomalyBotDecisionRoot`
  + Arguments values
  + Return value
  + [Function code](https://github.com/Viir/bots/blob/5f711e9043bd20810578b1185a81ef5764d45e7c/implement/applications/eve-online/eve-online-combat-anomaly-bot/BotEngineApp.elm#L175-L197)
  + Evaluation
    + `branchDependingOnDockedOrInSpace`
      + Arguments values
      + Return value
      + [Function code](https://github.com/Viir/bots/blob/5f711e9043bd20810578b1185a81ef5764d45e7c/implement/applications/eve-online/eve-online-combat-anomaly-bot/EveOnline/AppFramework.elm#L1287-L1313)
      + Evaluation
        + `case readingFromGameClient.shipUI of`
          + Matching case `CanSee shipUI`
            + Arguments values
            + Return value
            + [Expression code](https://github.com/Viir/bots/blob/5f711e9043bd20810578b1185a81ef5764d45e7c/implement/applications/eve-online/eve-online-combat-anomaly-bot/EveOnline/AppFramework.elm#L1300-L1313)
            + Evaluation
              + `Maybe.withDefault`
          + Unused cases

Can we simplify this further for a MVP? What else can we remove?

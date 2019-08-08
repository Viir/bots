{- This bot demonstrates how to work with bot configurations, and how to implement a bot which supports configuration.
   It takes any configuration string received from the user and stores it in the bot state.
   This bot also updates the status message to show the last received bot configuration, so you can check that a method (e.g., via command line) of setting the bot configuration works.

   bot-catalog-tags:guide,demo-interface-to-host
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import Interface_To_Host_20190808 as InterfaceToHost
import Json.Encode


type alias State =
    { lastSetConfiguration : Maybe { timeInMilliseconds : Int, configuration : String }
    , timeInMilliseconds : Int
    }


initState : State
initState =
    { timeInMilliseconds = 0, lastSetConfiguration = Nothing }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent event stateBefore =
    let
        state =
            stateBefore |> integrateEvent event
    in
    ( state
    , InterfaceToHost.ContinueSession
        { statusDescriptionText = state |> statusMessageFromState
        , startTasks = []
        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = state.timeInMilliseconds + 1000 }
        }
    )


integrateEvent : InterfaceToHost.BotEvent -> State -> State
integrateEvent event stateBefore =
    case event of
        InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
            { stateBefore | timeInMilliseconds = timeInMilliseconds }

        InterfaceToHost.SetBotConfiguration configuration ->
            { stateBefore
                | lastSetConfiguration = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, configuration = configuration }
            }

        InterfaceToHost.CompletedTask _ ->
            stateBefore

        InterfaceToHost.SetSessionTimeLimit _ ->
            stateBefore


statusMessageFromState : State -> String
statusMessageFromState state =
    case state.lastSetConfiguration of
        Nothing ->
            "I did not receive any configuration so far."

        Just lastSetConfiguration ->
            let
                lastSetConfigurationAgeInSeconds =
                    (state.timeInMilliseconds - lastSetConfiguration.timeInMilliseconds) // 1000
            in
            (lastSetConfigurationAgeInSeconds |> String.fromInt)
                ++ " seconds ago, I received the following configuration:\n"
                ++ (lastSetConfiguration.configuration |> Json.Encode.string |> Json.Encode.encode 0)

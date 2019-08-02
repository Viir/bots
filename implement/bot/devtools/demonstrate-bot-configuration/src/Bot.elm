{- This bot demonstrates how to work with bot configurations, and how to implement a bot which supports configuration.
   It takes any configuration string received from the user and stores it in the bot state.
   This bot also updates the status message to show the last received bot configuration, so you can check that a method (e.g., via command line) of setting the bot configuration works.

   bot-catalog-tags:guide,demo-botengine
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import Interface_To_Host_20190720 as InterfaceToHost exposing (BotEventAtTime, BotRequest, ProcessEventResponse)
import Json.Encode


type alias State =
    { lastSetConfiguration : Maybe { timeInMilliseconds : Int, configuration : String }
    , timeInMilliseconds : Int
    }


initState : State
initState =
    { timeInMilliseconds = 0, lastSetConfiguration = Nothing }


processEvent : BotEventAtTime -> State -> ( State, ProcessEventResponse )
processEvent eventAtTime stateBefore =
    let
        state =
            stateBefore |> integrateEvent eventAtTime
    in
    ( state, { botRequests = [], statusDescriptionForOperator = state |> statusMessageFromState } )


integrateEvent : BotEventAtTime -> State -> State
integrateEvent eventAtTime stateBefore =
    let
        stateWithUpdatedTime =
            { stateBefore | timeInMilliseconds = eventAtTime.timeInMilliseconds }
    in
    case eventAtTime.event of
        InterfaceToHost.SetBotConfiguration configuration ->
            { stateWithUpdatedTime
                | lastSetConfiguration = Just { timeInMilliseconds = eventAtTime.timeInMilliseconds, configuration = configuration }
            }

        _ ->
            stateWithUpdatedTime


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

{- This bot demonstrates how to work with bot configurations, and how to implement a bot which supports configuration.
   It takes any configuration string received from the user and stores it in the bot state.
   This bot also updates the status message to show the last received bot configuration, so you can check that a method (e.g., via command line) of setting the bot configuration works.

   bot-catalog-tags:guide,demo-botengine
-}


module Main exposing
    ( InterfaceBotState
    , State
    , interfaceToHost_deserializeState
    , interfaceToHost_initState
    , interfaceToHost_processEvent
    , interfaceToHost_serializeState
    , main
    )

import Bot_Interface_To_Host_20190720 as InterfaceToHost exposing (BotEventAtTime, BotRequest, ProcessEventResponse)
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


type alias InterfaceBotState =
    State


interfaceToHost_initState : InterfaceBotState
interfaceToHost_initState =
    initState


interfaceToHost_processEvent : String -> InterfaceBotState -> ( InterfaceBotState, String )
interfaceToHost_processEvent =
    InterfaceToHost.wrapForSerialInterface_processEvent processEvent


interfaceToHost_serializeState : InterfaceBotState -> String
interfaceToHost_serializeState =
    always ""


interfaceToHost_deserializeState : String -> InterfaceBotState
interfaceToHost_deserializeState =
    always interfaceToHost_initState


{-| Define the Elm entry point. Don't change this function.
-}
main : Program Int InterfaceBotState String
main =
    InterfaceToHost.elmEntryPoint interfaceToHost_initState interfaceToHost_processEvent interfaceToHost_serializeState (interfaceToHost_deserializeState >> always interfaceToHost_initState)

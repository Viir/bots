{- This bot demonstrates how to remember the app settings string.
   It takes any settings string received from the user and stores it in the app state.
   This app also updates the status message to show the last received settings string, so you can check that a method (e.g., via command line) of applying the settings works.
-}
{-
   bot-catalog-tags:template,app-settings,demo-interface-to-host
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import Json.Encode


type alias State =
    { lastReceivedSettings : Maybe { timeInMilliseconds : Int, settings : String }
    , timeInMilliseconds : Int
    }


initState : State
initState =
    { timeInMilliseconds = 0, lastReceivedSettings = Nothing }


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

        InterfaceToHost.SetAppSettings settingsString ->
            { stateBefore
                | lastReceivedSettings = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, settings = settingsString }
            }

        InterfaceToHost.CompletedTask _ ->
            stateBefore

        InterfaceToHost.SetSessionTimeLimit _ ->
            stateBefore


statusMessageFromState : State -> String
statusMessageFromState state =
    case state.lastReceivedSettings of
        Nothing ->
            "I did not receive any settings so far."

        Just lastReceivedSettings ->
            let
                ageInSeconds =
                    (state.timeInMilliseconds - lastReceivedSettings.timeInMilliseconds) // 1000
            in
            (ageInSeconds |> String.fromInt)
                ++ " seconds ago, I received the following settings:\n"
                ++ (lastReceivedSettings.settings |> Json.Encode.string |> Json.Encode.encode 0)

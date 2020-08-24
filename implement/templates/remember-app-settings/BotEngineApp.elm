{- This bot demonstrates how to remember the app settings string.
   It takes any settings string received from the user and stores it in the app state.
   This app also updates the status message to show the last received settings string, so you can check that a method (e.g., via command line) of applying the settings works.
-}
{-
   app-catalog-tags:template,app-settings,demo-interface-to-host
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import Json.Encode


type alias State =
    { lastReceivedSettings : Maybe { timeInMilliseconds : Int, settings : String }
    , timeInMilliseconds : Int
    }


initState : State
initState =
    { timeInMilliseconds = 0, lastReceivedSettings = Nothing }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
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


integrateEvent : InterfaceToHost.AppEvent -> State -> State
integrateEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    case event.eventAtTime of
        InterfaceToHost.AppSettingsChangedEvent settingsString ->
            { stateBefore
                | lastReceivedSettings =
                    Just
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , settings = settingsString
                        }
            }

        InterfaceToHost.TimeArrivedEvent ->
            stateBefore

        InterfaceToHost.TaskCompletedEvent _ ->
            stateBefore

        InterfaceToHost.SessionDurationPlannedEvent _ ->
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
            [ (ageInSeconds |> String.fromInt) ++ " seconds ago, I received the following settings:"
            , lastReceivedSettings.settings
            , "----"
            , "As JSON encoded:"
            , lastReceivedSettings.settings |> Json.Encode.string |> Json.Encode.encode 0
            ]
                |> String.join "\n"

{- This program demonstrates how to use the session time limit.

   Some bots should consider the remaining time in the current session when choosing the next activity.
   This program gets and stores the session length limit set in the configuration interface.
   It also computes the remaining time as the difference between the present time and the configured limit and displays the result via the status text.
-}
{-
   catalog-tags:template,demo-interface-to-host
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost


type alias State =
    { timeInMilliseconds : Int
    , lastSessionLengthLimitInMilliseconds : Maybe Int
    }


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = { timeInMilliseconds = 0, lastSessionLengthLimitInMilliseconds = Nothing }
    , processEvent = processEvent
    }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotEventResponse )
processEvent event stateBefore =
    let
        state =
            stateBefore |> integrateEvent event
    in
    ( state
    , InterfaceToHost.ContinueSession
        { statusDescriptionText = state |> statusTextFromState
        , startTasks = []
        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = state.timeInMilliseconds + 1000 }
        }
    )


integrateEvent : InterfaceToHost.BotEvent -> State -> State
integrateEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    case event.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            stateBefore

        InterfaceToHost.BotSettingsChangedEvent _ ->
            stateBefore

        InterfaceToHost.TaskCompletedEvent _ ->
            stateBefore

        InterfaceToHost.SessionDurationPlannedEvent { timeInMilliseconds } ->
            { stateBefore | lastSessionLengthLimitInMilliseconds = Just timeInMilliseconds }


statusTextFromState : State -> String
statusTextFromState state =
    case state.lastSessionLengthLimitInMilliseconds of
        Nothing ->
            "I did not yet receive information about a session length limit."

        Just lastSessionLengthLimitInMilliseconds ->
            let
                remainingTotalSeconds =
                    (lastSessionLengthLimitInMilliseconds - state.timeInMilliseconds) // 1000
            in
            "The session length was set to "
                ++ describeTimespanAsMinutesPlusSeconds { lengthInSeconds = lastSessionLengthLimitInMilliseconds // 1000 }
                ++ ".\nRemaining are "
                ++ describeTimespanAsMinutesPlusSeconds { lengthInSeconds = remainingTotalSeconds }
                ++ "."


describeTimespanAsMinutesPlusSeconds : { lengthInSeconds : Int } -> String
describeTimespanAsMinutesPlusSeconds { lengthInSeconds } =
    let
        totalMinutes =
            lengthInSeconds // 60

        secondsInMinute =
            lengthInSeconds - totalMinutes * 60
    in
    (totalMinutes |> String.fromInt)
        ++ " minutes and "
        ++ (secondsInMinute |> String.fromInt)
        ++ " seconds"

{- This template demonstrates how to send inputs to a window on the same Windows machine.

   This bot only sends a sequence of inputs to the window and then stops.
   As the example input sequence below shows, we can implement drag&drop operations by using the inputs `MouseButtonDown`, `MoveMouseToLocation`, and `MouseButtonUp`.
   A good way to test and visualize the mouse paths is to use this bot on a canvas in the MS Paint app.
-}
{-
   catalog-tags:template,send-input-to-window,test
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework
    exposing
        ( bringWindowToForeground
        , keyboardKeyDown
        , keyboardKeyUp
        , mouseButtonDown
        , mouseButtonLeft
        , mouseButtonRight
        , mouseButtonUp
        , moveMouseToLocation
        )
import Common.EffectOnWindow


type alias SimpleState =
    { timeInMilliseconds : Int
    , remainingInputTasks : List SimpleBotFramework.Task
    , waitingForTaskToComplete : Maybe SimpleBotFramework.TaskId
    }


type alias State =
    SimpleBotFramework.State SimpleState


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = SimpleBotFramework.initState initState
    , processEvent = SimpleBotFramework.processEvent simpleProcessEvent
    }


initState : SimpleState
initState =
    { timeInMilliseconds = 0
    , waitingForTaskToComplete = Nothing
    , remainingInputTasks =
        [ bringWindowToForeground
        , moveMouseToLocation { x = 100, y = 350 }
        , mouseButtonDown mouseButtonLeft
        , moveMouseToLocation { x = 200, y = 400 }
        , mouseButtonUp mouseButtonLeft
        , mouseButtonDown mouseButtonRight
        , moveMouseToLocation { x = 300, y = 330 }
        , mouseButtonUp mouseButtonRight
        , moveMouseToLocation { x = 160, y = 335 }
        , mouseButtonDown mouseButtonLeft
        , mouseButtonUp mouseButtonLeft

        -- 2019-06-09 MS Paint did also draw when space key was pressed. Next, we draw a line without a mouse button, by holding the space key down.
        , moveMouseToLocation { x = 180, y = 330 }
        , keyboardKeyDown Common.EffectOnWindow.vkey_SPACE
        , moveMouseToLocation { x = 210, y = 340 }
        , keyboardKeyUp Common.EffectOnWindow.vkey_SPACE
        ]
    }


simpleProcessEvent : SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent event stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateEvent event
    in
    -- Do not start a new task before the engine has completed the last task.
    if stateBefore.waitingForTaskToComplete /= Nothing then
        ( stateBefore
        , SimpleBotFramework.ContinueSession
            { statusDescriptionText = "Waiting for task to complete."
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 100 }
            , startTasks = []
            }
        )

    else
        case stateBefore.remainingInputTasks of
            nextInputTask :: nextRemainingInputTasks ->
                let
                    { state, startTask, statusDescription, notifyWhenArrivedAtTime } =
                        let
                            taskId =
                                SimpleBotFramework.taskIdFromString "send-input"
                        in
                        { state =
                            { stateBefore
                                | remainingInputTasks = nextRemainingInputTasks
                                , waitingForTaskToComplete = Just taskId
                            }
                        , startTask =
                            { taskId = taskId, task = nextInputTask }
                                |> Just
                        , statusDescription =
                            "Sending next input. ("
                                ++ String.fromInt (List.length nextRemainingInputTasks)
                                ++ " others remaining)"
                        , notifyWhenArrivedAtTime = stateBefore.timeInMilliseconds + 100
                        }
                in
                ( state
                , SimpleBotFramework.ContinueSession
                    { statusDescriptionText = statusDescription
                    , notifyWhenArrivedAtTime = Just { timeInMilliseconds = notifyWhenArrivedAtTime }
                    , startTasks = startTask |> Maybe.map List.singleton |> Maybe.withDefault []
                    }
                )

            [] ->
                ( stateBefore
                , SimpleBotFramework.FinishSession { statusDescriptionText = "Completed sending inputs." }
                )


integrateEvent : SimpleBotFramework.BotEvent -> SimpleState -> SimpleState
integrateEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    case event.eventAtTime of
        SimpleBotFramework.TimeArrivedEvent ->
            stateBefore

        SimpleBotFramework.BotSettingsChangedEvent _ ->
            stateBefore

        SimpleBotFramework.SessionDurationPlannedEvent _ ->
            stateBefore

        SimpleBotFramework.TaskCompletedEvent taskCompletedEvent ->
            if stateBefore.waitingForTaskToComplete == Just taskCompletedEvent.taskId then
                { stateBefore | waitingForTaskToComplete = Nothing }

            else
                stateBefore

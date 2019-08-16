{- This template demonstrates how to send inputs to a window on the same Windows machine.
   This bot only sends a sequence of inputs to the window and then stops.
   As the example input sequence below shows, we can implement drag&drop operations by using the inputs `MouseButtonDown`, `MoveMouseToLocation`, and `MouseButtonUp`.
   A good way to test and visualize the mouse paths is to use this bot on a canvas in the MS Paint app.

   bot-catalog-tags:template,send-input-to-window,test
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import Interface_To_Host_20190808 as InterfaceToHost
import SimpleBotFramework


type alias SimpleState =
    { timeInMilliseconds : Int
    , remainingInputTasks : List SimpleBotFramework.Task
    , waitingForTaskToComplete : Maybe SimpleBotFramework.TaskId
    }


type alias State =
    SimpleBotFramework.State SimpleState


initState : State
initState =
    SimpleBotFramework.initState
        { timeInMilliseconds = 0
        , waitingForTaskToComplete = Nothing
        , remainingInputTasks =
            [ SimpleBotFramework.BringWindowToForeground
            , SimpleBotFramework.MoveMouseToLocation { x = 100, y = 250 }
            , SimpleBotFramework.MouseButtonDown SimpleBotFramework.MouseButtonLeft
            , SimpleBotFramework.MoveMouseToLocation { x = 200, y = 300 }
            , SimpleBotFramework.MouseButtonUp SimpleBotFramework.MouseButtonLeft
            , SimpleBotFramework.MouseButtonDown SimpleBotFramework.MouseButtonRight
            , SimpleBotFramework.MoveMouseToLocation { x = 300, y = 230 }
            , SimpleBotFramework.MouseButtonUp SimpleBotFramework.MouseButtonRight
            , SimpleBotFramework.MoveMouseToLocation { x = 160, y = 235 }
            , SimpleBotFramework.MouseButtonDown SimpleBotFramework.MouseButtonLeft
            , SimpleBotFramework.MouseButtonUp SimpleBotFramework.MouseButtonLeft

            -- 2019-06-09 MS Paint did also draw when space key was pressed. Next, we draw a line without a mouse button, by holding the space key down.
            , SimpleBotFramework.MoveMouseToLocation { x = 180, y = 230 }
            , SimpleBotFramework.KeyboardKeyDown SimpleBotFramework.VK_SPACE
            , SimpleBotFramework.MoveMouseToLocation { x = 210, y = 240 }
            , SimpleBotFramework.KeyboardKeyUp SimpleBotFramework.VK_SPACE
            ]
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleBotFramework.processEvent simpleProcessEvent


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
                        , statusDescription = "Sending next input."
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
integrateEvent event stateBefore =
    case event of
        SimpleBotFramework.ArrivedAtTime arrivedAtTime ->
            { stateBefore | timeInMilliseconds = arrivedAtTime.timeInMilliseconds }

        SimpleBotFramework.SetBotConfiguration _ ->
            stateBefore

        SimpleBotFramework.SetSessionTimeLimit _ ->
            stateBefore

        SimpleBotFramework.CompletedTask completedTask ->
            if stateBefore.waitingForTaskToComplete == Just completedTask.taskId then
                { stateBefore | waitingForTaskToComplete = Nothing }

            else
                stateBefore

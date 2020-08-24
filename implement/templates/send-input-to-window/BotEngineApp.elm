{- This template demonstrates how to send inputs to a window on the same Windows machine.
   This bot only sends a sequence of inputs to the window and then stops.
   As the example input sequence below shows, we can implement drag&drop operations by using the inputs `MouseButtonDown`, `MoveMouseToLocation`, and `MouseButtonUp`.
   A good way to test and visualize the mouse paths is to use this bot on a canvas in the MS Paint app.
-}
{-
   app-catalog-tags:template,send-input-to-window,test
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import BotEngine.SimpleBotFramework as SimpleBotFramework
    exposing
        ( bringWindowToForeground
        , keyboardKeyDown
        , keyboardKeyUp
        , keyboardKey_space
        , mouseButtonDown
        , mouseButtonLeft
        , mouseButtonRight
        , mouseButtonUp
        , moveMouseToLocation
        )


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
            [ bringWindowToForeground
            , moveMouseToLocation { x = 100, y = 250 }
            , mouseButtonDown mouseButtonLeft
            , moveMouseToLocation { x = 200, y = 300 }
            , mouseButtonUp mouseButtonLeft
            , mouseButtonDown mouseButtonRight
            , moveMouseToLocation { x = 300, y = 230 }
            , mouseButtonUp mouseButtonRight
            , moveMouseToLocation { x = 160, y = 235 }
            , mouseButtonDown mouseButtonLeft
            , mouseButtonUp mouseButtonLeft

            -- 2019-06-09 MS Paint did also draw when space key was pressed. Next, we draw a line without a mouse button, by holding the space key down.
            , moveMouseToLocation { x = 180, y = 230 }
            , keyboardKeyDown keyboardKey_space
            , moveMouseToLocation { x = 210, y = 240 }
            , keyboardKeyUp keyboardKey_space
            ]
        }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
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
integrateEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    case event.eventAtTime of
        SimpleBotFramework.TimeArrivedEvent ->
            stateBefore

        SimpleBotFramework.AppSettingsChangedEvent _ ->
            stateBefore

        SimpleBotFramework.SessionDurationPlannedEvent _ ->
            stateBefore

        SimpleBotFramework.TaskCompletedEvent taskCompletedEvent ->
            if stateBefore.waitingForTaskToComplete == Just taskCompletedEvent.taskId then
                { stateBefore | waitingForTaskToComplete = Nothing }

            else
                stateBefore

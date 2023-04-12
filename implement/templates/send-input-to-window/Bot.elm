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

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework
    exposing
        ( bringWindowToForeground
        , keyboardKeyDownEffect
        , keyboardKeyUpEffect
        , mouseButtonDownEffect
        , mouseButtonUpEffect
        , setMouseCursorPositionEffect
        )
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))


type alias BotSettings =
    {}


type alias SimpleState =
    { timeInMilliseconds : Int
    , remainingInputEffects : List Common.EffectOnWindow.EffectOnWindowStructure
    , waitingForTaskToComplete : Maybe SimpleBotFramework.TaskId
    }


type alias State =
    SimpleBotFramework.State BotSettings SimpleState


botMain : InterfaceToHost.BotConfig State
botMain =
    SimpleBotFramework.composeSimpleBotMain
        { parseBotSettings = AppSettings.parseAllowOnlyEmpty {}
        , init = initState
        , processEvent = simpleProcessEvent
        }


initState : SimpleState
initState =
    { timeInMilliseconds = 0
    , waitingForTaskToComplete = Nothing
    , remainingInputEffects =
        [ setMouseCursorPositionEffect { x = 100, y = 350 }
        , mouseButtonDownEffect LeftMouseButton
        , setMouseCursorPositionEffect { x = 200, y = 400 }
        , mouseButtonUpEffect LeftMouseButton
        , mouseButtonDownEffect RightMouseButton
        , setMouseCursorPositionEffect { x = 300, y = 330 }
        , mouseButtonUpEffect RightMouseButton
        , setMouseCursorPositionEffect { x = 160, y = 335 }
        , mouseButtonDownEffect LeftMouseButton
        , mouseButtonUpEffect LeftMouseButton

        -- 2019-06-09 MS Paint did also draw when space key was pressed. Next, we draw a line without a mouse button, by holding the space key down.
        , setMouseCursorPositionEffect { x = 180, y = 330 }
        , keyboardKeyDownEffect Common.EffectOnWindow.vkey_SPACE
        , setMouseCursorPositionEffect { x = 210, y = 340 }
        , keyboardKeyUpEffect Common.EffectOnWindow.vkey_SPACE
        ]
    }


simpleProcessEvent :
    BotSettings
    -> SimpleBotFramework.BotEvent
    -> SimpleState
    -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent _ event stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateEvent event
    in
    -- Do not start a new task before the engine has completed the last task.
    if stateBefore.waitingForTaskToComplete /= Nothing then
        ( stateBefore
        , SimpleBotFramework.ContinueSession
            { statusText = "Waiting for task to complete."
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 100 }
            , startTasks = []
            }
        )

    else
        case stateBefore.remainingInputEffects of
            nextInputEffect :: nextRemainingInputEffects ->
                let
                    { state, startTasks, statusDescription, notifyWhenArrivedAtTime } =
                        let
                            taskId =
                                SimpleBotFramework.taskIdFromString "send-input"
                        in
                        { state =
                            { stateBefore
                                | remainingInputEffects = nextRemainingInputEffects
                                , waitingForTaskToComplete = Just taskId
                            }
                        , startTasks =
                            [ { taskId = SimpleBotFramework.taskIdFromString "bring-window-to-front"
                              , task = bringWindowToForeground
                              }
                            , { taskId = SimpleBotFramework.taskIdFromString "send-input"
                              , task =
                                    [ nextInputEffect ]
                                        |> SimpleBotFramework.effectSequenceTask
                                            { delayBetweenEffectsMilliseconds = 100 }
                              }
                            ]
                        , statusDescription =
                            "Sending next input. ("
                                ++ String.fromInt (List.length nextRemainingInputEffects)
                                ++ " others remaining)"
                        , notifyWhenArrivedAtTime = stateBefore.timeInMilliseconds + 100
                        }
                in
                ( state
                , SimpleBotFramework.ContinueSession
                    { statusText = statusDescription
                    , notifyWhenArrivedAtTime = Just { timeInMilliseconds = notifyWhenArrivedAtTime }
                    , startTasks = startTasks
                    }
                )

            [] ->
                ( stateBefore
                , SimpleBotFramework.FinishSession { statusText = "Completed sending inputs." }
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

        SimpleBotFramework.SessionDurationPlannedEvent _ ->
            stateBefore

        SimpleBotFramework.TaskCompletedEvent taskCompletedEvent ->
            if stateBefore.waitingForTaskToComplete == Just taskCompletedEvent.taskId then
                { stateBefore | waitingForTaskToComplete = Nothing }

            else
                stateBefore

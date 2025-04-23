module EveOnline.UnstuckBot exposing (..)

{-| A wrapper to solve the problem of a bot getting stuck as seen in session-recording-2024-10-14T22-30-16:
In that session, the bot repeatedly tried to click on a target to select it.
Customer reported that after clicking somewhere else, the bot continued as normal.

The mentioned session log shows that the bot repeatedly sent the exact same effect request for a mouse click.
However, when we randomize the mouse click coordinates, doing a plain equality check on the effect requests will not be enough anymore.

-}

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import Common.EffectOnWindow


type alias UnstuckBotState supervised =
    { supervised : supervised
    , lastStepsEffectsOnGameClient : List (List InterfaceToHost.WindowsInputSequenceItem)
    , lastReadFromWindowComplete :
        Maybe
            { windowId : String
            , clientRectLeftUpperToScreen : InterfaceToHost.WinApiPointStruct
            }
    }


botResolvingStuck :
    InterfaceToHost.BotConfig supervised
    -> InterfaceToHost.BotConfig (UnstuckBotState supervised)
botResolvingStuck supervisedBotConfig =
    { init =
        { supervised = supervisedBotConfig.init
        , lastStepsEffectsOnGameClient = []
        , lastReadFromWindowComplete = Nothing
        }
    , processEvent = processEventResolvingStuck supervisedBotConfig.processEvent
    }


processEventResolvingStuck :
    (InterfaceToHost.BotEvent
     -> supervised
     -> ( supervised, InterfaceToHost.BotEventResponse )
    )
    -> InterfaceToHost.BotEvent
    -> UnstuckBotState supervised
    -> ( UnstuckBotState supervised, InterfaceToHost.BotEventResponse )
processEventResolvingStuck config event stateBefore =
    let
        lastReadFromWindowComplete =
            case event.eventAtTime of
                InterfaceToHost.TaskCompletedEvent taskComplete ->
                    case taskComplete.taskResult of
                        InterfaceToHost.InvokeMethodOnWindowResponse windowId (Ok (InterfaceToHost.ReadFromWindowMethodResult readFromWindowComplete)) ->
                            Just
                                { windowId = windowId
                                , clientRectLeftUpperToScreen =
                                    readFromWindowComplete.clientRectLeftUpperToScreen
                                }

                        _ ->
                            stateBefore.lastReadFromWindowComplete

                _ ->
                    stateBefore.lastReadFromWindowComplete

        ( supervisedState, supervisedResponse ) =
            config event stateBefore.supervised

        continueWithoutUpdate =
            ( { stateBefore
                | supervised = supervisedState
                , lastReadFromWindowComplete = lastReadFromWindowComplete
              }
            , supervisedResponse
            )
    in
    case supervisedResponse of
        InterfaceToHost.FinishSession _ ->
            continueWithoutUpdate

        InterfaceToHost.ContinueSession continueSession ->
            case listEffectsFromContinueSessionStructure continueSession of
                [] ->
                    continueWithoutUpdate

                newEffectsOnGameClient ->
                    let
                        lastStepsEffectsOnGameClient : List (List InterfaceToHost.WindowsInputSequenceItem)
                        lastStepsEffectsOnGameClient =
                            newEffectsOnGameClient
                                :: List.take 10 stateBefore.lastStepsEffectsOnGameClient

                        continueWithoutIntervention : ( UnstuckBotState supervised, InterfaceToHost.BotEventResponse )
                        continueWithoutIntervention =
                            ( { stateBefore
                                | supervised = supervisedState
                                , lastStepsEffectsOnGameClient = lastStepsEffectsOnGameClient
                              }
                            , supervisedResponse
                            )

                        shouldIntervene : Bool
                        shouldIntervene =
                            (4 < List.length stateBefore.lastStepsEffectsOnGameClient)
                                && List.all
                                    (\previousStepEffects -> previousStepEffects == newEffectsOnGameClient)
                                    stateBefore.lastStepsEffectsOnGameClient
                    in
                    if shouldIntervene then
                        let
                            ( interventionStatusText, interventionTasks ) =
                                case lastReadFromWindowComplete of
                                    Nothing ->
                                        ( "Failed to intervene because the last readFromWindowComplete is missing."
                                        , []
                                        )

                                    Just readFromWindowComplete ->
                                        let
                                            mouseClickLocation =
                                                { x = readFromWindowComplete.clientRectLeftUpperToScreen.x + 10
                                                , y = readFromWindowComplete.clientRectLeftUpperToScreen.y + 10
                                                }

                                            windowId =
                                                if String.startsWith "winapi" readFromWindowComplete.windowId then
                                                    readFromWindowComplete.windowId

                                                else
                                                    "winapi/" ++ readFromWindowComplete.windowId

                                            (Common.EffectOnWindow.VirtualKeyCodeFromInt buttonCode) =
                                                Common.EffectOnWindow.virtualKeyCodeFromMouseButton Common.EffectOnWindow.MouseButtonLeft

                                            interfaceTask : InterfaceToHost.Task
                                            interfaceTask =
                                                InterfaceToHost.WindowsInputRequest
                                                    [ InterfaceToHost.BringWindowToForeground windowId
                                                    , InterfaceToHost.WaitMilliseconds 300
                                                    , InterfaceToHost.MouseMoveAbsolute
                                                        mouseClickLocation.x
                                                        mouseClickLocation.y
                                                    , InterfaceToHost.WaitMilliseconds 200
                                                    , InterfaceToHost.ButtonDown buttonCode
                                                    , InterfaceToHost.WaitMilliseconds 300
                                                    , InterfaceToHost.ButtonUp buttonCode
                                                    ]
                                        in
                                        ( String.join ""
                                            [ "I will intervene by clicking at "
                                            , String.fromInt mouseClickLocation.x
                                            , ", " ++ String.fromInt mouseClickLocation.y
                                            ]
                                        , [ { taskId = "click"
                                            , task = interfaceTask
                                            }
                                          ]
                                        )

                            statusText =
                                String.join "\n"
                                    [ String.join ""
                                        [ "I see the bot repeated the same action for the last "
                                        , String.fromInt (List.length stateBefore.lastStepsEffectsOnGameClient)
                                        , " steps."
                                        ]
                                    , interventionStatusText
                                    ]

                            continueSessionWithIntervention : InterfaceToHost.ContinueSessionStructure
                            continueSessionWithIntervention =
                                { statusText = statusText
                                , startTasks = interventionTasks
                                , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                                }
                        in
                        ( { stateBefore
                            | supervised = supervisedState
                            , lastStepsEffectsOnGameClient = []
                          }
                        , InterfaceToHost.ContinueSession continueSessionWithIntervention
                        )

                    else
                        continueWithoutIntervention


listEffectsFromContinueSessionStructure :
    InterfaceToHost.ContinueSessionStructure
    -> List InterfaceToHost.WindowsInputSequenceItem
listEffectsFromContinueSessionStructure continueSession =
    continueSession.startTasks
        |> List.concatMap
            (\startTask ->
                case startTask.task of
                    InterfaceToHost.WindowsInputRequest windowsInputItems ->
                        windowsInputItems
                            |> List.filter
                                (\item ->
                                    case item of
                                        InterfaceToHost.WaitMilliseconds _ ->
                                            False

                                        InterfaceToHost.AbortIfWindowNotInForeground _ ->
                                            False

                                        InterfaceToHost.BringWindowToForeground _ ->
                                            False

                                        InterfaceToHost.KeyDown _ _ ->
                                            True

                                        InterfaceToHost.KeyUp _ _ ->
                                            True

                                        InterfaceToHost.MouseMoveAbsolute _ _ ->
                                            True

                                        InterfaceToHost.MouseMoveRelative _ _ ->
                                            True

                                        InterfaceToHost.ButtonDown _ ->
                                            True

                                        InterfaceToHost.ButtonUp _ ->
                                            True

                                        InterfaceToHost.ButtonScroll _ _ _ ->
                                            True

                                        InterfaceToHost.CharacterDown _ ->
                                            True

                                        InterfaceToHost.CharacterUp _ ->
                                            True
                                )

                    _ ->
                        []
            )

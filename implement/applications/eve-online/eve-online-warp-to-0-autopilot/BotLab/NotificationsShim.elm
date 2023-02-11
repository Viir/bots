module BotLab.NotificationsShim exposing
    ( Notification
    , StateWithNotifications
    , addNotifications
    , consoleBeepNotification
    )

{-| This module offers a shim to add notification sounds to your bot even before the botlab client supports notifications.
To use it, apply the `addNotifications` function on your bot configuration in your `botMain` declaration.

The framework derives the notifications from your bot's status text, according to the function you give as the argument to `addNotifications`.

-}

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import BotLab.NotificationsShim.VolatileProcessInterface as VolatileProcessInterface
import CompilationInterface.SourceFiles


type alias NotificationsFunction =
    { statusText : String } -> List Notification


type Notification
    = ConsoleBeepNotification (List ConsoleBeepStructure)


type alias ConsoleBeepStructure =
    { frequency : Int
    , durationInMs : Int
    }


type alias StateWithNotifications botState =
    { -- Remember also the last response because we continue to display the status text.
      wrappedBot : ( botState, InterfaceToHost.BotEventResponse )
    , notifications : ( NotificationsState, InterfaceToHost.ContinueSessionStructure )
    }


type alias NotificationsState =
    { volatileProcess : Maybe VolatileProcessSetupState
    , notificationsCount : Int
    }


type VolatileProcessSetupState
    = CreationRequestedSetupState
    | CreationFailedSetupState InterfaceToHost.CreateVolatileProcessErrorStructure
    | CreationCompletedState InterfaceToHost.CreateVolatileProcessComplete


taskIdPrefix : String
taskIdPrefix =
    "notifications-shim-"


consoleBeepNotification : List ConsoleBeepStructure -> Notification
consoleBeepNotification =
    ConsoleBeepNotification


addNotifications :
    NotificationsFunction
    -> InterfaceToHost.BotConfig botState
    -> InterfaceToHost.BotConfig (StateWithNotifications botState)
addNotifications notificationsFunction wrappedBot =
    { init = init wrappedBot
    , processEvent = processEvent wrappedBot notificationsFunction
    }


init : InterfaceToHost.BotConfig botState -> StateWithNotifications botState
init wrappedBot =
    { wrappedBot =
        ( wrappedBot.init
        , InterfaceToHost.FinishSession { statusText = "This value will never be used" }
        )
    , notifications =
        ( { volatileProcess = Nothing
          , notificationsCount = 0
          }
        , { startTasks = [], statusText = "", notifyWhenArrivedAtTime = Nothing }
        )
    }


switchEvent :
    InterfaceToHost.BotEvent
    -> { toNotifications : Maybe InterfaceToHost.BotEvent, toWrappedBot : Maybe InterfaceToHost.BotEvent }
switchEvent event =
    case event.eventAtTime of
        InterfaceToHost.TaskCompletedEvent taskCompleted ->
            if String.startsWith taskIdPrefix taskCompleted.taskId then
                { toNotifications = Just event, toWrappedBot = Nothing }

            else
                { toNotifications = Nothing, toWrappedBot = Just event }

        _ ->
            { toNotifications = Just event, toWrappedBot = Just event }


processEventNotificationsSetup :
    InterfaceToHost.BotEvent
    -> NotificationsState
    -> ( NotificationsState, InterfaceToHost.ContinueSessionStructure )
processEventNotificationsSetup event stateBefore =
    let
        notificationTasksCompleted =
            case event.eventAtTime of
                InterfaceToHost.TimeArrivedEvent ->
                    []

                InterfaceToHost.SessionDurationPlannedEvent _ ->
                    []

                InterfaceToHost.BotSettingsChangedEvent _ ->
                    []

                InterfaceToHost.TaskCompletedEvent taskCompleted ->
                    if String.startsWith taskIdPrefix taskCompleted.taskId then
                        [ taskCompleted.taskResult ]

                    else
                        []

        state =
            notificationTasksCompleted
                |> List.foldl
                    (\notificationTaskCompleted intermediateState ->
                        case notificationTaskCompleted of
                            InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResponse ->
                                let
                                    volatileProcess =
                                        case createVolatileProcessResponse of
                                            Err error ->
                                                CreationFailedSetupState error

                                            Ok ok ->
                                                CreationCompletedState ok
                                in
                                { intermediateState
                                    | volatileProcess = Just volatileProcess
                                }

                            InterfaceToHost.RequestToVolatileProcessResponse _ ->
                                intermediateState

                            InterfaceToHost.OpenWindowResponse _ ->
                                intermediateState

                            InterfaceToHost.InvokeMethodOnWindowResponse _ _ ->
                                intermediateState

                            InterfaceToHost.CompleteWithoutResult ->
                                intermediateState

                            InterfaceToHost.RandomBytesResponse _ ->
                                intermediateState
                    )
                    stateBefore
    in
    case state.volatileProcess of
        Nothing ->
            ( { state | volatileProcess = Just CreationRequestedSetupState }
            , { statusText = "Creating volatile process."
              , startTasks =
                    [ { taskId = taskIdPrefix ++ "create-volatile-process"
                      , task =
                            InterfaceToHost.CreateVolatileProcess
                                { programCode = CompilationInterface.SourceFiles.file____BotLab_NotificationsShim_VolatileProcess_csx.utf8 }
                      }
                    ]
              , notifyWhenArrivedAtTime = Nothing
              }
            )

        Just CreationRequestedSetupState ->
            ( state
            , { statusText = "Waiting for volatile process..."
              , startTasks = []
              , notifyWhenArrivedAtTime = Nothing
              }
            )

        Just (CreationFailedSetupState failed) ->
            ( state
            , { statusText = "Failed to create volatile process: " ++ failed.exceptionToString
              , startTasks = []
              , notifyWhenArrivedAtTime = Nothing
              }
            )

        Just (CreationCompletedState _) ->
            ( state
            , { statusText = ""
              , startTasks = []
              , notifyWhenArrivedAtTime = Nothing
              }
            )


processEvent :
    InterfaceToHost.BotConfig botState
    -> NotificationsFunction
    -> InterfaceToHost.BotEvent
    -> StateWithNotifications botState
    -> ( StateWithNotifications botState, InterfaceToHost.BotEventResponse )
processEvent wrappedBot notificationsFunction event stateBefore =
    let
        switchedEvent =
            switchEvent event

        wrappedBotNewStateAndResponse =
            switchedEvent.toWrappedBot
                |> Maybe.map (wrappedBot.processEvent >> (|>) (Tuple.first stateBefore.wrappedBot))

        notificationsStateBefore =
            Tuple.first stateBefore.notifications

        maybeNotificationEventSetupResult =
            switchedEvent.toNotifications
                |> Maybe.map (processEventNotificationsSetup >> (|>) notificationsStateBefore)

        notificationsState =
            maybeNotificationEventSetupResult
                |> Maybe.map Tuple.first
                |> Maybe.withDefault notificationsStateBefore

        notificationsLastResponse =
            maybeNotificationEventSetupResult |> Maybe.map Tuple.second |> Maybe.withDefault (Tuple.second stateBefore.notifications)

        wrappedBotStateAndResponse =
            wrappedBotNewStateAndResponse
                |> Maybe.withDefault stateBefore.wrappedBot

        ( mergedResponse, notificationsCountIncrease ) =
            case Tuple.second wrappedBotStateAndResponse of
                InterfaceToHost.FinishSession _ ->
                    ( Tuple.second wrappedBotStateAndResponse, 0 )

                InterfaceToHost.ContinueSession wrappedBotContinueSession ->
                    let
                        ( wrappedBotStartTasks, notifications ) =
                            case Maybe.map Tuple.second wrappedBotNewStateAndResponse of
                                Nothing ->
                                    ( [], [] )

                                Just (InterfaceToHost.FinishSession _) ->
                                    ( [], [] )

                                Just (InterfaceToHost.ContinueSession wrappedBotNewContinueSession) ->
                                    ( wrappedBotNewContinueSession.startTasks
                                    , notificationsFunction
                                        { statusText = wrappedBotNewContinueSession.statusText }
                                    )

                        notificationsSetupTasks =
                            maybeNotificationEventSetupResult
                                |> Maybe.map (Tuple.second >> .startTasks)
                                |> Maybe.withDefault []

                        notificationsTasks =
                            case notificationsState.volatileProcess of
                                Nothing ->
                                    []

                                Just CreationRequestedSetupState ->
                                    []

                                Just (CreationFailedSetupState _) ->
                                    []

                                Just (CreationCompletedState creationComplete) ->
                                    notifications
                                        |> List.indexedMap
                                            (\index notification ->
                                                let
                                                    taskIdString =
                                                        taskIdPrefix ++ "notify-" ++ String.fromInt (notificationsStateBefore.notificationsCount + index)

                                                    taskRequest =
                                                        case notification of
                                                            ConsoleBeepNotification beeps ->
                                                                VolatileProcessInterface.EffectConsoleBeepSequence beeps

                                                    task =
                                                        InterfaceToHost.RequestToVolatileProcess
                                                            (InterfaceToHost.RequestNotRequiringInputFocus
                                                                { processId = creationComplete.processId
                                                                , request =
                                                                    VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost taskRequest
                                                                }
                                                            )
                                                in
                                                { taskId = taskIdString
                                                , task = task
                                                }
                                            )

                        statusTextNotificationsAppendix =
                            case notificationsLastResponse.statusText of
                                "" ->
                                    Nothing

                                nonEmpty ->
                                    Just ("Notifications shim: " ++ nonEmpty)

                        mergedStatusText =
                            wrappedBotContinueSession.statusText
                                ++ "\n"
                                ++ Maybe.withDefault "" statusTextNotificationsAppendix

                        mergedNotifyWhenArrivedAtTime =
                            [ Just wrappedBotContinueSession, Maybe.map Tuple.second maybeNotificationEventSetupResult ]
                                |> List.filterMap identity
                                |> List.map .notifyWhenArrivedAtTime
                                |> List.filterMap (Maybe.map .timeInMilliseconds)
                                |> List.minimum
                                |> Maybe.map (\timeInMilliseconds -> { timeInMilliseconds = timeInMilliseconds })

                        startTasks =
                            wrappedBotStartTasks
                                ++ notificationsSetupTasks
                                ++ notificationsTasks
                    in
                    ( InterfaceToHost.ContinueSession
                        { statusText = mergedStatusText
                        , startTasks = startTasks
                        , notifyWhenArrivedAtTime = mergedNotifyWhenArrivedAtTime
                        }
                    , List.length notifications
                    )

        notificationsCount =
            notificationsStateBefore.notificationsCount + notificationsCountIncrease
    in
    ( { wrappedBot = wrappedBotStateAndResponse
      , notifications = ( { notificationsState | notificationsCount = notificationsCount }, notificationsLastResponse )
      }
    , mergedResponse
    )

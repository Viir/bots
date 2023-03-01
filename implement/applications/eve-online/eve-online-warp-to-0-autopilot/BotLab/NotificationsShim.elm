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
import Dict


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
      timeInMilliseconds : Int
    , wrappedBot :
        { state : botState
        , lastStatusText : String
        , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
        }
    , notifications : ( NotificationsState, InterfaceToHost.ContinueSessionStructure )
    }


type alias NotificationsState =
    { volatileProcess : Maybe VolatileProcessSetupState
    , notificationsCount : Int
    , queuedNotifications : List { timeInMilliseconds : Int, notification : Notification }
    , startedNotifications : List { timeInMilliseconds : Int, notification : Notification }
    , runningTasks : Dict.Dict String { timeInMilliseconds : Int }
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
    { timeInMilliseconds = 0
    , wrappedBot =
        { state = wrappedBot.init
        , lastStatusText = "This value will never be used"
        , notifyWhenArrivedAtTime = Nothing
        }
    , notifications =
        ( { volatileProcess = Nothing
          , notificationsCount = 0
          , queuedNotifications = []
          , startedNotifications = []
          , runningTasks = Dict.empty
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

        InterfaceToHost.TimeArrivedEvent ->
            { toNotifications = Just event, toWrappedBot = Just event }

        InterfaceToHost.SessionDurationPlannedEvent _ ->
            { toNotifications = Just event, toWrappedBot = Just event }

        _ ->
            { toNotifications = Nothing, toWrappedBot = Just event }


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
                        [ taskCompleted ]

                    else
                        []

        runningTasks =
            notificationTasksCompleted
                |> List.map .taskId
                |> List.foldl Dict.remove
                    stateBefore.runningTasks

        state =
            notificationTasksCompleted
                |> List.map .taskResult
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
                    { stateBefore | runningTasks = runningTasks }
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
        notificationsStateBefore =
            Tuple.first stateBefore.notifications

        switchedEvent =
            switchEvent event

        wrappedBotNewStateAndResponse =
            switchedEvent.toWrappedBot
                |> Maybe.map (wrappedBot.processEvent >> (|>) stateBefore.wrappedBot.state)

        wrappedBotState =
            case wrappedBotNewStateAndResponse of
                Nothing ->
                    stateBefore.wrappedBot

                Just ( botState, botResponse ) ->
                    let
                        ( lastStatusText, notifyWhenArrivedAtTime ) =
                            case botResponse of
                                InterfaceToHost.ContinueSession botContinueSession ->
                                    ( botContinueSession.statusText, botContinueSession.notifyWhenArrivedAtTime )

                                InterfaceToHost.FinishSession botFinishSession ->
                                    ( botFinishSession.statusText, Nothing )
                    in
                    { state = botState
                    , lastStatusText = lastStatusText
                    , notifyWhenArrivedAtTime = notifyWhenArrivedAtTime
                    }

        currentNotifications =
            case wrappedBotNewStateAndResponse of
                Nothing ->
                    []

                Just ( _, botResponse ) ->
                    let
                        botResponseStatusText =
                            case botResponse of
                                InterfaceToHost.ContinueSession continueSession ->
                                    continueSession.statusText

                                InterfaceToHost.FinishSession finishSession ->
                                    finishSession.statusText
                    in
                    notificationsFunction { statusText = botResponseStatusText }

        notificationAlreadyQueued notification =
            notificationsStateBefore.queuedNotifications
                |> List.map .notification
                |> List.member notification

        newQueuedNotifications =
            currentNotifications
                |> List.filter (notificationAlreadyQueued >> not)
                |> List.map
                    (\notification ->
                        { timeInMilliseconds = stateBefore.timeInMilliseconds, notification = notification }
                    )

        maybeNotificationEventSetupResult =
            switchedEvent.toNotifications
                |> Maybe.map
                    (processEventNotificationsSetup
                        >> (|>)
                            { notificationsStateBefore
                                | queuedNotifications = notificationsStateBefore.queuedNotifications ++ newQueuedNotifications
                            }
                    )

        notificationsState =
            maybeNotificationEventSetupResult
                |> Maybe.map Tuple.first
                |> Maybe.withDefault notificationsStateBefore

        notificationsLastResponse =
            maybeNotificationEventSetupResult
                |> Maybe.map Tuple.second
                |> Maybe.withDefault (Tuple.second stateBefore.notifications)

        notificationsTasks =
            if notificationsState.runningTasks /= Dict.empty then
                []

            else
                case notificationsState.volatileProcess of
                    Nothing ->
                        []

                    Just CreationRequestedSetupState ->
                        []

                    Just (CreationFailedSetupState _) ->
                        []

                    Just (CreationCompletedState creationComplete) ->
                        case notificationsState.queuedNotifications of
                            [] ->
                                []

                            nextQueuedNotification :: _ ->
                                let
                                    taskIdString =
                                        [ taskIdPrefix
                                        , "notify"
                                        , String.fromInt notificationsStateBefore.notificationsCount
                                        ]
                                            |> String.join "-"

                                    taskRequest =
                                        case nextQueuedNotification.notification of
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
                                [ { taskId = taskIdString
                                  , task = task
                                  }
                                ]

        startedNotifications =
            notificationsState.queuedNotifications
                |> List.take (List.length notificationsTasks)

        remainingQueuedNotifications =
            notificationsState.queuedNotifications
                |> List.drop (List.length notificationsTasks)

        runningTasks =
            notificationsTasks
                |> List.map .taskId
                |> List.foldl (\taskId -> Dict.insert taskId { timeInMilliseconds = stateBefore.timeInMilliseconds })
                    notificationsState.runningTasks

        statusTextNotificationsAppendix =
            case notificationsLastResponse.statusText of
                "" ->
                    Nothing

                nonEmpty ->
                    Just ("Notifications shim: " ++ nonEmpty)

        baseResponse =
            wrappedBotNewStateAndResponse
                |> Maybe.map Tuple.second
                |> Maybe.withDefault
                    (InterfaceToHost.ContinueSession
                        { statusText = stateBefore.wrappedBot.lastStatusText
                        , startTasks = []
                        , notifyWhenArrivedAtTime = Nothing
                        }
                    )

        mergedResponse =
            case baseResponse of
                InterfaceToHost.FinishSession _ ->
                    baseResponse

                InterfaceToHost.ContinueSession continueSession ->
                    let
                        notificationsSetupTasks =
                            maybeNotificationEventSetupResult
                                |> Maybe.map (Tuple.second >> .startTasks)
                                |> Maybe.withDefault []

                        mergedStatusText =
                            continueSession.statusText
                                ++ "\n"
                                ++ Maybe.withDefault "" statusTextNotificationsAppendix

                        mergedNotifyWhenArrivedAtTime =
                            [ Just wrappedBotState.notifyWhenArrivedAtTime
                            , Maybe.map (Tuple.second >> .notifyWhenArrivedAtTime) maybeNotificationEventSetupResult
                            ]
                                |> List.filterMap identity
                                |> List.filterMap (Maybe.map .timeInMilliseconds)
                                |> List.minimum
                                |> Maybe.map (\timeInMilliseconds -> { timeInMilliseconds = timeInMilliseconds })

                        startTasks =
                            continueSession.startTasks
                                ++ notificationsSetupTasks
                                ++ notificationsTasks
                    in
                    InterfaceToHost.ContinueSession
                        { statusText = mergedStatusText
                        , startTasks = startTasks
                        , notifyWhenArrivedAtTime = mergedNotifyWhenArrivedAtTime
                        }

        notificationsCount =
            notificationsState.notificationsCount + List.length notificationsTasks
    in
    ( { timeInMilliseconds = event.timeInMilliseconds
      , wrappedBot = wrappedBotState
      , notifications =
            ( { notificationsState
                | notificationsCount = notificationsCount
                , queuedNotifications = remainingQueuedNotifications
                , startedNotifications = List.take 10 (startedNotifications ++ notificationsState.startedNotifications)
                , runningTasks = runningTasks
              }
            , notificationsLastResponse
            )
      }
    , mergedResponse
    )

{- This module contains a framework to build EVE Online bots and intel tools.
   Features:
   + Read from the game client using Sanderling memory reading (https://github.com/Arcitectus/Sanderling).
   + Play sounds.
   + Send mouse and keyboard input to the game client.
   + Transmit the bot configuration from the host.

   The framework automatically selects an EVE Online client process and finishes the session when that process disappears.
   To use the framework, import this module and use the `initState` and `processEvent` functions.
-}


module EveOnline.BotFramework exposing
    ( BotEffect(..)
    , BotEvent(..)
    , BotEventContext
    , BotEventWithContext
    , SetupState
    , StateIncludingSetup
    , VolatileHostState(..)
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import EveOnline.MemoryReading
import EveOnline.VolatileHostInterface as VolatileHostInterface
import EveOnline.VolatileHostScript as VolatileHostScript


type BotEvent
    = MemoryReadingCompleted EveOnline.MemoryReading.ParsedUserInterface


type alias BotEventContext =
    { timeInMilliseconds : Int
    , configuration : Maybe String
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotEventWithContext =
    { event : BotEvent
    , context : BotEventContext
    }


type BotEffect
    = EffectOnGameClientWindow VolatileHostInterface.EffectOnWindowStructure
    | EffectConsoleBeepSequence (List ConsoleBeepStructure)


type alias StateIncludingSetup simpleBotState =
    { setup : SetupState
    , botState : BotState simpleBotState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    , configuration : Maybe String
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotState simpleBotState =
    { simpleBotState : simpleBotState
    , lastEvent : Maybe { timeInMilliseconds : Int, eventResult : BotProcessEventResult simpleBotState }
    , effectQueue : BotEffectQueue
    }


type alias BotEffectQueue =
    List { timeInMilliseconds : Int, effect : BotEffect }


type alias SetupState =
    { volatileHost : Maybe ( InterfaceToHost.VolatileHostId, VolatileHostState )
    , lastRunScriptResult : Maybe (Result String InterfaceToHost.RunInVolatileHostComplete)
    , eveOnlineProcessesIds : Maybe (List Int)
    , lastMemoryReading : Maybe { timeInMilliseconds : Int, memoryReadingResult : VolatileHostInterface.GetMemoryReadingResultStructure }
    , memoryReadingDurations : List Int
    }


type VolatileHostState
    = Initial
    | SetupCompleted


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { buildTaskFromBotEffect : BotEffect -> InterfaceToHost.Task, getMemoryReadingTask : InterfaceToHost.Task }
    | FinishSession String


type alias BotProcessEventResult simpleBotState =
    { newState : simpleBotState
    , effects : List BotEffect
    , millisecondsToNextMemoryReading : Int
    , statusDescriptionText : String
    }


type alias ConsoleBeepStructure =
    { frequency : Int
    , durationInMs : Int
    }


initSetup : SetupState
initSetup =
    { volatileHost = Nothing
    , lastRunScriptResult = Nothing
    , eveOnlineProcessesIds = Nothing
    , lastMemoryReading = Nothing
    , memoryReadingDurations = []
    }


initState : simpleBotState -> StateIncludingSetup simpleBotState
initState simpleBotState =
    { setup = initSetup
    , botState =
        { simpleBotState = simpleBotState
        , lastEvent = Nothing
        , effectQueue = []
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    , configuration = Nothing
    , sessionTimeLimitInMilliseconds = Nothing
    }


processEvent :
    (BotEventWithContext -> simpleBotState -> BotProcessEventResult simpleBotState)
    -> InterfaceToHost.BotEvent
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEvent simpleBotProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotEvent ) =
            stateBeforeIntegratingEvent |> integrateFromHostEvent fromHostEvent

        ( state, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    processEventNotWaitingForTaskCompletion simpleBotProcessEvent maybeBotEvent stateBefore

                Just taskInProgress ->
                    ( stateBefore
                    , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 300 }
                      , startTasks = []
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        response =
            case responseBeforeAddingStatusMessage of
                InterfaceToHost.ContinueSession continueSession ->
                    { continueSession
                        | statusDescriptionText = statusMessagePrefix ++ continueSession.statusDescriptionText
                    }
                        |> InterfaceToHost.ContinueSession

                InterfaceToHost.FinishSession finishSession ->
                    { finishSession
                        | statusDescriptionText = statusMessagePrefix ++ finishSession.statusDescriptionText
                    }
                        |> InterfaceToHost.FinishSession
    in
    ( state, response )


processEventNotWaitingForTaskCompletion :
    (BotEventWithContext -> simpleBotState -> BotProcessEventResult simpleBotState)
    -> Maybe BotEventWithContext
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEventNotWaitingForTaskCompletion simpleBotProcessEvent maybeBotEvent stateBefore =
    case stateBefore.setup |> getNextSetupTask of
        ContinueSetup setupState setupTask setupTaskDescription ->
            let
                taskIndex =
                    stateBefore.lastTaskIndex + 1

                taskIdString =
                    "setup-" ++ (taskIndex |> String.fromInt)
            in
            ( { stateBefore
                | setup = setupState
                , lastTaskIndex = taskIndex
                , taskInProgress =
                    Just
                        { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                        , taskIdString = taskIdString
                        , taskDescription = setupTaskDescription
                        }
              }
            , { startTasks = [ { taskId = InterfaceToHost.taskIdFromString taskIdString, task = setupTask } ]
              , statusDescriptionText = "Continue setup: " ++ setupTaskDescription
              , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 1000 }
              }
                |> InterfaceToHost.ContinueSession
            )

        OperateBot operateBot ->
            let
                botStateBefore =
                    stateBefore.botState

                maybeSimpleBotEventResult =
                    maybeBotEvent
                        |> Maybe.map
                            (\botEvent -> botStateBefore.simpleBotState |> simpleBotProcessEvent botEvent)

                botStateBeforeProcessEffects =
                    case maybeSimpleBotEventResult of
                        Nothing ->
                            stateBefore.botState

                        Just simpleBotEventResult ->
                            let
                                effectQueue =
                                    simpleBotEventResult.effects
                                        |> List.map
                                            (\botEffect ->
                                                { timeInMilliseconds = stateBefore.timeInMilliseconds, effect = botEffect }
                                            )
                            in
                            { botStateBefore
                                | simpleBotState = simpleBotEventResult.newState
                                , lastEvent = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, eventResult = simpleBotEventResult }
                                , effectQueue = effectQueue
                            }

                ( botEffectQueue, botEffectTask ) =
                    case
                        botStateBeforeProcessEffects.effectQueue
                            |> dequeueNextEffectFromBotState { currentTimeInMs = stateBefore.timeInMilliseconds }
                    of
                        NoEffect ->
                            ( botStateBeforeProcessEffects.effectQueue, Nothing )

                        ForwardEffect forward ->
                            ( forward.newQueueState, forward.effect |> operateBot.buildTaskFromBotEffect |> Just )

                botState =
                    { botStateBeforeProcessEffects | effectQueue = botEffectQueue }

                timeForNextMemoryReadingGeneral =
                    (stateBefore.setup.lastMemoryReading |> Maybe.map .timeInMilliseconds |> Maybe.withDefault 0) + 10000

                timeForNextMemoryReadingFromBot =
                    botState.lastEvent
                        |> Maybe.map (\botLastEvent -> botLastEvent.timeInMilliseconds + botLastEvent.eventResult.millisecondsToNextMemoryReading)
                        |> Maybe.withDefault 0

                timeForNextMemoryReading =
                    min timeForNextMemoryReadingGeneral timeForNextMemoryReadingFromBot

                memoryReadingTasks =
                    if timeForNextMemoryReading < stateBefore.timeInMilliseconds then
                        [ operateBot.getMemoryReadingTask ]

                    else
                        []

                ( taskInProgress, startTasks ) =
                    (botEffectTask |> Maybe.map List.singleton |> Maybe.withDefault [])
                        ++ memoryReadingTasks
                        |> List.head
                        |> Maybe.map
                            (\task ->
                                let
                                    taskIdString =
                                        "operate-bot"
                                in
                                ( Just
                                    { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                                    , taskIdString = taskIdString
                                    , taskDescription = "From bot effect or memory reading."
                                    }
                                , [ { taskId = InterfaceToHost.taskIdFromString taskIdString, task = task } ]
                                )
                            )
                        |> Maybe.withDefault ( stateBefore.taskInProgress, [] )
            in
            ( { stateBefore | botState = botState, taskInProgress = taskInProgress }
            , { startTasks = startTasks
              , statusDescriptionText = "Operate bot."
              , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
              }
                |> InterfaceToHost.ContinueSession
            )

        FinishSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Finish session (" ++ reason ++ ")" }
            )


integrateFromHostEvent : InterfaceToHost.BotEvent -> StateIncludingSetup a -> ( StateIncludingSetup a, Maybe BotEventWithContext )
integrateFromHostEvent fromHostEvent stateBefore =
    let
        ( state, maybeBotEvent ) =
            case fromHostEvent of
                InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
                    ( { stateBefore | timeInMilliseconds = timeInMilliseconds }, Nothing )

                InterfaceToHost.CompletedTask taskComplete ->
                    let
                        ( setupState, maybeBotEventFromTaskComplete ) =
                            stateBefore.setup
                                |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
                    in
                    ( { stateBefore | setup = setupState, taskInProgress = Nothing }, maybeBotEventFromTaskComplete )

                InterfaceToHost.SetBotConfiguration newBotConfiguration ->
                    ( { stateBefore | configuration = Just newBotConfiguration }, Nothing )

                InterfaceToHost.SetSessionTimeLimit sessionTimeLimit ->
                    ( { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }, Nothing )
    in
    ( state
    , maybeBotEvent
        |> Maybe.map
            (\botEvent ->
                { event = botEvent
                , context =
                    { timeInMilliseconds = state.timeInMilliseconds
                    , configuration = state.configuration
                    , sessionTimeLimitInMilliseconds = state.sessionTimeLimitInMilliseconds
                    }
                }
            )
    )


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileHostResponse createVolatileHostResult ->
            case createVolatileHostResult of
                Err _ ->
                    ( setupStateBefore, Nothing )

                Ok createVolatileHostComplete ->
                    ( { setupStateBefore | volatileHost = Just ( createVolatileHostComplete.hostId, Initial ) }, Nothing )

        InterfaceToHost.RunInVolatileHostResponse runInVolatileHostResponse ->
            let
                runScriptResult =
                    runInVolatileHostResponse
                        |> Result.mapError
                            (\error ->
                                case error of
                                    InterfaceToHost.HostNotFound ->
                                        "HostNotFound"
                            )
                        |> Result.andThen
                            (\fromHostResult ->
                                case fromHostResult.exceptionToString of
                                    Nothing ->
                                        Ok fromHostResult

                                    Just exception ->
                                        Err ("Exception from host: " ++ exception)
                            )

                volatileHost =
                    case runInVolatileHostResponse of
                        Err _ ->
                            setupStateBefore.volatileHost

                        Ok runInVolatileHostComplete ->
                            setupStateBefore.volatileHost
                                |> Maybe.map (Tuple.mapSecond (updateVolatileHostState runInVolatileHostComplete))

                maybeResponseFromVolatileHost =
                    runScriptResult
                        |> Result.toMaybe
                        |> Maybe.andThen
                            (\fromHostResult ->
                                fromHostResult.returnValueToString
                                    |> Maybe.withDefault ""
                                    |> VolatileHostInterface.deserializeResponseFromVolatileHost
                                    |> Result.toMaybe
                                    |> Maybe.map (\responseFromVolatileHost -> { fromHostResult = fromHostResult, responseFromVolatileHost = responseFromVolatileHost })
                            )

                setupStateWithScriptRunResult =
                    { setupStateBefore
                        | lastRunScriptResult = Just runScriptResult
                        , volatileHost = volatileHost
                    }
            in
            case maybeResponseFromVolatileHost of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just { fromHostResult, responseFromVolatileHost } ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileHost
                            { timeInMilliseconds = timeInMilliseconds
                            , responseFromVolatileHost = responseFromVolatileHost
                            , runInVolatileHostDurationInMs = fromHostResult.durationInMilliseconds
                            }

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateResponseFromVolatileHost :
    { timeInMilliseconds : Int, responseFromVolatileHost : VolatileHostInterface.ResponseFromVolatileHost, runInVolatileHostDurationInMs : Int }
    -> SetupState
    -> ( SetupState, Maybe BotEvent )
integrateResponseFromVolatileHost { timeInMilliseconds, responseFromVolatileHost, runInVolatileHostDurationInMs } stateBefore =
    case responseFromVolatileHost of
        VolatileHostInterface.EveOnlineProcessesIds eveOnlineProcessesIds ->
            ( { stateBefore | eveOnlineProcessesIds = Just eveOnlineProcessesIds }, Nothing )

        VolatileHostInterface.GetMemoryReadingResult getMemoryReadingResult ->
            let
                memoryReadingDurations =
                    runInVolatileHostDurationInMs
                        :: stateBefore.memoryReadingDurations
                        |> List.take 10

                state =
                    { stateBefore
                        | lastMemoryReading = Just { timeInMilliseconds = timeInMilliseconds, memoryReadingResult = getMemoryReadingResult }
                        , memoryReadingDurations = memoryReadingDurations
                    }

                maybeBotEvent =
                    case getMemoryReadingResult of
                        VolatileHostInterface.ProcessNotFound ->
                            Nothing

                        VolatileHostInterface.Completed completedMemoryReading ->
                            let
                                maybeParsedMemoryReading =
                                    completedMemoryReading.serialRepresentationJson
                                        |> Maybe.andThen (EveOnline.MemoryReading.decodeMemoryReadingFromString >> Result.toMaybe)
                                        |> Maybe.map (EveOnline.MemoryReading.parseUITreeWithDisplayRegionFromUITree >> EveOnline.MemoryReading.parseUserInterfaceFromUITree)
                            in
                            maybeParsedMemoryReading
                                |> Maybe.map MemoryReadingCompleted
            in
            ( state, maybeBotEvent )


type NextBotEffectFromQueue
    = NoEffect
    | ForwardEffect { newQueueState : BotEffectQueue, effect : BotEffect }


dequeueNextEffectFromBotState : { currentTimeInMs : Int } -> BotEffectQueue -> NextBotEffectFromQueue
dequeueNextEffectFromBotState { currentTimeInMs } effectQueueBefore =
    case effectQueueBefore of
        [] ->
            NoEffect

        nextEntry :: remainingEntries ->
            ForwardEffect
                { newQueueState = remainingEntries
                , effect = nextEntry.effect
                }


getNextSetupTask : SetupState -> SetupTask
getNextSetupTask stateBefore =
    case stateBefore.volatileHost of
        Nothing ->
            ContinueSetup stateBefore InterfaceToHost.CreateVolatileHost "Create volatile host."

        Just ( volatileHostId, volatileHostState ) ->
            case volatileHostState of
                Initial ->
                    ContinueSetup stateBefore
                        (InterfaceToHost.RunInVolatileHost
                            { hostId = volatileHostId
                            , script = VolatileHostScript.setupScript
                            }
                        )
                        "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

                SetupCompleted ->
                    getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId


getSetupTaskWhenVolatileHostSetupCompleted : SetupState -> InterfaceToHost.VolatileHostId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId =
    case stateBefore.eveOnlineProcessesIds of
        Nothing ->
            ContinueSetup stateBefore
                (InterfaceToHost.RunInVolatileHost
                    { hostId = volatileHostId
                    , script = VolatileHostInterface.buildScriptToGetResponseFromVolatileHost VolatileHostInterface.GetEveOnlineProcessesIds
                    }
                )
                "Get ids of EVE Online client processes."

        Just eveOnlineProcessesIds ->
            case eveOnlineProcessesIds |> List.head of
                Nothing ->
                    FinishSession "I did not find an EVE Online client process."

                Just eveOnlineProcessId ->
                    case stateBefore.lastMemoryReading of
                        Nothing ->
                            ContinueSetup stateBefore
                                (InterfaceToHost.RunInVolatileHost
                                    { hostId = volatileHostId
                                    , script =
                                        VolatileHostInterface.buildScriptToGetResponseFromVolatileHost
                                            (VolatileHostInterface.GetMemoryReading { processId = eveOnlineProcessId })
                                    }
                                )
                                "Get the first memory reading from the EVE Online client process. This can take several seconds."

                        Just lastMemoryReadingTime ->
                            case lastMemoryReadingTime.memoryReadingResult of
                                VolatileHostInterface.ProcessNotFound ->
                                    FinishSession "The EVE Online client process disappeared."

                                VolatileHostInterface.Completed lastCompletedMemoryReading ->
                                    let
                                        buildTaskFromRequestToVolatileHost requestToVolatileHost =
                                            InterfaceToHost.RunInVolatileHost
                                                { hostId = volatileHostId
                                                , script = VolatileHostInterface.buildScriptToGetResponseFromVolatileHost requestToVolatileHost
                                                }
                                    in
                                    OperateBot
                                        { buildTaskFromBotEffect =
                                            \effect ->
                                                case effect of
                                                    EffectOnGameClientWindow effectOnWindow ->
                                                        { windowId = lastCompletedMemoryReading.mainWindowId
                                                        , task = effectOnWindow
                                                        , bringWindowToForeground = True
                                                        }
                                                            |> VolatileHostInterface.EffectOnWindow
                                                            |> buildTaskFromRequestToVolatileHost

                                                    EffectConsoleBeepSequence consoleBeepSequence ->
                                                        consoleBeepSequence
                                                            |> VolatileHostInterface.EffectConsoleBeepSequence
                                                            |> buildTaskFromRequestToVolatileHost
                                        , getMemoryReadingTask =
                                            VolatileHostInterface.GetMemoryReading { processId = eveOnlineProcessId } |> buildTaskFromRequestToVolatileHost
                                        }


updateVolatileHostState : InterfaceToHost.RunInVolatileHostComplete -> VolatileHostState -> VolatileHostState
updateVolatileHostState runInVolatileHostComplete stateBefore =
    case runInVolatileHostComplete.returnValueToString of
        Nothing ->
            stateBefore

        Just returnValueString ->
            case stateBefore of
                Initial ->
                    if returnValueString |> String.contains "Setup Completed" then
                        SetupCompleted

                    else
                        stateBefore

                SetupCompleted ->
                    stateBefore


runScriptResultDisplayString : Result String InterfaceToHost.RunInVolatileHostComplete -> { string : String, isErr : Bool }
runScriptResultDisplayString result =
    case result of
        Err error ->
            { string = "Error: " ++ error, isErr = True }

        Ok runInVolatileHostComplete ->
            { string = "Success: " ++ (runInVolatileHostComplete.returnValueToString |> Maybe.withDefault "null"), isErr = False }


statusReportFromState : StateIncludingSetup s -> String
statusReportFromState state =
    let
        fromBot =
            state.botState.lastEvent |> Maybe.map (.eventResult >> .statusDescriptionText) |> Maybe.withDefault ""

        lastScriptRunResult =
            "Last script run result is: "
                ++ (state.setup.lastRunScriptResult
                        |> Maybe.map runScriptResultDisplayString
                        |> Maybe.map
                            (\runScriptResult ->
                                runScriptResult.string
                                    |> stringEllipsis
                                        (if runScriptResult.isErr then
                                            640

                                         else
                                            140
                                        )
                                        "...."
                            )
                        |> Maybe.withDefault "Nothing"
                   )

        botEffectQueueLength =
            state.botState.effectQueue |> List.length

        memoryReadingDurations =
            state.setup.memoryReadingDurations
                -- Don't consider the first memory reading because it takes much longer.
                |> List.reverse
                |> List.drop 1

        averageMemoryReadingDuration =
            (memoryReadingDurations |> List.sum)
                // (memoryReadingDurations |> List.length)

        runtimeExpensesReport =
            "amrd=" ++ (averageMemoryReadingDuration |> String.fromInt) ++ "ms"

        botEffectQueueLengthWarning =
            if botEffectQueueLength < 4 then
                []

            else
                [ "Bot effect queue length is " ++ (botEffectQueueLength |> String.fromInt) ]
    in
    [ fromBot
    , "----"
    , "EVE Online framework status:"

    -- , runtimeExpensesReport
    , lastScriptRunResult
    ]
        ++ botEffectQueueLengthWarning
        |> String.join "\n"


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

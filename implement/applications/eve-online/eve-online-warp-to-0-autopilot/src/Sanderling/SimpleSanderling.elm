{- This module contains a framework to build EVE Online bots.
   The framework automatically selects an EVE Online client process and finishes the bot session when that process disappears.
   To use the framework, import this module and use the `initState` and `processEvent` functions.
-}


module Sanderling.SimpleSanderling exposing
    ( BotEvent(..)
    , BotEventAtTime
    , BotRequest(..)
    , SetupState
    , StateIncludingSetup
    , VolatileHostState(..)
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import Sanderling.MemoryReading
import Sanderling.Sanderling as Sanderling
import Sanderling.SanderlingVolatileHostSetup as SanderlingVolatileHostSetup


type alias BotEventAtTime =
    { timeInMilliseconds : Int
    , event : BotEvent
    }


type BotEvent
    = MemoryReadingCompleted Sanderling.MemoryReading.ParsedUserInterface
    | SetBotConfiguration String


type BotRequest
    = EffectOnGameClientWindow Sanderling.EffectOnWindowStructure
    | ConsoleBeepSequenceRequest (List ConsoleBeepStructure)


type alias StateIncludingSetup simpleBotState =
    { setup : SetupState
    , botState : BotState simpleBotState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    }


type alias BotState simpleBotState =
    { simpleBotState : simpleBotState
    , lastEvent : Maybe { timeInMilliseconds : Int, eventResult : BotProcessEventResult simpleBotState }
    , requestQueue : BotRequestQueue
    }


type alias BotRequestQueue =
    List { timeInMilliseconds : Int, request : BotRequest }


type alias SetupState =
    { volatileHost : Maybe ( InterfaceToHost.VolatileHostId, VolatileHostState )
    , lastRunScriptResult : Maybe (Result String InterfaceToHost.RunInVolatileHostComplete)
    , eveOnlineProcessesIds : Maybe (List Int)
    , lastMemoryReading : Maybe { timeInMilliseconds : Int, memoryReadingResult : Sanderling.GetMemoryReadingResultStructure }
    , memoryReadingDurations : List Int
    }


type VolatileHostState
    = Initial
    | SanderlingSetupCompleted


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { buildTaskFromBotRequest : BotRequest -> InterfaceToHost.Task, getMemoryReadingTask : InterfaceToHost.Task }
    | FinishSession String


type alias BotProcessEventResult simpleBotState =
    { newState : simpleBotState
    , requests : List BotRequest
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
        , requestQueue = []
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    }


processEvent :
    (BotEventAtTime -> simpleBotState -> BotProcessEventResult simpleBotState)
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
    (BotEventAtTime -> simpleBotState -> BotProcessEventResult simpleBotState)
    -> Maybe BotEventAtTime
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

                botStateBeforeRequest =
                    case maybeSimpleBotEventResult of
                        Nothing ->
                            stateBefore.botState

                        Just simpleBotEventResult ->
                            let
                                requestQueue =
                                    simpleBotEventResult.requests
                                        |> List.map
                                            (\botRequest ->
                                                { timeInMilliseconds = stateBefore.timeInMilliseconds, request = botRequest }
                                            )
                            in
                            { botStateBefore
                                | simpleBotState = simpleBotEventResult.newState
                                , lastEvent = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, eventResult = simpleBotEventResult }
                                , requestQueue = requestQueue
                            }

                ( botRequestQueue, botRequestTask ) =
                    case
                        botStateBeforeRequest.requestQueue
                            |> dequeueNextRequestFromBotState { currentTimeInMs = stateBefore.timeInMilliseconds }
                    of
                        NoRequest ->
                            ( botStateBeforeRequest.requestQueue, Nothing )

                        ForwardRequest forward ->
                            ( forward.newQueueState, forward.request |> operateBot.buildTaskFromBotRequest |> Just )

                botState =
                    { botStateBeforeRequest | requestQueue = botRequestQueue }

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
                    (botRequestTask |> Maybe.map List.singleton |> Maybe.withDefault [])
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
                                    , taskDescription = "From bot request or memory reading."
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


integrateFromHostEvent : InterfaceToHost.BotEvent -> StateIncludingSetup a -> ( StateIncludingSetup a, Maybe BotEventAtTime )
integrateFromHostEvent fromHostEvent stateBefore =
    case fromHostEvent of
        InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
            ( { stateBefore | timeInMilliseconds = timeInMilliseconds }, Nothing )

        InterfaceToHost.CompletedTask taskComplete ->
            let
                ( setupState, maybeBotEvent ) =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
                        |> Tuple.mapSecond
                            (Maybe.map
                                (\botEvent ->
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds, event = botEvent }
                                )
                            )
            in
            ( { stateBefore | setup = setupState, taskInProgress = Nothing }, maybeBotEvent )

        InterfaceToHost.SetBotConfiguration newBotConfiguration ->
            ( stateBefore
            , Just { timeInMilliseconds = stateBefore.timeInMilliseconds, event = SetBotConfiguration newBotConfiguration }
            )

        InterfaceToHost.SetSessionTimeLimit _ ->
            ( stateBefore, Nothing )


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
                                    |> Sanderling.deserializeResponseFromVolatileHost
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
                        |> integrateSanderlingResponseFromVolatileHost
                            { timeInMilliseconds = timeInMilliseconds
                            , responseFromVolatileHost = responseFromVolatileHost
                            , runInVolatileHostDurationInMs = fromHostResult.durationInMilliseconds
                            }

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateSanderlingResponseFromVolatileHost :
    { timeInMilliseconds : Int, responseFromVolatileHost : Sanderling.ResponseFromVolatileHost, runInVolatileHostDurationInMs : Int }
    -> SetupState
    -> ( SetupState, Maybe BotEvent )
integrateSanderlingResponseFromVolatileHost { timeInMilliseconds, responseFromVolatileHost, runInVolatileHostDurationInMs } stateBefore =
    case responseFromVolatileHost of
        Sanderling.EveOnlineProcessesIds eveOnlineProcessesIds ->
            ( { stateBefore | eveOnlineProcessesIds = Just eveOnlineProcessesIds }, Nothing )

        Sanderling.GetMemoryReadingResult getMemoryReadingResult ->
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
                        Sanderling.ProcessNotFound ->
                            Nothing

                        Sanderling.Completed completedMemoryReading ->
                            let
                                maybeParsedMemoryReading =
                                    completedMemoryReading.serialRepresentationJson
                                        |> Maybe.andThen (Sanderling.MemoryReading.decodeMemoryReadingFromString >> Result.toMaybe)
                                        |> Maybe.map (Sanderling.MemoryReading.parseUITreeWithDisplayRegionFromUITree >> Sanderling.MemoryReading.parseUserInterfaceFromUITree)
                            in
                            maybeParsedMemoryReading
                                |> Maybe.map MemoryReadingCompleted
            in
            ( state, maybeBotEvent )


type NextBotRequestFromQueue
    = NoRequest
    | ForwardRequest { newQueueState : BotRequestQueue, request : BotRequest }


dequeueNextRequestFromBotState : { currentTimeInMs : Int } -> BotRequestQueue -> NextBotRequestFromQueue
dequeueNextRequestFromBotState { currentTimeInMs } requestQueueBefore =
    case requestQueueBefore of
        [] ->
            NoRequest

        nextEntry :: remainingEntries ->
            ForwardRequest
                { newQueueState = remainingEntries
                , request = nextEntry.request
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
                            , script = SanderlingVolatileHostSetup.sanderlingSetupScript
                            }
                        )
                        "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

                SanderlingSetupCompleted ->
                    getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId


getSetupTaskWhenVolatileHostSetupCompleted : SetupState -> InterfaceToHost.VolatileHostId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId =
    case stateBefore.eveOnlineProcessesIds of
        Nothing ->
            ContinueSetup stateBefore
                (InterfaceToHost.RunInVolatileHost
                    { hostId = volatileHostId
                    , script = Sanderling.buildScriptToGetResponseFromVolatileHost Sanderling.GetEveOnlineProcessesIds
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
                                        Sanderling.buildScriptToGetResponseFromVolatileHost
                                            (Sanderling.GetMemoryReading { processId = eveOnlineProcessId })
                                    }
                                )
                                "Get the first memory reading from the EVE Online client process. This can take several seconds."

                        Just lastMemoryReadingTime ->
                            case lastMemoryReadingTime.memoryReadingResult of
                                Sanderling.ProcessNotFound ->
                                    FinishSession "The EVE Online client process disappeared."

                                Sanderling.Completed lastCompletedMemoryReading ->
                                    let
                                        buildTaskFromRequestToVolatileHost requestToVolatileHost =
                                            InterfaceToHost.RunInVolatileHost
                                                { hostId = volatileHostId
                                                , script = Sanderling.buildScriptToGetResponseFromVolatileHost requestToVolatileHost
                                                }
                                    in
                                    OperateBot
                                        { buildTaskFromBotRequest =
                                            \request ->
                                                case request of
                                                    EffectOnGameClientWindow effect ->
                                                        { windowId = lastCompletedMemoryReading.mainWindowId
                                                        , task = effect
                                                        , bringWindowToForeground = True
                                                        }
                                                            |> Sanderling.EffectOnWindow
                                                            |> buildTaskFromRequestToVolatileHost

                                                    ConsoleBeepSequenceRequest consoleBeepSequence ->
                                                        consoleBeepSequence
                                                            |> Sanderling.ConsoleBeepSequenceRequest
                                                            |> buildTaskFromRequestToVolatileHost
                                        , getMemoryReadingTask =
                                            Sanderling.GetMemoryReading { processId = eveOnlineProcessId } |> buildTaskFromRequestToVolatileHost
                                        }


updateVolatileHostState : InterfaceToHost.RunInVolatileHostComplete -> VolatileHostState -> VolatileHostState
updateVolatileHostState runInVolatileHostComplete stateBefore =
    case runInVolatileHostComplete.returnValueToString of
        Nothing ->
            stateBefore

        Just returnValueString ->
            case stateBefore of
                Initial ->
                    if returnValueString |> String.contains "Sanderling Setup Completed" then
                        SanderlingSetupCompleted

                    else
                        stateBefore

                SanderlingSetupCompleted ->
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

        botRequestQueueLength =
            state.botState.requestQueue |> List.length

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

        botRequestQueueLengthWarning =
            if botRequestQueueLength < 4 then
                []

            else
                [ "Bot request queue length is " ++ (botRequestQueueLength |> String.fromInt) ]
    in
    [ fromBot
    , "----"
    , "EVE Online framework status:"

    -- , runtimeExpensesReport
    , lastScriptRunResult
    ]
        ++ botRequestQueueLengthWarning
        |> String.join "\n"


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

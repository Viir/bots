{- This module contains a framework to build simple EVE Online bots.
   This framework automatically selects an EVE Online client process and finishes the bot session when that process disappears.
   To use this framework, import this module and use the `initState` and `processEvent` functions.
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
import Sanderling.Sanderling as Sanderling
import Sanderling.SanderlingMemoryMeasurement as SanderlingMemoryMeasurement
import Sanderling.SanderlingVolatileHostSetup as SanderlingVolatileHostSetup


type alias BotEventAtTime =
    { timeInMilliseconds : Int
    , event : BotEvent
    }


type BotEvent
    = MemoryMeasurementCompleted SanderlingMemoryMeasurement.MemoryMeasurementReducedWithNamedNodes
    | SetBotConfiguration String


type BotRequest
    = TakeMemoryMeasurementAfterDelayInMilliseconds Int
    | EffectOnGameClientWindow Sanderling.EffectOnWindowStructure


type alias StateIncludingSetup simpleBotState =
    { setup : SetupState
    , botState : BotState simpleBotState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    }


type alias BotState simpleBotState =
    { simpleBotState : simpleBotState
    , statusMessage : Maybe String
    , requestQueue : BotRequestQueue
    }


type alias BotRequestQueue =
    { queuedRequests : List ( Int, BotRequest )
    , lastForwardedRequestTask : Maybe BotRequestTaskState
    }


type BotRequestTaskState
    = Started { taskId : Int }
    | Completed { taskId : Int }


type alias SetupState =
    { volatileHost : Maybe ( InterfaceToHost.VolatileHostId, VolatileHostState )
    , lastRunScriptResult : Maybe (Result String (Maybe String))
    , eveOnlineProcessesIds : Maybe (List Int)
    , lastMemoryMeasurement : Maybe ( Int, Sanderling.GetMemoryMeasurementResultStructure )
    }


type VolatileHostState
    = Initial
    | SanderlingSetupCompleted


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { taskFromBotRequest : BotRequest -> InterfaceToHost.Task }
    | FinishSession String


initSetup : SetupState
initSetup =
    { volatileHost = Nothing
    , lastRunScriptResult = Nothing
    , eveOnlineProcessesIds = Nothing
    , lastMemoryMeasurement = Nothing
    }


initState : simpleBotState -> StateIncludingSetup simpleBotState
initState simpleBotState =
    { setup = initSetup
    , botState =
        { simpleBotState = simpleBotState
        , statusMessage = Nothing
        , requestQueue =
            { queuedRequests = []
            , lastForwardedRequestTask = Nothing
            }
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    }


processEvent :
    (BotEventAtTime -> simpleBotState -> { newState : simpleBotState, requests : List BotRequest, statusMessage : String })
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
                    processEventNotWaitingForTask simpleBotProcessEvent maybeBotEvent stateBefore

                Just taskInProgress ->
                    ( stateBefore
                    , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 300 }
                      , startTasks = []
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\n\nCurrent activity: "

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


processEventNotWaitingForTask :
    (BotEventAtTime -> simpleBotState -> { newState : simpleBotState, requests : List BotRequest, statusMessage : String })
    -> Maybe BotEventAtTime
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, InterfaceToHost.BotResponse )
processEventNotWaitingForTask simpleBotProcessEvent maybeBotEvent stateBefore =
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
                                requestQueueBefore =
                                    botStateBefore.requestQueue

                                requestQueue =
                                    { requestQueueBefore
                                        | queuedRequests =
                                            simpleBotEventResult.requests
                                                |> List.map (\botRequest -> ( stateBefore.timeInMilliseconds, botRequest ))
                                    }
                            in
                            { botStateBefore
                                | simpleBotState = simpleBotEventResult.newState
                                , statusMessage = Just simpleBotEventResult.statusMessage
                                , requestQueue = requestQueue
                            }

                ( botRequestQueue, operateBotRequestTask ) =
                    case
                        botStateBeforeRequest.requestQueue
                            |> dequeueNextRequestFromBotState { currentTimeInMs = stateBefore.timeInMilliseconds }
                    of
                        NoRequest ->
                            let
                                timeForNewMemoryMeasurement =
                                    case stateBefore.setup.lastMemoryMeasurement of
                                        Nothing ->
                                            True

                                        Just ( lastMemoryMeasurementTime, _ ) ->
                                            lastMemoryMeasurementTime + 10000 < stateBefore.timeInMilliseconds

                                memoryMeasurementTask =
                                    if timeForNewMemoryMeasurement then
                                        Just (operateBot.taskFromBotRequest (TakeMemoryMeasurementAfterDelayInMilliseconds 0))

                                    else
                                        Nothing
                            in
                            ( botStateBeforeRequest.requestQueue, memoryMeasurementTask )

                        WaitForNextRequest { durationInMilliseconds } ->
                            ( botStateBeforeRequest.requestQueue
                            , Nothing
                            )

                        ForwardRequest forward ->
                            ( forward.newQueueState, forward.request |> operateBot.taskFromBotRequest |> Just )

                operateBotRequestStartTasks =
                    operateBotRequestTask
                        |> Maybe.map (\task -> { taskId = InterfaceToHost.taskIdFromString "operate-bot", task = task })
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []

                botState =
                    { botStateBeforeRequest | requestQueue = botRequestQueue }
            in
            ( { stateBefore | botState = botState }
            , { startTasks = operateBotRequestStartTasks
              , statusDescriptionText = "Operate bot:\n" ++ (botState.statusMessage |> Maybe.withDefault "")
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
integrateTaskResult ( time, taskResult ) setupStateBefore =
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
                                        Ok fromHostResult.returnValueToString

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
                        |> Maybe.andThen identity
                        |> Maybe.map Sanderling.deserializeResponseFromVolatileHost
                        |> Maybe.andThen Result.toMaybe

                setupStateWithScriptRunResult =
                    { setupStateBefore
                        | lastRunScriptResult = Just runScriptResult
                        , volatileHost = volatileHost
                    }
            in
            case maybeResponseFromVolatileHost of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileHost ->
                    setupStateWithScriptRunResult
                        |> integrateSanderlingResponseFromVolatileHost ( time, responseFromVolatileHost )

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateSanderlingResponseFromVolatileHost : ( Int, Sanderling.ResponseFromVolatileHost ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateSanderlingResponseFromVolatileHost ( time, response ) stateBefore =
    case response of
        Sanderling.EveOnlineProcessesIds eveOnlineProcessesIds ->
            ( { stateBefore | eveOnlineProcessesIds = Just eveOnlineProcessesIds }, Nothing )

        Sanderling.GetMemoryMeasurementResult getMemoryMeasurementResult ->
            let
                state =
                    { stateBefore | lastMemoryMeasurement = Just ( time, getMemoryMeasurementResult ) }

                maybeBotEvent =
                    case getMemoryMeasurementResult of
                        Sanderling.ProcessNotFound ->
                            Nothing

                        Sanderling.Completed completedMemoryMeasurement ->
                            let
                                maybeParsedMemoryMeasurement =
                                    completedMemoryMeasurement.reducedWithNamedNodesJson
                                        |> Maybe.andThen (SanderlingMemoryMeasurement.parseMemoryMeasurementReducedWithNamedNodesFromJson >> Result.toMaybe)
                            in
                            maybeParsedMemoryMeasurement
                                |> Maybe.map MemoryMeasurementCompleted
            in
            ( state, maybeBotEvent )


type NextBotRequestFromQueue
    = NoRequest
    | WaitForNextRequest { durationInMilliseconds : Int }
    | ForwardRequest { newQueueState : BotRequestQueue, request : BotRequest }


dequeueNextRequestFromBotState : { currentTimeInMs : Int } -> BotRequestQueue -> NextBotRequestFromQueue
dequeueNextRequestFromBotState { currentTimeInMs } stateBefore =
    case stateBefore.queuedRequests |> List.head of
        Nothing ->
            NoRequest

        Just ( queueTime, nextRequest ) ->
            let
                timeToWaitToNextRequest =
                    case nextRequest of
                        TakeMemoryMeasurementAfterDelayInMilliseconds delayInMs ->
                            queueTime + delayInMs - currentTimeInMs

                        EffectOnGameClientWindow _ ->
                            0
            in
            if timeToWaitToNextRequest <= 0 then
                ForwardRequest
                    { newQueueState =
                        { stateBefore | queuedRequests = stateBefore.queuedRequests |> List.tail |> Maybe.withDefault [] }
                    , request = nextRequest
                    }

            else
                WaitForNextRequest { durationInMilliseconds = timeToWaitToNextRequest }


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
                    case stateBefore.lastMemoryMeasurement of
                        Nothing ->
                            ContinueSetup stateBefore
                                (InterfaceToHost.RunInVolatileHost
                                    { hostId = volatileHostId
                                    , script =
                                        Sanderling.buildScriptToGetResponseFromVolatileHost
                                            (Sanderling.GetMemoryMeasurement { processId = eveOnlineProcessId })
                                    }
                                )
                                "Get the first memory reading from the EVE Online client process. This can take several seconds."

                        Just ( lastMemoryMeasurementTime, lastMemoryMeasurement ) ->
                            case lastMemoryMeasurement of
                                Sanderling.ProcessNotFound ->
                                    FinishSession "The EVE Online client process disappeared."

                                Sanderling.Completed lastCompletedMemoryMeasurement ->
                                    -- TODO: FinishSession when memory reading failed.
                                    OperateBot
                                        { taskFromBotRequest =
                                            \request ->
                                                let
                                                    requestToVolatileHost =
                                                        case request of
                                                            TakeMemoryMeasurementAfterDelayInMilliseconds _ ->
                                                                Sanderling.GetMemoryMeasurement { processId = eveOnlineProcessId }

                                                            EffectOnGameClientWindow effect ->
                                                                Sanderling.EffectOnWindow
                                                                    { windowId = lastCompletedMemoryMeasurement.mainWindowId
                                                                    , task = effect
                                                                    , bringWindowToForeground = True
                                                                    }
                                                in
                                                InterfaceToHost.RunInVolatileHost
                                                    { hostId = volatileHostId
                                                    , script = Sanderling.buildScriptToGetResponseFromVolatileHost requestToVolatileHost
                                                    }
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


runScriptResultDisplayString : Result String (Maybe String) -> String
runScriptResultDisplayString result =
    case result of
        Err error ->
            "Error: " ++ error

        Ok successResult ->
            "Success: " ++ (successResult |> Maybe.withDefault "null")


statusReportFromState : StateIncludingSetup s -> String
statusReportFromState state =
    let
        lastScriptRunResult =
            "Last Sanderling script run result is: "
                ++ (state.setup.lastRunScriptResult |> Maybe.map (runScriptResultDisplayString >> stringEllipsis 140 "....") |> Maybe.withDefault "Nothing")

        botRequestQueueLength =
            state.botState.requestQueue.queuedRequests |> List.length

        botRequestQueueLengthWarning =
            if botRequestQueueLength < 4 then
                []

            else
                [ "Bot request queue length is " ++ (botRequestQueueLength |> String.fromInt) ]
    in
    [ lastScriptRunResult ]
        ++ botRequestQueueLengthWarning
        |> List.intersperse "\n"
        |> List.foldl (++) ""


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

{- This module contains a framework to build simple EVE Online bots.
   This framework automatically selects an EVE Online client process and finishes the bot session when that process disappears.
   To use this framework, import this module and use the `initState` and `processEvent` functions.
-}


module SimpleSanderling exposing
    ( BotEvent(..)
    , BotEventAtTime
    , BotRequest(..)
    , SetupState
    , StateIncludingSetup
    , VolatileHostState(..)
    , initState
    , processEvent
    )

import Bot_Interface_To_Host_20190529 as InterfaceToHost
import Sanderling
import SanderlingMemoryMeasurement
import SanderlingVolatileHostSetup


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
    { volatileHost : Maybe ( String, VolatileHostState )
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
    }


processEvent :
    (BotEventAtTime -> simpleBotState -> { newState : simpleBotState, requests : List BotRequest, statusMessage : String })
    -> InterfaceToHost.BotEventAtTime
    -> StateIncludingSetup simpleBotState
    -> ( StateIncludingSetup simpleBotState, List InterfaceToHost.BotRequest )
processEvent simpleBotProcessEvent fromHostEventAtTime stateBefore =
    let
        ( setupStateAfterIntegratingEvent, maybeBotEvent ) =
            stateBefore.setup |> integrateFromHostEvent fromHostEventAtTime

        stateAfterIntegratingEvent =
            { stateBefore | setup = setupStateAfterIntegratingEvent }

        ( state, ( request, currentActivityMessage ) ) =
            case stateAfterIntegratingEvent.setup |> getNextSetupTask of
                ContinueSetup setupState setupTask setupTaskDescription ->
                    ( { stateAfterIntegratingEvent | setup = setupState }
                    , ( { taskId = "setup", task = setupTask } |> InterfaceToHost.StartTask
                      , "Continue setup: " ++ setupTaskDescription
                      )
                    )

                OperateBot operateBot ->
                    let
                        botStateBefore =
                            stateAfterIntegratingEvent.botState

                        maybeSimpleBotEventResult =
                            maybeBotEvent
                                |> Maybe.map
                                    (\botEvent -> botStateBefore.simpleBotState |> simpleBotProcessEvent botEvent)

                        botStateBeforeRequest =
                            case maybeSimpleBotEventResult of
                                Nothing ->
                                    stateAfterIntegratingEvent.botState

                                Just simpleBotEventResult ->
                                    let
                                        requestQueueBefore =
                                            botStateBefore.requestQueue

                                        requestQueue =
                                            { requestQueueBefore
                                                | queuedRequests =
                                                    simpleBotEventResult.requests
                                                        |> List.map (\botRequest -> ( fromHostEventAtTime.timeInMilliseconds, botRequest ))
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
                                    |> dequeueNextRequestFromBotState { currentTimeInMs = fromHostEventAtTime.timeInMilliseconds }
                            of
                                NoRequest ->
                                    let
                                        timeForNewMemoryMeasurement =
                                            case stateBefore.setup.lastMemoryMeasurement of
                                                Nothing ->
                                                    True

                                                Just ( lastMemoryMeasurementTime, _ ) ->
                                                    lastMemoryMeasurementTime + 10000 < fromHostEventAtTime.timeInMilliseconds

                                        task =
                                            if timeForNewMemoryMeasurement then
                                                operateBot.taskFromBotRequest (TakeMemoryMeasurementAfterDelayInMilliseconds 0)

                                            else
                                                InterfaceToHost.Delay { milliseconds = 3000 }
                                    in
                                    ( botStateBeforeRequest.requestQueue, task )

                                WaitForNextRequest { durationInMilliseconds } ->
                                    ( botStateBeforeRequest.requestQueue
                                    , InterfaceToHost.Delay { milliseconds = durationInMilliseconds |> min 4000 }
                                    )

                                ForwardRequest forward ->
                                    ( forward.newQueueState, forward.request |> operateBot.taskFromBotRequest )

                        operateBotRequest =
                            InterfaceToHost.StartTask
                                { taskId = "operate-bot", task = operateBotRequestTask }

                        botState =
                            { botStateBeforeRequest | requestQueue = botRequestQueue }
                    in
                    ( { stateAfterIntegratingEvent | botState = botState }
                    , ( operateBotRequest, "Operate bot:\n" ++ (botState.statusMessage |> Maybe.withDefault "") )
                    )

                FinishSession reason ->
                    ( stateAfterIntegratingEvent
                    , ( InterfaceToHost.FinishSession, "Finish session (" ++ reason ++ ")" )
                    )

        statusMessage =
            (state |> statusReportFromState)
                ++ "\nCurrent activity: "
                ++ currentActivityMessage

        requests =
            [ request, InterfaceToHost.SetStatusMessage statusMessage ]
    in
    ( state, requests )


integrateFromHostEvent : InterfaceToHost.BotEventAtTime -> SetupState -> ( SetupState, Maybe BotEventAtTime )
integrateFromHostEvent fromHostEventAtTime setupStateBefore =
    case fromHostEventAtTime.event of
        InterfaceToHost.TaskComplete taskComplete ->
            integrateTaskResult ( fromHostEventAtTime.timeInMilliseconds, taskComplete.taskResult ) setupStateBefore
                |> Tuple.mapSecond
                    (Maybe.map
                        (\botEvent ->
                            { timeInMilliseconds = fromHostEventAtTime.timeInMilliseconds, event = botEvent }
                        )
                    )

        InterfaceToHost.SetSessionTimeLimitInMilliseconds _ ->
            ( setupStateBefore, Nothing )

        InterfaceToHost.SetBotConfiguration newBotConfiguration ->
            ( setupStateBefore
            , Just { timeInMilliseconds = fromHostEventAtTime.timeInMilliseconds, event = SetBotConfiguration newBotConfiguration }
            )


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
                    getSetupTaskWhenVolatileHostSetupCompleted stateBefore { volatileHostId = volatileHostId }


getSetupTaskWhenVolatileHostSetupCompleted : SetupState -> { volatileHostId : String } -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted stateBefore { volatileHostId } =
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


stringFromVolatileHostState : VolatileHostState -> String
stringFromVolatileHostState volatileHostState =
    case volatileHostState of
        Initial ->
            "Initial"

        SanderlingSetupCompleted ->
            "SanderlingSetupCompleted"


statusReportFromState : StateIncludingSetup s -> String
statusReportFromState state =
    let
        lastScriptRunResult =
            "Last script run result is: "
                ++ (state.setup.lastRunScriptResult |> Maybe.map (runScriptResultDisplayString >> stringEllipsis 500 "....") |> Maybe.withDefault "Nothing")

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

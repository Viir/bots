{- This module contains a framework to build EVE Online bots and intel tools.
   Features:
   + Read from the game client using Sanderling memory reading and parse the user interface from the memory reading (https://github.com/Arcitectus/Sanderling).
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
    , BotEventResponse(..)
    , SetupState
    , StateIncludingFramework
    , getEntropyIntFromUserInterface
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200213 as InterfaceToHost
import Common.FNV
import Dict
import EveOnline.MemoryReading
import EveOnline.VolatileHostInterface as VolatileHostInterface
import EveOnline.VolatileHostScript as VolatileHostScript


type BotEvent
    = MemoryReadingCompleted EveOnline.MemoryReading.ParsedUserInterface


type BotEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession { statusDescriptionText : String }


type alias ContinueSessionStructure =
    { effects : List BotEffect
    , millisecondsToNextReadingFromGame : Int
    , statusDescriptionText : String
    }


type BotEffect
    = EffectOnGameClientWindow VolatileHostInterface.EffectOnWindowStructure
    | EffectConsoleBeepSequence (List ConsoleBeepStructure)


type alias BotEventContext =
    { timeInMilliseconds : Int
    , configuration : Maybe String
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias StateIncludingFramework botState =
    { setup : SetupState
    , botState : BotAndLastEventState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    , configuration : Maybe String
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotAndLastEventState botState =
    { botState : botState
    , lastEvent : Maybe { timeInMilliseconds : Int, eventResult : ( botState, BotEventResponse ) }
    , effectQueue : BotEffectQueue
    }


type alias BotEffectQueue =
    List { timeInMilliseconds : Int, effect : BotEffect }


type alias SetupState =
    { createVolatileHostResult : Maybe (Result InterfaceToHost.CreateVolatileHostErrorStructure InterfaceToHost.CreateVolatileHostComplete)
    , lastRequestToVolatileHostResult : Maybe (Result String InterfaceToHost.RequestToVolatileHostComplete)
    , eveOnlineProcessesIds : Maybe (List Int)
    , searchUIRootAddressResult : Maybe VolatileHostInterface.SearchUIRootAddressResultStructure
    , lastMemoryReading : Maybe { timeInMilliseconds : Int, memoryReadingResult : VolatileHostInterface.GetMemoryReadingResultStructure }
    , memoryReadingDurations : List Int
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot { buildTaskFromBotEffect : BotEffect -> InterfaceToHost.Task, getMemoryReadingTask : InterfaceToHost.Task }
    | FrameworkStopSession String


type alias ConsoleBeepStructure =
    { frequency : Int
    , durationInMs : Int
    }


initSetup : SetupState
initSetup =
    { createVolatileHostResult = Nothing
    , lastRequestToVolatileHostResult = Nothing
    , eveOnlineProcessesIds = Nothing
    , searchUIRootAddressResult = Nothing
    , lastMemoryReading = Nothing
    , memoryReadingDurations = []
    }


initState : botState -> StateIncludingFramework botState
initState botState =
    { setup = initSetup
    , botState =
        { botState = botState
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
    (BotEventContext -> BotEvent -> botState -> ( botState, BotEventResponse ))
    -> InterfaceToHost.BotEvent
    -> StateIncludingFramework botState
    -> ( StateIncludingFramework botState, InterfaceToHost.BotResponse )
processEvent botProcessEvent fromHostEvent stateBeforeIntegratingEvent =
    let
        ( stateBefore, maybeBotEvent ) =
            stateBeforeIntegratingEvent |> integrateFromHostEvent fromHostEvent

        ( state, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    processEventNotWaitingForTaskCompletion botProcessEvent maybeBotEvent stateBefore

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
    (BotEventContext -> BotEvent -> botState -> ( botState, BotEventResponse ))
    -> Maybe ( BotEvent, BotEventContext )
    -> StateIncludingFramework botState
    -> ( StateIncludingFramework botState, InterfaceToHost.BotResponse )
processEventNotWaitingForTaskCompletion botProcessEvent maybeBotEvent stateBefore =
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

                maybeBotEventResult =
                    maybeBotEvent
                        |> Maybe.map
                            (\( botEvent, botEventContext ) -> botStateBefore.botState |> botProcessEvent botEventContext botEvent)

                botStateBeforeProcessEffects =
                    case maybeBotEventResult of
                        Nothing ->
                            stateBefore.botState

                        Just ( newBotState, botEventResponse ) ->
                            let
                                effectQueue =
                                    case botEventResponse of
                                        FinishSession _ ->
                                            []

                                        ContinueSession continueSessionResponse ->
                                            continueSessionResponse.effects
                                                |> List.map
                                                    (\botEffect ->
                                                        { timeInMilliseconds = stateBefore.timeInMilliseconds, effect = botEffect }
                                                    )
                            in
                            { botStateBefore
                                | botState = newBotState
                                , lastEvent = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, eventResult = ( newBotState, botEventResponse ) }
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
                        |> Maybe.andThen
                            (\botLastEvent ->
                                case botLastEvent.eventResult |> Tuple.second of
                                    ContinueSession continueSessionResponse ->
                                        Just (botLastEvent.timeInMilliseconds + continueSessionResponse.millisecondsToNextReadingFromGame)

                                    FinishSession _ ->
                                        Nothing
                            )
                        |> Maybe.withDefault 0

                timeForNextMemoryReading =
                    min timeForNextMemoryReadingGeneral timeForNextMemoryReadingFromBot

                memoryReadingTasks =
                    if timeForNextMemoryReading < stateBefore.timeInMilliseconds then
                        [ operateBot.getMemoryReadingTask ]

                    else
                        []

                botFinishesSession =
                    botState.lastEvent
                        |> Maybe.map
                            (\botLastEvent ->
                                case botLastEvent.eventResult |> Tuple.second of
                                    ContinueSession _ ->
                                        False

                                    FinishSession _ ->
                                        True
                            )
                        |> Maybe.withDefault False

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

                state =
                    { stateBefore | botState = botState, taskInProgress = taskInProgress }
            in
            if botFinishesSession then
                ( state, { statusDescriptionText = "The app finished the session." } |> InterfaceToHost.FinishSession )

            else
                ( state
                , { startTasks = startTasks
                  , statusDescriptionText = "Operate bot."
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
                  }
                    |> InterfaceToHost.ContinueSession
                )

        FrameworkStopSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Stop session (" ++ reason ++ ")" }
            )


integrateFromHostEvent : InterfaceToHost.BotEvent -> StateIncludingFramework a -> ( StateIncludingFramework a, Maybe ( BotEvent, BotEventContext ) )
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
                ( botEvent
                , { timeInMilliseconds = state.timeInMilliseconds
                  , configuration = state.configuration
                  , sessionTimeLimitInMilliseconds = state.sessionTimeLimitInMilliseconds
                  }
                )
            )
    )


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe BotEvent )
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileHostResponse createVolatileHostResult ->
            ( { setupStateBefore | createVolatileHostResult = Just createVolatileHostResult }, Nothing )

        InterfaceToHost.RequestToVolatileHostResponse requestToVolatileHostResponse ->
            let
                requestToVolatileHostResult =
                    requestToVolatileHostResponse
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

                maybeResponseFromVolatileHost =
                    requestToVolatileHostResult
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
                    { setupStateBefore | lastRequestToVolatileHostResult = Just requestToVolatileHostResult }
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

        VolatileHostInterface.SearchUIRootAddressResult searchUIRootAddressResult ->
            let
                state =
                    { stateBefore | searchUIRootAddressResult = Just searchUIRootAddressResult }
            in
            ( state, Nothing )

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
    case stateBefore.createVolatileHostResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileHost { script = VolatileHostScript.setupScript })
                "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FrameworkStopSession ("Create volatile host failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileHostComplete) ->
            getSetupTaskWhenVolatileHostSetupCompleted stateBefore createVolatileHostComplete.hostId


getSetupTaskWhenVolatileHostSetupCompleted : SetupState -> InterfaceToHost.VolatileHostId -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted stateBefore volatileHostId =
    case stateBefore.searchUIRootAddressResult of
        Nothing ->
            case stateBefore.eveOnlineProcessesIds of
                Nothing ->
                    ContinueSetup stateBefore
                        (InterfaceToHost.RequestToVolatileHost
                            { hostId = volatileHostId
                            , request =
                                VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                    VolatileHostInterface.GetEveOnlineProcessesIds
                            }
                        )
                        "Get ids of EVE Online client processes."

                Just eveOnlineProcessesIds ->
                    case eveOnlineProcessesIds |> List.head of
                        Nothing ->
                            FrameworkStopSession "I did not find an EVE Online client process."

                        Just eveOnlineProcessId ->
                            ContinueSetup stateBefore
                                (InterfaceToHost.RequestToVolatileHost
                                    { hostId = volatileHostId
                                    , request =
                                        VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                            (VolatileHostInterface.SearchUIRootAddress { processId = eveOnlineProcessId })
                                    }
                                )
                                ("Search the address of the UI root in process " ++ (eveOnlineProcessId |> String.fromInt))

        Just searchResult ->
            case searchResult.uiRootAddress of
                Nothing ->
                    FrameworkStopSession ("Did not find the UI root in process " ++ (searchResult.processId |> String.fromInt))

                Just uiRootAddress ->
                    let
                        getMemoryReadingRequest =
                            VolatileHostInterface.GetMemoryReading { processId = searchResult.processId, uiRootAddress = uiRootAddress }
                    in
                    case stateBefore.lastMemoryReading of
                        Nothing ->
                            ContinueSetup stateBefore
                                (InterfaceToHost.RequestToVolatileHost
                                    { hostId = volatileHostId
                                    , request =
                                        VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost getMemoryReadingRequest
                                    }
                                )
                                "Get the first memory reading from the EVE Online client process. This can take several seconds."

                        Just lastMemoryReadingTime ->
                            case lastMemoryReadingTime.memoryReadingResult of
                                VolatileHostInterface.ProcessNotFound ->
                                    FrameworkStopSession "The EVE Online client process disappeared."

                                VolatileHostInterface.Completed lastCompletedMemoryReading ->
                                    let
                                        buildTaskFromRequestToVolatileHost requestToVolatileHost =
                                            InterfaceToHost.RequestToVolatileHost
                                                { hostId = volatileHostId
                                                , request = VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost requestToVolatileHost
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
                                        , getMemoryReadingTask = getMemoryReadingRequest |> buildTaskFromRequestToVolatileHost
                                        }


requestToVolatileHostResultDisplayString : Result String InterfaceToHost.RequestToVolatileHostComplete -> { string : String, isErr : Bool }
requestToVolatileHostResultDisplayString result =
    case result of
        Err error ->
            { string = "Error: " ++ error, isErr = True }

        Ok runInVolatileHostComplete ->
            { string = "Success: " ++ (runInVolatileHostComplete.returnValueToString |> Maybe.withDefault "null"), isErr = False }


statusReportFromState : StateIncludingFramework s -> String
statusReportFromState state =
    let
        fromBot =
            state.botState.lastEvent
                |> Maybe.map
                    (\lastEvent ->
                        case lastEvent.eventResult |> Tuple.second of
                            FinishSession finishSession ->
                                finishSession.statusDescriptionText

                            ContinueSession continueSession ->
                                continueSession.statusDescriptionText
                    )
                |> Maybe.withDefault ""

        lastResultFromVolatileHost =
            "Last result from volatile host is: "
                ++ (state.setup.lastRequestToVolatileHostResult
                        |> Maybe.map requestToVolatileHostResultDisplayString
                        |> Maybe.map
                            (\resultDisplayInfo ->
                                resultDisplayInfo.string
                                    |> stringEllipsis
                                        (if resultDisplayInfo.isErr then
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
    , lastResultFromVolatileHost
    ]
        ++ botEffectQueueLengthWarning
        |> String.join "\n"


getEntropyIntFromUserInterface : EveOnline.MemoryReading.ParsedUserInterface -> Int
getEntropyIntFromUserInterface parsedUserInterface =
    let
        entropyFromString =
            Common.FNV.hashString

        entropyFromUiElement uiElement =
            [ uiElement.uiNode.pythonObjectAddress |> entropyFromString
            , uiElement.totalDisplayRegion.x
            , uiElement.totalDisplayRegion.y
            , uiElement.totalDisplayRegion.width
            , uiElement.totalDisplayRegion.height
            ]

        entropyFromOverviewEntry overviewEntry =
            (overviewEntry.cellsTexts |> Dict.values |> List.map entropyFromString)
                ++ (overviewEntry.uiNode |> entropyFromUiElement)

        entropyFromProbeScanResult probeScanResult =
            [ probeScanResult.uiNode |> entropyFromUiElement, probeScanResult.textsLeftToRight |> List.map entropyFromString ]
                |> List.concat

        fromMenus =
            parsedUserInterface.contextMenus
                |> List.concatMap (.entries >> List.map .uiNode)
                |> List.concatMap entropyFromUiElement

        fromOverview =
            parsedUserInterface.overviewWindow
                |> EveOnline.MemoryReading.maybeNothingFromCanNotSeeIt
                |> Maybe.map .entries
                |> Maybe.withDefault []
                |> List.concatMap entropyFromOverviewEntry

        fromProbeScanner =
            parsedUserInterface.probeScannerWindow
                |> EveOnline.MemoryReading.maybeNothingFromCanNotSeeIt
                |> Maybe.map .scanResults
                |> Maybe.withDefault []
                |> List.concatMap entropyFromProbeScanResult
    in
    (fromMenus ++ fromOverview ++ fromProbeScanner) |> List.sum


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

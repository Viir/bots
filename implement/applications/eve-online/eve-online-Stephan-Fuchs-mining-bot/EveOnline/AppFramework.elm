{- This module contains a framework to build EVE Online bots and intel tools.
   Features:
   + Read from the game client using Sanderling memory reading and parse the user interface from the memory reading (https://github.com/Arcitectus/Sanderling).
   + Play sounds.
   + Send mouse and keyboard input to the game client.
   + Parse the app-settings and inform the user about the result.

   The framework automatically selects an EVE Online client process and finishes the session when that process disappears.
   When multiple game clients are open, the framework prioritizes the one with the topmost window. This approach helps users control which game client is picked by an app.
   To use the framework, import this module and use the `initState` and `processEvent` functions.
-}


module EveOnline.AppFramework exposing (..)

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import Common.Basics
import Common.DecisionTree
import Common.EffectOnWindow
import Common.FNV
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion)
import EveOnline.VolatileHostInterface as VolatileHostInterface
import EveOnline.VolatileHostScript as VolatileHostScript
import List.Extra
import String.Extra


type alias AppConfiguration appSettings appState =
    { parseAppSettings : String -> Result String appSettings
    , selectGameClientInstance : Maybe appSettings -> List GameClientProcessSummary -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
    , processEvent : AppEventContext appSettings -> AppEvent -> appState -> ( appState, AppEventResponse )
    }


type AppEvent
    = ReadingFromGameClientCompleted EveOnline.ParseUserInterface.ParsedUserInterface


type AppEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession { statusDescriptionText : String }


type alias ContinueSessionStructure =
    { effects : List AppEffect
    , millisecondsToNextReadingFromGame : Int
    , statusDescriptionText : String
    }


type AppEffect
    = EffectOnGameClientWindow Common.EffectOnWindow.EffectOnWindowStructure
    | EffectConsoleBeepSequence (List ConsoleBeepStructure)


type alias AppEventContext appSettings =
    { timeInMilliseconds : Int
    , appSettings : appSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias StateIncludingFramework appSettings appState =
    { setup : SetupState
    , appState : AppAndLastEventState appState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    , appSettings : Maybe appSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias AppAndLastEventState appState =
    { appState : appState
    , lastEvent : Maybe { timeInMilliseconds : Int, eventResult : ( appState, AppEventResponse ) }
    , effectQueue : AppEffectQueue
    }


type alias AppEffectQueue =
    List { timeInMilliseconds : Int, effect : AppEffect }


type alias SetupState =
    { createVolatileHostResult : Maybe (Result InterfaceToHost.CreateVolatileHostErrorStructure InterfaceToHost.CreateVolatileHostComplete)
    , requestsToVolatileHostCount : Int
    , lastRequestToVolatileHostResult : Maybe (Result String InterfaceToHost.RequestToVolatileHostComplete)
    , gameClientProcesses : Maybe (List GameClientProcessSummary)
    , searchUIRootAddressResult : Maybe VolatileHostInterface.SearchUIRootAddressResultStructure
    , lastMemoryReading : Maybe { timeInMilliseconds : Int, memoryReadingResult : VolatileHostInterface.GetMemoryReadingResultStructure }
    , memoryReadingDurations : List Int
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateApp
        { buildTaskFromAppEffect : AppEffect -> InterfaceToHost.Task
        , getMemoryReadingTask : InterfaceToHost.Task
        , releaseVolatileHostTask : InterfaceToHost.Task
        }
    | FrameworkStopSession String


type alias ConsoleBeepStructure =
    { frequency : Int
    , durationInMs : Int
    }


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias GameClientProcessSummary =
    VolatileHostInterface.GameClientProcessSummaryStruct


type alias ShipModulesMemory =
    { tooltipFromModuleButton : Dict.Dict String EveOnline.ParseUserInterface.ModuleButtonTooltip
    , lastReadingTooltip : Maybe EveOnline.ParseUserInterface.ModuleButtonTooltip
    }


volatileHostRecycleInterval : Int
volatileHostRecycleInterval =
    400


initShipModulesMemory : ShipModulesMemory
initShipModulesMemory =
    { tooltipFromModuleButton = Dict.empty
    , lastReadingTooltip = Nothing
    }


integrateCurrentReadingsIntoShipModulesMemory : EveOnline.ParseUserInterface.ParsedUserInterface -> ShipModulesMemory -> ShipModulesMemory
integrateCurrentReadingsIntoShipModulesMemory currentReading memoryBefore =
    let
        getTooltipDataForEqualityComparison tooltip =
            tooltip.uiNode
                |> EveOnline.ParseUserInterface.getAllContainedDisplayTextsWithRegion
                |> List.map (Tuple.mapSecond .totalDisplayRegion)

        {- To ensure robustness, we store a new tooltip only when the display texts match in two consecutive readings from the game client. -}
        tooltipAvailableToStore =
            case ( memoryBefore.lastReadingTooltip, currentReading.moduleButtonTooltip ) of
                ( Just previousTooltip, Just currentTooltip ) ->
                    if getTooltipDataForEqualityComparison previousTooltip == getTooltipDataForEqualityComparison currentTooltip then
                        Just currentTooltip

                    else
                        Nothing

                _ ->
                    Nothing

        visibleModuleButtons =
            currentReading.shipUI
                |> Maybe.map .moduleButtons
                |> Maybe.withDefault []

        visibleModuleButtonsIds =
            visibleModuleButtons |> List.map getModuleButtonIdentifierInMemory

        maybeModuleButtonWithHighlight =
            visibleModuleButtons
                |> List.filter .isHiliteVisible
                |> List.head

        tooltipFromModuleButtonAddition =
            case ( tooltipAvailableToStore, maybeModuleButtonWithHighlight ) of
                ( Just tooltip, Just moduleButtonWithHighlight ) ->
                    Dict.insert (moduleButtonWithHighlight |> getModuleButtonIdentifierInMemory) tooltip

                _ ->
                    identity

        tooltipFromModuleButton =
            memoryBefore.tooltipFromModuleButton
                |> tooltipFromModuleButtonAddition
                |> Dict.filter (\moduleButtonId _ -> visibleModuleButtonsIds |> List.member moduleButtonId)
    in
    { tooltipFromModuleButton = tooltipFromModuleButton
    , lastReadingTooltip = currentReading.moduleButtonTooltip
    }


getModuleButtonTooltipFromModuleButton : ShipModulesMemory -> EveOnline.ParseUserInterface.ShipUIModuleButton -> Maybe EveOnline.ParseUserInterface.ModuleButtonTooltip
getModuleButtonTooltipFromModuleButton moduleMemory moduleButton =
    moduleMemory.tooltipFromModuleButton |> Dict.get (moduleButton |> getModuleButtonIdentifierInMemory)


getModuleButtonIdentifierInMemory : EveOnline.ParseUserInterface.ShipUIModuleButton -> String
getModuleButtonIdentifierInMemory =
    .uiNode >> .uiNode >> .pythonObjectAddress


initSetup : SetupState
initSetup =
    { createVolatileHostResult = Nothing
    , requestsToVolatileHostCount = 0
    , lastRequestToVolatileHostResult = Nothing
    , gameClientProcesses = Nothing
    , searchUIRootAddressResult = Nothing
    , lastMemoryReading = Nothing
    , memoryReadingDurations = []
    }


initState : appState -> StateIncludingFramework appSettings appState
initState appState =
    { setup = initSetup
    , appState =
        { appState = appState
        , lastEvent = Nothing
        , effectQueue = []
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    , appSettings = Nothing
    , sessionTimeLimitInMilliseconds = Nothing
    }


processEvent :
    AppConfiguration appSettings appState
    -> InterfaceToHost.AppEvent
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEvent appConfiguration fromHostEvent stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = fromHostEvent.timeInMilliseconds }

        continueAfterIntegrateEvent =
            processEventAfterIntegrateEvent appConfiguration
    in
    case fromHostEvent.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            continueAfterIntegrateEvent Nothing stateBefore

        InterfaceToHost.TaskCompletedEvent taskComplete ->
            let
                ( setupState, maybeAppEventFromTaskComplete ) =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
            in
            continueAfterIntegrateEvent
                maybeAppEventFromTaskComplete
                { stateBefore | setup = setupState, taskInProgress = Nothing }

        InterfaceToHost.AppSettingsChangedEvent appSettings ->
            case appConfiguration.parseAppSettings appSettings of
                Err parseSettingsError ->
                    ( stateBefore
                    , InterfaceToHost.FinishSession
                        { statusDescriptionText = "Failed to parse these app-settings: " ++ parseSettingsError }
                    )

                Ok parsedAppSettings ->
                    ( { stateBefore | appSettings = Just parsedAppSettings }
                    , InterfaceToHost.ContinueSession
                        { statusDescriptionText = "Succeeded parsing these app-settings."
                        , startTasks = []
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = 0 }
                        }
                    )

        InterfaceToHost.SessionDurationPlannedEvent sessionTimeLimit ->
            continueAfterIntegrateEvent
                Nothing
                { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }


processEventAfterIntegrateEvent :
    AppConfiguration appSettings appState
    -> Maybe AppEvent
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEventAfterIntegrateEvent appConfiguration maybeAppEvent stateBefore =
    let
        ( state, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    case stateBefore.appSettings of
                        Nothing ->
                            ( stateBefore
                            , InterfaceToHost.FinishSession
                                { statusDescriptionText =
                                    "Unexpected order of events: I did not receive any app-settings changed event."
                                }
                            )

                        Just appSettings ->
                            processEventNotWaitingForTaskCompletion
                                appConfiguration
                                (maybeAppEvent
                                    |> Maybe.map
                                        (\appEvent ->
                                            ( appEvent
                                            , { timeInMilliseconds = stateBefore.timeInMilliseconds
                                              , appSettings = appSettings
                                              , sessionTimeLimitInMilliseconds = stateBefore.sessionTimeLimitInMilliseconds
                                              }
                                            )
                                        )
                                )
                                stateBefore

                Just taskInProgress ->
                    ( stateBefore
                    , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                      , startTasks = []
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        statusMessagePrefix =
            (state |> statusReportFromState) ++ "\nCurrent activity: "

        notifyWhenArrivedAtTimeUpperBound =
            stateBefore.timeInMilliseconds + 2000

        response =
            case responseBeforeAddingStatusMessage of
                InterfaceToHost.ContinueSession continueSession ->
                    { continueSession
                        | statusDescriptionText = statusMessagePrefix ++ continueSession.statusDescriptionText
                        , notifyWhenArrivedAtTime =
                            Just
                                { timeInMilliseconds =
                                    continueSession.notifyWhenArrivedAtTime
                                        |> Maybe.map .timeInMilliseconds
                                        |> Maybe.withDefault notifyWhenArrivedAtTimeUpperBound
                                        |> min notifyWhenArrivedAtTimeUpperBound
                                }
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
    AppConfiguration appSettings appState
    -> Maybe ( AppEvent, AppEventContext appSettings )
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEventNotWaitingForTaskCompletion appConfiguration maybeAppEvent stateBefore =
    case stateBefore.setup |> getNextSetupTask appConfiguration stateBefore.appSettings of
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
              , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
              }
                |> InterfaceToHost.ContinueSession
            )

        OperateApp operateApp ->
            if volatileHostRecycleInterval < stateBefore.setup.requestsToVolatileHostCount then
                let
                    taskIndex =
                        stateBefore.lastTaskIndex + 1

                    taskIdString =
                        "maintain-" ++ (taskIndex |> String.fromInt)

                    setupStateBefore =
                        stateBefore.setup

                    setupState =
                        { setupStateBefore | createVolatileHostResult = Nothing }

                    setupTaskDescription =
                        "Recycle the volatile host after " ++ (setupStateBefore.requestsToVolatileHostCount |> String.fromInt) ++ " requests."
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
                , { startTasks =
                        [ { taskId = InterfaceToHost.taskIdFromString taskIdString
                          , task = operateApp.releaseVolatileHostTask
                          }
                        ]
                  , statusDescriptionText = "Continue setup: " ++ setupTaskDescription
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                  }
                    |> InterfaceToHost.ContinueSession
                )

            else
                let
                    appStateBefore =
                        stateBefore.appState

                    maybeAppEventResult =
                        maybeAppEvent
                            |> Maybe.map
                                (\( appEvent, appEventContext ) -> appStateBefore.appState |> appConfiguration.processEvent appEventContext appEvent)

                    appStateBeforeProcessEffects =
                        case maybeAppEventResult of
                            Nothing ->
                                stateBefore.appState

                            Just ( newAppState, appEventResponse ) ->
                                let
                                    effectQueue =
                                        case appEventResponse of
                                            FinishSession _ ->
                                                []

                                            ContinueSession continueSessionResponse ->
                                                continueSessionResponse.effects
                                                    |> List.map
                                                        (\appEffect ->
                                                            { timeInMilliseconds = stateBefore.timeInMilliseconds, effect = appEffect }
                                                        )
                                in
                                { appStateBefore
                                    | appState = newAppState
                                    , lastEvent = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, eventResult = ( newAppState, appEventResponse ) }
                                    , effectQueue = effectQueue
                                }

                    ( appEffectQueue, appEffectTask ) =
                        case
                            appStateBeforeProcessEffects.effectQueue
                                |> dequeueNextEffectFromAppState { currentTimeInMs = stateBefore.timeInMilliseconds }
                        of
                            NoEffect ->
                                ( appStateBeforeProcessEffects.effectQueue, Nothing )

                            ForwardEffect forward ->
                                ( forward.newQueueState, forward.effect |> operateApp.buildTaskFromAppEffect |> Just )

                    appState =
                        { appStateBeforeProcessEffects | effectQueue = appEffectQueue }

                    timeForNextReadingFromGameGeneral =
                        (stateBefore.setup.lastMemoryReading |> Maybe.map .timeInMilliseconds |> Maybe.withDefault 0) + 10000

                    timeForNextReadingFromGameFromApp =
                        appState.lastEvent
                            |> Maybe.andThen
                                (\appLastEvent ->
                                    case appLastEvent.eventResult |> Tuple.second of
                                        ContinueSession continueSessionResponse ->
                                            Just (appLastEvent.timeInMilliseconds + continueSessionResponse.millisecondsToNextReadingFromGame)

                                        FinishSession _ ->
                                            Nothing
                                )
                            |> Maybe.withDefault 0

                    timeForNextReadingFromGame =
                        min timeForNextReadingFromGameGeneral timeForNextReadingFromGameFromApp

                    remainingTimeToNextReadingFromGame =
                        timeForNextReadingFromGame - stateBefore.timeInMilliseconds

                    memoryReadingTasks =
                        if remainingTimeToNextReadingFromGame <= 0 then
                            [ operateApp.getMemoryReadingTask ]

                        else
                            []

                    appFinishesSession =
                        appState.lastEvent
                            |> Maybe.map
                                (\appLastEvent ->
                                    case appLastEvent.eventResult |> Tuple.second of
                                        ContinueSession _ ->
                                            False

                                        FinishSession _ ->
                                            True
                                )
                            |> Maybe.withDefault False

                    ( taskInProgress, startTasks ) =
                        (appEffectTask |> Maybe.map List.singleton |> Maybe.withDefault [])
                            ++ memoryReadingTasks
                            |> List.head
                            |> Maybe.map
                                (\task ->
                                    let
                                        taskIdString =
                                            "operate-app"
                                    in
                                    ( Just
                                        { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                                        , taskIdString = taskIdString
                                        , taskDescription = "From app effect or memory reading."
                                        }
                                    , [ { taskId = InterfaceToHost.taskIdFromString taskIdString, task = task } ]
                                    )
                                )
                            |> Maybe.withDefault ( stateBefore.taskInProgress, [] )

                    setupStateBefore =
                        stateBefore.setup

                    setupState =
                        { setupStateBefore
                            | requestsToVolatileHostCount = setupStateBefore.requestsToVolatileHostCount + (startTasks |> List.length)
                        }

                    state =
                        { stateBefore | setup = setupState, appState = appState, taskInProgress = taskInProgress }
                in
                if appFinishesSession then
                    ( state, { statusDescriptionText = "The app finished the session." } |> InterfaceToHost.FinishSession )

                else
                    ( state
                    , { startTasks = startTasks
                      , statusDescriptionText = "Operate app."
                      , notifyWhenArrivedAtTime =
                            if taskInProgress == Nothing then
                                Just { timeInMilliseconds = timeForNextReadingFromGame }

                            else
                                Nothing
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        FrameworkStopSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Stop session (" ++ reason ++ ")" }
            )


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe AppEvent )
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileHostResponse createVolatileHostResult ->
            ( { setupStateBefore
                | createVolatileHostResult = Just createVolatileHostResult
                , requestsToVolatileHostCount = 0
              }
            , Nothing
            )

        InterfaceToHost.RequestToVolatileHostResponse (Err InterfaceToHost.HostNotFound) ->
            ( { setupStateBefore | createVolatileHostResult = Nothing }, Nothing )

        InterfaceToHost.RequestToVolatileHostResponse (Ok requestResult) ->
            let
                requestToVolatileHostResult =
                    case requestResult.exceptionToString of
                        Nothing ->
                            Ok requestResult

                        Just exception ->
                            Err ("Exception from host: " ++ exception)

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
    -> ( SetupState, Maybe AppEvent )
integrateResponseFromVolatileHost { timeInMilliseconds, responseFromVolatileHost, runInVolatileHostDurationInMs } stateBefore =
    case responseFromVolatileHost of
        VolatileHostInterface.ListGameClientProcessesResponse gameClientProcesses ->
            ( { stateBefore | gameClientProcesses = Just gameClientProcesses }, Nothing )

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

                maybeAppEvent =
                    case getMemoryReadingResult of
                        VolatileHostInterface.ProcessNotFound ->
                            Nothing

                        VolatileHostInterface.Completed completedMemoryReading ->
                            let
                                maybeParsedMemoryReading =
                                    completedMemoryReading.serialRepresentationJson
                                        |> Maybe.andThen (EveOnline.MemoryReading.decodeMemoryReadingFromString >> Result.toMaybe)
                                        |> Maybe.map (EveOnline.ParseUserInterface.parseUITreeWithDisplayRegionFromUITree >> EveOnline.ParseUserInterface.parseUserInterfaceFromUITree)
                            in
                            maybeParsedMemoryReading
                                |> Maybe.map ReadingFromGameClientCompleted
            in
            ( state, maybeAppEvent )


type NextAppEffectFromQueue
    = NoEffect
    | ForwardEffect { newQueueState : AppEffectQueue, effect : AppEffect }


dequeueNextEffectFromAppState : { currentTimeInMs : Int } -> AppEffectQueue -> NextAppEffectFromQueue
dequeueNextEffectFromAppState _ effectQueueBefore =
    case effectQueueBefore of
        [] ->
            NoEffect

        nextEntry :: remainingEntries ->
            ForwardEffect
                { newQueueState = remainingEntries
                , effect = nextEntry.effect
                }


getNextSetupTask :
    AppConfiguration appSettings appState
    -> Maybe appSettings
    -> SetupState
    -> SetupTask
getNextSetupTask appConfiguration appSettings stateBefore =
    case stateBefore.createVolatileHostResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileHost { script = VolatileHostScript.setupScript })
                "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FrameworkStopSession ("Create volatile host failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileHostComplete) ->
            getSetupTaskWhenVolatileHostSetupCompleted appConfiguration appSettings stateBefore createVolatileHostComplete.hostId


getSetupTaskWhenVolatileHostSetupCompleted :
    AppConfiguration appSettings appState
    -> Maybe appSettings
    -> SetupState
    -> InterfaceToHost.VolatileHostId
    -> SetupTask
getSetupTaskWhenVolatileHostSetupCompleted appConfiguration appSettings stateBefore volatileHostId =
    case stateBefore.searchUIRootAddressResult of
        Nothing ->
            case stateBefore.gameClientProcesses of
                Nothing ->
                    ContinueSetup stateBefore
                        (InterfaceToHost.RequestToVolatileHost
                            { hostId = volatileHostId
                            , request =
                                VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                    VolatileHostInterface.ListGameClientProcessesRequest
                            }
                        )
                        "Get list of EVE Online client processes."

                Just gameClientProcesses ->
                    case gameClientProcesses |> appConfiguration.selectGameClientInstance appSettings of
                        Err selectGameClientProcessError ->
                            FrameworkStopSession ("Failed to select the game client process: " ++ selectGameClientProcessError)

                        Ok gameClientSelection ->
                            ContinueSetup stateBefore
                                (InterfaceToHost.RequestToVolatileHost
                                    { hostId = volatileHostId
                                    , request =
                                        VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                            (VolatileHostInterface.SearchUIRootAddress { processId = gameClientSelection.selectedProcess.processId })
                                    }
                                )
                                ((("Search the address of the UI root in process "
                                    ++ (gameClientSelection.selectedProcess.processId |> String.fromInt)
                                  )
                                    :: gameClientSelection.report
                                 )
                                    |> String.join "\n"
                                )

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
                                    OperateApp
                                        { buildTaskFromAppEffect =
                                            \effect ->
                                                case effect of
                                                    EffectOnGameClientWindow effectOnWindow ->
                                                        { windowId = lastCompletedMemoryReading.mainWindowId
                                                        , task = effectOnWindow |> effectOnWindowAsVolatileHostEffectOnWindow
                                                        , bringWindowToForeground = True
                                                        }
                                                            |> VolatileHostInterface.EffectOnWindow
                                                            |> buildTaskFromRequestToVolatileHost

                                                    EffectConsoleBeepSequence consoleBeepSequence ->
                                                        consoleBeepSequence
                                                            |> VolatileHostInterface.EffectConsoleBeepSequence
                                                            |> buildTaskFromRequestToVolatileHost
                                        , getMemoryReadingTask = getMemoryReadingRequest |> buildTaskFromRequestToVolatileHost
                                        , releaseVolatileHostTask = InterfaceToHost.ReleaseVolatileHost { hostId = volatileHostId }
                                        }


effectOnWindowAsVolatileHostEffectOnWindow : Common.EffectOnWindow.EffectOnWindowStructure -> VolatileHostInterface.EffectOnWindowStructure
effectOnWindowAsVolatileHostEffectOnWindow effectOnWindow =
    case effectOnWindow of
        Common.EffectOnWindow.MouseMoveTo mouseMoveTo ->
            VolatileHostInterface.MouseMoveTo { location = mouseMoveTo }

        Common.EffectOnWindow.KeyDown key ->
            VolatileHostInterface.KeyDown key

        Common.EffectOnWindow.KeyUp key ->
            VolatileHostInterface.KeyUp key


selectGameClientInstanceWithTopmostWindow :
    List GameClientProcessSummary
    -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
selectGameClientInstanceWithTopmostWindow gameClientProcesses =
    case gameClientProcesses |> List.sortBy .mainWindowZIndex |> List.head of
        Nothing ->
            Err "I did not find an EVE Online client process."

        Just selectedProcess ->
            let
                report =
                    if [ selectedProcess ] == gameClientProcesses then
                        []

                    else
                        [ "I found "
                            ++ (gameClientProcesses |> List.length |> String.fromInt)
                            ++ " game client processes. I selected process "
                            ++ (selectedProcess.processId |> String.fromInt)
                            ++ " ('"
                            ++ selectedProcess.mainWindowTitle
                            ++ "') because its main window was the topmost."
                        ]
            in
            Ok { selectedProcess = selectedProcess, report = report }


selectGameClientInstanceWithPilotName :
    String
    -> List GameClientProcessSummary
    -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
selectGameClientInstanceWithPilotName pilotName gameClientProcesses =
    if gameClientProcesses |> List.isEmpty then
        Err "I did not find an EVE Online client process."

    else
        case
            gameClientProcesses
                |> List.filter (.mainWindowTitle >> String.toLower >> String.contains (pilotName |> String.toLower))
                |> List.head
        of
            Nothing ->
                Err
                    ("I did not find an EVE Online client process for the pilot name '"
                        ++ pilotName
                        ++ "'. Here is a list of window names of the visible game client instances: "
                        ++ (gameClientProcesses |> List.map (.mainWindowTitle >> String.Extra.surround "'") |> String.join ", ")
                    )

            Just selectedProcess ->
                let
                    report =
                        if [ selectedProcess ] == gameClientProcesses then
                            []

                        else
                            [ "I found "
                                ++ (gameClientProcesses |> List.length |> String.fromInt)
                                ++ " game client processes. I selected process "
                                ++ (selectedProcess.processId |> String.fromInt)
                                ++ " ('"
                                ++ selectedProcess.mainWindowTitle
                                ++ "') because its main window title matches the given pilot name."
                            ]
                in
                Ok { selectedProcess = selectedProcess, report = report }


requestToVolatileHostResultDisplayString : Result String InterfaceToHost.RequestToVolatileHostComplete -> { string : String, isErr : Bool }
requestToVolatileHostResultDisplayString result =
    case result of
        Err error ->
            { string = "Error: " ++ error, isErr = True }

        Ok runInVolatileHostComplete ->
            { string = "Success: " ++ (runInVolatileHostComplete.returnValueToString |> Maybe.withDefault "null"), isErr = False }


statusReportFromState : StateIncludingFramework appSettings s -> String
statusReportFromState state =
    let
        fromApp =
            state.appState.lastEvent
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

        appEffectQueueLength =
            state.appState.effectQueue |> List.length

        {-
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
        -}
        appEffectQueueLengthWarning =
            if appEffectQueueLength < 6 then
                []

            else
                [ "App effect queue length is " ++ (appEffectQueueLength |> String.fromInt) ]
    in
    [ fromApp
    , "----"
    , "EVE Online framework status:"

    -- , runtimeExpensesReport
    , lastResultFromVolatileHost
    ]
        ++ appEffectQueueLengthWarning
        |> String.join "\n"


useContextMenuCascadeOnOverviewEntry :
    UseContextMenuCascadeNode
    -> EveOnline.ParseUserInterface.OverviewWindowEntry
    -> ReadingFromGameClient
    -> DecisionPathNode
useContextMenuCascadeOnOverviewEntry useContextMenu overviewEntry readingFromGameClient =
    useContextMenuCascade
        ( "overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'", overviewEntry.uiNode )
        useContextMenu
        readingFromGameClient


useContextMenuCascadeOnListSurroundingsButton :
    UseContextMenuCascadeNode
    -> ReadingFromGameClient
    -> DecisionPathNode
useContextMenuCascadeOnListSurroundingsButton useContextMenu readingFromGameClient =
    case readingFromGameClient.infoPanelContainer |> Maybe.andThen .infoPanelLocationInfo of
        Nothing ->
            Common.DecisionTree.describeBranch "I do not see the location info panel." askForHelpToGetUnstuck

        Just infoPanelLocationInfo ->
            useContextMenuCascade
                ( "surroundings button", infoPanelLocationInfo.listSurroundingsButton )
                useContextMenu
                readingFromGameClient


useContextMenuCascade :
    ( String, UIElement )
    -> UseContextMenuCascadeNode
    -> ReadingFromGameClient
    -> DecisionPathNode
useContextMenuCascade ( initialUIElementName, initialUIElement ) useContextMenu readingFromGameClient =
    let
        occludingRegionsWithSafetyMargin =
            readingFromGameClient.contextMenus
                |> List.map (.uiNode >> .totalDisplayRegion >> growRegionOnAllSides 2)

        regionsRemainingAfterOcclusion =
            subtractRegionsFromRegion
                { minuend = initialUIElement.totalDisplayRegion, subtrahend = occludingRegionsWithSafetyMargin }
    in
    case
        regionsRemainingAfterOcclusion
            |> List.filter (\region -> 3 < region.width && 3 < region.height)
            |> List.sortBy (\region -> negate (min region.width region.height))
            |> List.head
    of
        Nothing ->
            Common.DecisionTree.describeBranch
                ("All of "
                    ++ initialUIElementName
                    ++ " is occluded by context menus."
                )
                (Common.DecisionTree.endDecisionPath
                    (actWithoutFurtherReadings
                        ( "Click somewhere else to get rid of the occluding elements."
                        , Common.EffectOnWindow.effectsMouseClickAtLocation Common.EffectOnWindow.MouseButtonRight { x = 4, y = 4 }
                        )
                    )
                )

        Just preferredRegion ->
            { actionsAlreadyDecided =
                ( "Open context menu on " ++ initialUIElementName
                , preferredRegion
                    |> centerFromDisplayRegion
                    |> Common.EffectOnWindow.effectsMouseClickAtLocation Common.EffectOnWindow.MouseButtonRight
                )
            , actionsDependingOnNewReadings = useContextMenu |> unpackContextMenuTreeToListOfActionsDependingOnReadings
            }
                |> Act
                |> Common.DecisionTree.endDecisionPath


getEntropyIntFromReadingFromGameClient : EveOnline.ParseUserInterface.ParsedUserInterface -> Int
getEntropyIntFromReadingFromGameClient readingFromGameClient =
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
            readingFromGameClient.contextMenus
                |> List.concatMap (.entries >> List.map .uiNode)
                |> List.concatMap entropyFromUiElement

        fromOverview =
            readingFromGameClient.overviewWindow
                |> Maybe.map .entries
                |> Maybe.withDefault []
                |> List.concatMap entropyFromOverviewEntry

        fromProbeScanner =
            readingFromGameClient.probeScannerWindow
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


secondsToSessionEnd : AppEventContext a -> Maybe Int
secondsToSessionEnd appEventContext =
    appEventContext.sessionTimeLimitInMilliseconds
        |> Maybe.map (\sessionTimeLimitInMilliseconds -> (sessionTimeLimitInMilliseconds - appEventContext.timeInMilliseconds) // 1000)


clickOnUIElement : Common.EffectOnWindow.MouseButton -> UIElement -> List Common.EffectOnWindow.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    Common.EffectOnWindow.effectsMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromDisplayRegion)


type UseContextMenuCascadeNode
    = MenuEntryWithCustomChoice { describeChoice : String, chooseEntry : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry } UseContextMenuCascadeNode
    | MenuCascadeCompleted


useMenuEntryWithTextContaining : String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextContaining textToSearch =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text containing '" ++ textToSearch ++ "'"
        , chooseEntry =
            List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
                >> List.sortBy (.text >> String.trim >> String.length)
                >> List.head
        }


useMenuEntryWithTextContainingFirstOf : List String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextContainingFirstOf priorities =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text containing first available of " ++ (priorities |> List.map (String.Extra.surround "'") |> String.join ", ")
        , chooseEntry =
            \menuEntries ->
                priorities
                    |> List.concatMap
                        (\textToSearch ->
                            menuEntries
                                |> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
                                |> List.sortBy (.text >> String.trim >> String.length)
                        )
                    |> List.head
        }


useMenuEntryWithTextEqual : String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextEqual textToSearch =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text equal '" ++ textToSearch ++ "'"
        , chooseEntry =
            List.filter (.text >> String.trim >> String.toLower >> (==) (textToSearch |> String.toLower))
                >> List.head
        }


useMenuEntryInLastContextMenuInCascade :
    { describeChoice : String, chooseEntry : List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry }
    -> UseContextMenuCascadeNode
    -> UseContextMenuCascadeNode
useMenuEntryInLastContextMenuInCascade choice =
    MenuEntryWithCustomChoice
        { describeChoice = choice.describeChoice
        , chooseEntry = pickEntryFromLastContextMenuInCascade choice.chooseEntry
        }


useRandomMenuEntry : UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useRandomMenuEntry =
    MenuEntryWithCustomChoice
        { describeChoice = "random entry"
        , chooseEntry =
            \readingFromGameClient ->
                readingFromGameClient
                    |> pickEntryFromLastContextMenuInCascade
                        (Common.Basics.listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient readingFromGameClient))
        }


menuCascadeCompleted : UseContextMenuCascadeNode
menuCascadeCompleted =
    MenuCascadeCompleted


{-| This works only while the context menu model does not support branching. In this special case, we can unpack the tree into a list.
-}
unpackContextMenuTreeToListOfActionsDependingOnReadings :
    UseContextMenuCascadeNode
    -> List ( String, ReadingFromGameClient -> Maybe (List Common.EffectOnWindow.EffectOnWindowStructure) )
unpackContextMenuTreeToListOfActionsDependingOnReadings treeNode =
    let
        actionFromChoice ( describeChoice, chooseEntry ) =
            ( "Click menu entry " ++ describeChoice ++ "."
            , chooseEntry
                >> Maybe.map (.uiNode >> clickOnUIElement Common.EffectOnWindow.MouseButtonLeft)
            )

        listFromNextChoiceAndFollowingNodes nextChoice following =
            (nextChoice |> actionFromChoice) :: (following |> unpackContextMenuTreeToListOfActionsDependingOnReadings)
    in
    case treeNode of
        MenuCascadeCompleted ->
            []

        MenuEntryWithCustomChoice custom following ->
            listFromNextChoiceAndFollowingNodes
                ( "'" ++ custom.describeChoice ++ "'"
                , custom.chooseEntry
                )
                following


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromLocationInfoPanel : String -> EveOnline.ParseUserInterface.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


pickEntryFromLastContextMenuInCascade :
    (List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry)
    -> ReadingFromGameClient
    -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry
pickEntryFromLastContextMenuInCascade pickEntry =
    lastContextMenuOrSubmenu >> Maybe.map .entries >> Maybe.withDefault [] >> pickEntry


lastContextMenuOrSubmenu : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


infoPanelRouteFirstMarkerFromReadingFromGameClient : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromReadingFromGameClient =
    .infoPanelContainer
        >> Maybe.andThen .infoPanelRoute
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiNode.totalDisplayRegion.x + routeMarker.uiNode.totalDisplayRegion.y))
        >> Maybe.andThen List.head


localChatWindowFromUserInterface : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ChatWindow
localChatWindowFromUserInterface =
    .chatWindowStacks
        >> List.filterMap .chatWindow
        >> List.filter (.name >> Maybe.map (String.endsWith "_local") >> Maybe.withDefault False)
        >> List.head


shipUIIndicatesShipIsWarpingOrJumping : EveOnline.ParseUserInterface.ShipUI -> Bool
shipUIIndicatesShipIsWarpingOrJumping =
    .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map
            (\maneuverType ->
                [ EveOnline.ParseUserInterface.ManeuverWarp, EveOnline.ParseUserInterface.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


doEffectsClickModuleButton : EveOnline.ParseUserInterface.ShipUIModuleButton -> List Common.EffectOnWindow.EffectOnWindowStructure -> Bool
doEffectsClickModuleButton moduleButton =
    List.Extra.tails
        >> List.any
            (\effects ->
                case effects of
                    firstEffect :: secondEffect :: _ ->
                        case ( firstEffect, secondEffect ) of
                            ( Common.EffectOnWindow.MouseMoveTo mouseMoveTo, Common.EffectOnWindow.KeyDown keyDown ) ->
                                doesPointIntersectRegion mouseMoveTo moduleButton.uiNode.totalDisplayRegion
                                    && (keyDown == Common.EffectOnWindow.vkey_LBUTTON)

                            _ ->
                                False

                    [ _ ] ->
                        False

                    [] ->
                        False
            )


doesPointIntersectRegion : { x : Int, y : Int } -> EveOnline.ParseUserInterface.DisplayRegion -> Bool
doesPointIntersectRegion { x, y } region =
    (region.x <= x)
        && (x <= region.x + region.width)
        && (region.y <= y)
        && (y <= region.y + region.height)


type alias TreeLeafAct =
    { actionsAlreadyDecided : ( String, List Common.EffectOnWindow.EffectOnWindowStructure )
    , actionsDependingOnNewReadings : List ( String, ReadingFromGameClient -> Maybe (List Common.EffectOnWindow.EffectOnWindowStructure) )
    }


type EndDecisionPathStructure
    = Wait
    | Act TreeLeafAct
    | DecideFinishSession


type alias DecisionPathNode =
    Common.DecisionTree.DecisionPathNode EndDecisionPathStructure


type alias StepDecisionContext appSettings appMemory =
    { eventContext : AppEventContext appSettings
    , readingFromGameClient : ReadingFromGameClient
    , memory : appMemory
    , previousStepEffects : List Common.EffectOnWindow.EffectOnWindowStructure
    }


type alias AppStateWithMemoryAndDecisionTree appMemory =
    { programState :
        Maybe
            { originalDecision : DecisionPathNode
            , remainingActions : List ( String, ReadingFromGameClient -> Maybe (List Common.EffectOnWindow.EffectOnWindowStructure) )
            }
    , appMemory : appMemory
    , previousStepEffects : List Common.EffectOnWindow.EffectOnWindowStructure
    }


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


ensureInfoPanelLocationInfoIsExpanded : ReadingFromGameClient -> Maybe DecisionPathNode
ensureInfoPanelLocationInfoIsExpanded readingFromGameClient =
    case readingFromGameClient.infoPanelContainer |> Maybe.andThen .infoPanelLocationInfo of
        Nothing ->
            Just
                (Common.DecisionTree.describeBranch "I do not see the location info panel. Enable the info panel."
                    (case readingFromGameClient.infoPanelContainer |> Maybe.andThen .icons |> Maybe.andThen .locationInfo of
                        Nothing ->
                            Common.DecisionTree.describeBranch "I do not see the icon for the location info panel." askForHelpToGetUnstuck

                        Just iconLocationInfoPanel ->
                            Common.DecisionTree.endDecisionPath
                                (actWithoutFurtherReadings
                                    ( "Click on the icon to enable the info panel."
                                    , iconLocationInfoPanel |> clickOnUIElement Common.EffectOnWindow.MouseButtonLeft
                                    )
                                )
                    )
                )

        Just infoPanelLocationInfo ->
            if 35 < infoPanelLocationInfo.uiNode.totalDisplayRegion.height then
                Nothing

            else
                Just
                    (Common.DecisionTree.describeBranch "Location info panel seems collapsed."
                        (Common.DecisionTree.endDecisionPath
                            (actWithoutFurtherReadings
                                ( "Click to expand the info panel."
                                , Common.EffectOnWindow.effectsMouseClickAtLocation
                                    Common.EffectOnWindow.MouseButtonLeft
                                    { x = infoPanelLocationInfo.uiNode.totalDisplayRegion.x + 8
                                    , y = infoPanelLocationInfo.uiNode.totalDisplayRegion.y + 8
                                    }
                                )
                            )
                        )
                    )


branchDependingOnDockedOrInSpace :
    { ifDocked : DecisionPathNode
    , ifSeeShipUI : EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode
    , ifUndockingComplete : SeeUndockingComplete -> DecisionPathNode
    }
    -> ReadingFromGameClient
    -> DecisionPathNode
branchDependingOnDockedOrInSpace { ifDocked, ifSeeShipUI, ifUndockingComplete } readingFromGameClient =
    case readingFromGameClient.shipUI of
        Nothing ->
            Common.DecisionTree.describeBranch "I see no ship UI, assume we are docked." ifDocked

        Just shipUI ->
            ifSeeShipUI shipUI
                |> Maybe.withDefault
                    (case readingFromGameClient.overviewWindow of
                        Nothing ->
                            Common.DecisionTree.describeBranch
                                "I see no overview window, wait until undocking completed."
                                waitForProgressInGame

                        Just overviewWindow ->
                            Common.DecisionTree.describeBranch "I see ship UI and overview, undocking complete."
                                (ifUndockingComplete
                                    { shipUI = shipUI, overviewWindow = overviewWindow }
                                )
                    )


waitForProgressInGame : DecisionPathNode
waitForProgressInGame =
    Common.DecisionTree.endDecisionPath Wait


askForHelpToGetUnstuck : DecisionPathNode
askForHelpToGetUnstuck =
    Common.DecisionTree.describeBranch "I am stuck here and need help to continue."
        (Common.DecisionTree.endDecisionPath Wait)


readShipUIModuleButtonTooltipWhereNotYetInMemory :
    { a
        | readingFromGameClient : ReadingFromGameClient
        , memory : { b | shipModules : ShipModulesMemory }
    }
    -> Maybe DecisionPathNode
readShipUIModuleButtonTooltipWhereNotYetInMemory context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filter (getModuleButtonTooltipFromModuleButton context.memory.shipModules >> (==) Nothing)
        |> List.head
        |> Maybe.map
            (\moduleButtonWithoutMemoryOfTooltip ->
                Common.DecisionTree.endDecisionPath
                    (actWithoutFurtherReadings
                        ( "Read tooltip for module button"
                        , [ Common.EffectOnWindow.MouseMoveTo
                                (moduleButtonWithoutMemoryOfTooltip.uiNode.totalDisplayRegion |> centerFromDisplayRegion)
                          ]
                        )
                    )
            )


actWithoutFurtherReadings : ( String, List Common.EffectOnWindow.EffectOnWindowStructure ) -> EndDecisionPathStructure
actWithoutFurtherReadings actionsAlreadyDecided =
    Act { actionsAlreadyDecided = actionsAlreadyDecided, actionsDependingOnNewReadings = [] }


initStateWithMemoryAndDecisionTree : appMemory -> AppStateWithMemoryAndDecisionTree appMemory
initStateWithMemoryAndDecisionTree appMemory =
    { programState = Nothing
    , appMemory = appMemory
    , previousStepEffects = []
    }


processEveOnlineAppEventWithMemoryAndDecisionTree :
    { updateMemoryForNewReadingFromGame : ReadingFromGameClient -> appMemory -> appMemory
    , statusTextFromState : StepDecisionContext appSettings appMemory -> String
    , decisionTreeRoot : StepDecisionContext appSettings appMemory -> DecisionPathNode
    , millisecondsToNextReadingFromGame : StepDecisionContext appSettings appMemory -> Int
    }
    -> AppEventContext appSettings
    -> AppEvent
    -> AppStateWithMemoryAndDecisionTree appMemory
    -> ( AppStateWithMemoryAndDecisionTree appMemory, AppEventResponse )
processEveOnlineAppEventWithMemoryAndDecisionTree config eventContext event stateBefore =
    case event of
        ReadingFromGameClientCompleted readingFromGameClient ->
            let
                appMemory =
                    stateBefore.appMemory |> config.updateMemoryForNewReadingFromGame readingFromGameClient

                decisionContext =
                    { eventContext = eventContext
                    , memory = appMemory
                    , readingFromGameClient = readingFromGameClient
                    , previousStepEffects = stateBefore.previousStepEffects
                    }

                programStateIfEvalDecisionTreeNew =
                    let
                        originalDecision =
                            config.decisionTreeRoot decisionContext

                        originalRemainingActions =
                            case Common.DecisionTree.unpackToDecisionStagesDescriptionsAndLeaf originalDecision |> Tuple.second of
                                Wait ->
                                    []

                                Act act ->
                                    (act.actionsAlreadyDecided |> Tuple.mapSecond (Just >> always))
                                        :: act.actionsDependingOnNewReadings

                                DecideFinishSession ->
                                    []
                    in
                    { originalDecision = originalDecision, remainingActions = originalRemainingActions }

                programStateToContinue =
                    stateBefore.programState
                        |> Maybe.andThen
                            (\previousProgramState ->
                                if 0 < (previousProgramState.remainingActions |> List.length) then
                                    Just previousProgramState

                                else
                                    Nothing
                            )
                        |> Maybe.withDefault programStateIfEvalDecisionTreeNew

                ( originalDecisionStagesDescriptions, originalDecisionLeaf ) =
                    Common.DecisionTree.unpackToDecisionStagesDescriptionsAndLeaf programStateToContinue.originalDecision

                ( currentStepDescription, effectsOnGameClientWindow, programState ) =
                    case programStateToContinue.remainingActions of
                        [] ->
                            ( "Wait", [], Nothing )

                        ( nextActionDescription, nextActionEffectFromGameClient ) :: remainingActions ->
                            case readingFromGameClient |> nextActionEffectFromGameClient of
                                Nothing ->
                                    ( "Failed step: " ++ nextActionDescription, [], Nothing )

                                Just effects ->
                                    ( nextActionDescription
                                    , effects
                                    , Just { programStateToContinue | remainingActions = remainingActions }
                                    )

                effectsRequests =
                    effectsOnGameClientWindow |> List.map EffectOnGameClientWindow

                describeActivity =
                    (originalDecisionStagesDescriptions ++ [ currentStepDescription ])
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"

                statusMessage =
                    [ config.statusTextFromState decisionContext, describeActivity ]
                        |> String.join "\n"
            in
            ( { stateBefore
                | appMemory = appMemory
                , programState = programState
                , previousStepEffects = effectsOnGameClientWindow
              }
            , if originalDecisionLeaf == DecideFinishSession then
                FinishSession { statusDescriptionText = statusMessage }

              else
                ContinueSession
                    { effects = effectsRequests
                    , millisecondsToNextReadingFromGame = config.millisecondsToNextReadingFromGame decisionContext
                    , statusDescriptionText = statusMessage
                    }
            )


subtractRegionsFromRegion :
    { minuend : EveOnline.ParseUserInterface.DisplayRegion
    , subtrahend : List EveOnline.ParseUserInterface.DisplayRegion
    }
    -> List EveOnline.ParseUserInterface.DisplayRegion
subtractRegionsFromRegion { minuend, subtrahend } =
    subtrahend
        |> List.foldl
            (\subtrahendPart previousResults ->
                previousResults
                    |> List.concatMap
                        (\minuendPart ->
                            subtractRegionFromRegion { subtrahend = subtrahendPart, minuend = minuendPart }
                        )
            )
            [ minuend ]


subtractRegionFromRegion :
    { minuend : EveOnline.ParseUserInterface.DisplayRegion
    , subtrahend : EveOnline.ParseUserInterface.DisplayRegion
    }
    -> List EveOnline.ParseUserInterface.DisplayRegion
subtractRegionFromRegion { minuend, subtrahend } =
    let
        minuendRight =
            minuend.x + minuend.width

        minuendBottom =
            minuend.y + minuend.height

        subtrahendRight =
            subtrahend.x + subtrahend.width

        subtrahendBottom =
            subtrahend.y + subtrahend.height
    in
    {-
       Similar to approach from https://stackoverflow.com/questions/3765283/how-to-subtract-a-rectangle-from-another/15228510#15228510
       We want to support finding the largest rectangle, so we let them overlap here.

       ----------------------------
       |  A  |       A      |  A  |
       |  B  |              |  C  |
       |--------------------------|
       |  B  |  subtrahend  |  C  |
       |--------------------------|
       |  B  |              |  C  |
       |  D  |      D       |  D  |
       ----------------------------
    -}
    [ { left = minuend.x
      , top = minuend.y
      , right = minuendRight
      , bottom = minuendBottom |> min subtrahend.y
      }
    , { left = minuend.x
      , top = minuend.y
      , right = minuendRight |> min subtrahend.x
      , bottom = minuendBottom
      }
    , { left = minuend.x |> max subtrahendRight
      , top = minuend.y
      , right = minuendRight
      , bottom = minuendBottom
      }
    , { left = minuend.x
      , top = minuend.y |> max subtrahendBottom
      , right = minuendRight
      , bottom = minuendBottom
      }
    ]
        |> List.map
            (\rect ->
                { x = rect.left
                , y = rect.top
                , width = rect.right - rect.left
                , height = rect.bottom - rect.top
                }
            )
        |> List.filter (\rect -> 0 < rect.width && 0 < rect.height)
        |> Common.Basics.listUnique


growRegionOnAllSides : Int -> EveOnline.ParseUserInterface.DisplayRegion -> EveOnline.ParseUserInterface.DisplayRegion
growRegionOnAllSides growthAmount region =
    { x = region.x - growthAmount
    , y = region.y - growthAmount
    , width = region.width + growthAmount * 2
    , height = region.height + growthAmount * 2
    }

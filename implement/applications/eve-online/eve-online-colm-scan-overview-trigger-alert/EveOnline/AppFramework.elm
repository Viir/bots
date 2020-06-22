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


module EveOnline.AppFramework exposing
    ( AppEffect(..)
    , AppEvent(..)
    , AppEventContext
    , AppEventResponse(..)
    , ReadingFromGameClient
    , SetupState
    , ShipModulesMemory
    , StateIncludingFramework
    , UIElement
    , UseContextMenuCascadeNode
    , clickOnUIElement
    , getEntropyIntFromReadingFromGameClient
    , getModuleButtonTooltipFromModuleButton
    , initShipModulesMemory
    , initState
    , integrateCurrentReadingsIntoShipModulesMemory
    , menuCascadeCompleted
    , menuEntryMatchesStationNameFromLocationInfoPanel
    , processEvent
    , secondsToSessionEnd
    , unpackContextMenuTreeToListOfActionsDependingOnReadings
    , useMenuEntryInLastContextMenuInCascade
    , useMenuEntryWithTextContaining
    , useMenuEntryWithTextContainingFirstOf
    , useMenuEntryWithTextEqual
    , useRandomMenuEntry
    )

import BotEngine.Interface_To_Host_20200610 as InterfaceToHost
import Common.Basics
import Common.EffectOnWindow
import Common.FNV
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (effectMouseClickAtLocation)
import EveOnline.VolatileHostScript as VolatileHostScript
import String.Extra


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
    = EffectOnGameClientWindow VolatileHostInterface.EffectOnWindowStructure
    | EffectConsoleBeepSequence (List ConsoleBeepStructure)


type alias AppEventContext appSettings =
    { timeInMilliseconds : Int
    , appSettings : Maybe appSettings
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
    , gameClientProcesses : Maybe (List VolatileHostInterface.GameClientProcessSummaryStruct)
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


type alias ShipModulesMemory =
    { tooltipFromModuleButton : Dict.Dict String EveOnline.ParseUserInterface.ModuleButtonTooltip
    , lastReadingTooltip : MaybeVisible EveOnline.ParseUserInterface.ModuleButtonTooltip
    }


volatileHostRecycleInterval : Int
volatileHostRecycleInterval =
    400


initShipModulesMemory : ShipModulesMemory
initShipModulesMemory =
    { tooltipFromModuleButton = Dict.empty
    , lastReadingTooltip = CanNotSeeIt
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
                ( CanSee previousTooltip, CanSee currentTooltip ) ->
                    if getTooltipDataForEqualityComparison previousTooltip == getTooltipDataForEqualityComparison currentTooltip then
                        Just currentTooltip

                    else
                        Nothing

                _ ->
                    Nothing

        visibleModuleButtons =
            currentReading.shipUI
                |> maybeNothingFromCanNotSeeIt
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
    { parseAppSettings : String -> Result String appSettings
    , processEvent : AppEventContext appSettings -> AppEvent -> appState -> ( appState, AppEventResponse )
    }
    -> InterfaceToHost.AppEvent
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEvent appConfiguration fromHostEvent stateBefore =
    let
        continueAfterIntegrateEvent =
            processEventAfterIntegrateEvent { processEvent = appConfiguration.processEvent }
    in
    case fromHostEvent of
        InterfaceToHost.ArrivedAtTime { timeInMilliseconds } ->
            continueAfterIntegrateEvent Nothing { stateBefore | timeInMilliseconds = timeInMilliseconds }

        InterfaceToHost.CompletedTask taskComplete ->
            let
                ( setupState, maybeAppEventFromTaskComplete ) =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
            in
            continueAfterIntegrateEvent
                maybeAppEventFromTaskComplete
                { stateBefore | setup = setupState, taskInProgress = Nothing }

        InterfaceToHost.SetAppSettings appSettings ->
            case appConfiguration.parseAppSettings appSettings of
                Err parseSettingsError ->
                    ( stateBefore
                    , InterfaceToHost.FinishSession { statusDescriptionText = "Failed to parse these app-settings: " ++ parseSettingsError }
                    )

                Ok parsedAppSettings ->
                    ( { stateBefore | appSettings = Just parsedAppSettings }
                    , InterfaceToHost.ContinueSession
                        { statusDescriptionText = "Succeeded parsing these app-settings."
                        , startTasks = []
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 300 }
                        }
                    )

        InterfaceToHost.SetSessionTimeLimit sessionTimeLimit ->
            continueAfterIntegrateEvent
                Nothing
                { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }


processEventAfterIntegrateEvent :
    { processEvent : AppEventContext appSettings -> AppEvent -> appState -> ( appState, AppEventResponse )
    }
    -> Maybe AppEvent
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEventAfterIntegrateEvent appConfiguration maybeAppEvent stateBefore =
    let
        ( state, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    processEventNotWaitingForTaskCompletion
                        appConfiguration.processEvent
                        (maybeAppEvent
                            |> Maybe.map
                                (\appEvent ->
                                    ( appEvent
                                    , { timeInMilliseconds = stateBefore.timeInMilliseconds
                                      , appSettings = stateBefore.appSettings
                                      , sessionTimeLimitInMilliseconds = stateBefore.sessionTimeLimitInMilliseconds
                                      }
                                    )
                                )
                        )
                        stateBefore

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
    (AppEventContext appSettings -> AppEvent -> appState -> ( appState, AppEventResponse ))
    -> Maybe ( AppEvent, AppEventContext appSettings )
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEventNotWaitingForTaskCompletion appProcessEvent maybeAppEvent stateBefore =
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
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 1000 }
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
                                (\( appEvent, appEventContext ) -> appStateBefore.appState |> appProcessEvent appEventContext appEvent)

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

                    timeForNextMemoryReadingGeneral =
                        (stateBefore.setup.lastMemoryReading |> Maybe.map .timeInMilliseconds |> Maybe.withDefault 0) + 10000

                    timeForNextMemoryReadingFromApp =
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

                    timeForNextMemoryReading =
                        min timeForNextMemoryReadingGeneral timeForNextMemoryReadingFromApp

                    memoryReadingTasks =
                        if timeForNextMemoryReading < stateBefore.timeInMilliseconds then
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
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
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
dequeueNextEffectFromAppState { currentTimeInMs } effectQueueBefore =
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
                    case gameClientProcesses |> selectGameClientProcess of
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
                                        , releaseVolatileHostTask = InterfaceToHost.ReleaseVolatileHost { hostId = volatileHostId }
                                        }


selectGameClientProcess :
    List VolatileHostInterface.GameClientProcessSummaryStruct
    -> Result String { selectedProcess : VolatileHostInterface.GameClientProcessSummaryStruct, report : List String }
selectGameClientProcess gameClientProcesses =
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
                |> EveOnline.ParseUserInterface.maybeNothingFromCanNotSeeIt
                |> Maybe.map .entries
                |> Maybe.withDefault []
                |> List.concatMap entropyFromOverviewEntry

        fromProbeScanner =
            readingFromGameClient.probeScannerWindow
                |> EveOnline.ParseUserInterface.maybeNothingFromCanNotSeeIt
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


clickOnUIElement : Common.EffectOnWindow.MouseButton -> UIElement -> VolatileHostInterface.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromDisplayRegion)


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
                        )
                    |> List.sortBy (.text >> String.trim >> String.length)
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
    -> List ( String, ReadingFromGameClient -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
unpackContextMenuTreeToListOfActionsDependingOnReadings treeNode =
    let
        actionFromChoice ( describeChoice, chooseEntry ) =
            ( "Click menu entry " ++ describeChoice ++ "."
            , chooseEntry
                >> Maybe.map (.uiNode >> clickOnUIElement Common.EffectOnWindow.MouseButtonLeft >> List.singleton)
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

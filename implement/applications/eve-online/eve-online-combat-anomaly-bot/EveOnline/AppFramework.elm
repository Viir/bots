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

import BotEngine.Interface_To_Host_20201207 as InterfaceToHost
import Common.Basics
import Common.EffectOnWindow
import Common.FNV
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface exposing (Location2d, centerFromDisplayRegion)
import EveOnline.VolatileHostInterface as VolatileHostInterface
import EveOnline.VolatileHostScript as VolatileHostScript
import Json.Decode
import List.Extra
import Result.Extra
import String.Extra


type alias AppConfiguration appSettings appState =
    { parseAppSettings : String -> Result String appSettings
    , selectGameClientInstance : Maybe appSettings -> List GameClientProcessSummary -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
    , processEvent : AppEventContext appSettings -> AppEvent -> appState -> ( appState, AppEventResponse )
    }


type AppEvent
    = ReadingFromGameClientCompleted EveOnline.ParseUserInterface.ParsedUserInterface ReadingFromGameClientImage


type AppEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession { statusDescriptionText : String }


type alias ContinueSessionStructure =
    { effects : List Common.EffectOnWindow.EffectOnWindowStructure
    , millisecondsToNextReadingFromGame : Int
    , screenshotRegionsToRead : ReadingFromGameClient -> { rects1x1 : List Rect2dStructure }
    , statusDescriptionText : String
    }


type alias Rect2dStructure =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


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
    }


type alias SetupState =
    { createVolatileHostResult : Maybe (Result InterfaceToHost.CreateVolatileHostErrorStructure InterfaceToHost.CreateVolatileHostComplete)
    , requestsToVolatileHostCount : Int
    , lastRequestToVolatileHostResult : Maybe (Result String ( InterfaceToHost.RequestToVolatileHostComplete, Result String VolatileHostInterface.ResponseFromVolatileHost ))
    , gameClientProcesses : Maybe (List GameClientProcessSummary)
    , searchUIRootAddressResult : Maybe VolatileHostInterface.SearchUIRootAddressResultStructure
    , lastReadingFromGame : Maybe { timeInMilliseconds : Int, aggregate : ReadingFromGameClientAggregateState }
    , readingFromGameDurations : List Int
    , lastEffectFailedToAcquireInputFocus : Maybe String
    }


type alias ReadingFromGameClientAggregateState =
    { initialReading : VolatileHostInterface.ReadFromWindowResultStructure
    , imageDataFromReadingResults : List VolatileHostInterface.GetImageDataFromReadingResultStructure
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateApp OperateAppConfiguration
    | FrameworkStopSession String


type alias OperateAppConfiguration =
    { buildTaskFromEffectSequence : List Common.EffectOnWindow.EffectOnWindowStructure -> InterfaceToHost.Task
    , readFromWindowTask : VolatileHostInterface.GetImageDataFromReadingStructure -> InterfaceToHost.Task
    , getImageDataFromReadingTask : VolatileHostInterface.GetImageDataFromReadingStructure -> InterfaceToHost.Task
    , releaseVolatileHostTask : InterfaceToHost.Task
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


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


type alias ReadingFromGameClientImage =
    { pixels1x1 : Dict.Dict ( Int, Int ) PixelValueRGB
    }


type alias PixelValueRGB =
    { red : Int, green : Int, blue : Int }


effectSequenceSpacingMilliseconds : Int
effectSequenceSpacingMilliseconds =
    30


volatileHostRecycleInterval : Int
volatileHostRecycleInterval =
    400


getImageDataFromReadingRequestLimit : Int
getImageDataFromReadingRequestLimit =
    3


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
    , lastReadingFromGame = Nothing
    , readingFromGameDurations = []
    , lastEffectFailedToAcquireInputFocus = Nothing
    }


initState : appState -> StateIncludingFramework appSettings appState
initState appState =
    { setup = initSetup
    , appState =
        { appState = appState
        , lastEvent = Nothing
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
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEventAfterIntegrateEvent appConfiguration maybeReadingFromGameClient stateBefore =
    let
        ( stateBeforeCountingRequests, responseBeforeAddingStatusMessage ) =
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
                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                , appSettings = appSettings
                                , sessionTimeLimitInMilliseconds = stateBefore.sessionTimeLimitInMilliseconds
                                }
                                maybeReadingFromGameClient
                                stateBefore

                Just taskInProgress ->
                    ( stateBefore
                    , { statusDescriptionText = "Waiting for completion of task '" ++ taskInProgress.taskIdString ++ "': " ++ taskInProgress.taskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                      , startTasks = []
                      }
                        |> InterfaceToHost.ContinueSession
                    )

        newRequestsToVolatileHostCount =
            case responseBeforeAddingStatusMessage of
                InterfaceToHost.FinishSession _ ->
                    0

                InterfaceToHost.ContinueSession continueSession ->
                    continueSession.startTasks
                        |> List.filter
                            (\task ->
                                case task.task of
                                    InterfaceToHost.RequestToVolatileHost _ ->
                                        True

                                    _ ->
                                        False
                            )
                        |> List.length

        setupBeforeCountingRequests =
            stateBeforeCountingRequests.setup

        state =
            { stateBeforeCountingRequests
                | setup =
                    { setupBeforeCountingRequests
                        | requestsToVolatileHostCount =
                            setupBeforeCountingRequests.requestsToVolatileHostCount + newRequestsToVolatileHostCount
                    }
            }

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
    -> AppEventContext appSettings
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework appSettings appState
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
processEventNotWaitingForTaskCompletion appConfiguration appEventContext maybeReadingFromGameClient stateBefore =
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
                operateAppExceptRenewingVolatileHost
                    appConfiguration
                    appEventContext
                    maybeReadingFromGameClient
                    stateBefore
                    operateApp

        FrameworkStopSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Stop session (" ++ reason ++ ")" }
            )


operateAppExceptRenewingVolatileHost :
    AppConfiguration appSettings appState
    -> AppEventContext appSettings
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework appSettings appState
    -> OperateAppConfiguration
    -> ( StateIncludingFramework appSettings appState, InterfaceToHost.AppResponse )
operateAppExceptRenewingVolatileHost appConfiguration appEventContext maybeReadingFromGameClient stateBefore operateApp =
    let
        readingForScreenshotRequiredRegions =
            case maybeReadingFromGameClient of
                Just readingFromGameClient ->
                    Just readingFromGameClient

                Nothing ->
                    case stateBefore.setup.lastReadingFromGame of
                        Nothing ->
                            Nothing

                        Just lastReading ->
                            parseReadingFromGameClient lastReading.aggregate
                                |> Result.toMaybe

        screenshotRequiredRegions =
            case readingForScreenshotRequiredRegions of
                Nothing ->
                    []

                Just readingFromGameClient ->
                    case stateBefore.appState.lastEvent of
                        Nothing ->
                            []

                        Just lastEvent ->
                            case Tuple.second lastEvent.eventResult of
                                FinishSession _ ->
                                    []

                                ContinueSession continueSession ->
                                    (continueSession.screenshotRegionsToRead readingFromGameClient.parsedMemoryReading).rects1x1
                                        |> List.map (offsetRect readingFromGameClient.windowClientRectOffset)

        addMarginOnEachSide marginSize originalRect =
            { x = originalRect.x - marginSize
            , y = originalRect.y - marginSize
            , width = originalRect.width + marginSize * 2
            , height = originalRect.height + marginSize * 2
            }

        screenshot1x1RectsWithMargins =
            screenshotRequiredRegions
                |> List.map (addMarginOnEachSide 1)

        getImageData =
            { screenshot1x1Rects = screenshot1x1RectsWithMargins }

        continueWithNamedTaskToWaitOn { taskDescription, taskIdString } task =
            let
                ( taskInProgress, startTasks ) =
                    ( { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                      , taskIdString = taskIdString
                      , taskDescription = taskDescription
                      }
                    , [ { taskId = InterfaceToHost.taskIdFromString taskIdString, task = task } ]
                    )

                state =
                    { stateBefore | taskInProgress = Just taskInProgress }
            in
            ( state
            , { startTasks = startTasks
              , statusDescriptionText = "Operate app - " ++ taskDescription
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InterfaceToHost.ContinueSession
            )

        continueWithReadingFromGameClient =
            continueWithNamedTaskToWaitOn
                { taskDescription = "Reading from game"
                , taskIdString = "operate-app-read-from-game"
                }
                (operateApp.readFromWindowTask getImageData)

        continueWithGetImageDataFromReading =
            continueWithNamedTaskToWaitOn
                { taskDescription = "Get image data from reading"
                , taskIdString = "operate-app-get-image-data-from-reading"
                }
                (operateApp.getImageDataFromReadingTask getImageData)
    in
    case maybeReadingFromGameClient of
        Just readingFromGameClient ->
            let
                screenshot1x1Rects =
                    readingFromGameClient.imageDataFromReadingResults
                        |> List.concatMap .screenshot1x1Rects

                coveredRegions =
                    screenshot1x1Rects
                        |> List.map
                            (\imageCrop ->
                                let
                                    width =
                                        imageCrop.pixels
                                            |> List.map List.length
                                            |> List.minimum
                                            |> Maybe.withDefault 0

                                    height =
                                        List.length imageCrop.pixels
                                in
                                { x = imageCrop.offset.x
                                , y = imageCrop.offset.y
                                , width = width
                                , height = height
                                }
                            )

                isRegionCovered region =
                    subtractRegionsFromRegion { minuend = region, subtrahend = coveredRegions }
                        |> List.isEmpty
            in
            if
                List.any (isRegionCovered >> not) screenshotRequiredRegions
                    && (List.length readingFromGameClient.imageDataFromReadingResults < getImageDataFromReadingRequestLimit)
            then
                continueWithGetImageDataFromReading

            else
                let
                    appStateBefore =
                        stateBefore.appState

                    image =
                        { pixels1x1 =
                            screenshot1x1Rects
                                |> List.concatMap
                                    (\imageCrop ->
                                        imageCrop.pixels
                                            |> List.indexedMap
                                                (\rowIndexInCrop rowPixels ->
                                                    rowPixels
                                                        |> List.indexedMap
                                                            (\columnIndexInCrop pixelValue ->
                                                                ( ( columnIndexInCrop + imageCrop.offset.x - readingFromGameClient.windowClientRectOffset.x
                                                                  , rowIndexInCrop + imageCrop.offset.y - readingFromGameClient.windowClientRectOffset.y
                                                                  )
                                                                , pixelValue
                                                                )
                                                            )
                                                )
                                            |> List.concat
                                    )
                                |> Dict.fromList
                        }

                    appEvent =
                        ReadingFromGameClientCompleted readingFromGameClient.parsedMemoryReading image

                    ( newAppState, appEventResponse ) =
                        appStateBefore.appState
                            |> appConfiguration.processEvent appEventContext appEvent

                    lastEvent =
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , eventResult = ( newAppState, appEventResponse )
                        }

                    response =
                        case appEventResponse of
                            FinishSession _ ->
                                InterfaceToHost.FinishSession
                                    { statusDescriptionText = "The app finished the session." }

                            ContinueSession continueSession ->
                                let
                                    timeForNextReadingFromGame =
                                        stateBefore.timeInMilliseconds
                                            + continueSession.millisecondsToNextReadingFromGame

                                    ( taskInProgress, startTasks ) =
                                        case continueSession.effects of
                                            [] ->
                                                ( stateBefore.taskInProgress, [] )

                                            effects ->
                                                let
                                                    task =
                                                        operateApp.buildTaskFromEffectSequence effects

                                                    taskIdString =
                                                        "operate-app-send-effects"
                                                in
                                                ( Just
                                                    { startTimeInMilliseconds = stateBefore.timeInMilliseconds
                                                    , taskIdString = taskIdString
                                                    , taskDescription = "Send effects to game client"
                                                    }
                                                , [ { taskId = InterfaceToHost.taskIdFromString taskIdString
                                                    , task = task
                                                    }
                                                  ]
                                                )
                                in
                                { startTasks = startTasks
                                , statusDescriptionText = "Operate app"
                                , notifyWhenArrivedAtTime =
                                    if taskInProgress == Nothing then
                                        Just { timeInMilliseconds = timeForNextReadingFromGame }

                                    else
                                        Nothing
                                }
                                    |> InterfaceToHost.ContinueSession

                    state =
                        { stateBefore
                            | appState =
                                { appStateBefore
                                    | appState = newAppState
                                    , lastEvent = Just lastEvent
                                }
                        }
                in
                ( state, response )

        Nothing ->
            let
                timeForNextReadingFromGameGeneral =
                    (stateBefore.setup.lastReadingFromGame
                        |> Maybe.map .timeInMilliseconds
                        |> Maybe.withDefault 0
                    )
                        + 10000

                timeForNextReadingFromGameFromApp =
                    stateBefore.appState.lastEvent
                        |> Maybe.andThen
                            (\appLastEvent ->
                                case appLastEvent.eventResult |> Tuple.second of
                                    ContinueSession continueSessionResponse ->
                                        Just
                                            (appLastEvent.timeInMilliseconds
                                                + continueSessionResponse.millisecondsToNextReadingFromGame
                                            )

                                    FinishSession _ ->
                                        Nothing
                            )
                        |> Maybe.withDefault 0

                timeForNextReadingFromGame =
                    min timeForNextReadingFromGameGeneral timeForNextReadingFromGameFromApp

                remainingTimeToNextReadingFromGame =
                    timeForNextReadingFromGame - stateBefore.timeInMilliseconds
            in
            if remainingTimeToNextReadingFromGame <= 0 then
                continueWithReadingFromGameClient

            else
                ( stateBefore
                , { startTasks = []
                  , statusDescriptionText = "Operate app."
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = timeForNextReadingFromGame }
                  }
                    |> InterfaceToHost.ContinueSession
                )


type alias ReadingFromGameClientStructure =
    { parsedMemoryReading : EveOnline.ParseUserInterface.ParsedUserInterface
    , windowClientRectOffset : Location2d
    , imageDataFromReadingResults : List VolatileHostInterface.GetImageDataFromReadingResultStructure
    }


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe ReadingFromGameClientStructure )
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

        InterfaceToHost.RequestToVolatileHostResponse (Err InterfaceToHost.FailedToAcquireInputFocus) ->
            ( { setupStateBefore | lastEffectFailedToAcquireInputFocus = Just "Failed before entering volatile host." }, Nothing )

        InterfaceToHost.RequestToVolatileHostResponse (Ok requestResult) ->
            let
                requestToVolatileHostResult =
                    case requestResult.exceptionToString of
                        Just exception ->
                            Err ("Exception from host: " ++ exception)

                        Nothing ->
                            let
                                decodeResponseResult =
                                    case requestResult.returnValueToString of
                                        Nothing ->
                                            Err "Unexpected response: return value is empty"

                                        Just returnValueToString ->
                                            returnValueToString
                                                |> VolatileHostInterface.deserializeResponseFromVolatileHost
                                                |> Result.mapError Json.Decode.errorToString
                            in
                            Ok ( requestResult, decodeResponseResult )

                setupStateWithScriptRunResult =
                    { setupStateBefore | lastRequestToVolatileHostResult = Just requestToVolatileHostResult }
            in
            case requestToVolatileHostResult |> Result.andThen Tuple.second |> Result.toMaybe of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileHostOk ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileHost
                            { timeInMilliseconds = timeInMilliseconds
                            , responseFromVolatileHost = responseFromVolatileHostOk
                            , runInVolatileHostDurationInMs = requestResult.durationInMilliseconds
                            }

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateResponseFromVolatileHost :
    { timeInMilliseconds : Int, responseFromVolatileHost : VolatileHostInterface.ResponseFromVolatileHost, runInVolatileHostDurationInMs : Int }
    -> SetupState
    -> ( SetupState, Maybe ReadingFromGameClientStructure )
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

        VolatileHostInterface.ReadFromWindowResult readFromWindowResult ->
            let
                readingFromGameDurations =
                    runInVolatileHostDurationInMs
                        :: stateBefore.readingFromGameDurations
                        |> List.take 10

                lastReadingFromGame =
                    { timeInMilliseconds = timeInMilliseconds
                    , aggregate =
                        { initialReading = readFromWindowResult
                        , imageDataFromReadingResults = []
                        }
                    }

                state =
                    { stateBefore
                        | lastReadingFromGame = Just lastReadingFromGame
                        , readingFromGameDurations = readingFromGameDurations
                    }

                maybeReadingFromGameClient =
                    parseReadingFromGameClient lastReadingFromGame.aggregate
                        |> Result.toMaybe
            in
            ( state, maybeReadingFromGameClient )

        VolatileHostInterface.GetImageDataFromReadingResult getImageDataFromReadingResult ->
            case stateBefore.lastReadingFromGame of
                Nothing ->
                    ( stateBefore, Nothing )

                Just lastReadingFromGameBefore ->
                    let
                        aggregateBefore =
                            lastReadingFromGameBefore.aggregate

                        imageDataFromReadingResults =
                            getImageDataFromReadingResult :: aggregateBefore.imageDataFromReadingResults

                        lastReadingFromGame =
                            { lastReadingFromGameBefore
                                | aggregate = { aggregateBefore | imageDataFromReadingResults = imageDataFromReadingResults }
                            }

                        maybeReadingFromGameClient =
                            parseReadingFromGameClient lastReadingFromGame.aggregate
                                |> Result.toMaybe
                    in
                    ( { stateBefore | lastReadingFromGame = Just lastReadingFromGame }
                    , maybeReadingFromGameClient
                    )

        VolatileHostInterface.FailedToBringWindowToFront error ->
            ( { stateBefore | lastEffectFailedToAcquireInputFocus = Just error }, Nothing )

        VolatileHostInterface.CompletedEffectSequenceOnWindow ->
            ( { stateBefore | lastEffectFailedToAcquireInputFocus = Nothing }, Nothing )


parseReadingFromGameClient :
    ReadingFromGameClientAggregateState
    -> Result String ReadingFromGameClientStructure
parseReadingFromGameClient readingAggregate =
    case readingAggregate.initialReading of
        VolatileHostInterface.ProcessNotFound ->
            Err "Initial reading failed with 'Process Not Found'"

        VolatileHostInterface.Completed completedReading ->
            case completedReading.memoryReadingSerialRepresentationJson of
                Nothing ->
                    Err "Missing json representation of memory reading"

                Just memoryReadingSerialRepresentationJson ->
                    memoryReadingSerialRepresentationJson
                        |> EveOnline.MemoryReading.decodeMemoryReadingFromString
                        |> Result.mapError Json.Decode.errorToString
                        |> Result.map (EveOnline.ParseUserInterface.parseUITreeWithDisplayRegionFromUITree >> EveOnline.ParseUserInterface.parseUserInterfaceFromUITree)
                        |> Result.map
                            (\parsedMemoryReading ->
                                { parsedMemoryReading = parsedMemoryReading
                                , windowClientRectOffset = completedReading.windowClientRectOffset
                                , imageDataFromReadingResults = completedReading.imageData :: readingAggregate.imageDataFromReadingResults
                                }
                            )


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
    case stateBefore.gameClientProcesses of
        Nothing ->
            ContinueSetup stateBefore
                (InterfaceToHost.RequestToVolatileHost
                    (InterfaceToHost.RequestNotRequiringInputFocus
                        { hostId = volatileHostId
                        , request =
                            VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                VolatileHostInterface.ListGameClientProcessesRequest
                        }
                    )
                )
                "Get list of EVE Online client processes."

        Just gameClientProcesses ->
            case gameClientProcesses |> appConfiguration.selectGameClientInstance appSettings of
                Err selectGameClientProcessError ->
                    FrameworkStopSession ("Failed to select the game client process: " ++ selectGameClientProcessError)

                Ok gameClientSelection ->
                    let
                        continueWithSearchUIRootAddress =
                            ContinueSetup stateBefore
                                (InterfaceToHost.RequestToVolatileHost
                                    (InterfaceToHost.RequestNotRequiringInputFocus
                                        { hostId = volatileHostId
                                        , request =
                                            VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                                (VolatileHostInterface.SearchUIRootAddress { processId = gameClientSelection.selectedProcess.processId })
                                        }
                                    )
                                )
                                ((("Search the address of the UI root in process "
                                    ++ (gameClientSelection.selectedProcess.processId |> String.fromInt)
                                  )
                                    :: gameClientSelection.report
                                 )
                                    |> String.join "\n"
                                )
                    in
                    case stateBefore.searchUIRootAddressResult of
                        Nothing ->
                            continueWithSearchUIRootAddress

                        Just searchResult ->
                            if searchResult.processId /= gameClientSelection.selectedProcess.processId then
                                continueWithSearchUIRootAddress

                            else
                                case searchResult.uiRootAddress of
                                    Nothing ->
                                        FrameworkStopSession
                                            ("Did not find the root of the UI tree in game client instance '"
                                                ++ gameClientSelection.selectedProcess.mainWindowTitle
                                                ++ "' (pid "
                                                ++ String.fromInt gameClientSelection.selectedProcess.processId
                                                ++ "). Maybe the selected game client had not yet completed its startup? TODO: Check if we can read memory of that process at all."
                                            )

                                    Just uiRootAddress ->
                                        let
                                            readFromWindowRequest getImageData =
                                                VolatileHostInterface.ReadFromWindow
                                                    { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                    , uiRootAddress = uiRootAddress
                                                    , getImageData = getImageData
                                                    }

                                            getImageDataFromReadingRequest readingId getImageData =
                                                VolatileHostInterface.GetImageDataFromReading
                                                    { readingId = readingId
                                                    , getImageData = getImageData
                                                    }
                                        in
                                        case stateBefore.lastReadingFromGame of
                                            Nothing ->
                                                ContinueSetup stateBefore
                                                    (InterfaceToHost.RequestToVolatileHost
                                                        (InterfaceToHost.RequestNotRequiringInputFocus
                                                            { hostId = volatileHostId
                                                            , request =
                                                                VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost
                                                                    (readFromWindowRequest { screenshot1x1Rects = [] })
                                                            }
                                                        )
                                                    )
                                                    "Get the first memory reading from the EVE Online client process. This can take several seconds."

                                            Just lastMemoryReading ->
                                                case lastMemoryReading.aggregate.initialReading of
                                                    VolatileHostInterface.ProcessNotFound ->
                                                        FrameworkStopSession "The EVE Online client process disappeared."

                                                    VolatileHostInterface.Completed lastCompletedMemoryReading ->
                                                        let
                                                            buildTaskFromRequestToVolatileHost maybeAcquireInputFocus requestToVolatileHost =
                                                                let
                                                                    requestBeforeConsideringInputFocus =
                                                                        { hostId = volatileHostId
                                                                        , request = VolatileHostInterface.buildRequestStringToGetResponseFromVolatileHost requestToVolatileHost
                                                                        }
                                                                in
                                                                InterfaceToHost.RequestToVolatileHost
                                                                    (case maybeAcquireInputFocus of
                                                                        Nothing ->
                                                                            InterfaceToHost.RequestNotRequiringInputFocus
                                                                                requestBeforeConsideringInputFocus

                                                                        Just acquireInputFocus ->
                                                                            InterfaceToHost.RequestRequiringInputFocus
                                                                                { request = requestBeforeConsideringInputFocus
                                                                                , acquireInputFocus = acquireInputFocus
                                                                                }
                                                                    )
                                                        in
                                                        OperateApp
                                                            { buildTaskFromEffectSequence =
                                                                \effectSequenceOnWindow ->
                                                                    { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                                    , task =
                                                                        effectSequenceOnWindow
                                                                            |> List.map (effectOnWindowAsVolatileHostEffectOnWindow >> VolatileHostInterface.Effect)
                                                                            |> List.intersperse (VolatileHostInterface.DelayMilliseconds effectSequenceSpacingMilliseconds)
                                                                    , bringWindowToForeground = True
                                                                    }
                                                                        |> VolatileHostInterface.EffectSequenceOnWindow
                                                                        |> buildTaskFromRequestToVolatileHost (Just { maximumDelayMilliseconds = 500 })
                                                            , readFromWindowTask =
                                                                \getImageData ->
                                                                    readFromWindowRequest
                                                                        getImageData
                                                                        |> buildTaskFromRequestToVolatileHost
                                                                            (Just { maximumDelayMilliseconds = 500 })
                                                            , getImageDataFromReadingTask =
                                                                getImageDataFromReadingRequest lastCompletedMemoryReading.readingId
                                                                    >> buildTaskFromRequestToVolatileHost Nothing
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


requestToVolatileHostResultDisplayString :
    Result String ( InterfaceToHost.RequestToVolatileHostComplete, Result String VolatileHostInterface.ResponseFromVolatileHost )
    -> Result String String
requestToVolatileHostResultDisplayString =
    Result.andThen
        (\( runInVolatileHostComplete, decodeResult ) ->
            let
                describeReturnValue =
                    runInVolatileHostComplete.returnValueToString
                        |> Maybe.withDefault "null"
            in
            case decodeResult of
                Ok _ ->
                    Ok describeReturnValue

                Err decodeError ->
                    Err
                        ("Failed to decode response from volatile host: " ++ decodeError ++ " (" ++ describeReturnValue ++ ")")
        )


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

        inputFocusLines =
            case state.setup.lastEffectFailedToAcquireInputFocus of
                Nothing ->
                    []

                Just error ->
                    [ "Failed to acquire input focus: " ++ error ]

        lastResultFromVolatileHost =
            "Last result from volatile host is: "
                ++ (state.setup.lastRequestToVolatileHostResult
                        |> Maybe.map requestToVolatileHostResultDisplayString
                        |> Maybe.map
                            (\resultDisplayInfo ->
                                let
                                    ( prefix, lengthLimit ) =
                                        if Result.Extra.isErr resultDisplayInfo then
                                            ( "Error", 640 )

                                        else
                                            ( "Success", 140 )
                                in
                                (prefix ++ ": " ++ Result.Extra.merge resultDisplayInfo)
                                    |> stringEllipsis
                                        lengthLimit
                                        "...."
                            )
                        |> Maybe.withDefault "Nothing"
                   )

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
        describeLastReadingFromGame =
            case state.setup.lastReadingFromGame of
                Nothing ->
                    "None so far"

                Just lastMemoryReading ->
                    case lastMemoryReading.aggregate.initialReading of
                        VolatileHostInterface.ProcessNotFound ->
                            "process not found"

                        VolatileHostInterface.Completed completedReading ->
                            let
                                allPixels =
                                    completedReading.imageData.screenshot1x1Rects
                                        |> List.map .pixels
                                        |> List.concat
                            in
                            completedReading.readingId
                                ++ ": "
                                ++ String.fromInt (List.length completedReading.imageData.screenshot1x1Rects)
                                ++ " rects containing "
                                ++ String.fromInt (List.sum (List.map List.length allPixels))
                                ++ " pixels"
    in
    [ [ fromApp ]
    , [ "----"
      , "EVE Online framework status:"
      ]

    --, [ runtimeExpensesReport ]
    , [ "Last reading from game client: " ++ describeLastReadingFromGame ]
    , [ lastResultFromVolatileHost ]
    , inputFocusLines
    ]
        |> List.concat
        |> String.join "\n"


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


cornersFromDisplayRegion : EveOnline.ParseUserInterface.DisplayRegion -> List { x : Int, y : Int }
cornersFromDisplayRegion region =
    [ { x = region.x, y = region.y }
    , { x = region.x + region.width, y = region.y }
    , { x = region.x, y = region.y + region.height }
    , { x = region.x + region.width, y = region.y + region.height }
    ]


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


offsetRect : Location2d -> Rect2dStructure -> Rect2dStructure
offsetRect offset rect =
    { rect | x = rect.x + offset.x, y = rect.y + offset.y }

module EveOnline.BotFramework exposing (..)

{-| A framework to build EVE Online bots and intel tools.
Features:

  - Read from the game client using Sanderling memory reading and parse the user interface from the memory reading (<https://github.com/Arcitectus/Sanderling>).
  - Play sounds.
  - Send mouse and keyboard input to the game client.
  - Parse the bot-settings and inform the user about the result.

The framework automatically selects an EVE Online client process and finishes the session when that process disappears.
When multiple game clients are open, the framework prioritizes the one with the topmost window. This approach helps users control which game client is picked by an app.
To use the framework, import this module and use the `initState` and `processEvent` functions.

To learn more about developing for EVE Online, see the guide at <https://to.botlab.org/guide/developing-for-eve-online>

-}

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Common.Basics
import Common.EffectOnWindow
import Common.FNV
import CompilationInterface.SourceFiles
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface exposing (Location2d, centerFromDisplayRegion)
import EveOnline.VolatileProcessInterface as VolatileProcessInterface
import Json.Decode
import List.Extra
import Result.Extra
import String.Extra


type alias BotConfiguration botSettings botState =
    { parseBotSettings : String -> Result String botSettings
    , selectGameClientInstance : Maybe botSettings -> List GameClientProcessSummary -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
    , processEvent : BotEventContext botSettings -> BotEvent -> botState -> ( botState, BotEventResponse )
    }


type BotEvent
    = ReadingFromGameClientCompleted EveOnline.ParseUserInterface.ParsedUserInterface ReadingFromGameClientImage


type BotEventResponse
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


type alias BotEventContext botSettings =
    { timeInMilliseconds : Int
    , botSettings : botSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias StateIncludingFramework botSettings botState =
    { setup : SetupState
    , botState : BotAndLastEventState botState
    , timeInMilliseconds : Int
    , lastTaskIndex : Int
    , taskInProgress : Maybe { startTimeInMilliseconds : Int, taskIdString : String, taskDescription : String }
    , botSettings : Maybe botSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotAndLastEventState botState =
    { botState : botState
    , lastEvent : Maybe { timeInMilliseconds : Int, eventResult : ( botState, BotEventResponse ) }
    }


type alias SetupState =
    { createVolatileProcessResult : Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , requestsToVolatileProcessCount : Int
    , lastRequestToVolatileProcessResult : Maybe (Result String ( InterfaceToHost.RequestToVolatileProcessComplete, Result String VolatileProcessInterface.ResponseFromVolatileHost ))
    , gameClientProcesses : Maybe (List GameClientProcessSummary)
    , searchUIRootAddressResult : Maybe VolatileProcessInterface.SearchUIRootAddressResultStructure
    , lastReadingFromGame : Maybe { timeInMilliseconds : Int, aggregate : ReadingFromGameClientAggregateState }
    , readingFromGameDurations : List Int
    , lastEffectFailedToAcquireInputFocus : Maybe String
    }


type alias ReadingFromGameClientAggregateState =
    { initialReading : VolatileProcessInterface.ReadFromWindowResultStructure
    , imageDataFromReadingResults : List VolatileProcessInterface.GetImageDataFromReadingResultStructure
    }


type SetupTask
    = ContinueSetup SetupState InterfaceToHost.Task String
    | OperateBot OperateBotConfiguration
    | FrameworkStopSession String


type alias OperateBotConfiguration =
    { buildTaskFromEffectSequence : List Common.EffectOnWindow.EffectOnWindowStructure -> InterfaceToHost.Task
    , readFromWindowTask : VolatileProcessInterface.GetImageDataFromReadingStructure -> InterfaceToHost.Task
    , getImageDataFromReadingTask : VolatileProcessInterface.GetImageDataFromReadingStructure -> InterfaceToHost.Task
    , releaseVolatileProcessTask : InterfaceToHost.Task
    }


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias GameClientProcessSummary =
    VolatileProcessInterface.GameClientProcessSummaryStruct


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


volatileProcessRecycleInterval : Int
volatileProcessRecycleInterval =
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
    { createVolatileProcessResult = Nothing
    , requestsToVolatileProcessCount = 0
    , lastRequestToVolatileProcessResult = Nothing
    , gameClientProcesses = Nothing
    , searchUIRootAddressResult = Nothing
    , lastReadingFromGame = Nothing
    , readingFromGameDurations = []
    , lastEffectFailedToAcquireInputFocus = Nothing
    }


initState : botState -> StateIncludingFramework botSettings botState
initState botState =
    { setup = initSetup
    , botState =
        { botState = botState
        , lastEvent = Nothing
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , taskInProgress = Nothing
    , botSettings = Nothing
    , sessionTimeLimitInMilliseconds = Nothing
    }


processEvent :
    BotConfiguration botSettings botState
    -> InterfaceToHost.BotEvent
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InterfaceToHost.BotEventResponse )
processEvent botConfiguration fromHostEvent stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = fromHostEvent.timeInMilliseconds }

        continueAfterIntegrateEvent =
            processEventAfterIntegrateEvent botConfiguration
    in
    case fromHostEvent.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            continueAfterIntegrateEvent Nothing stateBefore

        InterfaceToHost.TaskCompletedEvent taskComplete ->
            let
                ( setupState, maybeBotEventFromTaskComplete ) =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
            in
            continueAfterIntegrateEvent
                maybeBotEventFromTaskComplete
                { stateBefore | setup = setupState, taskInProgress = Nothing }

        InterfaceToHost.BotSettingsChangedEvent botSettings ->
            case botConfiguration.parseBotSettings botSettings of
                Err parseSettingsError ->
                    ( stateBefore
                    , InterfaceToHost.FinishSession
                        { statusDescriptionText = "Failed to parse these bot-settings: " ++ parseSettingsError }
                    )

                Ok parsedBotSettings ->
                    ( { stateBefore | botSettings = Just parsedBotSettings }
                    , InterfaceToHost.ContinueSession
                        { statusDescriptionText = "Succeeded parsing these bot-settings."
                        , startTasks = []
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = 0 }
                        }
                    )

        InterfaceToHost.SessionDurationPlannedEvent sessionTimeLimit ->
            continueAfterIntegrateEvent
                Nothing
                { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }


processEventAfterIntegrateEvent :
    BotConfiguration botSettings botState
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InterfaceToHost.BotEventResponse )
processEventAfterIntegrateEvent botConfiguration maybeReadingFromGameClient stateBefore =
    let
        ( stateBeforeCountingRequests, responseBeforeAddingStatusMessage ) =
            case stateBefore.taskInProgress of
                Nothing ->
                    case stateBefore.botSettings of
                        Nothing ->
                            ( stateBefore
                            , InterfaceToHost.FinishSession
                                { statusDescriptionText =
                                    "Unexpected order of events: I did not receive any bot-settings changed event."
                                }
                            )

                        Just botSettings ->
                            processEventNotWaitingForTaskCompletion
                                botConfiguration
                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                , botSettings = botSettings
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

        newRequestsToVolatileProcessCount =
            case responseBeforeAddingStatusMessage of
                InterfaceToHost.FinishSession _ ->
                    0

                InterfaceToHost.ContinueSession continueSession ->
                    continueSession.startTasks
                        |> List.filter
                            (\task ->
                                case task.task of
                                    InterfaceToHost.RequestToVolatileProcess _ ->
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
                        | requestsToVolatileProcessCount =
                            setupBeforeCountingRequests.requestsToVolatileProcessCount + newRequestsToVolatileProcessCount
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
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InterfaceToHost.BotEventResponse )
processEventNotWaitingForTaskCompletion botConfiguration botEventContext maybeReadingFromGameClient stateBefore =
    case stateBefore.setup |> getNextSetupTask botConfiguration stateBefore.botSettings of
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

        OperateBot operateBot ->
            if volatileProcessRecycleInterval < stateBefore.setup.requestsToVolatileProcessCount then
                let
                    taskIndex =
                        stateBefore.lastTaskIndex + 1

                    taskIdString =
                        "maintain-" ++ (taskIndex |> String.fromInt)

                    setupStateBefore =
                        stateBefore.setup

                    setupState =
                        { setupStateBefore | createVolatileProcessResult = Nothing }

                    setupTaskDescription =
                        "Recycle the volatile process after " ++ (setupStateBefore.requestsToVolatileProcessCount |> String.fromInt) ++ " requests."
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
                          , task = operateBot.releaseVolatileProcessTask
                          }
                        ]
                  , statusDescriptionText = "Continue setup: " ++ setupTaskDescription
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                  }
                    |> InterfaceToHost.ContinueSession
                )

            else
                operateBotExceptRenewingVolatileProcess
                    botConfiguration
                    botEventContext
                    maybeReadingFromGameClient
                    stateBefore
                    operateBot

        FrameworkStopSession reason ->
            ( stateBefore
            , InterfaceToHost.FinishSession { statusDescriptionText = "Stop session (" ++ reason ++ ")" }
            )


operateBotExceptRenewingVolatileProcess :
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> Maybe ReadingFromGameClientStructure
    -> StateIncludingFramework botSettings botState
    -> OperateBotConfiguration
    -> ( StateIncludingFramework botSettings botState, InterfaceToHost.BotEventResponse )
operateBotExceptRenewingVolatileProcess botConfiguration botEventContext maybeReadingFromGameClient stateBefore operateBot =
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
                    case stateBefore.botState.lastEvent of
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
              , statusDescriptionText = "Operate bot - " ++ taskDescription
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InterfaceToHost.ContinueSession
            )

        continueWithReadingFromGameClient =
            continueWithNamedTaskToWaitOn
                { taskDescription = "Reading from game"
                , taskIdString = "operate-bot-read-from-game"
                }
                (operateBot.readFromWindowTask getImageData)

        continueWithGetImageDataFromReading =
            continueWithNamedTaskToWaitOn
                { taskDescription = "Get image data from reading"
                , taskIdString = "operate-bot-get-image-data-from-reading"
                }
                (operateBot.getImageDataFromReadingTask getImageData)
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
                    botStateBefore =
                        stateBefore.botState

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

                    botEvent =
                        ReadingFromGameClientCompleted readingFromGameClient.parsedMemoryReading image

                    ( newBotState, botEventResponse ) =
                        botStateBefore.botState
                            |> botConfiguration.processEvent botEventContext botEvent

                    lastEvent =
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , eventResult = ( newBotState, botEventResponse )
                        }

                    response =
                        case botEventResponse of
                            FinishSession _ ->
                                InterfaceToHost.FinishSession
                                    { statusDescriptionText = "The bot finished the session." }

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
                                                        operateBot.buildTaskFromEffectSequence effects

                                                    taskIdString =
                                                        "operate-bot-send-effects"
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
                                , statusDescriptionText = "Operate bot"
                                , notifyWhenArrivedAtTime =
                                    if taskInProgress == Nothing then
                                        Just { timeInMilliseconds = timeForNextReadingFromGame }

                                    else
                                        Nothing
                                }
                                    |> InterfaceToHost.ContinueSession

                    state =
                        { stateBefore
                            | botState =
                                { botStateBefore
                                    | botState = newBotState
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

                timeForNextReadingFromGameFromBot =
                    stateBefore.botState.lastEvent
                        |> Maybe.andThen
                            (\botLastEvent ->
                                case botLastEvent.eventResult |> Tuple.second of
                                    ContinueSession continueSessionResponse ->
                                        Just
                                            (botLastEvent.timeInMilliseconds
                                                + continueSessionResponse.millisecondsToNextReadingFromGame
                                            )

                                    FinishSession _ ->
                                        Nothing
                            )
                        |> Maybe.withDefault 0

                timeForNextReadingFromGame =
                    min timeForNextReadingFromGameGeneral timeForNextReadingFromGameFromBot

                remainingTimeToNextReadingFromGame =
                    timeForNextReadingFromGame - stateBefore.timeInMilliseconds
            in
            if remainingTimeToNextReadingFromGame <= 0 then
                continueWithReadingFromGameClient

            else
                ( stateBefore
                , { startTasks = []
                  , statusDescriptionText = "Operate bot."
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = timeForNextReadingFromGame }
                  }
                    |> InterfaceToHost.ContinueSession
                )


type alias ReadingFromGameClientStructure =
    { parsedMemoryReading : EveOnline.ParseUserInterface.ParsedUserInterface
    , windowClientRectOffset : Location2d
    , imageDataFromReadingResults : List VolatileProcessInterface.GetImageDataFromReadingResultStructure
    }


integrateTaskResult : ( Int, InterfaceToHost.TaskResultStructure ) -> SetupState -> ( SetupState, Maybe ReadingFromGameClientStructure )
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResult ->
            ( { setupStateBefore
                | createVolatileProcessResult = Just createVolatileProcessResult
                , requestsToVolatileProcessCount = 0
              }
            , Nothing
            )

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.ProcessNotFound) ->
            ( { setupStateBefore | createVolatileProcessResult = Nothing }, Nothing )

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.FailedToAcquireInputFocus) ->
            ( { setupStateBefore | lastEffectFailedToAcquireInputFocus = Just "Failed before entering volatile process." }, Nothing )

        InterfaceToHost.RequestToVolatileProcessResponse (Ok requestResult) ->
            let
                requestToVolatileProcessResult =
                    case requestResult.exceptionToString of
                        Just exception ->
                            Err ("Exception from volatile process: " ++ exception)

                        Nothing ->
                            let
                                decodeResponseResult =
                                    case requestResult.returnValueToString of
                                        Nothing ->
                                            Err "Unexpected response: return value is empty"

                                        Just returnValueToString ->
                                            returnValueToString
                                                |> VolatileProcessInterface.deserializeResponseFromVolatileHost
                                                |> Result.mapError Json.Decode.errorToString
                            in
                            Ok ( requestResult, decodeResponseResult )

                setupStateWithScriptRunResult =
                    { setupStateBefore | lastRequestToVolatileProcessResult = Just requestToVolatileProcessResult }
            in
            case requestToVolatileProcessResult |> Result.andThen Tuple.second |> Result.toMaybe of
                Nothing ->
                    ( setupStateWithScriptRunResult, Nothing )

                Just responseFromVolatileProcessOk ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileProcess
                            { timeInMilliseconds = timeInMilliseconds
                            , responseFromVolatileProcess = responseFromVolatileProcessOk
                            , runInVolatileProcessDurationInMs = requestResult.durationInMilliseconds
                            }

        InterfaceToHost.CompleteWithoutResult ->
            ( setupStateBefore, Nothing )


integrateResponseFromVolatileProcess :
    { timeInMilliseconds : Int, responseFromVolatileProcess : VolatileProcessInterface.ResponseFromVolatileHost, runInVolatileProcessDurationInMs : Int }
    -> SetupState
    -> ( SetupState, Maybe ReadingFromGameClientStructure )
integrateResponseFromVolatileProcess { timeInMilliseconds, responseFromVolatileProcess, runInVolatileProcessDurationInMs } stateBefore =
    case responseFromVolatileProcess of
        VolatileProcessInterface.ListGameClientProcessesResponse gameClientProcesses ->
            ( { stateBefore | gameClientProcesses = Just gameClientProcesses }, Nothing )

        VolatileProcessInterface.SearchUIRootAddressResult searchUIRootAddressResult ->
            let
                state =
                    { stateBefore | searchUIRootAddressResult = Just searchUIRootAddressResult }
            in
            ( state, Nothing )

        VolatileProcessInterface.ReadFromWindowResult readFromWindowResult ->
            let
                readingFromGameDurations =
                    runInVolatileProcessDurationInMs
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

        VolatileProcessInterface.GetImageDataFromReadingResult getImageDataFromReadingResult ->
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

        VolatileProcessInterface.FailedToBringWindowToFront error ->
            ( { stateBefore | lastEffectFailedToAcquireInputFocus = Just error }, Nothing )

        VolatileProcessInterface.CompletedEffectSequenceOnWindow ->
            ( { stateBefore | lastEffectFailedToAcquireInputFocus = Nothing }, Nothing )


parseReadingFromGameClient :
    ReadingFromGameClientAggregateState
    -> Result String ReadingFromGameClientStructure
parseReadingFromGameClient readingAggregate =
    case readingAggregate.initialReading of
        VolatileProcessInterface.ProcessNotFound ->
            Err "Initial reading failed with 'Process Not Found'"

        VolatileProcessInterface.Completed completedReading ->
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
    BotConfiguration botSettings botState
    -> Maybe botSettings
    -> SetupState
    -> SetupTask
getNextSetupTask botConfiguration botSettings stateBefore =
    case stateBefore.createVolatileProcessResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (InterfaceToHost.CreateVolatileProcess
                    { programCode = CompilationInterface.SourceFiles.file____EveOnline_VolatileProcess_cx.utf8 }
                )
                "Set up the volatile process. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FrameworkStopSession ("Create volatile process failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileProcessComplete) ->
            getSetupTaskWhenVolatileProcessSetupCompleted
                botConfiguration
                botSettings
                stateBefore
                createVolatileProcessComplete.processId


getSetupTaskWhenVolatileProcessSetupCompleted :
    BotConfiguration botSettings appState
    -> Maybe botSettings
    -> SetupState
    -> InterfaceToHost.VolatileProcessId
    -> SetupTask
getSetupTaskWhenVolatileProcessSetupCompleted botConfiguration botSettings stateBefore volatileProcessId =
    case stateBefore.gameClientProcesses of
        Nothing ->
            ContinueSetup stateBefore
                (InterfaceToHost.RequestToVolatileProcess
                    (InterfaceToHost.RequestNotRequiringInputFocus
                        { processId = volatileProcessId
                        , request =
                            VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                VolatileProcessInterface.ListGameClientProcessesRequest
                        }
                    )
                )
                "Get list of EVE Online client processes."

        Just gameClientProcesses ->
            case gameClientProcesses |> botConfiguration.selectGameClientInstance botSettings of
                Err selectGameClientProcessError ->
                    FrameworkStopSession ("Failed to select the game client process: " ++ selectGameClientProcessError)

                Ok gameClientSelection ->
                    let
                        continueWithSearchUIRootAddress =
                            ContinueSetup stateBefore
                                (InterfaceToHost.RequestToVolatileProcess
                                    (InterfaceToHost.RequestNotRequiringInputFocus
                                        { processId = volatileProcessId
                                        , request =
                                            VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                                (VolatileProcessInterface.SearchUIRootAddress { processId = gameClientSelection.selectedProcess.processId })
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
                                                VolatileProcessInterface.ReadFromWindow
                                                    { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                    , uiRootAddress = uiRootAddress
                                                    , getImageData = getImageData
                                                    }

                                            getImageDataFromReadingRequest readingId getImageData =
                                                VolatileProcessInterface.GetImageDataFromReading
                                                    { readingId = readingId
                                                    , getImageData = getImageData
                                                    }
                                        in
                                        case stateBefore.lastReadingFromGame of
                                            Nothing ->
                                                ContinueSetup stateBefore
                                                    (InterfaceToHost.RequestToVolatileProcess
                                                        (InterfaceToHost.RequestNotRequiringInputFocus
                                                            { processId = volatileProcessId
                                                            , request =
                                                                VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                                                    (readFromWindowRequest { screenshot1x1Rects = [] })
                                                            }
                                                        )
                                                    )
                                                    "Get the first memory reading from the EVE Online client process. This can take several seconds."

                                            Just lastMemoryReading ->
                                                case lastMemoryReading.aggregate.initialReading of
                                                    VolatileProcessInterface.ProcessNotFound ->
                                                        FrameworkStopSession "The EVE Online client process disappeared."

                                                    VolatileProcessInterface.Completed lastCompletedMemoryReading ->
                                                        let
                                                            buildTaskFromRequestToVolatileProcess maybeAcquireInputFocus requestToVolatileProcess =
                                                                let
                                                                    requestBeforeConsideringInputFocus =
                                                                        { processId = volatileProcessId
                                                                        , request = VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost requestToVolatileProcess
                                                                        }
                                                                in
                                                                InterfaceToHost.RequestToVolatileProcess
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
                                                        OperateBot
                                                            { buildTaskFromEffectSequence =
                                                                \effectSequenceOnWindow ->
                                                                    { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                                    , task =
                                                                        effectSequenceOnWindow
                                                                            |> List.map (effectOnWindowAsVolatileProcessEffectOnWindow >> VolatileProcessInterface.Effect)
                                                                            |> List.intersperse (VolatileProcessInterface.DelayMilliseconds effectSequenceSpacingMilliseconds)
                                                                    , bringWindowToForeground = True
                                                                    }
                                                                        |> VolatileProcessInterface.EffectSequenceOnWindow
                                                                        |> buildTaskFromRequestToVolatileProcess (Just { maximumDelayMilliseconds = 500 })
                                                            , readFromWindowTask =
                                                                \getImageData ->
                                                                    readFromWindowRequest
                                                                        getImageData
                                                                        |> buildTaskFromRequestToVolatileProcess
                                                                            (Just { maximumDelayMilliseconds = 500 })
                                                            , getImageDataFromReadingTask =
                                                                getImageDataFromReadingRequest lastCompletedMemoryReading.readingId
                                                                    >> buildTaskFromRequestToVolatileProcess Nothing
                                                            , releaseVolatileProcessTask = InterfaceToHost.ReleaseVolatileProcess { processId = volatileProcessId }
                                                            }


effectOnWindowAsVolatileProcessEffectOnWindow : Common.EffectOnWindow.EffectOnWindowStructure -> VolatileProcessInterface.EffectOnWindowStructure
effectOnWindowAsVolatileProcessEffectOnWindow effectOnWindow =
    case effectOnWindow of
        Common.EffectOnWindow.MouseMoveTo mouseMoveTo ->
            VolatileProcessInterface.MouseMoveTo { location = mouseMoveTo }

        Common.EffectOnWindow.KeyDown key ->
            VolatileProcessInterface.KeyDown key

        Common.EffectOnWindow.KeyUp key ->
            VolatileProcessInterface.KeyUp key


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


requestToVolatileProcessResultDisplayString :
    Result String ( InterfaceToHost.RequestToVolatileProcessComplete, Result String VolatileProcessInterface.ResponseFromVolatileHost )
    -> Result String String
requestToVolatileProcessResultDisplayString =
    Result.andThen
        (\( runInVolatileProcessComplete, decodeResult ) ->
            let
                describeReturnValue =
                    runInVolatileProcessComplete.returnValueToString
                        |> Maybe.withDefault "null"
            in
            case decodeResult of
                Ok _ ->
                    Ok describeReturnValue

                Err decodeError ->
                    Err
                        ("Failed to decode response from volatile process: " ++ decodeError ++ " (" ++ describeReturnValue ++ ")")
        )


statusReportFromState : StateIncludingFramework botSettings s -> String
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

        inputFocusLines =
            case state.setup.lastEffectFailedToAcquireInputFocus of
                Nothing ->
                    []

                Just error ->
                    [ "Failed to acquire input focus: " ++ error ]

        lastResultFromVolatileProcess =
            "Last result from volatile process is: "
                ++ (state.setup.lastRequestToVolatileProcessResult
                        |> Maybe.map requestToVolatileProcessResultDisplayString
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
                        VolatileProcessInterface.ProcessNotFound ->
                            "process not found"

                        VolatileProcessInterface.Completed completedReading ->
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
    [ [ fromBot ]
    , [ "----"
      , "EVE Online framework status:"
      ]

    --, [ runtimeExpensesReport ]
    , [ "Last reading from game client: " ++ describeLastReadingFromGame ]
    , [ lastResultFromVolatileProcess ]
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


secondsToSessionEnd : BotEventContext a -> Maybe Int
secondsToSessionEnd botEventContext =
    botEventContext.sessionTimeLimitInMilliseconds
        |> Maybe.map (\sessionTimeLimitInMilliseconds -> (sessionTimeLimitInMilliseconds - botEventContext.timeInMilliseconds) // 1000)


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

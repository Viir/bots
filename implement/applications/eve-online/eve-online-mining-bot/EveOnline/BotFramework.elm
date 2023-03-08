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

import Array
import Bitwise
import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import Common.Basics
import Common.EffectOnWindow
import CompilationInterface.SourceFiles
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseGuiFromScreenshot
import EveOnline.ParseUserInterface exposing (DisplayRegion, centerFromDisplayRegion, getAllContainedDisplayTextsWithRegion)
import EveOnline.VolatileProcessInterface as VolatileProcessInterface
import Json.Decode
import List.Extra
import Maybe.Extra
import String.Extra


type alias BotConfiguration botSettings botState =
    { parseBotSettings : String -> Result String botSettings
    , selectGameClientInstance : Maybe botSettings -> List GameClientProcessSummary -> Result String { selectedProcess : GameClientProcessSummary, report : List String }
    , processEvent : BotEventContext botSettings -> BotEvent -> botState -> ( botState, BotEventResponse )
    }


type BotEvent
    = ReadingFromGameClientCompleted ReadingFromGameClientCompletedStruct


type alias ReadingFromGameClientCompletedStruct =
    { parsed : EveOnline.ParseUserInterface.ParsedUserInterface
    , screenshot : ReadingFromGameClientScreenshot
    , randomIntegers : List Int
    }


type BotEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession { statusText : String }


type InternalBotEventResponse
    = InternalContinueSession InternalContinueSessionStructure
    | InternalFinishSession { statusText : String }


type alias InternalContinueSessionStructure =
    { statusText : String
    , startTasks : List { areaId : String, taskType : Maybe TaskType, task : InterfaceToHost.Task }
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type TaskType
    = SetupTaskType { description : String }


type alias ContinueSessionStructure =
    { effects : List Common.EffectOnWindow.EffectOnWindowStructure
    , millisecondsToNextReadingFromGame : Int
    , statusText : String
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
    , waitingForSetupTasks : List { taskId : String, description : String }
    , botSettings : Maybe botSettings
    , sessionTimeLimitInMilliseconds : Maybe Int
    }


type alias BotAndLastEventState botState =
    { botState : botState
    , lastEvent :
        Maybe
            { timeInMilliseconds : Int
            , eventResult : ( botState, BotEventResponse )
            }
    }


type alias SetupState =
    { createVolatileProcessResult : Maybe (Result InterfaceToHost.CreateVolatileProcessErrorStructure InterfaceToHost.CreateVolatileProcessComplete)
    , requestsToVolatileProcessCount : Int
    , lastRequestToVolatileProcessResult : Maybe (Result String ( InterfaceToHost.RequestToVolatileProcessComplete, Result String VolatileProcessInterface.ResponseFromVolatileHost ))
    , gameClientProcesses : Maybe (List GameClientProcessSummary)
    , searchUIRootAddressResponse :
        Maybe { timeInMilliseconds : Int, response : VolatileProcessInterface.SearchUIRootAddressResponseStruct }
    , lastReadingFromGame : Maybe { timeInMilliseconds : Int, stage : ReadingFromGameState }
    , lastEffectFailedToAcquireInputFocus : Maybe String
    , randomIntegers : List Int
    }


type ReadingFromGameState
    = ReadingFromGameInProgress ReadingFromGameClientAggregateState
    | ReadingFromGameCompleted { timeInMilliseconds : Int }


type alias ReadingFromGameClientAggregateState =
    { memoryReading : Maybe VolatileProcessInterface.ReadFromWindowResultStructure
    , readingFromWindow : Maybe InterfaceToHost.ReadFromWindowCompleteStruct
    }


type SetupTask
    = ContinueSetup SetupState (Maybe InterfaceToHost.Task) String
    | OperateBot OperateBotConfiguration
    | FrameworkStopSession String


type alias OperateBotConfiguration =
    { buildTaskFromEffectSequence : List Common.EffectOnWindow.EffectOnWindowStructure -> InterfaceToHost.Task
    , readFromWindowTasks : List InterfaceToHost.Task
    , releaseVolatileProcessTask : InterfaceToHost.Task
    }


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias GameClientProcessSummary =
    VolatileProcessInterface.GameClientProcessSummaryStruct


type alias ShipModulesMemory =
    { tooltipFromModuleButton : Dict.Dict String ModuleButtonTooltipMemory
    , previousReadingTooltip : Maybe ModuleButtonTooltipMemory
    }


type alias ReadingFromGameClientMemory =
    { contextMenus : List ContextMenu
    }


type alias ModuleButtonTooltipMemory =
    { uiNodeDisplayRegion : DisplayRegion
    , shortcut : Maybe { text : String, parseResult : Result String (List Common.EffectOnWindow.VirtualKeyCode) }
    , optimalRange : Maybe { asString : String, inMeters : Result String Int }
    , allContainedDisplayTextsWithRegion : List ( String, DisplayRegion )
    }


type alias ContextMenu =
    { uiNode : UITreeNodeWithDisplayRegion
    , entries : List ContextMenuEntry
    }


type alias ContextMenuEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , text : String
    }


type alias UITreeNodeWithDisplayRegion =
    { uiNode : { pythonObjectAddress : String }
    , totalDisplayRegion : EveOnline.ParseUserInterface.DisplayRegion
    }


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindows : List EveOnline.ParseUserInterface.OverviewWindow
    }


type alias ReadingFromGameClientScreenshot =
    EveOnline.ParseGuiFromScreenshot.ReadingFromGameClientScreenshot


type alias PixelValueRGB =
    EveOnline.ParseGuiFromScreenshot.PixelValueRGB


type alias ReadingFromGameClientStructure =
    { parsedMemoryReading : EveOnline.ParseUserInterface.ParsedUserInterface
    , readingFromWindow : InterfaceToHost.ReadFromWindowCompleteStruct
    }


type alias ImageCrop =
    { offset : InterfaceToHost.WinApiPointStruct
    , widthPixels : Int
    , pixels : Array.Array Int
    }


type alias Location2d =
    EveOnline.ParseUserInterface.Location2d


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
    , previousReadingTooltip = Nothing
    }


integrateCurrentReadingsIntoShipModulesMemory : EveOnline.ParseUserInterface.ParsedUserInterface -> ShipModulesMemory -> ShipModulesMemory
integrateCurrentReadingsIntoShipModulesMemory currentReading memoryBefore =
    let
        currentTooltipMemory =
            currentReading.moduleButtonTooltip
                |> Maybe.map asModuleButtonTooltipMemory

        getTooltipDataForEqualityComparison tooltip =
            tooltip.allContainedDisplayTextsWithRegion

        {- To ensure robustness, we store a new tooltip only when the display texts from two game client readings are similar enough. -}
        tooltipAvailableToStore =
            case ( memoryBefore.previousReadingTooltip, currentTooltipMemory ) of
                ( Just previousTooltip, Just currentTooltip ) ->
                    let
                        previousVariants =
                            previousTooltip
                                :: commonReductionsOfModuleButtonTooltipMemoryForRobustness previousTooltip
                                |> List.map getTooltipDataForEqualityComparison
                                |> List.Extra.unique

                        currentVariants =
                            currentTooltip
                                :: commonReductionsOfModuleButtonTooltipMemoryForRobustness currentTooltip
                                |> List.Extra.unique
                    in
                    currentVariants
                        |> List.filter (getTooltipDataForEqualityComparison >> (<|) List.member >> (|>) previousVariants)
                        |> List.head

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
    , previousReadingTooltip =
        currentTooltipMemory
            |> Maybe.Extra.orElse memoryBefore.previousReadingTooltip
    }


commonReductionsOfModuleButtonTooltipMemoryForRobustness : ModuleButtonTooltipMemory -> List ModuleButtonTooltipMemory
commonReductionsOfModuleButtonTooltipMemoryForRobustness originalTooltip =
    {-
       Adapt to the game client from session-recording-2023-03-03T12-59-09:
       The tooltips of some module buttons exhibit frequently changing text.
       In the said session, one of the texts changes from '01:42' in event 80 to '01:39' in event 84.
       In that module tooltip is another text element left of the changing text, containing "Activation time / duration".
    -}
    let
        allContainedDisplayTextsWithRegionTrimmed =
            originalTooltip.allContainedDisplayTextsWithRegion
                |> List.map (Tuple.mapFirst String.trim)

        reduceTextIfTime text =
            if
                String.split ":" text
                    |> List.all (String.toInt >> (/=) Nothing)
            then
                "reduced-time"

            else
                text

        reduceTimeFromText =
            String.split " "
                >> List.map reduceTextIfTime
                >> String.join " "

        allContainedDisplayTextsWithRegionTimeReduced =
            allContainedDisplayTextsWithRegionTrimmed
                |> List.map (Tuple.mapFirst reduceTimeFromText)
    in
    [ { originalTooltip
        | allContainedDisplayTextsWithRegion = allContainedDisplayTextsWithRegionTrimmed
      }
    , { originalTooltip
        | allContainedDisplayTextsWithRegion = allContainedDisplayTextsWithRegionTimeReduced
      }
    ]


getModuleButtonTooltipFromModuleButton : ShipModulesMemory -> EveOnline.ParseUserInterface.ShipUIModuleButton -> Maybe ModuleButtonTooltipMemory
getModuleButtonTooltipFromModuleButton moduleMemory moduleButton =
    moduleMemory.tooltipFromModuleButton |> Dict.get (moduleButton |> getModuleButtonIdentifierInMemory)


getModuleButtonIdentifierInMemory : EveOnline.ParseUserInterface.ShipUIModuleButton -> String
getModuleButtonIdentifierInMemory =
    .uiNode >> .uiNode >> .pythonObjectAddress


initState : botState -> StateIncludingFramework botSettings botState
initState botState =
    { setup = initSetup
    , botState =
        { botState = botState
        , lastEvent = Nothing
        }
    , timeInMilliseconds = 0
    , lastTaskIndex = 0
    , waitingForSetupTasks = []
    , botSettings = Nothing
    , sessionTimeLimitInMilliseconds = Nothing
    }


initSetup : SetupState
initSetup =
    { createVolatileProcessResult = Nothing
    , requestsToVolatileProcessCount = 0
    , lastRequestToVolatileProcessResult = Nothing
    , gameClientProcesses = Nothing
    , searchUIRootAddressResponse = Nothing
    , lastReadingFromGame = Nothing
    , lastEffectFailedToAcquireInputFocus = Nothing
    , randomIntegers = []
    }


processEvent :
    BotConfiguration botSettings botState
    -> InterfaceToHost.BotEvent
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InterfaceToHost.BotEventResponse )
processEvent botConfiguration fromHostEvent stateBefore =
    let
        ( state, response ) =
            processEventLessMappingTasks botConfiguration fromHostEvent stateBefore
    in
    case response of
        InternalFinishSession finishSession ->
            ( state, InterfaceToHost.FinishSession finishSession )

        InternalContinueSession continueSession ->
            let
                startTasksWithOrigin =
                    continueSession.startTasks
                        |> List.indexedMap
                            (\startTaskIndex startTask ->
                                let
                                    taskIdString =
                                        startTask.areaId ++ "-" ++ String.fromInt (state.lastTaskIndex + startTaskIndex)
                                in
                                { taskId = taskIdString
                                , task = startTask.task
                                , taskType = startTask.taskType
                                }
                            )

                waitingForSetupTasks =
                    (startTasksWithOrigin
                        |> List.filterMap
                            (\startTask ->
                                case startTask.taskType of
                                    Just (SetupTaskType setupTask) ->
                                        Just { taskId = startTask.taskId, description = setupTask.description }

                                    _ ->
                                        Nothing
                            )
                    )
                        ++ state.waitingForSetupTasks

                startTasks =
                    startTasksWithOrigin
                        |> List.map (\startTask -> { taskId = startTask.taskId, task = startTask.task })
            in
            ( { state
                | lastTaskIndex = state.lastTaskIndex + List.length startTasks
                , waitingForSetupTasks = waitingForSetupTasks
              }
            , InterfaceToHost.ContinueSession
                { statusText = continueSession.statusText
                , startTasks = startTasks
                , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                }
            )


processEventLessMappingTasks :
    BotConfiguration botSettings botState
    -> InterfaceToHost.BotEvent
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventLessMappingTasks botConfiguration fromHostEvent stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = fromHostEvent.timeInMilliseconds }

        continueAfterIntegrateEvent =
            processEventAfterIntegrateEvent botConfiguration
    in
    case fromHostEvent.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            continueAfterIntegrateEvent stateBefore

        InterfaceToHost.TaskCompletedEvent taskComplete ->
            let
                waitingForSetupTasks =
                    stateBefore.waitingForSetupTasks
                        |> List.filter (.taskId >> (/=) taskComplete.taskId)

                setupState =
                    stateBefore.setup
                        |> integrateTaskResult ( stateBefore.timeInMilliseconds, taskComplete.taskResult )
            in
            continueAfterIntegrateEvent
                { stateBefore
                    | setup = setupState
                    , waitingForSetupTasks = waitingForSetupTasks
                }

        InterfaceToHost.BotSettingsChangedEvent botSettings ->
            case botConfiguration.parseBotSettings botSettings of
                Err parseSettingsError ->
                    ( stateBefore
                    , InternalFinishSession
                        { statusText = "Failed to parse these bot-settings: " ++ parseSettingsError }
                    )

                Ok parsedBotSettings ->
                    ( { stateBefore | botSettings = Just parsedBotSettings }
                    , InternalContinueSession
                        { statusText = "Succeeded parsing these bot-settings."
                        , startTasks = []
                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = 0 }
                        }
                    )

        InterfaceToHost.SessionDurationPlannedEvent sessionTimeLimit ->
            continueAfterIntegrateEvent
                { stateBefore | sessionTimeLimitInMilliseconds = Just sessionTimeLimit.timeInMilliseconds }


processEventAfterIntegrateEvent :
    BotConfiguration botSettings botState
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventAfterIntegrateEvent botConfiguration stateBefore =
    let
        ( stateBeforeCountingRequests, responseBeforeAddingStatusMessage ) =
            case stateBefore.botSettings of
                Nothing ->
                    ( stateBefore
                    , InternalFinishSession
                        { statusText =
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
                        stateBefore

        newRequestsToVolatileProcessCount =
            case responseBeforeAddingStatusMessage of
                InternalFinishSession _ ->
                    0

                InternalContinueSession continueSession ->
                    continueSession.startTasks
                        |> List.map
                            (\startTask ->
                                case startTask.task of
                                    InterfaceToHost.RequestToVolatileProcess _ ->
                                        1

                                    _ ->
                                        0
                            )
                        |> List.sum

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

        commonStatusMessagePrefix =
            statusReportFromState state

        notifyWhenArrivedAtTimeUpperBound =
            stateBefore.timeInMilliseconds + 2000

        startTasksGetRandom =
            if 100 < List.length state.setup.randomIntegers then
                []

            else
                [ { areaId = "get-entropy"
                  , taskType = Nothing
                  , task = InterfaceToHost.RandomBytesRequest 300
                  }
                ]

        response =
            case responseBeforeAddingStatusMessage of
                InternalContinueSession continueSession ->
                    InternalContinueSession
                        { continueSession
                            | statusText =
                                [ commonStatusMessagePrefix
                                , continueSession.statusText
                                ]
                                    |> String.join "\n"
                            , notifyWhenArrivedAtTime =
                                Just
                                    { timeInMilliseconds =
                                        continueSession.notifyWhenArrivedAtTime
                                            |> Maybe.map .timeInMilliseconds
                                            |> Maybe.withDefault notifyWhenArrivedAtTimeUpperBound
                                            |> min notifyWhenArrivedAtTimeUpperBound
                                    }
                            , startTasks = continueSession.startTasks ++ startTasksGetRandom
                        }

                InternalFinishSession finishSession ->
                    InternalFinishSession
                        { statusText =
                            [ commonStatusMessagePrefix
                            , finishSession.statusText
                            ]
                                |> String.join "\n"
                        }
    in
    ( state, response )


processEventNotWaitingForTaskCompletion :
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> StateIncludingFramework botSettings botState
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
processEventNotWaitingForTaskCompletion botConfiguration botEventContext stateBefore =
    case
        stateBefore.setup
            |> getNextSetupTask
                { timeInMilliseconds = stateBefore.timeInMilliseconds }
                botConfiguration
                stateBefore.botSettings
    of
        ContinueSetup setupState maybeSetupTask setupTaskDescription ->
            case List.head stateBefore.waitingForSetupTasks of
                Nothing ->
                    ( { stateBefore | setup = setupState }
                    , { startTasks =
                            maybeSetupTask
                                |> Maybe.map
                                    (\setupTask ->
                                        [ { areaId = "setup"
                                          , task = setupTask
                                          , taskType = Just (SetupTaskType { description = setupTaskDescription })
                                          }
                                        ]
                                    )
                                |> Maybe.withDefault []
                      , statusText = setupTaskDescription
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                      }
                        |> InternalContinueSession
                    )

                Just waitingForSetupTask ->
                    ( stateBefore
                    , { startTasks = []
                      , statusText = "Wait for completion: " ++ waitingForSetupTask.description
                      , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                      }
                        |> InternalContinueSession
                    )

        OperateBot operateBot ->
            if volatileProcessRecycleInterval < stateBefore.setup.requestsToVolatileProcessCount then
                let
                    taskAreaIdString =
                        "maintain"

                    setupStateBefore =
                        stateBefore.setup

                    setupState =
                        { setupStateBefore | createVolatileProcessResult = Nothing }

                    setupTaskDescription =
                        "Recycle the volatile process after " ++ (setupStateBefore.requestsToVolatileProcessCount |> String.fromInt) ++ " requests."
                in
                ( { stateBefore | setup = setupState }
                , { startTasks =
                        [ { areaId = taskAreaIdString
                          , task = operateBot.releaseVolatileProcessTask
                          , taskType = Just (SetupTaskType { description = setupTaskDescription })
                          }
                        ]
                  , statusText = setupTaskDescription
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 2000 }
                  }
                    |> InternalContinueSession
                )

            else
                operateBotExceptRenewingVolatileProcess
                    botConfiguration
                    botEventContext
                    stateBefore
                    operateBot

        FrameworkStopSession reason ->
            ( stateBefore
            , InternalFinishSession { statusText = "Stop session (" ++ reason ++ ")" }
            )


operateBotExceptRenewingVolatileProcess :
    BotConfiguration botSettings botState
    -> BotEventContext botSettings
    -> StateIncludingFramework botSettings botState
    -> OperateBotConfiguration
    -> ( StateIncludingFramework botSettings botState, InternalBotEventResponse )
operateBotExceptRenewingVolatileProcess botConfiguration botEventContext stateBefore operateBot =
    let
        setupStateBefore =
            stateBefore.setup

        continueSessionStatusText statusTextState =
            [ "Reading from game"
            , case statusTextState.setup.lastReadingFromGame of
                Nothing ->
                    "not started"

                Just lastReadingFromGame ->
                    case lastReadingFromGame.stage of
                        ReadingFromGameInProgress _ ->
                            "in progress"

                        ReadingFromGameCompleted completed ->
                            let
                                ageInSeconds =
                                    (statusTextState.timeInMilliseconds - completed.timeInMilliseconds) // 1000
                            in
                            "completed "
                                ++ (if ageInSeconds < 1 then
                                        ""

                                    else
                                        String.fromInt ageInSeconds ++ " s ago"
                                   )
            ]
                |> String.join " "

        maybeReadingFromGameClient =
            case stateBefore.setup.lastReadingFromGame of
                Nothing ->
                    Nothing

                Just lastReadingFromGame ->
                    case lastReadingFromGame.stage of
                        ReadingFromGameCompleted _ ->
                            Nothing

                        ReadingFromGameInProgress aggregate ->
                            aggregate
                                |> parseReadingFromGameClient
                                |> Result.toMaybe

        continueWithReadingFromGameClient =
            let
                state =
                    { stateBefore
                        | setup =
                            { setupStateBefore
                                | lastReadingFromGame =
                                    Just
                                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                                        , stage =
                                            ReadingFromGameInProgress
                                                { memoryReading = Nothing
                                                , readingFromWindow = Nothing
                                                }
                                        }
                            }
                    }
            in
            ( state
            , { startTasks =
                    operateBot.readFromWindowTasks
                        |> List.map
                            (\task ->
                                { areaId = "read-from-game"
                                , taskType = Nothing
                                , task = task
                                }
                            )
              , statusText = continueSessionStatusText state
              , notifyWhenArrivedAtTime = Nothing
              }
                |> InternalContinueSession
            )
    in
    case maybeReadingFromGameClient of
        Just readingFromGameClient ->
            let
                clientRectOffset =
                    readingFromGameClient.readingFromWindow.clientRectLeftUpperToScreen

                pixelFromCropsInClientArea binningFactor crops ( pixelX, pixelY ) =
                    pixelFromCrops crops
                        ( pixelX + (clientRectOffset.x // binningFactor)
                        , pixelY + (clientRectOffset.y // binningFactor)
                        )

                screenshotCrops_original =
                    readingFromGameClient.readingFromWindow.imageData.screenshotCrops_original
                        |> List.map parseImageCropFromInterface
                        |> List.filterMap Result.toMaybe

                screenshotCrops_binned_2x2 =
                    readingFromGameClient.readingFromWindow.imageData.screenshotCrops_binned_2x2
                        |> List.map parseImageCropFromInterface
                        |> List.filterMap Result.toMaybe

                screenshot =
                    { pixels_1x1 = screenshotCrops_original |> pixelFromCropsInClientArea 1
                    , pixels_2x2 = screenshotCrops_binned_2x2 |> pixelFromCropsInClientArea 2
                    }

                ( parsedUserInterface, statusTextAdditionFromParseFromScreenshot ) =
                    case
                        readingFromGameClient.parsedMemoryReading
                            |> EveOnline.ParseGuiFromScreenshot.parseUserInterfaceFromScreenshot screenshot
                    of
                        Ok parsed ->
                            ( parsed, [] )

                        Err parseErr ->
                            ( readingFromGameClient.parsedMemoryReading
                            , [ "Failed to parse user interface: " ++ parseErr ]
                            )

                botStateBefore =
                    stateBefore.botState

                botEvent =
                    ReadingFromGameClientCompleted
                        { parsed = parsedUserInterface
                        , screenshot = screenshot
                        , randomIntegers = setupStateBefore.randomIntegers
                        }

                ( newBotState, botEventResponse ) =
                    botStateBefore.botState
                        |> botConfiguration.processEvent botEventContext botEvent

                lastEvent =
                    { timeInMilliseconds = stateBefore.timeInMilliseconds
                    , eventResult = ( newBotState, botEventResponse )
                    }

                sharedStatusTextAddition =
                    statusTextAdditionFromParseFromScreenshot

                setup =
                    { setupStateBefore
                        | lastReadingFromGame =
                            setupStateBefore.lastReadingFromGame
                                |> Maybe.map
                                    (\lastReadingFromGame ->
                                        { lastReadingFromGame
                                            | stage =
                                                ReadingFromGameCompleted
                                                    { timeInMilliseconds = stateBefore.timeInMilliseconds }
                                        }
                                    )
                        , randomIntegers = List.drop 1 setupStateBefore.randomIntegers
                    }

                state =
                    { stateBefore
                        | botState =
                            { botStateBefore
                                | botState = newBotState
                                , lastEvent = Just lastEvent
                            }
                        , setup = setup
                    }

                response =
                    case botEventResponse of
                        FinishSession _ ->
                            InternalFinishSession
                                { statusText =
                                    "The bot finished the session."
                                        :: sharedStatusTextAddition
                                        |> String.join "\n"
                                }

                        ContinueSession continueSession ->
                            let
                                timeForNextReadingFromGame =
                                    stateBefore.timeInMilliseconds
                                        + continueSession.millisecondsToNextReadingFromGame

                                startTasks =
                                    case continueSession.effects of
                                        [] ->
                                            []

                                        effects ->
                                            [ { areaId = "send-effects"
                                              , taskType = Nothing
                                              , task = operateBot.buildTaskFromEffectSequence effects
                                              }
                                            ]
                            in
                            { startTasks = startTasks
                            , statusText =
                                continueSessionStatusText state
                                    :: sharedStatusTextAddition
                                    |> String.join "\n"
                            , notifyWhenArrivedAtTime =
                                if startTasks == [] then
                                    Just { timeInMilliseconds = timeForNextReadingFromGame }

                                else
                                    Nothing
                            }
                                |> InternalContinueSession
            in
            ( state, response )

        Nothing ->
            let
                timeForNextReadingFromGameGeneral =
                    (stateBefore.setup.lastReadingFromGame
                        |> Maybe.map .timeInMilliseconds
                        |> Maybe.withDefault 0
                    )
                        + 5000

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

                nextReadingLowerBoundByLast =
                    case stateBefore.setup.lastReadingFromGame of
                        Nothing ->
                            0

                        Just startedReading ->
                            let
                                lastReadingCompleted =
                                    case stateBefore.setup.lastReadingFromGame of
                                        Nothing ->
                                            False

                                        Just lastReadingFromGame ->
                                            startedReading.timeInMilliseconds < lastReadingFromGame.timeInMilliseconds
                            in
                            if lastReadingCompleted then
                                0

                            else
                                startedReading.timeInMilliseconds + 3000

                timeForNextReadingFromGame =
                    timeForNextReadingFromGameFromBot
                        |> min timeForNextReadingFromGameGeneral
                        |> max nextReadingLowerBoundByLast

                remainingTimeToNextReadingFromGame =
                    timeForNextReadingFromGame - stateBefore.timeInMilliseconds
            in
            if remainingTimeToNextReadingFromGame <= 0 then
                continueWithReadingFromGameClient

            else
                ( stateBefore
                , { startTasks = []
                  , statusText = continueSessionStatusText stateBefore
                  , notifyWhenArrivedAtTime = Just { timeInMilliseconds = timeForNextReadingFromGame }
                  }
                    |> InternalContinueSession
                )


pixelFromCrops : List ImageCrop -> ( Int, Int ) -> Maybe PixelValueRGB
pixelFromCrops crops ( pixelX, pixelY ) =
    crops
        |> List.Extra.findMap
            (\imageCrop ->
                let
                    inCropX =
                        pixelX - imageCrop.offset.x

                    inCropY =
                        pixelY - imageCrop.offset.y
                in
                if inCropX < 0 || inCropY < 0 || imageCrop.widthPixels <= inCropX then
                    Nothing

                else
                    Array.get (inCropY * imageCrop.widthPixels + inCropX) imageCrop.pixels
                        |> Maybe.map colorFromInt_R8G8B8
            )


parseImageCropFromInterface : InterfaceToHost.ImageCrop -> Result String ImageCrop
parseImageCropFromInterface imageCrop =
    imageCrop.pixelsString
        |> parseImageCropPixelsArrayFromPixelsString
        |> Result.map
            (\pixels ->
                { offset = imageCrop.offset
                , widthPixels = imageCrop.widthPixels
                , pixels = pixels
                }
            )


parseImageCropPixelsArrayFromPixelsString : String -> Result String (Array.Array Int)
parseImageCropPixelsArrayFromPixelsString =
    Json.Decode.decodeString
        (Json.Decode.array Json.Decode.int)
        >> Result.mapError Json.Decode.errorToString


integrateTaskResult :
    ( Int, InterfaceToHost.TaskResultStructure )
    -> SetupState
    -> SetupState
integrateTaskResult ( timeInMilliseconds, taskResult ) setupStateBefore =
    case taskResult of
        InterfaceToHost.CreateVolatileProcessResponse createVolatileProcessResult ->
            { setupStateBefore
                | createVolatileProcessResult = Just createVolatileProcessResult
                , requestsToVolatileProcessCount = 0
            }

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.ProcessNotFound) ->
            { setupStateBefore | createVolatileProcessResult = Nothing }

        InterfaceToHost.RequestToVolatileProcessResponse (Err InterfaceToHost.FailedToAcquireInputFocus) ->
            { setupStateBefore | lastEffectFailedToAcquireInputFocus = Just "Failed before entering volatile process." }

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
                    setupStateWithScriptRunResult

                Just responseFromVolatileProcessOk ->
                    setupStateWithScriptRunResult
                        |> integrateResponseFromVolatileProcess
                            { timeInMilliseconds = timeInMilliseconds }
                            responseFromVolatileProcessOk

        InterfaceToHost.OpenWindowResponse _ ->
            setupStateBefore

        InterfaceToHost.InvokeMethodOnWindowResponse _ methodOnWindowResult ->
            case methodOnWindowResult of
                Ok (InterfaceToHost.ReadFromWindowMethodResult readFromWindowComplete) ->
                    setupStateBefore
                        |> integrateReadFromWindowComplete
                            { timeInMilliseconds = timeInMilliseconds
                            , readFromWindowComplete = readFromWindowComplete
                            }

                _ ->
                    setupStateBefore

        InterfaceToHost.RandomBytesResponse randomBytes ->
            { setupStateBefore
                | randomIntegers = setupStateBefore.randomIntegers ++ randomIntegersFromRandomBytes randomBytes
            }

        InterfaceToHost.CompleteWithoutResult ->
            setupStateBefore


randomIntegersFromRandomBytes : List Int -> List Int
randomIntegersFromRandomBytes bytes =
    case bytes of
        a :: b :: c :: d :: e :: f :: remaining ->
            ((((((a - 127) * 255 + b) * 255 + c) * 255 + d) * 255 + e) * 255 + f)
                :: randomIntegersFromRandomBytes remaining

        _ ->
            []


integrateResponseFromVolatileProcess :
    { timeInMilliseconds : Int }
    -> VolatileProcessInterface.ResponseFromVolatileHost
    -> SetupState
    -> SetupState
integrateResponseFromVolatileProcess { timeInMilliseconds } responseFromVolatileProcess stateBefore =
    case responseFromVolatileProcess of
        VolatileProcessInterface.ListGameClientProcessesResponse gameClientProcesses ->
            { stateBefore | gameClientProcesses = Just gameClientProcesses }

        VolatileProcessInterface.SearchUIRootAddressResponse searchUIRootAddressResponse ->
            let
                state =
                    { stateBefore
                        | searchUIRootAddressResponse =
                            Just
                                { timeInMilliseconds = timeInMilliseconds
                                , response = searchUIRootAddressResponse
                                }
                    }
            in
            state

        VolatileProcessInterface.ReadFromWindowResult readFromWindowResult ->
            let
                readingTimeInMilliseconds =
                    stateBefore.lastReadingFromGame
                        |> Maybe.map .timeInMilliseconds
                        |> Maybe.withDefault timeInMilliseconds

                inProgressBefore =
                    case stateBefore.lastReadingFromGame of
                        Nothing ->
                            { memoryReading = Nothing
                            , readingFromWindow = Nothing
                            }

                        Just lastReadingFromGame ->
                            case lastReadingFromGame.stage of
                                ReadingFromGameCompleted _ ->
                                    { memoryReading = Nothing
                                    , readingFromWindow = Nothing
                                    }

                                ReadingFromGameInProgress readingInProgress ->
                                    readingInProgress

                inProgress =
                    { inProgressBefore
                        | memoryReading = Just readFromWindowResult
                    }
            in
            { stateBefore
                | lastReadingFromGame =
                    Just
                        { timeInMilliseconds = readingTimeInMilliseconds
                        , stage = ReadingFromGameInProgress inProgress
                        }
            }

        VolatileProcessInterface.FailedToBringWindowToFront error ->
            { stateBefore | lastEffectFailedToAcquireInputFocus = Just error }

        VolatileProcessInterface.CompletedEffectSequenceOnWindow ->
            { stateBefore | lastEffectFailedToAcquireInputFocus = Nothing }


integrateReadFromWindowComplete :
    { timeInMilliseconds : Int, readFromWindowComplete : InterfaceToHost.ReadFromWindowCompleteStruct }
    -> SetupState
    -> SetupState
integrateReadFromWindowComplete { timeInMilliseconds, readFromWindowComplete } stateBefore =
    let
        readingTimeInMilliseconds =
            stateBefore.lastReadingFromGame
                |> Maybe.map .timeInMilliseconds
                |> Maybe.withDefault timeInMilliseconds

        inProgressBefore =
            case stateBefore.lastReadingFromGame of
                Nothing ->
                    { memoryReading = Nothing
                    , readingFromWindow = Nothing
                    }

                Just lastReadingFromGame ->
                    case lastReadingFromGame.stage of
                        ReadingFromGameCompleted _ ->
                            { memoryReading = Nothing
                            , readingFromWindow = Nothing
                            }

                        ReadingFromGameInProgress readingInProgress ->
                            readingInProgress

        inProgress =
            { inProgressBefore | readingFromWindow = Just readFromWindowComplete }
    in
    { stateBefore
        | lastReadingFromGame =
            Just
                { timeInMilliseconds = readingTimeInMilliseconds
                , stage = ReadingFromGameInProgress inProgress
                }
    }


colorFromInt_R8G8B8 : Int -> PixelValueRGB
colorFromInt_R8G8B8 combined =
    { red = combined |> Bitwise.shiftRightZfBy 16 |> Bitwise.and 0xFF
    , green = combined |> Bitwise.shiftRightZfBy 8 |> Bitwise.and 0xFF
    , blue = combined |> Bitwise.and 0xFF
    }


parseReadingFromGameClient :
    ReadingFromGameClientAggregateState
    -> Result String ReadingFromGameClientStructure
parseReadingFromGameClient readingAggregate =
    case readingAggregate.memoryReading of
        Nothing ->
            Err "Memory reading not completed"

        Just memoryReading ->
            case memoryReading of
                VolatileProcessInterface.ProcessNotFound ->
                    Err "Initial reading failed with 'Process Not Found'"

                VolatileProcessInterface.Completed completedReading ->
                    case completedReading.memoryReadingSerialRepresentationJson of
                        Nothing ->
                            Err "Missing json representation of memory reading"

                        Just memoryReadingSerialRepresentationJson ->
                            case readingAggregate.readingFromWindow of
                                Nothing ->
                                    Err "Reading from window not arrived yet"

                                Just readingFromWindow ->
                                    memoryReadingSerialRepresentationJson
                                        |> EveOnline.MemoryReading.decodeMemoryReadingFromString
                                        |> Result.mapError Json.Decode.errorToString
                                        |> Result.map (EveOnline.ParseUserInterface.parseUITreeWithDisplayRegionFromUITree >> EveOnline.ParseUserInterface.parseUserInterfaceFromUITree)
                                        |> Result.map
                                            (\parsedMemoryReading ->
                                                { parsedMemoryReading = parsedMemoryReading
                                                , readingFromWindow = readingFromWindow
                                                }
                                            )


getNextSetupTask :
    { timeInMilliseconds : Int }
    -> BotConfiguration botSettings botState
    -> Maybe botSettings
    -> SetupState
    -> SetupTask
getNextSetupTask { timeInMilliseconds } botConfiguration botSettings stateBefore =
    case stateBefore.createVolatileProcessResult of
        Nothing ->
            ContinueSetup
                stateBefore
                (Just
                    (InterfaceToHost.CreateVolatileProcess
                        { programCode = CompilationInterface.SourceFiles.file____EveOnline_VolatileProcess_csx.utf8 }
                    )
                )
                "Setting up volatile process. This can take several seconds, especially when assemblies are not cached yet."

        Just (Err error) ->
            FrameworkStopSession ("Create volatile process failed with exception: " ++ error.exceptionToString)

        Just (Ok createVolatileProcessComplete) ->
            getSetupTaskWhenVolatileProcessSetupCompleted
                { timeInMilliseconds = timeInMilliseconds }
                botConfiguration
                botSettings
                stateBefore
                createVolatileProcessComplete.processId


getSetupTaskWhenVolatileProcessSetupCompleted :
    { timeInMilliseconds : Int }
    -> BotConfiguration botSettings appState
    -> Maybe botSettings
    -> SetupState
    -> String
    -> SetupTask
getSetupTaskWhenVolatileProcessSetupCompleted { timeInMilliseconds } botConfiguration botSettings stateBefore volatileProcessId =
    case stateBefore.gameClientProcesses of
        Nothing ->
            ContinueSetup
                stateBefore
                (Just
                    (InterfaceToHost.RequestToVolatileProcess
                        (InterfaceToHost.RequestNotRequiringInputFocus
                            { processId = volatileProcessId
                            , request =
                                VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                    VolatileProcessInterface.ListGameClientProcessesRequest
                            }
                        )
                    )
                )
                "Get list of EVE Online client processes."

        Just gameClientProcesses ->
            case gameClientProcesses |> botConfiguration.selectGameClientInstance botSettings of
                Err selectGameClientProcessError ->
                    FrameworkStopSession ("Failed to select the game client process: " ++ selectGameClientProcessError)

                Ok gameClientSelection ->
                    let
                        continueWithSearchUIRootAddress timeToSendRequest =
                            ContinueSetup
                                stateBefore
                                (if not timeToSendRequest then
                                    Nothing

                                 else
                                    Just
                                        (InterfaceToHost.RequestToVolatileProcess
                                            (InterfaceToHost.RequestNotRequiringInputFocus
                                                { processId = volatileProcessId
                                                , request =
                                                    VolatileProcessInterface.buildRequestStringToGetResponseFromVolatileHost
                                                        (VolatileProcessInterface.SearchUIRootAddress { processId = gameClientSelection.selectedProcess.processId })
                                                }
                                            )
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
                    case stateBefore.searchUIRootAddressResponse of
                        Nothing ->
                            continueWithSearchUIRootAddress True

                        Just responseAtTime ->
                            let
                                timeToSendRequest =
                                    1000 < timeInMilliseconds - responseAtTime.timeInMilliseconds
                            in
                            if responseAtTime.response.processId /= gameClientSelection.selectedProcess.processId then
                                continueWithSearchUIRootAddress timeToSendRequest

                            else
                                case responseAtTime.response.stage of
                                    VolatileProcessInterface.SearchUIRootAddressInProgress _ ->
                                        continueWithSearchUIRootAddress timeToSendRequest

                                    VolatileProcessInterface.SearchUIRootAddressCompleted searchRootCompleted ->
                                        case searchRootCompleted.uiRootAddress of
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
                                                    readFromWindowRequest =
                                                        VolatileProcessInterface.ReadFromWindow
                                                            { windowId = gameClientSelection.selectedProcess.mainWindowId
                                                            , uiRootAddress = uiRootAddress
                                                            }
                                                in
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

                                                    buildTaskFromInvokeMethodOnWindowRequest methodOnWindow =
                                                        InterfaceToHost.InvokeMethodOnWindowRequest
                                                            ("winapi-" ++ gameClientSelection.selectedProcess.mainWindowId)
                                                            methodOnWindow

                                                    continueNormalOperation =
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
                                                            , readFromWindowTasks =
                                                                [ readFromWindowRequest
                                                                    |> buildTaskFromRequestToVolatileProcess
                                                                        (Just { maximumDelayMilliseconds = 500 })
                                                                , buildTaskFromInvokeMethodOnWindowRequest
                                                                    InterfaceToHost.ReadFromWindowMethod
                                                                ]
                                                            , releaseVolatileProcessTask = InterfaceToHost.ReleaseVolatileProcess { processId = volatileProcessId }
                                                            }
                                                in
                                                case stateBefore.lastReadingFromGame of
                                                    Nothing ->
                                                        continueNormalOperation

                                                    Just lastReadingFromGame ->
                                                        case lastReadingFromGame.stage of
                                                            ReadingFromGameCompleted _ ->
                                                                continueNormalOperation

                                                            ReadingFromGameInProgress inProgress ->
                                                                case inProgress.memoryReading of
                                                                    Nothing ->
                                                                        continueNormalOperation

                                                                    Just VolatileProcessInterface.ProcessNotFound ->
                                                                        FrameworkStopSession "The EVE Online client process disappeared."

                                                                    Just (VolatileProcessInterface.Completed _) ->
                                                                        continueNormalOperation


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
                |> List.filter (.mainWindowTitle >> Common.Basics.stringContainsIgnoringCase pilotName)
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
                                finishSession.statusText

                            ContinueSession continueSession ->
                                continueSession.statusText
                    )
                |> Maybe.withDefault ""

        inputFocusLines =
            case state.setup.lastEffectFailedToAcquireInputFocus of
                Nothing ->
                    []

                Just error ->
                    [ "Failed to acquire input focus: " ++ error ]
    in
    [ [ fromBot ]
    , [ "--------"
      , "EVE Online framework status:"
      ]
    , inputFocusLines
    ]
        |> List.concat
        |> String.join "\n"


{-| This works only while the context menu model does not support branching. In this special case, we can unpack the tree into a list.

With the switch to the new 'Photon UI' in the game client, the effects used to expand menu entries change: Before, the player used a click on the menu entry to expand its children, but now expanding it requires hovering the mouse over the menu entry.

-}
unpackContextMenuTreeToListOfActionsDependingOnReadings :
    UseContextMenuCascadeNode
    -> List (ReadingFromGameClient -> ( String, Maybe (List Common.EffectOnWindow.EffectOnWindowStructure) ))
unpackContextMenuTreeToListOfActionsDependingOnReadings treeNode =
    let
        actionFromChoice { isLastElement } ( describeChoice, chooseEntry ) =
            chooseEntry
                >> Maybe.map
                    (\menuEntry ->
                        let
                            useClick =
                                isLastElement
                                    || (String.toLower (String.trim menuEntry.text) == "dock")
                        in
                        if useClick then
                            ( "Click menu entry " ++ describeChoice ++ "."
                            , menuEntry.uiNode |> mouseClickOnUIElement Common.EffectOnWindow.MouseButtonLeft |> Just
                            )

                        else
                            ( "Hover menu entry " ++ describeChoice ++ "."
                            , menuEntry.uiNode |> mouseMoveToUIElement |> Just
                            )
                    )
                >> Maybe.withDefault
                    ( "Search menu entry " ++ describeChoice ++ "."
                    , Nothing
                    )

        listFromNextChoiceAndFollowingNodes nextChoice following =
            (nextChoice |> actionFromChoice { isLastElement = following == MenuCascadeCompleted })
                :: (following |> unpackContextMenuTreeToListOfActionsDependingOnReadings)
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


secondsToSessionEnd : BotEventContext a -> Maybe Int
secondsToSessionEnd botEventContext =
    botEventContext.sessionTimeLimitInMilliseconds
        |> Maybe.map (\sessionTimeLimitInMilliseconds -> (sessionTimeLimitInMilliseconds - botEventContext.timeInMilliseconds) // 1000)


mouseMoveToUIElement : UIElement -> List Common.EffectOnWindow.EffectOnWindowStructure
mouseMoveToUIElement uiElement =
    Common.EffectOnWindow.effectsMouseMoveToLocation
        (uiElement.totalDisplayRegionVisible |> centerFromDisplayRegion)


mouseClickOnUIElement : Common.EffectOnWindow.MouseButton -> UIElement -> List Common.EffectOnWindow.EffectOnWindowStructure
mouseClickOnUIElement mouseButton uiElement =
    Common.EffectOnWindow.effectsMouseClickAtLocation
        mouseButton
        (uiElement.totalDisplayRegionVisible |> centerFromDisplayRegion)


type UseContextMenuCascadeNode
    = MenuEntryWithCustomChoice { describeChoice : String, chooseEntry : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry } UseContextMenuCascadeNode
    | MenuCascadeCompleted


useMenuEntryWithTextContaining : String -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useMenuEntryWithTextContaining textToSearch =
    useMenuEntryInLastContextMenuInCascade
        { describeChoice = "with text containing '" ++ textToSearch ++ "'"
        , chooseEntry =
            List.filter (.text >> Common.Basics.stringContainsIgnoringCase textToSearch)
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
                                |> List.filter (.text >> Common.Basics.stringContainsIgnoringCase textToSearch)
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


useRandomMenuEntry : Int -> UseContextMenuCascadeNode -> UseContextMenuCascadeNode
useRandomMenuEntry randomInt =
    MenuEntryWithCustomChoice
        { describeChoice = "random entry"
        , chooseEntry =
            \readingFromGameClient ->
                readingFromGameClient
                    |> pickEntryFromLastContextMenuInCascade
                        (Common.Basics.listElementAtWrappedIndex randomInt)
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


quickMessageFromReadingFromGameClient : ReadingFromGameClient -> Maybe String
quickMessageFromReadingFromGameClient =
    .layerAbovemain
        >> Maybe.andThen .quickMessage
        >> Maybe.map (.text >> String.trim)


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
    findMouseButtonClickLocationsInListOfEffects Common.EffectOnWindow.MouseButtonLeft
        >> List.any (isPointInRectangle moduleButton.uiNode.totalDisplayRegion)


findMouseButtonClickLocationsInListOfEffects : Common.EffectOnWindow.MouseButton -> List Common.EffectOnWindow.EffectOnWindowStructure -> List Location2d
findMouseButtonClickLocationsInListOfEffects mouseButton =
    List.foldl
        (\effect ( maybeLastMouseMoveLocation, leftClickLocations ) ->
            case effect of
                Common.EffectOnWindow.MouseMoveTo mouseMoveTo ->
                    ( Just mouseMoveTo, leftClickLocations )

                Common.EffectOnWindow.KeyDown keyDown ->
                    case maybeLastMouseMoveLocation of
                        Nothing ->
                            ( maybeLastMouseMoveLocation, leftClickLocations )

                        Just lastMouseMoveLocation ->
                            if keyDown == Common.EffectOnWindow.virtualKeyCodeFromMouseButton mouseButton then
                                ( maybeLastMouseMoveLocation, leftClickLocations ++ [ lastMouseMoveLocation ] )

                            else
                                ( maybeLastMouseMoveLocation, leftClickLocations )

                _ ->
                    ( maybeLastMouseMoveLocation, leftClickLocations )
        )
        ( Nothing, [] )
        >> Tuple.second


{-| Finds the closest point on the edge of an orthogonal rectangle.
<https://math.stackexchange.com/questions/356792/how-to-find-nearest-point-on-line-of-rectangle-from-anywhere/356813#356813>
-}
closestPointOnRectangleEdge : EveOnline.ParseUserInterface.DisplayRegion -> Location2d -> Location2d
closestPointOnRectangleEdge rectangle point =
    let
        distToLeft =
            abs (point.x - rectangle.x)

        distToRight =
            abs ((rectangle.x + rectangle.width) - point.x)

        distToTop =
            abs (point.y - rectangle.y)

        distToBottom =
            abs ((rectangle.y + rectangle.height) - point.y)
    in
    if isPointInRectangle rectangle point then
        if min distToLeft distToRight < min distToTop distToBottom then
            if distToLeft < distToRight then
                { x = rectangle.x, y = point.y }

            else
                { x = rectangle.x + rectangle.width, y = point.y }

        else if distToTop < distToBottom then
            { x = point.x, y = rectangle.y }

        else
            { x = point.x, y = rectangle.y + rectangle.height }

    else
        closestPointInRectangle rectangle point


closestPointInRectangle : EveOnline.ParseUserInterface.DisplayRegion -> Location2d -> Location2d
closestPointInRectangle rectangle { x, y } =
    { x = x |> max rectangle.x |> min (rectangle.x + rectangle.width)
    , y = y |> max rectangle.y |> min (rectangle.y + rectangle.height)
    }


isPointInRectangle : EveOnline.ParseUserInterface.DisplayRegion -> Location2d -> Bool
isPointInRectangle rectangle { x, y } =
    (rectangle.x <= x)
        && (x <= rectangle.x + rectangle.width)
        && (rectangle.y <= y)
        && (y <= rectangle.y + rectangle.height)


cornersFromDisplayRegion : EveOnline.ParseUserInterface.DisplayRegion -> List Location2d
cornersFromDisplayRegion region =
    [ { x = region.x, y = region.y }
    , { x = region.x + region.width, y = region.y }
    , { x = region.x, y = region.y + region.height }
    , { x = region.x + region.width, y = region.y + region.height }
    ]


growRegionOnAllSides : Int -> EveOnline.ParseUserInterface.DisplayRegion -> EveOnline.ParseUserInterface.DisplayRegion
growRegionOnAllSides growthAmount region =
    { x = region.x - growthAmount
    , y = region.y - growthAmount
    , width = region.width + growthAmount * 2
    , height = region.height + growthAmount * 2
    }


regionAddMarginOnEachSide : Int -> DisplayRegion -> DisplayRegion
regionAddMarginOnEachSide marginSize originalRect =
    { x = originalRect.x - marginSize
    , y = originalRect.y - marginSize
    , width = originalRect.width + marginSize * 2
    , height = originalRect.height + marginSize * 2
    }


asReadingFromGameClientMemory : EveOnline.ParseUserInterface.ParsedUserInterface -> ReadingFromGameClientMemory
asReadingFromGameClientMemory reading =
    { contextMenus = reading.contextMenus |> List.map asContextMenuMemory }


asModuleButtonTooltipMemory : EveOnline.ParseUserInterface.ModuleButtonTooltip -> ModuleButtonTooltipMemory
asModuleButtonTooltipMemory tooltip =
    { uiNodeDisplayRegion = tooltip.uiNode.totalDisplayRegion
    , shortcut = tooltip.shortcut
    , optimalRange = tooltip.optimalRange
    , allContainedDisplayTextsWithRegion =
        tooltip.uiNode
            |> getAllContainedDisplayTextsWithRegion
            |> List.map (Tuple.mapSecond .totalDisplayRegion)
    }


asContextMenuMemory : EveOnline.ParseUserInterface.ContextMenu -> ContextMenu
asContextMenuMemory contextMenu =
    { uiNode = contextMenu.uiNode |> asUITreeNodeWithDisplayRegionMemory
    , entries = contextMenu.entries |> List.map asContextMenuEntryMemory
    }


asContextMenuEntryMemory : EveOnline.ParseUserInterface.ContextMenuEntry -> ContextMenuEntry
asContextMenuEntryMemory contextMenuEntry =
    { uiNode = contextMenuEntry.uiNode |> asUITreeNodeWithDisplayRegionMemory
    , text = contextMenuEntry.text
    }


asUITreeNodeWithDisplayRegionMemory : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion -> UITreeNodeWithDisplayRegion
asUITreeNodeWithDisplayRegionMemory node =
    { uiNode = { pythonObjectAddress = node.uiNode.pythonObjectAddress }
    , totalDisplayRegion = node.totalDisplayRegion
    }


distanceSquaredBetweenLocations : Location2d -> Location2d -> Int
distanceSquaredBetweenLocations a b =
    let
        distanceX =
            a.x - b.x

        distanceY =
            a.y - b.y
    in
    distanceX * distanceX + distanceY * distanceY

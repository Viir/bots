{-
   This framework helps with bot development by taking care of these common tasks:

   + Keeping track of the window the bot should work in so that the bot reads from and sends input to the right window.
   + Set up the volatile host to interface with Windows.
   + Map typical tasks like sending inputs or taking screenshots to the Windows API.

   To use this framework:

   + Wrap you bots `processEvent` function with `BotEngine.SimpleBotFramework.processEvent`.
   + Wrap you bots `initState` function with `BotEngine.SimpleBotFramework.initState`.
-}


module BotEngine.SimpleBotFramework exposing (..)

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import BotEngine.VolatileHostWindowsApi as VolatileHostWindowsApi
import Dict
import Json.Decode


type alias BotEvent =
    { timeInMilliseconds : Int
    , eventAtTime : BotEventAtTime
    }


type BotEventAtTime
    = TimeArrivedEvent
    | AppSettingsChangedEvent String
    | SessionDurationPlannedEvent { timeInMilliseconds : Int }
    | TaskCompletedEvent CompletedTaskStructure


type BotResponse
    = ContinueSession BotResponseContinueSession
    | FinishSession BotResponseFinishSession


type alias CompletedTaskStructure =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = NoResultValue
    | TakeScreenshotResult ImageStructure


type alias ImageStructure =
    { imageWidth : Int
    , imageHeight : Int
    , imageAsDict : Dict.Dict ( Int, Int ) PixelValue
    , imageBinned2x2AsDict : Dict.Dict ( Int, Int ) PixelValue
    }


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


type alias BotResponseContinueSession =
    { statusDescriptionText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias BotResponseFinishSession =
    { statusDescriptionText : String
    }


type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type TaskId
    = TaskIdFromString String


type alias Location2d =
    { x : Int, y : Int }


type MouseButton
    = MouseButtonLeft
    | MouseButtonRight


type KeyboardKey
    = KeyboardKeyFromVirtualKeyCode Int


type Task
    = BringWindowToForeground
    | MoveMouseToLocation Location2d
    | MouseButtonDown MouseButton
    | MouseButtonUp MouseButton
    | KeyboardKeyDown KeyboardKey
    | KeyboardKeyUp KeyboardKey
    | TakeScreenshot


type alias State simpleBotState =
    { timeInMilliseconds : Int
    , createVolatileHostResult : Maybe (Result InterfaceToHost.CreateVolatileHostErrorStructure InterfaceToHost.CreateVolatileHostComplete)
    , windowId : Maybe VolatileHostWindowsApi.WindowId
    , lastWindowTitleMeasurement : Maybe { timeInMilliseconds : Int, windowTitle : String }
    , waitingForTaskId : Maybe InterfaceToHost.TaskId
    , error : Maybe String
    , settingsString : Maybe String
    , simpleBotInitState : simpleBotState
    , simpleBot : Maybe simpleBotState
    , simpleBotLastResponse : Maybe BotResponse
    , simpleBotTasksInProgress : List ( InterfaceToHost.TaskId, StartTaskStructure )
    }


type FrameworkSetupStepActivity
    = StopWithResult { resultDescription : String }
    | ContinueSetupWithTask { task : InterfaceToHost.StartTaskStructure, taskDescription : String }
    | OperateSimpleBot { buildTaskFromTaskOnWindow : VolatileHostWindowsApi.TaskOnWindowStructure -> InterfaceToHost.Task }


type LocatePatternInImageApproach
    = TestPerPixelWithBroadPhase2x2
        { testOnBinned2x2 : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
        , testOnOriginalResolution : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
        }


type ImageSearchRegion
    = SearchEverywhere


initState : simpleBotState -> State simpleBotState
initState simpleBotInitState =
    { timeInMilliseconds = 0
    , createVolatileHostResult = Nothing
    , windowId = Nothing
    , lastWindowTitleMeasurement = Nothing
    , waitingForTaskId = Nothing
    , error = Nothing
    , settingsString = Nothing
    , simpleBotInitState = simpleBotInitState
    , simpleBot = Nothing
    , simpleBotLastResponse = Nothing
    , simpleBotTasksInProgress = []
    }


processEvent :
    (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse ))
    -> InterfaceToHost.AppEvent
    -> State simpleBotState
    -> ( State simpleBotState, InterfaceToHost.AppResponse )
processEvent simpleBotProcessEvent event stateBefore =
    let
        state =
            stateBefore |> integrateEvent event

        generalStatusDescription =
            (state |> statusDescriptionFromState) ++ "\n"
    in
    case stateBefore.error of
        Just error ->
            ( state, InterfaceToHost.FinishSession { statusDescriptionText = generalStatusDescription ++ "Error: " ++ error } )

        Nothing ->
            case state |> getNextSetupStepWithDescriptionFromState of
                StopWithResult { resultDescription } ->
                    ( state
                    , InterfaceToHost.FinishSession
                        { statusDescriptionText = generalStatusDescription ++ "Stopped with result: " ++ resultDescription
                        }
                    )

                ContinueSetupWithTask continue ->
                    ( state
                    , InterfaceToHost.ContinueSession
                        { startTasks = [ continue.task ]
                        , statusDescriptionText = generalStatusDescription ++ "I continue to set up the framework: Current step: " ++ continue.taskDescription
                        , notifyWhenArrivedAtTime = Nothing
                        }
                    )

                OperateSimpleBot { buildTaskFromTaskOnWindow } ->
                    let
                        ( simpleBotStateBefore, simpleBotEventsBefore ) =
                            case state.simpleBot of
                                Nothing ->
                                    let
                                        configurationEvents =
                                            case state.settingsString of
                                                Nothing ->
                                                    []

                                                Just settingsString ->
                                                    [ AppSettingsChangedEvent settingsString ]
                                    in
                                    ( stateBefore.simpleBotInitState
                                    , configurationEvents
                                        ++ [ TimeArrivedEvent ]
                                    )

                                Just simpleBot ->
                                    ( simpleBot, [] )

                        simpleBotLastResponseNotifyWhenArrivedAtTime =
                            case state.simpleBotLastResponse of
                                Nothing ->
                                    Nothing

                                Just (ContinueSession simpleBotLastResponseContinue) ->
                                    simpleBotLastResponseContinue.notifyWhenArrivedAtTime

                                Just (FinishSession _) ->
                                    Nothing

                        arriveAtTimeEvents =
                            case simpleBotLastResponseNotifyWhenArrivedAtTime of
                                Nothing ->
                                    []

                                Just notifyWhenArrivedAtTime ->
                                    if notifyWhenArrivedAtTime.timeInMilliseconds <= state.timeInMilliseconds then
                                        [ TimeArrivedEvent ]

                                    else
                                        []

                        mapCurrentEventToSimpleBotEventsResult =
                            case event.eventAtTime of
                                InterfaceToHost.TimeArrivedEvent ->
                                    Ok ( [], state.simpleBotTasksInProgress )

                                InterfaceToHost.AppSettingsChangedEvent settingsString ->
                                    Ok ( [ AppSettingsChangedEvent settingsString ], state.simpleBotTasksInProgress )

                                InterfaceToHost.SessionDurationPlannedEvent sessionDurationPlannedEvent ->
                                    Ok ( [ SessionDurationPlannedEvent sessionDurationPlannedEvent ], state.simpleBotTasksInProgress )

                                InterfaceToHost.TaskCompletedEvent completedTask ->
                                    case state.simpleBotTasksInProgress |> List.filter (\( key, _ ) -> key == completedTask.taskId) |> List.head of
                                        Nothing ->
                                            Ok ( [], state.simpleBotTasksInProgress )

                                        Just ( completedTaskInterfaceId, simpleBotTask ) ->
                                            let
                                                taskResultResult =
                                                    case completedTask.taskResult of
                                                        InterfaceToHost.CreateVolatileHostResponse _ ->
                                                            Err "CreateVolatileHostResponse"

                                                        InterfaceToHost.CompleteWithoutResult ->
                                                            Err "CompleteWithoutResult"

                                                        InterfaceToHost.RequestToVolatileHostResponse requestToVolatileHostResponse ->
                                                            case requestToVolatileHostResponse of
                                                                Err InterfaceToHost.HostNotFound ->
                                                                    Err "Error running script in volatile host: HostNotFound"

                                                                Ok volatileHostResponseSuccess ->
                                                                    case volatileHostResponseSuccess.exceptionToString of
                                                                        Just exceptionInVolatileHost ->
                                                                            Err ("Exception in volatile host: " ++ exceptionInVolatileHost)

                                                                        Nothing ->
                                                                            case volatileHostResponseSuccess.returnValueToString |> Maybe.withDefault "" |> VolatileHostWindowsApi.deserializeResponseFromVolatileHost of
                                                                                Err error ->
                                                                                    Err ("Failed to parse response from volatile host: " ++ (error |> Json.Decode.errorToString))

                                                                                Ok parsedResponse ->
                                                                                    case simpleBotTask.task of
                                                                                        BringWindowToForeground ->
                                                                                            Ok NoResultValue

                                                                                        MoveMouseToLocation _ ->
                                                                                            Ok NoResultValue

                                                                                        MouseButtonDown _ ->
                                                                                            Ok NoResultValue

                                                                                        MouseButtonUp _ ->
                                                                                            Ok NoResultValue

                                                                                        KeyboardKeyDown _ ->
                                                                                            Ok NoResultValue

                                                                                        KeyboardKeyUp _ ->
                                                                                            Ok NoResultValue

                                                                                        TakeScreenshot ->
                                                                                            case parsedResponse of
                                                                                                VolatileHostWindowsApi.TakeScreenshotResult takeScreenshotResult ->
                                                                                                    Ok
                                                                                                        (TakeScreenshotResult (deriveImageRepresentation takeScreenshotResult.pixels))

                                                                                                _ ->
                                                                                                    Err ("Unexpected return value from volatile host: " ++ (volatileHostResponseSuccess.returnValueToString |> Maybe.withDefault ""))
                                            in
                                            case taskResultResult of
                                                Err error ->
                                                    Err ("Unexpected task result: " ++ error)

                                                Ok taskResultOk ->
                                                    Ok
                                                        ( [ TaskCompletedEvent
                                                                { taskId = simpleBotTask.taskId, taskResult = taskResultOk }
                                                          ]
                                                        , state.simpleBotTasksInProgress
                                                            |> List.filter (Tuple.first >> (/=) completedTaskInterfaceId)
                                                        )

                        ( stateAfterPropagatingEventToSimpleBot, response ) =
                            case mapCurrentEventToSimpleBotEventsResult of
                                Err error ->
                                    ( { state | error = Just error }
                                    , InterfaceToHost.FinishSession { statusDescriptionText = generalStatusDescription ++ "Error: " ++ error }
                                    )

                                Ok ( simpleBotEventsFromCurrentEvent, simpleBotTasksInProgressAfterRemoval ) ->
                                    let
                                        botEvents =
                                            (simpleBotEventsBefore ++ arriveAtTimeEvents ++ simpleBotEventsFromCurrentEvent)
                                                |> List.map
                                                    (\eventAtTime ->
                                                        { timeInMilliseconds = state.timeInMilliseconds
                                                        , eventAtTime = eventAtTime
                                                        }
                                                    )

                                        ( simpleBotState, simpleBotResponse ) =
                                            simpleBotStateBefore
                                                |> processSequenceOfSimpleBotEventsAndCombineResponses
                                                    simpleBotProcessEvent
                                                    botEvents

                                        simpleBotLastResponse =
                                            [ simpleBotResponse, state.simpleBotLastResponse ]
                                                |> List.filterMap identity
                                                |> List.head

                                        ( responseFromSimpleBotLastResponse, simpleBotTasksInProgress ) =
                                            case simpleBotLastResponse of
                                                Nothing ->
                                                    ( InterfaceToHost.ContinueSession
                                                        { statusDescriptionText = generalStatusDescription ++ "Operate bot:\nNo response from bot so far."
                                                        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = state.timeInMilliseconds + 1000 }
                                                        , startTasks = []
                                                        }
                                                    , simpleBotTasksInProgressAfterRemoval
                                                    )

                                                Just (ContinueSession continueSession) ->
                                                    let
                                                        startTasks =
                                                            continueSession.startTasks
                                                                |> List.map
                                                                    (\simpleBotTaskWithId ->
                                                                        ( { taskId = simpleBotTaskWithId.taskId |> taskIdFromSimpleBotTaskId
                                                                          , task = simpleBotTaskWithId.task |> taskOnWindowFromSimpleBotTask |> buildTaskFromTaskOnWindow
                                                                          }
                                                                        , simpleBotTaskWithId
                                                                        )
                                                                    )

                                                        addedSimpleBotTasksInProgress =
                                                            startTasks
                                                                |> List.map
                                                                    (\( interfaceStartTask, simpleBotStartTask ) ->
                                                                        ( interfaceStartTask.taskId, simpleBotStartTask )
                                                                    )
                                                    in
                                                    ( InterfaceToHost.ContinueSession
                                                        { statusDescriptionText = generalStatusDescription ++ "Operate bot:\n" ++ continueSession.statusDescriptionText
                                                        , notifyWhenArrivedAtTime = continueSession.notifyWhenArrivedAtTime
                                                        , startTasks = startTasks |> List.map Tuple.first
                                                        }
                                                    , simpleBotTasksInProgressAfterRemoval ++ addedSimpleBotTasksInProgress
                                                    )

                                                Just (FinishSession finishSession) ->
                                                    ( InterfaceToHost.FinishSession
                                                        { statusDescriptionText = generalStatusDescription ++ "Finish session: " ++ finishSession.statusDescriptionText
                                                        }
                                                    , simpleBotTasksInProgressAfterRemoval
                                                    )
                                    in
                                    ( { state
                                        | simpleBot = Just simpleBotState
                                        , simpleBotLastResponse = simpleBotLastResponse
                                        , simpleBotTasksInProgress = simpleBotTasksInProgress
                                      }
                                    , responseFromSimpleBotLastResponse
                                    )
                    in
                    ( stateAfterPropagatingEventToSimpleBot, response )


deriveImageRepresentation : List (List PixelValue) -> ImageStructure
deriveImageRepresentation imageAsNestedList =
    let
        imageWidths =
            imageAsNestedList |> List.map List.length

        imageWidth =
            imageWidths |> List.maximum |> Maybe.withDefault 0

        imageHeight =
            imageWidths |> List.length

        imageAsDict =
            imageAsNestedList |> dictWithTupleKeyFromIndicesInNestedList

        imageBinned2x2AsDict =
            List.range 0 (((imageAsNestedList |> List.length) - 1) // 2)
                |> List.map
                    (\binnedRowIndex ->
                        let
                            rowWidth =
                                imageAsNestedList
                                    |> List.drop (binnedRowIndex * 2)
                                    |> List.take 2
                                    |> List.map List.length
                                    |> List.maximum
                                    |> Maybe.withDefault 0

                            rowBinnedWidth =
                                (rowWidth - 1) // 2 + 1
                        in
                        List.range 0 (rowBinnedWidth - 1)
                            |> List.map
                                (\binnedColumnIndex ->
                                    let
                                        sourcePixelsValues =
                                            [ ( 0, 0 ), ( 1, 0 ), ( 0, 1 ), ( 1, 1 ) ]
                                                |> List.filterMap (\( relX, relY ) -> imageAsDict |> Dict.get ( binnedColumnIndex * 2 + relX, binnedRowIndex * 2 + relY ))

                                        pixelValueSum =
                                            sourcePixelsValues
                                                |> List.foldl (\pixel sum -> { red = sum.red + pixel.red, green = sum.green + pixel.green, blue = sum.blue + pixel.blue }) { red = 0, green = 0, blue = 0 }

                                        sourcePixelsValuesCount =
                                            sourcePixelsValues |> List.length

                                        pixelValue =
                                            { red = pixelValueSum.red // sourcePixelsValuesCount
                                            , green = pixelValueSum.green // sourcePixelsValuesCount
                                            , blue = pixelValueSum.blue // sourcePixelsValuesCount
                                            }
                                    in
                                    pixelValue
                                )
                    )
                |> dictWithTupleKeyFromIndicesInNestedList
    in
    { imageWidth = imageWidth
    , imageHeight = imageHeight
    , imageAsDict = imageAsDict
    , imageBinned2x2AsDict = imageBinned2x2AsDict
    }


locatePatternInImage : LocatePatternInImageApproach -> ImageSearchRegion -> ImageStructure -> List Location2d
locatePatternInImage searchPattern searchRegion image =
    case searchPattern of
        TestPerPixelWithBroadPhase2x2 { testOnBinned2x2, testOnOriginalResolution } ->
            let
                binnedSearchLocations =
                    case searchRegion of
                        SearchEverywhere ->
                            image.imageBinned2x2AsDict |> Dict.keys |> List.map (\( x, y ) -> { x = x, y = y })

                matchLocationsOnBinned2x2 =
                    image.imageBinned2x2AsDict
                        |> getMatchesLocationsFromImage testOnBinned2x2 binnedSearchLocations

                originalResolutionSearchLocations =
                    matchLocationsOnBinned2x2
                        |> List.concatMap
                            (\binnedLocation ->
                                [ { x = binnedLocation.x * 2, y = binnedLocation.y * 2 }
                                , { x = binnedLocation.x * 2 + 1, y = binnedLocation.y * 2 }
                                , { x = binnedLocation.x * 2, y = binnedLocation.y * 2 + 1 }
                                , { x = binnedLocation.x * 2 + 1, y = binnedLocation.y * 2 + 1 }
                                ]
                            )

                matchLocations =
                    image.imageAsDict
                        |> getMatchesLocationsFromImage testOnOriginalResolution originalResolutionSearchLocations
            in
            matchLocations


getMatchesLocationsFromImage :
    (({ x : Int, y : Int } -> Maybe PixelValue) -> Bool)
    -> List { x : Int, y : Int }
    -> Dict.Dict ( Int, Int ) PixelValue
    -> List { x : Int, y : Int }
getMatchesLocationsFromImage imageMatchesPatternAtOrigin locationsToSearchAt image =
    locationsToSearchAt
        |> List.filter
            (\searchOrigin ->
                imageMatchesPatternAtOrigin
                    (\relativeLocation -> image |> Dict.get ( relativeLocation.x + searchOrigin.x, relativeLocation.y + searchOrigin.y ))
            )


processSequenceOfSimpleBotEventsAndCombineResponses : (BotEvent -> simpleBotState -> ( simpleBotState, BotResponse )) -> List BotEvent -> simpleBotState -> ( simpleBotState, Maybe BotResponse )
processSequenceOfSimpleBotEventsAndCombineResponses simpleBotProcessEvent events botStateBefore =
    case events of
        [] ->
            ( botStateBefore, Nothing )

        nextEvent :: followingEvents ->
            let
                ( nextBotState, nextBotResponse ) =
                    botStateBefore |> simpleBotProcessEvent nextEvent
            in
            case nextBotResponse of
                FinishSession _ ->
                    ( nextBotState, Just nextBotResponse )

                ContinueSession nextBotResponseContinue ->
                    let
                        ( followingBotState, followingBotResponse ) =
                            nextBotState
                                |> processSequenceOfSimpleBotEventsAndCombineResponses simpleBotProcessEvent followingEvents

                        combinedResponse =
                            case followingBotResponse of
                                Nothing ->
                                    nextBotResponse

                                Just (ContinueSession followingContinueSession) ->
                                    let
                                        startTasks =
                                            nextBotResponseContinue.startTasks ++ followingContinueSession.startTasks
                                    in
                                    ContinueSession
                                        { startTasks = startTasks
                                        , notifyWhenArrivedAtTime = followingContinueSession.notifyWhenArrivedAtTime
                                        , statusDescriptionText = followingContinueSession.statusDescriptionText
                                        }

                                Just (FinishSession finishSession) ->
                                    FinishSession finishSession
                    in
                    ( followingBotState, Just combinedResponse )


taskIdFromSimpleBotTaskId : TaskId -> InterfaceToHost.TaskId
taskIdFromSimpleBotTaskId simpleBotTaskId =
    case simpleBotTaskId of
        TaskIdFromString asString ->
            InterfaceToHost.taskIdFromString ("simple-bot-" ++ asString)


taskOnWindowFromSimpleBotTask : Task -> VolatileHostWindowsApi.TaskOnWindowStructure
taskOnWindowFromSimpleBotTask simpleBotTask =
    case simpleBotTask of
        BringWindowToForeground ->
            VolatileHostWindowsApi.BringWindowToForeground

        MoveMouseToLocation location ->
            VolatileHostWindowsApi.MoveMouseToLocation location

        MouseButtonDown button ->
            VolatileHostWindowsApi.MouseButtonDown
                (volatileHostMouseButtonFromMouseButton button)

        MouseButtonUp button ->
            VolatileHostWindowsApi.MouseButtonUp
                (volatileHostMouseButtonFromMouseButton button)

        KeyboardKeyDown key ->
            VolatileHostWindowsApi.KeyboardKeyDown
                (volatileHostKeyboardKeyFromKeyboardKey key)

        KeyboardKeyUp key ->
            VolatileHostWindowsApi.KeyboardKeyUp
                (volatileHostKeyboardKeyFromKeyboardKey key)

        TakeScreenshot ->
            VolatileHostWindowsApi.TakeScreenshot


integrateEvent : InterfaceToHost.AppEvent -> State simpleBotState -> State simpleBotState
integrateEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    case event.eventAtTime of
        InterfaceToHost.TimeArrivedEvent ->
            stateBefore

        InterfaceToHost.AppSettingsChangedEvent settingsString ->
            { stateBefore | settingsString = Just settingsString }

        InterfaceToHost.TaskCompletedEvent { taskId, taskResult } ->
            case taskResult of
                InterfaceToHost.CreateVolatileHostResponse createVolatileHostResult ->
                    { stateBefore | createVolatileHostResult = Just createVolatileHostResult }

                InterfaceToHost.RequestToVolatileHostResponse requestToVolatileHostResponse ->
                    case requestToVolatileHostResponse of
                        Err InterfaceToHost.HostNotFound ->
                            { stateBefore | error = Just "Error running script in volatile host: HostNotFound" }

                        Ok runInVolatileHostComplete ->
                            case runInVolatileHostComplete.returnValueToString of
                                Nothing ->
                                    { stateBefore | error = Just ("Error in volatile host: " ++ (runInVolatileHostComplete.exceptionToString |> Maybe.withDefault "")) }

                                Just returnValueToString ->
                                    case stateBefore.createVolatileHostResult of
                                        Nothing ->
                                            { stateBefore | error = Just ("Unexpected response from volatile host: " ++ returnValueToString) }

                                        Just (Err createVolatileHostError) ->
                                            { stateBefore | error = Just ("Failed to create volatile host: " ++ createVolatileHostError.exceptionToString) }

                                        Just (Ok createVolatileHostCompleted) ->
                                            case returnValueToString |> VolatileHostWindowsApi.deserializeResponseFromVolatileHost of
                                                Err error ->
                                                    { stateBefore | error = Just ("Failed to parse response from volatile host: " ++ (error |> Json.Decode.errorToString)) }

                                                Ok responseFromVolatileHost ->
                                                    case stateBefore.windowId of
                                                        Nothing ->
                                                            case responseFromVolatileHost of
                                                                VolatileHostWindowsApi.GetForegroundWindowResult windowId ->
                                                                    { stateBefore | windowId = Just windowId }

                                                                _ ->
                                                                    { stateBefore | error = Just ("Unexpected response from volatile host: " ++ returnValueToString) }

                                                        Just windowId ->
                                                            case responseFromVolatileHost of
                                                                VolatileHostWindowsApi.GetWindowTextResult windowText ->
                                                                    { stateBefore
                                                                        | lastWindowTitleMeasurement = Just { timeInMilliseconds = stateBefore.timeInMilliseconds, windowTitle = windowText }
                                                                    }

                                                                _ ->
                                                                    stateBefore

                InterfaceToHost.CompleteWithoutResult ->
                    stateBefore

        InterfaceToHost.SessionDurationPlannedEvent _ ->
            stateBefore


statusDescriptionFromState : State simpleBotState -> String
statusDescriptionFromState state =
    let
        portionWindow =
            case state.lastWindowTitleMeasurement of
                Nothing ->
                    ""

                Just { windowTitle } ->
                    "I work in the window with title '" ++ windowTitle ++ "'."
    in
    portionWindow


getNextSetupStepWithDescriptionFromState : State simpleBotState -> FrameworkSetupStepActivity
getNextSetupStepWithDescriptionFromState state =
    case state.createVolatileHostResult of
        Nothing ->
            { task =
                { taskId = InterfaceToHost.taskIdFromString "create_volatile_host"
                , task = InterfaceToHost.CreateVolatileHost { script = VolatileHostWindowsApi.setupScript }
                }
            , taskDescription = "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."
            }
                |> ContinueSetupWithTask

        Just (Err createVolatileHostError) ->
            StopWithResult { resultDescription = "Failed to create volatile host: " ++ createVolatileHostError.exceptionToString }

        Just (Ok createVolatileHostCompleted) ->
            case state.windowId of
                Nothing ->
                    let
                        task =
                            InterfaceToHost.RequestToVolatileHost
                                { hostId = createVolatileHostCompleted.hostId
                                , request =
                                    VolatileHostWindowsApi.GetForegroundWindow
                                        |> VolatileHostWindowsApi.buildRequestStringToGetResponseFromVolatileHost
                                }
                    in
                    { task = { taskId = InterfaceToHost.taskIdFromString "get_foreground_window", task = task }
                    , taskDescription = "Get foreground window"
                    }
                        |> ContinueSetupWithTask

                Just windowId ->
                    case state.lastWindowTitleMeasurement of
                        Nothing ->
                            let
                                task =
                                    InterfaceToHost.RequestToVolatileHost
                                        { hostId = createVolatileHostCompleted.hostId
                                        , request =
                                            windowId
                                                |> VolatileHostWindowsApi.GetWindowText
                                                |> VolatileHostWindowsApi.buildRequestStringToGetResponseFromVolatileHost
                                        }
                            in
                            { task = { taskId = InterfaceToHost.taskIdFromString "get_window_title", task = task }
                            , taskDescription = "Get window title"
                            }
                                |> ContinueSetupWithTask

                        Just { windowTitle } ->
                            OperateSimpleBot
                                { buildTaskFromTaskOnWindow =
                                    \taskOnWindow ->
                                        InterfaceToHost.RequestToVolatileHost
                                            { hostId = createVolatileHostCompleted.hostId
                                            , request =
                                                { windowId = windowId, task = taskOnWindow }
                                                    |> VolatileHostWindowsApi.TaskOnWindow
                                                    |> VolatileHostWindowsApi.buildRequestStringToGetResponseFromVolatileHost
                                            }
                                }


taskIdFromString : String -> TaskId
taskIdFromString =
    TaskIdFromString


volatileHostMouseButtonFromMouseButton : MouseButton -> VolatileHostWindowsApi.MouseButton
volatileHostMouseButtonFromMouseButton mouseButton =
    case mouseButton of
        MouseButtonLeft ->
            VolatileHostWindowsApi.MouseButtonLeft

        MouseButtonRight ->
            VolatileHostWindowsApi.MouseButtonRight


volatileHostKeyboardKeyFromKeyboardKey : KeyboardKey -> VolatileHostWindowsApi.KeyboardKey
volatileHostKeyboardKeyFromKeyboardKey keyboardKey =
    case keyboardKey of
        KeyboardKeyFromVirtualKeyCode keyCode ->
            VolatileHostWindowsApi.KeyboardKeyFromVirtualKeyCode keyCode


dictWithTupleKeyFromIndicesInNestedList : List (List element) -> Dict.Dict ( Int, Int ) element
dictWithTupleKeyFromIndicesInNestedList nestedList =
    nestedList
        |> List.indexedMap
            (\rowIndex list ->
                list
                    |> List.indexedMap
                        (\columnIndex element ->
                            ( ( columnIndex, rowIndex ), element )
                        )
            )
        |> List.concat
        |> Dict.fromList


bringWindowToForeground : Task
bringWindowToForeground =
    BringWindowToForeground


moveMouseToLocation : Location2d -> Task
moveMouseToLocation =
    MoveMouseToLocation


mouseButtonDown : MouseButton -> Task
mouseButtonDown =
    MouseButtonDown


mouseButtonUp : MouseButton -> Task
mouseButtonUp =
    MouseButtonUp


keyboardKeyDown : KeyboardKey -> Task
keyboardKeyDown =
    KeyboardKeyDown


keyboardKeyUp : KeyboardKey -> Task
keyboardKeyUp =
    KeyboardKeyUp


takeScreenshot : Task
takeScreenshot =
    TakeScreenshot


mouseButtonLeft : MouseButton
mouseButtonLeft =
    MouseButtonLeft


mouseButtonRight : MouseButton
mouseButtonRight =
    MouseButtonRight


{-| For documentation of virtual key codes, see <https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes>
-}
keyboardKeyFromVirtualKeyCode : Int -> KeyboardKey
keyboardKeyFromVirtualKeyCode =
    KeyboardKeyFromVirtualKeyCode


keyboardKey_space : KeyboardKey
keyboardKey_space =
    keyboardKeyFromVirtualKeyCode 0x20

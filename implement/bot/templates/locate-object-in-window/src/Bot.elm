{- This template demonstrates how to locate an object in a game client or another application window.

   You can test this by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can change its location within the window easily.

   bot-catalog-tags:template,test,locate-object-in-window
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import Interface_To_Host_20190808 as InterfaceToHost
import Maybe.Extra
import SimpleBotFramework exposing (PixelValue)


type alias SimpleState =
    { timeInMilliseconds : Int
    , lastTakeScreenshotResult :
        Maybe
            { timeInMilliseconds : Int
            , screenshot : SimpleBotFramework.ImageStructure
            , objectFoundLocations : List { x : Int, y : Int }
            }
    , waitingForTaskToComplete : Maybe SimpleBotFramework.TaskId
    , nextTaskIndex : Int
    }


type alias State =
    SimpleBotFramework.State SimpleState


initState : State
initState =
    SimpleBotFramework.initState
        { timeInMilliseconds = 0
        , waitingForTaskToComplete = Nothing
        , lastTakeScreenshotResult = Nothing
        , nextTaskIndex = 0
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleBotFramework.processEvent simpleProcessEvent


simpleProcessEvent : SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent event stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateEvent event

        lastScreenshotDescription =
            case stateBefore.lastTakeScreenshotResult of
                Nothing ->
                    "I did not take a screenshot so far."

                Just lastTakeScreenshotResult ->
                    let
                        objectFoundLocationsToDescribe =
                            lastTakeScreenshotResult.objectFoundLocations
                                |> List.take 10

                        objectFoundLocationsDescription =
                            "I found the object in "
                                ++ (lastTakeScreenshotResult.objectFoundLocations |> List.length |> String.fromInt)
                                ++ " locations:\n[ "
                                ++ (objectFoundLocationsToDescribe |> List.map describeLocation |> String.join ", ")
                                ++ " ]"
                    in
                    "The last screenshot had a width of "
                        ++ (lastTakeScreenshotResult.screenshot.imageWidth |> String.fromInt)
                        ++ " and a height of "
                        ++ (lastTakeScreenshotResult.screenshot.imageHeight |> String.fromInt)
                        ++ " pixels.\n"
                        ++ objectFoundLocationsDescription
    in
    -- Do not start a new task before the engine has completed the last task.
    if stateBefore.waitingForTaskToComplete /= Nothing then
        ( stateBefore
        , SimpleBotFramework.ContinueSession
            { statusDescriptionText = lastScreenshotDescription ++ "\nWaiting for task to complete."
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 100 }
            , startTasks = []
            }
        )

    else
        let
            taskId =
                SimpleBotFramework.taskIdFromString ("take-screenshot-" ++ (stateBefore.nextTaskIndex |> String.fromInt))
        in
        ( { stateBefore | nextTaskIndex = stateBefore.nextTaskIndex + 1, waitingForTaskToComplete = Just taskId }
        , SimpleBotFramework.ContinueSession
            { startTasks = [ { taskId = taskId, task = SimpleBotFramework.TakeScreenshot } ]
            , statusDescriptionText = lastScreenshotDescription
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 300 }
            }
        )


integrateEvent : SimpleBotFramework.BotEvent -> SimpleState -> SimpleState
integrateEvent event stateBefore =
    case event of
        SimpleBotFramework.ArrivedAtTime arrivedAtTime ->
            { stateBefore | timeInMilliseconds = arrivedAtTime.timeInMilliseconds }

        SimpleBotFramework.SetBotConfiguration _ ->
            stateBefore

        SimpleBotFramework.SetSessionTimeLimit _ ->
            stateBefore

        SimpleBotFramework.CompletedTask completedTask ->
            if stateBefore.waitingForTaskToComplete == Just completedTask.taskId then
                let
                    lastTakeScreenshotResult =
                        case completedTask.taskResult of
                            SimpleBotFramework.NoResultValue ->
                                stateBefore.lastTakeScreenshotResult

                            SimpleBotFramework.TakeScreenshotResult takeScreenshotResult ->
                                let
                                    objectFoundLocations =
                                        takeScreenshotResult
                                            |> SimpleBotFramework.locatePatternInImage
                                                locate_EVE_Online_Undock_Button
                                                SimpleBotFramework.SearchEverywhere
                                in
                                Just
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds
                                    , screenshot = takeScreenshotResult
                                    , objectFoundLocations = objectFoundLocations
                                    }
                in
                { stateBefore
                    | waitingForTaskToComplete = Nothing
                    , lastTakeScreenshotResult = lastTakeScreenshotResult
                }

            else
                stateBefore


{-| This is from the game EVE Online, the undock button in the station window. For an example image, see the training data linked below:
<https://github.com/Viir/bots/blob/0a283d8476c49418a5ef449d5a30d98383933d8c/implement/bot/eve-online/training-data/2019-08-06.eve-online-station-window-undock-and-other-buttons.png>
-}
locate_EVE_Online_Undock_Button : SimpleBotFramework.LocatePatternInImageApproach
locate_EVE_Online_Undock_Button =
    let
        testOnOriginalResolution getPixelValueAtLocation =
            let
                -- Check four pixels located in the four corners of the button.
                cornerLocationsToCheck =
                    [ { x = -80, y = -20 }
                    , { x = 79, y = -20 }
                    , { x = 79, y = 19 }
                    , { x = -80, y = 19 }
                    ]

                pixelColorMatchesButtonCornerColor : PixelValue -> Bool
                pixelColorMatchesButtonCornerColor pixelValue =
                    (((pixelValue.red - 187) |> abs) < 20)
                        && (((pixelValue.green - 138) |> abs) < 20)
                        && (pixelValue.blue < 20)
            in
            case cornerLocationsToCheck |> List.map getPixelValueAtLocation |> Maybe.Extra.combine of
                Nothing ->
                    False

                Just pixelValuesCorners ->
                    pixelValuesCorners |> List.all pixelColorMatchesButtonCornerColor

        -- Only check the greyish yellow color of one pixel in the upper left quadrant.
        testOnBinned2x2 : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
        testOnBinned2x2 getPixelValueAtLocation =
            getPixelValueAtLocation { x = -30, y = -5 }
                |> Maybe.map
                    (\pixelValue -> (pixelValue.red - 77 |> abs) < 10 && (pixelValue.green - 57 |> abs) < 10 && pixelValue.blue < 10)
                |> Maybe.withDefault False
    in
    SimpleBotFramework.TestPerPixelWithBroadPhase2x2
        { testOnOriginalResolution = testOnOriginalResolution
        , testOnBinned2x2 = testOnBinned2x2
        }


describeLocation : { x : Int, y : Int } -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"

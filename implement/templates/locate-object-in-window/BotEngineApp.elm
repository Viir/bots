{- This template demonstrates how to locate an object in a game client or another application window.

   You can test this by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can change its location within the window easily.
-}
{-
   app-catalog-tags:template,locate-object-in-window,test
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import BotEngine.SimpleBotFramework as SimpleBotFramework exposing (PixelValue)
import Maybe.Extra


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


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    SimpleBotFramework.processEvent simpleProcessEvent


simpleProcessEvent : SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent event stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateEvent event
    in
    -- Do not start a new task before the engine has completed the last task.
    if stateBefore.waitingForTaskToComplete /= Nothing then
        ( stateBefore
        , SimpleBotFramework.ContinueSession
            { statusDescriptionText = lastScreenshotDescription stateBefore ++ "\nWaiting for task to complete."
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 100 }
            , startTasks = []
            }
        )

    else
        let
            taskToStart =
                { taskId = SimpleBotFramework.taskIdFromString ("take-screenshot-" ++ (stateBefore.nextTaskIndex |> String.fromInt))
                , task = SimpleBotFramework.takeScreenshot
                }
        in
        ( { stateBefore | nextTaskIndex = stateBefore.nextTaskIndex + 1, waitingForTaskToComplete = Just taskToStart.taskId }
        , SimpleBotFramework.ContinueSession
            { startTasks = [ taskToStart ]
            , statusDescriptionText = lastScreenshotDescription stateBefore
            , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 300 }
            }
        )


integrateEvent : SimpleBotFramework.BotEvent -> SimpleState -> SimpleState
integrateEvent event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }
    in
    case event.eventAtTime of
        SimpleBotFramework.TimeArrivedEvent ->
            stateBefore

        SimpleBotFramework.AppSettingsChangedEvent _ ->
            stateBefore

        SimpleBotFramework.SessionDurationPlannedEvent _ ->
            stateBefore

        SimpleBotFramework.TaskCompletedEvent completedTask ->
            if stateBefore.waitingForTaskToComplete == Just completedTask.taskId then
                let
                    lastTakeScreenshotResult =
                        case completedTask.taskResult of
                            SimpleBotFramework.NoResultValue ->
                                stateBefore.lastTakeScreenshotResult

                            SimpleBotFramework.TakeScreenshotResult screenshot ->
                                let
                                    objectFoundLocations =
                                        SimpleBotFramework.locatePatternInImage
                                            locate_EVE_Online_Undock_Button
                                            SimpleBotFramework.SearchEverywhere
                                            screenshot
                                in
                                Just
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds
                                    , screenshot = screenshot
                                    , objectFoundLocations = objectFoundLocations
                                    }
                in
                { stateBefore
                    | waitingForTaskToComplete = Nothing
                    , lastTakeScreenshotResult = lastTakeScreenshotResult
                }

            else
                stateBefore


lastScreenshotDescription : SimpleState -> String
lastScreenshotDescription stateBefore =
    case stateBefore.lastTakeScreenshotResult of
        Nothing ->
            "Taking the first screenshot..."

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


{-| This is from the game EVE Online, the undock button in the station window.
This pattern is based on the following training images:
<https://github.com/Viir/bots/blob/f8331eb236137026e415fe535c7f48958974d0f4/implement/applications/eve-online/training-data/2019-08-06.eve-online-station-window-undock-and-other-buttons.png>
<https://github.com/Viir/bots/blob/f8331eb236137026e415fe535c7f48958974d0f4/implement/applications/eve-online/training-data/2019-08-06.eve-online-station-window-undock-button-mouse-over.png>

Beyond considering the original training images, this pattern applies additional tolerance to account for pixel value changes which can result from lossy compression (e.g. tinypng, JPEG).

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
                    (((pixelValue.red - 187) |> abs) < 30)
                        && (((pixelValue.green - 138) |> abs) < 30)
                        && (pixelValue.blue < 30)
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
                    (\pixelValue ->
                        (pixelValue.red - 106 |> abs) < 40 && (pixelValue.green - 78 |> abs) < 30 && pixelValue.blue < 20
                    )
                |> Maybe.withDefault False
    in
    SimpleBotFramework.TestPerPixelWithBroadPhase2x2
        { testOnOriginalResolution = testOnOriginalResolution
        , testOnBinned2x2 = testOnBinned2x2
        }


describeLocation : { x : Int, y : Int } -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"

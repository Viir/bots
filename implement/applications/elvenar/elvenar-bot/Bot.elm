{- Elvenar Bot v2022-03-13

   This bot locates coins in the Elvenar game client window.

   The bot picks the topmost window in the display order, the one in the front. This selection happens once when starting the bot. The bot then remembers the window address and continues working on the same window.
   To use this bot, bring the target window to the foreground after pressing the button to run the bot. When the bot displays the window title in the status text, you know it has completed the selection.

   You can test this bot by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can change its location within the window easily.
-}
{-
   catalog-tags:elvenar
   authors-forum-usernames:viir
-}


module Bot exposing
    ( ImagePattern
    , State
    , botMain
    , coinPattern
    , describeLocation
    , filterRemoveCloseLocations
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework
import DecodeBMPImage
import Dict


type alias ImagePattern =
    Dict.Dict ( Int, Int ) DecodeBMPImage.PixelValue -> ( Int, Int ) -> Bool


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


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = SimpleBotFramework.initState initState
    , processEvent = SimpleBotFramework.processEvent simpleProcessEvent
    }


initState : SimpleState
initState =
    { timeInMilliseconds = 0
    , waitingForTaskToComplete = Nothing
    , lastTakeScreenshotResult = Nothing
    , nextTaskIndex = 0
    }


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

        SimpleBotFramework.BotSettingsChangedEvent _ ->
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
                                            coinPattern
                                            SimpleBotFramework.SearchEverywhere
                                            screenshot
                                            |> filterRemoveCloseLocations 3
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


coinPattern : SimpleBotFramework.LocatePatternInImageApproach
coinPattern =
    SimpleBotFramework.TestPerPixelWithBroadPhase2x2
        { testOnBinned2x2 =
            \getPixelColor ->
                case getPixelColor { x = 0, y = 0 } of
                    Nothing ->
                        False

                    Just centerColor ->
                        (centerColor.red > 240)
                            && (centerColor.green < 230 && centerColor.green > 190)
                            && (centerColor.blue < 150 && centerColor.blue > 80)
        , testOnOriginalResolution =
            \getPixelColor ->
                case getPixelColor { x = 0, y = 0 } of
                    Nothing ->
                        False

                    Just centerColor ->
                        if
                            not
                                ((centerColor.red > 240)
                                    && (centerColor.green < 240 && centerColor.green > 210)
                                    && (centerColor.blue < 200 && centerColor.blue > 120)
                                )
                        then
                            False

                        else
                            case ( getPixelColor { x = 9, y = 0 }, getPixelColor { x = 2, y = -8 } ) of
                                ( Just rightColor, Just upperColor ) ->
                                    (rightColor.red > 70 && rightColor.red < 120)
                                        && (rightColor.green > 30 && rightColor.green < 80)
                                        && (rightColor.blue > 5 && rightColor.blue < 50)
                                        && (upperColor.red > 100 && upperColor.red < 180)
                                        && (upperColor.green > 70 && upperColor.green < 180)
                                        && (upperColor.blue > 60 && upperColor.blue < 100)

                                _ ->
                                    False
        }


filterRemoveCloseLocations : Int -> List { x : Int, y : Int } -> List { x : Int, y : Int }
filterRemoveCloseLocations distanceMin locations =
    let
        locationsTooClose l0 l1 =
            ((l0.x - l1.x) * (l0.x - l1.x) + (l0.y - l1.y) * (l0.y - l1.y)) < distanceMin * distanceMin
    in
    locations
        |> List.foldl
            (\nextLocation aggregate ->
                if List.any (locationsTooClose nextLocation) aggregate then
                    aggregate

                else
                    nextLocation :: aggregate
            )
            []


describeLocation : { x : Int, y : Int } -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"

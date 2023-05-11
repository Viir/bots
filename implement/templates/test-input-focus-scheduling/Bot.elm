{- Test scheduling 2023-05-11

   This bot helps testing the input focus scheduling functionality.
-}
{-
   catalog-tags:elvenar
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    , coinPattern
    , describeLocation
    , filterRemoveCloseLocations
    )

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework
import Common.AppSettings as AppSettings
import Common.EffectOnWindow


readFromWindowIntervalMilliseconds : Int
readFromWindowIntervalMilliseconds =
    4000


type alias BotState =
    { timeInMilliseconds : Int
    , lastReadingsFromWindow : List ReadFromWindowResult
    }


type alias ReadFromWindowResult =
    { timeInMilliseconds : Int
    , readResult : SimpleBotFramework.ReadFromWindowResultStruct
    , coinFoundLocations : List Location2d
    }


type alias State =
    SimpleBotFramework.State BotSettings BotState


type alias BotSettings =
    {}


botMain : InterfaceToHost.BotConfig State
botMain =
    SimpleBotFramework.composeSimpleBotMain
        { parseBotSettings = AppSettings.parseAllowOnlyEmpty {}
        , init = initState
        , processEvent = processEvent
        }


initState : BotState
initState =
    { timeInMilliseconds = 0
    , lastReadingsFromWindow = []
    }


processEvent :
    BotSettings
    -> SimpleBotFramework.BotEvent
    -> BotState
    -> ( BotState, SimpleBotFramework.BotResponse )
processEvent _ event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }

        activityContinueWaiting =
            ( [], "Wait before starting next reading..." )

        continueWaitingOrRead stateToContinueWaitingOrRead =
            let
                timeToTakeNewReadingFromGameWindow =
                    case stateToContinueWaitingOrRead.lastReadingsFromWindow of
                        [] ->
                            True

                        lastReadFromWindowResult :: _ ->
                            readFromWindowIntervalMilliseconds
                                < (stateToContinueWaitingOrRead.timeInMilliseconds - lastReadFromWindowResult.timeInMilliseconds)

                activityContinueWaitingOrRead =
                    if timeToTakeNewReadingFromGameWindow then
                        ( [ { taskId = SimpleBotFramework.taskIdFromString "read-from-window"
                            , task = SimpleBotFramework.readFromWindow
                            }
                          ]
                        , "Get the next reading from the game"
                        )

                    else
                        activityContinueWaiting
            in
            ( stateToContinueWaitingOrRead, activityContinueWaitingOrRead )

        ( state, ( startTasks, activityDescription ) ) =
            case event.eventAtTime of
                SimpleBotFramework.TimeArrivedEvent ->
                    continueWaitingOrRead stateBefore

                SimpleBotFramework.SessionDurationPlannedEvent _ ->
                    continueWaitingOrRead stateBefore

                SimpleBotFramework.TaskCompletedEvent completedTask ->
                    case completedTask.taskResult of
                        SimpleBotFramework.NoResultValue ->
                            continueWaitingOrRead stateBefore

                        SimpleBotFramework.ReadFromWindowResult readFromWindowResult image ->
                            let
                                lastReadFromWindowResult =
                                    computeReadFromWindowResult readFromWindowResult image stateBefore

                                activityFromReadResult =
                                    let
                                        mouseDownLocation =
                                            { x = readFromWindowResult.windowClientAreaSize.x // 2
                                            , y = readFromWindowResult.windowClientAreaSize.y // 2
                                            }
                                    in
                                    ( [ { taskId =
                                            SimpleBotFramework.taskIdFromString "collect-coin-input-sequence"
                                        , task =
                                            Common.EffectOnWindow.effectsForMouseDragAndDrop
                                                { startPosition = mouseDownLocation
                                                , mouseButton = Common.EffectOnWindow.LeftMouseButton
                                                , waypointsPositionsInBetween =
                                                    [ mouseDownLocation |> addOffset { x = 15, y = 30 } ]
                                                , endPosition = mouseDownLocation
                                                }
                                                |> SimpleBotFramework.effectSequenceTask
                                                    { delayBetweenEffectsMilliseconds = 100 }
                                        }
                                      ]
                                    , "Drag and drop around window center"
                                    )
                            in
                            ( { stateBefore
                                | lastReadingsFromWindow =
                                    lastReadFromWindowResult :: List.take 3 stateBefore.lastReadingsFromWindow
                              }
                            , activityFromReadResult
                            )

        notifyWhenArrivedAtTime =
            { timeInMilliseconds = state.timeInMilliseconds + 1000 }

        statusText =
            [ activityDescription
            , lastReadingDescription state
            ]
                |> String.join "\n"
    in
    ( state
    , SimpleBotFramework.ContinueSession
        { startTasks = startTasks
        , statusText = statusText
        , notifyWhenArrivedAtTime = Just notifyWhenArrivedAtTime
        }
    )


computeReadFromWindowResult :
    SimpleBotFramework.ReadFromWindowResultStruct
    -> SimpleBotFramework.ReadingFromGameClientScreenshot
    -> BotState
    -> ReadFromWindowResult
computeReadFromWindowResult readFromWindowResult image stateBefore =
    let
        coinFoundLocations =
            SimpleBotFramework.locatePatternInImage
                coinPattern
                SimpleBotFramework.SearchEverywhere
                image
                |> filterRemoveCloseLocations 4
    in
    { timeInMilliseconds = stateBefore.timeInMilliseconds
    , readResult = readFromWindowResult
    , coinFoundLocations = coinFoundLocations
    }


lastReadingDescription : BotState -> String
lastReadingDescription stateBefore =
    case stateBefore.lastReadingsFromWindow of
        [] ->
            "Taking the first reading from the window..."

        lastReadFromWindowResult :: _ ->
            let
                coinFoundLocationsToDescribe =
                    lastReadFromWindowResult.coinFoundLocations
                        |> List.take 10

                coinFoundLocationsDescription =
                    "I found the coin in "
                        ++ (lastReadFromWindowResult.coinFoundLocations |> List.length |> String.fromInt)
                        ++ " locations:\n[ "
                        ++ (coinFoundLocationsToDescribe |> List.map describeLocation |> String.join ", ")
                        ++ " ]"

                windowProperties =
                    [ ( "window.width", String.fromInt lastReadFromWindowResult.readResult.windowSize.x )
                    , ( "window.height", String.fromInt lastReadFromWindowResult.readResult.windowSize.y )
                    , ( "windowClientArea.width", String.fromInt lastReadFromWindowResult.readResult.windowClientAreaSize.x )
                    , ( "windowClientArea.height", String.fromInt lastReadFromWindowResult.readResult.windowClientAreaSize.y )
                    ]
                        |> List.map (\( property, value ) -> property ++ " = " ++ value)
                        |> String.join ", "
            in
            [ "Last reading from window: " ++ windowProperties
            , coinFoundLocationsDescription
            ]
                |> String.join "\n"


coinPattern : SimpleBotFramework.LocatePatternInImageApproach
coinPattern =
    SimpleBotFramework.TestPerPixelWithBroadPhase4x4
        { testOnBinned4x4 =
            \getPixelColor ->
                case getPixelColor { x = 0, y = 0 } of
                    Nothing ->
                        False

                    Just centerColor ->
                        (160 < centerColor.red)
                            && (centerColor.green < centerColor.red)
                            && (centerColor.blue < centerColor.red // 2)
        , testOnBinned2x2 =
            \getPixelColor ->
                coinTestOnBinned2x2_100 getPixelColor
                    || coinTestOnBinned2x2_125 getPixelColor
        , testOnOriginalResolution = always True
        }


coinTestOnBinned2x2_125 : ({ x : Int, y : Int } -> Maybe SimpleBotFramework.PixelValueRGB) -> Bool
coinTestOnBinned2x2_125 =
    \getPixelColor ->
        case
            ( getPixelColor { x = 0, y = 0 }
            , ( getPixelColor { x = -2, y = 0 }, getPixelColor { x = 0, y = -3 } )
            , getPixelColor { x = 3, y = 0 }
            )
        of
            ( Just centerColor, ( Just leftColor, Just topColor ), Just rightColor ) ->
                (centerColor.red > 220)
                    && (centerColor.green > 190 && centerColor.green < 235)
                    && (centerColor.blue > 90 && centerColor.blue < 150)
                    && (leftColor.red > 155 && leftColor.red < 200)
                    && (leftColor.green > 90 && leftColor.green < 190)
                    && (leftColor.blue > 20 && leftColor.blue < 100)
                    && (topColor.red > 140 && topColor.red < 200)
                    && (topColor.green > 90 && topColor.red < 170)
                    && (topColor.blue > 10 && topColor.blue < 70)
                    && (rightColor.red > 150 && rightColor.red < 220)
                    && (rightColor.green > 90 && rightColor.green < 160)
                    && (rightColor.blue > 10 && rightColor.blue < 70)

            _ ->
                False


coinTestOnBinned2x2_100 : ({ x : Int, y : Int } -> Maybe SimpleBotFramework.PixelValueRGB) -> Bool
coinTestOnBinned2x2_100 =
    \getPixelColor ->
        case
            ( getPixelColor { x = 0, y = 0 }
            , ( getPixelColor { x = -2, y = 0 }, getPixelColor { x = 0, y = -2 } )
            , getPixelColor { x = 2, y = 0 }
            )
        of
            ( Just centerColor, ( Just leftColor, Just topColor ), Just rightColor ) ->
                (centerColor.red > 240)
                    && (centerColor.green > 190 && centerColor.green < 235)
                    && (centerColor.blue > 90 && centerColor.blue < 150)
                    && (leftColor.red > 150 && leftColor.red < 220)
                    && (leftColor.green > 90 && leftColor.green < 190)
                    && (leftColor.blue > 20 && leftColor.blue < 100)
                    && (topColor.red > 140 && topColor.red < 200)
                    && (topColor.green > 90 && topColor.red < 170)
                    && (topColor.blue > 10 && topColor.blue < 80)
                    && (rightColor.red > 150 && rightColor.red < 240)
                    && (rightColor.green > 90 && rightColor.green < 200)
                    && (rightColor.blue > 10 && rightColor.blue < 100)

            _ ->
                False


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


describeLocation : Location2d -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"


type alias Location2d =
    SimpleBotFramework.Location2d


addOffset : Location2d -> Location2d -> Location2d
addOffset a b =
    { x = a.x + b.x, y = a.y + b.y }

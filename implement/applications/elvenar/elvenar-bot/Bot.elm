{- Elvenar Bot version 2023-02-10

   This bot collects coins in the Elvenar game client window.

   The bot picks the topmost window in the display order, the one in the front. This selection happens once when starting the bot. The bot then remembers the window address and continues working on the same window.
   To use this bot, bring the Elvenar game client window to the foreground after pressing the button to run the bot. When the bot displays the window title in the status text, it has completed the selection of the game window.

   You can test this bot by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can change its location within the window easily.

   You can see the training data samples used to develop this bot at <https://github.com/Viir/bots/tree/8b955f4035a9a202ba8450f12f4c38be8a2b8d7e/implement/applications/elvenar/training-data>
   If the bot does not recognize all coins with your setup, post it on GitHub issues at <https://github.com/Viir/bots/issues> or on the forum at <https://forum.botlab.org>
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
import Random
import Random.List


mouseClickLocationOffsetFromCoin : Location2d
mouseClickLocationOffsetFromCoin =
    { x = 0, y = 50 }


readFromWindowIntervalMilliseconds : Int
readFromWindowIntervalMilliseconds =
    4000


type alias SimpleState =
    { timeInMilliseconds : Int
    , lastReadFromWindowResult : Maybe ReadFromWindowResult
    }


type alias ReadFromWindowResult =
    { timeInMilliseconds : Int
    , readResult : SimpleBotFramework.ReadFromWindowResultStruct
    , coinFoundLocations : List Location2d
    }


type alias State =
    SimpleBotFramework.State BotSettings SimpleState


type alias BotSettings =
    {}


type alias PixelValue =
    SimpleBotFramework.PixelValueRGB


botMain : InterfaceToHost.BotConfig State
botMain =
    SimpleBotFramework.composeSimpleBotMain
        { parseBotSettings = AppSettings.parseAllowOnlyEmpty {}
        , init = initState
        , processEvent = simpleProcessEvent
        }


initState : SimpleState
initState =
    { timeInMilliseconds = 0
    , lastReadFromWindowResult = Nothing
    }


simpleProcessEvent : BotSettings -> SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent _ event stateBeforeUpdateTime =
    let
        stateBefore =
            { stateBeforeUpdateTime | timeInMilliseconds = event.timeInMilliseconds }

        activityContinueWaiting =
            ( [], "Wait before starting next reading..." )

        continueWaitingOrRead stateToContinueWaitingOrRead =
            let
                timeToTakeNewReadingFromGameWindow =
                    case stateToContinueWaitingOrRead.lastReadFromWindowResult of
                        Nothing ->
                            True

                        Just lastReadFromWindowResult ->
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

                                reachableCoinLocations =
                                    lastReadFromWindowResult.coinFoundLocations
                                        |> List.filter
                                            (\location ->
                                                location.y
                                                    < readFromWindowResult.windowClientRectOffset.y
                                                    + readFromWindowResult.windowClientAreaSize.y
                                                    - mouseClickLocationOffsetFromCoin.y
                                                    - 20
                                            )

                                activityFromReadResult =
                                    case
                                        Random.initialSeed stateBefore.timeInMilliseconds
                                            |> Random.step (Random.List.shuffle reachableCoinLocations)
                                            |> Tuple.first
                                    of
                                        [] ->
                                            activityContinueWaiting
                                                |> Tuple.mapSecond ((++) "Did not find any coin with reachable interactive area to click on. ")

                                        coinFoundLocation :: _ ->
                                            let
                                                mouseDownLocation =
                                                    coinFoundLocation
                                                        |> addOffset mouseClickLocationOffsetFromCoin
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
                                            , "Collect coin at " ++ describeLocation coinFoundLocation
                                            )
                            in
                            ( { stateBefore
                                | lastReadFromWindowResult = Just lastReadFromWindowResult
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
    -> SimpleState
    -> ReadFromWindowResult
computeReadFromWindowResult readFromWindowResult image stateBefore =
    let
        coinFoundLocations =
            SimpleBotFramework.locatePatternInImage
                coinPattern
                SimpleBotFramework.SearchEverywhere
                image
                |> filterRemoveCloseLocations 3
    in
    { timeInMilliseconds = stateBefore.timeInMilliseconds
    , readResult = readFromWindowResult
    , coinFoundLocations = coinFoundLocations
    }


lastReadingDescription : SimpleState -> String
lastReadingDescription stateBefore =
    case stateBefore.lastReadFromWindowResult of
        Nothing ->
            "Taking the first reading from the window..."

        Just lastReadFromWindowResult ->
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
    SimpleBotFramework.TestPerPixelWithBroadPhase2x2
        { testOnBinned2x2 = coinPatternTestOnBinned2x2
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


coinPatternTestOnBinned2x2 : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
coinPatternTestOnBinned2x2 getPixelColor =
    case getPixelColor { x = 0, y = 0 } of
        Nothing ->
            False

        Just centerColor ->
            (centerColor.red > 240)
                && (centerColor.green < 230 && centerColor.green > 190)
                && (centerColor.blue < 150 && centerColor.blue > 80)


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

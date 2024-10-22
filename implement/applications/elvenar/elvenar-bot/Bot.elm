{- Elvenar coin collecting bot version 2023-05-16

   This bot collects coins in the Elvenar game client window.
   It locates the coins over residential buildings in the Elvenar window and then clicks on them to collect them 🪙

   ## Setup and starting the bot

   Follow these steps to start a new bot session:

   + Load Elvenar in a web browser.
   + Ensure the product of the display 'scale' setting in Windows and the 'zoom' setting in the web browser is 125%. If the 'scale' in Windows settings is 100%, zoom the web browser tab to 125%. If the 'scale' in Windows settings is 125%, zoom the web browser tab to 100%.
   + Elvenar offers you five different zoom levels. Zoom to the middle level to ensure the bot will correctly recognize the icons in the game. (You can change zoom levels using the mouse wheel or via the looking glass icons in the settings menu)
   + Start the bot and immediately click on the web browser containing Elvenar.

   The bot picks the topmost window in the display order, the one in the front. This selection happens once when starting the bot. The bot then remembers the window address and continues working on the same window.
   To use this bot, bring the Elvenar game client window to the foreground after pressing the button to run the bot. When the bot displays the window title in the status text, it has completed the selection of the game window.

   You can test this bot by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can quickly change its location within the window.

   You can see the training data samples used to develop this bot at <https://github.com/Viir/bots/tree/71d857d01597a3dfa36c5724be79e85c44dfd3ae/implement/applications/elvenar/training-data>

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

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework
import Common.AppSettings as AppSettings
import Common.EffectOnWindow
import Random
import Random.List


mouseClickLocationOffsetFromCoin : Location2d
mouseClickLocationOffsetFromCoin =
    { x = 0, y = 65 }


readFromWindowIntervalMilliseconds : Int
readFromWindowIntervalMilliseconds =
    4000


{-| The maximum of how much we assume the statistics bar at the top of the game viewport to extend from the top of the screenshot.
We use this to separate the coin icon shown in the statistics bar from the coin icons that represent collectibles in the game world.
Since the overall screenshot region can also contain parts of the web browser UI outside the page viewport, this height can depend on the web browser used. I observed a value of 145 with Google Chrome on Windows.
Mid-term, we will make this more precise by having a more accurate screenshotting or detecting the actual extent of the statistics bar using image processing.
-}
topStatsBarBottomMaximum : Int
topStatsBarBottomMaximum =
    145


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

                                collectibleCoinLocations =
                                    lastReadFromWindowResult.coinFoundLocations
                                        |> List.filter
                                            (assumeCoinIconRepresentsCollectible
                                                stateBefore.lastReadingsFromWindow
                                                image.bounds
                                            )

                                reachableCoinLocations =
                                    collectibleCoinLocations
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
                                                |> Tuple.mapSecond ((++) "Found no collectible coin with a reachable interactive area to click on. ")

                                        coinFoundLocation :: _ ->
                                            let
                                                mouseDownLocation =
                                                    coinFoundLocation
                                                        |> addOffset mouseClickLocationOffsetFromCoin
                                            in
                                            ( [ { taskId =
                                                    SimpleBotFramework.taskIdFromString "collect-coin-input-sequence"
                                                , task =
                                                    SimpleBotFramework.EffectSequenceOnWindowTask
                                                        { waitBeforeEffectsMs = 300
                                                        , waitBetweenEffectsMs = 500
                                                        }
                                                        (Common.EffectOnWindow.effectsForMouseDragAndDrop
                                                            { startPosition = mouseDownLocation
                                                            , mouseButton = Common.EffectOnWindow.LeftMouseButton
                                                            , waypointsPositionsInBetween =
                                                                [ mouseDownLocation |> addOffset { x = 15, y = 30 } ]
                                                            , endPosition = mouseDownLocation
                                                            }
                                                        )
                                                }
                                              ]
                                            , "Collect coin at " ++ describeLocation coinFoundLocation
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


assumeCoinIconRepresentsCollectible :
    List ReadFromWindowResult
    -> InterfaceToHost.WinApiRectStruct
    -> Location2d
    -> Bool
assumeCoinIconRepresentsCollectible lastReadingsFromWindow gameClientViewport iconLocation =
    let
        coinLocationAgeGreaterThanOrEqual ageBound location =
            lastReadingsFromWindow
                |> List.take ageBound
                |> List.all (.coinFoundLocations >> List.any (distanceSquared location >> (>) 10))
    in
    if iconLocation.y < topStatsBarBottomMaximum then
        -- There is always a coin icon in the upper statistics bar
        False

    else if iconLocation.y < topStatsBarBottomMaximum + 110 && iconLocation.x > gameClientViewport.right - 140 then
        -- There is sometimes an advert in the upper right corner, which can have a yellowish texture.
        False

    else
        coinLocationAgeGreaterThanOrEqual 2 iconLocation


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


distanceSquared : Location2d -> Location2d -> Int
distanceSquared a b =
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


describeLocation : Location2d -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"


type alias Location2d =
    SimpleBotFramework.Location2d


addOffset : Location2d -> Location2d -> Location2d
addOffset a b =
    { x = a.x + b.x, y = a.y + b.y }

{- Elvenar Bot v2022-06-07

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


readFromWindowIntervalMilliseconds : Int
readFromWindowIntervalMilliseconds =
    1000


type alias SimpleState =
    { timeInMilliseconds : Int
    , lastReadFromWindowResult :
        Maybe
            { timeInMilliseconds : Int
            , readResult : SimpleBotFramework.ReadFromWindowResultStruct
            , image : SimpleBotFramework.ImageStructure
            , coinFoundLocations : List Location2d
            , missingOriginalPixelsCrops : List Rect
            }
    }


type alias State =
    SimpleBotFramework.State SimpleState


type alias PixelValue =
    SimpleBotFramework.PixelValue


type alias ImagePattern =
    Dict.Dict ( Int, Int ) DecodeBMPImage.PixelValue -> ( Int, Int ) -> Bool


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = SimpleBotFramework.initState initState
    , processEvent = SimpleBotFramework.processEvent simpleProcessEvent
    }


initState : SimpleState
initState =
    { timeInMilliseconds = 0
    , lastReadFromWindowResult = Nothing
    }


simpleProcessEvent : SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent event stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateEvent event
    in
    let
        timeToTakeNewReadingFromGameWindow =
            case stateBefore.lastReadFromWindowResult of
                Nothing ->
                    True

                Just lastReadFromWindowResult ->
                    readFromWindowIntervalMilliseconds
                        < (stateBefore.timeInMilliseconds - lastReadFromWindowResult.timeInMilliseconds)

        startTasksIfDoneWithLastReading =
            if timeToTakeNewReadingFromGameWindow then
                [ { taskId = SimpleBotFramework.taskIdFromString "read-from-window"
                  , task =
                        SimpleBotFramework.readFromWindow
                            { crops_1x1_r8g8b8 = []
                            , crops_2x2_r8g8b8 = [ { x = 0, y = 0, width = 9999, height = 9999 } ]
                            }
                  }
                ]

            else
                []

        startTasks =
            case stateBefore.lastReadFromWindowResult of
                Just lastReadFromWindowResult ->
                    if
                        (lastReadFromWindowResult.missingOriginalPixelsCrops /= [])
                            && Dict.isEmpty lastReadFromWindowResult.image.imageAsDict
                    then
                        [ { taskId = SimpleBotFramework.taskIdFromString "get-image-data-from-reading"
                          , task =
                                SimpleBotFramework.getImageDataFromReading
                                    { crops_1x1_r8g8b8 = lastReadFromWindowResult.missingOriginalPixelsCrops
                                    , crops_2x2_r8g8b8 = []
                                    }
                          }
                        ]

                    else
                        startTasksIfDoneWithLastReading

                Nothing ->
                    startTasksIfDoneWithLastReading
    in
    ( stateBefore
    , SimpleBotFramework.ContinueSession
        { startTasks = startTasks
        , statusDescriptionText = lastReadingDescription stateBefore
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
            let
                lastReadFromWindowResult =
                    case completedTask.taskResult of
                        SimpleBotFramework.NoResultValue ->
                            stateBefore.lastReadFromWindowResult

                        SimpleBotFramework.ReadFromWindowResult readFromWindowResult image ->
                            let
                                coinFoundLocations =
                                    SimpleBotFramework.locatePatternInImage
                                        coinPattern
                                        SimpleBotFramework.SearchEverywhere
                                        image
                                        |> filterRemoveCloseLocations 3

                                binnedSearchLocations =
                                    image.imageBinned2x2AsDict
                                        |> Dict.keys
                                        |> List.map (\( x, y ) -> { x = x, y = y })

                                matchLocationsOnBinned2x2 =
                                    image.imageBinned2x2AsDict
                                        |> SimpleBotFramework.getMatchesLocationsFromImage
                                            coinPatternTestOnBinned2x2
                                            binnedSearchLocations

                                missingOriginalPixelsCrops =
                                    matchLocationsOnBinned2x2
                                        |> List.map (\binnedLocation -> ( binnedLocation.x * 2, binnedLocation.y * 2 ))
                                        |> List.filter (\location -> not (Dict.member location image.imageAsDict))
                                        |> List.map
                                            (\( x, y ) ->
                                                { x = x - 10
                                                , y = y - 10
                                                , width = 20
                                                , height = 20
                                                }
                                            )
                                        |> List.filter (\rect -> 0 < rect.width && 0 < rect.height)
                            in
                            Just
                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                , readResult = readFromWindowResult
                                , image = image
                                , coinFoundLocations = coinFoundLocations
                                , missingOriginalPixelsCrops = missingOriginalPixelsCrops
                                }
            in
            { stateBefore
                | lastReadFromWindowResult = lastReadFromWindowResult
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
                    [ ( "window.width", lastReadFromWindowResult.readResult.windowSize.x )
                    , ( "window.height", lastReadFromWindowResult.readResult.windowSize.y )
                    , ( "windowClientArea.width", lastReadFromWindowResult.readResult.windowClientAreaSize.x )
                    , ( "windowClientArea.height", lastReadFromWindowResult.readResult.windowClientAreaSize.y )
                    ]
                        |> List.map (\( property, value ) -> property ++ " = " ++ String.fromInt value)
                        |> String.join ", "
            in
            [ "Last reading from window: " ++ windowProperties
            , "Pixels: "
                ++ ([ ( "binned 2x2", lastReadFromWindowResult.image.imageBinned2x2AsDict |> Dict.size )
                    , ( "original", lastReadFromWindowResult.image.imageAsDict |> Dict.size )
                    ]
                        |> List.map (\( name, value ) -> String.fromInt value ++ " " ++ name)
                        |> String.join ", "
                   )
                ++ "."
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


type alias Rect =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }

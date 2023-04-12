{- This template demonstrates how to locate an object in a game client or another application window.

   You can test this by placing a screenshot in a paint app like MS Paint or Paint.NET, where you can change its location within the window easily.
-}
{-
   catalog-tags:template,locate-object-in-window,test
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework exposing (PixelValueRGB)
import Common.AppSettings as AppSettings
import Maybe.Extra


readFromWindowIntervalMilliseconds : Int
readFromWindowIntervalMilliseconds =
    1000


type alias SimpleState =
    { timeInMilliseconds : Int
    , lastReadFromWindowResult :
        Maybe
            { timeInMilliseconds : Int
            , readResult : SimpleBotFramework.ReadFromWindowResultStruct
            , objectFoundLocations : List { x : Int, y : Int }
            }
    }


type alias State =
    SimpleBotFramework.State BotSettings SimpleState


type alias BotSettings =
    {}


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
simpleProcessEvent _ event stateBeforeIntegratingEvent =
    let
        stateBefore =
            stateBeforeIntegratingEvent |> integrateEvent event

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
                  , task = SimpleBotFramework.readFromWindow
                  }
                ]

            else
                []
    in
    ( stateBefore
    , SimpleBotFramework.ContinueSession
        { startTasks = startTasksIfDoneWithLastReading
        , statusText = lastReadingDescription stateBefore
        , notifyWhenArrivedAtTime = Just { timeInMilliseconds = stateBefore.timeInMilliseconds + 500 }
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
                                objectFoundLocations =
                                    SimpleBotFramework.locatePatternInImage
                                        locate_EVE_Online_Undock_Button
                                        SimpleBotFramework.SearchEverywhere
                                        image
                            in
                            Just
                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                , readResult = readFromWindowResult
                                , objectFoundLocations = objectFoundLocations
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
                objectFoundLocationsToDescribe =
                    lastReadFromWindowResult.objectFoundLocations
                        |> List.take 10

                objectFoundLocationsDescription =
                    "I found the object in "
                        ++ (lastReadFromWindowResult.objectFoundLocations |> List.length |> String.fromInt)
                        ++ " locations:\n[ "
                        ++ (objectFoundLocationsToDescribe |> List.map describeLocation |> String.join ", ")
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
            , objectFoundLocationsDescription
            ]
                |> String.join "\n"


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

                pixelColorMatchesButtonCornerColor : PixelValueRGB -> Bool
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
        testOnBinned2x2 : ({ x : Int, y : Int } -> Maybe PixelValueRGB) -> Bool
        testOnBinned2x2 getPixelValueAtLocation =
            getPixelValueAtLocation { x = -30, y = -5 }
                |> Maybe.map
                    (\pixelValue ->
                        ((pixelValue.red - 106 |> abs) < 40)
                            && ((pixelValue.green - 78 |> abs) < 30)
                            && (pixelValue.blue < 20)
                    )
                |> Maybe.withDefault False
    in
    SimpleBotFramework.TestPerPixelWithBroadPhase4x4
        { testOnBinned4x4 = always True
        , testOnBinned2x2 = testOnBinned2x2
        , testOnOriginalResolution = testOnOriginalResolution
        }


describeLocation : { x : Int, y : Int } -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"

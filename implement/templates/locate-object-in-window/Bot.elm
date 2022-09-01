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

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import BotLab.SimpleBotFramework as SimpleBotFramework exposing (PixelValue)
import Dict
import Maybe.Extra


type alias Location2d =
    SimpleBotFramework.Location2d


type alias Rect =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


readFromWindowIntervalMilliseconds : Int
readFromWindowIntervalMilliseconds =
    1000


windowOriginalLocationsToInspectOffset : Location2d
windowOriginalLocationsToInspectOffset =
    { x = 100, y = 200 }


window2x2LocationsToInspectOffset : Location2d
window2x2LocationsToInspectOffset =
    { x = windowOriginalLocationsToInspectOffset.x // 2
    , y = windowOriginalLocationsToInspectOffset.y // 2
    }


windowOriginalLocationsToInspect : List Location2d
windowOriginalLocationsToInspect =
    [ { x = 0, y = 0 }
    , { x = 1, y = 0 }
    , { x = 0, y = 1 }
    , { x = 1, y = 1 }
    , { x = 10, y = 0 }
    , { x = 11, y = 0 }
    , { x = 10, y = 1 }
    , { x = 11, y = 1 }
    , { x = 0, y = 10 }
    , { x = 1, y = 10 }
    , { x = 0, y = 11 }
    , { x = 1, y = 11 }
    ]
        |> List.map (addOffset windowOriginalLocationsToInspectOffset)


window2x2LocationsToInspect : List Location2d
window2x2LocationsToInspect =
    [ { x = 0, y = 0 }
    , { x = 5, y = 0 }
    , { x = 0, y = 5 }
    ]
        |> List.map (addOffset window2x2LocationsToInspectOffset)


type alias SimpleState =
    { timeInMilliseconds : Int
    , lastReadFromWindowResult :
        Maybe
            { timeInMilliseconds : Int
            , readResult : SimpleBotFramework.ReadFromWindowResultStruct
            , image : SimpleBotFramework.ImageStructure
            , objectFoundLocations : List { x : Int, y : Int }
            , missingOriginalPixelsCrops : List Rect
            }
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
    , lastReadFromWindowResult = Nothing
    }


simpleProcessEvent : SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent event stateBeforeIntegratingEvent =
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
                                objectFoundLocations =
                                    SimpleBotFramework.locatePatternInImage
                                        locate_EVE_Online_Undock_Button
                                        SimpleBotFramework.SearchEverywhere
                                        image

                                binnedSearchLocations =
                                    image.imageBinned2x2AsDict
                                        |> Dict.keys
                                        |> List.map (\( x, y ) -> { x = x, y = y })

                                testOnBinned2x2 =
                                    case locate_EVE_Online_Undock_Button of
                                        SimpleBotFramework.TestPerPixelWithBroadPhase2x2 pattern ->
                                            pattern.testOnBinned2x2

                                matchLocationsOnBinned2x2 =
                                    image.imageBinned2x2AsDict
                                        |> SimpleBotFramework.getMatchesLocationsFromImage
                                            testOnBinned2x2
                                            binnedSearchLocations

                                missingOriginalPixelsCrops =
                                    (matchLocationsOnBinned2x2
                                        |> List.map (\binnedLocation -> ( binnedLocation.x * 2, binnedLocation.y * 2 ))
                                    )
                                        ++ List.map (\loc -> ( loc.x, loc.y )) windowOriginalLocationsToInspect
                                        |> List.filter (\location -> not (Dict.member location image.imageAsDict))
                                        |> List.map
                                            (\( x, y ) ->
                                                { x = x - 100
                                                , y = y - 50
                                                , width = 200
                                                , height = 100
                                                }
                                            )
                                        |> List.filter (\rect -> 0 < rect.width && 0 < rect.height)
                            in
                            Just
                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                , readResult = readFromWindowResult
                                , image = image
                                , objectFoundLocations = objectFoundLocations
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
                objectFoundLocationsToDescribe =
                    lastReadFromWindowResult.objectFoundLocations
                        |> List.take 10

                objectFoundLocationsDescription =
                    "I found the object in "
                        ++ (lastReadFromWindowResult.objectFoundLocations |> List.length |> String.fromInt)
                        ++ " locations:\n[ "
                        ++ (objectFoundLocationsToDescribe |> List.map describeLocation |> String.join ", ")
                        ++ " ]"

                pixelValues =
                    [ { reprName = "binned-2x2"
                      , locations = window2x2LocationsToInspect
                      , getter = .imageBinned2x2AsDict
                      }
                    , { reprName = "original"
                      , locations = windowOriginalLocationsToInspect
                      , getter = .imageAsDict
                      }
                    ]
                        |> List.map
                            (\reprConfig ->
                                "Inspecting on representation '"
                                    ++ reprConfig.reprName
                                    ++ "':\n"
                                    ++ (reprConfig.locations
                                            |> List.map
                                                (\location ->
                                                    String.fromInt location.x
                                                        ++ ","
                                                        ++ String.fromInt location.y
                                                        ++ ": "
                                                        ++ (lastReadFromWindowResult.image
                                                                |> reprConfig.getter
                                                                |> Dict.get ( location.x, location.y )
                                                                |> Maybe.map describePixelValue
                                                                |> Maybe.withDefault "NA"
                                                           )
                                                )
                                            |> String.join "\n"
                                       )
                            )
                        |> String.join "\n"

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
            , objectFoundLocationsDescription
            , "Inspecting individual pixel values:"
            , pixelValues
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
                        ((pixelValue.red - 106 |> abs) < 40)
                            && ((pixelValue.green - 78 |> abs) < 30)
                            && (pixelValue.blue < 20)
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


describePixelValue : PixelValue -> String
describePixelValue pixelValue =
    [ "{ "
    , [ ( "red", .red )
      , ( "green", .green )
      , ( "blue", .blue )
      ]
        |> List.map
            (\( name, getter ) ->
                name ++ " = " ++ (pixelValue |> getter |> String.fromInt)
            )
        |> String.join ", "
    , " }"
    ]
        |> String.join ""


addOffset : Location2d -> Location2d -> Location2d
addOffset a b =
    { x = a.x + b.x, y = a.y + b.y }

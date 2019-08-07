{- This is a template to test functions to locate objects in images.

   To use this template, use it like a bot and start it using the `start-bot` command.
   Specify the path to the file to load the image from using the `--bot-configuration` parameter.

   To test an image search function, replace the function `image_shows_object_at_origin` below with your search function.
   The framework calls this function for every pixel in the image specified with the `--bot-configuration`, and keeps a list of locations where `image_shows_object_at_origin` returned `True`.
   After running this search, it displays a list of these matching locations as the status message from the bot, so you see it in the console output.

   For an example of such an image search function, you can look at the example included below as `image_shows_object_at_origin`.
   When you use this example image search function with the example image from `2019-07-11.example-from-eve-online-crop-0.bmp`, the bot outputs following results:

    > Stopped with result: Decoded image: bitmapWidthInPixels: 153, bitmapHeightInPixels: 81
    > Found matches in 4 locations:
    > [ { x = 23, y = 57 }, { x = 33, y = 57 }, { x = 43, y = 57 }, { x = 53, y = 57 } ]

   bot-catalog-tags:devtool,test,locate-object-in-image
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import Dict
import Interface_To_Host_20190803 as InterfaceToHost
import Json.Decode
import Maybe.Extra
import VolatileHostSetup exposing (PixelValue)


type alias State =
    { imageFileName : Maybe String
    , lastStepResult : ProcessStepResult
    , error : Maybe String
    }


type ProcessStepResult
    = Initialized
    | VolatileHostCreated VolatileHostCreatedStructure
    | VolatileHostSetupCompleted VolatileHostCreatedStructure
    | GotImage GotImageStructure
    | GotImagePixels GotImagePixelsStructure


type alias VolatileHostCreatedStructure =
    { hostId : String }


type alias GotImageStructure =
    { volatileHost : VolatileHostCreatedStructure
    , volatileHostResponse : VolatileHostSetup.GetImageSuccessStructure
    }


type alias GotImagePixelsStructure =
    { previousStep : GotImageStructure
    , volatileHostResponse : VolatileHostSetup.GetPixels2DSuccessStructure
    , imageSearchResultLocations : List { x : Int, y : Int }
    }


type TestProcessStepActivity
    = StopWithResult { resultDescription : String }
    | ContinueWithTask { task : InterfaceToHost.StartTaskStructure, taskDescription : String }


image_shows_object_at_origin : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
image_shows_object_at_origin getPixelValueAtLocation =
    image_matches_EVE_Online_Info_Panel_Route_Marker getPixelValueAtLocation


getMatchesLocationsFromImage : Dict.Dict ( Int, Int ) PixelValue -> List { x : Int, y : Int }
getMatchesLocationsFromImage image =
    let
        locationsToSearchAt =
            image |> Dict.keys |> List.map (\( x, y ) -> { x = x, y = y })
    in
    locationsToSearchAt
        |> List.filter
            (\searchOrigin ->
                image_shows_object_at_origin
                    (\relativeLocation -> image |> Dict.get ( relativeLocation.x + searchOrigin.x, relativeLocation.y + searchOrigin.y ))
            )


{-| This is the square-shaped thing displayed in the route info panel in the game EVE Online. There seems to be one for each solar system on the route.
In the image <https://github.com/Viir/bots/blob/a755e00ae395d89cb586995fb7f4d07a21200a8a/explore/2019-07-10.read-from-screenshot/2019-07-11.example-from-eve-online-crop-0.bmp>, you can see 4 of these.
-}
image_matches_EVE_Online_Info_Panel_Route_Marker : ({ x : Int, y : Int } -> Maybe PixelValue) -> Bool
image_matches_EVE_Online_Info_Panel_Route_Marker getPixelValueAtLocation =
    let
        markerSideLength =
            8

        markerSideOffset =
            markerSideLength - 1

        pixelsLocations =
            List.range 0 markerSideOffset
                |> List.concatMap
                    (\offset ->
                        [ { x = offset, y = 0 }
                        , { x = 0, y = offset }
                        , { x = offset, y = markerSideOffset }
                        , { x = markerSideOffset, y = offset }
                        ]
                    )

        -- Evaluate map to HSV model before applying the checks.
        pixelIsSufficientlyBrightAndSaturated : PixelValue -> Bool
        pixelIsSufficientlyBrightAndSaturated pixelValue =
            (pixelValue.red > 160 || pixelValue.green > 160 || pixelValue.blue > 160)
                && ([ pixelValue.red - pixelValue.green, pixelValue.green - pixelValue.blue, pixelValue.blue - pixelValue.red ]
                        |> List.any (\colorChannelDifference -> (colorChannelDifference |> abs) > 40)
                   )
    in
    case pixelsLocations |> List.map getPixelValueAtLocation |> Maybe.Extra.combine of
        Nothing ->
            False

        Just pixelValuesToCompare ->
            if pixelValuesToCompare |> List.all pixelIsSufficientlyBrightAndSaturated |> not then
                False

            else
                let
                    reds =
                        pixelValuesToCompare |> List.map .red

                    greens =
                        pixelValuesToCompare |> List.map .green

                    blues =
                        pixelValuesToCompare |> List.map .blue

                    areSimilarEnough =
                        [ reds, greens, blues ]
                            |> List.all
                                (\colorChannelValues ->
                                    case ( colorChannelValues |> List.minimum, colorChannelValues |> List.maximum ) of
                                        ( Just minimum, Just maximum ) ->
                                            maximum - minimum < 50

                                        _ ->
                                            False
                                )
                in
                areSimilarEnough


initState : State
initState =
    { imageFileName = Nothing
    , lastStepResult = Initialized
    , error = Nothing
    }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent eventAtTime stateBefore =
    let
        state =
            stateBefore |> integrateEvent eventAtTime

        nextStep =
            case state.error of
                Just error ->
                    StopWithResult { resultDescription = "Error: " ++ error }

                Nothing ->
                    state |> getNextRequestWithDescriptionFromState

        generalStatusDescription =
            (state |> statusDescriptionFromState) ++ "\n"

        response =
            case nextStep of
                StopWithResult { resultDescription } ->
                    InterfaceToHost.FinishSession
                        { statusDescriptionForOperator = generalStatusDescription ++ "Stopped with result: " ++ resultDescription
                        }

                ContinueWithTask continue ->
                    InterfaceToHost.ContinueSession
                        { startTasks = [ continue.task ]
                        , statusDescriptionForOperator = generalStatusDescription ++ "Current step: " ++ continue.taskDescription
                        , notifyWhenArrivedAtTime = Nothing
                        }
    in
    ( state, response )


integrateEvent : InterfaceToHost.BotEvent -> State -> State
integrateEvent event stateBefore =
    case event of
        InterfaceToHost.ArrivedAtTime _ ->
            stateBefore

        InterfaceToHost.SetBotConfiguration configuration ->
            { stateBefore | imageFileName = Just configuration }

        InterfaceToHost.TaskComplete { taskResult } ->
            case taskResult of
                InterfaceToHost.CreateVolatileHostResponse createVolatileHostResponse ->
                    case createVolatileHostResponse of
                        Err _ ->
                            { stateBefore | error = Just "Failed to create volatile host." }

                        Ok { hostId } ->
                            { stateBefore | lastStepResult = VolatileHostCreated { hostId = hostId } }

                InterfaceToHost.RunInVolatileHostResponse runInVolatileHostResponse ->
                    case runInVolatileHostResponse of
                        Err InterfaceToHost.HostNotFound ->
                            { stateBefore | error = Just "Error running script in volatile host: HostNotFound" }

                        Ok runInVolatileHostComplete ->
                            case runInVolatileHostComplete.returnValueToString of
                                Nothing ->
                                    { stateBefore | error = Just ("Error in volatile host: " ++ (runInVolatileHostComplete.exceptionToString |> Maybe.withDefault "")) }

                                Just returnValueToString ->
                                    case stateBefore.lastStepResult of
                                        Initialized ->
                                            stateBefore

                                        VolatileHostCreated volatileHost ->
                                            if returnValueToString == "Setup Completed" then
                                                { stateBefore | lastStepResult = VolatileHostSetupCompleted volatileHost }

                                            else
                                                stateBefore

                                        VolatileHostSetupCompleted volatileHost ->
                                            case returnValueToString |> VolatileHostSetup.deserializeResponseFromVolatileHost of
                                                Err error ->
                                                    { stateBefore | error = Just ("Failed to parse response from volatile host: " ++ (error |> Json.Decode.errorToString)) }

                                                Ok responseFromVolatileHost ->
                                                    case responseFromVolatileHost of
                                                        VolatileHostSetup.GetImageResult VolatileHostSetup.DidNotFindFileAtSpecifiedPath ->
                                                            { stateBefore | error = Just "Getting the file failed: Did not find the file at the specified path." }

                                                        VolatileHostSetup.GetImageResult (VolatileHostSetup.ExceptionAsString exceptionAsString) ->
                                                            { stateBefore | error = Just ("Getting the file failed with exception: " ++ exceptionAsString) }

                                                        VolatileHostSetup.GetImageResult (VolatileHostSetup.GetImageSuccess getImageSuccess) ->
                                                            let
                                                                gotImage =
                                                                    { volatileHost = volatileHost
                                                                    , volatileHostResponse = getImageSuccess
                                                                    }
                                                            in
                                                            { stateBefore | lastStepResult = GotImage gotImage }

                                                        _ ->
                                                            { stateBefore | error = Just "Unexpected response from volatile host." }

                                        GotImage gotImage ->
                                            case returnValueToString |> VolatileHostSetup.deserializeResponseFromVolatileHost of
                                                Err error ->
                                                    { stateBefore | error = Just ("Failed to parse response from volatile host: " ++ (error |> Json.Decode.errorToString)) }

                                                Ok responseFromVolatileHost ->
                                                    case responseFromVolatileHost of
                                                        VolatileHostSetup.GetPixelsFromImageRectangleResult getPixelsFromImageRectangleResult ->
                                                            case getPixelsFromImageRectangleResult of
                                                                VolatileHostSetup.DidNotFindSpecifiedImage ->
                                                                    { stateBefore | error = Just "Getting image pixels failed: Did not find specified image." }

                                                                VolatileHostSetup.GetPixels2DSuccess getPixelsSuccess ->
                                                                    let
                                                                        pixelsDict =
                                                                            getPixelsSuccess.pixels
                                                                                |> dictWithTupleKeyFromNestedList

                                                                        gotImagePixels =
                                                                            { previousStep = gotImage
                                                                            , volatileHostResponse = getPixelsSuccess
                                                                            , imageSearchResultLocations = pixelsDict |> getMatchesLocationsFromImage
                                                                            }
                                                                    in
                                                                    { stateBefore | lastStepResult = GotImagePixels gotImagePixels }

                                                        _ ->
                                                            { stateBefore | error = Just ("Unexpected response from volatile host: " ++ returnValueToString) }

                                        GotImagePixels _ ->
                                            stateBefore

                InterfaceToHost.CompleteWithoutResult ->
                    stateBefore

        InterfaceToHost.SetSessionTimeLimit _ ->
            stateBefore


statusDescriptionFromState : State -> String
statusDescriptionFromState state =
    let
        portionConfiguration =
            case state.imageFileName |> Maybe.withDefault "" of
                "" ->
                    "I have not received a path to an image to load."

                imageFileName ->
                    "I received '" ++ imageFileName ++ "' as the path to the image to load."

        ( maybeGotImage, maybeGotImagePixels ) =
            case state.lastStepResult of
                GotImage gotImage ->
                    ( Just gotImage.volatileHostResponse, Nothing )

                GotImagePixels gotImagePixels ->
                    ( Just gotImagePixels.previousStep.volatileHostResponse, Just gotImagePixels.volatileHostResponse )

                _ ->
                    ( Nothing, Nothing )

        portionImage =
            case maybeGotImage of
                Nothing ->
                    ""

                Just gotImage ->
                    "I got the image with id '"
                        ++ gotImage.fileIdBase16
                        ++ "', a width of "
                        ++ (gotImage.widthInPixels |> String.fromInt)
                        ++ ", and a height of "
                        ++ (gotImage.heightInPixels |> String.fromInt)
                        ++ "."

        portionImagePixels =
            case maybeGotImagePixels of
                Nothing ->
                    ""

                Just gotImagePixels ->
                    "I got " ++ (gotImagePixels.pixels |> List.concat |> List.length |> String.fromInt) ++ " pixels"
    in
    [ portionConfiguration, portionImage, portionImagePixels ]
        |> String.join "\n"


getNextRequestWithDescriptionFromState : State -> TestProcessStepActivity
getNextRequestWithDescriptionFromState state =
    case state.lastStepResult of
        Initialized ->
            ContinueWithTask
                { task =
                    { taskId = "create_volatile_host"
                    , task = InterfaceToHost.CreateVolatileHost
                    }
                , taskDescription = "Create volatile host."
                }

        VolatileHostCreated volatileHost ->
            ContinueWithTask
                { task =
                    { taskId = "set_up_volatile_host"
                    , task =
                        InterfaceToHost.RunInVolatileHost
                            { hostId = volatileHost.hostId
                            , script = VolatileHostSetup.setupScript
                            }
                    }
                , taskDescription = "Set up the volatile host. This can take several seconds, especially when assemblies are not cached yet."
                }

        VolatileHostSetupCompleted volatileHost ->
            let
                imageFilePath =
                    state.imageFileName |> Maybe.withDefault ""
            in
            if (imageFilePath |> String.length) < 1 then
                StopWithResult
                    { resultDescription = "I have no file path to load the image from. Please specify a path to the image file using the bot configuration."
                    }

            else
                let
                    task =
                        InterfaceToHost.RunInVolatileHost
                            { hostId = volatileHost.hostId
                            , script = { filePath = imageFilePath } |> VolatileHostSetup.GetImage |> VolatileHostSetup.buildScriptToGetResponseFromVolatileHost
                            }
                in
                ContinueWithTask
                    { task = { taskId = "get_image", task = task }
                    , taskDescription = "Get image from '" ++ imageFilePath ++ "'"
                    }

        GotImage gotImage ->
            let
                task =
                    InterfaceToHost.RunInVolatileHost
                        { hostId = gotImage.volatileHost.hostId
                        , script =
                            { fileIdBase16 = gotImage.volatileHostResponse.fileIdBase16
                            , left = 0
                            , top = 0
                            , width = gotImage.volatileHostResponse.widthInPixels
                            , height = gotImage.volatileHostResponse.heightInPixels
                            , binningX = 1
                            , binningY = 1
                            }
                                |> VolatileHostSetup.GetPixelsFromImageRectangle
                                |> VolatileHostSetup.buildScriptToGetResponseFromVolatileHost
                        }
            in
            ContinueWithTask
                { task = { taskId = "get_image_pixels", task = task }
                , taskDescription = "Get image pixels"
                }

        GotImagePixels gotImagePixels ->
            let
                describeSearchResults =
                    let
                        searchResultsLocationsToDisplay =
                            gotImagePixels.imageSearchResultLocations |> List.take 40
                    in
                    "Found matches in "
                        ++ (gotImagePixels.imageSearchResultLocations |> List.length |> String.fromInt)
                        ++ " locations:\n[ "
                        ++ (searchResultsLocationsToDisplay |> List.map describeLocation |> String.join ", ")
                        ++ " ]"
            in
            StopWithResult
                { resultDescription = describeSearchResults
                }


describeLocation : { x : Int, y : Int } -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"


dictWithTupleKeyFromNestedList : List (List a) -> Dict.Dict ( Int, Int ) a
dictWithTupleKeyFromNestedList nestedList =
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

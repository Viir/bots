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

   bot-catalog-tags:demo,test,locate-object-in-image
-}


module Main exposing
    ( InterfaceBotState
    , State
    , interfaceToHost_deserializeState
    , interfaceToHost_initState
    , interfaceToHost_processEvent
    , interfaceToHost_serializeState
    , main
    )

import Base64.Decode
import Bot_Interface_To_Host_20190529 as InterfaceToHost exposing (BotEventAtTime, BotRequest(..))
import DecodeBMPImage exposing (DecodeBMPImageResult, PixelValue)
import Dict
import Json.Decode
import Maybe.Extra
import VolatileHostSetup exposing (ReadFileContentResultStructure(..), RequestToVolatileHost(..), ResponseFromVolatileHost(..))


type alias State =
    { imageFileName : Maybe String
    , lastStepResult : ProcessStepResult
    , error : Maybe String
    }


type ProcessStepResult
    = Initialized
    | VolatileHostCreated VolatileHostCreatedStructure
    | VolatileHostSetupCompleted VolatileHostCreatedStructure
    | FileContentsRead FileContentsReadStructure


type alias VolatileHostCreatedStructure =
    { hostId : String }


type alias FileContentsReadStructure =
    { volatileHost : VolatileHostCreatedStructure
    , decodeImageResult :
        Result String
            { image : DecodeBMPImageResult
            , imageSearchResultLocations : List { x : Int, y : Int }
            }
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


getMatchesLocationsFromDecodeImageResult : DecodeBMPImageResult -> List { x : Int, y : Int }
getMatchesLocationsFromDecodeImageResult decodeImageResult =
    decodeImageResult |> pixelValueDictFromDecodeBMPImageResult |> getMatchesLocationsFromImage


{-| This is the square-shaped thing displayed in the route info panel in the game EVE Online.
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


processEvent : BotEventAtTime -> State -> ( State, List BotRequest )
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

        ( requests, activityDescription ) =
            case nextStep of
                StopWithResult { resultDescription } ->
                    ( [ FinishSession ], "Stopped with result: " ++ resultDescription )

                ContinueWithTask continue ->
                    ( [ StartTask continue.task ], "Current step: " ++ continue.taskDescription )

        statusDescription =
            (state |> statusDescriptionFromState)
                ++ "\n"
                ++ activityDescription
    in
    ( state, requests ++ [ SetStatusMessage statusDescription ] )


integrateEvent : BotEventAtTime -> State -> State
integrateEvent eventAtTime stateBefore =
    case eventAtTime.event of
        InterfaceToHost.SetBotConfiguration configuration ->
            { stateBefore | imageFileName = Just configuration }

        InterfaceToHost.SetSessionTimeLimitInMilliseconds _ ->
            stateBefore

        InterfaceToHost.TaskComplete { taskId, taskResult } ->
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

                                        FileContentsRead _ ->
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
                                                        ReadFileContentResult DidNotFindFileAtSpecifiedPath ->
                                                            { stateBefore | error = Just "Reading the file failed: Did not find the file at the specified path." }

                                                        ReadFileContentResult (ExceptionAsString exceptionAsString) ->
                                                            { stateBefore | error = Just ("Reading the file failed with exception: " ++ exceptionAsString) }

                                                        ReadFileContentResult (FileContentAsBase64 fileContentBase64) ->
                                                            case fileContentBase64 |> Base64.Decode.decode Base64.Decode.bytes of
                                                                Err base64decodeError ->
                                                                    { stateBefore | error = Just "Error decoding the file contents from base64." }

                                                                Ok fileContents ->
                                                                    let
                                                                        decodeImageResult =
                                                                            fileContents
                                                                                |> DecodeBMPImage.decodeBMPImageFile
                                                                                |> Result.map
                                                                                    (\decodeResult ->
                                                                                        { image = decodeResult
                                                                                        , imageSearchResultLocations = decodeResult |> getMatchesLocationsFromDecodeImageResult
                                                                                        }
                                                                                    )

                                                                        fileContentsRead =
                                                                            { volatileHost = volatileHost
                                                                            , decodeImageResult = decodeImageResult
                                                                            }
                                                                    in
                                                                    { stateBefore | lastStepResult = FileContentsRead fileContentsRead }

                InterfaceToHost.CompleteWithoutResult ->
                    stateBefore


statusDescriptionFromState : State -> String
statusDescriptionFromState state =
    case state.imageFileName |> Maybe.withDefault "" of
        "" ->
            "I have not received a path to an image to load."

        imageFileName ->
            "I received '" ++ imageFileName ++ "' as the path to the image to load."


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
                            , script = { filePath = imageFilePath } |> ReadFileContent |> VolatileHostSetup.buildScriptToGetResponseFromVolatileHost
                            }
                in
                ContinueWithTask
                    { task = { taskId = "read_file_content", task = task }
                    , taskDescription = "Read content of file at '" ++ imageFilePath ++ "'"
                    }

        FileContentsRead fileContentsRead ->
            case fileContentsRead.decodeImageResult of
                Err decodeImageError ->
                    StopWithResult
                        { resultDescription = "Failed to decode image: " ++ decodeImageError }

                Ok decodeImageSuccess ->
                    let
                        describeSearchResults =
                            let
                                searchResultsLocationsToDisplay =
                                    decodeImageSuccess.imageSearchResultLocations |> List.take 40
                            in
                            "Found matches in "
                                ++ (decodeImageSuccess.imageSearchResultLocations |> List.length |> String.fromInt)
                                ++ " locations:\n[ "
                                ++ (searchResultsLocationsToDisplay |> List.map describeLocation |> String.join ", ")
                                ++ " ]"
                    in
                    StopWithResult
                        { resultDescription = "Decoded image: " ++ (decodeImageSuccess.image |> describeImage) ++ "\n" ++ describeSearchResults
                        }


describeLocation : { x : Int, y : Int } -> String
describeLocation { x, y } =
    "{ x = " ++ (x |> String.fromInt) ++ ", y = " ++ (y |> String.fromInt) ++ " }"


pixelValueDictFromDecodeBMPImageResult : DecodeBMPImage.DecodeBMPImageResult -> Dict.Dict ( Int, Int ) PixelValue
pixelValueDictFromDecodeBMPImageResult decodeImageResult =
    decodeImageResult.pixelsLeftToRightTopToBottom
        |> List.indexedMap
            (\pixelIndex pixelValue ->
                ( ( pixelIndex |> modBy decodeImageResult.bitmapWidthInPixels, pixelIndex // decodeImageResult.bitmapWidthInPixels )
                , pixelValue
                )
            )
        |> Dict.fromList


describeImage : DecodeBMPImageResult -> String
describeImage image =
    [ ( "bitmapWidthInPixels", image.bitmapWidthInPixels |> String.fromInt )
    , ( "bitmapHeightInPixels", image.bitmapHeightInPixels |> String.fromInt )
    ]
        |> List.map (\( property, value ) -> property ++ ": " ++ value)
        |> String.join ", "


type alias InterfaceBotState =
    State


interfaceToHost_initState : InterfaceBotState
interfaceToHost_initState =
    initState


interfaceToHost_processEvent : String -> InterfaceBotState -> ( InterfaceBotState, String )
interfaceToHost_processEvent =
    InterfaceToHost.wrapForSerialInterface_processEvent processEvent


interfaceToHost_serializeState : InterfaceBotState -> String
interfaceToHost_serializeState =
    always ""


interfaceToHost_deserializeState : String -> InterfaceBotState
interfaceToHost_deserializeState =
    always interfaceToHost_initState


{-| Define the Elm entry point. Don't change this function.
-}
main : Program Int InterfaceBotState String
main =
    InterfaceToHost.elmEntryPoint interfaceToHost_initState interfaceToHost_processEvent interfaceToHost_serializeState (interfaceToHost_deserializeState >> always interfaceToHost_initState)

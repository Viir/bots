module Main exposing (main)

{-
   This demo was adapted from https://github.com/ivadzy/ivadzy.github.io/tree/90013a59b3889f68e89f590d77c280ead3a424b6/demos/bbase64
   Credits to Ivan for supplying us with such a nice demo!
-}

import Base64.Encode
import Bitwise
import Browser
import Bytes
import DecodeBMPImage exposing (DecodeBMPImageResult)
import File
import Html
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode
import Task


type Event
    = NoOp
    | OnDrop (List File.File)
    | FileDropped Bytes.Bytes
    | ConfigureImageSearch PixelValueExactRGB


type alias PixelValueExactRGB =
    { red : Int, green : Int, blue : Int }


type alias FileReadResult =
    { fileAsBase64 : String
    , decodeImageResult : Result String DecodeBMPImage.DecodeBMPImageResult
    }


type alias State =
    { fileReadResult : Maybe FileReadResult
    , imageSearchConfiguration : ImageSearchConfiguration
    , imageSearchResults : Maybe (List { x : Int, y : Int })
    }


type alias ImageSearchConfiguration =
    PixelValueExactRGB


main : Program () State Event
main =
    Browser.document
        { init = init
        , view = \state -> { title = "Search in BMP Image", body = [ view state ] }
        , update = update
        , subscriptions = \_ -> Sub.none
        }


init : () -> ( State, Cmd Event )
init _ =
    let
        initialState =
            { fileReadResult = Nothing
            , imageSearchConfiguration = { red = 0, green = 0, blue = 0 }
            , imageSearchResults = Nothing
            }
    in
    ( initialState, Cmd.none )


update : Event -> State -> ( State, Cmd Event )
update msg stateBefore =
    case msg of
        NoOp ->
            Debug.log "noop" <|
                ( stateBefore, Cmd.none )

        OnDrop files ->
            let
                task =
                    case List.head files of
                        Just file ->
                            Task.perform FileDropped (File.toBytes file)

                        Nothing ->
                            Cmd.none
            in
            ( stateBefore, task )

        FileDropped bytes ->
            let
                fileAsBase64 =
                    Base64.Encode.encode (Base64.Encode.bytes bytes)

                decodeImageResult =
                    DecodeBMPImage.decodeBMPImageFile bytes
            in
            ( { stateBefore
                | fileReadResult = Just { fileAsBase64 = fileAsBase64, decodeImageResult = decodeImageResult }
                , imageSearchResults = Nothing
              }
            , Cmd.none
            )

        ConfigureImageSearch imageSearchConfiguration ->
            let
                imageSearchResults =
                    stateBefore.fileReadResult
                        |> Maybe.andThen (.decodeImageResult >> Result.toMaybe)
                        |> Maybe.map (findMatchesInImage imageSearchConfiguration)
            in
            ( { stateBefore
                | imageSearchConfiguration = imageSearchConfiguration
                , imageSearchResults = imageSearchResults
              }
            , Cmd.none
            )



-- Drag and Drop


onDrop : (List File.File -> msg) -> Html.Attribute msg
onDrop msg =
    let
        fileDecoder =
            Json.Decode.field "dataTransfer" (Json.Decode.field "files" (Json.Decode.list File.decoder))

        dropDecoder msg_ =
            Json.Decode.map msg_ fileDecoder
                |> Json.Decode.map alwaysPreventDefault
    in
    HE.preventDefaultOn "drop" (dropDecoder msg)


onDragOver : msg -> Html.Attribute msg
onDragOver msg =
    HE.preventDefaultOn "dragover" (Json.Decode.map alwaysPreventDefault (Json.Decode.succeed msg))


alwaysPreventDefault : msg -> ( msg, Bool )
alwaysPreventDefault msg =
    ( msg, True )



-- View


view : State -> Html.Html Event
view state =
    Html.div [] <|
        viewInfoSection state
            :: [ viewWidget state ]


viewInfoSection : State -> Html.Html Event
viewInfoSection state =
    Html.section []
        [ Html.header []
            [ Html.h1 [] [ Html.text "Base64 Encoding" ]
            ]
        , Html.p []
            [ Html.text "Base64 is a group of similar binary-to-text encoding schemes that represent binary data in an ASCII string format by translating it into a radix-64 representation. The term Base64 originates from a specific MIME content transfer encoding. Each Base64 digit represents exactly 6 bits of data. Three 8-bit bytes (i.e., a total of 24 bits) can therefore be represented by four 6-bit Base64 digits. "
            , Html.a [ HA.href "https://en.wikipedia.org/wiki/Base64" ] [ Html.text "Base64 on Wikipedia" ]
            ]
        , Html.p []
            [ Html.a [ HA.href "https://github.com/ivadzy/bbase64" ] [ Html.text "Repository" ]
            ]
        ]


viewWidget : State -> Html.Html Event
viewWidget state =
    let
        fileReadResultHtml =
            case state.fileReadResult of
                Nothing ->
                    Html.text "No file loaded so far."

                Just fileReadResult ->
                    viewFileReadResult fileReadResult

        imageSearchHtml =
            viewImageSearchConfiguration state.imageSearchConfiguration
    in
    [ Html.div [ HA.style "padding" "1em", onDrop OnDrop, onDragOver NoOp ] [ Html.text "Drop a file here" ]
    , fileReadResultHtml
    , [] |> Html.div [ HA.style "height" "1em" ]
    , [ "Configure Image Search" |> Html.text ] |> Html.div []
    , [ imageSearchHtml ] |> Html.div [ HA.style "margin-left" "1em" ]
    , [] |> Html.div [ HA.style "height" "1em" ]
    , [ "Image Search Results" |> Html.text ] |> Html.div []
    , [ viewImageSearchResults state.imageSearchResults ] |> Html.div [ HA.style "margin-left" "1em" ]
    ]
        |> Html.div []


fileAsBase64DisplayLengthMax : Int
fileAsBase64DisplayLengthMax =
    100000


viewFileReadResult : FileReadResult -> Html.Html Event
viewFileReadResult fileReadResult =
    let
        imageDecodeResultHtml =
            case fileReadResult.decodeImageResult of
                Err error ->
                    [ ("Decoding failed: " ++ error) |> Html.text ] |> Html.div []

                Ok decodeSuccess ->
                    [ ( "file size / byte", decodeSuccess.fileSizeInBytes |> String.fromInt )
                    , ( "width / pixel", decodeSuccess.bitmapWidthInPixels |> String.fromInt )
                    , ( "height / pixel", decodeSuccess.bitmapHeightInPixels |> String.fromInt )
                    , ( "bits per pixel", decodeSuccess.bitsPerPixel |> String.fromInt )
                    ]
                        |> List.map
                            (\( dimension, amount ) ->
                                [ [ (dimension ++ " = " ++ amount) |> Html.text ]
                                    |> Html.td [ HA.style "padding" "0.1 em" ]
                                ]
                                    |> Html.tr []
                            )
                        |> Html.div []
    in
    [ [ Html.text "A Base64 string of the dropped file" ] |> Html.div []
    , Html.textarea
        [ HA.value
            (if fileAsBase64DisplayLengthMax < (fileReadResult.fileAsBase64 |> String.length) then
                "Base64 encoding is not displayed because it is longer than " ++ (fileAsBase64DisplayLengthMax |> String.fromInt)

             else
                fileReadResult.fileAsBase64
            )
        , HA.readonly True
        , HA.style "margin-left" "1em"
        ]
        []
    , [ Html.text "Image decoding result" ] |> Html.div []
    , [ imageDecodeResultHtml ] |> Html.div [ HA.style "margin-left" "1em" ]
    ]
        |> Html.div []


viewImageSearchConfiguration : ImageSearchConfiguration -> Html.Html Event
viewImageSearchConfiguration state =
    let
        components : List ( String, Int, ImageSearchConfiguration -> Int -> ImageSearchConfiguration )
        components =
            [ ( "red", state.red, \previousValue input -> { previousValue | red = input } )
            , ( "green", state.green, \previousValue input -> { previousValue | green = input } )
            , ( "blue", state.blue, \previousValue input -> { previousValue | blue = input } )
            ]
    in
    components
        |> List.map
            (\( componentName, componentCurrentValue, componentMap ) ->
                let
                    inputMap : String -> Event
                    inputMap =
                        \inputString ->
                            inputString
                                |> String.toInt
                                |> Maybe.map
                                    (\inputAsInt ->
                                        componentMap state inputAsInt
                                    )
                                |> Maybe.map ConfigureImageSearch
                                |> Maybe.withDefault NoOp
                in
                [ componentName |> Html.text
                , []
                    |> Html.input
                        [ HA.value (componentCurrentValue |> String.fromInt)
                        , HE.onInput inputMap
                        ]
                ]
                    |> Html.div []
            )
        |> Html.div []


viewImageSearchResults : Maybe (List { x : Int, y : Int }) -> Html.Html a
viewImageSearchResults maybeSearchResults =
    case maybeSearchResults of
        Nothing ->
            [ "No search performed yet." |> Html.text ] |> Html.div []

        Just searchResults ->
            let
                resultsToDisplay =
                    searchResults |> List.take 10

                truncatedSearchResultsHtml =
                    resultsToDisplay
                        |> List.map
                            (\searchResult ->
                                [ ((searchResult.x |> String.fromInt) ++ ", " ++ (searchResult.y |> String.fromInt)) |> Html.text ]
                                    |> Html.div []
                            )
                        |> Html.div []

                overviewHtml =
                    [ ("Found matches in "
                        ++ (searchResults |> List.length |> String.fromInt)
                        ++ " locations."
                      )
                        |> Html.text
                    ]
                        |> Html.div []
            in
            [ overviewHtml, [ truncatedSearchResultsHtml ] |> Html.div [ HA.style "margin-left" "1em" ] ] |> Html.div []


findMatchesInImage : ImageSearchConfiguration -> DecodeBMPImageResult -> List { x : Int, y : Int }
findMatchesInImage searchConfiguration image =
    let
        pixelValueToSearchAsInt =
            DecodeBMPImage.encodeRGBasInt
                { red = searchConfiguration.red, green = searchConfiguration.green, blue = searchConfiguration.blue }
    in
    image.pixelsAsIntsLeftToRightTopToBottom
        |> List.indexedMap
            (\pixelIndex pixelValue ->
                if pixelValue == pixelValueToSearchAsInt then
                    Just
                        { x = pixelIndex |> modBy image.bitmapWidthInPixels, y = pixelIndex // image.bitmapWidthInPixels }

                else
                    Nothing
            )
        |> List.filterMap identity

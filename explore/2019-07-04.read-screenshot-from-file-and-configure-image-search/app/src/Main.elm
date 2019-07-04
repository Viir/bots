module Main exposing (main)

import Base64.Encode
import Bitwise
import Browser
import Bytes
import DecodeBMPImage exposing (DecodeBMPImageResult)
import Dict
import File
import Html
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode
import Task


viewInfoSection : State -> Html.Html event
viewInfoSection state =
    Html.section []
        [ Html.header []
            [ Html.h1 [] [ Html.text "Configure and Test an Image Search Pattern" ]
            ]
        , Html.p []
            [ Html.text "This example demonstrates how to load a screenshot from a file and locate an object in the screenshot."
            ]
        , Html.p []
            [ Html.text "With the tools below, you can configure an image search pattern and test it with a bitmap image."
            ]
        , Html.p []
            [ Html.a [ HA.href "https://github.com/Viir/bots" ] [ Html.text "Repository" ]
            ]
        , Html.p []
            [ Html.text "Credits to Ivan for supplying the demos for file loading and base64 at https://github.com/ivadzy/ivadzy.github.io/tree/90013a59b3889f68e89f590d77c280ead3a424b6/demos/bbase64"
            ]
        ]


type Event
    = NoOp
    | OnDrop (List File.File)
    | FileDropped Bytes.Bytes
    | ConfigureImageSearch ConfigureImageSearchEvent
    | SetImagePatternConfigureLeafFormState ImagePatternLeaf
    | UpdateImageSearchResults


type ConfigureImageSearchEvent
    = RemovePatternLeaf ImagePatternLeaf
    | AddPatternLeaf ImagePatternLeaf


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


type PixelColorChannel
    = Red
    | Green
    | Blue


type PatternConstraintOnColorChannelValue
    = Minimum Int
    | Maximum Int


type alias ImagePatternLeaf =
    { pixelOffset : { x : Int, y : Int }
    , channel : PixelColorChannel
    , channelValueConstraint : PatternConstraintOnColorChannelValue
    }


type alias FileReadResult =
    { fileAsBase64 : String
    , decodeImageResult : Result String DecodeBMPImage.DecodeBMPImageResult
    , imageAsDict : Maybe (Dict.Dict ( Int, Int ) PixelValue)
    }


type alias State =
    { fileReadResult : Maybe FileReadResult
    , imageSearchConfiguration : ImageSearchConfiguration
    , imageSearchResults : Maybe (List { x : Int, y : Int })
    , imagePatternConfigureLeafForm : ImagePatternLeaf
    }


type alias ImageSearchConfiguration =
    List ImagePatternLeaf


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
            , imageSearchConfiguration = []
            , imageSearchResults = Nothing
            , imagePatternConfigureLeafForm =
                { pixelOffset = { x = 0, y = 0 }, channel = Red, channelValueConstraint = Minimum 0 }
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

                imageAsDict =
                    decodeImageResult
                        |> Result.map pixelValueDictFromDecodeBMPImageResult
                        |> Result.toMaybe
            in
            ( { stateBefore
                | fileReadResult = Just { fileAsBase64 = fileAsBase64, decodeImageResult = decodeImageResult, imageAsDict = imageAsDict }
                , imageSearchResults = Nothing
              }
            , Cmd.none
            )

        ConfigureImageSearch configureImageSearchEvent ->
            let
                imageSearchConfigurationBefore =
                    stateBefore.imageSearchConfiguration

                imageSearchConfiguration =
                    case configureImageSearchEvent of
                        AddPatternLeaf patternLeaf ->
                            imageSearchConfigurationBefore ++ [ patternLeaf ]

                        RemovePatternLeaf patternLeaf ->
                            imageSearchConfigurationBefore |> List.filter ((/=) patternLeaf)
            in
            { stateBefore | imageSearchConfiguration = imageSearchConfiguration } |> update UpdateImageSearchResults

        SetImagePatternConfigureLeafFormState formState ->
            ( { stateBefore | imagePatternConfigureLeafForm = formState }, Cmd.none )

        UpdateImageSearchResults ->
            ( stateBefore |> updateImageSearchResult
            , Cmd.none
            )


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


updateImageSearchResult : State -> State
updateImageSearchResult stateBefore =
    let
        imageSearchResults =
            if stateBefore.imageSearchConfiguration |> List.isEmpty then
                Nothing

            else
                stateBefore.fileReadResult
                    |> Maybe.andThen .imageAsDict
                    |> Maybe.map (findMatchesInImage stateBefore.imageSearchConfiguration)
    in
    { stateBefore | imageSearchResults = imageSearchResults }


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


view : State -> Html.Html Event
view state =
    Html.div [] <|
        viewInfoSection state
            :: [ viewWidget state ]


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
            viewImageSearchConfiguration state
    in
    [ Html.div [ onDrop OnDrop, onDragOver NoOp, HA.style "border" "2px dashed #555", HA.style "padding" "1em" ]
        [ Html.text "Drop an image file here to load it for testing the search pattern." ]
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
    [ [ Html.text "Base64 string of the dropped file" ] |> Html.div []
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


viewImageSearchConfiguration : State -> Html.Html Event
viewImageSearchConfiguration state =
    let
        patternLeavesHtml =
            state.imageSearchConfiguration
                |> List.map viewImagePatternLeaf
                |> Html.div []
    in
    [ [ Html.text "List of constraints to accept a match" ] |> Html.div []
    , [ patternLeavesHtml ] |> Html.div [ HA.style "margin-left" "1em" ]
    , [ Html.text "Configure a new constraint" ] |> Html.div []
    , [ viewConfigureImagePatternLeafForm state.imagePatternConfigureLeafForm ] |> Html.div [ HA.style "margin-left" "1em" ]
    ]
        |> Html.div []


viewImagePatternLeaf : ImagePatternLeaf -> Html.Html Event
viewImagePatternLeaf imagePatternLeaf =
    let
        pixelOffsetText =
            (imagePatternLeaf.pixelOffset.x |> String.fromInt) ++ " | " ++ (imagePatternLeaf.pixelOffset.y |> String.fromInt)

        channelName =
            colorChannelFromNameInForm
                |> dictListGet imagePatternLeaf.channel
                |> Maybe.withDefault "Error"

        channelConstraintText =
            case imagePatternLeaf.channelValueConstraint of
                Minimum channelMinimum ->
                    " >= " ++ (channelMinimum |> String.fromInt)

                Maximum channelMaximum ->
                    " <= " ++ (channelMaximum |> String.fromInt)

        removeButtonHtml =
            [ "⌫ remove this constraint" |> Html.text ] |> Html.button [ HE.onClick (RemovePatternLeaf imagePatternLeaf) ]
    in
    [ ("for pixel at " ++ pixelOffsetText ++ ", channel " ++ channelName ++ channelConstraintText) |> Html.text, removeButtonHtml ]
        |> Html.div []
        |> Html.map ConfigureImageSearch


viewConfigureImagePatternLeafForm : ImagePatternLeaf -> Html.Html Event
viewConfigureImagePatternLeafForm state =
    let
        selectChannelDropdownEvent =
            HE.on "change"
                (pixelColorChannelDecoder |> Json.Decode.map (\channel -> { state | channel = channel }))

        viewOfferedColorChannel : PixelColorChannel -> Html.Html event
        viewOfferedColorChannel offeredChannel =
            let
                label =
                    colorChannelFromNameInForm
                        |> dictListGet offeredChannel
                        |> Maybe.withDefault "Error"
            in
            [ Html.text label ]
                |> Html.option [ HA.value label, HA.selected (state.channel == offeredChannel) ]

        currentSelectedChannelNameInForm =
            colorChannelFromNameInForm
                |> dictListGet state.channel
                |> Maybe.withDefault "none"

        ( selectedChannelConstraintName, selectedOperandValue ) =
            case state.channelValueConstraint of
                Minimum channelMinimum ->
                    ( "min", channelMinimum )

                Maximum channelMaximum ->
                    ( "max", channelMaximum )

        offeredConstraintsOptionsHtml =
            [ ( "min", ">=" ), ( "max", "<=" ) ]
                |> List.map
                    (\( offeredConstraintName, offeredConstraintOperatorText ) ->
                        [ offeredConstraintOperatorText |> Html.text ]
                            |> Html.option
                                [ HA.value offeredConstraintName, HA.selected (selectedChannelConstraintName == offeredConstraintName) ]
                    )

        channelConstraintDecoder : Json.Decode.Decoder PatternConstraintOnColorChannelValue
        channelConstraintDecoder =
            HE.targetValue
                |> Json.Decode.map
                    (\targetValue ->
                        if targetValue == "min" then
                            Minimum selectedOperandValue

                        else
                            Maximum selectedOperandValue
                    )

        selectChannelConstraintDropdownEvent =
            HE.on "change"
                (channelConstraintDecoder |> Json.Decode.map (\channelConstraint -> { state | channelValueConstraint = channelConstraint }))

        operandInputEventDecoder : Json.Decode.Decoder PatternConstraintOnColorChannelValue
        operandInputEventDecoder =
            eventTargetValueAsIntDecoder
                |> Json.Decode.map
                    (\operand ->
                        case state.channelValueConstraint of
                            Minimum _ ->
                                Minimum operand

                            Maximum _ ->
                                Maximum operand
                    )

        operandInputEventAttribute =
            HE.on "input"
                (operandInputEventDecoder |> Json.Decode.map (\channelConstraint -> { state | channelValueConstraint = channelConstraint }))

        operandInputHtml =
            []
                |> Html.input
                    [ HA.value (selectedOperandValue |> String.fromInt)
                    , operandInputEventAttribute
                    , HA.style "width" "3em"
                    ]

        currentPixelOffset =
            state.pixelOffset

        offsetInputHtml =
            [ [ "offset " |> Html.text ] |> Html.span []
            , [ ( currentPixelOffset.x, \input -> { currentPixelOffset | x = input } )
              , ( currentPixelOffset.y, \input -> { currentPixelOffset | y = input } )
              ]
                |> List.map
                    (\( currentValue, inputMap ) ->
                        let
                            eventDecoder =
                                eventTargetValueAsIntDecoder
                                    |> Json.Decode.map (inputMap >> (\newPixelOffset -> { state | pixelOffset = newPixelOffset }))
                        in
                        []
                            |> Html.input
                                [ HE.on "input" eventDecoder
                                , HA.value (currentValue |> String.fromInt)
                                , HA.style "width" "3em"
                                ]
                    )
                |> Html.span []
            ]
                |> Html.span []

        parameterHtml =
            [ offsetInputHtml
            , colorChannelFromNameInForm
                |> List.map (Tuple.first >> viewOfferedColorChannel)
                |> Html.select
                    [ HA.value currentSelectedChannelNameInForm, selectChannelDropdownEvent ]
            , offeredConstraintsOptionsHtml
                |> Html.select
                    [ HA.value selectedChannelConstraintName, selectChannelConstraintDropdownEvent ]
            , operandInputHtml
            ]
                |> Html.span []
                |> Html.map SetImagePatternConfigureLeafFormState
    in
    [ parameterHtml
    , [ "Add this constraint to the search pattern" |> Html.text ] |> Html.button [ HE.onClick (ConfigureImageSearch (AddPatternLeaf state)) ]
    ]
        |> Html.div []


eventTargetValueAsIntDecoder : Json.Decode.Decoder Int
eventTargetValueAsIntDecoder =
    HE.targetValue
        |> Json.Decode.andThen
            (String.toInt
                >> Maybe.map Json.Decode.succeed
                >> Maybe.withDefault (Json.Decode.fail "Failed to parse as integer")
            )


colorChannelFromNameInForm : List ( PixelColorChannel, String )
colorChannelFromNameInForm =
    [ ( Red, "red" ), ( Green, "green" ), ( Blue, "blue" ) ]


pixelColorChannelDecoder : Json.Decode.Decoder PixelColorChannel
pixelColorChannelDecoder =
    HE.targetValue
        |> Json.Decode.andThen
            (\targetValue ->
                colorChannelFromNameInForm
                    |> List.map tupleSwap
                    |> dictListGet targetValue
                    |> Maybe.map Json.Decode.succeed
                    |> Maybe.withDefault (Json.Decode.fail ("Invalid channel kind: " ++ targetValue))
            )


viewImageSearchResults : Maybe (List { x : Int, y : Int }) -> Html.Html Event
viewImageSearchResults maybeSearchResults =
    case maybeSearchResults of
        Nothing ->
            [ "No search performed yet." |> Html.text
            , [ "Start search for pattern in image now" |> Html.text ] |> Html.button [ HE.onClick UpdateImageSearchResults ]
            ]
                |> Html.div []

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


findMatchesInImage : ImageSearchConfiguration -> Dict.Dict ( Int, Int ) PixelValue -> List { x : Int, y : Int }
findMatchesInImage searchConfiguration imageAsDict =
    imageAsDict
        |> Dict.keys
        |> List.filter
            (\( originX, originY ) ->
                searchConfiguration
                    |> List.all
                        (\patternLeaf ->
                            let
                                leafAbsoluteX =
                                    originX + patternLeaf.pixelOffset.x

                                leafAbsoluteY =
                                    originY + patternLeaf.pixelOffset.y
                            in
                            case imageAsDict |> Dict.get ( leafAbsoluteX, leafAbsoluteY ) of
                                Nothing ->
                                    False

                                Just leafPixelValue ->
                                    let
                                        channelValue =
                                            case patternLeaf.channel of
                                                Red ->
                                                    leafPixelValue.red

                                                Green ->
                                                    leafPixelValue.green

                                                Blue ->
                                                    leafPixelValue.blue
                                    in
                                    case patternLeaf.channelValueConstraint of
                                        Minimum channelMinimum ->
                                            channelMinimum <= channelValue

                                        Maximum channelMaximum ->
                                            channelValue <= channelMaximum
                        )
            )
        |> List.map (\( originX, originY ) -> { x = originX, y = originY })


dictListGet : key -> List ( key, value ) -> Maybe value
dictListGet key dict =
    dict
        |> List.filterMap
            (\( cKey, val ) ->
                if cKey == key then
                    Just val

                else
                    Nothing
            )
        |> List.head


tupleSwap : ( a, b ) -> ( b, a )
tupleSwap ( a, b ) =
    ( b, a )

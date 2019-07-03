module Main exposing (main)

{-
   This demo was adapted from https://github.com/ivadzy/ivadzy.github.io/tree/90013a59b3889f68e89f590d77c280ead3a424b6/demos/bbase64
   Credits to Ivan for supplying us with such a nice demo!
-}

import Base64.Encode
import Browser
import Bytes
import DecodeBMPImage
import File
import Html
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode
import Task


type Msg
    = NoOp
    | OnDrop (List File.File)
    | FileDropped Bytes.Bytes


type alias FileReadResult =
    { fileAsBase64 : String
    , decodeImageResult : Result String DecodeBMPImage.DecodeBMPImageResult
    }


type alias Model =
    { fileReadResult : Maybe FileReadResult
    }


main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = \model -> { title = "ivadzy/bbase64", body = [ view model ] }
        , update = update
        , subscriptions = \_ -> Sub.none
        }


init : () -> ( Model, Cmd Msg )
init _ =
    let
        initialModel =
            { fileReadResult = Nothing
            }
    in
    ( initialModel, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            Debug.log "noop" <|
                ( model, Cmd.none )

        OnDrop files ->
            let
                task =
                    case List.head files of
                        Just file ->
                            Task.perform FileDropped (File.toBytes file)

                        Nothing ->
                            Cmd.none
            in
            ( model, task )

        FileDropped bytes ->
            let
                fileAsBase64 =
                    Base64.Encode.encode (Base64.Encode.bytes bytes)

                decodeImageResult =
                    DecodeBMPImage.decodeBMPImageFile bytes
            in
            ( { model
                | fileReadResult = Just { fileAsBase64 = fileAsBase64, decodeImageResult = decodeImageResult }
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


view : Model -> Html.Html Msg
view model =
    Html.div [] <|
        viewInfoSection model
            :: [ viewWidget model ]


viewInfoSection : Model -> Html.Html Msg
viewInfoSection model =
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


viewWidget : Model -> Html.Html Msg
viewWidget model =
    let
        fileReadResultHtml =
            case model.fileReadResult of
                Nothing ->
                    Html.text "No file loaded so far."

                Just fileReadResult ->
                    viewFileReadResult fileReadResult
    in
    [ Html.div [ HA.style "padding" "1em", onDrop OnDrop, onDragOver NoOp ] [ Html.text "Drop a file here" ]
    , fileReadResultHtml
    ]
        |> Html.div []


fileAsBase64DisplayLengthMax : Int
fileAsBase64DisplayLengthMax =
    100000


viewFileReadResult : FileReadResult -> Html.Html Msg
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

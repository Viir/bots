module Main exposing (main)

import Base64.Decode as Decode
import Base64.Encode as Encode
import Browser
import Bytes
import File
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (on, onClick, onInput, preventDefaultOn)
import Json.Decode exposing (field, list)
import Task


type Msg
    = NoOp
    | ToTextExample
    | ToImageExample
    | OnTextInput String
    | OnTextOutput String
    | OnDrop (List File.File)
    | FileBytesEncoded Bytes.Bytes


type alias Model =
    { input : String
    , output : String
    , imageEncoded : String
    , widgetType : String
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
            Model
                ""
                ""
                ""
                "text"
    in
    ( initialModel, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            Debug.log "noop" <|
                ( model, Cmd.none )

        ToImageExample ->
            ( { model | widgetType = "image" }, Cmd.none )

        ToTextExample ->
            ( { model | widgetType = "text" }, Cmd.none )

        OnTextInput input ->
            let
                encoded =
                    Encode.encode (Encode.string input)
            in
            ( { model | input = input, output = encoded }, Cmd.none )

        OnTextOutput output ->
            let
                decodedResult =
                    Decode.decode Decode.string output
            in
            case decodedResult of
                Ok decoded ->
                    ( { model | input = decoded, output = output }, Cmd.none )

                Err e ->
                    ( { model | input = Debug.toString e, output = output }, Cmd.none )

        OnDrop files ->
            let
                task =
                    case List.head files of
                        Just file ->
                            Task.perform FileBytesEncoded (File.toBytes file)

                        Nothing ->
                            Cmd.none
            in
            ( model, task )

        FileBytesEncoded bytes ->
            let
                encoded =
                    Encode.encode (Encode.bytes bytes)
            in
            ( { model | imageEncoded = encoded }, Cmd.none )



-- Drag and Drop


onDrop : (List File.File -> msg) -> Html.Attribute msg
onDrop msg =
    let
        fileDecoder =
            field "dataTransfer" (field "files" (list File.decoder))

        dropDecoder msg_ =
            Json.Decode.map msg_ fileDecoder
                |> Json.Decode.map alwaysPreventDefault
    in
    preventDefaultOn "drop" (dropDecoder msg)


onDragOver : msg -> Html.Attribute msg
onDragOver msg =
    preventDefaultOn "dragover" (Json.Decode.map alwaysPreventDefault (Json.Decode.succeed msg))


alwaysPreventDefault : msg -> ( msg, Bool )
alwaysPreventDefault msg =
    ( msg, True )



-- View


view : Model -> Html Msg
view model =
    div [ class "main-wrapper" ] <|
        viewInfoSection model
            :: [ viewWidget model ]


viewInfoSection : Model -> Html Msg
viewInfoSection model =
    section [ class "info-section" ]
        [ header []
            [ h1 [] [ text "Base64 Encoding" ]
            ]
        , p []
            [ text "Base64 is a group of similar binary-to-text encoding schemes that represent binary data in an ASCII string format by translating it into a radix-64 representation. The term Base64 originates from a specific MIME content transfer encoding. Each Base64 digit represents exactly 6 bits of data. Three 8-bit bytes (i.e., a total of 24 bits) can therefore be represented by four 6-bit Base64 digits. "
            , a [ href "https://en.wikipedia.org/wiki/Base64" ] [ text "Base64 on Wikipedia" ]
            ]
        , p []
            [ a [ href "https://github.com/ivadzy/bbase64" ] [ text "Repository" ]
            ]
        ]


viewWidget : Model -> Html Msg
viewWidget model =
    let
        textWidgetButtonDisabled =
            model.widgetType == "text"

        imageWidgeButtonDisabled =
            not textWidgetButtonDisabled
    in
    div [ class "widget" ]
        [ div [ class "widget_wrapper" ]
            [ div [ class "widget_button-wrapper" ]
                [ button [ onClick ToTextExample, disabled textWidgetButtonDisabled ] [ text "Text" ]
                , button [ onClick ToImageExample, disabled imageWidgeButtonDisabled ] [ text "File" ]
                ]
            , if model.widgetType == "text" then
                viewTextWidget model

              else
                viewImageWidget model
            ]
        ]


viewTextWidget : Model -> Html Msg
viewTextWidget model =
    div [ class "text-widget" ]
        [ textarea [ onInput OnTextInput, placeholder "Enter a text", value model.input ] []
        , textarea [ onInput OnTextOutput, placeholder "Encoded output", value model.output ] []
        ]


viewImageWidget : Model -> Html Msg
viewImageWidget model =
    div [ class "image-widget" ]
        [ div [ class "image-widget_dropzone", onDrop OnDrop, onDragOver NoOp ] [ text "Drop a file" ]
        , textarea [ class "image-widget_textarea", placeholder "A Base64 string of the dropped file", value model.imageEncoded ] []
        ]

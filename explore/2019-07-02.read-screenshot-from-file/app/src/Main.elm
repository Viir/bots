module Main exposing (main)

{-
   This demo was adapted from https://github.com/ivadzy/ivadzy.github.io/tree/90013a59b3889f68e89f590d77c280ead3a424b6/demos/bbase64
   Credits to Ivan for supplying us with such a nice demo!
-}

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
    | OnDrop (List File.File)
    | FileBytesEncoded Bytes.Bytes


type alias Model =
    { input : String
    , output : String
    , imageEncoded : String
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
            { input = ""
            , output = ""
            , imageEncoded = ""
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
    div [ class "widget" ]
        [ div [ class "widget_wrapper" ]
            [ viewImageWidget model
            ]
        ]


viewImageWidget : Model -> Html Msg
viewImageWidget model =
    div [ class "image-widget" ]
        [ div [ class "image-widget_dropzone", onDrop OnDrop, onDragOver NoOp ] [ text "Drop a file" ]
        , textarea [ class "image-widget_textarea", placeholder "A Base64 string of the dropped file", value model.imageEncoded ] []
        ]

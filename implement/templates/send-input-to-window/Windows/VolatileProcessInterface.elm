module Windows.VolatileProcessInterface exposing
    ( KeyboardKey(..)
    , Location2d
    , MouseButton(..)
    , ReadFileContentResultStructure(..)
    , RequestToVolatileProcess(..)
    , ResponseFromVolatileProcess(..)
    , TaskOnWindowStructure(..)
    , WindowId
    , buildRequestStringToGetResponseFromVolatileProcess
    , deserializeResponseFromVolatileProcess
    )

import Json.Decode
import Json.Encode


type RequestToVolatileProcess
    = GetForegroundWindow
    | GetWindowText WindowId
    | TaskOnWindow TaskOnIdentifiedWindowStructure


type ResponseFromVolatileProcess
    = GetForegroundWindowResult WindowId
    | GetWindowTextResult String
    | TakeScreenshotResult TakeScreenshotResultStructure
    | NoReturnValue


type alias TaskOnIdentifiedWindowStructure =
    { windowId : WindowId
    , task : TaskOnWindowStructure
    }


type alias TakeScreenshotResultStructure =
    { pixels : List (List PixelValue) }


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


type ReadFileContentResultStructure
    = DidNotFindFileAtSpecifiedPath
    | ExceptionAsString String
    | FileContentAsBase64 String


type WindowId
    = WindowHandleFromInt Int


type TaskOnWindowStructure
    = BringWindowToForeground
    | MoveMouseToLocation Location2d
    | MouseButtonDown MouseButton
    | MouseButtonUp MouseButton
    | KeyboardKeyDown KeyboardKey
    | KeyboardKeyUp KeyboardKey
    | TakeScreenshot


type alias Location2d =
    { x : Int, y : Int }


type KeyboardKey
    = KeyboardKeyFromVirtualKeyCode Int


type MouseButton
    = MouseButtonLeft
    | MouseButtonRight


buildRequestStringToGetResponseFromVolatileProcess : RequestToVolatileProcess -> String
buildRequestStringToGetResponseFromVolatileProcess =
    encodeRequestToVolatileProcess
        >> Json.Encode.encode 0


encodeRequestToVolatileProcess : RequestToVolatileProcess -> Json.Encode.Value
encodeRequestToVolatileProcess request =
    case request of
        GetForegroundWindow ->
            Json.Encode.object [ ( "GetForegroundWindow", Json.Encode.object [] ) ]

        GetWindowText getWindowText ->
            Json.Encode.object [ ( "GetWindowText", getWindowText |> encodeWindowId ) ]

        TaskOnWindow taskOnWindow ->
            Json.Encode.object [ ( "TaskOnWindow", taskOnWindow |> encodeTaskOnIdentifiedWindowStructure ) ]


deserializeResponseFromVolatileProcess : String -> Result Json.Decode.Error ResponseFromVolatileProcess
deserializeResponseFromVolatileProcess =
    Json.Decode.decodeString decodeResponseFromVolatileProcess


decodeResponseFromVolatileProcess : Json.Decode.Decoder ResponseFromVolatileProcess
decodeResponseFromVolatileProcess =
    Json.Decode.oneOf
        [ Json.Decode.field "GetForegroundWindowResult" decodeWindowId
            |> Json.Decode.map GetForegroundWindowResult
        , Json.Decode.field "GetWindowTextResult" Json.Decode.string
            |> Json.Decode.map GetWindowTextResult
        , Json.Decode.field "TakeScreenshotResult" jsonDecodeTakeScreenshotResult
            |> Json.Decode.map TakeScreenshotResult
        , Json.Decode.field "NoReturnValue" (jsonDecodeSucceedWhenNotNull NoReturnValue)
        ]


jsonDecodeTakeScreenshotResult : Json.Decode.Decoder TakeScreenshotResultStructure
jsonDecodeTakeScreenshotResult =
    Json.Decode.field "pixels" (Json.Decode.list (Json.Decode.list jsonDecodePixelValue))
        |> Json.Decode.map TakeScreenshotResultStructure


jsonDecodePixelValue : Json.Decode.Decoder PixelValue
jsonDecodePixelValue =
    Json.Decode.int
        |> Json.Decode.map
            (\asInt ->
                { red = asInt // (256 * 256)
                , green = asInt // 256 |> modBy 256
                , blue = asInt |> modBy 256
                }
            )


encodeWindowId : WindowId -> Json.Encode.Value
encodeWindowId windowId =
    case windowId of
        WindowHandleFromInt windowHandleFromInt ->
            [ ( "WindowHandleFromInt", windowHandleFromInt |> Json.Encode.int ) ]
                |> Json.Encode.object


decodeWindowId : Json.Decode.Decoder WindowId
decodeWindowId =
    Json.Decode.oneOf
        [ Json.Decode.field "WindowHandleFromInt" Json.Decode.int
            |> Json.Decode.map WindowHandleFromInt
        ]


encodeTaskOnIdentifiedWindowStructure : TaskOnIdentifiedWindowStructure -> Json.Encode.Value
encodeTaskOnIdentifiedWindowStructure taskOnIdentifiedWindow =
    [ ( "windowId", taskOnIdentifiedWindow.windowId |> encodeWindowId )
    , ( "task", taskOnIdentifiedWindow.task |> encodeTaskOnWindowStructure )
    ]
        |> Json.Encode.object


encodeTaskOnWindowStructure : TaskOnWindowStructure -> Json.Encode.Value
encodeTaskOnWindowStructure taskOnWindow =
    case taskOnWindow of
        BringWindowToForeground ->
            [ ( "BringWindowToForeground", [] |> Json.Encode.object ) ]
                |> Json.Encode.object

        MoveMouseToLocation moveMouseToLocation ->
            [ ( "MoveMouseToLocation", moveMouseToLocation |> jsonEncodeLocation2d ) ]
                |> Json.Encode.object

        MouseButtonDown mouseButtonDown ->
            [ ( "MouseButtonDown", mouseButtonDown |> jsonEncodeMouseButton ) ]
                |> Json.Encode.object

        MouseButtonUp mouseButtonUp ->
            [ ( "MouseButtonUp", mouseButtonUp |> jsonEncodeMouseButton ) ]
                |> Json.Encode.object

        KeyboardKeyDown keyboardKeyDown ->
            [ ( "KeyboardKeyDown", keyboardKeyDown |> jsonEncodeKeyboardKey ) ]
                |> Json.Encode.object

        KeyboardKeyUp keyboardKeyUp ->
            [ ( "KeyboardKeyUp", keyboardKeyUp |> jsonEncodeKeyboardKey ) ]
                |> Json.Encode.object

        TakeScreenshot ->
            [ ( "TakeScreenshot", [] |> Json.Encode.object ) ]
                |> Json.Encode.object


jsonEncodeLocation2d : Location2d -> Json.Encode.Value
jsonEncodeLocation2d location =
    [ ( "x", location.x |> Json.Encode.int )
    , ( "y", location.y |> Json.Encode.int )
    ]
        |> Json.Encode.object


jsonEncodeMouseButton : MouseButton -> Json.Encode.Value
jsonEncodeMouseButton mouseButton =
    case mouseButton of
        MouseButtonLeft ->
            [ ( "MouseButtonLeft", [] |> Json.Encode.object ) ] |> Json.Encode.object

        MouseButtonRight ->
            [ ( "MouseButtonRight", [] |> Json.Encode.object ) ] |> Json.Encode.object


jsonEncodeKeyboardKey : KeyboardKey -> Json.Encode.Value
jsonEncodeKeyboardKey keyboardKey =
    case keyboardKey of
        KeyboardKeyFromVirtualKeyCode keyCode ->
            [ ( "KeyboardKeyFromVirtualKeyCode", keyCode |> Json.Encode.int ) ] |> Json.Encode.object


jsonDecodeSucceedWhenNotNull : a -> Json.Decode.Decoder a
jsonDecodeSucceedWhenNotNull valueIfNotNull =
    Json.Decode.value
        |> Json.Decode.andThen
            (\asValue ->
                if asValue == Json.Encode.null then
                    Json.Decode.fail "Is null."

                else
                    Json.Decode.succeed valueIfNotNull
            )

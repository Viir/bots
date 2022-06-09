module Windows.VolatileProcessInterface exposing (..)

import Common.EffectOnWindow
    exposing
        ( EffectOnWindowStructure(..)
        , MouseButton(..)
        , VirtualKeyCode(..)
        , virtualKeyCodeAsInteger
        )
import Json.Decode
import Json.Encode



{-
   One request/response structure design goal is to support the derivation of (performance) metrics and notifications with additional passive programs: The agent events should contain all the info for these derivations.
   To avoid depending on knowledge about the commands that caused these events, we repeat the window ID and reading ID in the response.
-}


type RequestToVolatileProcess
    = ListWindowsRequest
      -- TODO: Phase out GetForegroundWindow
    | GetForegroundWindow
      -- TODO: Phase out GetWindowText
    | GetWindowText WindowId
    | TaskOnWindowRequest TaskOnIdentifiedWindowRequestStruct
    | GetImageDataFromReadingRequest GetImageDataFromReadingRequestStruct


type ResponseFromVolatileProcess
    = ListWindowsResponse (List WindowSummaryStruct)
      -- TODO: Phase out GetForegroundWindowResult
    | GetForegroundWindowResult WindowId
      -- TODO: Phase out GetWindowTextResult
    | GetWindowTextResult String
      -- | TakeScreenshotResult ReadFromWindowResponseStructure
    | TaskOnWindowResponse TaskOnIdentifiedWindowResponseStruct
    | ReadingNotFound
    | GetImageDataFromReadingComplete GetImageDataFromReadingCompleteStruct
    | NoReturnValue


type alias WindowSummaryStruct =
    { windowId : String
    , windowTitle : String
    , windowZIndex : Int
    }


type alias TaskOnIdentifiedWindowRequestStruct =
    { windowId : WindowId
    , task : TaskOnWindowRequestStruct
    }


type alias TaskOnIdentifiedWindowResponseStruct =
    { windowId : WindowId
    , result : TaskOnWindowResponseStruct
    }


type ReadFileContentResultStructure
    = DidNotFindFileAtSpecifiedPath
    | ExceptionAsString String
    | FileContentAsBase64 String


type alias WindowId =
    String



{- TODO:
   Review API structure: Consider adding flag 'bringWindowToForeground' to both ReadFromWindowRequest and EffectSequenceOnWindowRequest.
   Then add a 'wasForegroundWindow' flag to the response. The measurement using `GetForegroundWindow` would happen at the end of an effect sequence or reading. This expansion helps the agent detect when the game window lost focus (Maybe also use `GetFocus` from the WinAPI) during the execution of the associated task.

-}


type TaskOnWindowRequestStruct
    = BringWindowToForeground
    | ReadFromWindowRequest ReadFromWindowStructure
    | EffectSequenceOnWindowRequest (List EffectSequenceOnWindowElement)


type EffectSequenceOnWindowElement
    = EffectElement EffectOnWindowStructure
    | DelayInMillisecondsElement Int


type TaskOnWindowResponseStruct
    = WindowNotFound
    | ReadFromWindowComplete ReadFromWindowCompleteStruct


type alias ReadFromWindowCompleteStruct =
    { readingId : String
    , windowSize : Location2d
    , windowClientRectOffset : Location2d
    , windowClientAreaSize : Location2d
    , imageData : GetImageDataFromReadingResultStructure
    }


type alias GetImageDataFromReadingCompleteStruct =
    { readingId : String
    , imageData : GetImageDataFromReadingResultStructure
    }


type alias ReadFromWindowStructure =
    { getImageData : GetImageDataFromReadingStructure
    }


type alias GetImageDataFromReadingRequestStruct =
    { readingId : String
    , getImageData : GetImageDataFromReadingStructure
    }


type alias GetImageDataFromReadingStructure =
    { crops_1x1_r8g8b8 : List Rect2dStructure
    , crops_2x2_r8g8b8 : List Rect2dStructure
    }


type alias GetImageDataFromReadingResultStructure =
    { crops_1x1_r8g8b8 : List ImageCropRGB
    , crops_2x2_r8g8b8 : List ImageCropRGB
    }


type alias ImageCropRGB =
    ImageCrop PixelValueRGB


type alias ImageCrop pixelFormat =
    { offset : Location2d
    , pixels : List (List pixelFormat)
    }


type alias PixelValueRGB =
    { red : Int
    , green : Int
    , blue : Int
    }


type alias Rect2dStructure =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


type alias Location2d =
    { x : Int
    , y : Int
    }


buildRequestStringToGetResponseFromVolatileProcess : RequestToVolatileProcess -> String
buildRequestStringToGetResponseFromVolatileProcess =
    encodeRequestToVolatileProcess
        >> Json.Encode.encode 0


encodeRequestToVolatileProcess : RequestToVolatileProcess -> Json.Encode.Value
encodeRequestToVolatileProcess request =
    (case request of
        ListWindowsRequest ->
            ( "ListWindowsRequest", Json.Encode.object [] )

        GetForegroundWindow ->
            ( "GetForegroundWindow", Json.Encode.object [] )

        GetWindowText getWindowText ->
            ( "GetWindowText", getWindowText |> encodeWindowId )

        TaskOnWindowRequest taskOnWindowRequest ->
            ( "TaskOnWindowRequest", taskOnWindowRequest |> encodeTaskOnIdentifiedWindowRequestStruct )

        GetImageDataFromReadingRequest getImageDataFromReading ->
            ( "GetImageDataFromReadingRequest"
            , getImageDataFromReading |> encodeGetImageDataFromReadingRequestStruct
            )
    )
        |> List.singleton
        |> Json.Encode.object


deserializeResponseFromVolatileProcess : String -> Result Json.Decode.Error ResponseFromVolatileProcess
deserializeResponseFromVolatileProcess =
    Json.Decode.decodeString decodeResponseFromVolatileProcess


decodeResponseFromVolatileProcess : Json.Decode.Decoder ResponseFromVolatileProcess
decodeResponseFromVolatileProcess =
    Json.Decode.oneOf
        [ Json.Decode.field "ListWindowsResponse" (Json.Decode.list decodeWindowSummaryStruct)
            |> Json.Decode.map ListWindowsResponse
        , Json.Decode.field "GetForegroundWindowResult" decodeWindowId
            |> Json.Decode.map GetForegroundWindowResult
        , Json.Decode.field "GetWindowTextResult" Json.Decode.string
            |> Json.Decode.map GetWindowTextResult
        , Json.Decode.field "TaskOnWindowResponse" decodeTaskOnIdentifiedWindowResponseStruct
            |> Json.Decode.map TaskOnWindowResponse
        , Json.Decode.field "ReadingNotFound" (jsonDecodeSucceedWhenNotNull ReadingNotFound)
        , Json.Decode.field "GetImageDataFromReadingComplete"
            jsonDecodeGetImageDataFromReadingCompleteStruct
            |> Json.Decode.map GetImageDataFromReadingComplete
        , Json.Decode.field "NoReturnValue" (jsonDecodeSucceedWhenNotNull NoReturnValue)
        ]


decodeWindowSummaryStruct : Json.Decode.Decoder WindowSummaryStruct
decodeWindowSummaryStruct =
    Json.Decode.map3 WindowSummaryStruct
        (Json.Decode.field "windowId" Json.Decode.string)
        (Json.Decode.field "windowTitle" Json.Decode.string)
        (Json.Decode.field "windowZIndex" Json.Decode.int)


decodeTaskOnIdentifiedWindowResponseStruct : Json.Decode.Decoder TaskOnIdentifiedWindowResponseStruct
decodeTaskOnIdentifiedWindowResponseStruct =
    Json.Decode.map2 TaskOnIdentifiedWindowResponseStruct
        (Json.Decode.field "windowId" Json.Decode.string)
        (Json.Decode.field "result" decodeTaskOnWindowResponseStruct)


decodeTaskOnWindowResponseStruct : Json.Decode.Decoder TaskOnWindowResponseStruct
decodeTaskOnWindowResponseStruct =
    Json.Decode.oneOf
        [ Json.Decode.field "WindowNotFound" (jsonDecodeSucceedWhenNotNull WindowNotFound)
        , Json.Decode.field "ReadFromWindowComplete"
            jsonDecodeReadFromWindowCompleteStruct
            |> Json.Decode.map ReadFromWindowComplete
        ]


jsonDecodeReadFromWindowCompleteStruct : Json.Decode.Decoder ReadFromWindowCompleteStruct
jsonDecodeReadFromWindowCompleteStruct =
    Json.Decode.map5 ReadFromWindowCompleteStruct
        (Json.Decode.field "readingId" Json.Decode.string)
        (Json.Decode.field "windowSize" jsonDecodeLocation2d)
        (Json.Decode.field "windowClientRectOffset" jsonDecodeLocation2d)
        (Json.Decode.field "windowClientAreaSize" jsonDecodeLocation2d)
        (Json.Decode.field "imageData" jsonDecodeGetImageDataFromReadingResult)


jsonDecodeGetImageDataFromReadingCompleteStruct : Json.Decode.Decoder GetImageDataFromReadingCompleteStruct
jsonDecodeGetImageDataFromReadingCompleteStruct =
    Json.Decode.map2 GetImageDataFromReadingCompleteStruct
        (Json.Decode.field "readingId" Json.Decode.string)
        (Json.Decode.field "imageData" jsonDecodeGetImageDataFromReadingResult)


jsonDecodeGetImageDataFromReadingResult : Json.Decode.Decoder GetImageDataFromReadingResultStructure
jsonDecodeGetImageDataFromReadingResult =
    Json.Decode.map2 GetImageDataFromReadingResultStructure
        (Json.Decode.field "crops_1x1_r8g8b8" (Json.Decode.nullable (Json.Decode.list jsonDecodeImageCrop))
            |> Json.Decode.map (Maybe.withDefault [])
        )
        (Json.Decode.field "crops_2x2_r8g8b8" (Json.Decode.nullable (Json.Decode.list jsonDecodeImageCrop))
            |> Json.Decode.map (Maybe.withDefault [])
        )


jsonDecodeImageCrop : Json.Decode.Decoder ImageCropRGB
jsonDecodeImageCrop =
    Json.Decode.map2 ImageCrop
        (Json.Decode.field "offset" jsonDecodeLocation2d)
        (Json.Decode.field "pixels" (Json.Decode.list (Json.Decode.list jsonDecodePixelValue_R8G8B8)))


jsonDecodePixelValue_R8G8B8 : Json.Decode.Decoder PixelValueRGB
jsonDecodePixelValue_R8G8B8 =
    Json.Decode.int
        |> Json.Decode.map
            (\asInt ->
                { red = asInt // (256 * 256)
                , green = asInt // 256 |> modBy 256
                , blue = asInt |> modBy 256
                }
            )


encodeWindowId : WindowId -> Json.Encode.Value
encodeWindowId =
    Json.Encode.string


decodeWindowId : Json.Decode.Decoder WindowId
decodeWindowId =
    Json.Decode.string


encodeTaskOnIdentifiedWindowRequestStruct : TaskOnIdentifiedWindowRequestStruct -> Json.Encode.Value
encodeTaskOnIdentifiedWindowRequestStruct taskOnIdentifiedWindow =
    [ ( "windowId", taskOnIdentifiedWindow.windowId |> encodeWindowId )
    , ( "task", taskOnIdentifiedWindow.task |> encodeTaskOnWindowRequestStruct )
    ]
        |> Json.Encode.object


encodeTaskOnWindowRequestStruct : TaskOnWindowRequestStruct -> Json.Encode.Value
encodeTaskOnWindowRequestStruct taskOnWindow =
    (case taskOnWindow of
        BringWindowToForeground ->
            ( "BringWindowToForeground", [] |> Json.Encode.object )

        ReadFromWindowRequest readFromWindowRequest ->
            ( "ReadFromWindowRequest", readFromWindowRequest |> encodeReadFromWindow )

        EffectSequenceOnWindowRequest effectSequenceOnWindowRequest ->
            ( "EffectSequenceOnWindowRequest"
            , effectSequenceOnWindowRequest |> Json.Encode.list jsonEncodeEffectSequenceOnWindowElement
            )
    )
        |> List.singleton
        |> Json.Encode.object


encodeGetImageDataFromReadingRequestStruct : GetImageDataFromReadingRequestStruct -> Json.Encode.Value
encodeGetImageDataFromReadingRequestStruct readFromWindow =
    Json.Encode.object
        [ ( "readingId", readFromWindow.readingId |> Json.Encode.string )
        , ( "getImageData", readFromWindow.getImageData |> encodeGetImageDataFromReading )
        ]


decodeGetImageDataFromReadingRequestStruct : Json.Decode.Decoder GetImageDataFromReadingRequestStruct
decodeGetImageDataFromReadingRequestStruct =
    Json.Decode.map2 GetImageDataFromReadingRequestStruct
        (Json.Decode.field "readingId" Json.Decode.string)
        (Json.Decode.field "getImageData" decodeGetImageDataFromReading)


encodeReadFromWindow : ReadFromWindowStructure -> Json.Encode.Value
encodeReadFromWindow readFromWindow =
    Json.Encode.object
        [ ( "getImageData", readFromWindow.getImageData |> encodeGetImageDataFromReading )
        ]


decodeReadFromWindow : Json.Decode.Decoder ReadFromWindowStructure
decodeReadFromWindow =
    Json.Decode.map ReadFromWindowStructure
        (Json.Decode.field "getImageData" decodeGetImageDataFromReading)


encodeGetImageDataFromReading : GetImageDataFromReadingStructure -> Json.Encode.Value
encodeGetImageDataFromReading getImageData =
    Json.Encode.object
        [ ( "crops_1x1_r8g8b8"
          , getImageData.crops_1x1_r8g8b8 |> Json.Encode.list jsonEncodeRect2d
          )
        , ( "crops_2x2_r8g8b8"
          , getImageData.crops_2x2_r8g8b8 |> Json.Encode.list jsonEncodeRect2d
          )
        ]


decodeGetImageDataFromReading : Json.Decode.Decoder GetImageDataFromReadingStructure
decodeGetImageDataFromReading =
    Json.Decode.map2 GetImageDataFromReadingStructure
        (Json.Decode.field "crops_1x1_r8g8b8" (Json.Decode.list jsonDecodeRect2d))
        (Json.Decode.field "crops_2x2_r8g8b8" (Json.Decode.list jsonDecodeRect2d))


jsonEncodeEffectSequenceOnWindowElement : EffectSequenceOnWindowElement -> Json.Encode.Value
jsonEncodeEffectSequenceOnWindowElement sequenceElement =
    (case sequenceElement of
        EffectElement effect ->
            ( "EffectElement", jsonEncodeEffectOnWindowStructure effect )

        DelayInMillisecondsElement milliseconds ->
            ( "DelayInMillisecondsElement", Json.Encode.int milliseconds )
    )
        |> List.singleton
        |> Json.Encode.object


jsonDecodeEffectSequenceOnWindowElement : Json.Decode.Decoder EffectSequenceOnWindowElement
jsonDecodeEffectSequenceOnWindowElement =
    Json.Decode.oneOf
        [ Json.Decode.field "EffectElement"
            (jsonDecodeEffectOnWindowStructure |> Json.Decode.map EffectElement)
        , Json.Decode.field "DelayInMillisecondsElement" Json.Decode.int
            |> Json.Decode.map DelayInMillisecondsElement
        ]


jsonEncodeEffectOnWindowStructure : EffectOnWindowStructure -> Json.Encode.Value
jsonEncodeEffectOnWindowStructure effectOnWindow =
    (case effectOnWindow of
        SetMouseCursorPositionEffect position ->
            ( "SetMouseCursorPositionEffect", position |> jsonEncodeLocation2d )

        KeyDownEffect virtualKeyCode ->
            ( "KeyDownEffect", virtualKeyCode |> jsonEncodeVirtualKeyCode )

        KeyUpEffect virtualKeyCode ->
            ( "KeyUpEffect", virtualKeyCode |> jsonEncodeVirtualKeyCode )
    )
        |> List.singleton
        |> Json.Encode.object


jsonDecodeEffectOnWindowStructure : Json.Decode.Decoder EffectOnWindowStructure
jsonDecodeEffectOnWindowStructure =
    Json.Decode.oneOf
        [ Json.Decode.field "SetMouseCursorPositionEffect" (jsonDecodeLocation2d |> Json.Decode.map SetMouseCursorPositionEffect)
        , Json.Decode.field "KeyDownEffect" (jsonDecodeVirtualKeyCode |> Json.Decode.map KeyDownEffect)
        , Json.Decode.field "KeyUpEffect" (jsonDecodeVirtualKeyCode |> Json.Decode.map KeyUpEffect)
        ]


jsonEncodeVirtualKeyCode : VirtualKeyCode -> Json.Encode.Value
jsonEncodeVirtualKeyCode virtualKeyCode =
    Json.Encode.object [ ( "virtualKeyCode", virtualKeyCode |> virtualKeyCodeAsInteger |> Json.Encode.int ) ]


jsonDecodeVirtualKeyCode : Json.Decode.Decoder VirtualKeyCode
jsonDecodeVirtualKeyCode =
    Json.Decode.field "virtualKeyCode" Json.Decode.int |> Json.Decode.map VirtualKeyCodeFromInt


jsonEncodeRect2d : Rect2dStructure -> Json.Encode.Value
jsonEncodeRect2d rect2d =
    Json.Encode.object
        [ ( "x", rect2d.x |> Json.Encode.int )
        , ( "y", rect2d.y |> Json.Encode.int )
        , ( "width", rect2d.width |> Json.Encode.int )
        , ( "height", rect2d.height |> Json.Encode.int )
        ]


jsonDecodeRect2d : Json.Decode.Decoder Rect2dStructure
jsonDecodeRect2d =
    Json.Decode.map4 Rect2dStructure
        (Json.Decode.field "x" Json.Decode.int)
        (Json.Decode.field "y" Json.Decode.int)
        (Json.Decode.field "width" Json.Decode.int)
        (Json.Decode.field "height" Json.Decode.int)


jsonDecodeLocation2d : Json.Decode.Decoder Location2d
jsonDecodeLocation2d =
    Json.Decode.map2 Location2d
        (Json.Decode.field "x" Json.Decode.int)
        (Json.Decode.field "y" Json.Decode.int)


jsonEncodeLocation2d : Location2d -> Json.Encode.Value
jsonEncodeLocation2d location =
    [ ( "x", location.x |> Json.Encode.int )
    , ( "y", location.y |> Json.Encode.int )
    ]
        |> Json.Encode.object


jsonEncodeMouseButton : MouseButton -> Json.Encode.Value
jsonEncodeMouseButton mouseButton =
    case mouseButton of
        LeftMouseButton ->
            [ ( "LeftMouseButton", [] |> Json.Encode.object ) ] |> Json.Encode.object

        RightMouseButton ->
            [ ( "RightMouseButton", [] |> Json.Encode.object ) ] |> Json.Encode.object


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

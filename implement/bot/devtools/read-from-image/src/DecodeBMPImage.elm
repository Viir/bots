module DecodeBMPImage exposing (DecodeBMPImageResult, PixelValue, decodeBMPImageFile)

import Bitwise
import Bytes
import Bytes.Decode


type alias DecodeBMPImageResult =
    { fileSizeInBytes : Int
    , bitmapWidthInPixels : Int
    , bitmapHeightInPixels : Int
    , bitsPerPixel : Int
    , pixelsLeftToRightTopToBottom : List PixelValue
    }


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


{-| Decode image file based on layout described at <https://en.wikipedia.org/wiki/BMP_file_format>
This decoder only supports the BITMAPINFOHEADER DIB header type.

To understand the Bytes decoding, note that functions in `Bytes.Decode` behave surprisingly.
What was not well visible in the documentation of the elm/bytes package is that the `map_` functions give different byte sequences to the individual decoding functions.
Reading the source code of the map functions reveals this. For example, see the implementation of `map3` at <https://github.com/elm/bytes/blob/2bce2aeda4ef18c3dcccd84084647d22a7af36a6/src/Bytes/Decode.elm#L232-L243>

-}
decodeBMPImageFile : Bytes.Bytes -> Result String DecodeBMPImageResult
decodeBMPImageFile bytes =
    let
        fileSize =
            bytes |> Bytes.width
    in
    if fileSize < 54 then
        Err ("Unexpected file size of " ++ (fileSize |> String.fromInt))

    else
        case
            bytes
                |> Bytes.Decode.decode
                    (Bytes.Decode.map2
                        (\fileHeader dibHeader -> { fileHeader = fileHeader, dibHeader = dibHeader })
                        decodeBMPImageFileHeaderDecoder
                        decoder_for_BITMAPINFOHEADER
                    )
        of
            Nothing ->
                Err "Failed to decode headers"

            Just { fileHeader, dibHeader } ->
                let
                    numberOfPixels =
                        dibHeader.bitmapWidthInPixels * dibHeader.bitmapHeightInPixels

                    pixelsDecoderFromFileBegin =
                        Bytes.Decode.bytes fileHeader.pixelArrayOffset
                            |> Bytes.Decode.andThen
                                (\_ ->
                                    pixelArrayDecoderLeftToRightTopToBottom
                                        { bitmapWidthInPixels = dibHeader.bitmapWidthInPixels
                                        , bitmapHeightInPixels = dibHeader.bitmapHeightInPixels
                                        , bitsPerPixel = dibHeader.bitsPerPixel
                                        }
                                )
                in
                case
                    bytes |> Bytes.Decode.decode pixelsDecoderFromFileBegin
                of
                    Nothing ->
                        Err "Failed to decode pixel array"

                    Just pixelsLeftToRightTopToBottom ->
                        { fileSizeInBytes = fileHeader.fileSizeInBytes
                        , bitmapWidthInPixels = dibHeader.bitmapWidthInPixels
                        , bitmapHeightInPixels = dibHeader.bitmapHeightInPixels
                        , bitsPerPixel = dibHeader.bitsPerPixel
                        , pixelsLeftToRightTopToBottom = pixelsLeftToRightTopToBottom
                        }
                            |> Ok


pixelArrayDecoderLeftToRightTopToBottom : { bitmapWidthInPixels : Int, bitmapHeightInPixels : Int, bitsPerPixel : Int } -> Bytes.Decode.Decoder (List PixelValue)
pixelArrayDecoderLeftToRightTopToBottom { bitmapWidthInPixels, bitmapHeightInPixels, bitsPerPixel } =
    Bytes.Decode.loop ( bitmapHeightInPixels, [] )
        (decodeListStep (pixelRowDecoderLeftToRight { bitmapWidthInPixels = bitmapWidthInPixels, bitsPerPixel = bitsPerPixel }))
        |> Bytes.Decode.map List.concat


pixelRowDecoderLeftToRight : { bitmapWidthInPixels : Int, bitsPerPixel : Int } -> Bytes.Decode.Decoder (List PixelValue)
pixelRowDecoderLeftToRight { bitmapWidthInPixels, bitsPerPixel } =
    let
        bytesPerPixel =
            bitsPerPixel // 8

        bytesPerRowBeforePadding =
            bitmapWidthInPixels * bytesPerPixel

        padding =
            (4 * bitmapWidthInPixels - bytesPerRowBeforePadding) |> modBy 4
    in
    Bytes.Decode.loop ( bitmapWidthInPixels, [] )
        (decodeListStep (pixelDecoder { bitsPerPixel = bitsPerPixel }))
        |> Bytes.Decode.map List.reverse
        |> Bytes.Decode.andThen (\rowPixels -> Bytes.Decode.bytes padding |> Bytes.Decode.map (always rowPixels))


pixelDecoder : { bitsPerPixel : Int } -> Bytes.Decode.Decoder PixelValue
pixelDecoder { bitsPerPixel } =
    if bitsPerPixel == 24 then
        Bytes.Decode.map3
            (\blue green red -> { red = red, green = green, blue = blue })
            Bytes.Decode.unsignedInt8
            Bytes.Decode.unsignedInt8
            Bytes.Decode.unsignedInt8

    else
        Bytes.Decode.fail


decodeListStep : Bytes.Decode.Decoder a -> ( Int, List a ) -> Bytes.Decode.Decoder (Bytes.Decode.Step ( Int, List a ) (List a))
decodeListStep elementDecoder ( n, xs ) =
    if n <= 0 then
        Bytes.Decode.succeed (Bytes.Decode.Done xs)

    else
        Bytes.Decode.map (\x -> Bytes.Decode.Loop ( n - 1, x :: xs )) elementDecoder


decodeBMPImageFileHeaderDecoder : Bytes.Decode.Decoder { fileSizeInBytes : Int, pixelArrayOffset : Int }
decodeBMPImageFileHeaderDecoder =
    Bytes.Decode.map4
        (\_ fileSizeInBytes _ pixelArrayOffset ->
            { fileSizeInBytes = fileSizeInBytes
            , pixelArrayOffset = pixelArrayOffset
            }
        )
        (Bytes.Decode.bytes 2)
        (Bytes.Decode.unsignedInt32 Bytes.LE)
        (Bytes.Decode.bytes 4)
        (Bytes.Decode.unsignedInt32 Bytes.LE)



-- TODO: Evaluate https://package.elm-lang.org/packages/zwilias/elm-bytes-parser/


decoder_for_BITMAPINFOHEADER :
    Bytes.Decode.Decoder
        { headerSizeInBytes : Int
        , bitmapWidthInPixels : Int
        , bitmapHeightInPixels : Int
        , bitsPerPixel : Int
        , compressionMethod : Int
        }
decoder_for_BITMAPINFOHEADER =
    Bytes.Decode.unsignedInt32 Bytes.LE
        |> Bytes.Decode.andThen
            (\headerSizeInBytes ->
                Bytes.Decode.unsignedInt32 Bytes.LE
                    |> Bytes.Decode.andThen
                        (\bitmapWidthInPixels ->
                            Bytes.Decode.unsignedInt32 Bytes.LE
                                |> Bytes.Decode.andThen
                                    (\bitmapHeightInPixels ->
                                        Bytes.Decode.unsignedInt16 Bytes.LE
                                            |> Bytes.Decode.andThen
                                                (\numberOfColorPlanes ->
                                                    Bytes.Decode.unsignedInt16 Bytes.LE
                                                        |> Bytes.Decode.andThen
                                                            (\bitsPerPixel ->
                                                                Bytes.Decode.unsignedInt32 Bytes.LE
                                                                    |> Bytes.Decode.andThen
                                                                        (\compressionMethod ->
                                                                            Bytes.Decode.bytes (4 * 5)
                                                                                |> Bytes.Decode.map
                                                                                    (\rest ->
                                                                                        { headerSizeInBytes = headerSizeInBytes
                                                                                        , bitmapWidthInPixels = bitmapWidthInPixels
                                                                                        , bitmapHeightInPixels = bitmapHeightInPixels
                                                                                        , bitsPerPixel = bitsPerPixel
                                                                                        , compressionMethod = compressionMethod
                                                                                        }
                                                                                    )
                                                                        )
                                                            )
                                                )
                                    )
                        )
            )

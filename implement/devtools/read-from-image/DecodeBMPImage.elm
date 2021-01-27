module DecodeBMPImage exposing (DecodeBMPImageResult, PixelValue, decodeBMPImageFile)

import Bitwise
import Bytes
import Bytes.Decode


type alias DecodeBMPImageResult =
    { fileSizeInBytes : Int
    , bitmapWidthInPixels : Int
    , bitmapHeightInPixels : Int
    , bitsPerPixel : Int
    , pixels : List (List PixelValue)
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
                if dibHeader.bitsPerPixel /= 24 then
                    Err ("Unsupported bitsPerPixel: " ++ (dibHeader.bitsPerPixel |> String.fromInt))

                else
                    let
                        bytesPerPixel =
                            3

                        numberOfPixels =
                            dibHeader.bitmapWidthInPixels * dibHeader.bitmapHeightInPixels

                        bytesPerRowBeforePadding =
                            dibHeader.bitmapWidthInPixels * bytesPerPixel

                        padding =
                            (4 * dibHeader.bitmapWidthInPixels - bytesPerRowBeforePadding) |> modBy 4

                        bytesPerRow =
                            bytesPerRowBeforePadding + padding

                        pixelArrayExpectedBytes =
                            bytesPerRow * dibHeader.bitmapHeightInPixels

                        pixelArrayBytes =
                            fileSize - fileHeader.pixelArrayOffset
                    in
                    if pixelArrayBytes < pixelArrayExpectedBytes then
                        Err
                            ("Too few bytes in pixel array: "
                                ++ (pixelArrayBytes |> String.fromInt)
                                ++ " instead of "
                                ++ (pixelArrayExpectedBytes |> String.fromInt)
                            )

                    else
                        let
                            rowsBytes =
                                List.range 0 (dibHeader.bitmapHeightInPixels - 1)
                                    |> List.map
                                        (\rowIndex ->
                                            let
                                                rowStart =
                                                    fileHeader.pixelArrayOffset + rowIndex * bytesPerRow

                                                rowBytesDecoder =
                                                    Bytes.Decode.bytes rowStart
                                                        |> Bytes.Decode.andThen (always (Bytes.Decode.bytes bytesPerRow))
                                            in
                                            bytes |> Bytes.Decode.decode rowBytesDecoder
                                        )
                                    |> List.reverse

                            rowDecoder =
                                pixelRowDecoderLeftToRight
                                    { bitmapWidthInPixels = dibHeader.bitmapWidthInPixels
                                    , bitsPerPixel = dibHeader.bitsPerPixel
                                    }

                            pixels =
                                rowsBytes
                                    |> List.map (Maybe.andThen (Bytes.Decode.decode rowDecoder) >> Maybe.withDefault [])
                        in
                        { fileSizeInBytes = fileHeader.fileSizeInBytes
                        , bitmapWidthInPixels = dibHeader.bitmapWidthInPixels
                        , bitmapHeightInPixels = dibHeader.bitmapHeightInPixels
                        , bitsPerPixel = dibHeader.bitsPerPixel
                        , pixels = pixels
                        }
                            |> Ok


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
    -- Maybe this can be simplified with `Bytes.Parser.repeat` from https://package.elm-lang.org/packages/zwilias/elm-bytes-parser/
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


decoder_for_BITMAPINFOHEADER :
    Bytes.Decode.Decoder
        { headerSizeInBytes : Int
        , bitmapWidthInPixels : Int
        , bitmapHeightInPixels : Int
        , bitsPerPixel : Int
        , compressionMethod : Int
        }
decoder_for_BITMAPINFOHEADER =
    Bytes.Decode.map3
        (\headerSizeInBytes bitmapWidthInPixels bitmapHeightInPixels ->
            { headerSizeInBytes = headerSizeInBytes
            , bitmapWidthInPixels = bitmapWidthInPixels
            , bitmapHeightInPixels = bitmapHeightInPixels
            }
        )
        (Bytes.Decode.unsignedInt32 Bytes.LE)
        (Bytes.Decode.unsignedInt32 Bytes.LE)
        (Bytes.Decode.unsignedInt32 Bytes.LE)
        |> Bytes.Decode.andThen
            (\headerAndSize ->
                Bytes.Decode.map4
                    (\numberOfColorPlanes bitsPerPixel compressionMethod rest ->
                        { headerSizeInBytes = headerAndSize.headerSizeInBytes
                        , bitmapWidthInPixels = headerAndSize.bitmapWidthInPixels
                        , bitmapHeightInPixels = headerAndSize.bitmapHeightInPixels
                        , bitsPerPixel = bitsPerPixel
                        , compressionMethod = compressionMethod
                        }
                    )
                    (Bytes.Decode.unsignedInt16 Bytes.LE)
                    (Bytes.Decode.unsignedInt16 Bytes.LE)
                    (Bytes.Decode.unsignedInt32 Bytes.LE)
                    (Bytes.Decode.bytes (4 * 5))
            )

module DecodeImageFile exposing (suite)

import Base64.Decode
import Bytes.Decode
import DecodeBMPImage
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Test exposing (..)


{-| Base64 encoding of a file created using the following process:

  - On Windows 10, open Paint.NET.

  - Create an image with size of 4 x 4 pixel.

  - Fill the image using the color with Red = 4, Green = 5, Blue = 6 (Hex 040506).

  - 'Save As', pick 'BMP' and and 'Bit-Depth' of '24-bit'.

-}
example_2019_07_02_4x4_040506_ImageFileBase64 : String
example_2019_07_02_4x4_040506_ImageFileBase64 =
    "Qk1mAAAAAAAAADYAAAAoAAAABAAAAAQAAAABABgAAAAAAAAAAADDDgAAww4AAAAAAAAAAAAABgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUEBgUE"


suite : Test
suite =
    test "Example file is decoded as expected" <|
        \_ ->
            example_2019_07_02_4x4_040506_ImageFileBase64
                |> Base64.Decode.decode Base64.Decode.bytes
                |> Result.toMaybe
                |> Maybe.andThen (Bytes.Decode.decode DecodeBMPImage.decodeBMPImage)
                |> Expect.equal
                    (Just
                        { bitmapWidthInPixels = 4
                        , bitmapHeightInPixels = 4
                        , bitsPerPixel = 24
                        , pixelsAsInts = 40506 |> List.repeat 16
                        }
                    )

module DecodeBMPImage exposing (decodeBMPImage)

import Bytes.Decode


type alias DecodeBMPImageResult =
    { fileSizeInBytes : Int
    , bitmapWidthInPixels : Int
    , bitmapHeightInPixels : Int
    , bitsPerPixel : Int
    , pixelsAsInts : List Int
    }


{-| Decode image file based on layout described at <https://en.wikipedia.org/wiki/BMP_file_format>
-}
decodeBMPImage : Bytes.Decode.Decoder DecodeBMPImageResult
decodeBMPImage =
    Bytes.Decode.fail

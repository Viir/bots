module DecodeBMPImage exposing (decodeBMPImage)

import Bytes.Decode


type alias DecodeBMPImageResult =
    { bitmapWidthInPixels : Int
    , bitmapHeightInPixels : Int
    , bitsPerPixel : Int
    , pixelsAsInts : List Int
    }


decodeBMPImage : Bytes.Decode.Decoder DecodeBMPImageResult
decodeBMPImage =
    Bytes.Decode.fail

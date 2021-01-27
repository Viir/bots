-- source: https://github.com/Skinney/fnv/blob/master/src/FNV.elm


module Common.FNV exposing (hashString)

{-| FNV hash function for hashing strings

@docs hashString

-}

import Bitwise
import Char


fnvPrime : Int
fnvPrime =
    (2 ^ 24) + (2 ^ 8) + 0x93


{-| Takes a string. Returns a hash (integer).
hashString "Turn me into a hash" == 4201504952
-}
hashString : String -> Int
hashString str =
    String.foldl hashHelp 0 str


hashHelp : Char -> Int -> Int
hashHelp c hash =
    (Bitwise.xor hash (Char.toCode c) * fnvPrime)
        |> Bitwise.shiftRightZfBy 0

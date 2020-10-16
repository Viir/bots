module Common.Basics exposing (..)


listElementAtWrappedIndex : Int -> List element -> Maybe element
listElementAtWrappedIndex indexToWrap list =
    if (list |> List.length) < 1 then
        Nothing

    else
        list |> List.drop (indexToWrap |> modBy (list |> List.length)) |> List.head


{-| Remove duplicate values, keeping the first instance of each element which appears more than once.
-}
listUnique : List element -> List element
listUnique =
    List.foldr
        (\nextElement elements ->
            if elements |> List.member nextElement then
                elements

            else
                nextElement :: elements
        )
        []

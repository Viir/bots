module Common.Basics exposing (..)

import List.Extra
import Maybe.Extra
import Result.Extra


resultFirstSuccessOrFirstError : List (Result e o) -> Maybe (Result e o)
resultFirstSuccessOrFirstError list =
    let
        ( oks, errors ) =
            Result.Extra.partition list
    in
    oks
        |> List.head
        |> Maybe.map Ok
        |> Maybe.Extra.orElse (errors |> List.head |> Maybe.map Err)


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


stringContainsIgnoringCase : String -> String -> Bool
stringContainsIgnoringCase pattern =
    String.toLower >> String.contains (String.toLower pattern)


listGatherEqualsBy : (a -> derived) -> List a -> List ( derived, ( a, List a ) )
listGatherEqualsBy derive list =
    List.map
        (\( first, rest ) -> ( derive first, ( first, rest ) ))
        (List.Extra.gatherEqualsBy derive list)

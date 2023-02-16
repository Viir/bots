module ImageProcessingTest exposing (..)

import Base64
import Base64.Decode
import Bot
import BotLab.SimpleBotFramework exposing (Location2d, PixelValueRGB)
import DecodeBMPImage
import Expect
import Sample_2022_03_07
import Test


locate_coin_in_image : Test.Test
locate_coin_in_image =
    Sample_2022_03_07.sample_2022_03_07_coins
        |> List.indexedMap
            (\scenarioIndex scenario ->
                scenario
                    |> buildTestsFromScenario Bot.coinPattern
                    |> Test.describe ("Scenario " ++ String.fromInt scenarioIndex)
            )
        |> Test.describe "Locate instances of coin in image"


expectationLocationTolerance : Int
expectationLocationTolerance =
    4


buildTestsFromScenario :
    BotLab.SimpleBotFramework.LocatePatternInImageApproach
    -> Sample_2022_03_07.ScenarioSinglePatternOnSampleImage
    -> List Test.Test
buildTestsFromScenario pattern scenario =
    case
        scenario.imageFileBase64
            |> Base64.toBytes
            |> Result.fromMaybe "Base64 decode error"
            |> Result.andThen DecodeBMPImage.decodeBMPImageFile
    of
        Err error ->
            [ Test.test "Decode image" <|
                always (Expect.fail ("Failed decoding image file: " ++ error))
            ]

        Ok image ->
            [ { x = 0, y = 0 }
            , { x = 1, y = 0 }
            , { x = 0, y = 1 }
            , { x = 1, y = 1 }
            ]
                |> List.map
                    (\offset ->
                        let
                            imageRepresentation =
                                deriveImageRepresentationFromNestedListOfPixelsAndOffset
                                    offset
                                    image.pixels

                            foundLocations =
                                imageRepresentation
                                    |> BotLab.SimpleBotFramework.locatePatternInImage pattern BotLab.SimpleBotFramework.SearchEverywhere
                                    |> List.sortBy .y
                        in
                        Test.test ("offset " ++ String.fromInt offset.x ++ ", " ++ String.fromInt offset.y) <|
                            always
                                (buildExpectationFromLocations
                                    { expected = scenario.instanceLocations, found = foundLocations }
                                )
                    )


deriveImageRepresentationFromNestedListOfPixelsAndOffset :
    Location2d
    -> List (List BotLab.SimpleBotFramework.PixelValueRGB)
    -> BotLab.SimpleBotFramework.ReadingFromGameClientScreenshot
deriveImageRepresentationFromNestedListOfPixelsAndOffset offset =
    List.map ((++) (List.repeat offset.x { red = 0, green = 0, blue = 0 }))
        >> (++) (List.repeat offset.y [])
        >> deriveImageRepresentationFromNestedListOfPixels


buildExpectationFromLocations :
    { expected : List Location2d, found : List Location2d }
    -> Expect.Expectation
buildExpectationFromLocations originalLocations =
    let
        foundAfterClustering =
            originalLocations.found
                |> Bot.filterRemoveCloseLocations expectationLocationTolerance

        fail failureDetail =
            let
                describeFound =
                    [ ("Found at " ++ String.fromInt (List.length originalLocations.found) ++ " locations before clustering:")
                        :: (originalLocations.found |> List.map describeLocation)
                        |> String.join "\n"
                    , "(" ++ String.fromInt (List.length foundAfterClustering) ++ " remaining after clustering)"
                    ]
                        |> String.join "\n"
            in
            [ failureDetail
            , describeFound
            ]
                |> String.join "\n"
                |> Expect.fail

        recursive locations =
            case locations.expected of
                [] ->
                    case locations.found of
                        [] ->
                            Expect.pass

                        nextFound :: _ ->
                            fail
                                ("Got "
                                    ++ (String.fromInt (List.length foundAfterClustering - List.length originalLocations.expected)
                                            ++ " too many matches: Unexpected at  "
                                            ++ describeLocation nextFound
                                       )
                                )

                nextExpected :: remainingExpected ->
                    case locations.found |> List.sortBy (distanceSquaredFromLocations nextExpected) of
                        [] ->
                            fail
                                ("Missing "
                                    ++ (String.fromInt (List.length originalLocations.expected - List.length foundAfterClustering)
                                            ++ " matches: Did not find  "
                                            ++ describeLocation nextExpected
                                       )
                                )

                        closestFound :: nextRemainingFound ->
                            let
                                distanceSquared =
                                    distanceSquaredFromLocations closestFound nextExpected
                            in
                            if expectationLocationTolerance * expectationLocationTolerance < distanceSquared then
                                fail
                                    ("Did not find "
                                        ++ describeLocation nextExpected
                                        ++ ": Closest found is "
                                        ++ describeLocation closestFound
                                    )

                            else
                                recursive { expected = remainingExpected, found = nextRemainingFound }
    in
    recursive { originalLocations | found = foundAfterClustering }


deriveImageRepresentationFromNestedListOfPixels :
    List (List BotLab.SimpleBotFramework.PixelValueRGB)
    -> BotLab.SimpleBotFramework.ReadingFromGameClientScreenshot
deriveImageRepresentationFromNestedListOfPixels pixelsRows =
    let
        pixels_1x1 ( x, y ) =
            pixelsRows
                |> List.drop y
                |> List.head
                |> Maybe.andThen (List.drop x >> List.head)

        pixels_2x2 =
            bin_pixels_2x2 pixels_1x1

        pixels_4x4 =
            bin_pixels_2x2 pixels_2x2

        width =
            pixelsRows
                |> List.map List.length
                |> List.maximum
                |> Maybe.withDefault 0
    in
    { pixels_1x1 = pixels_1x1
    , pixels_2x2 = pixels_2x2
    , pixels_4x4 = pixels_4x4
    , bounds =
        { left = 0
        , top = 0
        , right = width
        , bottom = List.length pixelsRows
        }
    }


bin_pixels_2x2 : (( Int, Int ) -> Maybe PixelValueRGB) -> ( Int, Int ) -> Maybe PixelValueRGB
bin_pixels_2x2 getPixel ( x, y ) =
    let
        originalPixels =
            [ ( 0, 0 )
            , ( 0, 1 )
            , ( 1, 0 )
            , ( 1, 1 )
            ]
                |> List.filterMap (\( offsetX, offsetY ) -> getPixel ( x * 2 + offsetX, y * 2 + offsetY ))

        componentAverage component =
            List.sum (List.map component originalPixels) // List.length originalPixels
    in
    if List.length originalPixels < 1 then
        Nothing

    else
        Just { red = componentAverage .red, green = componentAverage .green, blue = componentAverage .blue }


describeLocation : Location2d -> String
describeLocation =
    Bot.describeLocation


distanceSquaredFromLocations : Location2d -> Location2d -> Int
distanceSquaredFromLocations a b =
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


stringDescriptionFromBase64DecodeError : Base64.Decode.Error -> String
stringDescriptionFromBase64DecodeError base64DecodeError =
    case base64DecodeError of
        Base64.Decode.ValidationError ->
            "validation error"

        Base64.Decode.InvalidByteSequence ->
            "invalid byte sequence"

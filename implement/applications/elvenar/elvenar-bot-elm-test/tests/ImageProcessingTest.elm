module ImageProcessingTest exposing (..)

import Base64
import Base64.Decode
import Bot
import BotLab.SimpleBotFramework exposing (Location2d)
import DecodeBMPImage
import Expect
import Sample_2022_03_07
import Test


locate_coin_in_image : Test.Test
locate_coin_in_image =
    Sample_2022_03_07.sample_2022_03_07_coins
        |> List.indexedMap
            (\scenarioIndex scenario ->
                Test.test ("Scenario " ++ String.fromInt scenarioIndex) <|
                    always (buildExpectationFromScenario Bot.coinPattern scenario)
            )
        |> Test.describe "Locate instances of coin in image"


expectationLocationTolerance : Int
expectationLocationTolerance =
    3


buildExpectationFromScenario :
    BotLab.SimpleBotFramework.LocatePatternInImageApproach
    -> Sample_2022_03_07.ScenarioSinglePatternOnSampleImage
    -> Expect.Expectation
buildExpectationFromScenario pattern scenario =
    case
        scenario.imageFileBase64
            |> Base64.toBytes
            |> Result.fromMaybe "Base64 decode error"
            |> Result.andThen DecodeBMPImage.decodeBMPImageFile
    of
        Err error ->
            Expect.fail ("Failed decoding image file: " ++ error)

        Ok image ->
            let
                imageRepresentation =
                    BotLab.SimpleBotFramework.deriveImageRepresentation image.pixels

                foundLocations =
                    imageRepresentation
                        |> BotLab.SimpleBotFramework.locatePatternInImage pattern BotLab.SimpleBotFramework.SearchEverywhere
                        |> Bot.filterRemoveCloseLocations expectationLocationTolerance
                        |> List.sortBy .y
            in
            buildExpectationFromLocations { expected = scenario.instanceLocations, found = foundLocations }


buildExpectationFromLocations :
    { expected : List Location2d, found : List Location2d }
    -> Expect.Expectation
buildExpectationFromLocations originalLocations =
    let
        recursive locations =
            case locations.expected of
                [] ->
                    case locations.found of
                        [] ->
                            Expect.pass

                        nextFound :: _ ->
                            Expect.fail
                                ("Got "
                                    ++ (String.fromInt (List.length originalLocations.expected - List.length originalLocations.found)
                                            ++ " too many matches: Unexpected at  "
                                            ++ describeLocation nextFound
                                       )
                                )

                nextExpected :: remainingExpected ->
                    case locations.found |> List.sortBy (distanceSquaredFromLocations nextExpected) of
                        [] ->
                            Expect.fail
                                ("Missing "
                                    ++ (String.fromInt (List.length originalLocations.expected - List.length originalLocations.found)
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
                                Expect.fail
                                    ("Did not find "
                                        ++ describeLocation nextExpected
                                        ++ ": Closest found is "
                                        ++ describeLocation closestFound
                                    )

                            else
                                recursive { expected = remainingExpected, found = nextRemainingFound }
    in
    recursive originalLocations


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

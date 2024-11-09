module EveOnline.ParseGuiFromScreenshot exposing (..)

import Dict
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion)
import Json.Encode
import List.Extra
import Maybe.Extra
import Result.Extra


type alias ReadingFromGameClientScreenshot =
    { pixels_1x1 : ( Int, Int ) -> Maybe PixelValueRGB
    , pixels_2x2 : ( Int, Int ) -> Maybe PixelValueRGB
    }


type alias PixelValueRGB =
    { red : Int, green : Int, blue : Int }


type alias Location2d =
    EveOnline.ParseUserInterface.Location2d


type alias RegionWithLabelText =
    { region : DisplayRegion
    , labelText : Maybe String
    }


type alias ParsedButton =
    { uiNode : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
    , mainText : Maybe String
    }


type alias DisplayRegion =
    EveOnline.ParseUserInterface.DisplayRegion


parseUserInterfaceFromScreenshot :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.ParsedUserInterface
    -> Result String EveOnline.ParseUserInterface.ParsedUserInterface
parseUserInterfaceFromScreenshot screenshot original =
    original.messageBoxes
        |> List.map (parseUserInterfaceFromScreenshotMessageBox screenshot)
        |> Result.Extra.combine
        |> Result.andThen
            (\messageBoxes ->
                original.repairShopWindow
                    |> Maybe.map (parseUserInterfaceFromScreenshotRepairShopWindow screenshot >> Result.map Just)
                    |> Maybe.withDefault (Ok Nothing)
                    |> Result.map
                        (\repairShopWindow ->
                            { original
                                | messageBoxes = messageBoxes
                                , repairShopWindow = repairShopWindow
                            }
                        )
            )


parseUserInterfaceFromScreenshotMessageBox :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.MessageBox
    -> Result String EveOnline.ParseUserInterface.MessageBox
parseUserInterfaceFromScreenshotMessageBox screenshot messageBox =
    case messageBox.buttonGroup of
        Nothing ->
            Ok messageBox

        Just buttonGroup ->
            buttonGroup
                |> parseButtonsFromButtonGroupRowAsUIElements screenshot
                |> Result.map
                    (\fromImageButtons ->
                        { messageBox
                            | buttons = messageBox.buttons ++ fromImageButtons
                        }
                    )


parseUserInterfaceFromScreenshotRepairShopWindow :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.RepairShopWindow
    -> Result String EveOnline.ParseUserInterface.RepairShopWindow
parseUserInterfaceFromScreenshotRepairShopWindow screenshot repairShopWindow =
    case repairShopWindow.buttonGroup of
        Nothing ->
            Ok repairShopWindow

        Just buttonGroup ->
            buttonGroup
                |> parseButtonsFromButtonGroupRowAsUIElements screenshot
                |> Result.map
                    (\fromImageButtons ->
                        { repairShopWindow
                            | buttons = repairShopWindow.buttons ++ fromImageButtons
                        }
                    )


parseButtonsFromButtonGroupRowAsUIElements :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
    -> Result String (List ParsedButton)
parseButtonsFromButtonGroupRowAsUIElements screenshot buttonGroup =
    parseButtonsFromButtonGroupRow screenshot buttonGroup
        |> Result.map
            (List.indexedMap
                (\buttonIndex button ->
                    { uiNode =
                        { uiNode =
                            { originalJson = Json.Encode.null
                            , pythonObjectAddress =
                                buttonGroup.uiNode.pythonObjectAddress
                                    ++ "-button-"
                                    ++ String.fromInt buttonIndex
                            , pythonObjectTypeName = "button-from-screenshot"
                            , dictEntriesOfInterest = Dict.empty
                            , children = Nothing
                            }
                        , totalDisplayRegion = button.region
                        , totalDisplayRegionVisible = button.region
                        , children = Nothing
                        , selfDisplayRegion = button.region
                        }
                    , mainText = button.labelText
                    }
                )
            )


{-| Parses buttons from a button group as seen in message boxes and other windows.
Constraints derived from the observations of game clients: All buttons are aligned in a single row, sharing the same horizontal (upper and lower) edges.
-}
parseButtonsFromButtonGroupRow :
    ReadingFromGameClientScreenshot
    -> EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
    -> Result String (List RegionWithLabelText)
parseButtonsFromButtonGroupRow screenshot buttonGroup =
    let
        colorDifferenceSum colorA colorB =
            [ colorA.red - colorB.red
            , colorA.green - colorB.green
            , colorA.blue - colorB.blue
            ]
                |> List.map abs
                |> List.sum

        getTextFromButtonCenter : Location2d -> Result String (Maybe String)
        getTextFromButtonCenter buttonCenter =
            case
                readButtonLabel
                    { x = buttonCenter.x // 2 - 1, width = 3, y = buttonCenter.y // 2 - 1, height = 3 }
                    { pixels_2x2 = screenshot.pixels_2x2 }
            of
                [] ->
                    Ok Nothing

                [ singleMatch ] ->
                    Ok (Just singleMatch)

                moreMatches ->
                    Err ("Matched " ++ String.fromInt (List.length moreMatches) ++ " labels: " ++ String.join ", " moreMatches)

        measureButtonEdgesY =
            buttonGroup.totalDisplayRegion.y + 6

        measureButtonEdgesLeft_2 =
            buttonGroup.totalDisplayRegion.x // 2 - 1

        measureButtonEdgesRight_2 =
            (measureButtonEdgesLeft_2 + buttonGroup.totalDisplayRegion.width // 2) + 1

        getEdgeLinePixel x =
            screenshot.pixels_2x2 ( x, measureButtonEdgesY // 2 )
    in
    case
        List.range measureButtonEdgesLeft_2 measureButtonEdgesRight_2
            |> List.map
                (\x ->
                    case ( getEdgeLinePixel (x - 1), getEdgeLinePixel (x + 1) ) of
                        ( Just leftPixel, Just rightPixel ) ->
                            Just (20 < colorDifferenceSum leftPixel rightPixel)

                        _ ->
                            Nothing
                )
            |> Maybe.Extra.combine
    of
        Nothing ->
            Err
                ("Missing pixel data for button group at "
                    ++ String.fromInt
                        (buttonGroup.totalDisplayRegion.x + buttonGroup.totalDisplayRegion.width // 2)
                    ++ ","
                    ++ String.fromInt
                        (buttonGroup.totalDisplayRegion.y + buttonGroup.totalDisplayRegion.height // 2)
                )

        Just buttonEdgesBools_2 ->
            let
                fromImageButtonsRegions =
                    buttonEdgesBools_2
                        |> centersOfTrueSequences
                        |> List.map ((+) measureButtonEdgesLeft_2)
                        |> pairsFromList
                        |> Tuple.first
                        |> List.map
                            (\( left_binned, right_binned ) ->
                                { x = left_binned * 2
                                , y = buttonGroup.totalDisplayRegion.y
                                , width = (right_binned - left_binned) * 2
                                , height = buttonGroup.totalDisplayRegion.height
                                }
                            )
            in
            fromImageButtonsRegions
                |> List.map
                    (\fromImageButtonRegion ->
                        let
                            buttonCenter =
                                centerFromDisplayRegion fromImageButtonRegion
                        in
                        case getTextFromButtonCenter buttonCenter of
                            Err err ->
                                Err
                                    ("Failed for button at "
                                        ++ String.fromInt buttonCenter.x
                                        ++ ","
                                        ++ String.fromInt buttonCenter.y
                                        ++ ": "
                                        ++ err
                                    )

                            Ok labelText ->
                                Ok
                                    { region = fromImageButtonRegion
                                    , labelText = labelText
                                    }
                    )
                |> Result.Extra.combine


readButtonLabel : DisplayRegion -> { pixels_2x2 : ( Int, Int ) -> Maybe PixelValueRGB } -> List String
readButtonLabel region screenshot =
    let
        offsets_pixels =
            List.range region.x (region.x + region.width - 1)
                |> List.concatMap
                    (\offsetX ->
                        List.range region.y (region.y + region.height - 1)
                            |> List.map
                                (\offsetY ->
                                    \( x, y ) -> screenshot.pixels_2x2 ( x + offsetX, y + offsetY )
                                )
                    )
    in
    [ ( "OK", buttonLabelOK )
    , ( "Repair All", buttonLabelRepairAll )
    ]
        |> List.filter
            (\( _, labelPattern ) ->
                offsets_pixels |> List.any (\pixels_2x2 -> labelPattern { pixels_2x2 = pixels_2x2 })
            )
        |> List.map Tuple.first


buttonLabelOK : { pixels_2x2 : ( Int, Int ) -> Maybe PixelValueRGB } -> Bool
buttonLabelOK screenshot =
    let
        colorSum color =
            color.red + color.green + color.blue

        pixels_2x2_withDefault =
            screenshot.pixels_2x2 >> Maybe.withDefault { red = 0, green = 0, blue = 0 }

        colorSumFromOffset =
            pixels_2x2_withDefault >> colorSum

        edgeThreshold =
            50

        secondIsSignificantlyBrighter a b =
            colorSumFromOffset a + edgeThreshold < colorSumFromOffset b
    in
    secondIsSignificantlyBrighter ( -1, -1 ) ( -1, -2 )
        && secondIsSignificantlyBrighter ( -1, 1 ) ( -1, 2 )
        && secondIsSignificantlyBrighter ( -1, -1 ) ( -2, -1 )
        && secondIsSignificantlyBrighter ( -1, -1 ) ( 0, -1 )
        && secondIsSignificantlyBrighter ( -1, 1 ) ( -2, 1 )
        && secondIsSignificantlyBrighter ( -1, 1 ) ( 0, 1 )


buttonLabelRepairAll : { pixels_2x2 : ( Int, Int ) -> Maybe PixelValueRGB } -> Bool
buttonLabelRepairAll screenshot =
    let
        colorSum color =
            color.red + color.green + color.blue

        pixels_2x2_withDefault =
            screenshot.pixels_2x2 >> Maybe.withDefault { red = 0, green = 0, blue = 0 }

        colorSumFromOffset =
            pixels_2x2_withDefault >> colorSum

        edgeThreshold =
            50

        secondIsSignificantlyBrighter a b =
            colorSumFromOffset a + edgeThreshold < colorSumFromOffset b
    in
    secondIsSignificantlyBrighter ( -10, -1 ) ( -11, -1 )
        && secondIsSignificantlyBrighter ( -10, -1 ) ( -9, -1 )
        && secondIsSignificantlyBrighter ( 12, -1 ) ( 11, -1 )
        && secondIsSignificantlyBrighter ( 12, -1 ) ( 13, -1 )


centersOfTrueSequences : List Bool -> List Int
centersOfTrueSequences list =
    (list ++ [ False ])
        |> List.Extra.indexedFoldl
            (\index currentBool aggregate ->
                if currentBool then
                    if aggregate.trueStartIndex == Nothing then
                        { aggregate | trueStartIndex = Just index }

                    else
                        aggregate

                else
                    case aggregate.trueStartIndex of
                        Nothing ->
                            aggregate

                        Just trueStartIndex ->
                            { aggregate
                                | edges = aggregate.edges ++ [ (trueStartIndex + index) // 2 ]
                                , trueStartIndex = Nothing
                            }
            )
            { edges = [], trueStartIndex = Nothing }
        |> .edges


pairsFromList : List a -> ( List ( a, a ), Maybe a )
pairsFromList list =
    case list of
        [] ->
            ( [], Nothing )

        [ single ] ->
            ( [], Just single )

        first :: second :: remainder ->
            pairsFromList remainder |> Tuple.mapFirst ((::) ( first, second ))

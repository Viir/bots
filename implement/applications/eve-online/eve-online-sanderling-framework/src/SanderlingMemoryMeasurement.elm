module SanderlingMemoryMeasurement exposing
    ( InfoPanelRouteRouteElementMarker
    , MemoryMeasurementInfoPanelRoute
    , MemoryMeasurementMenu
    , MemoryMeasurementMenuEntry
    , MemoryMeasurementReducedWithNamedNodes
    , MemoryMeasurementShipUi
    , MemoryMeasurementShipUiIndication
    , PossiblyInvisible(..)
    , ShipManeuverType(..)
    , UIElement
    , UIElementRegion
    , maybeNothingFromCanNotSeeIt
    , parseInventoryCapacityGaugeText
    , parseInventoryDecoder
    , parseInventoryWindowCapacityGaugeDecoder
    , parseMemoryMeasurementReducedWithNamedNodesFromJson
    )

import Json.Decode
import Json.Decode.Extra
import Json.Encode
import Regex
import Result.Extra


type alias MemoryMeasurementReducedWithNamedNodes =
    { menus : List MemoryMeasurementMenu
    , shipUi : PossiblyInvisible MemoryMeasurementShipUi
    , infoPanelRoute : PossiblyInvisible MemoryMeasurementInfoPanelRoute
    , inventoryWindow : PossiblyInvisible InventoryWindow
    }


type alias MemoryMeasurementMenu =
    { uiElement : UIElement
    , entries : List MemoryMeasurementMenuEntry
    }


type alias MemoryMeasurementMenuEntry =
    { uiElement : UIElement
    , text : String
    }


type alias MemoryMeasurementInfoPanelRoute =
    { routeElementMarker : List InfoPanelRouteRouteElementMarker }


type alias InfoPanelRouteRouteElementMarker =
    { uiElement : UIElement }


type alias MemoryMeasurementShipUi =
    { indication : PossiblyInvisible MemoryMeasurementShipUiIndication }


type alias MemoryMeasurementShipUiIndication =
    { maneuverType : PossiblyInvisible ShipManeuverType }


type alias InventoryWindow =
    { leftTreeEntries : List InventoryWindowLeftTreeEntry
    , selectedContainedCapacityGauge : Maybe InventoryWindowCapacityGauge
    , selectedContainerInventory : Maybe Inventory
    }


type alias Inventory =
    { listViewItems : List UIElement
    }


type alias InventoryWindowLeftTreeEntry =
    { uiElement : UIElement
    , text : String
    }


type alias InventoryWindowCapacityGauge =
    { maximum : Int
    , used : Int
    }


type PossiblyInvisible feature
    = CanNotSeeIt
    | CanSee feature


type ShipManeuverType
    = Warp
    | Jump
    | Orbit
    | Approach


type alias UIElement =
    { id : Int
    , region : UIElementRegion
    }


type alias UIElementRegion =
    { left : Int
    , top : Int
    , right : Int
    , bottom : Int
    }


{-| Parse JSON string containing a Sanderling memory measurement.
The string expected here is not the raw measurement, but the stage which after parsing for named nodes.
To get a representation of the EVE Online clients memory contents as expected here, see the example at <https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs>
-}
parseMemoryMeasurementReducedWithNamedNodesFromJson : String -> Result String MemoryMeasurementReducedWithNamedNodes
parseMemoryMeasurementReducedWithNamedNodesFromJson =
    Json.Decode.decodeString memoryMeasurementReducedWithNamedNodesJsonDecoder
        >> Result.mapError Json.Decode.errorToString


memoryMeasurementReducedWithNamedNodesJsonDecoder : Json.Decode.Decoder MemoryMeasurementReducedWithNamedNodes
memoryMeasurementReducedWithNamedNodesJsonDecoder =
    Json.Decode.map4 MemoryMeasurementReducedWithNamedNodes
        -- TODO: Consider treating 'null' value like field is not present, to avoid breakage when server encodes fiels with 'null' values too.
        (Json.Decode.Extra.optionalField "Menu" (Json.Decode.list menuDecoder) |> Json.Decode.map (Maybe.withDefault []))
        (Json.Decode.Extra.optionalField "ShipUi" shipUIDecoder |> Json.Decode.map canNotSeeItFromMaybeNothing)
        (Json.Decode.Extra.optionalField "InfoPanelRoute" infoPanelRouteDecoder |> Json.Decode.map canNotSeeItFromMaybeNothing)
        (Json.Decode.Extra.optionalField "WindowInventory" (Json.Decode.list parseInventoryWindowDecoder) |> Json.Decode.map (Maybe.andThen List.head >> canNotSeeItFromMaybeNothing))


shipUIDecoder : Json.Decode.Decoder MemoryMeasurementShipUi
shipUIDecoder =
    Json.Decode.map MemoryMeasurementShipUi
        (Json.Decode.maybe
            (Json.Decode.field "Indication" shipUIIndicationDecoder)
            |> Json.Decode.map canNotSeeItFromMaybeNothing
        )


shipUIIndicationDecoder : Json.Decode.Decoder MemoryMeasurementShipUiIndication
shipUIIndicationDecoder =
    Json.Decode.value |> Json.Decode.map shipUIIndicationFromJsonValue


shipUIIndicationFromJsonValue : Json.Encode.Value -> MemoryMeasurementShipUiIndication
shipUIIndicationFromJsonValue jsonValue =
    let
        jsonString =
            Json.Encode.encode 0 jsonValue

        maneuverType =
            [ ( "Warp", Warp )
            , ( "Jump", Jump )
            , ( "Orbit", Orbit )
            , ( "Approach", Approach )
            ]
                |> List.filterMap
                    (\( pattern, candidateManeuverType ) ->
                        if jsonString |> String.contains pattern then
                            Just candidateManeuverType

                        else
                            Nothing
                    )
                |> List.head
                |> canNotSeeItFromMaybeNothing
    in
    { maneuverType = maneuverType }


infoPanelRouteDecoder : Json.Decode.Decoder MemoryMeasurementInfoPanelRoute
infoPanelRouteDecoder =
    Json.Decode.map MemoryMeasurementInfoPanelRoute
        (Json.Decode.maybe
            (Json.Decode.field "RouteElementMarker" (Json.Decode.list infoPanelRouteRouteElementMarkerDecoder))
            |> Json.Decode.map (Maybe.withDefault [])
        )


infoPanelRouteRouteElementMarkerDecoder : Json.Decode.Decoder InfoPanelRouteRouteElementMarker
infoPanelRouteRouteElementMarkerDecoder =
    uiElementDecoder
        |> Json.Decode.map (\uiElement -> { uiElement = uiElement })


uiElementDecoder : Json.Decode.Decoder UIElement
uiElementDecoder =
    Json.Decode.map2 UIElement
        (Json.Decode.field "Id" Json.Decode.int)
        (Json.Decode.field "Region" uiElementRegionDecoder)


uiElementRegionDecoder : Json.Decode.Decoder UIElementRegion
uiElementRegionDecoder =
    Json.Decode.map4 UIElementRegion
        (Json.Decode.field "Min0" Json.Decode.float |> Json.Decode.map round)
        (Json.Decode.field "Min1" Json.Decode.float |> Json.Decode.map round)
        (Json.Decode.field "Max0" Json.Decode.float |> Json.Decode.map round)
        (Json.Decode.field "Max1" Json.Decode.float |> Json.Decode.map round)


menuDecoder : Json.Decode.Decoder MemoryMeasurementMenu
menuDecoder =
    Json.Decode.map2 MemoryMeasurementMenu
        uiElementDecoder
        (Json.Decode.field "Entry" (Json.Decode.list menuEntryDecoder))


menuEntryDecoder : Json.Decode.Decoder MemoryMeasurementMenuEntry
menuEntryDecoder =
    Json.Decode.map2 MemoryMeasurementMenuEntry
        uiElementDecoder
        (Json.Decode.field "Text" Json.Decode.string)


parseInventoryWindowDecoder : Json.Decode.Decoder InventoryWindow
parseInventoryWindowDecoder =
    Json.Decode.map3 InventoryWindow
        (Json.Decode.field "LeftTreeListEntry" (Json.Decode.list parseInventoryWindowLeftTreeEntry))
        (Json.Decode.Extra.optionalField "SelectedRightInventoryCapacity" parseInventoryWindowCapacityGaugeDecoder)
        (Json.Decode.Extra.optionalField "SelectedRightInventory" parseInventoryDecoder)


parseInventoryWindowLeftTreeEntry : Json.Decode.Decoder InventoryWindowLeftTreeEntry
parseInventoryWindowLeftTreeEntry =
    Json.Decode.map2 InventoryWindowLeftTreeEntry
        uiElementDecoder
        (Json.Decode.field "Text" Json.Decode.string)


parseInventoryWindowCapacityGaugeDecoder : Json.Decode.Decoder InventoryWindowCapacityGauge
parseInventoryWindowCapacityGaugeDecoder =
    Json.Decode.field "Text" Json.Decode.string
        |> Json.Decode.andThen (Json.Decode.Extra.fromResult << parseInventoryCapacityGaugeText)


parseInventoryCapacityGaugeText : String -> Result String InventoryWindowCapacityGauge
parseInventoryCapacityGaugeText capacityText =
    {- Observed Example:
       "1,211.9/5,000.0 m³"
    -}
    let
        numbersParseResults =
            capacityText
                |> String.replace "m³" ""
                |> String.split "/"
                |> List.map (String.trim >> parseNumberTruncatingAfterDecimalSeparator)
    in
    case numbersParseResults |> Result.Extra.combine of
        Err parseError ->
            Err ("Failed to parse numbers: " ++ parseError)

        Ok numbers ->
            case numbers of
                [ leftNumber, rightNumber ] ->
                    Ok { used = leftNumber, maximum = rightNumber }

                _ ->
                    Err ("Unexpected number of components in capacityText '" ++ capacityText ++ "'")


parseNumberTruncatingAfterDecimalSeparator : String -> Result String Int
parseNumberTruncatingAfterDecimalSeparator numberDisplayText =
    case "^([\\d\\,]+)" |> Regex.fromString of
        Nothing ->
            Err "Regex code error"

        Just regex ->
            case numberDisplayText |> Regex.find regex |> List.head of
                Nothing ->
                    Err ("Text did not match expected number format: '" ++ numberDisplayText ++ "'")

                Just match ->
                    match.match
                        |> String.replace "," ""
                        |> String.toInt
                        |> Result.fromMaybe ("Failed to parse to integer: " ++ match.match)


parseInventoryDecoder : Json.Decode.Decoder Inventory
parseInventoryDecoder =
    Json.Decode.map Inventory
        (Json.Decode.field "ListView" (Json.Decode.field "Entry" (Json.Decode.list uiElementDecoder)))


canNotSeeItFromMaybeNothing : Maybe a -> PossiblyInvisible a
canNotSeeItFromMaybeNothing maybe =
    case maybe of
        Nothing ->
            CanNotSeeIt

        Just feature ->
            CanSee feature


maybeNothingFromCanNotSeeIt : PossiblyInvisible a -> Maybe a
maybeNothingFromCanNotSeeIt possiblyInvisible =
    case possiblyInvisible of
        CanNotSeeIt ->
            Nothing

        CanSee feature ->
            Just feature

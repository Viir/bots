{- Common functionality for EVE Online bots.
 -}


module Sanderling exposing
    ( InfoPanelRouteRouteElementMarker
    , MemoryMeasurement
    , MemoryMeasurementShipUi
    , ShipManeuverType(..)
    , UIElementRegion
    , centerFromRegion
    , elmEntryPoint
    , parseMemoryMeasurementFromJson
    )

import Json.Decode
import Json.Decode.Extra
import Json.Encode
import Sanderling_Interface_20190514


type alias MemoryMeasurement =
    { shipUi : Maybe MemoryMeasurementShipUi
    , infoPanelRoute : Maybe MemoryMeasurementInfoPanelRoute
    , menus : List MemoryMeasurementMenu
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
    { indication : Maybe MemoryMeasurementShipUiIndication }


type alias MemoryMeasurementShipUiIndication =
    { maneuverType : Maybe ShipManeuverType }


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
parseMemoryMeasurementFromJson : String -> Result String MemoryMeasurement
parseMemoryMeasurementFromJson =
    Json.Decode.decodeString memoryMeasurementReducedWithNamedNodesJsonDecoder
        >> Result.mapError Json.Decode.errorToString


memoryMeasurementReducedWithNamedNodesJsonDecoder : Json.Decode.Decoder MemoryMeasurement
memoryMeasurementReducedWithNamedNodesJsonDecoder =
    Json.Decode.map3 MemoryMeasurement
        -- TODO: Consider treating 'null' value like field is not present, to avoid breakage when server encodes fiels with 'null' values too.
        (Json.Decode.Extra.optionalField "ShipUi" shipUIDecoder)
        (Json.Decode.Extra.optionalField "InfoPanelRoute" infoPanelRouteDecoder)
        (Json.Decode.Extra.optionalField "Menu" (Json.Decode.list menuDecoder) |> Json.Decode.map (Maybe.withDefault []))


shipUIDecoder : Json.Decode.Decoder MemoryMeasurementShipUi
shipUIDecoder =
    Json.Decode.map MemoryMeasurementShipUi
        (Json.Decode.maybe
            (Json.Decode.field "Indication" shipUIIndicationDecoder)
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


centerFromRegion : UIElementRegion -> Sanderling_Interface_20190514.Location
centerFromRegion region =
    { x = (region.left + region.right) // 2, y = (region.top + region.bottom) // 2 }


{-| Support function-level dead code elimination (<https://elm-lang.org/blog/small-assets-without-the-headache>).
Elm code needed to inform the Elm compiler about our entry points.
-}
elmEntryPoint :
    ( botState, String )
    -> (String -> botState -> ( botState, String ))
    -> (botState -> String)
    -> (String -> botState)
    -> Program Int botState String
elmEntryPoint botInit botStepInterface serializeState deserializeState =
    Platform.worker
        { init = \_ -> ( botInit |> Tuple.first, Cmd.none )
        , update =
            \event stateBefore ->
                botStepInterface "" (stateBefore |> serializeState |> deserializeState) |> Tuple.mapSecond (always Cmd.none)
        , subscriptions = \_ -> Sub.none
        }

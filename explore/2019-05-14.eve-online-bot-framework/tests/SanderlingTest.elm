module SanderlingTest exposing (suite)

import Expect exposing (Expectation)
import Sanderling
import Test exposing (..)


suite : Test
suite =
    describe "Parse memory measurement"
        [ parseMemoryMeasurement_from_97DAA8E6F1_reduced_shipui_indication
        , parseMemoryMeasurement_from_97DAA8E6F1_reduced_infopanel_route_routeelementmarker
        , parseMemoryMeasurement_from_F8E7BF79FF_reduced_menu
        ]



-- For getting the serialized memory measurement, see https://github.com/Arcitectus/Sanderling/commit/4c848131cd3248a42a25c6b86536ac53eca7a4af


parseMemoryMeasurement_from_97DAA8E6F1_reduced_shipui_indication : Test
parseMemoryMeasurement_from_97DAA8E6F1_reduced_shipui_indication =
    test "Parse reduced derivation from  97DAA8E6F1 for Ship UI Indication" <|
        \_ ->
            """
{
    "ShipUi": {
        "Indication": {
            "LabelText": [
                {
                    "Text": "Warp Drive Active",
                    "Region": {
                        "Min0": 483,
                        "Min1": 499,
                        "Max0": 676,
                        "Max1": 524
                    },
                    "InTreeIndex": 574,
                    "Id": 796361168
                },
                {
                    "Text": "<center><center><center>Distance: 5,154 m to warp bubble collapse",
                    "Region": {
                        "Min0": 379,
                        "Min1": 524,
                        "Max0": 779,
                        "Max1": 540
                    },
                    "InTreeIndex": 575,
                    "Id": 786949328
                }
            ],
            "Region": {
                "Min0": 379,
                "Min1": 498,
                "Max0": 779,
                "Max1": 548
            },
            "InTreeIndex": 573,
            "ChildLastInTreeIndex": 575,
            "Id": 788539600
        }
    }
}
"""
                |> Sanderling.parseMemoryMeasurementFromJson
                |> Expect.equal
                    (Ok
                        { shipUi =
                            Just
                                { indication = Just { maneuverType = Just Sanderling.Warp }
                                }
                        , infoPanelRoute = Nothing
                        , menus = []
                        }
                    )


parseMemoryMeasurement_from_97DAA8E6F1_reduced_infopanel_route_routeelementmarker : Test
parseMemoryMeasurement_from_97DAA8E6F1_reduced_infopanel_route_routeelementmarker =
    test "Parse reduced derivation from 97DAA8E6F1 for Infopanel Route - route element marker" <|
        \_ ->
            """
{
    "InfoPanelRoute": {
        "RouteElementMarker": [
            {
                "Region": {
                    "Min0": 82,
                    "Min1": 267,
                    "Max0": 90,
                    "Max1": 275
                },
                "InTreeIndex": 373,
                "ChildLastInTreeIndex": 374,
                "Id": 788615728
            },
            {
                "Region": {
                    "Min0": 92,
                    "Min1": 267,
                    "Max0": 100,
                    "Max1": 275
                },
                "InTreeIndex": 371,
                "ChildLastInTreeIndex": 372,
                "Id": 788617872
            }
        ]
    }
}
"""
                |> Sanderling.parseMemoryMeasurementFromJson
                |> Expect.equal
                    (Ok
                        { shipUi = Nothing
                        , infoPanelRoute =
                            Just
                                { routeElementMarker =
                                    [ { uiElement =
                                            { id = 788615728, region = { left = 82, top = 267, right = 90, bottom = 275 } }
                                      }
                                    , { uiElement =
                                            { id = 788617872, region = { left = 92, top = 267, right = 100, bottom = 275 } }
                                      }
                                    ]
                                }
                        , menus = []
                        }
                    )


parseMemoryMeasurement_from_F8E7BF79FF_reduced_menu : Test
parseMemoryMeasurement_from_F8E7BF79FF_reduced_menu =
    test "Parse reduced derivation from F8E7BF79FF for menu" <|
        \_ ->
            """
{
    "Menu": [
        {
            "Entry": [
                {
                    "HighlightVisible": false,
                    "Text": "Warp to Within 0 m",
                    "LabelText": [
                        {
                            "Text": "Warp to Within 0 m",
                            "Region": {
                                "Min0": 942,
                                "Min1": 436,
                                "Max0": 1045,
                                "Max1": 449
                            },
                            "InTreeIndex": 1647,
                            "Id": 788245072
                        }
                    ],
                    "Region": {
                        "Min0": 934,
                        "Min1": 434,
                        "Max0": 1104,
                        "Max1": 449
                    },
                    "InTreeIndex": 1645,
                    "ChildLastInTreeIndex": 1648,
                    "Id": 787530576
                },
                {
                    "HighlightVisible": true,
                    "Text": "Warp to Within",
                    "LabelText": [
                        {
                            "Text": "Warp to Within",
                            "Region": {
                                "Min0": 942,
                                "Min1": 451,
                                "Max0": 1020,
                                "Max1": 464
                            },
                            "InTreeIndex": 1643,
                            "Id": 788183472
                        }
                    ],
                    "Sprite": [
                        {
                            "TexturePath": "res:/UI/Texture/Icons/1_16_14.png",
                            "Region": {
                                "Min0": 1088,
                                "Min1": 448,
                                "Max0": 1104,
                                "Max1": 465
                            },
                            "InTreeIndex": 1644,
                            "Id": 795038704
                        }
                    ],
                    "Region": {
                        "Min0": 934,
                        "Min1": 449,
                        "Max0": 1104,
                        "Max1": 464
                    },
                    "InTreeIndex": 1641,
                    "ChildLastInTreeIndex": 1644,
                    "Id": 791189040
                }
            ],
            "Region": {
                "Min0": 934,
                "Min1": 433,
                "Max0": 1104,
                "Max1": 552
            },
            "InTreeIndex": 1621,
            "ChildLastInTreeIndex": 1648,
            "Id": 792406864
        }
    ]
}
"""
                |> Sanderling.parseMemoryMeasurementFromJson
                |> Expect.equal
                    (Ok
                        { shipUi = Nothing
                        , infoPanelRoute = Nothing
                        , menus =
                            [ { uiElement = { id = 792406864, region = { left = 934, top = 433, right = 1104, bottom = 552 } }
                              , entries =
                                    [ { uiElement = { id = 787530576, region = { left = 934, top = 434, right = 1104, bottom = 449 } }
                                      , text = "Warp to Within 0 m"
                                      }
                                    , { uiElement = { id = 791189040, region = { left = 934, top = 449, right = 1104, bottom = 464 } }
                                      , text = "Warp to Within"
                                      }
                                    ]
                              }
                            ]
                        }
                    )

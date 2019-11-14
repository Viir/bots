module ParseSanderlingMemoryMeasurementTest exposing (allTests)

{-
   -- For getting the serialized memory measurement, see following sources:
   + https://github.com/Arcitectus/Sanderling/commit/4c848131cd3248a42a25c6b86536ac53eca7a4af
   + https://github.com/Viir/bots/commit/1950486ef8e0c8016b3a7f6c08a67ba0c403abc4
-}

import Expect
import Json.Decode
import Sanderling.SanderlingMemoryMeasurement as SanderlingMemoryMeasurement exposing (MaybeVisible(..))
import Test exposing (..)


parseMemoryMeasurementFromJson =
    SanderlingMemoryMeasurement.parseMemoryMeasurementReducedWithNamedNodesFromJson


allTests : Test
allTests =
    describe "Parse memory measurement"
        [ parseMemoryMeasurement_from_97DAA8E6F1_reduced_shipui_indication
        , ship_ui_module
        , ship_ui_ship_is_stopped
        , ship_ui_ship_is_not_stopped
        , target
        , parseMemoryMeasurement_from_97DAA8E6F1_reduced_infopanel_route_routeelementmarker
        , parseMemoryMeasurement_from_F8E7BF79FF_reduced_menu
        , from_measurement_root_inventoryWindow_with_left_tree
        , overview_window_entry
        , overview_entry_distance_text_to_meter
        , inventory_window_selected_container_capacity_gauge
        , inventory_containing_three_items
        , inventory_capacity_gauge_text
        ]


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
                |> parseMemoryMeasurementFromJson
                |> Result.map .shipUi
                |> Expect.equal
                    (Ok
                        (CanSee
                            { indication = CanSee { maneuverType = CanSee SanderlingMemoryMeasurement.Warp }
                            , modules = []
                            , shipIsStopped = Nothing
                            }
                        )
                    )


ship_ui_module : Test
ship_ui_module =
    test "Ship UI Module" <|
        \_ ->
            """
{
    "ModuleButtonVisible": true,
    "ModuleButtonIconTexture": {
        "Id": 876602232
    },
    "RampActive": true,
    "GlowVisible": true,
    "OverloadOn": false,
    "RegionInteraction": {
        "Region": {
            "Min0": 656,
            "Min1": 563,
            "Max0": 672,
            "Max1": 579
        },
        "InTreeIndex": 699,
        "ChildLastInTreeIndex": 715,
        "Id": 543723600
    },
    "Region": {
        "Min0": 632,
        "Min1": 539,
        "Max0": 696,
        "Max1": 603
    },
    "InTreeIndex": 699,
    "ChildLastInTreeIndex": 715,
    "Id": 543723600
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.shipUiModuleDecoder
                |> Expect.equal
                    (Ok
                        { uiElement = { id = 543723600, region = { left = 632, top = 539, right = 696, bottom = 603 } }
                        , isActive = Just True
                        }
                    )


ship_ui_ship_is_stopped : Test
ship_ui_ship_is_stopped =
    test "Ship UI ship is stopped" <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/a272acde3fd79bc834cf6e0f6ef0c41c82419c7d/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-7C3AE6AF.reduced-with-named-nodes.only-shipui.json
            """
{
    "SpeedLabel": {
        "Text": "0 m/s",
        "Region": {
            "Min0": 523,
            "Min1": 663,
            "Max0": 566,
            "Max1": 676
        },
        "InTreeIndex": 729,
        "Id": 777412336
    },
    "Region": {
        "Min0": 0,
        "Min1": 0,
        "Max0": 0,
        "Max1": 0
    },
    "Id": 0
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.shipUiDecoder
                |> Result.map .shipIsStopped
                |> Expect.equal (Ok (Just True))


ship_ui_ship_is_not_stopped : Test
ship_ui_ship_is_not_stopped =
    test "Ship UI ship is not stopped" <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/a272acde3fd79bc834cf6e0f6ef0c41c82419c7d/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-7C3AE6AF.reduced-with-named-nodes.only-shipui.json
            """
{
    "SpeedLabel": {
        "Text": "352 m/s",
        "Region": {
            "Min0": 523,
            "Min1": 663,
            "Max0": 566,
            "Max1": 676
        },
        "InTreeIndex": 729,
        "Id": 777412336
    },
    "Region": {
        "Min0": 0,
        "Min1": 0,
        "Max0": 0,
        "Max1": 0
    },
    "Id": 0
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.shipUiDecoder
                |> Result.map .shipIsStopped
                |> Expect.equal (Ok (Just False))


target : Test
target =
    test "Target" <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/a272acde3fd79bc834cf6e0f6ef0c41c82419c7d/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-7C3AE6AF.reduced-with-named-nodes.only-targets.json
            """
{
    "LabelText": [
        {
            "Text": "<center>Asteroid (Pyroxeres)",
            "Region": {
                "Min0": 545,
                "Min1": 100,
                "Max0": 655,
                "Max1": 113
            },
            "InTreeIndex": 804,
            "Id": 695619696
        },
        {
            "Text": "<center>3,871 m",
            "Region": {
                "Min0": 545,
                "Min1": 113,
                "Max0": 655,
                "Max1": 126
            },
            "InTreeIndex": 801,
            "Id": 800586256
        }
    ],
    "IsSelected": false,
    "Hitpoints": {},
    "RegionInteractionElement": {
        "Region": {
            "Min0": 562,
            "Min1": 15,
            "Max0": 639,
            "Max1": 85
        },
        "InTreeIndex": 805,
        "ChildLastInTreeIndex": 813,
        "Id": 796207728
    },
    "RegionInteraction": {
        "Region": {
            "Min0": 580,
            "Min1": 30,
            "Max0": 620,
            "Max1": 70
        },
        "InTreeIndex": 805,
        "ChildLastInTreeIndex": 813,
        "Id": 796207728
    },
    "Region": {
        "Min0": 545,
        "Min1": 0,
        "Max0": 655,
        "Max1": 181
    },
    "InTreeIndex": 797,
    "ChildLastInTreeIndex": 813,
    "Id": 568574960
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.targetDecoder
                |> Expect.equal
                    (Ok
                        { uiElement = { id = 568574960, region = { left = 545, top = 0, right = 655, bottom = 181 } }
                        , textsTopToBottom = [ "<center>Asteroid (Pyroxeres)", "<center>3,871 m" ]
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
                |> parseMemoryMeasurementFromJson
                |> Result.map .infoPanelRoute
                |> Expect.equal
                    (Ok
                        (CanSee
                            { routeElementMarker =
                                [ { uiElement =
                                        { id = 788615728, region = { left = 82, top = 267, right = 90, bottom = 275 } }
                                  }
                                , { uiElement =
                                        { id = 788617872, region = { left = 92, top = 267, right = 100, bottom = 275 } }
                                  }
                                ]
                            }
                        )
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
                |> parseMemoryMeasurementFromJson
                |> Result.map .contextMenus
                |> Expect.equal
                    (Ok
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
                    )


from_measurement_root_inventoryWindow_with_left_tree : Test
from_measurement_root_inventoryWindow_with_left_tree =
    test "Inventory window parsed from measurement root containing the left navigation tree." <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/479e1f9b870c1e0e00764e318eeda77938b95e81/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-D61A3AAC.reduced-with-named-nodes.only-inventory-window.json
            """
{
    "UserDefaultLocaleName": "en-AU",
    "ScreenSize": {
        "A": 1087,
        "B": 716
    },
    "WindowInventory": [
        {
            "LeftTreeListEntry": [
                {
                    "IsSelected": false,
                    "RegionInteraction": {
                        "Text": "Item hangar",
                        "Region": {
                            "Min0": 246,
                            "Min1": 560,
                            "Max0": 308,
                            "Max1": 576
                        },
                        "InTreeIndex": 404,
                        "Id": 569971312
                    },
                    "Text": "Item hangar",
                    "LabelText": [
                        {
                            "Text": "Item hangar",
                            "Region": {
                                "Min0": 246,
                                "Min1": 560,
                                "Max0": 308,
                                "Max1": 576
                            },
                            "InTreeIndex": 404,
                            "Id": 569971312
                        }
                    ],
                    "Region": {
                        "Min0": 204,
                        "Min1": 557,
                        "Max0": 360,
                        "Max1": 579
                    },
                    "InTreeIndex": 402,
                    "ChildLastInTreeIndex": 405,
                    "Id": 543915376
                },
                {
                    "Child": [
                        {
                            "IsSelected": true,
                            "RegionInteraction": {
                                "Text": "Ore Hold",
                                "Region": {
                                    "Min0": 256,
                                    "Min1": 484,
                                    "Max0": 301,
                                    "Max1": 500
                                },
                                "InTreeIndex": 423,
                                "Id": 798608016
                            },
                            "Text": "Ore Hold",
                            "LabelText": [
                                {
                                    "Text": "Ore Hold",
                                    "Region": {
                                        "Min0": 256,
                                        "Min1": 484,
                                        "Max0": 301,
                                        "Max1": 500
                                    },
                                    "InTreeIndex": 423,
                                    "Id": 798608016
                                }
                            ],
                            "Region": {
                                "Min0": 204,
                                "Min1": 481,
                                "Max0": 360,
                                "Max1": 503
                            },
                            "InTreeIndex": 421,
                            "ChildLastInTreeIndex": 424,
                            "Id": 794546320
                        },
                        {
                            "IsSelected": false,
                            "RegionInteraction": {
                                "Text": "Drone Bay",
                                "Region": {
                                    "Min0": 256,
                                    "Min1": 462,
                                    "Max0": 310,
                                    "Max1": 478
                                },
                                "InTreeIndex": 427,
                                "Id": 798609200
                            },
                            "Text": "Drone Bay",
                            "LabelText": [],
                            "Region": {
                                "Min0": 204,
                                "Min1": 459,
                                "Max0": 360,
                                "Max1": 481
                            },
                            "InTreeIndex": 425,
                            "ChildLastInTreeIndex": 428,
                            "Id": 798458512
                        }
                    ],
                    "IsSelected": false,
                    "RegionInteraction": {
                        "Text": "Ship Name (Venture)",
                        "Region": {
                            "Min0": 246,
                            "Min1": 440,
                            "Max0": 420,
                            "Max1": 456
                        },
                        "InTreeIndex": 432,
                        "Id": 710134384
                    },
                    "Text": "Ship Name (Venture)",
                    "LabelText": [],
                    "Region": {
                        "Min0": 204,
                        "Min1": 437,
                        "Max0": 360,
                        "Max1": 508
                    },
                    "InTreeIndex": 419,
                    "ChildLastInTreeIndex": 433,
                    "Id": 543353264
                }
            ],
            "Region": {
                "Min0": 200,
                "Min1": 393,
                "Max0": 732,
                "Max1": 668
            },
            "InTreeIndex": 277,
            "ChildLastInTreeIndex": 518,
            "Id": 568554320
        }
    ]
}
"""
                |> parseMemoryMeasurementFromJson
                |> Result.map .inventoryWindow
                |> Expect.equal
                    (Ok
                        (CanSee
                            { leftTreeEntries =
                                [ { text = "Item hangar", uiElement = { id = 543915376, region = { bottom = 579, left = 204, right = 360, top = 557 } } }
                                , { text = "Ship Name (Venture)", uiElement = { id = 543353264, region = { bottom = 508, left = 204, right = 360, top = 437 } } }
                                ]
                            , selectedContainedCapacityGauge = Nothing
                            , selectedContainerInventory = Nothing
                            }
                        )
                    )


overview_window_entry : Test
overview_window_entry =
    test "Overview window entry" <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/479e1f9b870c1e0e00764e318eeda77938b95e81/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-7C3AE6AF.reduced-with-named-nodes.only-overview-window.json
            """
{
    "MainIconSetIndicatorName": [
        "attackingMeIndicator"
    ],
    "ContentBoundLeft": 772,
    "IsGroup": false,
    "IsSelected": false,
    "ListBackgroundColor": [
        {
            "OMilli": 0,
            "RMilli": 250,
            "GMilli": 250,
            "BMilli": 250
        }
    ],
    "LabelText": [
        {
            "Text": "2,856 m",
            "Region": {
                "Min0": 826,
                "Min1": 162,
                "Max0": 868,
                "Max1": 178
            },
            "InTreeIndex": 1340,
            "Id": 569849648
        },
        {
            "Text": "Guristas Arrogator",
            "Region": {
                "Min0": 876,
                "Min1": 162,
                "Max0": 971,
                "Max1": 178
            },
            "InTreeIndex": 1341,
            "Id": 569851408
        },
        {
            "Text": "Guristas Arrogator",
            "Region": {
                "Min0": 988,
                "Min1": 162,
                "Max0": 1083,
                "Max1": 178
            },
            "InTreeIndex": 1342,
            "Id": 569847856
        }
    ],
    "Region": {
        "Min0": 770,
        "Min1": 160,
        "Max0": 1059,
        "Max1": 179
    },
    "InTreeIndex": 1336,
    "ChildLastInTreeIndex": 1342,
    "Id": 793528816
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.parseOverviewWindowListViewEntryDecoder
                |> Expect.equal
                    (Ok
                        { uiElement = { id = 793528816, region = { left = 770, top = 160, right = 1059, bottom = 179 } }
                        , textsLeftToRight = [ "2,856 m", "Guristas Arrogator", "Guristas Arrogator" ]
                        , distanceInMeters = Ok 2856
                        }
                    )


overview_entry_distance_text_to_meter : Test
overview_entry_distance_text_to_meter =
    [ ( "2,856 m", Ok 2856 )
    , ( "123 m", Ok 123 )
    , ( "16 km", Ok 16000 )
    , ( "   345 m  ", Ok 345 )
    ]
        |> List.map
            (\( displayText, expectedResult ) ->
                test displayText <|
                    \_ ->
                        displayText
                            |> SanderlingMemoryMeasurement.parseOverviewEntryDistanceInMetersFromText
                            |> Expect.equal expectedResult
            )
        |> describe "Overview entry distance text"


inventory_window_selected_container_capacity_gauge : Test
inventory_window_selected_container_capacity_gauge =
    test "Inventory window capacity gauge" <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/479e1f9b870c1e0e00764e318eeda77938b95e81/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-D61A3AAC.reduced-with-named-nodes.only-inventory-window.json
            """
{
    "Text": "1,211.9/5,000.0 m³",
    "Region": {
        "Min0": 438,
        "Min1": 442,
        "Max0": 533,
        "Max1": 455
    },
    "InTreeIndex": 357,
    "Id": 777335312
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.parseInventoryWindowCapacityGaugeDecoder
                |> Expect.equal
                    (Ok { used = 1211, maximum = 5000 })


inventory_capacity_gauge_text : Test
inventory_capacity_gauge_text =
    [ ( "1,211.9/5,000.0 m³", Ok { used = 1211, maximum = 5000 } )
    , ( " 123.4 / 5,000.0 m³ ", Ok { used = 123, maximum = 5000 } )

    -- Example from https://forum.botengine.org/t/standard-mining-bot-problems/2715/14?u=viir
    , ( "4 999,8/5 000,0 m³", Ok { used = 4999, maximum = 5000 } )
    ]
        |> List.map
            (\( text, expectedResult ) ->
                test text <|
                    \_ ->
                        text
                            |> SanderlingMemoryMeasurement.parseInventoryCapacityGaugeText
                            |> Expect.equal expectedResult
            )
        |> describe "Inventory capacity gauge text"


inventory_containing_three_items : Test
inventory_containing_three_items =
    test "Inventory containing three items." <|
        \_ ->
            -- Sample from https://github.com/Viir/bots/blob/479e1f9b870c1e0e00764e318eeda77938b95e81/implement/applications/eve-online/training-data/2019-10-12.eve-online-mining/2019-10-12.from-D61A3AAC.reduced-with-named-nodes.only-inventory-window.json
            """
{
    "ListView": {
        "Entry": [
            {
                "ContentBoundLeft": 377,
                "IsGroup": false,
                "IsSelected": false,
                "LabelText": [
                    {
                        "Text": "Massive Scordite<t><right>598<t>Scordite<t><t><t><right>89.70 m3<t><right>11,954.02 ISK",
                        "Region": {
                            "Min0": 377,
                            "Min1": 480,
                            "Max0": 1464,
                            "Max1": 496
                        },
                        "InTreeIndex": 303,
                        "Id": 569850992
                    }
                ],
                "Region": {
                    "Min0": 365,
                    "Min1": 477,
                    "Max0": 727,
                    "Max1": 498
                },
                "InTreeIndex": 301,
                "ChildLastInTreeIndex": 303,
                "Id": 697598480
            },
            {
                "ContentBoundLeft": 377,
                "IsGroup": false,
                "IsSelected": false,
                "LabelText": [
                    {
                        "Text": "Scordite<t><right>6,649<t>Scordite<t><t><t><right>997.35 m3<t><right>122,075.64 ISK",
                        "Region": {
                            "Min0": 377,
                            "Min1": 501,
                            "Max0": 1464,
                            "Max1": 517
                        },
                        "InTreeIndex": 300,
                        "Id": 569851120
                    }
                ],
                "Region": {
                    "Min0": 365,
                    "Min1": 498,
                    "Max0": 727,
                    "Max1": 519
                },
                "InTreeIndex": 298,
                "ChildLastInTreeIndex": 300,
                "Id": 569849616
            },
            {
                "ContentBoundLeft": 377,
                "IsGroup": false,
                "IsSelected": false,
                "LabelText": [
                    {
                        "Text": "Solid Pyroxeres<t><right>416<t>Pyroxeres<t><t><t><right>124.80 m3<t><right>17,343.04 ISK",
                        "Region": {
                            "Min0": 377,
                            "Min1": 522,
                            "Max0": 1464,
                            "Max1": 538
                        },
                        "InTreeIndex": 297,
                        "Id": 569851152
                    }
                ],
                "Region": {
                    "Min0": 365,
                    "Min1": 519,
                    "Max0": 727,
                    "Max1": 540
                },
                "InTreeIndex": 295,
                "ChildLastInTreeIndex": 297,
                "Id": 569851632
            }
        ],
        "Region": {
            "Min0": 364,
            "Min1": 460,
            "Max0": 728,
            "Max1": 628
        },
        "InTreeIndex": 283,
        "ChildLastInTreeIndex": 342,
        "Id": 699561072
    }
}
"""
                |> Json.Decode.decodeString SanderlingMemoryMeasurement.parseInventoryDecoder
                |> Expect.equal
                    (Ok
                        { listViewItems =
                            [ { id = 697598480, region = { bottom = 498, left = 365, right = 727, top = 477 } }
                            , { id = 569849616, region = { bottom = 519, left = 365, right = 727, top = 498 } }
                            , { id = 569851632, region = { bottom = 540, left = 365, right = 727, top = 519 } }
                            ]
                        }
                    )

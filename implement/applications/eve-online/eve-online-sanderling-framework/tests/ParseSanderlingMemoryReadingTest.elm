module ParseSanderlingMemoryReadingTest exposing (allTests)

import Expect
import Sanderling.MemoryReading exposing (MaybeVisible(..))
import Test exposing (..)


allTests : Test
allTests =
    describe "Parse memory reading"
        [ overview_entry_distance_text_to_meter
        , inventory_capacity_gauge_text
        ]


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
                            |> Sanderling.MemoryReading.parseOverviewEntryDistanceInMetersFromText
                            |> Expect.equal expectedResult
            )
        |> describe "Overview entry distance text"


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
                            |> Sanderling.MemoryReading.parseInventoryCapacityGaugeText
                            |> Expect.equal expectedResult
            )
        |> describe "Inventory capacity gauge text"

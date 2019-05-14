module SanderlingInterfaceTest exposing (suite)

import Expect exposing (Expectation)
import Sanderling_Interface_20190514
import Test exposing (..)


suite : Test
suite =
    describe "Interface between host and bot."
        [ botEventMemoryMeasurementCompleted
        ]


botEventMemoryMeasurementCompleted : Test
botEventMemoryMeasurementCompleted =
    test "Bot event for memory measurement completed." <|
        \_ ->
            """
{
    "timeInMilliseconds" : 1234,
    "event": {
        "memoryMeasurementFinished" : {
            "ok" : {
                "reducedWithNamedNodesJson" : "json content"
            }
        }
    }
}
"""
                |> Sanderling_Interface_20190514.deserializeBotEventAtTime
                |> Expect.equal
                    (Ok
                        { timeInMilliseconds = 1234
                        , event =
                            Sanderling_Interface_20190514.MemoryMeasurementFinished
                                (Ok { reducedWithNamedNodesJson = Just "json content" })
                        }
                    )

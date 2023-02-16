module BotFrameworkTest exposing (..)

import EveOnline.BotFramework
import Expect
import Test


test_closestPointOnRectangleEdge : Test.Test
test_closestPointOnRectangleEdge =
    [ { input =
            { rectangle = { left = 100, top = 10, right = 200, bottom = 30 }
            , point = { x = 0, y = 0 }
            }
      , expected = { x = 100, y = 10 }
      }
    , { input =
            { rectangle = { left = 100, top = 10, right = 200, bottom = 30 }
            , point = { x = 130, y = 13 }
            }
      , expected = { x = 130, y = 10 }
      }
    , { input =
            { rectangle = { left = 100, top = 10, right = 200, bottom = 30 }
            , point = { x = 135, y = 21 }
            }
      , expected = { x = 135, y = 30 }
      }
    , { input =
            { rectangle = { left = 100, top = 10, right = 200, bottom = 30 }
            , point = { x = 103, y = 21 }
            }
      , expected = { x = 100, y = 21 }
      }
    , { input =
            { rectangle = { left = 100, top = 10, right = 200, bottom = 30 }
            , point = { x = 198, y = 23 }
            }
      , expected = { x = 200, y = 23 }
      }
    ]
        |> List.indexedMap
            (\i testCase ->
                Test.test ("Scenario " ++ String.fromInt i) <|
                    \_ ->
                        let
                            frameworkRect =
                                { x = testCase.input.rectangle.left
                                , y = testCase.input.rectangle.top
                                , width = testCase.input.rectangle.right - testCase.input.rectangle.left
                                , height = testCase.input.rectangle.bottom - testCase.input.rectangle.top
                                }

                            closestPoint =
                                EveOnline.BotFramework.closestPointOnRectangleEdge frameworkRect testCase.input.point
                        in
                        closestPoint
                            |> Expect.equal testCase.expected
            )
        |> Test.describe "closest point on rectangle edge"

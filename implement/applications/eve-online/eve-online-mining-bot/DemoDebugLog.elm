module DemoDebugLog exposing (..)

import BotEngineApp
import Dict
import EveOnline.MemoryReading
import EveOnline.ParseUserInterface
import Html
import Html.Attributes
import Json.Encode
import Set


main : Html.Html e
main =
    exampleOverviewEntries
        |> List.map
            (\overviewEntry ->
                let
                    resultRecord =
                        Debug.log "result for overview entry"
                            { overviewEntry = overviewEntry
                            , representsAsteroid = BotEngineApp.overviewWindowEntryRepresentsAnAsteroid overviewEntry
                            }
                in
                [ Html.text
                    ("representsAsteroid: "
                        ++ (if resultRecord.representsAsteroid then
                                "True"

                            else
                                "False"
                           )
                    )
                ]
                    |> Html.div []
            )
        |> Html.div [ Html.Attributes.style "color" "whitesmoke" ]


exampleOverviewEntries : List EveOnline.ParseUserInterface.OverviewWindowEntry
exampleOverviewEntries =
    [ { uiNode = minimalUiNodeWithDisplayRegion
      , textsLeftToRight = [ "Some asteroid", "Veldspar", "12345 m" ]
      , cellsTexts = Dict.empty
      , objectDistance = Just "12345 m"
      , objectDistanceInMeters = Ok 12345
      , objectName = Just "Some asteroid"
      , objectType = Just "Veldspar"
      , objectAlliance = Nothing
      , iconSpriteColorPercent = Nothing
      , namesUnderSpaceObjectIcon = Set.empty
      , bgColorFillsPercent = []
      , rightAlignedIconsHints = []
      , commonIndications =
            { targeting = False
            , targetedByMe = False
            , isJammingMe = False
            , isWarpDisruptingMe = False
            }
      }
    , { uiNode = minimalUiNodeWithDisplayRegion
      , textsLeftToRight = [ "Pilot Name", "Ship Type", "12345 m" ]
      , cellsTexts = Dict.empty
      , objectDistance = Just "12345 m"
      , objectDistanceInMeters = Ok 12345
      , objectName = Just "Pilot Name"
      , objectType = Just "Ship Type"
      , objectAlliance = Nothing
      , iconSpriteColorPercent = Nothing
      , namesUnderSpaceObjectIcon = Set.empty
      , bgColorFillsPercent = []
      , rightAlignedIconsHints = []
      , commonIndications =
            { targeting = False
            , targetedByMe = False
            , isJammingMe = False
            , isWarpDisruptingMe = False
            }
      }
    ]


minimalUiNodeWithDisplayRegion : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
minimalUiNodeWithDisplayRegion =
    { uiNode = fakeUiNode
    , children = Nothing
    , selfDisplayRegion = zeroDisplayRegion
    , totalDisplayRegion = zeroDisplayRegion
    }


zeroDisplayRegion : EveOnline.ParseUserInterface.DisplayRegion
zeroDisplayRegion =
    { x = 0
    , y = 0
    , width = 0
    , height = 0
    }


fakeUiNode : EveOnline.MemoryReading.UITreeNode
fakeUiNode =
    { originalJson = Json.Encode.object []
    , pythonObjectAddress = "123456789"
    , pythonObjectTypeName = "fake-type"
    , dictEntriesOfInterest = Dict.empty
    , children = Nothing
    }

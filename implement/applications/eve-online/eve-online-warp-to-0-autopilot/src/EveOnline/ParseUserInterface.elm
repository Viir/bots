module EveOnline.ParseUserInterface exposing
    ( ShipUIModulesGroupedIntoRows
    , groupShipUIModulesIntoRows
    )

import EveOnline.MemoryReading exposing (ShipUIModule)


type alias ShipUIModulesGroupedIntoRows =
    { top : List ShipUIModule
    , middle : List ShipUIModule
    , bottom : List ShipUIModule
    }


groupShipUIModulesIntoRows : EveOnline.MemoryReading.ShipUI -> Maybe ShipUIModulesGroupedIntoRows
groupShipUIModulesIntoRows shipUI =
    let
        maybeCapacitorUINode =
            shipUI.uiNode
                |> EveOnline.MemoryReading.listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "CapacitorContainer")
                |> List.head
    in
    maybeCapacitorUINode
        |> Maybe.map
            (\capacitorUINode ->
                let
                    verticalDistanceThreshold =
                        20

                    verticalCenterOfUINode uiNode =
                        uiNode.totalDisplayRegion.y + uiNode.totalDisplayRegion.height // 2

                    capacitorVerticalCenter =
                        verticalCenterOfUINode capacitorUINode
                in
                shipUI.modules
                    |> List.foldr
                        (\shipModule previousRows ->
                            if verticalCenterOfUINode shipModule.uiNode < capacitorVerticalCenter - verticalDistanceThreshold then
                                { previousRows | top = shipModule :: previousRows.top }

                            else if verticalCenterOfUINode shipModule.uiNode > capacitorVerticalCenter + verticalDistanceThreshold then
                                { previousRows | bottom = shipModule :: previousRows.bottom }

                            else
                                { previousRows | middle = shipModule :: previousRows.middle }
                        )
                        { top = [], middle = [], bottom = [] }
            )

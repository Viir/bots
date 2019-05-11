module SimplifiedSanderling exposing
    ( BotEffect(..)
    , BotEvent(..)
    , BotEventAtTime
    , BotRequest(..)
    , InfoPanelRouteRouteElementMarker
    , MemoryMeasurement
    , MouseButtonType(..)
    , ShipManeuverType(..)
    , centerFromRegion
    , mouseClickAtLocation
    )


type alias BotEventAtTime =
    { timeInMilliseconds : Int
    , event : BotEvent
    }


type BotEvent
    = MemoryMeasurementCompleted MemoryMeasurement


type BotRequest
    = TakeMemoryMeasurementAtTime Int
    | ReportStatus String
    | Effect BotEffect


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


type alias UIElement =
    { id : Int
    , region : UIElementRegion
    }


type BotEffect
    = SimpleEffect SimpleBotEffect


type SimpleBotEffect
    = SimpleMouseClickAtLocation Location MouseButtonType


type MouseButtonType
    = MouseButtonLeft
    | MouseButtonRight


type alias Location =
    { x : Int, y : Int }


type alias UIElementRegion =
    { left : Int
    , top : Int
    , width : Int
    , height : Int
    }


type alias MemoryMeasurementShipUi =
    { indication : Maybe MemoryMeasurementShipUiIndication }


type alias MemoryMeasurementShipUiIndication =
    { maneuverType : Maybe ShipManeuverType }


type ShipManeuverType
    = Warp
    | Jump
    | Orbit
    | Approach


mouseClickAtLocation : Location -> MouseButtonType -> BotEffect
mouseClickAtLocation location mouseButtonType =
    SimpleMouseClickAtLocation location mouseButtonType |> SimpleEffect


centerFromRegion : UIElementRegion -> Location
centerFromRegion region =
    { x = region.left + region.width // 2, y = region.height // 2 }

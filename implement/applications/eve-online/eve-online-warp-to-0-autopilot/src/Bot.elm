{- This is a warp to 0km auto-pilot, making your travels faster and thus safer by directly warping to gates/stations.
   The bot follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.
   Before starting the bot, set the in-game autopilot route and make sure the autopilot is expanded, so that the route is visible.
   Make sure you are undocked before starting the bot because the bot does not undock.

   bot-catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import Sanderling.Sanderling as Sanderling exposing (MouseButton(..), centerFromRegion, effectMouseClickAtLocation)
import Sanderling.SanderlingMemoryMeasurement as SanderlingMemoryMeasurement
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , ShipUi
        , maybeNothingFromCanNotSeeIt
        )
import Sanderling.SimpleSanderling as SimpleSanderling exposing (BotEventAtTime, BotRequest(..))


type alias MemoryMeasurement =
    SanderlingMemoryMeasurement.MemoryMeasurementReducedWithNamedNodes


{-| The autopilot bot does not need to remember anything from the past; the information on the game client screen is sufficient to decide what to do next.
Therefore we need no state and use an empty tuple '()' to define the type of the state.
-}
type alias SimpleState =
    ()


type alias State =
    SimpleSanderling.StateIncludingSetup SimpleState


initState : State
initState =
    SimpleSanderling.initState ()


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleSanderling.processEvent simpleProcessEvent


simpleProcessEvent : BotEventAtTime -> SimpleState -> { newState : SimpleState, requests : List BotRequest, statusMessage : String }
simpleProcessEvent eventAtTime stateBefore =
    case eventAtTime.event of
        SimpleSanderling.MemoryMeasurementCompleted memoryMeasurement ->
            let
                ( requests, statusMessage ) =
                    botRequestsFromGameClientState memoryMeasurement
            in
            { newState = stateBefore
            , requests = requests
            , statusMessage = statusMessage
            }

        SimpleSanderling.SetBotConfiguration botConfiguration ->
            { newState = stateBefore
            , requests = []
            , statusMessage =
                if botConfiguration |> String.isEmpty then
                    ""

                else
                    "I have a problem with this configuration: I am not programmed to support configuration at all. Maybe the bot catalog (https://to.botengine.org/bot-catalog) has a bot which better matches your use case?"
            }


botRequestsFromGameClientState : MemoryMeasurement -> ( List BotRequest, String )
botRequestsFromGameClientState memoryMeasurement =
    case memoryMeasurement |> infoPanelRouteFirstMarkerFromMemoryMeasurement of
        Nothing ->
            ( [ TakeMemoryMeasurementAfterDelayInMilliseconds 4000 ]
            , "I see no route in the info panel. I will start when a route is set."
            )

        Just infoPanelRouteFirstMarker ->
            case memoryMeasurement.shipUi of
                CanNotSeeIt ->
                    ( [ TakeMemoryMeasurementAfterDelayInMilliseconds 4000 ]
                    , "I cannot see if the ship is warping or jumping. I wait for the ship UI to appear on the screen."
                    )

                CanSee shipUi ->
                    if shipUi |> isShipWarpingOrJumping then
                        ( [ TakeMemoryMeasurementAfterDelayInMilliseconds 4000 ]
                        , "I see the ship is warping or jumping. I wait until that maneuver ends."
                        )

                    else
                        let
                            ( requests, statusMessage ) =
                                botRequestsWhenNotWaitingForShipManeuver
                                    memoryMeasurement
                                    infoPanelRouteFirstMarker
                        in
                        ( requests ++ [ TakeMemoryMeasurementAfterDelayInMilliseconds 2000 ], statusMessage )


botRequestsWhenNotWaitingForShipManeuver :
    MemoryMeasurement
    -> InfoPanelRouteRouteElementMarker
    -> ( List BotRequest, String )
botRequestsWhenNotWaitingForShipManeuver memoryMeasurement infoPanelRouteFirstMarker =
    let
        openMenuAnnouncementAndEffect =
            ( [ EffectOnGameClientWindow
                    (effectMouseClickAtLocation
                        Sanderling.MouseButtonRight
                        (infoPanelRouteFirstMarker.uiElement.region |> centerFromRegion)
                    )
              ]
            , "I click on the route marker in the info panel to open the menu."
            )
    in
    case memoryMeasurement.contextMenus |> List.head of
        Nothing ->
            openMenuAnnouncementAndEffect

        Just firstMenu ->
            let
                maybeMenuEntryToClick =
                    firstMenu.entries
                        |> List.filter
                            (\menuEntry ->
                                let
                                    textLowercase =
                                        menuEntry.text |> String.toLower
                                in
                                (textLowercase |> String.contains "dock")
                                    || (textLowercase |> String.contains "jump")
                            )
                        |> List.head
            in
            case maybeMenuEntryToClick of
                Nothing ->
                    openMenuAnnouncementAndEffect

                Just menuEntryToClick ->
                    ( [ EffectOnGameClientWindow (effectMouseClickAtLocation MouseButtonLeft (menuEntryToClick.uiElement.region |> centerFromRegion)) ]
                    , "I click on the menu entry '" ++ menuEntryToClick.text ++ "' to start the next ship maneuver."
                    )


infoPanelRouteFirstMarkerFromMemoryMeasurement : MemoryMeasurement -> Maybe InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromMemoryMeasurement =
    .infoPanelRoute
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiElement.region.left + routeMarker.uiElement.region.top))
        >> Maybe.andThen List.head


isShipWarpingOrJumping : ShipUi -> Bool
isShipWarpingOrJumping =
    .indication
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map
            (\maneuverType ->
                [ SanderlingMemoryMeasurement.Warp, SanderlingMemoryMeasurement.Jump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False

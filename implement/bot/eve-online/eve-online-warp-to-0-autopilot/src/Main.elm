{- This is a warp to 0km auto-pilot, making your travels faster and thus safer by directly warping to gates/stations.
   The bot follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.
   Before starting the bot, set the in-game autopilot route and make sure the autopilot is expanded, so that the route is visible.
   Make sure you are undocked before starting the bot because the bot does not undock.

   bot-catalog-tags:eve-online,auto-pilot,travel
-}


module Main exposing
    ( InterfaceBotState
    , State
    , interfaceToHost_deserializeState
    , interfaceToHost_initState
    , interfaceToHost_processEvent
    , interfaceToHost_serializeState
    , main
    )

import Bot_Interface_To_Host_20190720 as InterfaceToHost
import Sanderling exposing (MouseButton(..), centerFromRegion, effectMouseClickAtLocation)
import SanderlingMemoryMeasurement exposing (InfoPanelRouteRouteElementMarker, MemoryMeasurementShipUi)
import SimpleSanderling exposing (BotEventAtTime, BotRequest(..))


type alias MemoryMeasurement =
    SanderlingMemoryMeasurement.MemoryMeasurementReducedWithNamedNodes


{-| The autopilot bot does not need to remember anything from the past; the information on the game client screen is sufficient to decide what to do next.
Therefore we need no state and use an empty tuple '()' to define the type of the state.
-}
type alias State =
    ()


initState : State
initState =
    ()


processEvent : BotEventAtTime -> State -> { newState : State, requests : List BotRequest, statusMessage : String }
processEvent eventAtTime stateBefore =
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
                Nothing ->
                    ( [ TakeMemoryMeasurementAfterDelayInMilliseconds 4000 ]
                    , "I cannot see if the ship is warping or jumping. I wait for the ship UI to appear on the screen."
                    )

                Just shipUi ->
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
                        (infoPanelRouteFirstMarker.uiElement.region |> centerFromRegion)
                        Sanderling.MouseButtonRight
                    )
              ]
            , "I click on the route marker in the info panel to open the menu."
            )
    in
    case memoryMeasurement.menus |> List.head of
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
                    ( [ EffectOnGameClientWindow (effectMouseClickAtLocation (menuEntryToClick.uiElement.region |> centerFromRegion) MouseButtonLeft) ]
                    , "I click on the menu entry '" ++ menuEntryToClick.text ++ "' to start the next ship maneuver."
                    )


infoPanelRouteFirstMarkerFromMemoryMeasurement : MemoryMeasurement -> Maybe InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromMemoryMeasurement =
    .infoPanelRoute
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiElement.region.left + routeMarker.uiElement.region.top))
        >> Maybe.andThen List.head


isShipWarpingOrJumping : MemoryMeasurementShipUi -> Bool
isShipWarpingOrJumping =
    .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map
            (\maneuverType ->
                [ SanderlingMemoryMeasurement.Warp, SanderlingMemoryMeasurement.Jump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


type alias InterfaceBotState =
    SimpleSanderling.StateIncludingSetup State


interfaceToHost_initState : InterfaceBotState
interfaceToHost_initState =
    SimpleSanderling.initState initState


interfaceToHost_processEvent : String -> InterfaceBotState -> ( InterfaceBotState, String )
interfaceToHost_processEvent =
    InterfaceToHost.wrapForSerialInterface_processEvent (SimpleSanderling.processEvent processEvent)


interfaceToHost_serializeState : InterfaceBotState -> String
interfaceToHost_serializeState =
    always ""


interfaceToHost_deserializeState : String -> InterfaceBotState
interfaceToHost_deserializeState =
    always interfaceToHost_initState


{-| Define the Elm entry point. Don't change this function.
-}
main : Program Int InterfaceBotState String
main =
    InterfaceToHost.elmEntryPoint interfaceToHost_initState interfaceToHost_processEvent interfaceToHost_serializeState (interfaceToHost_deserializeState >> always interfaceToHost_initState)

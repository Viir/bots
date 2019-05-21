{- This is a warp to 0km auto-pilot, making your travels faster and thus safer by directly warping to gates/stations.
   The bot follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.
   Before starting the bot, set the in-game autopilot route and make sure the autopilot is expanded, so that the route is visible.
   Make sure you are undocked before starting the bot because the bot does not undock.

   bot-catalog-tags:eve-online,auto-pilot,travel
-}


module Main exposing
    ( InterfaceBotState
    , State
    , botStepInterface
    , deserializeState
    , initInterface
    , main
    , serializeState
    )

import Bot_Interface_To_Host_20190521 as InterfaceToHost
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


init : ( State, List BotRequest )
init =
    ( initState, [] )


botStep : BotEventAtTime -> State -> { newState : State, requests : List BotRequest, statusMessage : String }
botStep eventAtTime stateBefore =
    case eventAtTime.event of
        SimpleSanderling.MemoryMeasurementCompleted memoryMeasurement ->
            let
                ( requests, statusMessage ) =
                    botRequestsFromGameClientState memoryMeasurement
            in
            { newState = initState
            , requests = requests
            , statusMessage = statusMessage
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


{-| Define interface function for the framework. Don't change the function signature.
<https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.Common/PersistentProcess.cs>
-}
serializeState : InterfaceBotState -> String
serializeState =
    always ""


{-| Define interface function for the framework. Don't change the function signature.
<https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.Common/PersistentProcess.cs>
-}
deserializeState : String -> InterfaceBotState
deserializeState =
    always (initInterface |> Tuple.first)


{-| Define interface function for the framework. Don't change this.
-}
initInterface : ( InterfaceBotState, String )
initInterface =
    InterfaceToHost.wrapInitForSerialInterface (SimpleSanderling.init init)


{-| Define interface function for the framework. Don't change this.
Temporary helper as long as the framework does not support the `initInterface`.
This function can be removed when the engine supports `initInterface`. (<https://github.com/Viir/Kalmit/issues/5>)
-}
initStateInterface : InterfaceBotState
initStateInterface =
    initInterface |> Tuple.first


{-| Define interface function for the framework. Don't change this.
-}
botStepInterface : String -> InterfaceBotState -> ( InterfaceBotState, String )
botStepInterface =
    InterfaceToHost.wrapBotStepForSerialInterface (SimpleSanderling.botStep botStep)


{-| Define the Elm entry point. Don't change this function.
-}
main : Program Int InterfaceBotState String
main =
    InterfaceToHost.elmEntryPoint initInterface botStepInterface serializeState (deserializeState >> always initStateInterface)

module Main exposing (botStep)

{-| This is a warp to 0km auto-pilot, making your travels faster and thus safer by directly warping to gates/stations.
The bot follows the route set in the in-game autopilot and uses the context menu to initiate warp and dock commands.
To use the bot, set the in-game autopilot route before starting the bot.
Make sure you are undocked before starting the bot because the bot does not undock.
-}

import SimplifiedSanderling
    exposing
        ( BotEvent(..)
        , BotEventAtTime
        , BotRequest(..)
        , InfoPanelRouteRouteElementMarker
        , MemoryMeasurement
        , MouseButtonType(..)
        , centerFromRegion
        , mouseClickAtLocation
        )



-- This implementation is modeled after the script from https://github.com/Arcitectus/Sanderling/blob/5cdd9f42759b40dc9f39084ec91beac70aef4134/src/Sanderling/Sanderling.Exe/sample/script/beginners-autopilot.cs


{-| We need no state for the autopilot bot
-}
type alias State =
    ()


init : ( State, List BotRequest )
init =
    ( initialState, [] )


initialState : State
initialState =
    ()


botStep : BotEventAtTime -> State -> ( State, List BotRequest )
botStep eventAtTime stateBefore =
    case eventAtTime.event of
        MemoryMeasurementCompleted memoryMeasurement ->
            ( initialState, botRequests ( eventAtTime.timeInMilliseconds, memoryMeasurement ) )


botRequests : ( Int, MemoryMeasurement ) -> List BotRequest
botRequests ( currentTimeInMilliseconds, memoryMeasurement ) =
    case memoryMeasurement |> infoPanelRouteFirstMarkerFromMemoryMeasurement of
        Nothing ->
            [ ReportStatus "I see no route in the info panel. I will start when a route is set."
            , TakeMemoryMeasurementAtTime (currentTimeInMilliseconds + 4000)
            ]

        Just infoPanelRouteFirstMarker ->
            case memoryMeasurement |> isShipWarpingOrJumping of
                Nothing ->
                    [ ReportStatus "I cannot see whether the ship is warping or jumping."
                    , TakeMemoryMeasurementAtTime (currentTimeInMilliseconds + 4000)
                    ]

                Just True ->
                    [ ReportStatus "I see the ship is warping or jumping, so I wait."
                    , TakeMemoryMeasurementAtTime (currentTimeInMilliseconds + 4000)
                    ]

                Just False ->
                    botRequestsWhenNotWaitingForShipManeuver
                        memoryMeasurement
                        infoPanelRouteFirstMarker
                        ++ [ TakeMemoryMeasurementAtTime (currentTimeInMilliseconds + 2000) ]


botRequestsWhenNotWaitingForShipManeuver : MemoryMeasurement -> InfoPanelRouteRouteElementMarker -> List BotRequest
botRequestsWhenNotWaitingForShipManeuver memoryMeasurement infoPanelRouteFirstMarker =
    let
        announceAndEffectToOpenMenu =
            [ ReportStatus "I click on the route marker to open the menu."
            , mouseClickAtLocation
                (infoPanelRouteFirstMarker.uiElement.region |> centerFromRegion)
                MouseButtonRight
                |> Effect
            ]
    in
    case memoryMeasurement.menus |> List.head of
        Nothing ->
            [ ReportStatus "No menu is open."
            ]
                ++ announceAndEffectToOpenMenu

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
                    [ ReportStatus "A menu was open, but it did not contain a matching entry." ]
                        ++ announceAndEffectToOpenMenu

                Just menuEntryToClick ->
                    [ ReportStatus ("I click on the menu entry '" ++ menuEntryToClick.text ++ "' to start the next ship maneuver.")
                    , mouseClickAtLocation (menuEntryToClick.uiElement.region |> centerFromRegion) MouseButtonLeft |> Effect
                    ]


infoPanelRouteFirstMarkerFromMemoryMeasurement : MemoryMeasurement -> Maybe InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromMemoryMeasurement =
    .infoPanelRoute
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiElement.region.left + routeMarker.uiElement.region.top))
        >> Maybe.andThen List.head


isShipWarpingOrJumping : MemoryMeasurement -> Maybe Bool
isShipWarpingOrJumping =
    .shipUi
        >> Maybe.andThen .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map (\maneuverType -> [ SimplifiedSanderling.Warp, SimplifiedSanderling.Jump ] |> List.member maneuverType)

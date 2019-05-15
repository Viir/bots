module Main exposing
    ( botStep
    , botStepInterface
    , deserializeState
    , initInterface
    , main
    , serializeState
    )

{-| This is a warp to 0km auto-pilot, making your travels faster and thus safer by directly warping to gates/stations.
The bot follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.
Before starting the bot, set the in-game autopilot route and make sure the autopilot is expanded, so that the route is visible.
Make sure you are undocked before starting the bot because the bot does not undock.
-}

import Sanderling
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MemoryMeasurement
        , MemoryMeasurementShipUi
        , centerFromRegion
        , parseMemoryMeasurementFromJson
        )
import Sanderling_Interface_20190514
    exposing
        ( BotEvent(..)
        , BotEventAtTime
        , BotRequest(..)
        , MouseButton(..)
        , mouseClickAtLocation
        )



-- This implementation is modeled after the script from https://github.com/Arcitectus/Sanderling/blob/5cdd9f42759b40dc9f39084ec91beac70aef4134/src/Sanderling/Sanderling.Exe/sample/script/beginners-autopilot.cs


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


botStep : BotEventAtTime -> State -> ( State, List BotRequest )
botStep eventAtTime stateBefore =
    case eventAtTime.event of
        MemoryMeasurementFinished memoryMeasurementFromInterface ->
            let
                parseResult =
                    memoryMeasurementFromInterface
                        |> Result.andThen (.reducedWithNamedNodesJson >> Maybe.map Ok >> Maybe.withDefault (Err "Memory measurement record from interface did not contain reducedWithNamedNodesJson"))
                        |> Result.andThen parseMemoryMeasurementFromJson
            in
            case parseResult of
                Err memoryMeasurementError ->
                    ( initState
                    , [ ReportStatus ("Failed to get memory measurement: " ++ memoryMeasurementError)
                      , TakeMemoryMeasurementAtTimeInMilliseconds (eventAtTime.timeInMilliseconds + 4000)
                      ]
                    )

                Ok memoryMeasurement ->
                    ( initState, botRequests ( eventAtTime.timeInMilliseconds, memoryMeasurement ) )

        SetSessionTimeLimitInMilliseconds _ ->
            ( initState, [] )


botRequests : ( Int, MemoryMeasurement ) -> List BotRequest
botRequests ( currentTimeInMilliseconds, memoryMeasurement ) =
    case memoryMeasurement |> infoPanelRouteFirstMarkerFromMemoryMeasurement of
        Nothing ->
            [ ReportStatus "I see no route in the info panel. I will start when a route is set."
            , TakeMemoryMeasurementAtTimeInMilliseconds (currentTimeInMilliseconds + 4000)
            ]

        Just infoPanelRouteFirstMarker ->
            case memoryMeasurement.shipUi of
                Nothing ->
                    [ ReportStatus "I cannot see if the ship is warping or jumping. I wait for the ship UI to appear on the screen."
                    , TakeMemoryMeasurementAtTimeInMilliseconds (currentTimeInMilliseconds + 4000)
                    ]

                Just shipUi ->
                    if shipUi |> isShipWarpingOrJumping then
                        [ ReportStatus "I see the ship is warping or jumping. I wait until that maneuver ends."
                        , TakeMemoryMeasurementAtTimeInMilliseconds (currentTimeInMilliseconds + 4000)
                        ]

                    else
                        botRequestsWhenNotWaitingForShipManeuver
                            memoryMeasurement
                            infoPanelRouteFirstMarker
                            ++ [ TakeMemoryMeasurementAtTimeInMilliseconds (currentTimeInMilliseconds + 2000) ]


botRequestsWhenNotWaitingForShipManeuver : MemoryMeasurement -> InfoPanelRouteRouteElementMarker -> List BotRequest
botRequestsWhenNotWaitingForShipManeuver memoryMeasurement infoPanelRouteFirstMarker =
    let
        openMenuAnnouncementAndEffect =
            [ ReportStatus "I click on the route marker in the info panel to open the menu."
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
                ++ openMenuAnnouncementAndEffect

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
                    [ ReportStatus "A menu is open, but it does not contain a matching entry." ]
                        ++ openMenuAnnouncementAndEffect

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


isShipWarpingOrJumping : MemoryMeasurementShipUi -> Bool
isShipWarpingOrJumping =
    .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map
            (\maneuverType ->
                [ Sanderling.Warp, Sanderling.Jump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


{-| Define interface function for the framework. Don't change the function signature.
<https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.Common/PersistentProcess.cs>
-}
serializeState : State -> String
serializeState =
    always ""


{-| Define interface function for the framework. Don't change the function signature.
<https://github.com/Viir/Kalmit/blob/640078f59bea3fa2ba1af43372933cff304b8c94/implement/PersistentProcess/PersistentProcess.Common/PersistentProcess.cs>
-}
deserializeState : String -> State
deserializeState =
    always initState


{-| Define interface function for the framework. Don't change this.
-}
initInterface : ( State, String )
initInterface =
    Sanderling_Interface_20190514.wrapInitForSerialInterface init


{-| Define interface function for the framework. Don't change this.
-}
botStepInterface : String -> State -> ( State, String )
botStepInterface =
    Sanderling_Interface_20190514.wrapBotStepForSerialInterface botStep


{-| Define the Elm entry point. Don't change this function.
-}
main : Program Int State String
main =
    Sanderling.elmEntryPoint initInterface botStepInterface serializeState deserializeState

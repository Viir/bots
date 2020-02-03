{- EVE Online Warp-to-0 auto-pilot version 2020-02-03
   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.
   Before starting the bot, set the in-game autopilot route and make sure the autopilot is expanded, so that the route is visible.
   Make sure you are undocked before starting the bot because the bot does not undock.
-}
{-
   bot-catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import EveOnline.BotFramework exposing (BotEventAtTime, BotRequest(..))
import EveOnline.MemoryReading
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , ParsedUserInterface
        , ShipUI
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)


{-| The autopilot bot does not need to remember anything from the past; the information on the game client screen is sufficient to decide what to do next.
Therefore we need no state and use an empty tuple '()' to define the type of the state.
-}
type alias BotState =
    ()


type alias State =
    EveOnline.BotFramework.StateIncludingSetup BotState


initState : State
initState =
    EveOnline.BotFramework.initState ()


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.BotFramework.processEvent processEveOnlineBotEvent


processEveOnlineBotEvent :
    BotEventAtTime
    -> BotState
    -> { newState : BotState, requests : List BotRequest, millisecondsToNextMemoryReading : Int, statusDescriptionText : String }
processEveOnlineBotEvent eventAtTime stateBefore =
    case eventAtTime.event of
        EveOnline.BotFramework.MemoryReadingCompleted parsedUserInterface ->
            let
                ( requests, statusMessage ) =
                    botRequestsFromGameClientState parsedUserInterface

                millisecondsToNextMemoryReading =
                    if requests |> List.isEmpty then
                        4000

                    else
                        2000
            in
            { newState = stateBefore
            , requests = requests
            , millisecondsToNextMemoryReading = millisecondsToNextMemoryReading
            , statusDescriptionText = statusMessage
            }

        EveOnline.BotFramework.SetBotConfiguration botConfiguration ->
            { newState = stateBefore
            , requests = []
            , millisecondsToNextMemoryReading = 2000
            , statusDescriptionText =
                if botConfiguration |> String.isEmpty then
                    ""

                else
                    "I have a problem with this configuration: I am not programmed to support configuration at all. Maybe the bot catalog (https://to.botengine.org/bot-catalog) has a bot which better matches your use case?"
            }


botRequestsFromGameClientState : ParsedUserInterface -> ( List BotRequest, String )
botRequestsFromGameClientState parsedUserInterface =
    case parsedUserInterface |> infoPanelRouteFirstMarkerFromParsedUserInterface of
        Nothing ->
            ( []
            , "I see no route in the info panel. I will start when a route is set."
            )

        Just infoPanelRouteFirstMarker ->
            case parsedUserInterface.shipUI of
                CanNotSeeIt ->
                    ( []
                    , "I cannot see if the ship is warping or jumping. I wait for the ship UI to appear on the screen."
                    )

                CanSee shipUi ->
                    if shipUi |> isShipWarpingOrJumping then
                        ( []
                        , "I see the ship is warping or jumping. I wait until that maneuver ends."
                        )

                    else
                        botRequestsWhenNotWaitingForShipManeuver
                            parsedUserInterface
                            infoPanelRouteFirstMarker


botRequestsWhenNotWaitingForShipManeuver :
    ParsedUserInterface
    -> InfoPanelRouteRouteElementMarker
    -> ( List BotRequest, String )
botRequestsWhenNotWaitingForShipManeuver parsedUserInterface infoPanelRouteFirstMarker =
    let
        openMenuAnnouncementAndEffect =
            ( [ EffectOnGameClientWindow
                    (effectMouseClickAtLocation
                        VolatileHostInterface.MouseButtonRight
                        (infoPanelRouteFirstMarker.uiNode.totalDisplayRegion |> centerFromDisplayRegion)
                    )
              ]
            , "I click on the route marker in the info panel to open the menu."
            )
    in
    case parsedUserInterface.contextMenus |> List.head of
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
                    ( [ EffectOnGameClientWindow (effectMouseClickAtLocation MouseButtonLeft (menuEntryToClick.uiNode.totalDisplayRegion |> centerFromDisplayRegion)) ]
                    , "I click on the menu entry '" ++ menuEntryToClick.text ++ "' to start the next ship maneuver."
                    )


infoPanelRouteFirstMarkerFromParsedUserInterface : ParsedUserInterface -> Maybe InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromParsedUserInterface =
    .infoPanelRoute
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiNode.totalDisplayRegion.x + routeMarker.uiNode.totalDisplayRegion.y))
        >> Maybe.andThen List.head


isShipWarpingOrJumping : ShipUI -> Bool
isShipWarpingOrJumping =
    .indication
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map
            (\maneuverType ->
                [ EveOnline.MemoryReading.ManeuverWarp, EveOnline.MemoryReading.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False

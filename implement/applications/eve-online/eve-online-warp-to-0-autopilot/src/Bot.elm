{- EVE Online Warp-to-0 auto-pilot version 2020-05-12
   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.

   Before starting the bot, set up as follows:
   + Set the UI language to English.
   + Set the in-game autopilot route.
   + Make sure the autopilot info panel is expanded, so that the route is visible.
   + Undock before starting the bot because the bot does not undock.
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

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import Common.AppSettings as AppSettings
import EveOnline.BotFramework exposing (BotEffect(..))
import EveOnline.ParseUserInterface
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , ParsedUserInterface
        , ShipUI
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)


finishSessionAfterInactivityMinutes : Int
finishSessionAfterInactivityMinutes =
    4


{-| To support the feature that finishes the session some time of inactivity, it needs to remember the time of the last activity.
-}
type alias BotState =
    { lastActivityTime : Int
    }


type alias State =
    EveOnline.BotFramework.StateIncludingFramework () BotState


initState : State
initState =
    EveOnline.BotFramework.initState { lastActivityTime = 0 }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.BotFramework.processEvent
        { processEvent = processEveOnlineBotEvent
        , parseAppSettings = AppSettings.parseAllowOnlyEmpty ()
        }


processEveOnlineBotEvent :
    EveOnline.BotFramework.BotEventContext ()
    -> EveOnline.BotFramework.BotEvent
    -> BotState
    -> ( BotState, EveOnline.BotFramework.BotEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.BotFramework.MemoryReadingCompleted parsedUserInterface ->
            let
                continueWaiting statusDescriptionText =
                    ( stateBefore
                    , EveOnline.BotFramework.ContinueSession
                        { millisecondsToNextReadingFromGame = 3000
                        , statusDescriptionText = statusDescriptionText
                        , effects = []
                        }
                    )

                continueWithCurrentEffects ( effects, statusDescriptionText ) =
                    let
                        lastActivityTime =
                            if effects |> List.isEmpty then
                                stateBefore.lastActivityTime

                            else
                                eventContext.timeInMilliseconds // 1000
                    in
                    if 60 * finishSessionAfterInactivityMinutes < eventContext.timeInMilliseconds // 1000 - lastActivityTime then
                        ( stateBefore
                        , EveOnline.BotFramework.FinishSession
                            { statusDescriptionText =
                                "I finish this session because there was nothing to do for me in the last "
                                    ++ (finishSessionAfterInactivityMinutes |> String.fromInt)
                                    ++ " minutes."
                            }
                        )

                    else
                        ( { stateBefore | lastActivityTime = lastActivityTime }
                        , EveOnline.BotFramework.ContinueSession
                            { millisecondsToNextReadingFromGame = 2000
                            , effects = effects
                            , statusDescriptionText = statusDescriptionText
                            }
                        )
            in
            case parsedUserInterface |> infoPanelRouteFirstMarkerFromParsedUserInterface of
                Nothing ->
                    continueWithCurrentEffects
                        ( [], "I see no route in the info panel. I will start when a route is set." )

                Just infoPanelRouteFirstMarker ->
                    case parsedUserInterface.shipUI of
                        CanNotSeeIt ->
                            continueWithCurrentEffects
                                ( [], "I do not see the ship UI. Looks like we are docked." )

                        CanSee shipUi ->
                            if shipUi |> isShipWarpingOrJumping then
                                continueWaiting
                                    "I see the ship is warping or jumping. I wait until that maneuver ends."

                            else
                                continueWithCurrentEffects
                                    (botEffectsWhenNotWaitingForShipManeuver parsedUserInterface infoPanelRouteFirstMarker)


botEffectsWhenNotWaitingForShipManeuver :
    ParsedUserInterface
    -> InfoPanelRouteRouteElementMarker
    -> ( List BotEffect, String )
botEffectsWhenNotWaitingForShipManeuver parsedUserInterface infoPanelRouteFirstMarker =
    let
        openMenuAnnouncementAndEffect =
            ( [ EffectOnGameClientWindow
                    (effectMouseClickAtLocation
                        VolatileHostInterface.MouseButtonRight
                        (infoPanelRouteFirstMarker.uiNode.totalDisplayRegion |> centerFromDisplayRegion)
                    )
              ]
            , "I click on the route element icon in the info panel to open the menu."
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
    .infoPanelContainer
        >> EveOnline.ParseUserInterface.maybeVisibleAndThen .infoPanelRoute
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
                [ EveOnline.ParseUserInterface.ManeuverWarp, EveOnline.ParseUserInterface.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False

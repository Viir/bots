{- EVE Online Warp-to-0 auto-pilot version 2020-08-24
   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.

   Before starting the bot, set up the game client as follows:

   + Set the UI language to English.
   + Set the in-game autopilot route.
   + Make sure the autopilot info panel is expanded, so that the route is visible.
-}
{-
   app-catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree exposing (describeBranch)
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , SeeUndockingComplete
        , branchDependingOnDockedOrInSpace
        , infoPanelRouteFirstMarkerFromReadingFromGameClient
        , menuCascadeCompleted
        , shipUIIndicatesShipIsWarpingOrJumping
        , useContextMenuCascade
        , useMenuEntryWithTextContainingFirstOf
        , waitForProgressInGame
        )


type alias StateMemoryAndDecisionTree =
    EveOnline.AppFramework.AppStateWithMemoryAndDecisionTree ()


type alias State =
    EveOnline.AppFramework.StateIncludingFramework () StateMemoryAndDecisionTree


type alias BotDecisionContext =
    EveOnline.AppFramework.StepDecisionContext () ()


initState : State
initState =
    EveOnline.AppFramework.initState
        (EveOnline.AppFramework.initStateWithMemoryAndDecisionTree ())


autopilotBotDecisionRoot : BotDecisionContext -> DecisionPathNode
autopilotBotDecisionRoot context =
    branchDependingOnDockedOrInSpace
        { ifDocked = describeBranch "To continue, undock manually." waitForProgressInGame
        , ifSeeShipUI = always Nothing
        , ifUndockingComplete = decisionTreeWhenInSpace context
        }
        context.readingFromGameClient


decisionTreeWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decisionTreeWhenInSpace context undockingComplete =
    case context.readingFromGameClient |> infoPanelRouteFirstMarkerFromReadingFromGameClient of
        Nothing ->
            describeBranch "I see no route in the info panel. I will start when a route is set." waitForProgressInGame

        Just infoPanelRouteFirstMarker ->
            if undockingComplete.shipUI |> shipUIIndicatesShipIsWarpingOrJumping then
                describeBranch
                    "I see the ship is warping or jumping. I wait until that maneuver ends."
                    waitForProgressInGame

            else
                useContextMenuCascade
                    ( "route element icon", infoPanelRouteFirstMarker.uiNode )
                    (useMenuEntryWithTextContainingFirstOf
                        [ "dock", "jump" ]
                        menuCascadeCompleted
                    )


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext ()
    -> EveOnline.AppFramework.AppEvent
    -> StateMemoryAndDecisionTree
    -> ( StateMemoryAndDecisionTree, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = always identity
        , decisionTreeRoot = autopilotBotDecisionRoot
        , statusTextFromState = always ""
        , millisecondsToNextReadingFromGame = always 2000
        }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = AppSettings.parseAllowOnlyEmpty ()
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }

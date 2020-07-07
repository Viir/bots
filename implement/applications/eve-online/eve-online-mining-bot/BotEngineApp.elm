{- EVE Online mining bot version 2020-07-07
   The bot warps to an asteroid belt, mines there until the ore hold is full, and then docks at a station to unload the ore. It then repeats this cycle until you stop it.
   It remembers the station in which it was last docked, and docks again at the same station.

   Setup instructions for the EVE Online client:
   + Set the UI language to English.
   + In Overview window, make asteroids visible.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + Open one inventory window.
   + In the ship UI, arrange the modules:
     + Place all mining modules (to activate on targets) in the top row.
     + Place modules that should always be active in the middle row.
     + Hide passive modules by disabling the check-box `Display Passive Modules`.
   + If you want to use drones for defense against rats, place them in the drone bay, and open the 'Drones' window.
-}
{-
   app-catalog-tags:eve-online,mining
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200610 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (listElementAtWrappedIndex)
import Common.DecisionTree exposing (describeBranch, endDecisionPath)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , EndDecisionPathStructure(..)
        , ReadingFromGameClient
        , ShipModulesMemory
        , UIElement
        , UseContextMenuCascadeNode
        , actWithoutFurtherReadings
        , clickOnUIElement
        , getEntropyIntFromReadingFromGameClient
        , menuCascadeCompleted
        , menuEntryMatchesStationNameFromLocationInfoPanel
        , useMenuEntryInLastContextMenuInCascade
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        , useMenuEntryWithTextEqual
        , useRandomMenuEntry
        )
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (effectMouseClickAtLocation)


{-| Sources for the defaults:

  - <https://forum.botengine.org/t/mining-bot-wont-approach/3162>

-}
defaultBotSettings : BotSettings
defaultBotSettings =
    { runAwayShieldHitpointsThresholdPercent = 70
    , targetingRange = 8000
    , miningModuleRange = 5000
    , botStepDelayMilliseconds = 2000
    , lastDockedStationNameFromInfoPanel = Nothing
    , oreHoldMaxPercent = 99
    , selectInstancePilotName = Nothing
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleCommaSeparatedList
        {- Names to support with the `--app-settings`, see <https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#configuring-a-bot> -}
        ([ ( "run-away-shield-hitpoints-threshold-percent"
           , AppSettings.ValueTypeInteger (\threshold settings -> { settings | runAwayShieldHitpointsThresholdPercent = threshold })
           )
         , ( "targeting-range"
           , AppSettings.ValueTypeInteger (\range settings -> { settings | targetingRange = range })
           )
         , ( "mining-module-range"
           , AppSettings.ValueTypeInteger (\range settings -> { settings | miningModuleRange = range })
           )
         , ( "last-docked-station-name-from-info-panel"
           , AppSettings.ValueTypeString (\stationName -> \settings -> { settings | lastDockedStationNameFromInfoPanel = Just stationName })
           )
         , ( "ore-hold-max-percent"
           , AppSettings.ValueTypeInteger (\percent settings -> { settings | oreHoldMaxPercent = percent })
           )
         , ( "select-instance-pilot-name"
           , AppSettings.ValueTypeString (\pilotName -> \settings -> { settings | selectInstancePilotName = Just pilotName })
           )
         , ( "bot-step-delay"
           , AppSettings.ValueTypeInteger (\delay settings -> { settings | botStepDelayMilliseconds = delay })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { runAwayShieldHitpointsThresholdPercent : Int
    , targetingRange : Int
    , miningModuleRange : Int
    , botStepDelayMilliseconds : Int
    , lastDockedStationNameFromInfoPanel : Maybe String
    , oreHoldMaxPercent : Int
    , selectInstancePilotName : Maybe String
    }


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    , timesUnloaded : Int
    , volumeUnloadedCubicMeters : Int
    , lastUsedCapacityInOreHold : Maybe Int
    , shipModules : ShipModulesMemory
    }


type alias BotDecisionContext =
    { eventContext : EveOnline.AppFramework.AppEventContext BotSettings
    , memory : BotMemory
    , readingFromGameClient : ReadingFromGameClient
    }


botSettingsFromDecisionContext : BotDecisionContext -> BotSettings
botSettingsFromDecisionContext decisionContext =
    decisionContext.eventContext.appSettings |> Maybe.withDefault defaultBotSettings


type alias BotState =
    EveOnline.AppFramework.AppStateWithMemoryAndDecisionTree BotMemory


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings BotState


{-| A first outline of the decision tree for a mining bot came from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
miningBotDecisionRoot : BotDecisionContext -> DecisionPathNode
miningBotDecisionRoot context =
    generalSetupInUserInterface context.readingFromGameClient
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                (describeBranch "I see no ship UI, assume we are docked."
                    (ensureOreHoldIsSelectedInInventoryWindow
                        context.readingFromGameClient
                        dockedWithOreHoldSelected
                    )
                )
                (returnDronesAndRunAwayIfHitpointsAreTooLow context)
                (\seeUndockingComplete ->
                    describeBranch "I see we are in space, undocking complete."
                        (ensureOreHoldIsSelectedInInventoryWindow
                            context.readingFromGameClient
                            (inSpaceWithOreHoldSelected context seeUndockingComplete)
                        )
                )
                context.readingFromGameClient
            )


returnDronesAndRunAwayIfHitpointsAreTooLow : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode
returnDronesAndRunAwayIfHitpointsAreTooLow context shipUI =
    let
        returnDronesShieldHitpointsThresholdPercent =
            (context |> botSettingsFromDecisionContext).runAwayShieldHitpointsThresholdPercent + 5

        runAwayWithDescription =
            describeBranch
                ("Shield hitpoints are at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%. Run away.")
                (runAway context)
    in
    if shipUI.hitpointsPercent.shield < (context |> botSettingsFromDecisionContext).runAwayShieldHitpointsThresholdPercent then
        Just runAwayWithDescription

    else if shipUI.hitpointsPercent.shield < returnDronesShieldHitpointsThresholdPercent then
        returnDronesToBay context.readingFromGameClient
            |> Maybe.map
                (describeBranch
                    ("Shield hitpoints are below " ++ (returnDronesShieldHitpointsThresholdPercent |> String.fromInt) ++ "%. Return drones.")
                )
            |> Maybe.withDefault runAwayWithDescription
            |> Just

    else
        Nothing


generalSetupInUserInterface : ReadingFromGameClient -> Maybe DecisionPathNode
generalSetupInUserInterface readingFromGameClient =
    [ closeMessageBox, ensureInfoPanelLocationInfoIsExpanded ]
        |> List.filterMap
            (\maybeSetupDecisionFromGameReading ->
                maybeSetupDecisionFromGameReading readingFromGameClient
            )
        |> List.head


closeMessageBox : ReadingFromGameClient -> Maybe DecisionPathNode
closeMessageBox readingFromGameClient =
    readingFromGameClient.messageBoxes
        |> List.head
        |> Maybe.map
            (\messageBox ->
                describeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose =
                            .mainText
                                >> Maybe.map (String.trim >> String.toLower >> (\buttonText -> [ "close", "ok" ] |> List.member buttonText))
                                >> Maybe.withDefault False
                     in
                     case messageBox.buttons |> List.filter buttonCanBeUsedToClose |> List.head of
                        Nothing ->
                            describeBranch "I see no way to close this message box." askForHelpToGetUnstuck

                        Just buttonToUse ->
                            endDecisionPath
                                (actWithoutFurtherReadings
                                    ( "Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'."
                                    , [ buttonToUse.uiNode |> clickOnUIElement MouseButtonLeft ]
                                    )
                                )
                    )
            )


ensureInfoPanelLocationInfoIsExpanded : ReadingFromGameClient -> Maybe DecisionPathNode
ensureInfoPanelLocationInfoIsExpanded readingFromGameClient =
    case readingFromGameClient.infoPanelContainer |> maybeVisibleAndThen .infoPanelLocationInfo of
        CanNotSeeIt ->
            Just
                (describeBranch "I do not see the location info panel. Enable the info panel."
                    (case readingFromGameClient.infoPanelContainer |> maybeVisibleAndThen .icons |> maybeVisibleAndThen .locationInfo of
                        CanNotSeeIt ->
                            describeBranch "I do not see the icon for the location info panel." askForHelpToGetUnstuck

                        CanSee iconLocationInfoPanel ->
                            endDecisionPath
                                (actWithoutFurtherReadings
                                    ( "Click on the icon to enable the info panel."
                                    , [ iconLocationInfoPanel |> clickOnUIElement MouseButtonLeft ]
                                    )
                                )
                    )
                )

        CanSee infoPanelLocationInfo ->
            if 35 < infoPanelLocationInfo.uiNode.totalDisplayRegion.height then
                Nothing

            else
                Just
                    (describeBranch "Location info panel seems collapsed."
                        (endDecisionPath
                            (actWithoutFurtherReadings
                                ( "Click to expand the info panel."
                                , [ effectMouseClickAtLocation
                                        MouseButtonLeft
                                        { x = infoPanelLocationInfo.uiNode.totalDisplayRegion.x + 8
                                        , y = infoPanelLocationInfo.uiNode.totalDisplayRegion.y + 8
                                        }
                                  ]
                                )
                            )
                        )
                    )


dockedWithOreHoldSelected : EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
dockedWithOreHoldSelected inventoryWindowWithOreHoldSelected =
    case inventoryWindowWithOreHoldSelected |> itemHangarFromInventoryWindow of
        Nothing ->
            describeBranch "I do not see the item hangar in the inventory." askForHelpToGetUnstuck

        Just itemHangar ->
            case inventoryWindowWithOreHoldSelected |> selectedContainerFirstItemFromInventoryWindow of
                Nothing ->
                    describeBranch "I see no item in the ore hold. Time to undock."
                        (case inventoryWindowWithOreHoldSelected |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                describeBranch "I do not see the active ship in the inventory." askForHelpToGetUnstuck

                            Just activeShipEntry ->
                                useContextMenuCascade
                                    ( "ship in the inventory window"
                                    , activeShipEntry |> predictUIElementInventoryShipEntry
                                    )
                                    (useMenuEntryWithTextContaining "Undock" menuCascadeCompleted)
                        )

                Just itemInInventory ->
                    describeBranch "I see at least one item in the ore hold. Move this to the item hangar."
                        (endDecisionPath
                            (actWithoutFurtherReadings
                                ( "Drag and drop."
                                , VolatileHostInterface.effectsForDragAndDrop
                                    { startLocation = itemInInventory.totalDisplayRegion |> centerFromDisplayRegion
                                    , endLocation = itemHangar.totalDisplayRegion |> centerFromDisplayRegion
                                    , mouseButton = MouseButtonLeft
                                    }
                                )
                            )
                        )


lastDockedStationNameFromInfoPanelFromMemoryOrSettings : BotDecisionContext -> Maybe String
lastDockedStationNameFromInfoPanelFromMemoryOrSettings context =
    case context.memory.lastDockedStationNameFromInfoPanel of
        Just stationName ->
            Just stationName

        Nothing ->
            (context |> botSettingsFromDecisionContext).lastDockedStationNameFromInfoPanel


inSpaceWithOreHoldSelected : BotDecisionContext -> SeeUndockingComplete -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
inSpaceWithOreHoldSelected context seeUndockingComplete inventoryWindowWithOreHoldSelected =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        describeBranch "I see we are warping."
            ([ returnDronesToBay context.readingFromGameClient
             , readShipUIModuleButtonTooltips context
             ]
                |> List.filterMap identity
                |> List.head
                |> Maybe.withDefault waitForProgressInGame
            )

    else
        case seeUndockingComplete.shipUI.moduleButtonsRows.middle |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
            Just inactiveModule ->
                describeBranch "I see an inactive module in the middle row. Activate it."
                    (endDecisionPath
                        (actWithoutFurtherReadings
                            ( "Click on the module.", [ inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft ] )
                        )
                    )

            Nothing ->
                case inventoryWindowWithOreHoldSelected |> capacityGaugeUsedPercent of
                    Nothing ->
                        describeBranch "I do not see the ore hold capacity gauge." askForHelpToGetUnstuck

                    Just fillPercent ->
                        let
                            describeThresholdToUnload =
                                ((context |> botSettingsFromDecisionContext).oreHoldMaxPercent |> String.fromInt) ++ "%"
                        in
                        if (context |> botSettingsFromDecisionContext).oreHoldMaxPercent <= fillPercent then
                            describeBranch ("The ore hold is filled at least " ++ describeThresholdToUnload ++ ". Unload the ore.")
                                (returnDronesToBay context.readingFromGameClient
                                    |> Maybe.withDefault
                                        (case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
                                            Nothing ->
                                                describeBranch "At which station should I dock?. I was never docked in a station in this session." askForHelpToGetUnstuck

                                            Just lastDockedStationNameFromInfoPanel ->
                                                dockToStationMatchingNameSeenInInfoPanel
                                                    { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel }
                                                    context.readingFromGameClient
                                        )
                                )

                        else
                            describeBranch ("The ore hold is not yet filled " ++ describeThresholdToUnload ++ ". Get more ore.")
                                (case context.readingFromGameClient.targets |> List.head of
                                    Nothing ->
                                        describeBranch "I see no locked target."
                                            (travelToMiningSiteAndLaunchDronesAndTargetAsteroid context)

                                    Just _ ->
                                        {- Depending on the UI configuration, the game client might automatically target rats.
                                           To avoid these targets interfering with mining, unlock them here.
                                        -}
                                        unlockTargetsNotForMining context
                                            |> Maybe.withDefault
                                                (describeBranch "I see a locked target."
                                                    (case seeUndockingComplete.shipUI.moduleButtonsRows.top |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                                        -- TODO: Check previous memory reading too for module activity.
                                                        Nothing ->
                                                            describeBranch "All mining laser modules are active."
                                                                (readShipUIModuleButtonTooltips context
                                                                    |> Maybe.withDefault waitForProgressInGame
                                                                )

                                                        Just inactiveModule ->
                                                            describeBranch "I see an inactive mining module. Activate it."
                                                                (endDecisionPath
                                                                    (actWithoutFurtherReadings
                                                                        ( "Click on the module."
                                                                        , [ inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft ]
                                                                        )
                                                                    )
                                                                )
                                                    )
                                                )
                                )


unlockTargetsNotForMining : BotDecisionContext -> Maybe DecisionPathNode
unlockTargetsNotForMining context =
    let
        targetsToUnlock =
            context.readingFromGameClient.targets
                |> List.filter (.textsTopToBottom >> List.any (String.toLower >> String.contains "asteroid") >> not)
    in
    targetsToUnlock
        |> List.head
        |> Maybe.map
            (\targetToUnlock ->
                describeBranch
                    ("I see a target not for mining: '"
                        ++ (targetToUnlock.textsTopToBottom |> String.join " ")
                        ++ "'. Unlock this target."
                    )
                    (useContextMenuCascade
                        ( "target", targetToUnlock.barAndImageCont |> Maybe.withDefault targetToUnlock.uiNode )
                        (useMenuEntryWithTextContaining "unlock" menuCascadeCompleted)
                    )
            )


travelToMiningSiteAndLaunchDronesAndTargetAsteroid : BotDecisionContext -> DecisionPathNode
travelToMiningSiteAndLaunchDronesAndTargetAsteroid context =
    case context.readingFromGameClient |> topmostAsteroidFromOverviewWindow of
        Nothing ->
            describeBranch "I see no asteroid in the overview. Warp to mining site."
                (returnDronesToBay context.readingFromGameClient
                    |> Maybe.withDefault
                        (warpToMiningSite context.readingFromGameClient)
                )

        Just asteroidInOverview ->
            launchDrones context.readingFromGameClient
                |> Maybe.withDefault
                    (describeBranch
                        ("Choosing asteroid '" ++ (asteroidInOverview.objectName |> Maybe.withDefault "Nothing") ++ "'")
                        (lockTargetFromOverviewEntryAndEnsureIsInRange
                            context.readingFromGameClient
                            (min (context |> botSettingsFromDecisionContext).targetingRange
                                (context |> botSettingsFromDecisionContext).miningModuleRange
                            )
                            asteroidInOverview
                        )
                    )


ensureOreHoldIsSelectedInInventoryWindow : ReadingFromGameClient -> (EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode) -> DecisionPathNode
ensureOreHoldIsSelectedInInventoryWindow readingFromGameClient continueWithInventoryWindow =
    case readingFromGameClient |> inventoryWindowWithOreHoldSelectedFromGameClient of
        Just inventoryWindow ->
            continueWithInventoryWindow inventoryWindow

        Nothing ->
            case readingFromGameClient.inventoryWindows |> List.head of
                Nothing ->
                    describeBranch "I do not see an inventory window. Please open an inventory window." askForHelpToGetUnstuck

                Just inventoryWindow ->
                    describeBranch
                        "Ore hold is not selected. Select the ore hold."
                        (case inventoryWindow |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                describeBranch "I do not see the active ship in the inventory." askForHelpToGetUnstuck

                            Just activeShipTreeEntry ->
                                let
                                    maybeOreHoldTreeEntry =
                                        activeShipTreeEntry.children
                                            |> List.map EveOnline.ParseUserInterface.unwrapInventoryWindowLeftTreeEntryChild
                                            |> List.filter (.text >> String.toLower >> String.contains "ore hold")
                                            |> List.head
                                in
                                case maybeOreHoldTreeEntry of
                                    Nothing ->
                                        describeBranch "I do not see the ore hold under the active ship in the inventory."
                                            (case activeShipTreeEntry.toggleBtn of
                                                Nothing ->
                                                    describeBranch "I do not see the toggle button to expand the active ship tree entry."
                                                        askForHelpToGetUnstuck

                                                Just toggleBtn ->
                                                    endDecisionPath
                                                        (actWithoutFurtherReadings
                                                            ( "Click the toggle button to expand."
                                                            , [ toggleBtn |> clickOnUIElement MouseButtonLeft ]
                                                            )
                                                        )
                                            )

                                    Just oreHoldTreeEntry ->
                                        endDecisionPath
                                            (actWithoutFurtherReadings
                                                ( "Click the tree entry representing the ore hold."
                                                , [ oreHoldTreeEntry.uiNode |> clickOnUIElement MouseButtonLeft ]
                                                )
                                            )
                        )


lockTargetFromOverviewEntryAndEnsureIsInRange : ReadingFromGameClient -> Int -> OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntryAndEnsureIsInRange readingFromGameClient rangeInMeters overviewEntry =
    case overviewEntry.objectDistanceInMeters of
        Ok distanceInMeters ->
            if distanceInMeters <= rangeInMeters then
                if overviewEntry.commonIndications.targetedByMe || overviewEntry.commonIndications.targeting then
                    describeBranch "Locking target is in progress, wait for completion." waitForProgressInGame

                else
                    describeBranch "Object is in range. Lock target."
                        (lockTargetFromOverviewEntry overviewEntry)

            else
                describeBranch ("Object is not in range (" ++ (distanceInMeters |> String.fromInt) ++ " meters away). Approach.")
                    (if shipManeuverIsApproaching readingFromGameClient then
                        describeBranch "I see we already approach." waitForProgressInGame

                     else
                        useContextMenuCascadeOnOverviewEntry
                            overviewEntry
                            (useMenuEntryWithTextContaining "approach" menuCascadeCompleted)
                    )

        Err error ->
            describeBranch ("Failed to read the distance: " ++ error) askForHelpToGetUnstuck


lockTargetFromOverviewEntry : OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry =
    describeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
        (useContextMenuCascadeOnOverviewEntry overviewEntry
            (useMenuEntryWithTextEqual "Lock target" menuCascadeCompleted)
        )


dockToStationMatchingNameSeenInInfoPanel : { stationNameFromInfoPanel : String } -> ReadingFromGameClient -> DecisionPathNode
dockToStationMatchingNameSeenInInfoPanel { stationNameFromInfoPanel } =
    dockToStationUsingSurroundingsButtonMenu
        { describeChoice = "representing the station '" ++ stationNameFromInfoPanel ++ "'."
        , chooseEntry =
            List.filter (menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel) >> List.head
        }


dockToStationUsingSurroundingsButtonMenu :
    { describeChoice : String, chooseEntry : List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry }
    -> ReadingFromGameClient
    -> DecisionPathNode
dockToStationUsingSurroundingsButtonMenu stationMenuEntryChoice =
    useContextMenuCascadeOnListSurroundingsButton
        (useMenuEntryWithTextContainingFirstOf [ "stations", "structures" ]
            (useMenuEntryInLastContextMenuInCascade stationMenuEntryChoice
                (useMenuEntryWithTextContaining "dock" menuCascadeCompleted)
            )
        )


warpToMiningSite : ReadingFromGameClient -> DecisionPathNode
warpToMiningSite readingFromGameClient =
    readingFromGameClient
        |> useContextMenuCascadeOnListSurroundingsButton
            (useMenuEntryWithTextContaining "asteroid belts"
                (useRandomMenuEntry
                    (useMenuEntryWithTextContaining "Warp to Within"
                        (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
                    )
                )
            )


runAway : BotDecisionContext -> DecisionPathNode
runAway context =
    case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
        Nothing ->
            dockToRandomStation context.readingFromGameClient

        Just lastDockedStationNameFromInfoPanel ->
            dockToStationMatchingNameSeenInInfoPanel
                { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel }
                context.readingFromGameClient


dockToRandomStation : ReadingFromGameClient -> DecisionPathNode
dockToRandomStation readingFromGameClient =
    dockToStationUsingSurroundingsButtonMenu
        { describeChoice = "Pick random station", chooseEntry = listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient readingFromGameClient) }
        readingFromGameClient


launchDrones : ReadingFromGameClient -> Maybe DecisionPathNode
launchDrones readingFromGameClient =
    readingFromGameClient.dronesWindow
        |> maybeNothingFromCanNotSeeIt
        |> Maybe.andThen
            (\dronesWindow ->
                case ( dronesWindow.droneGroupInBay, dronesWindow.droneGroupInLocalSpace ) of
                    ( Just droneGroupInBay, Just droneGroupInLocalSpace ) ->
                        let
                            dronesInBayQuantity =
                                droneGroupInBay.header.quantityFromTitle |> Maybe.withDefault 0

                            dronesInLocalSpaceQuantity =
                                droneGroupInLocalSpace.header.quantityFromTitle |> Maybe.withDefault 0
                        in
                        if 0 < dronesInBayQuantity && dronesInLocalSpaceQuantity < 5 then
                            Just
                                (describeBranch "Launch drones"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInBay.header.uiNode )
                                        (useMenuEntryWithTextContaining "Launch drone" menuCascadeCompleted)
                                    )
                                )

                        else
                            Nothing

                    _ ->
                        Nothing
            )


returnDronesToBay : ReadingFromGameClient -> Maybe DecisionPathNode
returnDronesToBay readingFromGameClient =
    readingFromGameClient.dronesWindow
        |> maybeNothingFromCanNotSeeIt
        |> Maybe.andThen .droneGroupInLocalSpace
        |> Maybe.andThen
            (\droneGroupInLocalSpace ->
                if (droneGroupInLocalSpace.header.quantityFromTitle |> Maybe.withDefault 0) < 1 then
                    Nothing

                else
                    Just
                        (describeBranch "I see there are drones in local space. Return those to bay."
                            (useContextMenuCascade
                                ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                (useMenuEntryWithTextContaining "Return to drone bay" menuCascadeCompleted)
                            )
                        )
            )


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips context =
    context.readingFromGameClient.shipUI
        |> maybeNothingFromCanNotSeeIt
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filter (EveOnline.AppFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules >> (==) Nothing)
        |> List.head
        |> Maybe.map
            (\moduleButtonWithoutMemoryOfTooltip ->
                endDecisionPath
                    (actWithoutFurtherReadings
                        ( "Read tooltip for module button"
                        , [ VolatileHostInterface.MouseMoveTo
                                { location = moduleButtonWithoutMemoryOfTooltip.uiNode.totalDisplayRegion |> centerFromDisplayRegion }
                          ]
                        )
                    )
            )


useContextMenuCascadeOnOverviewEntry :
    OverviewWindowEntry
    -> UseContextMenuCascadeNode
    -> DecisionPathNode
useContextMenuCascadeOnOverviewEntry overviewEntry useContextMenu =
    useContextMenuCascade
        ( "overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'", overviewEntry.uiNode )
        useContextMenu


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


branchDependingOnDockedOrInSpace :
    DecisionPathNode
    -> (EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode)
    -> (SeeUndockingComplete -> DecisionPathNode)
    -> ReadingFromGameClient
    -> DecisionPathNode
branchDependingOnDockedOrInSpace branchIfDocked branchIfCanSeeShipUI branchIfUndockingComplete readingFromGameClient =
    case readingFromGameClient.shipUI of
        CanNotSeeIt ->
            branchIfDocked

        CanSee shipUI ->
            branchIfCanSeeShipUI shipUI
                |> Maybe.withDefault
                    (case readingFromGameClient.overviewWindow of
                        CanNotSeeIt ->
                            describeBranch "I see no overview window, wait until undocking completed." waitForProgressInGame

                        CanSee overviewWindow ->
                            branchIfUndockingComplete
                                { shipUI = shipUI, overviewWindow = overviewWindow }
                    )


useContextMenuCascadeOnListSurroundingsButton : UseContextMenuCascadeNode -> ReadingFromGameClient -> DecisionPathNode
useContextMenuCascadeOnListSurroundingsButton useContextMenu readingFromGameClient =
    case readingFromGameClient.infoPanelContainer |> maybeVisibleAndThen .infoPanelLocationInfo of
        CanNotSeeIt ->
            describeBranch "I do not see the location info panel." askForHelpToGetUnstuck

        CanSee infoPanelLocationInfo ->
            useContextMenuCascade
                ( "surroundings button", infoPanelLocationInfo.listSurroundingsButton )
                useContextMenu


waitForProgressInGame : DecisionPathNode
waitForProgressInGame =
    endDecisionPath Wait


askForHelpToGetUnstuck : DecisionPathNode
askForHelpToGetUnstuck =
    describeBranch "I am stuck here and need help to continue." (endDecisionPath Wait)


initState : State
initState =
    EveOnline.AppFramework.initState
        (EveOnline.AppFramework.initStateWithMemoryAndDecisionTree
            { lastDockedStationNameFromInfoPanel = Nothing
            , timesUnloaded = 0
            , volumeUnloadedCubicMeters = 0
            , lastUsedCapacityInOreHold = Nothing
            , shipModules = EveOnline.AppFramework.initShipModulesMemory
            }
        )


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = parseBotSettings
        , selectGameClientInstance =
            Maybe.andThen .selectInstancePilotName
                >> Maybe.map EveOnline.AppFramework.selectGameClientInstanceWithPilotName
                >> Maybe.withDefault EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
        , statusTextFromState = statusTextFromState
        , decisionTreeRoot = miningBotDecisionRoot
        , millisecondsToNextReadingFromGame =
            .eventContext
                >> .appSettings
                >> Maybe.withDefault defaultBotSettings
                >> .botStepDelayMilliseconds
        }


statusTextFromState : BotDecisionContext -> String
statusTextFromState context =
    let
        readingFromGameClient =
            context.readingFromGameClient

        describeSessionPerformance =
            [ ( "times unloaded", context.memory.timesUnloaded )
            , ( "volume unloaded / m³", context.memory.volumeUnloadedCubicMeters )
            ]
                |> List.map (\( metric, amount ) -> metric ++ ": " ++ (amount |> String.fromInt))
                |> String.join ", "

        describeShip =
            case readingFromGameClient.shipUI of
                CanSee shipUI ->
                    "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    case
                        readingFromGameClient.infoPanelContainer
                            |> maybeVisibleAndThen .infoPanelLocationInfo
                            |> maybeVisibleAndThen .expandedContent
                            |> maybeNothingFromCanNotSeeIt
                            |> Maybe.andThen .currentStationName
                    of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I do not see if I am docked or in space. Please set up game client first."

        describeDrones =
            case readingFromGameClient.dronesWindow of
                CanNotSeeIt ->
                    "I do not see the drones window."

                CanSee dronesWindow ->
                    "I see the drones window: In bay: "
                        ++ (dronesWindow.droneGroupInBay |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ ", in local space: "
                        ++ (dronesWindow.droneGroupInLocalSpace |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ "."

        describeOreHold =
            "Ore hold filled "
                ++ (readingFromGameClient
                        |> inventoryWindowWithOreHoldSelectedFromGameClient
                        |> Maybe.andThen capacityGaugeUsedPercent
                        |> Maybe.map String.fromInt
                        |> Maybe.withDefault "Unknown"
                   )
                ++ "%."

        describeCurrentReading =
            [ describeOreHold, describeShip, describeDrones ] |> String.join " "
    in
    [ "Session performance: " ++ describeSessionPerformance
    , "---"
    , "Current reading: " ++ describeCurrentReading
    ]
        |> String.join "\n"


updateMemoryForNewReadingFromGame : ReadingFromGameClient -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame currentReading botMemoryBefore =
    let
        currentStationNameFromInfoPanel =
            currentReading.infoPanelContainer
                |> maybeVisibleAndThen .infoPanelLocationInfo
                |> maybeVisibleAndThen .expandedContent
                |> maybeNothingFromCanNotSeeIt
                |> Maybe.andThen .currentStationName

        lastUsedCapacityInOreHold =
            currentReading
                |> inventoryWindowWithOreHoldSelectedFromGameClient
                |> Maybe.andThen .selectedContainerCapacityGauge
                |> Maybe.andThen Result.toMaybe
                |> Maybe.map .used

        completedUnloadSincePreviousReading =
            case botMemoryBefore.lastUsedCapacityInOreHold of
                Nothing ->
                    False

                Just previousUsedCapacityInOreHold ->
                    lastUsedCapacityInOreHold == Just 0 && 0 < previousUsedCapacityInOreHold

        volumeUnloadedSincePreviousReading =
            case botMemoryBefore.lastUsedCapacityInOreHold of
                Nothing ->
                    0

                Just previousUsedCapacityInOreHold ->
                    case lastUsedCapacityInOreHold of
                        Nothing ->
                            0

                        Just currentUsedCapacityInOreHold ->
                            -- During mining, when new ore appears in the inventory, this difference is negative.
                            max 0 (previousUsedCapacityInOreHold - currentUsedCapacityInOreHold)

        timesUnloaded =
            botMemoryBefore.timesUnloaded
                + (if completedUnloadSincePreviousReading then
                    1

                   else
                    0
                  )

        volumeUnloadedCubicMeters =
            botMemoryBefore.volumeUnloadedCubicMeters + volumeUnloadedSincePreviousReading
    in
    { lastDockedStationNameFromInfoPanel =
        [ currentStationNameFromInfoPanel, botMemoryBefore.lastDockedStationNameFromInfoPanel ]
            |> List.filterMap identity
            |> List.head
    , timesUnloaded = timesUnloaded
    , volumeUnloadedCubicMeters = volumeUnloadedCubicMeters
    , lastUsedCapacityInOreHold = lastUsedCapacityInOreHold
    , shipModules =
        botMemoryBefore.shipModules
            |> EveOnline.AppFramework.integrateCurrentReadingsIntoShipModulesMemory currentReading
    }


useContextMenuCascade : ( String, UIElement ) -> UseContextMenuCascadeNode -> DecisionPathNode
useContextMenuCascade ( initialUIElementName, initialUIElement ) useContextMenu =
    { actionsAlreadyDecided =
        ( "Open context menu on " ++ initialUIElementName
        , [ initialUIElement |> clickOnUIElement MouseButtonRight
          ]
        )
    , actionsDependingOnNewReadings = useContextMenu |> EveOnline.AppFramework.unpackContextMenuTreeToListOfActionsDependingOnReadings
    }
        |> Act
        |> endDecisionPath


activeShipTreeEntryFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
activeShipTreeEntryFromInventoryWindow =
    .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


topmostAsteroidFromOverviewWindow : ReadingFromGameClient -> Maybe OverviewWindowEntry
topmostAsteroidFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


overviewWindowEntriesRepresentingAsteroids : ReadingFromGameClient -> List OverviewWindowEntry
overviewWindowEntriesRepresentingAsteroids =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter overviewWindowEntryRepresentsAnAsteroid)
        >> Maybe.withDefault []


overviewWindowEntryRepresentsAnAsteroid : OverviewWindowEntry -> Bool
overviewWindowEntryRepresentsAnAsteroid entry =
    (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "asteroid"))
        && (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "belt") |> not)


capacityGaugeUsedPercent : EveOnline.ParseUserInterface.InventoryWindow -> Maybe Int
capacityGaugeUsedPercent =
    .selectedContainerCapacityGauge
        >> Maybe.andThen Result.toMaybe
        >> Maybe.andThen
            (\capacity -> capacity.maximum |> Maybe.map (\maximum -> capacity.used * 100 // maximum))


inventoryWindowWithOreHoldSelectedFromGameClient : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindow
inventoryWindowWithOreHoldSelectedFromGameClient =
    .inventoryWindows
        >> List.filter inventoryWindowSelectedContainerIsOreHold
        >> List.head


inventoryWindowSelectedContainerIsOreHold : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsOreHold =
    .subCaptionLabelText >> Maybe.map (String.toLower >> String.contains "ore hold") >> Maybe.withDefault False


selectedContainerFirstItemFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe UIElement
selectedContainerFirstItemFromInventoryWindow =
    .selectedContainerInventory
        >> Maybe.andThen .itemsView
        >> Maybe.map
            (\itemsView ->
                case itemsView of
                    EveOnline.ParseUserInterface.InventoryItemsListView { items } ->
                        items

                    EveOnline.ParseUserInterface.InventoryItemsNotListView { items } ->
                        items
            )
        >> Maybe.andThen List.head


itemHangarFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe UIElement
itemHangarFromInventoryWindow =
    .leftTreeEntries
        >> List.filter (.text >> String.toLower >> String.contains "item hangar")
        >> List.head
        >> Maybe.map .uiNode


{-| The region of a ship entry in the inventory window can contain child nodes (e.g. 'Ore Hold').
For this reason, we don't click on the center but stay close to the top.
-}
predictUIElementInventoryShipEntry : EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry -> UIElement
predictUIElementInventoryShipEntry treeEntry =
    let
        originalUIElement =
            treeEntry.uiNode

        originalTotalDisplayRegion =
            originalUIElement.totalDisplayRegion

        totalDisplayRegion =
            { originalTotalDisplayRegion | height = 10 }
    in
    { originalUIElement | totalDisplayRegion = totalDisplayRegion }


isShipWarpingOrJumping : EveOnline.ParseUserInterface.ShipUI -> Bool
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


shipManeuverIsApproaching : ReadingFromGameClient -> Bool
shipManeuverIsApproaching =
    .shipUI
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.indication >> maybeNothingFromCanNotSeeIt)
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map ((==) EveOnline.ParseUserInterface.ManeuverApproach)
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False

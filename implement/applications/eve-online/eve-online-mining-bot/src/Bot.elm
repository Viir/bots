{- EVE Online mining bot version 2020-05-29
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
   bot-catalog-tags:eve-online,mining
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (listElementAtWrappedIndex)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework exposing (AppEffect(..), ShipModulesMemory, getEntropyIntFromReadingFromGameClient)
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
         , ( "bot-step-delay"
           , AppSettings.ValueTypeInteger (\delay settings -> { settings | botStepDelayMilliseconds = delay })
           )
         , ( "last-docked-station-name-from-info-panel"
           , AppSettings.ValueTypeString (\stationName -> \settings -> { settings | lastDockedStationNameFromInfoPanel = Just stationName })
           )
         , ( "ore-hold-max-percent"
           , AppSettings.ValueTypeInteger (\percent settings -> { settings | oreHoldMaxPercent = percent })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias BotSettings =
    { runAwayShieldHitpointsThresholdPercent : Int
    , targetingRange : Int
    , miningModuleRange : Int
    , botStepDelayMilliseconds : Int
    , lastDockedStationNameFromInfoPanel : Maybe String
    , oreHoldMaxPercent : Int
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


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias TreeLeafAct =
    { actionsAlreadyDecided : ( String, List VolatileHostInterface.EffectOnWindowStructure )
    , actionsDependingOnNewReadings : List ( String, ReadingFromGameClient -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
    }


type EndDecisionPathStructure
    = Wait
    | Act TreeLeafAct


type DecisionPathNode
    = DescribeBranch String DecisionPathNode
    | EndDecisionPath EndDecisionPathStructure


type alias BotState =
    { programState :
        Maybe
            { originalDecision : DecisionPathNode
            , remainingActions : List ( String, ReadingFromGameClient -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
            }
    , botMemory : BotMemory
    }


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings BotState


{-| A first outline of the decision tree for a mining bot came from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
decideNextAction : BotDecisionContext -> DecisionPathNode
decideNextAction context =
    generalSetupInUserInterface context.readingFromGameClient
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                (DescribeBranch "I see no ship UI, assume we are docked."
                    (ensureOreHoldIsSelectedInInventoryWindow
                        context.readingFromGameClient
                        dockedWithOreHoldSelected
                    )
                )
                (returnDronesAndRunAwayIfHitpointsAreTooLow context)
                (\seeUndockingComplete ->
                    DescribeBranch "I see we are in space, undocking complete."
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
            DescribeBranch
                ("Shield hitpoints are at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%. Run away.")
                (runAway context)
    in
    if shipUI.hitpointsPercent.shield < (context |> botSettingsFromDecisionContext).runAwayShieldHitpointsThresholdPercent then
        Just runAwayWithDescription

    else if shipUI.hitpointsPercent.shield < returnDronesShieldHitpointsThresholdPercent then
        returnDronesToBay context.readingFromGameClient
            |> Maybe.map
                (DescribeBranch
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
                DescribeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose =
                            .mainText
                                >> Maybe.map (String.trim >> String.toLower >> (\buttonText -> [ "close", "ok" ] |> List.member buttonText))
                                >> Maybe.withDefault False
                     in
                     case messageBox.buttons |> List.filter buttonCanBeUsedToClose |> List.head of
                        Nothing ->
                            DescribeBranch "I see no way to close this message box." askForHelpToGetUnstuck

                        Just buttonToUse ->
                            EndDecisionPath
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
                (DescribeBranch "I do not see the location info panel. Enable the info panel."
                    (case readingFromGameClient.infoPanelContainer |> maybeVisibleAndThen .icons |> maybeVisibleAndThen .locationInfo of
                        CanNotSeeIt ->
                            DescribeBranch "I do not see the icon for the location info panel." askForHelpToGetUnstuck

                        CanSee iconLocationInfoPanel ->
                            EndDecisionPath
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
                    (DescribeBranch "Location info panel seems collapsed."
                        (EndDecisionPath
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
            DescribeBranch "I do not see the item hangar in the inventory." askForHelpToGetUnstuck

        Just itemHangar ->
            case inventoryWindowWithOreHoldSelected |> selectedContainerFirstItemFromInventoryWindow of
                Nothing ->
                    DescribeBranch "I see no item in the ore hold. Time to undock."
                        (case inventoryWindowWithOreHoldSelected |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                DescribeBranch "I do not see the active ship in the inventory." askForHelpToGetUnstuck

                            Just activeShipEntry ->
                                EndDecisionPath
                                    (useContextMenuCascade
                                        ( "Rightclick on the ship in the inventory window."
                                        , activeShipEntry |> predictUIElementInventoryShipEntry
                                        )
                                        [ MenuEntryWithTextContaining "Undock" ]
                                    )
                        )

                Just itemInInventory ->
                    DescribeBranch "I see at least one item in the ore hold. Move this to the item hangar."
                        (EndDecisionPath
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
        DescribeBranch "I see we are warping."
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
                DescribeBranch "I see an inactive module in the middle row. Activate it."
                    (EndDecisionPath
                        (actWithoutFurtherReadings
                            ( "Click on the module.", [ inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft ] )
                        )
                    )

            Nothing ->
                case inventoryWindowWithOreHoldSelected |> capacityGaugeUsedPercent of
                    Nothing ->
                        DescribeBranch "I do not see the ore hold capacity gauge." askForHelpToGetUnstuck

                    Just fillPercent ->
                        let
                            describeThresholdToUnload =
                                ((context |> botSettingsFromDecisionContext).oreHoldMaxPercent |> String.fromInt) ++ "%"
                        in
                        if (context |> botSettingsFromDecisionContext).oreHoldMaxPercent <= fillPercent then
                            DescribeBranch ("The ore hold is filled at least " ++ describeThresholdToUnload ++ ". Unload the ore.")
                                (returnDronesToBay context.readingFromGameClient
                                    |> Maybe.withDefault
                                        (case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
                                            Nothing ->
                                                DescribeBranch "At which station should I dock?. I was never docked in a station in this session." askForHelpToGetUnstuck

                                            Just lastDockedStationNameFromInfoPanel ->
                                                dockToStationMatchingNameSeenInInfoPanel
                                                    { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel }
                                                    context.readingFromGameClient
                                        )
                                )

                        else
                            DescribeBranch ("The ore hold is not yet filled " ++ describeThresholdToUnload ++ ". Get more ore.")
                                (case context.readingFromGameClient.targets |> List.head of
                                    Nothing ->
                                        DescribeBranch "I see no locked target."
                                            (travelToMiningSiteAndLaunchDronesAndTargetAsteroid context)

                                    Just _ ->
                                        {- Depending on the UI configuration, the game client might automatically target rats.
                                           To avoid these targets interfering with mining, unlock them here.
                                        -}
                                        unlockTargetsNotForMining context
                                            |> Maybe.withDefault
                                                (DescribeBranch "I see a locked target."
                                                    (case seeUndockingComplete.shipUI.moduleButtonsRows.top |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                                        -- TODO: Check previous memory reading too for module activity.
                                                        Nothing ->
                                                            DescribeBranch "All mining laser modules are active."
                                                                (readShipUIModuleButtonTooltips context
                                                                    |> Maybe.withDefault waitForProgressInGame
                                                                )

                                                        Just inactiveModule ->
                                                            DescribeBranch "I see an inactive mining module. Activate it."
                                                                (EndDecisionPath
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
                DescribeBranch
                    ("I see a target not for mining: '"
                        ++ (targetToUnlock.textsTopToBottom |> String.join " ")
                        ++ "'. Unlock this target."
                    )
                    (EndDecisionPath
                        (useContextMenuCascade
                            ( "Target", targetToUnlock.barAndImageCont |> Maybe.withDefault targetToUnlock.uiNode )
                            [ MenuEntryWithTextContaining "unlock" ]
                        )
                    )
            )


travelToMiningSiteAndLaunchDronesAndTargetAsteroid : BotDecisionContext -> DecisionPathNode
travelToMiningSiteAndLaunchDronesAndTargetAsteroid context =
    case context.readingFromGameClient |> topmostAsteroidFromOverviewWindow of
        Nothing ->
            DescribeBranch "I see no asteroid in the overview. Warp to mining site."
                (returnDronesToBay context.readingFromGameClient
                    |> Maybe.withDefault
                        (warpToMiningSite context.readingFromGameClient)
                )

        Just asteroidInOverview ->
            launchDrones context.readingFromGameClient
                |> Maybe.withDefault
                    (DescribeBranch
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
                    DescribeBranch "I do not see an inventory window. Please open an inventory window." askForHelpToGetUnstuck

                Just inventoryWindow ->
                    DescribeBranch
                        "Ore hold is not selected. Select the ore hold."
                        (case inventoryWindow |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                DescribeBranch "I do not see the active ship in the inventory." askForHelpToGetUnstuck

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
                                        DescribeBranch "I do not see the ore hold under the active ship in the inventory."
                                            (case activeShipTreeEntry.toggleBtn of
                                                Nothing ->
                                                    DescribeBranch "I do not see the toggle button to expand the active ship tree entry."
                                                        askForHelpToGetUnstuck

                                                Just toggleBtn ->
                                                    EndDecisionPath
                                                        (actWithoutFurtherReadings
                                                            ( "Click the toggle button to expand."
                                                            , [ toggleBtn |> clickOnUIElement MouseButtonLeft ]
                                                            )
                                                        )
                                            )

                                    Just oreHoldTreeEntry ->
                                        EndDecisionPath
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
                    DescribeBranch "Locking target is in progress, wait for completion." waitForProgressInGame

                else
                    DescribeBranch "Object is in range. Lock target."
                        (lockTargetFromOverviewEntry overviewEntry)

            else
                DescribeBranch ("Object is not in range (" ++ (distanceInMeters |> String.fromInt) ++ " meters away). Approach.")
                    (if shipManeuverIsApproaching readingFromGameClient then
                        DescribeBranch "I see we already approach." waitForProgressInGame

                     else
                        EndDecisionPath
                            (actStartingWithRightClickOnOverviewEntry
                                overviewEntry
                                [ MenuEntryWithTextContaining "approach" ]
                            )
                    )

        Err error ->
            DescribeBranch ("Failed to read the distance: " ++ error) askForHelpToGetUnstuck


lockTargetFromOverviewEntry : OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry =
    DescribeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
        (EndDecisionPath
            (actStartingWithRightClickOnOverviewEntry overviewEntry
                [ MenuEntryWithTextEqual "Lock target" ]
            )
        )


dockToStationMatchingNameSeenInInfoPanel : { stationNameFromInfoPanel : String } -> ReadingFromGameClient -> DecisionPathNode
dockToStationMatchingNameSeenInInfoPanel { stationNameFromInfoPanel } =
    dockToStationUsingSurroundingsButtonMenu
        ( "Click on menu entry representing the station '" ++ stationNameFromInfoPanel ++ "'."
        , List.filter (menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel)
            >> List.head
        )


dockToStationUsingSurroundingsButtonMenu :
    ( String, List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry )
    -> ReadingFromGameClient
    -> DecisionPathNode
dockToStationUsingSurroundingsButtonMenu ( describeChooseStation, chooseStationMenuEntry ) =
    useContextMenuOnListSurroundingsButton
        [ MenuEntryWithTextContaining "stations"
        , MenuEntryWithCustomChoice { describeChoice = describeChooseStation, chooseEntry = chooseStationMenuEntry }
        , MenuEntryWithTextContaining "dock"
        ]


warpToMiningSite : ReadingFromGameClient -> DecisionPathNode
warpToMiningSite readingFromGameClient =
    readingFromGameClient
        |> useContextMenuOnListSurroundingsButton
            [ MenuEntryWithTextContaining "asteroid belts"
            , MenuEntryWithCustomChoice
                { describeChoice = "random entry"
                , chooseEntry = listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient readingFromGameClient)
                }
            , MenuEntryWithTextContaining "Warp to Within"
            , MenuEntryWithTextContaining "Within 0 m"
            ]


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
        ( "Pick random station.", listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient readingFromGameClient) )
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
                                (DescribeBranch "Launch drones"
                                    (EndDecisionPath
                                        (useContextMenuCascade
                                            ( "drones group.", droneGroupInBay.header.uiNode )
                                            [ MenuEntryWithTextContaining "Launch drone" ]
                                        )
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
                        (DescribeBranch "I see there are drones in local space. Return those to bay."
                            (EndDecisionPath
                                (useContextMenuCascade
                                    ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                    [ MenuEntryWithTextContaining "Return to drone bay" ]
                                )
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
                EndDecisionPath
                    (actWithoutFurtherReadings
                        ( "Read tooltip for module button"
                        , [ VolatileHostInterface.MouseMoveTo
                                { location = moduleButtonWithoutMemoryOfTooltip.uiNode.totalDisplayRegion |> centerFromDisplayRegion }
                          ]
                        )
                    )
            )


actWithoutFurtherReadings : ( String, List VolatileHostInterface.EffectOnWindowStructure ) -> EndDecisionPathStructure
actWithoutFurtherReadings actionsAlreadyDecided =
    Act { actionsAlreadyDecided = actionsAlreadyDecided, actionsDependingOnNewReadings = [] }


actStartingWithRightClickOnOverviewEntry :
    OverviewWindowEntry
    -> List ContextMenuCascadeStage
    -> EndDecisionPathStructure
actStartingWithRightClickOnOverviewEntry overviewEntry contextMenuStages =
    useContextMenuCascade
        ( "overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'.", overviewEntry.uiNode )
        contextMenuStages


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
                            DescribeBranch "I see no overview window, wait until undocking completed." waitForProgressInGame

                        CanSee overviewWindow ->
                            branchIfUndockingComplete
                                { shipUI = shipUI, overviewWindow = overviewWindow }
                    )


useContextMenuOnListSurroundingsButton : List ContextMenuCascadeStage -> ReadingFromGameClient -> DecisionPathNode
useContextMenuOnListSurroundingsButton contextMenuCascadeStages readingFromGameClient =
    case readingFromGameClient.infoPanelContainer |> maybeVisibleAndThen .infoPanelLocationInfo of
        CanNotSeeIt ->
            DescribeBranch "I do not see the location info panel." askForHelpToGetUnstuck

        CanSee infoPanelLocationInfo ->
            EndDecisionPath
                (useContextMenuCascade
                    ( "surroundings button", infoPanelLocationInfo.listSurroundingsButton )
                    contextMenuCascadeStages
                )


waitForProgressInGame : DecisionPathNode
waitForProgressInGame =
    EndDecisionPath Wait


askForHelpToGetUnstuck : DecisionPathNode
askForHelpToGetUnstuck =
    DescribeBranch "I am stuck here and need help to continue." (EndDecisionPath Wait)


initState : State
initState =
    EveOnline.AppFramework.initState
        { programState = Nothing
        , botMemory =
            { lastDockedStationNameFromInfoPanel = Nothing
            , timesUnloaded = 0
            , volumeUnloadedCubicMeters = 0
            , lastUsedCapacityInOreHold = Nothing
            , shipModules = EveOnline.AppFramework.initShipModulesMemory
            }
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = parseBotSettings
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            let
                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory readingFromGameClient

                decisionContext =
                    { eventContext = eventContext
                    , memory = botMemory
                    , readingFromGameClient = readingFromGameClient
                    }

                programStateIfEvalDecisionTreeNew =
                    let
                        originalDecision =
                            decideNextAction decisionContext

                        originalRemainingActions =
                            case unpackToDecisionStagesDescriptionsAndLeaf originalDecision |> Tuple.second of
                                Wait ->
                                    []

                                Act act ->
                                    (act.actionsAlreadyDecided |> Tuple.mapSecond (Just >> always))
                                        :: act.actionsDependingOnNewReadings
                    in
                    { originalDecision = originalDecision, remainingActions = originalRemainingActions }

                programStateToContinue =
                    stateBefore.programState
                        |> Maybe.andThen
                            (\previousProgramState ->
                                if 0 < (previousProgramState.remainingActions |> List.length) then
                                    Just previousProgramState

                                else
                                    Nothing
                            )
                        |> Maybe.withDefault programStateIfEvalDecisionTreeNew

                ( originalDecisionStagesDescriptions, _ ) =
                    unpackToDecisionStagesDescriptionsAndLeaf programStateToContinue.originalDecision

                ( currentStepDescription, effectsOnGameClientWindow, programState ) =
                    case programStateToContinue.remainingActions of
                        [] ->
                            ( "Wait", [], Nothing )

                        ( nextActionDescription, nextActionEffectFromGameClient ) :: remainingActions ->
                            case readingFromGameClient |> nextActionEffectFromGameClient of
                                Nothing ->
                                    ( "Failed step: " ++ nextActionDescription, [], Nothing )

                                Just effects ->
                                    ( nextActionDescription
                                    , effects
                                    , Just { programStateToContinue | remainingActions = remainingActions }
                                    )

                effectsRequests =
                    effectsOnGameClientWindow |> List.map EveOnline.AppFramework.EffectOnGameClientWindow

                describeActivity =
                    (originalDecisionStagesDescriptions ++ [ currentStepDescription ])
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"

                statusMessage =
                    [ describeStateForMonitoring readingFromGameClient botMemory, describeActivity ]
                        |> String.join "\n"
            in
            ( { stateBefore | botMemory = botMemory, programState = programState }
            , EveOnline.AppFramework.ContinueSession
                { effects = effectsRequests
                , millisecondsToNextReadingFromGame = (decisionContext |> botSettingsFromDecisionContext).botStepDelayMilliseconds
                , statusDescriptionText = statusMessage
                }
            )


describeStateForMonitoring : ReadingFromGameClient -> BotMemory -> String
describeStateForMonitoring readingFromGameClient botMemory =
    let
        describeSessionPerformance =
            [ ( "times unloaded", botMemory.timesUnloaded )
            , ( "volume unloaded / m³", botMemory.volumeUnloadedCubicMeters )
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


integrateCurrentReadingsIntoBotMemory : ReadingFromGameClient -> BotMemory -> BotMemory
integrateCurrentReadingsIntoBotMemory currentReading botMemoryBefore =
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


unpackToDecisionStagesDescriptionsAndLeaf : DecisionPathNode -> ( List String, EndDecisionPathStructure )
unpackToDecisionStagesDescriptionsAndLeaf node =
    case node of
        EndDecisionPath leaf ->
            ( [], leaf )

        DescribeBranch branchDescription childNode ->
            let
                ( childDecisionsDescriptions, leaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf childNode
            in
            ( branchDescription :: childDecisionsDescriptions, leaf )


activeShipTreeEntryFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
activeShipTreeEntryFromInventoryWindow =
    .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


type ContextMenuCascadeStage
    = MenuEntryWithTextContaining String
    | MenuEntryWithTextEqual String
    | MenuEntryWithCustomChoice { describeChoice : String, chooseEntry : List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry }


useContextMenuCascade : ( String, UIElement ) -> List ContextMenuCascadeStage -> EndDecisionPathStructure
useContextMenuCascade ( initialUIElementName, initialUIElement ) stages =
    Act
        { actionsAlreadyDecided =
            ( "Open context menu on " ++ initialUIElementName
            , [ initialUIElement |> clickOnUIElement MouseButtonRight
              ]
            )
        , actionsDependingOnNewReadings = stages |> List.map actionForContextMenuCascadeStage
        }


actionForContextMenuCascadeStage : ContextMenuCascadeStage -> ( String, ReadingFromGameClient -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
actionForContextMenuCascadeStage stage =
    let
        ( describeChoice, chooseEntry ) =
            case stage of
                MenuEntryWithTextContaining textToSearch ->
                    ( "with text containing '" ++ textToSearch ++ "'"
                    , List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
                        >> List.sortBy (.text >> String.trim >> String.length)
                        >> List.head
                    )

                MenuEntryWithTextEqual textToSearch ->
                    ( "with text equal '" ++ textToSearch ++ "'"
                    , List.filter (.text >> String.trim >> String.toLower >> (==) (textToSearch |> String.toLower))
                        >> List.head
                    )

                MenuEntryWithCustomChoice custom ->
                    ( "'" ++ custom.describeChoice ++ "'"
                    , custom.chooseEntry
                    )
    in
    ( "Click menu entry " ++ describeChoice ++ "."
    , lastContextMenuOrSubmenu
        >> Maybe.andThen (.entries >> chooseEntry)
        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
    )


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromLocationInfoPanel : String -> EveOnline.ParseUserInterface.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


lastContextMenuOrSubmenu : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


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


clickOnUIElement : MouseButton -> UIElement -> VolatileHostInterface.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromDisplayRegion)


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

{- EVE Online mining bot version 2023-03-04

   The bot warps to an asteroid belt, mines there until the mining hold is full, and then docks at a station or structure to unload the ore. It then repeats this cycle until you stop it.
   If no station name or structure name is given with the bot-settings, the bot docks again at the station where it was last docked.

   Setup instructions for the EVE Online client:

   + Set the UI language to English.
   + In the ship UI in the 'Options' menu, tick the checkbox for 'Display Module Tooltips'.
   + In Overview window, make asteroids visible.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + Open one inventory window.
   + If you want to use drones for defense against rats, place them in the drone bay, and open the 'Drones' window.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `unload-station-name` : Name of a station to dock to when the mining hold is full.
   + `unload-structure-name` : Name of a structure to dock to when the mining hold is full.
   + `activate-module-always` : Text found in tooltips of ship modules that should always be active. For example: "shield hardener".
   + `hide-when-neutral-in-local` : Should we hide when a neutral or hostile pilot appears in the local chat? The only supported values are `no` and `yes`.
   + `unload-fleet-hangar-percent` : This will make the bot to unload the mining hold at least XX percent full to the fleet hangar, you must be in a fleet with an orca or a rorqual and the fleet hangar must be visible within the inventory window.
   + `dock-when-without-drones` : This will make the bot dock when it's out of drones. The only supported values are `no` and `yes`.
   + `repair-before-undocking` : Repair the ship at the station before undocking. The only supported values are `no` and `yes`.

   When using more than one setting, start a new line for each setting in the text input field.
   Here is an example of a complete settings string:

   ```
   unload-station-name = Noghere VII - Moon 15
   activate-module-always = shield hardener
   activate-module-always = afterburner
   ```

   To learn more about the mining bot, see <https://to.botlab.org/guide/app/eve-online-mining-bot>

-}
{-
   catalog-tags:eve-online,mining
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (listElementAtWrappedIndex, stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.BotFramework
    exposing
        ( ModuleButtonTooltipMemory
        , ReadingFromGameClient
        , SeeUndockingComplete
        , ShipModulesMemory
        , UIElement
        , doEffectsClickModuleButton
        , localChatWindowFromUserInterface
        , menuCascadeCompleted
        , mouseClickOnUIElement
        , shipUIIndicatesShipIsWarpingOrJumping
        , useMenuEntryInLastContextMenuInCascade
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        , useMenuEntryWithTextEqual
        , useRandomMenuEntry
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , EndDecisionPathStructure(..)
        , askForHelpToGetUnstuck
        , branchDependingOnDockedOrInSpace
        , decideActionForCurrentStep
        , ensureInfoPanelLocationInfoIsExpanded
        , useContextMenuCascade
        , useContextMenuCascadeOnListSurroundingsButton
        , useContextMenuCascadeOnOverviewEntry
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface
    exposing
        ( OverviewWindowEntry
        , UITreeNodeWithDisplayRegion
        , centerFromDisplayRegion
        )
import Regex


{-| Sources for the defaults:

  - <https://forum.botlab.org/t/mining-bot-wont-approach/3162>

-}
defaultBotSettings : BotSettings
defaultBotSettings =
    { runAwayShieldHitpointsThresholdPercent = 70
    , unloadStationName = Nothing
    , unloadStructureName = Nothing
    , unloadFleetHangarPercent = -1
    , unloadMiningHoldPercent = 99
    , activateModulesAlways = []
    , hideWhenNeutralInLocal = Nothing
    , dockWhenWithoutDrones = Nothing
    , repairBeforeUndocking = Nothing
    , targetingRange = 8000
    , miningModuleRange = 5000
    , botStepDelayMilliseconds = 1300
    , selectInstancePilotName = Nothing
    , includeAsteroidPatterns = []
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "run-away-shield-hitpoints-threshold-percent"
           , AppSettings.valueTypeInteger (\threshold settings -> { settings | runAwayShieldHitpointsThresholdPercent = threshold })
           )
         , ( "unload-station-name"
           , AppSettings.valueTypeString (\stationName settings -> { settings | unloadStationName = Just stationName })
           )
         , ( "unload-structure-name"
           , AppSettings.valueTypeString (\structureName settings -> { settings | unloadStructureName = Just structureName })
           )
         , ( "unload-fleet-hangar-percent"
           , AppSettings.valueTypeInteger (\fleetHangarPercent settings -> { settings | unloadFleetHangarPercent = fleetHangarPercent })
           )
         , ( "unload-mining-hold-percent"
           , AppSettings.valueTypeInteger (\percent settings -> { settings | unloadMiningHoldPercent = percent })
           )
         , ( "activate-module-always"
           , AppSettings.valueTypeString (\moduleName settings -> { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways })
           )
         , ( "hide-when-neutral-in-local"
           , AppSettings.valueTypeYesOrNo
                (\hide settings -> { settings | hideWhenNeutralInLocal = Just hide })
           )
         , ( "dock-when-without-drones"
           , AppSettings.valueTypeYesOrNo
                (\without settings -> { settings | dockWhenWithoutDrones = Just without })
           )
         , ( "repair-before-undocking"
           , AppSettings.valueTypeYesOrNo
                (\repair settings -> { settings | repairBeforeUndocking = Just repair })
           )
         , ( "targeting-range"
           , AppSettings.valueTypeInteger (\range settings -> { settings | targetingRange = range })
           )
         , ( "mining-module-range"
           , AppSettings.valueTypeInteger (\range settings -> { settings | miningModuleRange = range })
           )
         , ( "select-instance-pilot-name"
           , AppSettings.valueTypeString (\pilotName settings -> { settings | selectInstancePilotName = Just pilotName })
           )
         , ( "bot-step-delay"
           , AppSettings.valueTypeInteger (\delay settings -> { settings | botStepDelayMilliseconds = delay })
           )
         , ( "include-asteroid-pattern"
           , AppSettings.valueTypeString
                (\pattern settings ->
                    { settings | includeAsteroidPatterns = pattern :: settings.includeAsteroidPatterns }
                )
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


dockWhenDroneWindowInvisibleCount : Int
dockWhenDroneWindowInvisibleCount =
    4


type alias BotSettings =
    { runAwayShieldHitpointsThresholdPercent : Int
    , unloadStationName : Maybe String
    , unloadStructureName : Maybe String
    , unloadFleetHangarPercent : Int
    , unloadMiningHoldPercent : Int
    , activateModulesAlways : List String
    , hideWhenNeutralInLocal : Maybe AppSettings.YesOrNo
    , dockWhenWithoutDrones : Maybe AppSettings.YesOrNo
    , repairBeforeUndocking : Maybe AppSettings.YesOrNo
    , targetingRange : Int
    , miningModuleRange : Int
    , botStepDelayMilliseconds : Int
    , selectInstancePilotName : Maybe String
    , includeAsteroidPatterns : List String
    }


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    , timesUnloaded : Int
    , volumeUnloadedCubicMeters : Int
    , lastUsedCapacityInMiningHold : Maybe Int
    , shipModules : ShipModulesMemory
    , lastReadingsInSpaceDronesWindowWasVisible : List Bool
    }


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


type alias State =
    EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory


miningBotDecisionRoot : BotDecisionContext -> DecisionPathNode
miningBotDecisionRoot context =
    miningBotDecisionRootBeforeApplyingSettings context
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase
            context.eventContext.botSettings.botStepDelayMilliseconds


{-| A first outline of the decision tree for a mining bot came from <https://forum.botlab.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
miningBotDecisionRootBeforeApplyingSettings : BotDecisionContext -> DecisionPathNode
miningBotDecisionRootBeforeApplyingSettings context =
    generalSetupInUserInterface
        context.readingFromGameClient
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                { ifDocked =
                    ensureMiningHoldIsSelectedInInventoryWindow
                        context.readingFromGameClient
                        (dockedWithMiningHoldSelected context)
                , ifSeeShipUI =
                    returnDronesAndRunAwayIfHitpointsAreTooLowOrWithoutDrones context
                , ifUndockingComplete =
                    \seeUndockingComplete ->
                        continueIfShouldHide
                            { ifShouldHide =
                                returnDronesToBay context
                                    |> Maybe.withDefault (dockToUnloadOre context)
                            }
                            context
                            |> Maybe.withDefault
                                (ensureUserEnabledNameColumnInOverview
                                    { ifEnabled =
                                        ensureMiningHoldIsSelectedInInventoryWindow
                                            context.readingFromGameClient
                                            (inSpaceWithMiningHoldSelected context seeUndockingComplete)
                                    , ifDisabled =
                                        describeBranch "Please configure the overview to show objects names." askForHelpToGetUnstuck
                                    }
                                    seeUndockingComplete
                                )
                }
                context.readingFromGameClient
            )


continueIfShouldHide : { ifShouldHide : DecisionPathNode } -> BotDecisionContext -> Maybe DecisionPathNode
continueIfShouldHide config context =
    case
        context.eventContext |> EveOnline.BotFramework.secondsToSessionEnd |> Maybe.andThen (nothingFromIntIfGreaterThan 200)
    of
        Just secondsToSessionEnd ->
            Just
                (describeBranch ("Session ends in " ++ (secondsToSessionEnd |> String.fromInt) ++ " seconds.")
                    config.ifShouldHide
                )

        Nothing ->
            if not (context |> shouldHideWhenNeutralInLocal) then
                Nothing

            else
                case context.readingFromGameClient |> localChatWindowFromUserInterface of
                    Nothing ->
                        Just (describeBranch "I don't see the local chat window." askForHelpToGetUnstuck)

                    Just localChatWindow ->
                        let
                            chatUserHasGoodStanding chatUser =
                                goodStandingPatterns
                                    |> List.any
                                        (\goodStandingPattern ->
                                            chatUser.standingIconHint
                                                |> Maybe.map (stringContainsIgnoringCase goodStandingPattern)
                                                |> Maybe.withDefault False
                                        )

                            subsetOfUsersWithNoGoodStanding =
                                localChatWindow.userlist
                                    |> Maybe.map .visibleUsers
                                    |> Maybe.withDefault []
                                    |> List.filter (chatUserHasGoodStanding >> not)
                        in
                        if 1 < (subsetOfUsersWithNoGoodStanding |> List.length) then
                            Just (describeBranch "There is an enemy or neutral in local chat." config.ifShouldHide)

                        else
                            Nothing


shouldHideWhenNeutralInLocal : BotDecisionContext -> Bool
shouldHideWhenNeutralInLocal context =
    case context.eventContext.botSettings.hideWhenNeutralInLocal of
        Just AppSettings.No ->
            False

        Just AppSettings.Yes ->
            True

        Nothing ->
            (context.readingFromGameClient.infoPanelContainer
                |> Maybe.andThen .infoPanelLocationInfo
                |> Maybe.andThen .securityStatusPercent
                |> Maybe.withDefault 0
            )
                < 50


shouldDockWhenWithoutDrones : BotDecisionContext -> Bool
shouldDockWhenWithoutDrones context =
    context.eventContext.botSettings.dockWhenWithoutDrones == Just AppSettings.Yes


shouldRepairBeforeUndocking : BotDecisionContext -> Bool
shouldRepairBeforeUndocking context =
    context.eventContext.botSettings.repairBeforeUndocking == Just AppSettings.Yes


returnDronesAndRunAwayIfHitpointsAreTooLowOrWithoutDrones : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode
returnDronesAndRunAwayIfHitpointsAreTooLowOrWithoutDrones context shipUI =
    let
        returnDronesShieldHitpointsThresholdPercent =
            context.eventContext.botSettings.runAwayShieldHitpointsThresholdPercent + 5

        runAwayWithDescription =
            describeBranch
                ("Shield hitpoints are at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%. Run away.")
                (runAway context)
    in
    if shipUI.hitpointsPercent.shield < context.eventContext.botSettings.runAwayShieldHitpointsThresholdPercent then
        Just runAwayWithDescription

    else if shipUI.hitpointsPercent.shield < returnDronesShieldHitpointsThresholdPercent then
        returnDronesToBay context
            |> Maybe.map
                (describeBranch
                    ("Shield hitpoints are below " ++ (returnDronesShieldHitpointsThresholdPercent |> String.fromInt) ++ "%. Return drones.")
                )
            |> Maybe.withDefault runAwayWithDescription
            |> Just

    else if
        (context |> shouldDockWhenWithoutDrones)
            && shouldDockBecauseDroneWindowWasInvisibleTooLong context.memory
    then
        Just
            (describeBranch "I don't see the drone window, are we out of drones? configured to run away when without a drone. Run to the station!" (dockToUnloadOre context))

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
                            describeBranch
                                ("Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'.")
                                (decideActionForCurrentStep
                                    (mouseClickOnUIElement MouseButtonLeft buttonToUse.uiNode)
                                )
                    )
            )


dockedWithMiningHoldSelected : BotDecisionContext -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
dockedWithMiningHoldSelected context inventoryWindowWithMiningHoldSelected =
    case inventoryWindowWithMiningHoldSelected |> itemHangarFromInventoryWindow |> Maybe.map .uiNode of
        Nothing ->
            describeBranch "I do not see the item hangar in the inventory." askForHelpToGetUnstuck

        Just itemHangar ->
            case inventoryWindowWithMiningHoldSelected |> selectedContainerFirstItemFromInventoryWindow of
                Nothing ->
                    describeBranch "I see no item in the mining hold. Checking if we should repaired ship and undock."
                        (if
                            (context |> shouldDockWhenWithoutDrones)
                                && shouldDockBecauseDroneWindowWasInvisibleTooLong context.memory
                         then
                            describeBranch "Stay docked because I didn't see the drone window. Are we out of drones?"
                                askForHelpToGetUnstuck

                         else
                            continueIfShouldHide
                                { ifShouldHide =
                                    describeBranch "Stay docked because we should hide." waitForProgressInGame
                                }
                                context
                                |> Maybe.withDefault
                                    (checkAndRepairBeforeUndockingUsingContextMenu context inventoryWindowWithMiningHoldSelected
                                        |> Maybe.withDefault
                                            (undockUsingStationWindow context
                                                { ifCannotReachButton =
                                                    describeBranch "Undock using context menu"
                                                        (undockUsingContextMenu context
                                                            { inventoryWindowWithMiningHoldSelected = inventoryWindowWithMiningHoldSelected }
                                                        )
                                                }
                                            )
                                    )
                        )

                Just itemInInventory ->
                    describeBranch "I see at least one item in the mining hold. Move this to the item hangar."
                        (describeBranch "Drag and drop."
                            (decideActionForCurrentStep
                                (EffectOnWindow.effectsForDragAndDrop
                                    { startLocation = itemInInventory.totalDisplayRegionVisible |> centerFromDisplayRegion
                                    , endLocation = itemHangar.totalDisplayRegionVisible |> centerFromDisplayRegion
                                    , mouseButton = MouseButtonLeft
                                    }
                                )
                            )
                        )


inSpaceWithMiningHoldSelectedWithFleetHangar : BotDecisionContext -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
inSpaceWithMiningHoldSelectedWithFleetHangar _ inventoryWindowWithMiningHoldSelected =
    case
        inventoryWindowWithMiningHoldSelected |> fleetHangarFromInventoryWindow |> Maybe.map .uiNode
    of
        Nothing ->
            describeBranch "I do not see the fleet hangar in the inventory." askForHelpToGetUnstuck

        Just fleetHangarFromInventory ->
            case inventoryWindowWithMiningHoldSelected |> selectedContainerFirstItemFromInventoryWindow of
                Nothing ->
                    describeBranch "I see no item in the mining hold. Click the tree entry representing the fleet Hangar."
                        (decideActionForCurrentStep
                            (mouseClickOnUIElement MouseButtonLeft fleetHangarFromInventory)
                        )

                Just itemInInventory ->
                    describeBranch "I see at least one item in the mining hold. Move this to the fleet hangar."
                        (describeBranch "Drag and drop."
                            (decideActionForCurrentStep
                                (EffectOnWindow.effectsForDragAndDrop
                                    { startLocation = itemInInventory.totalDisplayRegionVisible |> centerFromDisplayRegion
                                    , endLocation = fleetHangarFromInventory.totalDisplayRegionVisible |> centerFromDisplayRegion
                                    , mouseButton = MouseButtonLeft
                                    }
                                )
                            )
                        )


undockUsingStationWindow :
    BotDecisionContext
    -> { ifCannotReachButton : DecisionPathNode }
    -> DecisionPathNode
undockUsingStationWindow context { ifCannotReachButton } =
    case context.readingFromGameClient.stationWindow of
        Nothing ->
            describeBranch "I do not see the station window." ifCannotReachButton

        Just stationWindow ->
            case stationWindow.undockButton of
                Nothing ->
                    case stationWindow.abortUndockButton of
                        Nothing ->
                            describeBranch "I do not see the undock button." ifCannotReachButton

                        Just _ ->
                            describeBranch "I see we are already undocking." waitForProgressInGame

                Just undockButton ->
                    describeBranch "Click on the button to undock."
                        (decideActionForCurrentStep
                            (mouseClickOnUIElement MouseButtonLeft undockButton)
                        )


undockUsingContextMenu :
    BotDecisionContext
    -> { inventoryWindowWithMiningHoldSelected : EveOnline.ParseUserInterface.InventoryWindow }
    -> DecisionPathNode
undockUsingContextMenu context { inventoryWindowWithMiningHoldSelected } =
    case inventoryWindowWithMiningHoldSelected |> activeShipTreeEntryFromInventoryWindow of
        Nothing ->
            describeBranch "I do not see the active ship in the inventory window." askForHelpToGetUnstuck

        Just activeShipEntry ->
            useContextMenuCascade
                ( "active ship", activeShipEntry.uiNode )
                (useMenuEntryWithTextContainingFirstOf [ "undock from station" ] menuCascadeCompleted)
                context


checkAndRepairBeforeUndockingUsingContextMenu : BotDecisionContext -> EveOnline.ParseUserInterface.InventoryWindow -> Maybe DecisionPathNode
checkAndRepairBeforeUndockingUsingContextMenu context inventoryWindowWithMiningHoldSelected =
    if not (context |> shouldRepairBeforeUndocking) then
        Nothing

    else
        case context.readingFromGameClient.repairShopWindow of
            Nothing ->
                case inventoryWindowWithMiningHoldSelected |> activeShipTreeEntryFromInventoryWindow of
                    Nothing ->
                        Just (describeBranch "I do not see the active ship in the inventory window." askForHelpToGetUnstuck)

                    Just activeShipEntry ->
                        Just
                            (useContextMenuCascade
                                ( "active ship", activeShipEntry.uiNode )
                                (useMenuEntryWithTextContaining "get repair quote" menuCascadeCompleted)
                                context
                            )

            Just repairShopWindow ->
                let
                    buttonUsed =
                        .mainText
                            >> Maybe.map
                                (String.trim
                                    >> String.toLower
                                    >> (\buttonText -> [ "repair all" ] |> List.member buttonText)
                                )
                            >> Maybe.withDefault False
                in
                case repairShopWindow.items |> List.head of
                    Nothing ->
                        Nothing

                    Just itemsRepair ->
                        Just
                            (describeBranch "It has items to repair, selecting the first item."
                                (case repairShopWindow.buttons |> List.filter buttonUsed |> List.head of
                                    Just btnRepairAll ->
                                        describeBranch "I see the repair all button, i'm going to click it."
                                            (decideActionForCurrentStep
                                                ([ mouseClickOnUIElement MouseButtonLeft itemsRepair
                                                 , mouseClickOnUIElement MouseButtonLeft btnRepairAll.uiNode
                                                 ]
                                                    |> List.concat
                                                )
                                            )

                                    Nothing ->
                                        describeBranch "It has items to repair, but I do not see the repair all button." askForHelpToGetUnstuck
                                )
                            )


inSpaceWithMiningHoldSelected : BotDecisionContext -> SeeUndockingComplete -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
inSpaceWithMiningHoldSelected context seeUndockingComplete inventoryWindowWithMiningHoldSelected =
    if seeUndockingComplete.shipUI |> shipUIIndicatesShipIsWarpingOrJumping then
        describeBranch "I see we are warping."
            ([ returnDronesToBay context
             , readShipUIModuleButtonTooltips context
             ]
                |> List.filterMap identity
                |> List.head
                |> Maybe.withDefault waitForProgressInGame
            )

    else
        case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> .isActive >> Maybe.withDefault False >> not) |> List.head of
            Just ( inactiveModuleMatchingText, inactiveModule ) ->
                describeBranch ("I see inactive module '" ++ inactiveModuleMatchingText ++ "' to activate always. Activate it.")
                    (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)

            Nothing ->
                case inventoryWindowWithMiningHoldSelected |> capacityGaugeUsedPercent of
                    Nothing ->
                        describeBranch "I do not see the mining hold capacity gauge." askForHelpToGetUnstuck

                    Just fillPercent ->
                        let
                            describeThresholdToUnload =
                                (context.eventContext.botSettings.unloadMiningHoldPercent |> String.fromInt) ++ "%"

                            describeThresholdToUnloadFleetHangar =
                                (context.eventContext.botSettings.unloadFleetHangarPercent |> String.fromInt) ++ "%"

                            knownMiningModules =
                                knownMiningModulesFromContext context
                        in
                        if context.eventContext.botSettings.unloadMiningHoldPercent <= fillPercent then
                            describeBranch ("The mining hold is filled at least " ++ describeThresholdToUnload ++ ". Unload the ore.")
                                (returnDronesToBay context
                                    |> Maybe.withDefault (dockToUnloadOre context)
                                )

                        else if context.eventContext.botSettings.unloadFleetHangarPercent > 0 && context.eventContext.botSettings.unloadFleetHangarPercent <= fillPercent then
                            describeBranch ("The mining hold is filled at least " ++ describeThresholdToUnloadFleetHangar ++ ". Unload the ore on fleet hangar.")
                                (ensureMiningHoldIsSelectedInInventoryWindow
                                    context.readingFromGameClient
                                    (inSpaceWithMiningHoldSelectedWithFleetHangar context)
                                )

                        else
                            describeBranch ("The mining hold is not yet filled " ++ describeThresholdToUnload ++ ". Get more ore.")
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
                                                    (case knownMiningModules |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                                        Nothing ->
                                                            describeBranch
                                                                (if knownMiningModules == [] then
                                                                    "Found no mining modules so far."

                                                                 else
                                                                    "All known mining modules found so far are active."
                                                                )
                                                                (readShipUIModuleButtonTooltips context
                                                                    |> Maybe.withDefault waitForProgressInGame
                                                                )

                                                        Just inactiveModule ->
                                                            describeBranch "I see an inactive mining module. Activate it."
                                                                (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)
                                                    )
                                                )
                                )


unlockTargetsNotForMining : BotDecisionContext -> Maybe DecisionPathNode
unlockTargetsNotForMining context =
    let
        targetsToUnlock =
            context.readingFromGameClient.targets
                |> List.filter (.textsTopToBottom >> List.any (stringContainsIgnoringCase "asteroid") >> not)
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
                        context
                    )
            )


travelToMiningSiteAndLaunchDronesAndTargetAsteroid : BotDecisionContext -> DecisionPathNode
travelToMiningSiteAndLaunchDronesAndTargetAsteroid context =
    let
        continueWithWarpToMiningSite =
            returnDronesToBay context
                |> Maybe.withDefault (warpToMiningSite context)
    in
    case context.readingFromGameClient |> clickableAsteroidsFromOverviewWindow of
        [] ->
            describeBranch "I see no clickable asteroid in the overview. Warp to mining site."
                continueWithWarpToMiningSite

        clickableAsteroids ->
            case
                clickableAsteroids
                    |> List.filter (asteroidOverviewEntryMatchesSettings context.eventContext.botSettings)
                    |> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
                    |> List.head
            of
                Nothing ->
                    describeBranch
                        ("I see "
                            ++ String.fromInt (List.length clickableAsteroids)
                            ++ "clickable asteroids in the overview. But none of these matches the filter from settings. Warp to mining site."
                        )
                        continueWithWarpToMiningSite

                Just asteroidInOverview ->
                    describeBranch ("Choosing asteroid '" ++ (asteroidInOverview.objectName |> Maybe.withDefault "Nothing") ++ "'")
                        (warpToOverviewEntryIfFarEnough context asteroidInOverview
                            |> Maybe.withDefault
                                (launchDrones context
                                    |> Maybe.withDefault
                                        (lockTargetFromOverviewEntryAndEnsureIsInRange
                                            context
                                            (min context.eventContext.botSettings.targetingRange
                                                context.eventContext.botSettings.miningModuleRange
                                            )
                                            asteroidInOverview
                                        )
                                )
                        )


warpToOverviewEntryIfFarEnough : BotDecisionContext -> OverviewWindowEntry -> Maybe DecisionPathNode
warpToOverviewEntryIfFarEnough context destinationOverviewEntry =
    case destinationOverviewEntry.objectDistanceInMeters of
        Ok distanceInMeters ->
            if distanceInMeters <= 150000 then
                Nothing

            else
                Just
                    (describeBranch "Far enough to use Warp"
                        (returnDronesToBay context
                            |> Maybe.withDefault
                                (useContextMenuCascadeOnOverviewEntry
                                    (useMenuEntryWithTextContaining "Warp to Within"
                                        (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
                                    )
                                    destinationOverviewEntry
                                    context
                                )
                        )
                    )

        Err error ->
            Just (describeBranch ("Failed to read the distance: " ++ error) askForHelpToGetUnstuck)


ensureMiningHoldIsSelectedInInventoryWindow : ReadingFromGameClient -> (EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode) -> DecisionPathNode
ensureMiningHoldIsSelectedInInventoryWindow readingFromGameClient continueWithInventoryWindow =
    case readingFromGameClient |> inventoryWindowWithMiningHoldSelectedFromGameClient of
        Just inventoryWindow ->
            continueWithInventoryWindow inventoryWindow

        Nothing ->
            case readingFromGameClient.inventoryWindows |> List.head of
                Nothing ->
                    describeBranch "I do not see an inventory window. Please open an inventory window." askForHelpToGetUnstuck

                Just inventoryWindow ->
                    describeBranch
                        "mining hold is not selected. Select the mining hold."
                        (case inventoryWindow |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                describeBranch "I do not see the active ship in the inventory." askForHelpToGetUnstuck

                            Just activeShipTreeEntry ->
                                let
                                    maybeMiningHoldTreeEntry =
                                        activeShipTreeEntry
                                            |> miningHoldFromInventoryWindowShipEntry
                                in
                                case maybeMiningHoldTreeEntry of
                                    Nothing ->
                                        describeBranch "I do not see the mining hold under the active ship in the inventory."
                                            (case activeShipTreeEntry.toggleBtn of
                                                Nothing ->
                                                    describeBranch "I do not see the toggle button to expand the active ship tree entry."
                                                        askForHelpToGetUnstuck

                                                Just toggleBtn ->
                                                    describeBranch "Click the toggle button to expand."
                                                        (decideActionForCurrentStep
                                                            (mouseClickOnUIElement MouseButtonLeft toggleBtn)
                                                        )
                                            )

                                    Just miningHoldTreeEntry ->
                                        describeBranch "Click the tree entry representing the mining hold."
                                            (decideActionForCurrentStep
                                                (mouseClickOnUIElement MouseButtonLeft miningHoldTreeEntry.uiNode)
                                            )
                        )


lockTargetFromOverviewEntryAndEnsureIsInRange : BotDecisionContext -> Int -> OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntryAndEnsureIsInRange context rangeInMeters overviewEntry =
    case overviewEntry.objectDistanceInMeters of
        Ok distanceInMeters ->
            if distanceInMeters <= rangeInMeters then
                if overviewEntry.commonIndications.targetedByMe || overviewEntry.commonIndications.targeting then
                    describeBranch "Locking target is in progress, wait for completion." waitForProgressInGame

                else
                    describeBranch "Object is in range. Lock target."
                        (lockTargetFromOverviewEntry overviewEntry context)

            else
                describeBranch ("Object is not in range (" ++ (distanceInMeters |> String.fromInt) ++ " meters away). Approach.")
                    (if shipManeuverIsApproaching context.readingFromGameClient then
                        describeBranch "I see we already approach." waitForProgressInGame

                     else
                        useContextMenuCascadeOnOverviewEntry
                            (useMenuEntryWithTextContaining "approach" menuCascadeCompleted)
                            overviewEntry
                            context
                    )

        Err error ->
            describeBranch ("Failed to read the distance: " ++ error) askForHelpToGetUnstuck


lockTargetFromOverviewEntry : OverviewWindowEntry -> BotDecisionContext -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry context =
    describeBranch
        ("Lock target from overview entry '"
            ++ (overviewEntry.objectName |> Maybe.withDefault "")
            ++ "' ("
            ++ (overviewEntry.objectDistance |> Maybe.withDefault "")
            ++ ")"
        )
        (useContextMenuCascadeOnOverviewEntry
            (useMenuEntryWithTextEqual "Lock target" menuCascadeCompleted)
            overviewEntry
            context
        )


dockToStationOrStructureWithMatchingName :
    { prioritizeStructures : Bool, nameFromSettingOrInfoPanel : String }
    -> BotDecisionContext
    -> DecisionPathNode
dockToStationOrStructureWithMatchingName { prioritizeStructures, nameFromSettingOrInfoPanel } context =
    let
        {-
           2023-01-11 Observation by Dean: Text in surroundings context menu entry sometimes wraps station name in XML tags:
           <color=#FF58A7BF>Niyabainen IV - M1 - Caldari Navy Assembly Plant</color>
        -}
        displayTextRepresentsMatchingStation =
            simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                >> String.contains (nameFromSettingOrInfoPanel |> simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry)

        matchingOverviewEntry =
            context.readingFromGameClient.overviewWindows
                |> List.concatMap .entries
                |> List.filter (.objectName >> Maybe.map displayTextRepresentsMatchingStation >> Maybe.withDefault False)
                |> List.head

        overviewWindowScrollControls =
            context.readingFromGameClient.overviewWindows
                |> List.filterMap .scrollControls
                |> List.head
    in
    matchingOverviewEntry
        |> Maybe.map
            (\entry ->
                EveOnline.BotFrameworkSeparatingMemory.useContextMenuCascadeOnOverviewEntry
                    (useMenuEntryWithTextContaining "dock" menuCascadeCompleted)
                    entry
                    context
            )
        |> Maybe.withDefault
            (overviewWindowScrollControls
                |> Maybe.andThen scrollDown
                |> Maybe.withDefault
                    (describeBranch "I do not see the station in the overview window. I use the menu from the surroundings button."
                        (dockToStationOrStructureUsingSurroundingsButtonMenu
                            { prioritizeStructures = prioritizeStructures
                            , describeChoice = "representing the station or structure '" ++ nameFromSettingOrInfoPanel ++ "'."
                            , chooseEntry =
                                List.filter (.text >> displayTextRepresentsMatchingStation) >> List.head
                            }
                            context
                        )
                    )
            )


scrollDown : EveOnline.ParseUserInterface.ScrollControls -> Maybe DecisionPathNode
scrollDown scrollControls =
    case scrollControls.scrollHandle of
        Nothing ->
            Nothing

        Just scrollHandle ->
            let
                scrollControlsTotalDisplayRegion =
                    scrollControls.uiNode.totalDisplayRegion

                scrollControlsBottom =
                    scrollControlsTotalDisplayRegion.y + scrollControlsTotalDisplayRegion.height

                freeHeightAtBottom =
                    scrollControlsBottom
                        - (scrollHandle.totalDisplayRegion.y + scrollHandle.totalDisplayRegion.height)
            in
            if 10 < freeHeightAtBottom then
                Just
                    (describeBranch "Click at scroll control bottom"
                        (decideActionForCurrentStep
                            (EffectOnWindow.effectsMouseClickAtLocation EffectOnWindow.MouseButtonLeft
                                { x = scrollControlsTotalDisplayRegion.x + 3
                                , y = scrollControlsBottom - 8
                                }
                                ++ [ EffectOnWindow.KeyDown EffectOnWindow.vkey_END
                                   , EffectOnWindow.KeyUp EffectOnWindow.vkey_END
                                   ]
                            )
                        )
                    )

            else
                Nothing


{-| Prepare a station name or structure name coming from bot-settings for comparing with menu entries.

  - The user could take the name from the info panel:
    The names sometimes differ between info panel and menu entries: 'Moon 7' can become 'M7'.

  - Do not distinguish between the comma and period characters:
    Besides the similar visual appearance, also because of the limitations of popular bot-settings parsing frameworks.
    The user can remove a comma or replace it with a full stop/period, whatever looks better.

-}
simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry : String -> String
simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry =
    String.toLower >> String.replace "moon " "m" >> String.replace "," "" >> String.replace "." "" >> String.trim


dockToStationOrStructureUsingSurroundingsButtonMenu :
    { prioritizeStructures : Bool
    , describeChoice : String
    , chooseEntry : List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry
    }
    -> BotDecisionContext
    -> DecisionPathNode
dockToStationOrStructureUsingSurroundingsButtonMenu { prioritizeStructures, describeChoice, chooseEntry } =
    useContextMenuCascadeOnListSurroundingsButton
        (useMenuEntryWithTextContainingFirstOf
            ([ "stations", "structures" ]
                |> (if prioritizeStructures then
                        List.reverse

                    else
                        identity
                   )
            )
            (useMenuEntryInLastContextMenuInCascade { describeChoice = describeChoice, chooseEntry = chooseEntry }
                (useMenuEntryWithTextContaining "dock" menuCascadeCompleted)
            )
        )


warpToMiningSite : BotDecisionContext -> DecisionPathNode
warpToMiningSite context =
    useContextMenuCascadeOnListSurroundingsButton
        (useMenuEntryWithTextContaining "asteroid belts"
            (useRandomMenuEntry (context.randomIntegers |> List.head |> Maybe.withDefault 0)
                (useMenuEntryWithTextContaining "Warp to Within"
                    (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
                )
            )
        )
        context


runAway : BotDecisionContext -> DecisionPathNode
runAway =
    dockToRandomStationOrStructure


dockToUnloadOre : BotDecisionContext -> DecisionPathNode
dockToUnloadOre context =
    case context.eventContext.botSettings.unloadStationName of
        Just unloadStationName ->
            dockToStationOrStructureWithMatchingName
                { prioritizeStructures = False, nameFromSettingOrInfoPanel = unloadStationName }
                context

        Nothing ->
            case context.eventContext.botSettings.unloadStructureName of
                Just unloadStructureName ->
                    dockToStationOrStructureWithMatchingName
                        { prioritizeStructures = True, nameFromSettingOrInfoPanel = unloadStructureName }
                        context

                Nothing ->
                    case context.memory.lastDockedStationNameFromInfoPanel of
                        Just unloadStationName ->
                            dockToStationOrStructureWithMatchingName
                                { prioritizeStructures = False, nameFromSettingOrInfoPanel = unloadStationName }
                                context

                        Nothing ->
                            describeBranch "At which station should I dock?. I was never docked in a station in this session." askForHelpToGetUnstuck


dockToRandomStationOrStructure : BotDecisionContext -> DecisionPathNode
dockToRandomStationOrStructure context =
    dockToStationOrStructureUsingSurroundingsButtonMenu
        { prioritizeStructures = False
        , describeChoice = "Pick random station"
        , chooseEntry = listElementAtWrappedIndex (context.randomIntegers |> List.head |> Maybe.withDefault 0)
        }
        context


launchDrones : BotDecisionContext -> Maybe DecisionPathNode
launchDrones context =
    context.readingFromGameClient.dronesWindow
        |> Maybe.andThen
            (\dronesWindow ->
                case ( dronesWindow.droneGroupInBay, dronesWindow.droneGroupInSpace ) of
                    ( Just droneGroupInBay, Just droneGroupInSpace ) ->
                        let
                            dronesInBayQuantity =
                                droneGroupInBay.header.quantityFromTitle
                                    |> Maybe.map .current
                                    |> Maybe.withDefault 0

                            dronesInSpaceQuantityCurrent =
                                droneGroupInSpace.header.quantityFromTitle
                                    |> Maybe.map .current
                                    |> Maybe.withDefault 0

                            dronesInSpaceQuantityLimit =
                                droneGroupInSpace.header.quantityFromTitle
                                    |> Maybe.andThen .maximum
                                    |> Maybe.withDefault 2
                        in
                        if 0 < dronesInBayQuantity && dronesInSpaceQuantityCurrent < dronesInSpaceQuantityLimit then
                            Just
                                (describeBranch "Launch drones"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInBay.header.uiNode )
                                        (useMenuEntryWithTextContaining "Launch drone" menuCascadeCompleted)
                                        context
                                    )
                                )

                        else
                            Nothing

                    _ ->
                        Nothing
            )


returnDronesToBay : BotDecisionContext -> Maybe DecisionPathNode
returnDronesToBay context =
    context.readingFromGameClient.dronesWindow
        |> Maybe.andThen .droneGroupInSpace
        |> Maybe.andThen
            (\droneGroupInLocalSpace ->
                if
                    (droneGroupInLocalSpace.header.quantityFromTitle
                        |> Maybe.map .current
                        |> Maybe.withDefault 0
                    )
                        < 1
                then
                    Nothing

                else
                    Just
                        (describeBranch "I see there are drones in space. Return those to bay."
                            (useContextMenuCascade
                                ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                (useMenuEntryWithTextContaining "Return to drone bay" menuCascadeCompleted)
                                context
                            )
                        )
            )


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.BotFrameworkSeparatingMemory.readShipUIModuleButtonTooltipWhereNotYetInMemory


knownMiningModulesFromContext : BotDecisionContext -> List EveOnline.ParseUserInterface.ShipUIModuleButton
knownMiningModulesFromContext context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filter
            (EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                >> Maybe.map tooltipLooksLikeMiningModule
                >> Maybe.withDefault False
            )


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filterMap
            (\moduleButton ->
                moduleButton
                    |> EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                    |> Maybe.andThen (tooltipLooksLikeModuleToActivateAlways context)
                    |> Maybe.map (\moduleName -> ( moduleName, moduleButton ))
            )


tooltipLooksLikeMiningModule : ModuleButtonTooltipMemory -> Bool
tooltipLooksLikeMiningModule =
    .allContainedDisplayTextsWithRegion
        >> List.map Tuple.first
        >> List.any
            (Regex.fromString "\\d\\s*m3\\s*\\/\\s*s" |> Maybe.map Regex.contains |> Maybe.withDefault (always False))


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> ModuleButtonTooltipMemory -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .allContainedDisplayTextsWithRegion
        >> List.map Tuple.first
        >> List.filterMap
            (\tooltipText ->
                context.eventContext.botSettings.activateModulesAlways
                    |> List.filterMap
                        (\moduleToActivateAlways ->
                            if tooltipText |> stringContainsIgnoringCase moduleToActivateAlways then
                                Just tooltipText

                            else
                                Nothing
                        )
                    |> List.head
            )
        >> List.head


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance =
                Maybe.andThen .selectInstancePilotName
                    >> Maybe.map EveOnline.BotFramework.selectGameClientInstanceWithPilotName
                    >> Maybe.withDefault EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            , decideNextStep = miningBotDecisionRoot
            }
    }


initBotMemory : BotMemory
initBotMemory =
    { lastDockedStationNameFromInfoPanel = Nothing
    , timesUnloaded = 0
    , volumeUnloadedCubicMeters = 0
    , lastUsedCapacityInMiningHold = Nothing
    , shipModules = EveOnline.BotFramework.initShipModulesMemory
    , lastReadingsInSpaceDronesWindowWasVisible = []
    }


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
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
                Just shipUI ->
                    [ "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."
                    , "Found " ++ (context |> knownMiningModulesFromContext |> List.length |> String.fromInt) ++ " mining modules."
                    ]
                        |> String.join " "

                Nothing ->
                    case
                        readingFromGameClient.infoPanelContainer
                            |> Maybe.andThen .infoPanelLocationInfo
                            |> Maybe.andThen .expandedContent
                            |> Maybe.andThen .currentStationName
                    of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I do not see if I am docked or in space. Please set up game client first."

        describeDrones =
            case readingFromGameClient.dronesWindow of
                Nothing ->
                    "I do not see the drones window."

                Just dronesWindow ->
                    "I see the drones window: In bay: "
                        ++ (dronesWindow.droneGroupInBay
                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                |> Maybe.map (.current >> String.fromInt)
                                |> Maybe.withDefault "Unknown"
                           )
                        ++ ", in space: "
                        ++ (dronesWindow.droneGroupInSpace
                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                |> Maybe.map (.current >> String.fromInt)
                                |> Maybe.withDefault "Unknown"
                           )
                        ++ "."

        describeMiningHold =
            "mining hold filled "
                ++ (readingFromGameClient
                        |> inventoryWindowWithMiningHoldSelectedFromGameClient
                        |> Maybe.andThen capacityGaugeUsedPercent
                        |> Maybe.map String.fromInt
                        |> Maybe.withDefault "Unknown"
                   )
                ++ "%."

        describeCurrentReading =
            [ describeMiningHold, describeShip, describeDrones ] |> String.join " "
    in
    [ "Session performance: " ++ describeSessionPerformance
    , "---"
    , "Current reading: " ++ describeCurrentReading
    ]
        |> String.join "\n"


updateMemoryForNewReadingFromGame : EveOnline.BotFrameworkSeparatingMemory.UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =
    let
        currentStationNameFromInfoPanel =
            context.readingFromGameClient.infoPanelContainer
                |> Maybe.andThen .infoPanelLocationInfo
                |> Maybe.andThen .expandedContent
                |> Maybe.andThen .currentStationName

        lastUsedCapacityInMiningHold =
            context.readingFromGameClient
                |> inventoryWindowWithMiningHoldSelectedFromGameClient
                |> Maybe.andThen .selectedContainerCapacityGauge
                |> Maybe.andThen Result.toMaybe
                |> Maybe.map .used

        completedUnloadSincePreviousReading =
            case botMemoryBefore.lastUsedCapacityInMiningHold of
                Nothing ->
                    False

                Just previousUsedCapacityInMiningHold ->
                    lastUsedCapacityInMiningHold == Just 0 && 0 < previousUsedCapacityInMiningHold

        volumeUnloadedSincePreviousReading =
            case botMemoryBefore.lastUsedCapacityInMiningHold of
                Nothing ->
                    0

                Just previousUsedCapacityInMiningHold ->
                    case lastUsedCapacityInMiningHold of
                        Nothing ->
                            0

                        Just currentUsedCapacityInMiningHold ->
                            -- During mining, when new ore appears in the inventory, this difference is negative.
                            max 0 (previousUsedCapacityInMiningHold - currentUsedCapacityInMiningHold)

        timesUnloaded =
            botMemoryBefore.timesUnloaded
                + (if completedUnloadSincePreviousReading then
                    1

                   else
                    0
                  )

        volumeUnloadedCubicMeters =
            botMemoryBefore.volumeUnloadedCubicMeters + volumeUnloadedSincePreviousReading

        lastReadingsInSpaceDronesWindowWasVisible =
            if context.readingFromGameClient.shipUI == Nothing then
                botMemoryBefore.lastReadingsInSpaceDronesWindowWasVisible

            else
                (context.readingFromGameClient.dronesWindow /= Nothing)
                    :: botMemoryBefore.lastReadingsInSpaceDronesWindowWasVisible
                    |> List.take dockWhenDroneWindowInvisibleCount
    in
    { lastDockedStationNameFromInfoPanel =
        [ currentStationNameFromInfoPanel, botMemoryBefore.lastDockedStationNameFromInfoPanel ]
            |> List.filterMap identity
            |> List.head
    , timesUnloaded = timesUnloaded
    , volumeUnloadedCubicMeters = volumeUnloadedCubicMeters
    , lastUsedCapacityInMiningHold = lastUsedCapacityInMiningHold
    , shipModules =
        botMemoryBefore.shipModules
            |> EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory context.readingFromGameClient
    , lastReadingsInSpaceDronesWindowWasVisible = lastReadingsInSpaceDronesWindowWasVisible
    }


shouldDockBecauseDroneWindowWasInvisibleTooLong : BotMemory -> Bool
shouldDockBecauseDroneWindowWasInvisibleTooLong memory =
    (dockWhenDroneWindowInvisibleCount <= List.length memory.lastReadingsInSpaceDronesWindowWasVisible)
        && List.all ((==) False) memory.lastReadingsInSpaceDronesWindowWasVisible


clickModuleButtonButWaitIfClickedInPreviousStep : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUIModuleButton -> DecisionPathNode
clickModuleButtonButWaitIfClickedInPreviousStep context moduleButton =
    if doEffectsClickModuleButton moduleButton context.previousStepEffects then
        describeBranch "Already clicked on this module button in previous step." waitForProgressInGame

    else
        describeBranch "Click on this module button."
            (decideActionForCurrentStep
                (mouseClickOnUIElement MouseButtonLeft moduleButton.uiNode)
            )


ensureUserEnabledNameColumnInOverview : { ifEnabled : DecisionPathNode, ifDisabled : DecisionPathNode } -> SeeUndockingComplete -> DecisionPathNode
ensureUserEnabledNameColumnInOverview { ifEnabled, ifDisabled } seeUndockingComplete =
    if
        seeUndockingComplete.overviewWindows
            |> List.any
                (\overviewWindow ->
                    (overviewWindow.entries |> List.all (.objectName >> (==) Nothing))
                        && (0 < List.length overviewWindow.entries)
                )
    then
        describeBranch "The 'Name' column in the overview window seems disabled." ifDisabled

    else
        ifEnabled


activeShipTreeEntryFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
activeShipTreeEntryFromInventoryWindow =
    .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


clickableAsteroidsFromOverviewWindow : ReadingFromGameClient -> List OverviewWindowEntry
clickableAsteroidsFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids
        >> List.filter (.uiNode >> uiNodeIsLargeEnoughForClicking)
        >> List.filter (.opacityPercent >> Maybe.map ((<=) 50) >> Maybe.withDefault True)
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)


asteroidOverviewEntryMatchesSettings : BotSettings -> OverviewWindowEntry -> Bool
asteroidOverviewEntryMatchesSettings settings overviewEntry =
    let
        textMatchesPattern text =
            (settings.includeAsteroidPatterns == [])
                || (settings.includeAsteroidPatterns
                        |> List.any (\pattern -> String.contains (String.toLower pattern) (String.toLower text))
                   )
    in
    overviewEntry.cellsTexts
        |> Dict.values
        |> List.any textMatchesPattern


overviewWindowEntriesRepresentingAsteroids : ReadingFromGameClient -> List OverviewWindowEntry
overviewWindowEntriesRepresentingAsteroids =
    .overviewWindows
        >> List.map (.entries >> List.filter overviewWindowEntryRepresentsAnAsteroid)
        >> List.concat


overviewWindowEntryRepresentsAnAsteroid : OverviewWindowEntry -> Bool
overviewWindowEntryRepresentsAnAsteroid entry =
    (entry.textsLeftToRight |> List.any (stringContainsIgnoringCase "asteroid"))
        && (entry.textsLeftToRight |> List.any (stringContainsIgnoringCase "belt") |> not)


capacityGaugeUsedPercent : EveOnline.ParseUserInterface.InventoryWindow -> Maybe Int
capacityGaugeUsedPercent =
    .selectedContainerCapacityGauge
        >> Maybe.andThen Result.toMaybe
        >> Maybe.andThen
            (\capacity -> capacity.maximum |> Maybe.map (\maximum -> capacity.used * 100 // maximum))


inventoryWindowWithMiningHoldSelectedFromGameClient : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindow
inventoryWindowWithMiningHoldSelectedFromGameClient =
    .inventoryWindows
        >> List.filter inventoryWindowSelectedContainerIsMiningHold
        >> List.head


inventoryWindowSelectedContainerIsMiningHold : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsMiningHold inventoryWindow =
    inventoryWindowSelectedContainerIsMiningHold_PhotonUI inventoryWindow
        || inventoryWindowSelectedContainerIsMiningHold_pre_PhotonUI inventoryWindow


inventoryWindowSelectedContainerIsMiningHold_PhotonUI : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsMiningHold_PhotonUI =
    activeShipTreeEntryFromInventoryWindow
        >> Maybe.andThen miningHoldFromInventoryWindowShipEntry
        >> Maybe.map (.uiNode >> containsSelectionIndicatorPhotonUI)
        >> Maybe.withDefault False


inventoryWindowSelectedContainerIsMiningHold_pre_PhotonUI : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsMiningHold_pre_PhotonUI =
    .subCaptionLabelText >> Maybe.map (stringContainsIgnoringCase "mining hold") >> Maybe.withDefault False


selectedContainerFirstItemFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe UIElement
selectedContainerFirstItemFromInventoryWindow =
    .selectedContainerInventory
        >> Maybe.andThen .itemsView
        >> Maybe.map
            (\itemsView ->
                case itemsView of
                    EveOnline.ParseUserInterface.InventoryItemsListView { items } ->
                        items |> List.map .uiNode

                    EveOnline.ParseUserInterface.InventoryItemsNotListView { items } ->
                        items
            )
        >> Maybe.andThen List.head


miningHoldFromInventoryWindowShipEntry :
    EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
    -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
miningHoldFromInventoryWindowShipEntry =
    .children
        >> List.map EveOnline.ParseUserInterface.unwrapInventoryWindowLeftTreeEntryChild
        >> List.filter (.text >> stringContainsIgnoringCase "mining hold")
        >> List.head


itemHangarFromInventoryWindow :
    EveOnline.ParseUserInterface.InventoryWindow
    -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
itemHangarFromInventoryWindow =
    .leftTreeEntries
        >> List.filter (.text >> stringContainsIgnoringCase "item hangar")
        >> List.head


fleetHangarFromInventoryWindow :
    EveOnline.ParseUserInterface.InventoryWindow
    -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
fleetHangarFromInventoryWindow =
    .leftTreeEntries
        >> List.filter (.text >> stringContainsIgnoringCase "fleet hangar")
        >> List.head


shipManeuverIsApproaching : ReadingFromGameClient -> Bool
shipManeuverIsApproaching =
    .shipUI
        >> Maybe.andThen .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map ((==) EveOnline.ParseUserInterface.ManeuverApproach)
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


uiNodeIsLargeEnoughForClicking : UITreeNodeWithDisplayRegion -> Bool
uiNodeIsLargeEnoughForClicking node =
    3 < node.totalDisplayRegionVisible.width && 3 < node.totalDisplayRegionVisible.height


containsSelectionIndicatorPhotonUI : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion -> Bool
containsSelectionIndicatorPhotonUI =
    EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion
        >> List.any
            (.uiNode
                >> (\uiNode ->
                        (uiNode.pythonObjectTypeName
                            |> String.startsWith "SelectionIndicator"
                        )
                            && (uiNode
                                    |> EveOnline.ParseUserInterface.getColorPercentFromDictEntries
                                    |> Maybe.map (.a >> (<) 10)
                                    |> Maybe.withDefault False
                               )
                   )
            )


nothingFromIntIfGreaterThan : Int -> Int -> Maybe Int
nothingFromIntIfGreaterThan limit originalInt =
    if limit < originalInt then
        Nothing

    else
        Just originalInt

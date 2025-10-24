{- EVE Online mining bot version 2025-10-24

   This bot automates the complete mining process, including offloading the ore and traveling between the mining spot and the unloading location.

   In addition to the automation, the bot reports performance statistics such as the number of completed cycles and the aggregate volume of mined ore in a standardized format.

   This bot supports configuring multiple mining sites. It picks a random asteroid belt from the solar system menu if no mining site is configured. When the bot settings contain at least one mining site, the bot searches the 'Locations' window and overview windows to find one of the sites and initiate warping the ship there.

   If no station name or structure name is given with the bot-settings, the bot docks again at the station where it was last docked.

   Setup instructions for the EVE Online client:

   + Set the UI language to English.
   + In the ship UI in the 'Options' menu, tick the checkbox for 'Display Module Tooltips'.
   + In Overview window, make asteroids visible.
   + Open one inventory window.
   + If you want to use drones for defense against rats, place them in the drone bay, and open the 'Drones' window.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `mining-site` : Name of a mining location, as it appears in the 'Label' column of the 'Locations' window.
   + `unload-station-name` : Name of a station to dock to when the mining hold is full.
   + `unload-structure-name` : Name of a structure to dock to when the mining hold is full.
   + `activate-module-always` : Text found in tooltips of ship modules that should always be active. For example: "shield hardener".
   + `hide-when-neutral-in-local` : Should we hide when a neutral or hostile pilot appears in the local chat? The only supported values are `no` and `yes`.
   + `unload-fleet-hangar-percent` : This will make the bot unload the mining hold at least XX percent full to the fleet hangar, you must be in a fleet with an orca or a rorqual and the fleet hangar must be visible within the inventory window.
   + `dock-when-without-drones` : This will make the bot dock when it's out of drones. The only supported values are `no` and `yes`.
   + `repair-before-undocking` : Repair the ship at the station before undocking. The only supported values are `no` and `yes`.
   + `afterburner-module-text` : Text found in tooltips of the afterburner module.
   + `afterburner-distance-threshold` : Distance threshold (in meters) at which to activate/deactivate the afterburner.

   When using more than one setting, start a new line for each setting in the text input field.
   Here is an example of a complete settings string:

   ```
   mining-site = mining bookmark label
   unload-station-name = Noghere VII - Moon 15
   activate-module-always = shield hardener
   activate-module-always = afterburner
   ```

   The bot searches the configured structure or station name in the 'Locations' window and all overview windows.
   If the destination is not visible in the locations and overview windows, it opens the solar system menu to search for it.
   When using the 'Locations' window, enter the unload station/structure name as it appears in the 'Label' column.

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

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import Common.Basics exposing (listElementAtWrappedIndex, stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import Common.PromptParser as PromptParser exposing (IntervalInt)
import Dict
import EveOnline.BotFramework
    exposing
        ( ModuleButtonTooltipMemory
        , OverviewWindowsMemory
        , ReadingFromGameClient
        , ShipModulesMemory
        , UIElement
        , localChatWindowFromUserInterface
        , menuCascadeCompleted
        , mouseClickOnUIElement
        , shipUIIndicatesShipIsWarpingOrJumping
        , uiNodeVisibleRegionLargeEnoughForClicking
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
        , clickModuleButtonButWaitIfClickedInPreviousStep
        , decideActionForCurrentStep
        , ensureInfoPanelLocationInfoIsExpanded
        , ensureOverviewsSorted
        , useContextMenuCascade
        , useContextMenuCascadeOnListSurroundingsButton
        , useContextMenuCascadeOnOverviewEntry
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface
    exposing
        ( OverviewWindowEntry
        , centerFromDisplayRegion
        , getAllContainedDisplayTextsWithRegion
        )
import List.Extra
import Maybe.Extra
import Regex
import Result.Extra


{-| Sources for the defaults:

  - <https://forum.botlab.org/t/mining-bot-wont-approach/3162>

-}
defaultBotSettings : BotSettings
defaultBotSettings =
    { runAwayShieldHitpointsThresholdPercent = 70
    , unloadStationNames = []
    , unloadStructureNames = []
    , unloadFleetHangarPercent = -1
    , unloadMiningHoldPercent = 99
    , activateModulesAlways = []
    , hideWhenNeutralInLocal = Nothing
    , dockWhenWithoutDrones = Nothing
    , repairBeforeUndocking = Nothing
    , targetingRange = 8000
    , miningModuleRange = 5000
    , botStepDelayMilliseconds = { minimum = 1300, maximum = 1500 }
    , selectInstancePilotName = Nothing
    , includeAsteroidPatterns = []
    , miningSites = []
    , afterburnerModuleText = Nothing
    , afterburnerDistanceThreshold = Nothing
    , compressFromMiningHold = PromptParser.No
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    PromptParser.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "run-away-shield-hitpoints-threshold-percent"
           , { alternativeNames = []
             , description = "Threshold of shield hitpoints in percent to trigger running away."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\threshold settings -> { settings | runAwayShieldHitpointsThresholdPercent = threshold })
             }
           )
         , ( "unload-station-name"
           , { alternativeNames = []
             , description = "Name of a station to dock to when the mining hold is full."
             , valueParser =
                PromptParser.valueTypeString
                    (\stationName settings ->
                        { settings
                            | unloadStationNames = String.trim stationName :: settings.unloadStationNames
                        }
                    )
             }
           )
         , ( "unload-structure-name"
           , { alternativeNames = []
             , description = "Name of a structure to dock to when the mining hold is full."
             , valueParser =
                PromptParser.valueTypeString
                    (\structureName settings ->
                        { settings
                            | unloadStructureNames = String.trim structureName :: settings.unloadStructureNames
                        }
                    )
             }
           )
         , ( "unload-fleet-hangar-percent"
           , { alternativeNames = []
             , description = "This will make the bot to unload the mining hold at least XX percent full to the fleet hangar, you must be in a fleet with an orca or a rorqual and the fleet hangar must be visible within the inventory window."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\fleetHangarPercent settings -> { settings | unloadFleetHangarPercent = fleetHangarPercent })
             }
           )
         , ( "unload-mining-hold-percent"
           , { alternativeNames = []
             , description = "When the mining hold is filled at least this much, we start unloading the ore."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\percent settings -> { settings | unloadMiningHoldPercent = percent })
             }
           )
         , ( "activate-module-always"
           , { alternativeNames = []
             , description = "Text found in tooltips of ship modules that should always be active. For example: 'shield hardener'."
             , valueParser =
                PromptParser.valueTypeString
                    (\moduleName settings -> { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways })
             }
           )
         , ( "hide-when-neutral-in-local"
           , { alternativeNames = []
             , description = "Should we hide when a neutral or hostile pilot appears in the local chat? The only supported values are `no` and `yes`."
             , valueParser =
                PromptParser.valueTypeYesOrNo
                    (\hide settings -> { settings | hideWhenNeutralInLocal = Just hide })
             }
           )
         , ( "dock-when-without-drones"
           , { alternativeNames = []
             , description = "This will make the bot dock when it's out of drones. The only supported values are `no` and `yes`."
             , valueParser =
                PromptParser.valueTypeYesOrNo
                    (\without settings -> { settings | dockWhenWithoutDrones = Just without })
             }
           )
         , ( "repair-before-undocking"
           , { alternativeNames = []
             , description = "Repair the ship at the station before undocking. The only supported values are `no` and `yes`."
             , valueParser =
                PromptParser.valueTypeYesOrNo
                    (\repair settings -> { settings | repairBeforeUndocking = Just repair })
             }
           )
         , ( "targeting-range"
           , { alternativeNames = []
             , description = "Distance under which we try to target an object in space."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\range settings -> { settings | targetingRange = range })
             }
           )
         , ( "mining-module-range"
           , { alternativeNames = []
             , description = "Range of the mining modules in the current ship fitting."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\range settings -> { settings | miningModuleRange = range })
             }
           )
         , ( "select-instance-pilot-name"
           , { alternativeNames = []
             , description = "Name of EVE Online character to search for when selecting an instance of the game client."
             , valueParser =
                PromptParser.valueTypeString
                    (\pilotName settings -> { settings | selectInstancePilotName = Just pilotName })
             }
           )
         , ( "bot-step-delay"
           , { alternativeNames = []
             , description = "Minimum time between starting bot steps in milliseconds. You can also specify a range like `1000 - 2000`. The bot then picks a random value in this range."
             , valueParser =
                PromptParser.parseIntervalIntFromPointOrIntervalString
                    >> Result.map
                        (\delay settings -> { settings | botStepDelayMilliseconds = delay })
             }
           )
         , ( "include-asteroid-pattern"
           , { alternativeNames = []
             , description = "Names of asteroids to select for mining. Can be used multiple times. If the setting is used zero times, we mine all kinds of asteroids."
             , valueParser =
                PromptParser.valueTypeString
                    (\pattern settings ->
                        { settings | includeAsteroidPatterns = pattern :: settings.includeAsteroidPatterns }
                    )
             }
           )
         , ( "mining-site"
           , { alternativeNames = [ "mining-site-location" ]
             , description = "Name of a mining site as it appears in the 'Locations' window or under 'Locations' in the solar system surroundings menu."
             , valueParser =
                PromptParser.valueTypeString
                    (\miningSite settings ->
                        { settings | miningSites = List.concat [ settings.miningSites, [ miningSite ] ] }
                    )
             }
           )
         , ( "afterburner-module-text"
           , { alternativeNames = []
             , description = "Text found in tooltips of the afterburner module."
             , valueParser =
                PromptParser.valueTypeString
                    (\moduleName settings -> { settings | afterburnerModuleText = Just moduleName })
             }
           )
         , ( "afterburner-distance-threshold"
           , { alternativeNames = []
             , description = "Distance threshold (in meters) to trigger the afterburner activation."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\distance settings -> { settings | afterburnerDistanceThreshold = Just distance })
             }
           )
         , ( "compress-from-mining-hold"
           , { alternativeNames = []
             , description = "Compress items from the mining hold, when the mining hold is filled at least 75 %. The only supported values are `no` and `yes`."
             , valueParser =
                PromptParser.valueTypeYesOrNo
                    (\compress settings -> { settings | compressFromMiningHold = compress })
             }
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
    , unloadStationNames : List String
    , unloadStructureNames : List String
    , unloadFleetHangarPercent : Int
    , unloadMiningHoldPercent : Int
    , activateModulesAlways : List String
    , hideWhenNeutralInLocal : Maybe PromptParser.YesOrNo
    , dockWhenWithoutDrones : Maybe PromptParser.YesOrNo
    , repairBeforeUndocking : Maybe PromptParser.YesOrNo
    , targetingRange : Int
    , miningModuleRange : Int
    , botStepDelayMilliseconds : IntervalInt
    , selectInstancePilotName : Maybe String
    , includeAsteroidPatterns : List String
    , miningSites : List String
    , afterburnerModuleText : Maybe String
    , afterburnerDistanceThreshold : Maybe Int
    , compressFromMiningHold : PromptParser.YesOrNo
    }


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    , timesUnloaded : Int
    , volumeUnloadedCubicMeters : Int
    , lastUsedCapacityInMiningHold : Maybe Int
    , shipModules : ShipModulesMemory
    , overviewWindows : OverviewWindowsMemory
    , lastReadingsInSpaceDronesWindowWasVisible : List Bool
    }


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


type alias State =
    EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory


type alias SelectedAsteroidsFromOverview =
    { clickableAsteroids : List OverviewWindowEntry
    , asteroidMatchingSettings : Maybe ( OverviewWindowEntry, { closeEnoughForMining : Bool } )
    }


miningBotDecisionRoot : BotDecisionContext -> DecisionPathNode
miningBotDecisionRoot context =
    miningBotDecisionRootBeforeApplyingSettings context
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase
            (randomIntFromInterval context context.eventContext.botSettings.botStepDelayMilliseconds)


{-| A first outline of the decision tree for a mining bot came from <https://forum.botlab.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
miningBotDecisionRootBeforeApplyingSettings : BotDecisionContext -> DecisionPathNode
miningBotDecisionRootBeforeApplyingSettings context =
    generalSetupInUserInterface
        context
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                { ifDocked =
                    ensureMiningHoldIsSelectedInInventoryWindow
                        context.readingFromGameClient
                        (dockedWithMiningHoldSelected context)
                , ifSeeShipUI =
                    \shipUI ->
                        case returnDronesAndRunAwayIfHitpointsAreTooLowOrWithoutDrones context shipUI of
                            Just toRunAway ->
                                toRunAway

                            Nothing ->
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
                                                    (inSpaceWithMiningHoldSelected context shipUI)
                                            , ifDisabled =
                                                describeBranch
                                                    "Please configure the overview to show objects names."
                                                    askForHelpToGetUnstuck
                                            }
                                            context.readingFromGameClient
                                        )
                }
                context.readingFromGameClient
            )


continueIfShouldHide : { ifShouldHide : DecisionPathNode } -> BotDecisionContext -> Maybe DecisionPathNode
continueIfShouldHide config context =
    case
        context.eventContext
            |> EveOnline.BotFramework.secondsToSessionEnd
            |> Maybe.andThen (nothingFromIntIfGreaterThan 200)
    of
        Just secondsToSessionEnd ->
            Just
                (describeBranch ("Session ends in " ++ (secondsToSessionEnd |> String.fromInt) ++ " seconds.")
                    config.ifShouldHide
                )

        Nothing ->
            case context |> quickMessageHasClusterShutdown of
                Just shutdownMessage ->
                    Just
                        (describeBranch
                            ("Quick Message: " ++ shutdownMessage)
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
        Just PromptParser.No ->
            False

        Just PromptParser.Yes ->
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
    context.eventContext.botSettings.dockWhenWithoutDrones == Just PromptParser.Yes


shouldRepairBeforeUndocking : BotDecisionContext -> Bool
shouldRepairBeforeUndocking context =
    context.eventContext.botSettings.repairBeforeUndocking == Just PromptParser.Yes


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


generalSetupInUserInterface : BotDecisionContext -> Maybe DecisionPathNode
generalSetupInUserInterface context =
    [ closeMessageBox
    , ensureInfoPanelLocationInfoIsExpanded
    , ensureOverviewsSorted
        { sortColumnName = "Distance", skipSortingWhenNotScrollable = True }
        context.memory.overviewWindows
        >> List.filterMap
            (\( _, ( description, maybeAction ) ) ->
                maybeAction |> Maybe.map (describeBranch description)
            )
        >> List.head
    ]
        |> List.filterMap ((|>) context.readingFromGameClient)
        |> List.head


closeMessageBox : ReadingFromGameClient -> Maybe DecisionPathNode
closeMessageBox readingFromGameClient =
    readingFromGameClient.messageBoxes
        |> List.head
        |> Maybe.map
            (\messageBox ->
                describeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose button =
                            case button.mainText of
                                Nothing ->
                                    False

                                Just buttonText ->
                                    let
                                        buttonTextLower =
                                            String.toLower buttonText
                                    in
                                    List.member buttonTextLower [ "close", "ok" ]
                     in
                     case List.filter buttonCanBeUsedToClose messageBox.buttons of
                        [] ->
                            describeBranch "I see no way to close this message box." askForHelpToGetUnstuck

                        buttonToUse :: _ ->
                            describeBranch
                                ("Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'.")
                                (case mouseClickOnUIElement MouseButtonLeft buttonToUse.uiNode of
                                    Err _ ->
                                        describeBranch "Failed to click" askForHelpToGetUnstuck

                                    Ok clickAction ->
                                        decideActionForCurrentStep clickAction
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
                                    , mouseButton = MouseButtonLeft
                                    , waypointsPositionsInBetween = []
                                    , endLocation = itemHangar.totalDisplayRegionVisible |> centerFromDisplayRegion
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
                        (mouseClickOnUIElement MouseButtonLeft fleetHangarFromInventory
                            |> Result.Extra.unpack
                                (always (describeBranch "Failed to click" askForHelpToGetUnstuck))
                                decideActionForCurrentStep
                        )

                Just itemInInventory ->
                    describeBranch "I see at least one item in the mining hold. Move this to the fleet hangar."
                        (describeBranch "Drag and drop."
                            (decideActionForCurrentStep
                                (EffectOnWindow.effectsForDragAndDrop
                                    { startLocation = itemInInventory.totalDisplayRegionVisible |> centerFromDisplayRegion
                                    , mouseButton = MouseButtonLeft
                                    , waypointsPositionsInBetween = []
                                    , endLocation = fleetHangarFromInventory.totalDisplayRegionVisible |> centerFromDisplayRegion
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
                        (mouseClickOnUIElement MouseButtonLeft undockButton
                            |> Result.Extra.unpack
                                (always ifCannotReachButton)
                                decideActionForCurrentStep
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

                    Just itemToRepair ->
                        Just
                            (describeBranch "There is at least one item to repair."
                                (case mouseClickOnUIElement MouseButtonLeft itemToRepair of
                                    Err _ ->
                                        describeBranch "Failed to click" askForHelpToGetUnstuck

                                    Ok clickItemToRepair ->
                                        case repairShopWindow.buttons |> List.filter buttonUsed |> List.head of
                                            Just btnRepairAll ->
                                                describeBranch "I see the repair all button, I'm going to click it."
                                                    (case mouseClickOnUIElement MouseButtonLeft btnRepairAll.uiNode of
                                                        Err _ ->
                                                            describeBranch "Failed to click" askForHelpToGetUnstuck

                                                        Ok clickButtonToRepair ->
                                                            decideActionForCurrentStep
                                                                ([ clickItemToRepair
                                                                 , clickButtonToRepair
                                                                 ]
                                                                    |> List.concat
                                                                )
                                                    )

                                            Nothing ->
                                                describeBranch
                                                    "I do not see the repair all button."
                                                    askForHelpToGetUnstuck
                                )
                            )


inSpaceWithMiningHoldSelected :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> EveOnline.ParseUserInterface.InventoryWindow
    -> DecisionPathNode
inSpaceWithMiningHoldSelected context shipUI inventoryWindowWithMiningHoldSelected =
    if shipUIIndicatesShipIsWarpingOrJumping shipUI then
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
                modulesToActivateAlwaysActivated context inventoryWindowWithMiningHoldSelected


modulesToActivateAlwaysActivated :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.InventoryWindow
    -> DecisionPathNode
modulesToActivateAlwaysActivated context inventoryWindowWithMiningHoldSelected =
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
                case selectAsteroidsFromOverview context of
                    Err err ->
                        describeBranch ("Failed to select asteroids from overview: " ++ err)
                            (dockToUnloadOre context)

                    Ok selectedAsteroids ->
                        describeBranch
                            ("The mining hold is not yet filled "
                                ++ describeThresholdToUnload
                                ++ ". Get more ore."
                            )
                            (case
                                context.readingFromGameClient.targets
                                    |> List.sortBy
                                        (\target ->
                                            if target.isActiveTarget then
                                                0

                                            else
                                                1
                                        )
                                    |> List.head
                             of
                                Nothing ->
                                    describeBranch "I see no locked target."
                                        (travelToMiningSiteAndLaunchDronesAndTargetAsteroid selectedAsteroids context)

                                Just nextTarget ->
                                    unlockTargetsNotForMining context
                                        |> Maybe.withDefault
                                            (describeBranch "I see a locked target."
                                                (ensureTargetIsInMiningRange
                                                    context
                                                    nextTarget
                                                    { whenInRange =
                                                        if shipManeuverIsApproaching context.readingFromGameClient then
                                                            describeBranch "Minable asteroid is close enough to stop the ship"
                                                                ([ EffectOnWindow.KeyDown EffectOnWindow.vkey_CONTROL
                                                                 , EffectOnWindow.KeyDown EffectOnWindow.vkey_SPACE
                                                                 , EffectOnWindow.KeyUp EffectOnWindow.vkey_CONTROL
                                                                 , EffectOnWindow.KeyUp EffectOnWindow.vkey_SPACE
                                                                 ]
                                                                    |> decideActionForCurrentStep
                                                                )

                                                        else
                                                            case
                                                                knownMiningModules
                                                                    |> List.filter (.isActive >> Maybe.withDefault False >> not)
                                                                    |> List.head
                                                            of
                                                                Nothing ->
                                                                    describeBranch
                                                                        (if knownMiningModules == [] then
                                                                            "Found no mining modules so far."

                                                                         else
                                                                            "All known mining modules found so far are active."
                                                                        )
                                                                        (case readShipUIModuleButtonTooltips context of
                                                                            Just readTooltips ->
                                                                                readTooltips

                                                                            Nothing ->
                                                                                case deactivateAfterburner context of
                                                                                    Just deactivateAfterburnerAction ->
                                                                                        describeBranch "Deactivate afterburner."
                                                                                            deactivateAfterburnerAction

                                                                                    Nothing ->
                                                                                        compressAndStackAllIfConditionsMet
                                                                                            context
                                                                                            inventoryWindowWithMiningHoldSelected
                                                                                            { miningHoldFillPercent = fillPercent
                                                                                            , ifNothingToCompress = waitForProgressInGame
                                                                                            }
                                                                        )

                                                                Just inactiveModule ->
                                                                    describeBranch "I see an inactive mining module. Activate it."
                                                                        (clickModuleButtonButWaitIfClickedInPreviousStep
                                                                            context
                                                                            inactiveModule
                                                                        )
                                                    }
                                                )
                                            )
                            )


ensureTargetIsInMiningRange :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.Target
    -> { whenInRange : DecisionPathNode }
    -> DecisionPathNode
ensureTargetIsInMiningRange context target { whenInRange } =
    case readDistanceOfTargetInMeters target of
        Err err ->
            describeBranch ("Failed to read distance of target: " ++ err)
                askForHelpToGetUnstuck

        Ok distanceMeters ->
            if distanceMeters <= context.eventContext.botSettings.miningModuleRange then
                whenInRange

            else
                let
                    approachCommand =
                        useContextMenuCascade
                            ( "targeted object", target.uiNode )
                            (useMenuEntryWithTextContaining "approach" menuCascadeCompleted)
                            context
                in
                describeBranch ("Target is " ++ String.fromInt distanceMeters ++ " meters away. Approach it.")
                    (if shipManeuverIsApproaching context.readingFromGameClient then
                        case activateAfterburnerIfNeeded context distanceMeters of
                            Just afterburnerActivation ->
                                describeBranch "Afterburner is not active. Activate it."
                                    afterburnerActivation

                            Nothing ->
                                approachCommand

                     else
                        approachCommand
                    )


deactivateAfterburner : BotDecisionContext -> Maybe DecisionPathNode
deactivateAfterburner context =
    let
        afterburnerModules =
            knownAfterburnerModulesFromContext context

        activeAfterburnerModules =
            afterburnerModules
                |> List.filter
                    (\moduleButton ->
                        case moduleButton.isActive of
                            Nothing ->
                                False

                            Just isActive ->
                                isActive
                    )
    in
    case activeAfterburnerModules of
        [] ->
            Nothing

        activeModule :: _ ->
            Just (clickModuleButtonButWaitIfClickedInPreviousStep context activeModule)


activateAfterburnerIfNeeded : BotDecisionContext -> Int -> Maybe DecisionPathNode
activateAfterburnerIfNeeded context distance =
    let
        afterburnerModules =
            knownAfterburnerModulesFromContext context

        isActive m =
            m.isActive |> Maybe.withDefault False
    in
    case context.eventContext.botSettings.afterburnerDistanceThreshold of
        Just threshold ->
            if distance > threshold then
                case List.filter (not << isActive) afterburnerModules |> List.head of
                    Just inactiveModule ->
                        Just
                            (describeBranch
                                ("Distance to target is "
                                    ++ String.fromInt distance
                                    ++ "m, above "
                                    ++ String.fromInt threshold
                                    ++ "m. Activating afterburner."
                                )
                                (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)
                            )

                    Nothing ->
                        Nothing

            else
                Nothing

        Nothing ->
            Nothing


readDistanceOfTargetInMeters : EveOnline.ParseUserInterface.Target -> Result String Int
readDistanceOfTargetInMeters target =
    {- Example seen in session-recording-2023-04-22T21-26-45.zip:
       0 = "<center>Asteroid (Golden"
       1 = "<center>Omber)"
       2 = "<center>23 km"
    -}
    target.textsTopToBottom
        |> List.reverse
        |> List.concatMap (String.split ">")
        |> List.filterMap (EveOnline.ParseUserInterface.parseOverviewEntryDistanceInMetersFromText >> Result.toMaybe)
        |> List.head
        |> Maybe.map Ok
        |> Maybe.withDefault
            (Err
                ("Found no matching text in "
                    ++ String.fromInt (List.length target.textsTopToBottom)
                    ++ " lines ("
                    ++ String.join ", " target.textsTopToBottom
                    ++ ")."
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


travelToMiningSiteAndLaunchDronesAndTargetAsteroid : SelectedAsteroidsFromOverview -> BotDecisionContext -> DecisionPathNode
travelToMiningSiteAndLaunchDronesAndTargetAsteroid selectedAsteroids context =
    let
        continueWithWarpToMiningSite =
            returnDronesToBay context
                |> Maybe.withDefault (warpToMiningSite context)
    in
    case selectedAsteroids.asteroidMatchingSettings of
        Nothing ->
            case selectedAsteroids.clickableAsteroids of
                [] ->
                    describeBranch "I see no clickable asteroid in the overview. Warp to mining site."
                        continueWithWarpToMiningSite

                clickableAsteroids ->
                    describeBranch
                        ("I see "
                            ++ String.fromInt (List.length clickableAsteroids)
                            ++ "clickable asteroids in the overview. But none of these matches the filter from settings. Warp to other mining site."
                        )
                        continueWithWarpToMiningSite

        Just ( asteroidInOverview, _ ) ->
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


selectAsteroidsFromOverview : BotDecisionContext -> Result String SelectedAsteroidsFromOverview
selectAsteroidsFromOverview context =
    let
        clickableAsteroids =
            clickableAsteroidsFromOverviewWindow context.readingFromGameClient

        continueWithAsteroidMatchingSettings asteroidMatchingSettings =
            Ok
                { clickableAsteroids = clickableAsteroids
                , asteroidMatchingSettings = asteroidMatchingSettings
                }
    in
    clickableAsteroids
        |> List.filter (asteroidOverviewEntryMatchesSettings context.eventContext.botSettings)
        |> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        |> List.sortBy (.objectDistanceInMeters >> Result.withDefault 9999999)
        |> List.head
        |> Maybe.map
            (\overviewEntry ->
                overviewEntry.objectDistanceInMeters
                    |> Result.mapError
                        ((++)
                            ("Failed to read the distance on overview entry "
                                ++ (overviewEntry.objectName |> Maybe.withDefault "")
                                ++ ": "
                            )
                        )
                    |> Result.andThen
                        (\distanceInMeters ->
                            ( overviewEntry
                            , { closeEnoughForMining =
                                    distanceInMeters
                                        <= min context.eventContext.botSettings.targetingRange
                                            context.eventContext.botSettings.miningModuleRange
                              }
                            )
                                |> Just
                                |> continueWithAsteroidMatchingSettings
                        )
            )
        |> Maybe.withDefault (continueWithAsteroidMatchingSettings Nothing)


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
                    case findInventoryButtonInNeocom readingFromGameClient of
                        Just inventoryButton ->
                            describeBranch "Opening the inventory window."
                                (case mouseClickOnUIElement MouseButtonLeft inventoryButton of
                                    Err _ ->
                                        describeBranch "Failed to click inventory button" askForHelpToGetUnstuck

                                    Ok clickAction ->
                                        decideActionForCurrentStep clickAction
                                )

                        Nothing ->
                            describeBranch "Could not find the inventory button in the Neocom." askForHelpToGetUnstuck

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
                                                        (mouseClickOnUIElement MouseButtonLeft toggleBtn
                                                            |> Result.Extra.unpack
                                                                (always (describeBranch "Failed to click" askForHelpToGetUnstuck))
                                                                decideActionForCurrentStep
                                                        )
                                            )

                                    Just miningHoldTreeEntry ->
                                        describeBranch "Click the tree entry representing the mining hold."
                                            (mouseClickOnUIElement MouseButtonLeft miningHoldTreeEntry.uiNode
                                                |> Result.Extra.unpack
                                                    (always (describeBranch "Failed to click" askForHelpToGetUnstuck))
                                                    decideActionForCurrentStep
                                            )
                        )


{-| Returns the inventory button in the neocom (Ready to be clicked on)
-}
findInventoryButtonInNeocom : ReadingFromGameClient -> Maybe UIElement
findInventoryButtonInNeocom readingFromGameClient =
    case readingFromGameClient.neocom of
        Nothing ->
            Nothing

        Just insideNeoCom ->
            insideNeoCom.inventoryButton


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
    { namesFromSettingOrInfoPanel : List String }
    -> BotDecisionContext
    ->
        { viaLocationsWindow : Maybe DecisionPathNode
        , viaOverview : Maybe DecisionPathNode
        , viaSolarSystemMenu : () -> DecisionPathNode
        }
dockToStationOrStructureWithMatchingName { namesFromSettingOrInfoPanel } context =
    let
        destNamesSimplified : List String
        destNamesSimplified =
            List.map
                simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                namesFromSettingOrInfoPanel

        {-
           2023-01-11 Observation by Dean: Text in surroundings context menu entry sometimes wraps station name in XML tags:
           <color=#FF58A7BF>Niyabainen IV - M1 - Caldari Navy Assembly Plant</color>
        -}
        displayTextRepresentsMatchingStation : String -> Bool
        displayTextRepresentsMatchingStation displayName =
            let
                displayNameSimplified =
                    simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                        displayName
            in
            List.any
                (\destName ->
                    String.contains destName displayNameSimplified
                )
                destNamesSimplified
    in
    useContextMenuOnLocationWithMatchingName
        displayTextRepresentsMatchingStation
        (useMenuEntryWithTextContaining "dock" menuCascadeCompleted)
        context


useContextMenuOnLocationWithMatchingName :
    (String -> Bool)
    -> EveOnline.BotFramework.UseContextMenuCascadeNode
    -> BotDecisionContext
    ->
        { viaLocationsWindow : Maybe DecisionPathNode
        , viaOverview : Maybe DecisionPathNode
        , viaSolarSystemMenu : () -> DecisionPathNode
        }
useContextMenuOnLocationWithMatchingName nameMatches useMenu context =
    let
        viaLocationsWindow : Maybe DecisionPathNode
        viaLocationsWindow =
            case context.readingFromGameClient.locationsWindow of
                Nothing ->
                    Nothing

                Just locationsWindow ->
                    case
                        locationsWindow.placeEntries
                            |> List.filter (.mainText >> nameMatches)
                            |> List.head
                    of
                        Nothing ->
                            Nothing

                        Just placeEntry ->
                            Just
                                (EveOnline.BotFrameworkSeparatingMemory.useContextMenuCascade
                                    ( placeEntry.mainText, placeEntry.uiNode )
                                    useMenu
                                    context
                                )

        matchingOverviewEntry : Maybe OverviewWindowEntry
        matchingOverviewEntry =
            context.readingFromGameClient.overviewWindows
                |> List.concatMap .entries
                |> List.filter
                    (.objectName
                        >> Maybe.map nameMatches
                        >> Maybe.withDefault False
                    )
                |> List.head

        viaOverview =
            case matchingOverviewEntry of
                Just overviewEntry ->
                    Just
                        (EveOnline.BotFrameworkSeparatingMemory.useContextMenuCascadeOnOverviewEntry
                            useMenu
                            overviewEntry
                            context
                        )

                Nothing ->
                    Nothing
    in
    { viaLocationsWindow = viaLocationsWindow
    , viaOverview = viaOverview
    , viaSolarSystemMenu =
        \() ->
            let
                overviewWindowScrollControls =
                    context.readingFromGameClient.overviewWindows
                        |> List.filterMap .scrollControls
                        |> List.head
            in
            overviewWindowScrollControls
                |> Maybe.andThen scrollDown
                |> Maybe.withDefault
                    (useContextMenuCascadeOnListSurroundingsButton
                        (useMenuEntryWithTextContainingFirstOf
                            [ "locations" ]
                            (useMenuEntryInLastContextMenuInCascade
                                { describeChoice = "select using the configured predicate"
                                , chooseEntry =
                                    List.filter (.text >> nameMatches)
                                        >> List.head
                                }
                                useMenu
                            )
                        )
                        context
                    )
    }


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
                            (EffectOnWindow.effectsMouseClickAtLocation
                                EffectOnWindow.MouseButtonLeft
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
    String.toLower
        >> String.replace "moon " "m"
        >> String.replace "," ""
        >> String.replace "." ""
        >> String.trim


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
    case context.eventContext.botSettings.miningSites of
        [] ->
            warpToRandomAsteroidBelt context

        miningSites ->
            let
                miningSitesSimplified : List String
                miningSitesSimplified =
                    List.map
                        simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                        miningSites

                travelOptions =
                    useContextMenuOnLocationWithMatchingName
                        (\displayName ->
                            List.any
                                (\miningSite ->
                                    String.contains
                                        miningSite
                                        (simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                                            displayName
                                        )
                                )
                                miningSitesSimplified
                        )
                        (useMenuEntryWithTextContaining "Warp to"
                            (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
                        )
                        context
            in
            case travelOptions.viaLocationsWindow of
                Just viaLocationsWindow ->
                    viaLocationsWindow

                Nothing ->
                    case travelOptions.viaOverview of
                        Just viaOverview ->
                            viaOverview

                        Nothing ->
                            describeBranch "I do not see a matching name in the Locations or overview windows. Therefore, we are falling back to the solar system menu."
                                (travelOptions.viaSolarSystemMenu ())


warpToRandomAsteroidBelt : BotDecisionContext -> DecisionPathNode
warpToRandomAsteroidBelt context =
    useContextMenuCascadeOnListSurroundingsButton
        (useMenuEntryWithTextContaining "asteroid belts"
            (useRandomMenuEntry (context.randomIntegers |> List.head |> Maybe.withDefault 0)
                (useMenuEntryWithTextContaining "Warp to"
                    (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
                )
            )
        )
        context


runAway : BotDecisionContext -> DecisionPathNode
runAway context =
    let
        defaultRoute : () -> DecisionPathNode
        defaultRoute () =
            dockToRandomStationOrStructure context
    in
    case unloadStationOrStructureNames context of
        [] ->
            defaultRoute ()

        stationAndStructureNames ->
            {-
               Prioritize unload station and overview entry, because that will be faster than using the surroundings button menu. If that fails, fall back to surroundings menu.
               <https://forum.botlab.org/t/the-mining-robot-cant-find-its-way-home/4922/4>
            -}
            let
                routesToStation =
                    dockToStationOrStructureWithMatchingName
                        { namesFromSettingOrInfoPanel = stationAndStructureNames }
                        context
            in
            case routesToStation.viaLocationsWindow of
                Just viaLocationsWindow ->
                    viaLocationsWindow

                Nothing ->
                    case routesToStation.viaOverview of
                        Just viaOverview ->
                            viaOverview

                        Nothing ->
                            defaultRoute ()


dockToUnloadOre : BotDecisionContext -> DecisionPathNode
dockToUnloadOre context =
    case unloadStationOrStructureNames context of
        [] ->
            describeBranch
                "At which station should I dock?. There is no station or structure name configured and I was never docked in a station in this session."
                askForHelpToGetUnstuck

        stationAndStructureNames ->
            let
                routesToStation :
                    { viaLocationsWindow : Maybe DecisionPathNode
                    , viaOverview : Maybe DecisionPathNode
                    , viaSolarSystemMenu : () -> DecisionPathNode
                    }
                routesToStation =
                    dockToStationOrStructureWithMatchingName
                        { namesFromSettingOrInfoPanel = stationAndStructureNames }
                        context
            in
            case routesToStation.viaLocationsWindow of
                Just viaLocationsWindow ->
                    viaLocationsWindow

                Nothing ->
                    case routesToStation.viaOverview of
                        Just viaOverview ->
                            viaOverview

                        Nothing ->
                            describeBranch
                                "I do not see a matching name in the Locations or overview windows. Therefore, we are falling back to the solar system menu."
                                (routesToStation.viaSolarSystemMenu ())


unloadStationOrStructureNames : BotDecisionContext -> List String
unloadStationOrStructureNames context =
    let
        fromSettings : List String
        fromSettings =
            List.concat
                [ context.eventContext.botSettings.unloadStationNames
                , context.eventContext.botSettings.unloadStructureNames
                ]
    in
    if fromSettings == [] then
        case context.memory.lastDockedStationNameFromInfoPanel of
            Just lastDocked ->
                [ lastDocked ]

            Nothing ->
                []

    else
        fromSettings


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
                            dronesInBayQuantity : Int
                            dronesInBayQuantity =
                                case droneGroupInBay.header.quantityFromTitle of
                                    Nothing ->
                                        0

                                    Just quantityFromTitle ->
                                        quantityFromTitle.current

                            dronesInSpaceQuantityCurrent : Int
                            dronesInSpaceQuantityCurrent =
                                case droneGroupInSpace.header.quantityFromTitle of
                                    Nothing ->
                                        0

                                    Just quantityFromTitle ->
                                        quantityFromTitle.current

                            dronesInSpaceQuantityLimit : Int
                            dronesInSpaceQuantityLimit =
                                case droneGroupInSpace.header.quantityFromTitle of
                                    Nothing ->
                                        2

                                    Just quantityFromTitle ->
                                        case quantityFromTitle.maximum of
                                            Nothing ->
                                                2

                                            Just maximum ->
                                                maximum
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
    case context.readingFromGameClient.dronesWindow of
        Nothing ->
            Nothing

        Just dronesWindow ->
            case dronesWindow.droneGroupInSpace of
                Nothing ->
                    Nothing

                Just droneGroupInLocalSpace ->
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


quickMessageHasClusterShutdown : BotDecisionContext -> Maybe String
quickMessageHasClusterShutdown context =
    context.readingFromGameClient
        |> EveOnline.BotFramework.quickMessageFromReadingFromGameClient
        |> Maybe.Extra.filter (Common.Basics.stringContainsIgnoringCase "Cluster Shutdown")


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
    , overviewWindows = EveOnline.BotFramework.initOverviewWindowsMemory
    , lastReadingsInSpaceDronesWindowWasVisible = []
    }


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        readingFromGameClient : ReadingFromGameClient
        readingFromGameClient =
            context.readingFromGameClient

        describeSessionPerformance : String
        describeSessionPerformance =
            [ ( "times unloaded", context.memory.timesUnloaded )
            , ( "volume unloaded / m³", context.memory.volumeUnloadedCubicMeters )
            ]
                |> List.map (\( metric, amount ) -> metric ++ ": " ++ (amount |> String.fromInt))
                |> String.join ", "

        describeShip : String
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

        describeDrones : String
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

        describeMiningHold : String
        describeMiningHold =
            "mining hold filled "
                ++ (readingFromGameClient
                        |> inventoryWindowWithMiningHoldSelectedFromGameClient
                        |> Maybe.andThen capacityGaugeUsedPercent
                        |> Maybe.map String.fromInt
                        |> Maybe.withDefault "Unknown"
                   )
                ++ "%."

        describeCurrentReading : String
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
    , overviewWindows =
        botMemoryBefore.overviewWindows
            |> EveOnline.BotFramework.integrateCurrentReadingsIntoOverviewWindowsMemory context.readingFromGameClient
    , lastReadingsInSpaceDronesWindowWasVisible = lastReadingsInSpaceDronesWindowWasVisible
    }


shouldDockBecauseDroneWindowWasInvisibleTooLong : BotMemory -> Bool
shouldDockBecauseDroneWindowWasInvisibleTooLong memory =
    (dockWhenDroneWindowInvisibleCount <= List.length memory.lastReadingsInSpaceDronesWindowWasVisible)
        && List.all ((==) False) memory.lastReadingsInSpaceDronesWindowWasVisible


ensureUserEnabledNameColumnInOverview :
    { ifEnabled : DecisionPathNode, ifDisabled : DecisionPathNode }
    -> ReadingFromGameClient
    -> DecisionPathNode
ensureUserEnabledNameColumnInOverview { ifEnabled, ifDisabled } readingFromGameClient =
    if
        readingFromGameClient.overviewWindows
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
        >> List.filter (.uiNode >> uiNodeVisibleRegionLargeEnoughForClicking)
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


compressAndStackAllIfConditionsMet :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.InventoryWindow
    -> { miningHoldFillPercent : Int, ifNothingToCompress : DecisionPathNode }
    -> DecisionPathNode
compressAndStackAllIfConditionsMet context inventoryWindowWithMiningHold config =
    let
        closeCompressionWindow =
            case context.readingFromGameClient.compressionWindow of
                Nothing ->
                    stackAllIfSeeingStackableItems
                        inventoryWindowWithMiningHold
                        { ifNotSeeingStackableItems = config.ifNothingToCompress }

                Just compressionWindow ->
                    case compressionWindow.windowControls |> Maybe.andThen .closeButton of
                        Nothing ->
                            describeBranch "Close window button is missing"
                                -- Assume buttons appear on mouse hover
                                (decideActionForCurrentStep
                                    (EveOnline.BotFramework.mouseMoveToUIElement compressionWindow.uiNode)
                                )

                        Just closeButton ->
                            mouseClickOnUIElement MouseButtonLeft closeButton
                                |> Result.Extra.unpack
                                    (always (describeBranch "Failed click on close button" askForHelpToGetUnstuck))
                                    decideActionForCurrentStep
    in
    if context.eventContext.botSettings.compressFromMiningHold /= PromptParser.Yes then
        closeCompressionWindow

    else
        case
            inventoryWindowWithMiningHold
                |> selectedContainerItemsFromInventoryWindow
                |> Maybe.withDefault []
                |> List.filter inventoryItemIsCandidateForCompression
                |> List.head
        of
            Nothing ->
                closeCompressionWindow

            Just itemToCompress ->
                describeBranch "I see at least one item to compress"
                    (if
                        config.miningHoldFillPercent
                            < (context.eventContext.botSettings.unloadMiningHoldPercent // 2)
                     then
                        closeCompressionWindow

                     else
                        case context.readingFromGameClient.compressionWindow of
                            Nothing ->
                                useContextMenuCascade
                                    ( "item to compress", itemToCompress )
                                    (useMenuEntryWithTextContaining "compress" menuCascadeCompleted)
                                    context

                            Just compressionWindow ->
                                case compressionWindow.compressButton of
                                    Nothing ->
                                        describeBranch "Compress button is missing" closeCompressionWindow

                                    Just compressButton ->
                                        mouseClickOnUIElement MouseButtonLeft compressButton
                                            |> Result.Extra.unpack
                                                (always (describeBranch "Failed click on compress button" askForHelpToGetUnstuck))
                                                decideActionForCurrentStep
                    )


stackAllIfSeeingStackableItems :
    EveOnline.ParseUserInterface.InventoryWindow
    -> { ifNotSeeingStackableItems : DecisionPathNode }
    -> DecisionPathNode
stackAllIfSeeingStackableItems inventoryWindow { ifNotSeeingStackableItems } =
    let
        inventoryItemsWithLongestDisplayText =
            inventoryWindow
                |> selectedContainerItemsFromInventoryWindow
                |> Maybe.withDefault []
                |> List.filterMap
                    (\itemNode ->
                        itemNode
                            |> getAllContainedDisplayTextsWithRegion
                            |> List.map Tuple.first
                            |> List.sortBy String.length
                            |> List.reverse
                            |> List.head
                            |> Maybe.map (Tuple.pair itemNode)
                    )

        inventoryItemsGroupedByDisplayText =
            inventoryItemsWithLongestDisplayText
                |> List.Extra.gatherEqualsBy Tuple.second

        stackableItems =
            inventoryItemsGroupedByDisplayText
                |> List.filter (Tuple.second >> List.length >> (<) 1)
    in
    if stackableItems == [] then
        ifNotSeeingStackableItems

    else
        describeBranch
            ("Seeing "
                ++ String.fromInt (List.sum (List.map (Tuple.second >> List.length) stackableItems))
                ++ " stackable items in "
                ++ String.fromInt (List.length stackableItems)
                ++ " groups"
            )
            (case inventoryWindow.buttonToStackAll of
                Nothing ->
                    describeBranch "Missing button to stack all"
                        ifNotSeeingStackableItems

                Just buttonToStackAll ->
                    mouseClickOnUIElement MouseButtonLeft buttonToStackAll
                        |> Result.Extra.unpack
                            (always (describeBranch "Failed click on button" askForHelpToGetUnstuck))
                            decideActionForCurrentStep
            )


inventoryItemIsCandidateForCompression : UIElement -> Bool
inventoryItemIsCandidateForCompression =
    EveOnline.ParseUserInterface.getAllContainedDisplayTextsWithRegion
        >> List.all (Tuple.first >> String.toLower >> String.contains "compressed" >> not)


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
    selectedContainerItemsFromInventoryWindow
        >> Maybe.andThen List.head


selectedContainerItemsFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe (List UIElement)
selectedContainerItemsFromInventoryWindow =
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


randomIntFromInterval : BotDecisionContext -> IntervalInt -> Int
randomIntFromInterval context interval =
    let
        randomInteger =
            context.randomIntegers
                |> List.head
                |> Maybe.withDefault 0

        intervalLength =
            interval.maximum - interval.minimum
    in
    if intervalLength < 1 then
        interval.minimum

    else
        interval.minimum + (randomInteger |> modBy intervalLength)


knownAfterburnerModulesFromContext : BotDecisionContext -> List EveOnline.ParseUserInterface.ShipUIModuleButton
knownAfterburnerModulesFromContext context =
    case context.eventContext.botSettings.afterburnerModuleText of
        Nothing ->
            []

        Just afterburnerText ->
            context.readingFromGameClient.shipUI
                |> Maybe.map .moduleButtons
                |> Maybe.withDefault []
                |> List.filter
                    (\moduleButton ->
                        moduleButton
                            |> EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                            |> Maybe.map
                                (\tooltipMemory ->
                                    tooltipMemory.allContainedDisplayTextsWithRegion
                                        |> List.map Tuple.first
                                        |> List.any (stringContainsIgnoringCase afterburnerText)
                                )
                            |> Maybe.withDefault False
                    )

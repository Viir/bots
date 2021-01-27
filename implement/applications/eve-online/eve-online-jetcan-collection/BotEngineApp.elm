{- 🚧 EVE Online Cerberus jetcan collection bot version 2021-01-27 📦

   As described by Foivos Saropoulos aka Cerberus in several posts:

   + https://forum.botengine.org/t/eve-jetcan-collection/3231/3?u=viir
   + https://forum.botengine.org/t/eve-jetcan-collection/3231/18?u=viir
-}
{-
   bot-catalog-tags:eve-online,mining,jetcan
   authors-forum-usernames:viir,cerberus
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20201207 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow as EffectOnWindow
    exposing
        ( MouseButton(..)
        , effectsForDragAndDrop
        , effectsMouseClickAtLocation
        )
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , ShipModulesMemory
        , clickOnUIElement
        , getEntropyIntFromReadingFromGameClient
        , menuCascadeCompleted
        , useMenuEntryInLastContextMenuInCascade
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        , useMenuEntryWithTextEqual
        )
import EveOnline.AppFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , UpdateMemoryContext
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
        , ParsedUserInterface
        , centerFromDisplayRegion
        )
import Set


{-| Sources for the defaults:

  - <https://forum.botengine.org/t/mining-bot-wont-approach/3162>

-}
defaultBotSettings : BotSettings
defaultBotSettings =
    { runAwayShieldHitpointsThresholdPercent = 70
    , targetingRange = 8000
    , botStepDelayMilliseconds = 2000
    , lastDockedStationNameFromInfoPanel = Nothing
    , oreHoldMaxPercent = 99
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignments { assignmentsSeparators = [ ",", "\n" ] }
        ([ ( "run-away-shield-hitpoints-threshold-percent"
           , AppSettings.valueTypeInteger (\threshold settings -> { settings | runAwayShieldHitpointsThresholdPercent = threshold })
           )
         , ( "targeting-range"
           , AppSettings.valueTypeInteger (\range settings -> { settings | targetingRange = range })
           )
         , ( "ore-hold-max-percent"
           , AppSettings.valueTypeInteger (\percent settings -> { settings | oreHoldMaxPercent = percent })
           )
         , ( "bot-step-delay"
           , AppSettings.valueTypeInteger (\delay settings -> { settings | botStepDelayMilliseconds = delay })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { runAwayShieldHitpointsThresholdPercent : Int
    , targetingRange : Int
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
    , warpToFleetMemberProgressSinceUndock : Maybe WarpToFleetMemberStage
    }


type WarpToFleetMemberStage
    = WarpToFleetMemberCompletedMenu
    | WarpToFleetMemberStartedWarp


type alias BotDecisionContext =
    EveOnline.AppFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias BotState =
    EveOnline.AppFrameworkSeparatingMemory.AppState BotMemory


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings BotState


{-| A first outline of the decision tree for a mining bot came from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
decideNextAction : BotDecisionContext -> DecisionPathNode
decideNextAction context =
    generalSetupInUserInterface context.readingFromGameClient
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                (describeBranch "I see no ship UI, assume we are docked."
                    (ensureOreHoldIsSelectedInInventoryWindow
                        context.readingFromGameClient
                        (dockedWithOreHoldSelected context)
                    )
                )
                (runAwayIfHitpointsAreTooLow context)
                (\seeUndockingComplete ->
                    describeBranch "I see we are in space, undocking complete."
                        (activateShipModulesInMiddleRow context seeUndockingComplete
                            |> Maybe.withDefault
                                (transferItemsFromCargoContainerToOreHold context
                                    |> Maybe.withDefault
                                        (ensureOreHoldIsSelectedInInventoryWindow
                                            context.readingFromGameClient
                                            (inSpaceWithOreHoldSelected context seeUndockingComplete)
                                        )
                                )
                        )
                )
                context.readingFromGameClient
            )


runAwayIfHitpointsAreTooLow : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode
runAwayIfHitpointsAreTooLow context shipUI =
    let
        runAwayWithDescription =
            describeBranch
                ("Shield hitpoints are at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%. Run away.")
                (runAway context)
    in
    if shipUI.hitpointsPercent.shield < context.eventContext.appSettings.runAwayShieldHitpointsThresholdPercent then
        Just runAwayWithDescription

    else
        Nothing


generalSetupInUserInterface : EveOnline.ParseUserInterface.ParsedUserInterface -> Maybe DecisionPathNode
generalSetupInUserInterface gameUserInterface =
    [ closeMessageBox, ensureInfoPanelLocationInfoIsExpanded ]
        |> List.filterMap
            (\maybeSetupDecisionFromGameReading ->
                maybeSetupDecisionFromGameReading gameUserInterface
            )
        |> List.head


closeMessageBox : EveOnline.ParseUserInterface.ParsedUserInterface -> Maybe DecisionPathNode
closeMessageBox gameUserInterface =
    gameUserInterface.messageBoxes
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
                            describeBranch "I see no way to close this message box." waitForProgressInGame

                        Just buttonToUse ->
                            decideActionForCurrentStepWithDescription
                                ( "Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'."
                                , buttonToUse.uiNode |> clickOnUIElement MouseButtonLeft
                                )
                    )
            )


ensureInfoPanelLocationInfoIsExpanded : EveOnline.ParseUserInterface.ParsedUserInterface -> Maybe DecisionPathNode
ensureInfoPanelLocationInfoIsExpanded gameUserInterface =
    case gameUserInterface.infoPanelContainer |> Maybe.andThen .infoPanelLocationInfo of
        Nothing ->
            Just
                (describeBranch "I cannot see the location info panel. Enable the info panel."
                    (case gameUserInterface.infoPanelContainer |> Maybe.andThen .icons |> Maybe.andThen .locationInfo of
                        Nothing ->
                            describeBranch "I cannot see the icon for the location info panel." waitForProgressInGame

                        Just iconLocationInfoPanel ->
                            decideActionForCurrentStepWithDescription
                                ( "Click on the icon to enable the info panel."
                                , iconLocationInfoPanel |> clickOnUIElement MouseButtonLeft
                                )
                    )
                )

        Just infoPanelLocationInfo ->
            if 35 < infoPanelLocationInfo.uiNode.totalDisplayRegion.height then
                Nothing

            else
                Just
                    (describeBranch "Location info panel seems collapsed."
                        (decideActionForCurrentStepWithDescription
                            ( "Click to expand the info panel."
                            , effectsMouseClickAtLocation
                                MouseButtonLeft
                                { x = infoPanelLocationInfo.uiNode.totalDisplayRegion.x + 8
                                , y = infoPanelLocationInfo.uiNode.totalDisplayRegion.y + 8
                                }
                            )
                        )
                    )


dockedWithOreHoldSelected : BotDecisionContext -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
dockedWithOreHoldSelected context inventoryWindowWithOreHoldSelected =
    case inventoryWindowWithOreHoldSelected |> itemHangarFromInventoryWindow of
        Nothing ->
            describeBranch "I do not see the item hangar in the inventory." waitForProgressInGame

        Just itemHangar ->
            case inventoryWindowWithOreHoldSelected |> selectedContainerFirstItemFromInventoryWindow of
                Nothing ->
                    describeBranch "I see no item in the ore hold. Time to undock."
                        (undockUsingStationWindow context)

                Just itemInInventory ->
                    describeBranch "I see at least one item in the ore hold. Move this to the item hangar."
                        (decideActionForCurrentStepWithDescription
                            ( "Drag and drop."
                            , effectsForDragAndDrop
                                { startLocation = itemInInventory.totalDisplayRegion |> centerFromDisplayRegion
                                , endLocation = itemHangar.totalDisplayRegion |> centerFromDisplayRegion
                                , mouseButton = MouseButtonLeft
                                }
                            )
                        )


undockUsingStationWindow : BotDecisionContext -> DecisionPathNode
undockUsingStationWindow context =
    case context.readingFromGameClient.stationWindow of
        Nothing ->
            describeBranch "I do not see the station window." askForHelpToGetUnstuck

        Just stationWindow ->
            case stationWindow.undockButton of
                Nothing ->
                    case stationWindow.abortUndockButton of
                        Nothing ->
                            describeBranch "I do not see the undock button." askForHelpToGetUnstuck

                        Just _ ->
                            describeBranch "I see we are already undocking." waitForProgressInGame

                Just undockButton ->
                    describeBranch "Click on the button to undock."
                        (decideActionForCurrentStep
                            (clickOnUIElement MouseButtonLeft undockButton)
                        )


transferItemsFromCargoContainerToOreHold : BotDecisionContext -> Maybe DecisionPathNode
transferItemsFromCargoContainerToOreHold context =
    case context.readingFromGameClient.inventoryWindows |> List.head of
        Nothing ->
            Nothing

        Just inventoryWindow ->
            if inventoryWindow |> inventoryWindowSelectedContainerIsJetCan |> not then
                Nothing

            else
                case inventoryWindow |> selectedContainerFirstItemFromInventoryWindow of
                    Nothing ->
                        Nothing

                    Just itemInInventory ->
                        Just
                            (describeBranch "I see at least one item in the cargo container. Move this to the ore hold."
                                (case inventoryWindow |> activeShipTreeEntryFromInventoryWindow of
                                    Nothing ->
                                        describeBranch "I do not see the active ship in the inventory." waitForProgressInGame

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
                                                describeBranch "I do not see the ore hold in the inventory." waitForProgressInGame

                                            Just oreHoldTreeEntry ->
                                                decideActionForCurrentStepWithDescription
                                                    ( "Drag and drop."
                                                    , effectsForDragAndDrop
                                                        { startLocation = itemInInventory.totalDisplayRegion |> centerFromDisplayRegion
                                                        , endLocation = oreHoldTreeEntry.uiNode.totalDisplayRegion |> centerFromDisplayRegion
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
            context.eventContext.appSettings.lastDockedStationNameFromInfoPanel


activateShipModulesInMiddleRow : BotDecisionContext -> SeeUndockingComplete -> Maybe DecisionPathNode
activateShipModulesInMiddleRow context seeUndockingComplete =
    case seeUndockingComplete.shipUI.moduleButtonsRows.middle |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
        Just inactiveModule ->
            Just
                (describeBranch "I see an inactive module in the middle row. Activate it."
                    (decideActionForCurrentStepWithDescription
                        ( "Click on the module.", inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft )
                    )
                )

        Nothing ->
            Nothing


inSpaceWithOreHoldSelected : BotDecisionContext -> SeeUndockingComplete -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
inSpaceWithOreHoldSelected context seeUndockingComplete inventoryWindowWithOreHoldSelected =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        describeBranch "I see we are warping."
            (readShipUIModuleButtonTooltips context |> Maybe.withDefault waitForProgressInGame)

    else
        case inventoryWindowWithOreHoldSelected |> capacityGaugeUsedPercent of
            Nothing ->
                describeBranch "I cannot see the ore hold capacity gauge." waitForProgressInGame

            Just fillPercent ->
                let
                    describeThresholdToUnload =
                        (context.eventContext.appSettings.oreHoldMaxPercent |> String.fromInt) ++ "%"
                in
                if context.eventContext.appSettings.oreHoldMaxPercent <= fillPercent then
                    describeBranch ("The ore hold is filled at least " ++ describeThresholdToUnload ++ ". Unload the ore.")
                        (case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
                            Nothing ->
                                describeBranch "At which station should I dock?. I was never docked in a station in this session." waitForProgressInGame

                            Just lastDockedStationNameFromInfoPanel ->
                                dockToStationOrStructureWithMatchingName
                                    { nameFromSettingOrInfoPanel = lastDockedStationNameFromInfoPanel
                                    , prioritizeStructures = False
                                    }
                                    context
                        )

                else
                    describeBranch ("The ore hold is not yet filled " ++ describeThresholdToUnload ++ ". Get more ore from jet cans.")
                        (getMoreOreFromJetCans context seeUndockingComplete)


getMoreOreFromJetCans : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
getMoreOreFromJetCans context seeUndockingComplete =
    case context.memory.warpToFleetMemberProgressSinceUndock of
        Nothing ->
            warpToFleetMember context

        Just WarpToFleetMemberCompletedMenu ->
            warpToFleetMember context

        Just WarpToFleetMemberStartedWarp ->
            {- Cerberus overview config only shows jetcans:
               ('point mouse on overview panel (i have set one that show only cans) on the first available can')
               (https://forum.botengine.org/t/eve-jetcan-collection/3231/5?u=viir)
            -}
            case
                context.readingFromGameClient.overviewWindow
                    |> Maybe.andThen (.entries >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y) >> List.head)
            of
                Nothing ->
                    describeBranch "I see no jetcan in the overview."
                        (describeBranch "wait for next can (this may be a long period some times above 10 minutes)"
                            (readShipUIModuleButtonTooltips context |> Maybe.withDefault waitForProgressInGame)
                        )

                Just jetcanInOverview ->
                    describeBranch
                        ("Choosing jetcan '" ++ (jetcanInOverview.objectName |> Maybe.withDefault "Nothing") ++ "'")
                        (if jetcanInOverview |> overviewEntryIsTargetedOrTargeting then
                            let
                                moduleIsActive =
                                    seeUndockingComplete.shipUI.moduleButtons |> List.any (.isActive >> Maybe.withDefault False)

                                keyDownAndKeyUpOnF5 =
                                    [ EffectOnWindow.KeyDown keyCodeF5
                                    , EffectOnWindow.KeyUp keyCodeF5
                                    ]
                            in
                            case jetcanInOverview.objectDistanceInMeters of
                                Err parseDistanceError ->
                                    describeBranch ("Failed to parse distance: " ++ parseDistanceError) waitForProgressInGame

                                Ok jetcanDistanceInMeters ->
                                    if jetcanDistanceInMeters < 2000 then
                                        if moduleIsActive then
                                            describeBranch "Module is active."
                                                (decideActionForCurrentStepWithDescription
                                                    ( "deactivate module with F5 again", keyDownAndKeyUpOnF5 )
                                                )

                                        else
                                            useContextMenuCascadeOnOverviewEntry
                                                (useMenuEntryWithTextContaining "open cargo" menuCascadeCompleted)
                                                jetcanInOverview
                                                context

                                    else if moduleIsActive then
                                        describeBranch "Module is active."
                                            (describeBranch "wait for can to be within 2000m." waitForProgressInGame)

                                    else
                                        decideActionForCurrentStepWithDescription
                                            ( "enable module with keyboard button F5", keyDownAndKeyUpOnF5 )

                         else
                            lockTargetFromOverviewEntry jetcanInOverview context
                        )


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.AppFrameworkSeparatingMemory.readShipUIModuleButtonTooltipWhereNotYetInMemory


keyCodeF5 : EffectOnWindow.VirtualKeyCode
keyCodeF5 =
    EffectOnWindow.VirtualKeyCodeFromInt 0x74


ensureOreHoldIsSelectedInInventoryWindow : ParsedUserInterface -> (EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode) -> DecisionPathNode
ensureOreHoldIsSelectedInInventoryWindow parsedUserInterface continueWithInventoryWindow =
    case parsedUserInterface |> inventoryWindowWithOreHoldSelectedFromUserInterface of
        Just inventoryWindow ->
            continueWithInventoryWindow inventoryWindow

        Nothing ->
            case parsedUserInterface.inventoryWindows |> List.head of
                Nothing ->
                    describeBranch "I do not see an inventory window. Please open an inventory window." waitForProgressInGame

                Just inventoryWindow ->
                    describeBranch
                        "Ore hold is not selected. Select the ore hold."
                        (case inventoryWindow |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                describeBranch "I do not see the active ship in the inventory." waitForProgressInGame

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
                                                        waitForProgressInGame

                                                Just toggleBtn ->
                                                    decideActionForCurrentStepWithDescription
                                                        ( "Click the toggle button to expand."
                                                        , toggleBtn |> clickOnUIElement MouseButtonLeft
                                                        )
                                            )

                                    Just oreHoldTreeEntry ->
                                        decideActionForCurrentStepWithDescription
                                            ( "Click the tree entry representing the ore hold."
                                            , oreHoldTreeEntry.uiNode |> clickOnUIElement MouseButtonLeft
                                            )
                        )


lockTargetFromOverviewEntry : OverviewWindowEntry -> BotDecisionContext -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry context =
    describeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
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
        displayTextRepresentsMatchingStation =
            simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                >> String.startsWith (nameFromSettingOrInfoPanel |> simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry)

        matchingOverviewEntry =
            context.readingFromGameClient.overviewWindow
                |> Maybe.map .entries
                |> Maybe.withDefault []
                |> List.filter (.objectName >> Maybe.map displayTextRepresentsMatchingStation >> Maybe.withDefault False)
                |> List.head

        overviewWindowScrollControls =
            context.readingFromGameClient.overviewWindow
                |> Maybe.andThen .scrollControls
    in
    matchingOverviewEntry
        |> Maybe.map
            (\entry ->
                EveOnline.AppFrameworkSeparatingMemory.useContextMenuCascadeOnOverviewEntry
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


{-| Prepare a station name or structure name coming from app-settings for comparing with menu entries.

  - The user could take the name from the info panel:
    The names sometimes differ between info panel and menu entries: 'Moon 7' can become 'M7'.

  - Do not distinguish between the comma and period characters:
    Besides the similar visual appearance, also because of the limitations of popular app-settings parsing frameworks.
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


warpToFleetMember : BotDecisionContext -> DecisionPathNode
warpToFleetMember context =
    case context.readingFromGameClient.chatWindowStacks |> List.head |> Maybe.andThen .chatWindow of
        Nothing ->
            describeBranch "I don't see a chat window. Make the fleet chat visible." waitForProgressInGame

        Just chatWindow ->
            case
                chatWindow.userlist
                    |> Maybe.map .visibleUsers
                    |> Maybe.withDefault []
                    |> List.filter (.standingIconHint >> Maybe.map (String.toLower >> String.contains "is in your fleet") >> Maybe.withDefault False)
                    |> List.head
            of
                Nothing ->
                    describeBranch "I don't see a chat member which 'is in your fleet'." waitForProgressInGame

                Just chatMemberInYourFleet ->
                    useContextMenuCascade
                        ( "on fleet chat the character name.", chatMemberInYourFleet.uiNode )
                        (useMenuEntryWithTextContaining "fleet"
                            (useMenuEntryWithTextContaining "warp to member within"
                                (useMenuEntryWithTextContaining "warp to 0"
                                    menuCascadeCompleted
                                )
                            )
                        )
                        context


runAway : BotDecisionContext -> DecisionPathNode
runAway context =
    case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
        Nothing ->
            dockToRandomStationOrStructure context

        Just lastDockedStationNameFromInfoPanel ->
            dockToStationOrStructureWithMatchingName
                { nameFromSettingOrInfoPanel = lastDockedStationNameFromInfoPanel
                , prioritizeStructures = False
                }
                context


dockToRandomStationOrStructure : BotDecisionContext -> DecisionPathNode
dockToRandomStationOrStructure context =
    dockToStationOrStructureUsingSurroundingsButtonMenu
        { prioritizeStructures = False
        , describeChoice = "Pick random station"
        , chooseEntry = listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient context.readingFromGameClient)
        }
        context


decideActionForCurrentStepWithDescription : ( String, List EffectOnWindow.EffectOnWindowStructure ) -> DecisionPathNode
decideActionForCurrentStepWithDescription ( description, effects ) =
    describeBranch description (decideActionForCurrentStep effects)


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


branchDependingOnDockedOrInSpace :
    DecisionPathNode
    -> (EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode)
    -> (SeeUndockingComplete -> DecisionPathNode)
    -> ParsedUserInterface
    -> DecisionPathNode
branchDependingOnDockedOrInSpace branchIfDocked branchIfCanSeeShipUI branchIfUndockingComplete parsedUserInterface =
    case parsedUserInterface.shipUI of
        Nothing ->
            branchIfDocked

        Just shipUI ->
            branchIfCanSeeShipUI shipUI
                |> Maybe.withDefault
                    (case parsedUserInterface.overviewWindow of
                        Nothing ->
                            describeBranch "I see no overview window, wait until undocking completed." waitForProgressInGame

                        Just overviewWindow ->
                            branchIfUndockingComplete
                                { shipUI = shipUI, overviewWindow = overviewWindow }
                    )


initState : State
initState =
    EveOnline.AppFrameworkSeparatingMemory.initState
        { lastDockedStationNameFromInfoPanel = Nothing
        , timesUnloaded = 0
        , volumeUnloadedCubicMeters = 0
        , lastUsedCapacityInOreHold = Nothing
        , shipModules = initShipModulesMemory
        , warpToFleetMemberProgressSinceUndock = Nothing
        }


initShipModulesMemory : ShipModulesMemory
initShipModulesMemory =
    { tooltipFromModuleButton = Dict.empty
    , lastReadingTooltip = Nothing
    }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFrameworkSeparatingMemory.processEvent
        { parseAppSettings = parseBotSettings
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
        , statusTextFromDecisionContext = statusTextFromDecisionContext
        , decideNextStep = decideNextAction
        }


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        describeSessionPerformance =
            [ ( "times unloaded", context.memory.timesUnloaded )
            , ( "volume unloaded / m³", context.memory.volumeUnloadedCubicMeters )
            ]
                |> List.map (\( metric, amount ) -> metric ++ ": " ++ (amount |> String.fromInt))
                |> String.join ", "

        describeShip =
            case context.readingFromGameClient.shipUI of
                Just shipUI ->
                    "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                Nothing ->
                    case
                        context.readingFromGameClient.infoPanelContainer
                            |> Maybe.andThen .infoPanelLocationInfo
                            |> Maybe.andThen .expandedContent
                            |> Maybe.andThen .currentStationName
                    of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I cannot see if I am docked or in space. Please set up game client first."

        describeOreHold =
            "Ore hold filled "
                ++ (context.readingFromGameClient
                        |> inventoryWindowWithOreHoldSelectedFromUserInterface
                        |> Maybe.andThen capacityGaugeUsedPercent
                        |> Maybe.map String.fromInt
                        |> Maybe.withDefault "Unknown"
                   )
                ++ "%."

        describeCurrentReading =
            [ describeOreHold, describeShip ] |> String.join " "
    in
    [ "Session performance: " ++ describeSessionPerformance
    , "---"
    , "Current reading: " ++ describeCurrentReading
    ]
        |> String.join "\n"


updateMemoryForNewReadingFromGame : UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =
    let
        currentStationNameFromInfoPanel =
            context.readingFromGameClient.infoPanelContainer
                |> Maybe.andThen .infoPanelLocationInfo
                |> Maybe.andThen .expandedContent
                |> Maybe.andThen .currentStationName

        lastUsedCapacityInOreHold =
            context.readingFromGameClient
                |> inventoryWindowWithOreHoldSelectedFromUserInterface
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

        warpToFleetMemberProgressSinceUndock =
            case context.readingFromGameClient.shipUI of
                Nothing ->
                    Nothing

                Just shipUI ->
                    if
                        (shipUI |> isShipWarpingOrJumping)
                            && (botMemoryBefore.warpToFleetMemberProgressSinceUndock == Just WarpToFleetMemberCompletedMenu)
                    then
                        Just WarpToFleetMemberStartedWarp

                    else
                        botMemoryBefore.warpToFleetMemberProgressSinceUndock
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
            |> integrateCurrentReadingsIntoShipModulesMemory context.readingFromGameClient
    , warpToFleetMemberProgressSinceUndock = warpToFleetMemberProgressSinceUndock
    }


getModuleButtonIdentifierInMemory : EveOnline.ParseUserInterface.ShipUIModuleButton -> String
getModuleButtonIdentifierInMemory =
    .uiNode >> .uiNode >> .pythonObjectAddress


integrateCurrentReadingsIntoShipModulesMemory : ParsedUserInterface -> ShipModulesMemory -> ShipModulesMemory
integrateCurrentReadingsIntoShipModulesMemory currentReading memoryBefore =
    let
        getTooltipDataForEqualityComparison tooltip =
            tooltip.uiNode
                |> EveOnline.ParseUserInterface.getAllContainedDisplayTextsWithRegion
                |> List.map (Tuple.mapSecond .totalDisplayRegion)

        {- To ensure robustness, we store a new tooltip only when the display texts match in two consecutive readings from the game client. -}
        tooltipAvailableToStore =
            case ( memoryBefore.lastReadingTooltip, currentReading.moduleButtonTooltip ) of
                ( Just previousTooltip, Just currentTooltip ) ->
                    if getTooltipDataForEqualityComparison previousTooltip == getTooltipDataForEqualityComparison currentTooltip then
                        Just currentTooltip

                    else
                        Nothing

                _ ->
                    Nothing

        visibleModuleButtons =
            currentReading.shipUI
                |> Maybe.map .moduleButtons
                |> Maybe.withDefault []

        visibleModuleButtonsIds =
            visibleModuleButtons |> List.map getModuleButtonIdentifierInMemory

        maybeModuleButtonWithHighlight =
            visibleModuleButtons
                |> List.filter .isHiliteVisible
                |> List.head

        tooltipFromModuleButtonAddition =
            case ( tooltipAvailableToStore, maybeModuleButtonWithHighlight ) of
                ( Just tooltip, Just moduleButtonWithHighlight ) ->
                    Dict.insert (moduleButtonWithHighlight |> getModuleButtonIdentifierInMemory) tooltip

                _ ->
                    identity

        tooltipFromModuleButton =
            memoryBefore.tooltipFromModuleButton
                |> tooltipFromModuleButtonAddition
                |> Dict.filter (\moduleButtonId _ -> visibleModuleButtonsIds |> List.member moduleButtonId)
    in
    { tooltipFromModuleButton = tooltipFromModuleButton
    , lastReadingTooltip = currentReading.moduleButtonTooltip
    }


activeShipTreeEntryFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe EveOnline.ParseUserInterface.InventoryWindowLeftTreeEntry
activeShipTreeEntryFromInventoryWindow =
    .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


overviewEntryIsTargetedOrTargeting : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsTargetedOrTargeting =
    .namesUnderSpaceObjectIcon
        >> Set.intersect ([ "targetedByMeIndicator", "targeting" ] |> Set.fromList)
        >> Set.isEmpty
        >> not


capacityGaugeUsedPercent : EveOnline.ParseUserInterface.InventoryWindow -> Maybe Int
capacityGaugeUsedPercent =
    .selectedContainerCapacityGauge
        >> Maybe.andThen Result.toMaybe
        >> Maybe.andThen
            (\capacity -> capacity.maximum |> Maybe.map (\maximum -> capacity.used * 100 // maximum))


inventoryWindowWithOreHoldSelectedFromUserInterface : ParsedUserInterface -> Maybe EveOnline.ParseUserInterface.InventoryWindow
inventoryWindowWithOreHoldSelectedFromUserInterface =
    .inventoryWindows
        >> List.filter inventoryWindowSelectedContainerIsOreHold
        >> List.head


inventoryWindowSelectedContainerIsOreHold : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsOreHold =
    .subCaptionLabelText >> Maybe.map (String.toLower >> String.contains "ore hold") >> Maybe.withDefault False


inventoryWindowSelectedContainerIsJetCan : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsJetCan =
    .subCaptionLabelText >> Maybe.map (String.toLower >> String.contains "cargo container") >> Maybe.withDefault False


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


isShipWarpingOrJumping : EveOnline.ParseUserInterface.ShipUI -> Bool
isShipWarpingOrJumping =
    .indication
        >> Maybe.andThen .maneuverType
        >> Maybe.map
            (\maneuverType ->
                [ EveOnline.ParseUserInterface.ManeuverWarp, EveOnline.ParseUserInterface.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


listElementAtWrappedIndex : Int -> List element -> Maybe element
listElementAtWrappedIndex indexToWrap list =
    if (list |> List.length) < 1 then
        Nothing

    else
        list |> List.drop (indexToWrap |> modBy (list |> List.length)) |> List.head

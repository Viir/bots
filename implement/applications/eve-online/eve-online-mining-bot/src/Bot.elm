{- EVE Online mining bot version 2020-05-15

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
import EveOnline.AppFramework exposing (AppEffect(..), ShipModulesMemory, getEntropyIntFromUserInterface)
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ParsedUserInterface
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
    , parsedUserInterface : ParsedUserInterface
    }


botSettingsFromDecisionContext : BotDecisionContext -> BotSettings
botSettingsFromDecisionContext decisionContext =
    decisionContext.eventContext.appSettings |> Maybe.withDefault defaultBotSettings


type alias UIElement =
    EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion


type alias TreeLeafAct =
    { actionsAlreadyDecided : ( String, List VolatileHostInterface.EffectOnWindowStructure )
    , actionsDependingOnNewReadings : List ( String, ParsedUserInterface -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
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
            , remainingActions : List ( String, ParsedUserInterface -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
            }
    , botMemory : BotMemory
    }


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings BotState


{-| A first outline of the decision tree for a mining bot came from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
decideNextAction : BotDecisionContext -> DecisionPathNode
decideNextAction context =
    generalSetupInUserInterface context.parsedUserInterface
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                (DescribeBranch "I see no ship UI, assume we are docked."
                    (ensureOreHoldIsSelectedInInventoryWindow
                        context.parsedUserInterface
                        dockedWithOreHoldSelected
                    )
                )
                (returnDronesAndRunAwayIfHitpointsAreTooLow context)
                (\seeUndockingComplete ->
                    DescribeBranch "I see we are in space, undocking complete."
                        (ensureOreHoldIsSelectedInInventoryWindow
                            context.parsedUserInterface
                            (inSpaceWithOreHoldSelected context seeUndockingComplete)
                        )
                )
                context.parsedUserInterface
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
        returnDronesToBay context.parsedUserInterface
            |> Maybe.map
                (DescribeBranch
                    ("Shield hitpoints are below " ++ (returnDronesShieldHitpointsThresholdPercent |> String.fromInt) ++ "%. Return drones.")
                )
            |> Maybe.withDefault runAwayWithDescription
            |> Just

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
                DescribeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose =
                            .mainText
                                >> Maybe.map (String.trim >> String.toLower >> (\buttonText -> [ "close", "ok" ] |> List.member buttonText))
                                >> Maybe.withDefault False
                     in
                     case messageBox.buttons |> List.filter buttonCanBeUsedToClose |> List.head of
                        Nothing ->
                            DescribeBranch "I see no way to close this message box." (EndDecisionPath Wait)

                        Just buttonToUse ->
                            EndDecisionPath
                                (actWithoutFurtherReadings
                                    ( "Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'."
                                    , [ buttonToUse.uiNode |> clickOnUIElement MouseButtonLeft ]
                                    )
                                )
                    )
            )


ensureInfoPanelLocationInfoIsExpanded : EveOnline.ParseUserInterface.ParsedUserInterface -> Maybe DecisionPathNode
ensureInfoPanelLocationInfoIsExpanded gameUserInterface =
    case gameUserInterface.infoPanelContainer |> maybeVisibleAndThen .infoPanelLocationInfo of
        CanNotSeeIt ->
            Just
                (DescribeBranch "I cannot see the location info panel. Enable the info panel."
                    (case gameUserInterface.infoPanelContainer |> maybeVisibleAndThen .icons |> maybeVisibleAndThen .locationInfo of
                        CanNotSeeIt ->
                            DescribeBranch "I cannot see the icon for the location info panel." (EndDecisionPath Wait)

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
            DescribeBranch "I do not see the item hangar in the inventory." (EndDecisionPath Wait)

        Just itemHangar ->
            case inventoryWindowWithOreHoldSelected |> selectedContainerFirstItemFromInventoryWindow of
                Nothing ->
                    DescribeBranch "I see no item in the ore hold. Time to undock."
                        (case inventoryWindowWithOreHoldSelected |> activeShipTreeEntryFromInventoryWindow |> Maybe.map .uiNode of
                            Nothing ->
                                EndDecisionPath Wait

                            Just activeShipEntry ->
                                EndDecisionPath
                                    (Act
                                        { actionsAlreadyDecided =
                                            ( "Rightclick on the ship in the inventory window."
                                            , [ activeShipEntry
                                                    |> clickLocationOnInventoryShipEntry
                                                    |> effectMouseClickAtLocation MouseButtonRight
                                              ]
                                            )
                                        , actionsDependingOnNewReadings =
                                            [ ( "Click menu entry 'undock'."
                                              , lastContextMenuOrSubmenu
                                                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Undock")
                                                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
                                              )
                                            ]
                                        }
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
            ([ returnDronesToBay context.parsedUserInterface
             , readShipUIModuleButtonTooltips context
             ]
                |> List.filterMap identity
                |> List.head
                |> Maybe.withDefault (EndDecisionPath Wait)
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
                        DescribeBranch "I cannot see the ore hold capacity gauge." (EndDecisionPath Wait)

                    Just fillPercent ->
                        let
                            describeThresholdToUnload =
                                ((context |> botSettingsFromDecisionContext).oreHoldMaxPercent |> String.fromInt) ++ "%"
                        in
                        if (context |> botSettingsFromDecisionContext).oreHoldMaxPercent <= fillPercent then
                            DescribeBranch ("The ore hold is filled at least " ++ describeThresholdToUnload ++ ". Unload the ore.")
                                (returnDronesToBay context.parsedUserInterface
                                    |> Maybe.withDefault
                                        (case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
                                            Nothing ->
                                                DescribeBranch "At which station should I dock?. I was never docked in a station in this session." (EndDecisionPath Wait)

                                            Just lastDockedStationNameFromInfoPanel ->
                                                dockToStationMatchingNameSeenInInfoPanel
                                                    { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel }
                                                    context.parsedUserInterface
                                        )
                                )

                        else
                            DescribeBranch ("The ore hold is not yet filled " ++ describeThresholdToUnload ++ ". Get more ore.")
                                (case context.parsedUserInterface.targets |> List.head of
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
                                                                    |> Maybe.withDefault (EndDecisionPath Wait)
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
            context.parsedUserInterface.targets
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
                        (Act
                            { actionsAlreadyDecided =
                                ( "Rightclick on the target."
                                , [ targetToUnlock.barAndImageCont
                                        |> Maybe.withDefault targetToUnlock.uiNode
                                        |> clickOnUIElement MouseButtonRight
                                  ]
                                )
                            , actionsDependingOnNewReadings =
                                [ ( "Click menu entry 'unlock'."
                                  , lastContextMenuOrSubmenu
                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "unlock")
                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
                                  )
                                ]
                            }
                        )
                    )
            )


travelToMiningSiteAndLaunchDronesAndTargetAsteroid : BotDecisionContext -> DecisionPathNode
travelToMiningSiteAndLaunchDronesAndTargetAsteroid context =
    case context.parsedUserInterface |> topmostAsteroidFromOverviewWindow of
        Nothing ->
            DescribeBranch "I see no asteroid in the overview. Warp to mining site."
                (returnDronesToBay context.parsedUserInterface
                    |> Maybe.withDefault
                        (warpToMiningSite context.parsedUserInterface)
                )

        Just asteroidInOverview ->
            launchDrones context.parsedUserInterface
                |> Maybe.withDefault
                    (DescribeBranch
                        ("Choosing asteroid '" ++ (asteroidInOverview.objectName |> Maybe.withDefault "Nothing") ++ "'")
                        (lockTargetFromOverviewEntryAndEnsureIsInRange
                            (min (context |> botSettingsFromDecisionContext).targetingRange
                                (context |> botSettingsFromDecisionContext).miningModuleRange
                            )
                            asteroidInOverview
                        )
                    )


ensureOreHoldIsSelectedInInventoryWindow : ParsedUserInterface -> (EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode) -> DecisionPathNode
ensureOreHoldIsSelectedInInventoryWindow parsedUserInterface continueWithInventoryWindow =
    case parsedUserInterface |> inventoryWindowWithOreHoldSelectedFromUserInterface of
        Just inventoryWindow ->
            continueWithInventoryWindow inventoryWindow

        Nothing ->
            case parsedUserInterface.inventoryWindows |> List.head of
                Nothing ->
                    DescribeBranch "I do not see an inventory window. Please open an inventory window." (EndDecisionPath Wait)

                Just inventoryWindow ->
                    DescribeBranch
                        "Ore hold is not selected. Select the ore hold."
                        (case inventoryWindow |> activeShipTreeEntryFromInventoryWindow of
                            Nothing ->
                                DescribeBranch "I do not see the active ship in the inventory." (EndDecisionPath Wait)

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
                                                        (EndDecisionPath Wait)

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


lockTargetFromOverviewEntryAndEnsureIsInRange : Int -> OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntryAndEnsureIsInRange rangeInMeters overviewEntry =
    case overviewEntry.objectDistanceInMeters of
        Ok distanceInMeters ->
            if distanceInMeters <= rangeInMeters then
                if overviewEntry.commonIndications.targetedByMe || overviewEntry.commonIndications.targeting then
                    DescribeBranch "Wait for target locking to complete." (EndDecisionPath Wait)

                else
                    DescribeBranch "Object is in range. Lock target."
                        (lockTargetFromOverviewEntry overviewEntry)

            else
                DescribeBranch ("Object is not in range (" ++ (distanceInMeters |> String.fromInt) ++ " meters away). Approach.")
                    (EndDecisionPath
                        (actStartingWithRightClickOnOverviewEntry
                            overviewEntry
                            [ ( "Click menu entry 'approach'."
                              , lastContextMenuOrSubmenu
                                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "approach")
                                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
                              )
                            ]
                        )
                    )

        Err error ->
            DescribeBranch ("Failed to read the distance: " ++ error) (EndDecisionPath Wait)


lockTargetFromOverviewEntry : OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry =
    DescribeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
        (EndDecisionPath
            (actStartingWithRightClickOnOverviewEntry overviewEntry
                [ ( "Click menu entry 'Lock target'."
                  , lastContextMenuOrSubmenu
                        >> Maybe.andThen (menuEntryWithTextEqualsIgnoringCase "Lock target")
                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
                  )
                ]
            )
        )


dockToStationMatchingNameSeenInInfoPanel : { stationNameFromInfoPanel : String } -> ParsedUserInterface -> DecisionPathNode
dockToStationMatchingNameSeenInInfoPanel { stationNameFromInfoPanel } =
    dockToStationUsingSurroundingsButtonMenu
        ( "Click on menu entry representing the station '" ++ stationNameFromInfoPanel ++ "'."
        , List.filter (menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel)
            >> List.head
        )


dockToStationUsingSurroundingsButtonMenu :
    ( String, List EveOnline.ParseUserInterface.ContextMenuEntry -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry )
    -> ParsedUserInterface
    -> DecisionPathNode
dockToStationUsingSurroundingsButtonMenu ( describeChooseStation, chooseStationMenuEntry ) =
    useContextMenuOnListSurroundingsButton
        [ ( "Click on menu entry 'stations'."
          , lastContextMenuOrSubmenu
                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "stations")
                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
          )
        , ( describeChooseStation
          , lastContextMenuOrSubmenu
                >> Maybe.andThen (.entries >> chooseStationMenuEntry)
                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
          )
        , ( "Click on menu entry 'dock'"
          , lastContextMenuOrSubmenu
                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "dock")
                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
          )
        ]


warpToMiningSite : ParsedUserInterface -> DecisionPathNode
warpToMiningSite parsedUserInterface =
    parsedUserInterface
        |> useContextMenuOnListSurroundingsButton
            [ ( "Click on menu entry 'asteroid belts'."
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "asteroid belts")
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
              )
            , ( "Click on one of the menu entries."
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen
                        (.entries >> listElementAtWrappedIndex (getEntropyIntFromUserInterface parsedUserInterface))
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
              )
            , ( "Click menu entry 'Warp to Within'"
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Warp to Within")
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
              )
            , ( "Click menu entry 'Within 0 m'"
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Within 0 m")
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
              )
            ]


runAway : BotDecisionContext -> DecisionPathNode
runAway context =
    case context |> lastDockedStationNameFromInfoPanelFromMemoryOrSettings of
        Nothing ->
            dockToRandomStation context.parsedUserInterface

        Just lastDockedStationNameFromInfoPanel ->
            dockToStationMatchingNameSeenInInfoPanel
                { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel }
                context.parsedUserInterface


dockToRandomStation : ParsedUserInterface -> DecisionPathNode
dockToRandomStation parsedUserInterface =
    dockToStationUsingSurroundingsButtonMenu
        ( "Pick random station.", listElementAtWrappedIndex (getEntropyIntFromUserInterface parsedUserInterface) )
        parsedUserInterface


launchDrones : ParsedUserInterface -> Maybe DecisionPathNode
launchDrones parsedUserInterface =
    parsedUserInterface.dronesWindow
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
                                        (Act
                                            { actionsAlreadyDecided =
                                                ( "Right click on the drones group."
                                                , [ droneGroupInBay.header.uiNode |> clickOnUIElement MouseButtonRight ]
                                                )
                                            , actionsDependingOnNewReadings =
                                                [ ( "Click menu entry 'Launch drone'."
                                                  , lastContextMenuOrSubmenu
                                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Launch drone")
                                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
                                                  )
                                                ]
                                            }
                                        )
                                    )
                                )

                        else
                            Nothing

                    _ ->
                        Nothing
            )


returnDronesToBay : ParsedUserInterface -> Maybe DecisionPathNode
returnDronesToBay parsedUserInterface =
    parsedUserInterface.dronesWindow
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
                                (Act
                                    { actionsAlreadyDecided =
                                        ( "Rightclick on the drones group."
                                        , [ droneGroupInLocalSpace.header.uiNode |> clickOnUIElement MouseButtonRight ]
                                        )
                                    , actionsDependingOnNewReadings =
                                        [ ( "Click menu entry 'Return to drone bay'."
                                          , lastContextMenuOrSubmenu
                                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Return to drone bay")
                                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
                                          )
                                        ]
                                    }
                                )
                            )
                        )
            )


actWithoutFurtherReadings : ( String, List VolatileHostInterface.EffectOnWindowStructure ) -> EndDecisionPathStructure
actWithoutFurtherReadings actionsAlreadyDecided =
    Act { actionsAlreadyDecided = actionsAlreadyDecided, actionsDependingOnNewReadings = [] }


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips context =
    context.parsedUserInterface.shipUI
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


actStartingWithRightClickOnOverviewEntry :
    OverviewWindowEntry
    -> List ( String, ParsedUserInterface -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
    -> EndDecisionPathStructure
actStartingWithRightClickOnOverviewEntry overviewEntry actionsDependingOnNewReadings =
    Act
        { actionsAlreadyDecided =
            ( "Rightclick on overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'."
            , [ overviewEntry.uiNode |> clickOnUIElement MouseButtonRight ]
            )
        , actionsDependingOnNewReadings = actionsDependingOnNewReadings
        }


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
        CanNotSeeIt ->
            branchIfDocked

        CanSee shipUI ->
            branchIfCanSeeShipUI shipUI
                |> Maybe.withDefault
                    (case parsedUserInterface.overviewWindow of
                        CanNotSeeIt ->
                            DescribeBranch "I see no overview window, wait until undocking completed." (EndDecisionPath Wait)

                        CanSee overviewWindow ->
                            branchIfUndockingComplete
                                { shipUI = shipUI, overviewWindow = overviewWindow }
                    )


useContextMenuOnListSurroundingsButton : List ( String, ParsedUserInterface -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) ) -> ParsedUserInterface -> DecisionPathNode
useContextMenuOnListSurroundingsButton actionsDependingOnNewReadings parsedUserInterface =
    case parsedUserInterface.infoPanelContainer |> maybeVisibleAndThen .infoPanelLocationInfo of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the location info panel." (EndDecisionPath Wait)

        CanSee infoPanelLocationInfo ->
            EndDecisionPath
                (Act
                    { actionsAlreadyDecided =
                        ( "Click on surroundings button."
                        , [ infoPanelLocationInfo.listSurroundingsButton |> clickOnUIElement MouseButtonLeft ]
                        )
                    , actionsDependingOnNewReadings = actionsDependingOnNewReadings
                    }
                )


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
        EveOnline.AppFramework.ReadingFromGameClientCompleted parsedUserInterface ->
            let
                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory parsedUserInterface

                decisionContext =
                    { eventContext = eventContext
                    , memory = botMemory
                    , parsedUserInterface = parsedUserInterface
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

                        ( nextActionDescription, nextActionEffectFromUserInterface ) :: remainingActions ->
                            case parsedUserInterface |> nextActionEffectFromUserInterface of
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
                    [ describeStateForMonitoring parsedUserInterface botMemory, describeActivity ]
                        |> String.join "\n"
            in
            ( { stateBefore | botMemory = botMemory, programState = programState }
            , EveOnline.AppFramework.ContinueSession
                { effects = effectsRequests
                , millisecondsToNextReadingFromGame = (decisionContext |> botSettingsFromDecisionContext).botStepDelayMilliseconds
                , statusDescriptionText = statusMessage
                }
            )


describeStateForMonitoring : ParsedUserInterface -> BotMemory -> String
describeStateForMonitoring parsedUserInterface botMemory =
    let
        describeSessionPerformance =
            [ ( "times unloaded", botMemory.timesUnloaded )
            , ( "volume unloaded / m³", botMemory.volumeUnloadedCubicMeters )
            ]
                |> List.map (\( metric, amount ) -> metric ++ ": " ++ (amount |> String.fromInt))
                |> String.join ", "

        describeShip =
            case parsedUserInterface.shipUI of
                CanSee shipUI ->
                    "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    case
                        parsedUserInterface.infoPanelContainer
                            |> maybeVisibleAndThen .infoPanelLocationInfo
                            |> maybeVisibleAndThen .expandedContent
                            |> maybeNothingFromCanNotSeeIt
                            |> Maybe.andThen .currentStationName
                    of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I cannot see if I am docked or in space. Please set up game client first."

        describeDrones =
            case parsedUserInterface.dronesWindow of
                CanNotSeeIt ->
                    "Can not see drone window."

                CanSee dronesWindow ->
                    "Can see the drones window: In bay: "
                        ++ (dronesWindow.droneGroupInBay |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ ", in local space: "
                        ++ (dronesWindow.droneGroupInLocalSpace |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ "."

        describeOreHold =
            "Ore hold filled "
                ++ (parsedUserInterface
                        |> inventoryWindowWithOreHoldSelectedFromUserInterface
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


integrateCurrentReadingsIntoBotMemory : ParsedUserInterface -> BotMemory -> BotMemory
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


{-| Returns the menu entry containing the string from the parameter `textToSearch`.
If there are multiple such entries, these are sorted by the length of their text, minus whitespaces in the beginning and the end.
The one with the shortest text is returned.
-}
menuEntryContainingTextIgnoringCase : String -> EveOnline.ParseUserInterface.ContextMenu -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry
menuEntryContainingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
        >> List.sortBy (.text >> String.trim >> String.length)
        >> List.head


menuEntryWithTextEqualsIgnoringCase : String -> EveOnline.ParseUserInterface.ContextMenu -> Maybe EveOnline.ParseUserInterface.ContextMenuEntry
menuEntryWithTextEqualsIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> (==) (textToSearch |> String.toLower))
        >> List.head


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromLocationInfoPanel : String -> EveOnline.ParseUserInterface.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


lastContextMenuOrSubmenu : ParsedUserInterface -> Maybe EveOnline.ParseUserInterface.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


topmostAsteroidFromOverviewWindow : ParsedUserInterface -> Maybe OverviewWindowEntry
topmostAsteroidFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


overviewWindowEntriesRepresentingAsteroids : ParsedUserInterface -> List OverviewWindowEntry
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


inventoryWindowWithOreHoldSelectedFromUserInterface : ParsedUserInterface -> Maybe EveOnline.ParseUserInterface.InventoryWindow
inventoryWindowWithOreHoldSelectedFromUserInterface =
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
clickLocationOnInventoryShipEntry : UIElement -> VolatileHostInterface.Location2d
clickLocationOnInventoryShipEntry uiElement =
    { x = uiElement.totalDisplayRegion.x + uiElement.totalDisplayRegion.width // 2
    , y = uiElement.totalDisplayRegion.y + 7
    }


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

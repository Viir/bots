{- EVE Online mining bot version 2020-03-18

   The bot warps to an asteroid belt, mines there until the ore hold is full, and then docks at a station to unload the ore. It then repeats this cycle until you stop it.
   It remembers the station in which it was last docked, and docks again at the same station.

   Setup instructions for the EVE Online client:
   + Set the UI language to English.
   + In Overview window, make asteroids visible.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + Setup inventory window so that 'Ore Hold' is always selected.
   + In the ship UI, arrange the modules:
     + Place all mining modules (to activate on targets) in the top row.
     + Place modules that should always be active in the middle row.
     + Hide passive modules by disabling the check-box `Display Passive Modules`.
   + Enable the info panel 'System info'.
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
import Dict
import EveOnline.BotFramework exposing (BotEffect(..), getEntropyIntFromUserInterface)
import EveOnline.MemoryReading
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ParsedUserInterface
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import EveOnline.ParseUserInterface
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)
import Result.Extra


defaultBotSettings : BotSettings
defaultBotSettings =
    { runAwayShieldHitpointsThresholdPercent = 50
    , targetingRange = 10000
    , miningModuleRange = 5000
    , botStepDelayMilliseconds = 2000
    }


{-| Names to support with the `--app-settings`, see <https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#configuring-a-bot>
-}
parseBotSettingsNames : Dict.Dict String (String -> Result String (BotSettings -> BotSettings))
parseBotSettingsNames =
    [ ( "run-away-shield-hitpoints-threshold-percent"
      , parseBotSettingInt (\threshold settings -> { settings | runAwayShieldHitpointsThresholdPercent = threshold })
      )
    , ( "mining-module-range"
      , parseBotSettingInt (\range settings -> { settings | miningModuleRange = range })
      )
    , ( "bot-step-delay"
      , parseBotSettingInt (\delay settings -> { settings | botStepDelayMilliseconds = delay })
      )
    ]
        |> Dict.fromList


type alias BotSettings =
    { runAwayShieldHitpointsThresholdPercent : Int
    , targetingRange : Int
    , miningModuleRange : Int
    , botStepDelayMilliseconds : Int
    }


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    }


type alias BotDecisionContext =
    { settings : BotSettings
    , memory : BotMemory
    , parsedUserInterface : ParsedUserInterface
    }


type alias UIElement =
    EveOnline.MemoryReading.UITreeNodeWithDisplayRegion


type alias TreeLeafAct =
    { firstAction : VolatileHostInterface.EffectOnWindowStructure
    , followingSteps : List ( String, ParsedUserInterface -> Maybe VolatileHostInterface.EffectOnWindowStructure )
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
            { decision : DecisionPathNode
            , lastStepIndexInSequence : Int
            }
    , botMemory : BotMemory
    }


type alias State =
    EveOnline.BotFramework.StateIncludingFramework BotState


{-| A first outline of the decision tree for a mining bot came from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
decideNextAction : BotDecisionContext -> DecisionPathNode
decideNextAction context =
    branchDependingOnDockedOrInSpace
        (DescribeBranch "I see no ship UI, assume we are docked." (decideNextActionWhenDocked context.parsedUserInterface))
        (\shipUI ->
            if shipUI.hitpointsPercent.shield < context.settings.runAwayShieldHitpointsThresholdPercent then
                Just
                    (DescribeBranch
                        ("Shield hitpoints are below " ++ (context.settings.runAwayShieldHitpointsThresholdPercent |> String.fromInt) ++ "% , run away.")
                        (runAway context)
                    )

            else
                Nothing
        )
        (decideNextActionWhenInSpace context)
        context.parsedUserInterface


decideNextActionWhenDocked : ParsedUserInterface -> DecisionPathNode
decideNextActionWhenDocked parsedUserInterface =
    case parsedUserInterface |> inventoryWindowItemHangar of
        Nothing ->
            DescribeBranch "I do not see the item hangar in the inventory." (EndDecisionPath Wait)

        Just itemHangar ->
            case parsedUserInterface |> inventoryWindowSelectedContainerFirstItem of
                Nothing ->
                    DescribeBranch "I see no item in the ore hold. Time to undock."
                        (case parsedUserInterface |> activeShipUiElementFromInventoryWindow of
                            Nothing ->
                                EndDecisionPath Wait

                            Just activeShipEntry ->
                                EndDecisionPath
                                    (Act
                                        { firstAction =
                                            activeShipEntry
                                                |> clickLocationOnInventoryShipEntry
                                                |> effectMouseClickAtLocation MouseButtonRight
                                        , followingSteps =
                                            [ ( "Click menu entry 'undock'."
                                              , lastContextMenuOrSubmenu
                                                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Undock")
                                                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                                              )
                                            ]
                                        }
                                    )
                        )

                Just itemInInventory ->
                    DescribeBranch "I see at least one item in the ore hold. Move this to the item hangar."
                        (EndDecisionPath
                            (Act
                                { firstAction =
                                    VolatileHostInterface.SimpleDragAndDrop
                                        { startLocation = itemInInventory.totalDisplayRegion |> centerFromDisplayRegion
                                        , endLocation = itemHangar.totalDisplayRegion |> centerFromDisplayRegion
                                        , mouseButton = MouseButtonLeft
                                        }
                                , followingSteps = []
                                }
                            )
                        )


decideNextActionWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideNextActionWhenInSpace context seeUndockingComplete =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else
        case seeUndockingComplete.shipModulesRows.middle |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
            Just inactiveModule ->
                DescribeBranch "I see an inactive module in the middle row. Click on it to activate."
                    (EndDecisionPath
                        (Act
                            { firstAction = inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft
                            , followingSteps = []
                            }
                        )
                    )

            Nothing ->
                case context.parsedUserInterface |> oreHoldFillPercent of
                    Nothing ->
                        DescribeBranch "I cannot see the ore hold capacity gauge." (EndDecisionPath Wait)

                    Just fillPercent ->
                        if 99 <= fillPercent then
                            DescribeBranch "The ore hold is full enough. Dock to station."
                                (case context.memory.lastDockedStationNameFromInfoPanel of
                                    Nothing ->
                                        DescribeBranch "At which station should I dock?. I was never docked in a station in this session." (EndDecisionPath Wait)

                                    Just lastDockedStationNameFromInfoPanel ->
                                        dockToStationMatchingNameSeenInInfoPanel
                                            { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel }
                                            context.parsedUserInterface
                                )

                        else
                            DescribeBranch "The ore hold is not full enough yet. Get more ore."
                                (case context.parsedUserInterface.targets |> List.head of
                                    Nothing ->
                                        DescribeBranch "I see no locked target." (ensureIsAtMiningSiteAndTargetAsteroid context)

                                    Just _ ->
                                        DescribeBranch "I see a locked target."
                                            (case seeUndockingComplete.shipModulesRows.top |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                                -- TODO: Check previous memory reading too for module activity.
                                                Nothing ->
                                                    DescribeBranch "All mining laser modules are active." (EndDecisionPath Wait)

                                                Just inactiveModule ->
                                                    DescribeBranch "I see an inactive mining module. Click on it to activate."
                                                        (EndDecisionPath
                                                            (Act
                                                                { firstAction = inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft
                                                                , followingSteps = []
                                                                }
                                                            )
                                                        )
                                            )
                                )


ensureIsAtMiningSiteAndTargetAsteroid : BotDecisionContext -> DecisionPathNode
ensureIsAtMiningSiteAndTargetAsteroid context =
    case context.parsedUserInterface |> topmostAsteroidFromOverviewWindow of
        Nothing ->
            DescribeBranch "I see no asteroid in the overview. Warp to mining site."
                (warpToMiningSite context.parsedUserInterface)

        Just asteroidInOverview ->
            DescribeBranch
                ("Choosing asteroid '" ++ (asteroidInOverview.objectName |> Maybe.withDefault "Nothing") ++ "'")
                (lockTargetFromOverviewEntryAndEnsureIsInRange (min context.settings.targetingRange context.settings.miningModuleRange) asteroidInOverview)


lockTargetFromOverviewEntryAndEnsureIsInRange : Int -> OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntryAndEnsureIsInRange rangeInMeters overviewEntry =
    case overviewEntry.objectDistanceInMeters of
        Ok distanceInMeters ->
            if distanceInMeters <= rangeInMeters then
                DescribeBranch "Object is in range. Lock target."
                    (EndDecisionPath
                        (Act
                            { firstAction = overviewEntry.uiNode |> clickOnUIElement MouseButtonRight
                            , followingSteps =
                                [ ( "Click menu entry 'lock'."
                                  , lastContextMenuOrSubmenu
                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "lock")
                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                                  )
                                ]
                            }
                        )
                    )

            else
                DescribeBranch ("Object is not in range (" ++ (distanceInMeters |> String.fromInt) ++ " meters away). Approach.")
                    (EndDecisionPath
                        (Act
                            { firstAction = overviewEntry.uiNode |> clickOnUIElement MouseButtonRight
                            , followingSteps =
                                [ ( "Click menu entry 'approach'."
                                  , lastContextMenuOrSubmenu
                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "approach")
                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                                  )
                                ]
                            }
                        )
                    )

        Err error ->
            DescribeBranch ("Failed to read the distance: " ++ error) (EndDecisionPath Wait)


dockToStationMatchingNameSeenInInfoPanel : { stationNameFromInfoPanel : String } -> ParsedUserInterface -> DecisionPathNode
dockToStationMatchingNameSeenInInfoPanel { stationNameFromInfoPanel } =
    dockToStationUsingSurroundingsButtonMenu
        ( "Click on menu entry representing the station '" ++ stationNameFromInfoPanel ++ "'."
        , List.filter (menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel)
            >> List.head
        )


dockToStationUsingSurroundingsButtonMenu :
    ( String, List EveOnline.MemoryReading.ContextMenuEntry -> Maybe EveOnline.MemoryReading.ContextMenuEntry )
    -> ParsedUserInterface
    -> DecisionPathNode
dockToStationUsingSurroundingsButtonMenu ( describeChooseStation, chooseStationMenuEntry ) =
    useContextMenuOnListSurroundingsButton
        [ ( "Click on menu entry 'stations'."
          , lastContextMenuOrSubmenu
                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "stations")
                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
          )
        , ( describeChooseStation
          , lastContextMenuOrSubmenu
                >> Maybe.andThen (.entries >> chooseStationMenuEntry)
                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
          )
        , ( "Click on menu entry 'dock'"
          , lastContextMenuOrSubmenu
                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "dock")
                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
          )
        ]


warpToMiningSite : ParsedUserInterface -> DecisionPathNode
warpToMiningSite parsedUserInterface =
    parsedUserInterface
        |> useContextMenuOnListSurroundingsButton
            [ ( "Click on menu entry 'asteroid belts'."
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "asteroid belts")
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
              )
            , ( "Click on one of the menu entries."
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen
                        (.entries >> listElementAtWrappedIndex (getEntropyIntFromUserInterface parsedUserInterface))
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
              )
            , ( "Click menu entry 'Warp to Within'"
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Warp to Within")
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
              )
            , ( "Click menu entry 'Within 0 m'"
              , lastContextMenuOrSubmenu
                    >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Within 0 m")
                    >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
              )
            ]


runAway : BotDecisionContext -> DecisionPathNode
runAway context =
    case context.memory.lastDockedStationNameFromInfoPanel of
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


type alias SeeUndockingComplete =
    { shipUI : EveOnline.MemoryReading.ShipUI
    , shipModulesRows : EveOnline.ParseUserInterface.ShipUIModulesGroupedIntoRows
    , overviewWindow : EveOnline.MemoryReading.OverviewWindow
    }


branchDependingOnDockedOrInSpace :
    DecisionPathNode
    -> (EveOnline.MemoryReading.ShipUI -> Maybe DecisionPathNode)
    -> (SeeUndockingComplete -> DecisionPathNode)
    -> ParsedUserInterface
    -> DecisionPathNode
branchDependingOnDockedOrInSpace branchIfDocked branchIfCanSeeShipUI branchIfUndockingComplete parsedUserInterface =
    case parsedUserInterface.shipUI of
        CanNotSeeIt ->
            DescribeBranch "I see no ship UI, assume we are docked." branchIfDocked

        CanSee shipUI ->
            branchIfCanSeeShipUI shipUI
                |> Maybe.withDefault
                    (case shipUI |> EveOnline.ParseUserInterface.groupShipUIModulesIntoRows of
                        Nothing ->
                            DescribeBranch "Failed to group the ship UI modules into rows." (EndDecisionPath Wait)

                        Just shipModulesRows ->
                            case parsedUserInterface.overviewWindow of
                                CanNotSeeIt ->
                                    DescribeBranch "I see no overview window, wait until undocking completed." (EndDecisionPath Wait)

                                CanSee overviewWindow ->
                                    DescribeBranch "I see we are in space."
                                        (branchIfUndockingComplete { shipUI = shipUI, shipModulesRows = shipModulesRows, overviewWindow = overviewWindow })
                    )


useContextMenuOnListSurroundingsButton : List ( String, ParsedUserInterface -> Maybe VolatileHostInterface.EffectOnWindowStructure ) -> ParsedUserInterface -> DecisionPathNode
useContextMenuOnListSurroundingsButton followingSteps parsedUserInterface =
    case parsedUserInterface.infoPanelLocationInfo of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the location info panel." (EndDecisionPath Wait)

        CanSee infoPanelLocationInfo ->
            EndDecisionPath
                (Act
                    { firstAction = infoPanelLocationInfo.listSurroundingsButton |> clickOnUIElement MouseButtonLeft
                    , followingSteps = followingSteps
                    }
                )


initState : State
initState =
    EveOnline.BotFramework.initState
        { programState = Nothing
        , botMemory = { lastDockedStationNameFromInfoPanel = Nothing }
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.BotFramework.processEvent processEveOnlineBotEvent


processEveOnlineBotEvent :
    EveOnline.BotFramework.BotEventContext
    -> EveOnline.BotFramework.BotEvent
    -> BotState
    -> ( BotState, EveOnline.BotFramework.BotEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case parseSettingsFromString defaultBotSettings (eventContext.appSettings |> Maybe.withDefault "") of
        Err parseSettingsError ->
            ( stateBefore
            , EveOnline.BotFramework.FinishSession { statusDescriptionText = "Failed to parse bot settings: " ++ parseSettingsError }
            )

        Ok settings ->
            processEveOnlineBotEventWithSettings settings event stateBefore


processEveOnlineBotEventWithSettings :
    BotSettings
    -> EveOnline.BotFramework.BotEvent
    -> BotState
    -> ( BotState, EveOnline.BotFramework.BotEventResponse )
processEveOnlineBotEventWithSettings botSettings event stateBefore =
    case event of
        EveOnline.BotFramework.MemoryReadingCompleted parsedUserInterface ->
            let
                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory parsedUserInterface

                programStateBefore =
                    stateBefore.programState
                        |> Maybe.withDefault
                            { decision =
                                decideNextAction
                                    { settings = botSettings, memory = botMemory, parsedUserInterface = parsedUserInterface }
                            , lastStepIndexInSequence = 0
                            }

                ( decisionStagesDescriptions, decisionLeaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf programStateBefore.decision

                ( currentStepDescription, effectsOnGameClientWindow, programState ) =
                    case decisionLeaf of
                        Wait ->
                            ( "Wait", [], Nothing )

                        Act act ->
                            let
                                programStateAdvancedToNextStep =
                                    { programStateBefore
                                        | lastStepIndexInSequence = programStateBefore.lastStepIndexInSequence + 1
                                    }

                                stepsIncludingFirstAction =
                                    ( "", always (Just act.firstAction) ) :: act.followingSteps
                            in
                            case stepsIncludingFirstAction |> List.drop programStateBefore.lastStepIndexInSequence |> List.head of
                                Nothing ->
                                    ( "Completed sequence.", [], Nothing )

                                Just ( stepDescription, effectOnGameClientWindowFromUserInterface ) ->
                                    case parsedUserInterface |> effectOnGameClientWindowFromUserInterface of
                                        Nothing ->
                                            ( "Failed step: " ++ stepDescription, [], Nothing )

                                        Just effect ->
                                            ( stepDescription, [ effect ], Just programStateAdvancedToNextStep )

                effectsRequests =
                    effectsOnGameClientWindow |> List.map EveOnline.BotFramework.EffectOnGameClientWindow

                describeActivity =
                    (decisionStagesDescriptions ++ [ currentStepDescription ])
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"

                statusMessage =
                    [ parsedUserInterface |> describeUserInterfaceForMonitoring, describeActivity ]
                        |> String.join "\n"
            in
            ( { stateBefore | botMemory = botMemory, programState = programState }
            , EveOnline.BotFramework.ContinueSession
                { effects = effectsRequests
                , millisecondsToNextReadingFromGame = botSettings.botStepDelayMilliseconds
                , statusDescriptionText = statusMessage
                }
            )


describeUserInterfaceForMonitoring : ParsedUserInterface -> String
describeUserInterfaceForMonitoring parsedUserInterface =
    let
        describeShip =
            case parsedUserInterface.shipUI of
                CanSee shipUI ->
                    "I am in space, shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    case parsedUserInterface.infoPanelLocationInfo |> maybeVisibleAndThen .expandedContent |> maybeNothingFromCanNotSeeIt |> Maybe.andThen .currentStationName of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I cannot see if I am docked or in space. Please set up game client first."

        describeOreHold =
            "Ore hold filled " ++ (parsedUserInterface |> oreHoldFillPercent |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown") ++ "%."
    in
    [ describeShip, describeOreHold ] |> String.join " "


integrateCurrentReadingsIntoBotMemory : ParsedUserInterface -> BotMemory -> BotMemory
integrateCurrentReadingsIntoBotMemory currentReading botMemoryBefore =
    let
        currentStationNameFromInfoPanel =
            currentReading.infoPanelLocationInfo
                |> maybeVisibleAndThen .expandedContent
                |> maybeNothingFromCanNotSeeIt
                |> Maybe.andThen .currentStationName
    in
    { lastDockedStationNameFromInfoPanel =
        [ currentStationNameFromInfoPanel, botMemoryBefore.lastDockedStationNameFromInfoPanel ]
            |> List.filterMap identity
            |> List.head
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


activeShipUiElementFromInventoryWindow : ParsedUserInterface -> Maybe UIElement
activeShipUiElementFromInventoryWindow =
    .inventoryWindows
        >> List.head
        >> Maybe.map .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> Maybe.andThen (List.sortBy (.uiNode >> .totalDisplayRegion >> .y) >> List.head)
        >> Maybe.map .uiNode


{-| Returns the menu entry containing the string from the parameter `textToSearch`.
If there are multiple such entries, these are sorted by the length of their text, minus whitespaces in the beginning and the end.
The one with the shortest text is returned.
-}
menuEntryContainingTextIgnoringCase : String -> EveOnline.MemoryReading.ContextMenu -> Maybe EveOnline.MemoryReading.ContextMenuEntry
menuEntryContainingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
        >> List.sortBy (.text >> String.trim >> String.length)
        >> List.head


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromLocationInfoPanel : String -> EveOnline.MemoryReading.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


lastContextMenuOrSubmenu : ParsedUserInterface -> Maybe EveOnline.MemoryReading.ContextMenu
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


oreHoldFillPercent : ParsedUserInterface -> Maybe Int
oreHoldFillPercent =
    .inventoryWindows
        >> List.head
        >> Maybe.andThen .selectedContainerCapacityGauge
        >> Maybe.andThen Result.toMaybe
        >> Maybe.andThen
            (\capacity -> capacity.maximum |> Maybe.map (\maximum -> capacity.used * 100 // maximum))


inventoryWindowSelectedContainerFirstItem : ParsedUserInterface -> Maybe UIElement
inventoryWindowSelectedContainerFirstItem =
    .inventoryWindows
        >> List.head
        >> Maybe.andThen .selectedContainerInventory
        >> Maybe.andThen .itemsView
        >> Maybe.map
            (\itemsView ->
                case itemsView of
                    EveOnline.MemoryReading.InventoryItemsListView { items } ->
                        items

                    EveOnline.MemoryReading.InventoryItemsNotListView { items } ->
                        items
            )
        >> Maybe.andThen List.head


inventoryWindowItemHangar : ParsedUserInterface -> Maybe UIElement
inventoryWindowItemHangar =
    .inventoryWindows
        >> List.head
        >> Maybe.map .leftTreeEntries
        >> Maybe.andThen (List.filter (.text >> String.toLower >> String.contains "item hangar") >> List.head)
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


isShipWarpingOrJumping : EveOnline.MemoryReading.ShipUI -> Bool
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


listElementAtWrappedIndex : Int -> List element -> Maybe element
listElementAtWrappedIndex indexToWrap list =
    if (list |> List.length) < 1 then
        Nothing

    else
        list |> List.drop (indexToWrap |> modBy (list |> List.length)) |> List.head


parseBotSettingInt : (Int -> BotSettings -> BotSettings) -> String -> Result String (BotSettings -> BotSettings)
parseBotSettingInt integrateInt argumentAsString =
    case argumentAsString |> String.toInt of
        Nothing ->
            Err ("Failed to parse '" ++ argumentAsString ++ "' as integer.")

        Just int ->
            Ok (integrateInt int)


parseSettingsFromString : BotSettings -> String -> Result String BotSettings
parseSettingsFromString settingsBefore settingsString =
    let
        assignments =
            settingsString |> String.split ","

        assignmentFunctionResults =
            assignments
                |> List.map String.trim
                |> List.filter (String.isEmpty >> not)
                |> List.map
                    (\assignment ->
                        case assignment |> String.split "=" |> List.map String.trim of
                            [ settingName, assignedValue ] ->
                                case parseBotSettingsNames |> Dict.get settingName of
                                    Nothing ->
                                        Err ("Unknown setting name '" ++ settingName ++ "'.")

                                    Just parseFunction ->
                                        parseFunction assignedValue
                                            |> Result.mapError (\parseError -> "Failed to parse value for setting '" ++ settingName ++ "': " ++ parseError)

                            _ ->
                                Err ("Failed to parse assignment '" ++ assignment ++ "'.")
                    )
    in
    assignmentFunctionResults
        |> Result.Extra.combine
        |> Result.map
            (\assignmentFunctions ->
                assignmentFunctions
                    |> List.foldl (\assignmentFunction previousSettings -> assignmentFunction previousSettings)
                        settingsBefore
            )

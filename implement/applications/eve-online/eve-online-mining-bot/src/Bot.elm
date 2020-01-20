{- Michaels EVE Online mining bot version 2020-01-20

   The bot warps to an asteroid belt, mines there until the ore hold is full, and then docks at a station to unload the ore. It then repeats this cycle until you stop it.
   It remembers the station in which it was last docked, and docks again at the same station.

   Setup instructions for the EVE Online client:
   + Enable `Run clients with 64 bit` in the settings, because this bot only works with the 64-bit version of the EVE Online client.
   + Set the UI language to English.
   + In Overview window, make asteroids visible.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + In the Inventory window select the 'List' view.
   + Setup inventory window so that 'Ore Hold' is always selected.
   + In the ship UI, arrange the mining modules to appear all in the upper row of modules.
   + Enable the info panel 'System info'.

   bot-catalog-tags:eve-online,mining
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import Sanderling.MemoryReading
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ParsedUserInterface
        , ShipUIModule
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import Sanderling.Sanderling as Sanderling exposing (MouseButton(..), centerFromRegion, effectMouseClickAtLocation)
import Sanderling.SimpleSanderling as SimpleSanderling exposing (BotEventAtTime, BotRequest(..))


type alias UIElement =
    Sanderling.MemoryReading.UITreeNodeWithDisplayRegion


type alias TreeLeafAct =
    { firstAction : Sanderling.EffectOnWindowStructure
    , followingSteps : List ( String, ParsedUserInterface -> Maybe Sanderling.EffectOnWindowStructure )
    }


type EndDecisionPathStructure
    = Wait
    | Act TreeLeafAct


type DecisionPathNode
    = DescribeBranch String DecisionPathNode
    | EndDecisionPath EndDecisionPathStructure


type alias SimpleState =
    { programState :
        Maybe
            { decision : DecisionPathNode
            , lastStepIndexInSequence : Int
            }
    , botMemory : BotMemory
    }


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    }


type alias State =
    SimpleSanderling.StateIncludingSetup SimpleState


generalStepDelayMilliseconds : Int
generalStepDelayMilliseconds =
    2000


{-| A first outline of the decision tree for a mining bot is coming from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
decideNextAction : BotMemory -> ParsedUserInterface -> DecisionPathNode
decideNextAction botMemory memoryReading =
    if memoryReading |> isShipWarpingOrJumping then
        -- TODO: Look also on the previous memory reading.
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else if memoryReading.overviewWindow == CanNotSeeIt then
        DescribeBranch "I see no overview window, assume we are docked." (decideNextActionWhenDocked memoryReading)

    else
        -- TODO: For robustness, also look also on the previous memory reading. Only continue when both indicate is undocked.
        DescribeBranch "I see we are in space." (decideNextActionWhenInSpace botMemory memoryReading)


decideNextActionWhenDocked : ParsedUserInterface -> DecisionPathNode
decideNextActionWhenDocked memoryReading =
    case memoryReading |> inventoryWindowItemHangar of
        Nothing ->
            DescribeBranch "I do not see the item hangar in the inventory." (EndDecisionPath Wait)

        Just itemHangar ->
            case memoryReading |> inventoryWindowSelectedContainerFirstItem of
                Nothing ->
                    DescribeBranch "I see no item in the ore hold. Time to undock."
                        (case memoryReading |> activeShipUiElementFromInventoryWindow of
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
                                    Sanderling.SimpleDragAndDrop
                                        { startLocation = itemInInventory.totalDisplayRegion |> centerFromRegion
                                        , endLocation = itemHangar.totalDisplayRegion |> centerFromRegion
                                        , mouseButton = MouseButtonLeft
                                        }
                                , followingSteps = []
                                }
                            )
                        )


decideNextActionWhenInSpace : BotMemory -> ParsedUserInterface -> DecisionPathNode
decideNextActionWhenInSpace botMemory memoryReading =
    case memoryReading |> oreHoldFillPercent of
        Nothing ->
            DescribeBranch "I cannot see the ore hold capacity gauge." (EndDecisionPath Wait)

        Just fillPercent ->
            if 99 <= fillPercent then
                DescribeBranch "The ore hold is full enough. Dock to station."
                    (case botMemory.lastDockedStationNameFromInfoPanel of
                        Nothing ->
                            DescribeBranch "At which station should I dock?. I was never docked in a station in this session." (EndDecisionPath Wait)

                        Just lastDockedStationNameFromInfoPanel ->
                            dockToStation { stationNameFromInfoPanel = lastDockedStationNameFromInfoPanel } memoryReading
                    )

            else
                DescribeBranch "The ore hold is not full enough yet. Get more ore."
                    (case memoryReading.targets |> List.head of
                        Nothing ->
                            DescribeBranch "I see no locked target." (decideNextActionAcquireLockedTarget memoryReading)

                        Just _ ->
                            DescribeBranch "I see a locked target."
                                (case memoryReading |> shipUiMiningModules |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
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


decideNextActionAcquireLockedTarget : ParsedUserInterface -> DecisionPathNode
decideNextActionAcquireLockedTarget memoryReading =
    case memoryReading |> topmostAsteroidFromOverviewWindow of
        Nothing ->
            DescribeBranch "I see no asteroid in the overview. Warp to mining site."
                (warpToMiningSite memoryReading)

        Just asteroidInOverview ->
            if asteroidInOverview |> overviewWindowEntryIsInRange |> Maybe.withDefault False then
                DescribeBranch "Asteroid is in range. Lock target."
                    (EndDecisionPath
                        (Act
                            { firstAction = asteroidInOverview.uiNode |> clickOnUIElement MouseButtonRight
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
                DescribeBranch "Asteroid is not in range. Approach."
                    (EndDecisionPath
                        (Act
                            { firstAction = asteroidInOverview.uiNode |> clickOnUIElement MouseButtonRight
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


dockToStation : { stationNameFromInfoPanel : String } -> ParsedUserInterface -> DecisionPathNode
dockToStation { stationNameFromInfoPanel } memoryReading =
    case memoryReading.infoPanelLocationInfo of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the location info panel." (EndDecisionPath Wait)

        CanSee infoPanelLocationInfo ->
            EndDecisionPath
                (Act
                    { firstAction = infoPanelLocationInfo.listSurroundingsButton |> clickOnUIElement MouseButtonLeft
                    , followingSteps =
                        [ ( "Click on menu entry 'stations'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "stations")
                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click on menu entry representing the station '" ++ stationNameFromInfoPanel ++ "'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen
                                    (.entries
                                        >> List.filter
                                            (menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel)
                                        >> List.head
                                    )
                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click on menu entry 'dock'"
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "dock")
                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                          )
                        ]
                    }
                )


warpToMiningSite : ParsedUserInterface -> DecisionPathNode
warpToMiningSite memoryReading =
    case memoryReading.infoPanelLocationInfo of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the current system info panel." (EndDecisionPath Wait)

        CanSee infoPanelLocationInfo ->
            EndDecisionPath
                (Act
                    { firstAction = infoPanelLocationInfo.listSurroundingsButton |> clickOnUIElement MouseButtonLeft
                    , followingSteps =
                        [ ( "Click on menu entry 'asteroid belts'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "asteroid belts")
                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click on one of the menu entries."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen
                                    (.entries >> listElementAtWrappedIndex (getEntropyIntFromMemoryReading memoryReading))
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
                    }
                )


initState : State
initState =
    SimpleSanderling.initState
        { programState = Nothing
        , botMemory = { lastDockedStationNameFromInfoPanel = Nothing }
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleSanderling.processEvent processEveOnlineBotEvent


processEveOnlineBotEvent :
    BotEventAtTime
    -> SimpleState
    -> { newState : SimpleState, requests : List BotRequest, millisecondsToNextMemoryReading : Int, statusDescriptionText : String }
processEveOnlineBotEvent eventAtTime stateBefore =
    case eventAtTime.event of
        SimpleSanderling.MemoryReadingCompleted memoryReading ->
            let
                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory memoryReading

                programStateBefore =
                    stateBefore.programState
                        |> Maybe.withDefault { decision = decideNextAction botMemory memoryReading, lastStepIndexInSequence = 0 }

                ( decisionStagesDescriptions, decisionLeaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf programStateBefore.decision

                ( currentStepDescription, effects, programState ) =
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

                                Just ( stepDescription, computeStepResult ) ->
                                    case memoryReading |> computeStepResult of
                                        Nothing ->
                                            ( "Failed step: " ++ stepDescription, [], Nothing )

                                        Just effect ->
                                            ( stepDescription, [ effect ], Just programStateAdvancedToNextStep )

                effectsRequests =
                    effects |> List.map EffectOnGameClientWindow

                describeActivity =
                    (decisionStagesDescriptions ++ [ currentStepDescription ])
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"

                statusMessage =
                    [ memoryReading |> describeMemoryReadingForMonitoring, describeActivity ]
                        |> String.join "\n"
            in
            { newState = { stateBefore | botMemory = botMemory, programState = programState }
            , requests = effectsRequests
            , millisecondsToNextMemoryReading = generalStepDelayMilliseconds
            , statusDescriptionText = statusMessage
            }

        SimpleSanderling.SetBotConfiguration botConfiguration ->
            { newState = stateBefore
            , requests = []
            , millisecondsToNextMemoryReading = generalStepDelayMilliseconds
            , statusDescriptionText =
                if botConfiguration |> String.isEmpty then
                    ""

                else
                    "I have a problem with this configuration: I am not programmed to support configuration at all. Maybe the bot catalog (https://to.botengine.org/bot-catalog) has a bot which better matches your use case?"
            }


describeMemoryReadingForMonitoring : ParsedUserInterface -> String
describeMemoryReadingForMonitoring memoryReading =
    let
        describeShip =
            case memoryReading.shipUI of
                CanSee shipUI ->
                    "I am in space, shield HP at " ++ ((shipUI.hitpointsMilli.shield // 10) |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    case memoryReading.infoPanelLocationInfo |> maybeVisibleAndThen .expandedContent |> maybeNothingFromCanNotSeeIt |> Maybe.andThen .currentStationName of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I cannot see if I am docked or in space. Please set up game client first."

        describeOreHold =
            "Ore hold filled " ++ (memoryReading |> oreHoldFillPercent |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown") ++ "%."
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


{-| Assume upper row of modules only contains mining modules.
-}
shipUiMiningModules : ParsedUserInterface -> List ShipUIModule
shipUiMiningModules =
    shipUiModulesRows >> List.head >> Maybe.withDefault []


shipUiModules : ParsedUserInterface -> List ShipUIModule
shipUiModules =
    .shipUI >> maybeNothingFromCanNotSeeIt >> Maybe.map .modules >> Maybe.withDefault []


{-| Groups the modules into rows.
-}
shipUiModulesRows : ParsedUserInterface -> List (List ShipUIModule)
shipUiModulesRows =
    let
        putModulesInSameGroup moduleA moduleB =
            let
                distanceY =
                    (moduleA.uiNode.totalDisplayRegion |> centerFromRegion).y
                        - (moduleB.uiNode.totalDisplayRegion |> centerFromRegion).y
            in
            abs distanceY < 10
    in
    shipUiModules
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.foldl
            (\shipModule groups ->
                case groups |> List.filter (List.any (putModulesInSameGroup shipModule)) |> List.head of
                    Nothing ->
                        groups ++ [ [ shipModule ] ]

                    Just matchingGroup ->
                        (groups |> listRemove matchingGroup) ++ [ matchingGroup ++ [ shipModule ] ]
            )
            []


{-| Returns the menu entry containing the string from the parameter `textToSearch`.
If there are multiple such entries, these are sorted by the length of their text, minus whitespaces in the beginning and the end.
The one with the shortest text is returned.
-}
menuEntryContainingTextIgnoringCase : String -> Sanderling.MemoryReading.ContextMenu -> Maybe Sanderling.MemoryReading.ContextMenuEntry
menuEntryContainingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
        >> List.sortBy (.text >> String.trim >> String.length)
        >> List.head


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromLocationInfoPanel : String -> Sanderling.MemoryReading.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromLocationInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


lastContextMenuOrSubmenu : ParsedUserInterface -> Maybe Sanderling.MemoryReading.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


topmostAsteroidFromOverviewWindow : ParsedUserInterface -> Maybe OverviewWindowEntry
topmostAsteroidFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids
        >> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
        >> List.head


overviewWindowEntryIsInRange : OverviewWindowEntry -> Maybe Bool
overviewWindowEntryIsInRange =
    .distanceInMeters >> Result.map (\distanceInMeters -> distanceInMeters < 1000) >> Result.toMaybe


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
        >> Maybe.map (\capacity -> capacity.used * 100 // capacity.maximum)


inventoryWindowSelectedContainerFirstItem : ParsedUserInterface -> Maybe UIElement
inventoryWindowSelectedContainerFirstItem =
    .inventoryWindows
        >> List.head
        >> Maybe.andThen .selectedContainerInventory
        >> Maybe.andThen (.listViewItems >> List.head)


inventoryWindowItemHangar : ParsedUserInterface -> Maybe UIElement
inventoryWindowItemHangar =
    .inventoryWindows
        >> List.head
        >> Maybe.map .leftTreeEntries
        >> Maybe.andThen (List.filter (.text >> String.toLower >> String.contains "item hangar") >> List.head)
        >> Maybe.map .uiNode


clickOnUIElement : MouseButton -> UIElement -> Sanderling.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromRegion)


{-| The region of a ship entry in the inventory window can contain child nodes (e.g. 'Ore Hold').
For this reason, we don't click on the center but stay close to the top.
-}
clickLocationOnInventoryShipEntry : UIElement -> Sanderling.Location2d
clickLocationOnInventoryShipEntry uiElement =
    { x = uiElement.totalDisplayRegion.x + uiElement.totalDisplayRegion.width // 2
    , y = uiElement.totalDisplayRegion.y + 7
    }


isShipWarpingOrJumping : ParsedUserInterface -> Bool
isShipWarpingOrJumping =
    .shipUI
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.indication >> maybeNothingFromCanNotSeeIt)
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map
            (\maneuverType ->
                [ Sanderling.MemoryReading.ManeuverWarp, Sanderling.MemoryReading.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


getEntropyIntFromMemoryReading : ParsedUserInterface -> Int
getEntropyIntFromMemoryReading memoryReading =
    let
        entropyFromUiElement uiElement =
            [ uiElement.uiNode.pythonObjectAddress |> String.toInt |> Maybe.withDefault 0
            , uiElement.totalDisplayRegion.x
            , uiElement.totalDisplayRegion.y
            , uiElement.totalDisplayRegion.width
            , uiElement.totalDisplayRegion.height
            ]
                |> List.sum

        entropyFromOverviewEntry overviewEntry =
            [ overviewEntry.uiNode |> entropyFromUiElement, overviewEntry.distanceInMeters |> Result.withDefault 0 ]
                |> List.sum

        fromMenus =
            memoryReading.contextMenus
                |> List.concatMap (.entries >> List.map .uiNode)
                |> List.map entropyFromUiElement

        fromOverview =
            memoryReading.overviewWindow
                |> maybeNothingFromCanNotSeeIt
                |> Maybe.map .entries
                |> Maybe.withDefault []
                |> List.map entropyFromOverviewEntry
    in
    (fromMenus ++ fromOverview) |> List.sum


listElementAtWrappedIndex : Int -> List element -> Maybe element
listElementAtWrappedIndex indexToWrap list =
    if (list |> List.length) < 1 then
        Nothing

    else
        list |> List.drop (indexToWrap |> modBy (list |> List.length)) |> List.head


listRemove : element -> List element -> List element
listRemove elementToRemove =
    List.filter ((/=) elementToRemove)

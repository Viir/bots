{- This is an asteroid mining bot for EVE Online

   The bot warps to an asteroid belt, mines there until the ore hold is full, and then docks at a station to unload the ore. It then repeats this cycle until you stop it.
   It remembers the station in which it was last docked, and docks again at the same station.

   Setup instructions for the EVE Online client:
   + Disable `Run clients with 64 bit` in the settings, because this bot only works with the 32-bit version of the EVE Online client.
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
import Sanderling.Sanderling as Sanderling exposing (MouseButton(..), centerFromRegion, effectMouseClickAtLocation)
import Sanderling.SanderlingMemoryMeasurement as SanderlingMemoryMeasurement
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ShipUiModule
        , UIElement
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import Sanderling.SimpleSanderling as SimpleSanderling exposing (BotEventAtTime, BotRequest(..))


type alias MemoryReading =
    SanderlingMemoryMeasurement.MemoryMeasurementReducedWithNamedNodes


type alias TreeLeafAct =
    { firstAction : Sanderling.EffectOnWindowStructure
    , followingSteps : List ( String, MemoryReading -> Maybe Sanderling.EffectOnWindowStructure )
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
decideNextAction : BotMemory -> MemoryReading -> DecisionPathNode
decideNextAction botMemory memoryReading =
    if memoryReading |> isShipWarpingOrJumping then
        -- TODO: Look also on the previous memory reading.
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else if memoryReading.overviewWindow == CanNotSeeIt then
        DescribeBranch "I see no overview window, assume we are docked." (decideNextActionWhenDocked memoryReading)

    else
        -- TODO: For robustness, also look also on the previous memory reading. Only continue when both indicate is undocked.
        DescribeBranch "I see we are in space." (decideNextActionWhenInSpace botMemory memoryReading)


decideNextActionWhenDocked : MemoryReading -> DecisionPathNode
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
                                                    >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
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
                                        { startLocation = itemInInventory.region |> centerFromRegion
                                        , endLocation = itemHangar.region |> centerFromRegion
                                        , mouseButton = MouseButtonLeft
                                        }
                                , followingSteps = []
                                }
                            )
                        )


decideNextActionWhenInSpace : BotMemory -> MemoryReading -> DecisionPathNode
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
                                (case memoryReading |> shipUiMiningModules |> List.filter (.isActive >> Maybe.withDefault True >> not) |> List.head of
                                    -- TODO: Check previous memory reading too for module activity.
                                    Nothing ->
                                        DescribeBranch "All mining laser modules are active." (EndDecisionPath Wait)

                                    Just inactiveModule ->
                                        DescribeBranch "I see an inactive mining module. Click on it to activate."
                                            (EndDecisionPath
                                                (Act
                                                    { firstAction = inactiveModule.uiElement |> clickOnUIElement MouseButtonLeft
                                                    , followingSteps = []
                                                    }
                                                )
                                            )
                                )
                    )


decideNextActionAcquireLockedTarget : MemoryReading -> DecisionPathNode
decideNextActionAcquireLockedTarget memoryReading =
    case memoryReading |> firstAsteroidFromOverviewWindow of
        Nothing ->
            DescribeBranch "I see no asteroid in the overview. Warp to mining site."
                (warpToMiningSite memoryReading)

        Just asteroidInOverview ->
            if asteroidInOverview |> overviewWindowEntryIsInRange |> Maybe.withDefault False then
                DescribeBranch "Asteroid is in range. Lock target."
                    (EndDecisionPath
                        (Act
                            { firstAction = asteroidInOverview.uiElement |> clickOnUIElement MouseButtonRight
                            , followingSteps =
                                [ ( "Click menu entry 'lock'."
                                  , lastContextMenuOrSubmenu
                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "lock")
                                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                                  )
                                ]
                            }
                        )
                    )

            else
                DescribeBranch "Asteroid is not in range. Approach."
                    (EndDecisionPath
                        (Act
                            { firstAction = asteroidInOverview.uiElement |> clickOnUIElement MouseButtonRight
                            , followingSteps =
                                [ ( "Click menu entry 'approach'."
                                  , lastContextMenuOrSubmenu
                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "approach")
                                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                                  )
                                ]
                            }
                        )
                    )


dockToStation : { stationNameFromInfoPanel : String } -> MemoryReading -> DecisionPathNode
dockToStation { stationNameFromInfoPanel } memoryReading =
    case memoryReading.infoPanelCurrentSystem of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the current system info panel." (EndDecisionPath Wait)

        CanSee infoPanelCurrentSystem ->
            EndDecisionPath
                (Act
                    { firstAction = infoPanelCurrentSystem.listSurroundingsButton |> clickOnUIElement MouseButtonLeft
                    , followingSteps =
                        [ ( "Click on menu entry 'stations'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "stations")
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click on menu entry representing the station '" ++ stationNameFromInfoPanel ++ "'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen
                                    (.entries
                                        >> List.filter
                                            (menuEntryMatchesStationNameFromCurrentSystemInfoPanel stationNameFromInfoPanel)
                                        >> List.head
                                    )
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click on menu entry 'dock'"
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "dock")
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        ]
                    }
                )


warpToMiningSite : MemoryReading -> DecisionPathNode
warpToMiningSite memoryReading =
    case memoryReading.infoPanelCurrentSystem of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the current system info panel." (EndDecisionPath Wait)

        CanSee infoPanelCurrentSystem ->
            EndDecisionPath
                (Act
                    { firstAction = infoPanelCurrentSystem.listSurroundingsButton |> clickOnUIElement MouseButtonLeft
                    , followingSteps =
                        [ ( "Click on menu entry 'asteroid belts'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "asteroid belts")
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click on one of the menu entries."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen
                                    (.entries >> listElementAtWrappedIndex (getEntropyIntFromMemoryReading memoryReading))
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click menu entry 'Warp to Within'"
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Warp to Within")
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click menu entry 'Within 0 m'"
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Within 0 m")
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
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
    SimpleSanderling.processEvent simpleProcessEvent


simpleProcessEvent : BotEventAtTime -> SimpleState -> { newState : SimpleState, requests : List BotRequest, statusMessage : String }
simpleProcessEvent eventAtTime stateBefore =
    case eventAtTime.event of
        SimpleSanderling.MemoryMeasurementCompleted memoryReading ->
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

                requests =
                    effectsRequests ++ [ TakeMemoryMeasurementAfterDelayInMilliseconds generalStepDelayMilliseconds ]

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
            , requests = requests
            , statusMessage = statusMessage
            }

        SimpleSanderling.SetBotConfiguration botConfiguration ->
            { newState = stateBefore
            , requests = []
            , statusMessage =
                if botConfiguration |> String.isEmpty then
                    ""

                else
                    "I have a problem with this configuration: I am not programmed to support configuration at all. Maybe the bot catalog (https://to.botengine.org/bot-catalog) has a bot which better matches your use case?"
            }


describeMemoryReadingForMonitoring : MemoryReading -> String
describeMemoryReadingForMonitoring memoryReading =
    let
        describeShip =
            case memoryReading.shipUi of
                CanSee shipUi ->
                    "I am in space, shield HP at " ++ ((shipUi.hitpointsAndEnergyMilli.shield // 10) |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    case memoryReading.infoPanelCurrentSystem |> maybeVisibleAndThen .expandedContent |> maybeNothingFromCanNotSeeIt |> Maybe.andThen .currentStationName of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I cannot see if I am docked or in space. Please set up game client first."

        describeOreHold =
            "Ore hold filled " ++ (memoryReading |> oreHoldFillPercent |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown") ++ "%."
    in
    [ describeShip, describeOreHold ] |> String.join " "


integrateCurrentReadingsIntoBotMemory : MemoryReading -> BotMemory -> BotMemory
integrateCurrentReadingsIntoBotMemory currentReading botMemoryBefore =
    let
        currentStationNameFromInfoPanel =
            currentReading.infoPanelCurrentSystem
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


activeShipUiElementFromInventoryWindow : MemoryReading -> Maybe UIElement
activeShipUiElementFromInventoryWindow =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> Maybe.andThen (List.sortBy (.uiElement >> .region >> .top) >> List.head)
        >> Maybe.map .uiElement


{-| Assume upper row of modules only contains mining modules.
-}
shipUiMiningModules : MemoryReading -> List ShipUiModule
shipUiMiningModules =
    shipUiModulesRows >> List.head >> Maybe.withDefault []


shipUiModules : MemoryReading -> List ShipUiModule
shipUiModules =
    .shipUi >> maybeNothingFromCanNotSeeIt >> Maybe.map .modules >> Maybe.withDefault []


{-| Groups the modules into rows.
-}
shipUiModulesRows : MemoryReading -> List (List ShipUiModule)
shipUiModulesRows =
    let
        putModulesInSameGroup moduleA moduleB =
            let
                distanceY =
                    (moduleA.uiElement.region |> centerFromRegion).y
                        - (moduleB.uiElement.region |> centerFromRegion).y
            in
            abs distanceY < 10
    in
    shipUiModules
        >> List.sortBy (.uiElement >> .region >> .top)
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
menuEntryContainingTextIgnoringCase : String -> SanderlingMemoryMeasurement.ContextMenu -> Maybe SanderlingMemoryMeasurement.ContextMenuEntry
menuEntryContainingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
        >> List.sortBy (.text >> String.trim >> String.length)
        >> List.head


{-| The names are at least sometimes displayed different: 'Moon 7' can become 'M7'
-}
menuEntryMatchesStationNameFromCurrentSystemInfoPanel : String -> SanderlingMemoryMeasurement.ContextMenuEntry -> Bool
menuEntryMatchesStationNameFromCurrentSystemInfoPanel stationNameFromInfoPanel menuEntry =
    (stationNameFromInfoPanel |> String.toLower |> String.replace "moon " "m")
        == (menuEntry.text |> String.trim |> String.toLower)


lastContextMenuOrSubmenu : MemoryReading -> Maybe SanderlingMemoryMeasurement.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.reverse >> List.head


firstAsteroidFromOverviewWindow : MemoryReading -> Maybe OverviewWindowEntry
firstAsteroidFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids >> List.head


overviewWindowEntryIsInRange : OverviewWindowEntry -> Maybe Bool
overviewWindowEntryIsInRange =
    .distanceInMeters >> Result.map (\distanceInMeters -> distanceInMeters < 1000) >> Result.toMaybe


overviewWindowEntriesRepresentingAsteroids : MemoryReading -> List OverviewWindowEntry
overviewWindowEntriesRepresentingAsteroids =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter overviewWindowEntryRepresentsAnAsteroid)
        >> Maybe.withDefault []


overviewWindowEntryRepresentsAnAsteroid : OverviewWindowEntry -> Bool
overviewWindowEntryRepresentsAnAsteroid entry =
    (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "asteroid"))
        && (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "belt") |> not)


oreHoldFillPercent : MemoryReading -> Maybe Int
oreHoldFillPercent =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen .selectedContainedCapacityGauge
        >> Maybe.map (\capacity -> capacity.used * 100 // capacity.maximum)


inventoryWindowSelectedContainerFirstItem : MemoryReading -> Maybe UIElement
inventoryWindowSelectedContainerFirstItem =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen .selectedContainerInventory
        >> Maybe.andThen (.listViewItems >> List.head)


inventoryWindowItemHangar : MemoryReading -> Maybe UIElement
inventoryWindowItemHangar =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .leftTreeEntries
        >> Maybe.andThen (List.filter (.text >> String.toLower >> String.contains "item hangar") >> List.head)
        >> Maybe.map .uiElement


clickOnUIElement : MouseButton -> UIElement -> Sanderling.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.region |> centerFromRegion)


{-| The region of a ship entry in the inventory window can contain child nodes (e.g. 'Ore Hold').
For this reason, we don't click on the center but stay close to the top.
-}
clickLocationOnInventoryShipEntry : UIElement -> Sanderling.Location2d
clickLocationOnInventoryShipEntry uiElement =
    { x = (uiElement.region.left + uiElement.region.right) // 2
    , y = uiElement.region.top + 7
    }


isShipWarpingOrJumping : MemoryReading -> Bool
isShipWarpingOrJumping =
    .shipUi
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.indication >> maybeNothingFromCanNotSeeIt)
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map
            (\maneuverType ->
                [ SanderlingMemoryMeasurement.Warp, SanderlingMemoryMeasurement.Jump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


getEntropyIntFromMemoryReading : MemoryReading -> Int
getEntropyIntFromMemoryReading memoryReading =
    let
        entropyFromUiElement uiElement =
            [ uiElement.id, uiElement.region.left, uiElement.region.right, uiElement.region.top, uiElement.region.bottom ]
                |> List.sum

        entropyFromOverviewEntry overviewEntry =
            [ overviewEntry.uiElement |> entropyFromUiElement, overviewEntry.distanceInMeters |> Result.withDefault 0 ]
                |> List.sum

        fromMenus =
            memoryReading.contextMenus
                |> List.concatMap (.entries >> List.map .uiElement)
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

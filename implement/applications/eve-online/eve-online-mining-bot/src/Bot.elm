{- This is an asteroid mining bot for EVE Online

    Setup instructions for the EVE Online client:
    + Disable `Run clients with 64 bit` in the settings, because this bot only works with the 32-bit version of the EVE Online client.
    + Set the UI language to English.
    + In Overview window, make asteroids visible.
    + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
    + In the Inventory window select the 'List' view.
    + Setup inventory window so that 'Ore Hold' is always selected.
    + In the ship UI, hide all modules which are no miners.
    + Enable the info panel 'System info'.
    + Create bookmark 'mining' for the mining site, for example an asteroid belt.
    + Create bookmark 'unload' for the station to store the mined ore in.

   bot-catalog-tags:eve-online,mining
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
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , OverviewWindowEntry
        , ShipUi
        , ShipUiModule
        , UIElement
        , maybeNothingFromCanNotSeeIt
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
    }


type alias State =
    SimpleSanderling.StateIncludingSetup SimpleState


miningSiteBookmarkName : String
miningSiteBookmarkName =
    "mining"


stationBookmarkName : String
stationBookmarkName =
    "unload"


generalStepDelayMilliseconds : Int
generalStepDelayMilliseconds =
    2000


{-| A first outline of the decision tree for a mining bot is coming from <https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/109?u=viir>
-}
decideNextAction : MemoryReading -> DecisionPathNode
decideNextAction memoryReading =
    if memoryReading |> isShipWarpingOrJumping then
        -- TODO: Look also on the previous memory reading.
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else if memoryReading.overviewWindow == CanNotSeeIt then
        DescribeBranch "I see no overview window, assume we are docked." (decideNextActionWhenDocked memoryReading)

    else
        -- TODO: For robustness, also look also on the previous memory reading. Only continue when both indicate is undocked.
        DescribeBranch "I see we are in space." (decideNextActionWhenInSpace memoryReading)


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


decideNextActionWhenInSpace : MemoryReading -> DecisionPathNode
decideNextActionWhenInSpace memoryReading =
    case memoryReading |> oreHoldFillPercent of
        Nothing ->
            DescribeBranch "I cannot see the ore hold capacity gauge." (EndDecisionPath Wait)

        Just fillPercent ->
            if 99 <= fillPercent then
                DescribeBranch "The ore hold is full enough. Dock to station."
                    (dockToStation memoryReading)

            else
                DescribeBranch "The ore hold is not full enough yet. Get more ore."
                    (case memoryReading.targets |> List.head of
                        Nothing ->
                            DescribeBranch "I see no locked target."
                                (case memoryReading |> firstAsteroidFromOverviewWindow of
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
                                )

                        Just _ ->
                            case memoryReading |> shipUiModules |> List.filter (.isActive >> Maybe.withDefault True >> not) |> List.head of
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


dockToStation : MemoryReading -> DecisionPathNode
dockToStation memoryReading =
    case memoryReading.infoPanelCurrentSystem of
        CanNotSeeIt ->
            DescribeBranch "I cannot see the current system info panel." (EndDecisionPath Wait)

        CanSee infoPanelCurrentSystem ->
            EndDecisionPath
                (Act
                    { firstAction = infoPanelCurrentSystem.listSurroundingsButton |> clickOnUIElement MouseButtonLeft
                    , followingSteps =
                        [ ( "Click on menu entry representing the station bookmark."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase stationBookmarkName)
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
                        [ ( "Click on menu entry representing the mining site."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase miningSiteBookmarkName)
                                >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft)
                          )
                        , ( "Click menu entry 'Warp to Location'"
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Warp to Location")
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
        { programState = Nothing }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleSanderling.processEvent simpleProcessEvent


simpleProcessEvent : BotEventAtTime -> SimpleState -> { newState : SimpleState, requests : List BotRequest, statusMessage : String }
simpleProcessEvent eventAtTime stateBefore =
    case eventAtTime.event of
        SimpleSanderling.MemoryMeasurementCompleted memoryReading ->
            let
                programStateBefore =
                    stateBefore.programState
                        |> Maybe.withDefault { decision = decideNextAction memoryReading, lastStepIndexInSequence = 0 }

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

                statusMessage =
                    decisionStagesDescriptions
                        ++ [ currentStepDescription ]
                        |> String.join "\n"
            in
            { newState = { stateBefore | programState = programState }
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


shipUiModules : MemoryReading -> List ShipUiModule
shipUiModules =
    .shipUi >> maybeNothingFromCanNotSeeIt >> Maybe.map .modules >> Maybe.withDefault []


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

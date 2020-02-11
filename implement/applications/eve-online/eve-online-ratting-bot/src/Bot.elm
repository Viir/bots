{- EVE Online ratting bot version 2020-02-11

   Setup instructions for the EVE Online client:
   + Enable `Run clients with 64 bit` in the settings, because this bot only works with the 64-bit version of the EVE Online client.
   + Set the UI language to English.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + Undock, open probe scanner, overview window and drones window.
   + In the ship UI, arrange the modules: The modules to use in combat must appear all in the upper row. Place modules which should always be active in a second row.
   + Enable the info panel 'System info'.
-}
{-
   bot-catalog-tags:eve-online,ratting
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import EveOnline.BotFramework exposing (BotEffect(..))
import EveOnline.MemoryReading
    exposing
        ( MaybeVisible(..)
        , OverviewWindow
        , OverviewWindowEntry
        , ParsedUserInterface
        , ShipUIModule
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)
import Set


attackMaxRange : Int
attackMaxRange =
    7000


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


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    }


type alias State =
    EveOnline.BotFramework.StateIncludingFramework BotState


generalStepDelayMilliseconds : Int
generalStepDelayMilliseconds =
    2000


decideNextAction : BotMemory -> ParsedUserInterface -> DecisionPathNode
decideNextAction botMemory parsedUserInterface =
    if parsedUserInterface |> isShipWarpingOrJumping then
        -- TODO: Look also on the previous memory reading.
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else
        case parsedUserInterface.overviewWindow of
            CanNotSeeIt ->
                DescribeBranch "I see no overview window, assume we are docked." (EndDecisionPath Wait)

            CanSee overviewWindow ->
                -- TODO: For robustness, also look also on the previous memory reading. Only continue when both indicate is undocked.
                DescribeBranch "I see we are in space." (decideNextActionWhenInSpace botMemory overviewWindow parsedUserInterface)


decideNextActionWhenInSpace : BotMemory -> OverviewWindow -> ParsedUserInterface -> DecisionPathNode
decideNextActionWhenInSpace botMemory overviewWindow parsedUserInterface =
    case parsedUserInterface |> shipUIModulesToActivateAlways |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
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
            combat botMemory overviewWindow parsedUserInterface


combat : BotMemory -> OverviewWindow -> ParsedUserInterface -> DecisionPathNode
combat botMemory overviewWindow parsedUserInterface =
    let
        overviewEntriesToAttack =
            overviewWindow.entries
                |> List.sortBy (.distanceInMeters >> Result.withDefault 999999)
                |> List.filter shouldAttackOverviewEntry
    in
    case overviewEntriesToAttack of
        [] ->
            DescribeBranch "I see no overview entry to attack." (EndDecisionPath Wait)

        nextOverviewEntryToAttack :: _ ->
            DescribeBranch "I see an overview entry to attack."
                (case parsedUserInterface.targets |> List.head of
                    Nothing ->
                        DescribeBranch "I see no locked target." (decideNextActionAcquireLockedTarget nextOverviewEntryToAttack)

                    Just _ ->
                        DescribeBranch "I see a locked target."
                            (case parsedUserInterface |> shipUIModulesToActivateOnTarget |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                -- TODO: Check previous memory reading too for module activity.
                                Nothing ->
                                    DescribeBranch "All attack modules are active." (EndDecisionPath Wait)

                                Just inactiveModule ->
                                    DescribeBranch "I see an inactive module to activate on targets. Click on it to activate."
                                        (EndDecisionPath
                                            (Act
                                                { firstAction = inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft
                                                , followingSteps = []
                                                }
                                            )
                                        )
                            )
                )


decideNextActionAcquireLockedTarget : OverviewWindowEntry -> DecisionPathNode
decideNextActionAcquireLockedTarget overviewEntry =
    if overviewEntry |> overviewWindowEntryIsInRange |> Maybe.withDefault False then
        DescribeBranch "Overview entry is in range. Lock target."
            (EndDecisionPath
                (Act
                    { firstAction = overviewEntry.uiNode |> clickOnUIElement MouseButtonRight
                    , followingSteps =
                        [ ( "Click menu entry 'lock'."
                          , lastContextMenuOrSubmenu
                                >> Maybe.andThen (menuEntryMatchingTextIgnoringCase "lock target")
                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                          )
                        ]
                    }
                )
            )

    else
        DescribeBranch "Overview entry is not in range. Approach."
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
    case event of
        EveOnline.BotFramework.MemoryReadingCompleted parsedUserInterface ->
            let
                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory parsedUserInterface

                programStateBefore =
                    stateBefore.programState
                        |> Maybe.withDefault { decision = decideNextAction botMemory parsedUserInterface, lastStepIndexInSequence = 0 }

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
                , millisecondsToNextReadingFromGame = generalStepDelayMilliseconds
                , statusDescriptionText = statusMessage
                }
            )


describeUserInterfaceForMonitoring : ParsedUserInterface -> String
describeUserInterfaceForMonitoring parsedUserInterface =
    let
        combatInfoLines =
            [ "Overview entries to attack: " ++ (parsedUserInterface |> allOverviewEntriesToAttack |> Maybe.map (List.length >> String.fromInt) |> Maybe.withDefault "Nothing") ]

        describeShip =
            case parsedUserInterface.shipUI of
                CanSee shipUI ->
                    "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    "I cannot see the ship UI. Please set up game client first."
    in
    [ describeShip ] ++ combatInfoLines |> String.join " "


allOverviewEntriesToAttack : ParsedUserInterface -> Maybe (List EveOnline.MemoryReading.OverviewWindowEntry)
allOverviewEntriesToAttack =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter shouldAttackOverviewEntry)


overviewEntryIsAlreadyTargetedOrTargeting : EveOnline.MemoryReading.OverviewWindowEntry -> Bool
overviewEntryIsAlreadyTargetedOrTargeting overviewEntry =
    let
        -- TODO: Probably add to parsing: Collect all names under the spaceObjectIconNode
        nodesNames =
            overviewEntry.uiNode.uiNode
                |> EveOnline.MemoryReading.listDescendantsInUITreeNode
                |> List.filterMap EveOnline.MemoryReading.getNameFromDictEntries
                |> Set.fromList
    in
    [ "targetedByMe", "targeting" ]
        |> Set.fromList
        |> Set.intersect nodesNames
        |> Set.isEmpty
        |> not


overviewEntryIsActiveTarget : EveOnline.MemoryReading.OverviewWindowEntry -> Bool
overviewEntryIsActiveTarget overviewEntry =
    -- TODO: Probably add to parsing: Collect all names under the spaceObjectIconNode
    overviewEntry.uiNode.uiNode
        |> EveOnline.MemoryReading.listDescendantsInUITreeNode
        |> List.filterMap EveOnline.MemoryReading.getNameFromDictEntries
        |> Set.fromList
        |> Set.member "myActiveTarget"


shouldAttackOverviewEntry : EveOnline.MemoryReading.OverviewWindowEntry -> Bool
shouldAttackOverviewEntry =
    iconSpriteHasColorOfRat


iconSpriteHasColorOfRat : EveOnline.MemoryReading.OverviewWindowEntry -> Bool
iconSpriteHasColorOfRat =
    .iconSpriteColorPercent
        >> Maybe.map
            (\colorPercent ->
                colorPercent.g * 3 < colorPercent.r && colorPercent.b * 3 < colorPercent.r && 60 < colorPercent.r && 50 < colorPercent.a
            )
        >> Maybe.withDefault False


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


shipUIModulesToActivateOnTarget : ParsedUserInterface -> List ShipUIModule
shipUIModulesToActivateOnTarget =
    shipUIModulesRows >> List.head >> Maybe.withDefault []


shipUIModulesToActivateAlways : ParsedUserInterface -> List ShipUIModule
shipUIModulesToActivateAlways =
    shipUIModulesRows >> List.drop 1 >> List.head >> Maybe.withDefault []


shipUiModules : ParsedUserInterface -> List ShipUIModule
shipUiModules =
    .shipUI >> maybeNothingFromCanNotSeeIt >> Maybe.map .modules >> Maybe.withDefault []


{-| Groups the modules into rows.
-}
shipUIModulesRows : ParsedUserInterface -> List (List ShipUIModule)
shipUIModulesRows =
    let
        putModulesInSameGroup moduleA moduleB =
            let
                distanceY =
                    (moduleA.uiNode.totalDisplayRegion |> centerFromDisplayRegion).y
                        - (moduleB.uiNode.totalDisplayRegion |> centerFromDisplayRegion).y
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
menuEntryContainingTextIgnoringCase : String -> EveOnline.MemoryReading.ContextMenu -> Maybe EveOnline.MemoryReading.ContextMenuEntry
menuEntryContainingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
        >> List.sortBy (.text >> String.trim >> String.length)
        >> List.head


menuEntryMatchingTextIgnoringCase : String -> EveOnline.MemoryReading.ContextMenu -> Maybe EveOnline.MemoryReading.ContextMenuEntry
menuEntryMatchingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> (==) (textToSearch |> String.toLower))
        >> List.head


lastContextMenuOrSubmenu : ParsedUserInterface -> Maybe EveOnline.MemoryReading.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


overviewWindowEntryIsInRange : OverviewWindowEntry -> Maybe Bool
overviewWindowEntryIsInRange =
    .distanceInMeters >> Result.map (\distanceInMeters -> distanceInMeters < attackMaxRange) >> Result.toMaybe


clickOnUIElement : MouseButton -> UIElement -> VolatileHostInterface.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromDisplayRegion)


isShipWarpingOrJumping : ParsedUserInterface -> Bool
isShipWarpingOrJumping =
    .shipUI
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.indication >> maybeNothingFromCanNotSeeIt)
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map
            (\maneuverType ->
                [ EveOnline.MemoryReading.ManeuverWarp, EveOnline.MemoryReading.ManeuverJump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


listRemove : element -> List element -> List element
listRemove elementToRemove =
    List.filter ((/=) elementToRemove)

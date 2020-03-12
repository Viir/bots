{- EVE Online anomaly ratting bot version 2020-03-12

   Setup instructions for the EVE Online client:
   + Set the UI language to English.
   + Enable the info panel 'System info'.
   + Undock, open probe scanner, overview window and drones window.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + In the ship UI, arrange the modules:
     + Place to use in combat (to activate on targets) in the top row.
     + Place modules that should always be active in the middle row.
     + Hide passive modules by disabling the check-box `Display Passive Modules`.
   + Configure the keyboard key 'W' to make the ship orbit.
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

import BotEngine.Interface_To_Host_20200213 as InterfaceToHost
import Dict
import EveOnline.BotFramework exposing (BotEffect(..), getEntropyIntFromUserInterface)
import EveOnline.MemoryReading
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ParsedUserInterface
        , ShipUI
        , ShipUIModule
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import EveOnline.ParseUserInterface
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)
import Result.Extra
import Set


defaultBotSettings : BotSettings
defaultBotSettings =
    { attackMaxRange = 18000
    , maxTargetCount = 3
    , botStepDelayMilliseconds = 1300
    }


{-| Names to support with the `--bot-configuration`, see <https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#configuring-a-bot>
-}
parseBotSettingsNames : Dict.Dict String (String -> Result String (BotSettings -> BotSettings))
parseBotSettingsNames =
    [ ( "bot-step-delay"
      , parseBotSettingInt (\delay settings -> { settings | botStepDelayMilliseconds = delay })
      )
    ]
        |> Dict.fromList


type alias BotSettings =
    { attackMaxRange : Int
    , maxTargetCount : Int
    , botStepDelayMilliseconds : Int
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


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    }


type alias BotDecisionContext =
    { settings : BotSettings
    , memory : BotMemory
    , parsedUserInterface : ParsedUserInterface
    }


type alias State =
    EveOnline.BotFramework.StateIncludingFramework BotState


probeScanResultsRepresentsMatchingAnomaly : EveOnline.MemoryReading.ProbeScanResult -> Bool
probeScanResultsRepresentsMatchingAnomaly =
    .textsLeftToRight >> List.any (String.toLower >> String.contains "combat")


decideNextAction : BotDecisionContext -> DecisionPathNode
decideNextAction context =
    branchDependingOnDockedOrInSpace
        (DescribeBranch "I see no ship UI, assume we are docked." (EndDecisionPath Wait))
        (always Nothing)
        (decideNextActionWhenInSpace context)
        context.parsedUserInterface


decideNextActionWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideNextActionWhenInSpace context seeUndockingComplete =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else
        case context.parsedUserInterface |> shipUIModulesToActivateAlways |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
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
                combat context seeUndockingComplete enterAnomaly


combat : BotDecisionContext -> SeeUndockingComplete -> (ParsedUserInterface -> DecisionPathNode) -> DecisionPathNode
combat context seeUndockingComplete continueIfCombatComplete =
    let
        overviewEntriesToAttack =
            seeUndockingComplete.overviewWindow.entries
                |> List.sortBy (.objectDistanceInMeters >> Result.withDefault 999999)
                |> List.filter shouldAttackOverviewEntry

        overviewEntriesToLock =
            overviewEntriesToAttack
                |> List.filter (overviewEntryIsAlreadyTargetedOrTargeting >> not)

        targetsToUnlock =
            if overviewEntriesToAttack |> List.any overviewEntryIsActiveTarget then
                []

            else
                context.parsedUserInterface.targets |> List.filter .isActiveTarget

        ensureShipIsOrbitingDecision =
            overviewEntriesToAttack
                |> List.head
                |> Maybe.andThen (\overviewEntryToAttack -> ensureShipIsOrbiting seeUndockingComplete.shipUI overviewEntryToAttack)

        decisionIfAlreadyOrbiting =
            case targetsToUnlock |> List.head of
                Just targetToUnlock ->
                    DescribeBranch "I see a target to unlock."
                        (EndDecisionPath
                            (Act
                                { firstAction =
                                    targetToUnlock.barAndImageCont
                                        |> Maybe.withDefault targetToUnlock.uiNode
                                        |> clickOnUIElement MouseButtonRight
                                , followingSteps =
                                    [ ( "Click menu entry 'unlock'."
                                      , lastContextMenuOrSubmenu
                                            >> Maybe.andThen (menuEntryContainingTextIgnoringCase "unlock")
                                            >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                                      )
                                    ]
                                }
                            )
                        )

                Nothing ->
                    case context.parsedUserInterface.targets |> List.head of
                        Nothing ->
                            DescribeBranch "I see no locked target."
                                (case overviewEntriesToLock of
                                    [] ->
                                        DescribeBranch "I see no overview entry to lock."
                                            (if overviewEntriesToAttack |> List.isEmpty then
                                                returnDronesToBay context.parsedUserInterface
                                                    |> Maybe.withDefault
                                                        (DescribeBranch "No drones to return." (continueIfCombatComplete context.parsedUserInterface))

                                             else
                                                DescribeBranch "Wait for target locking to complete." (EndDecisionPath Wait)
                                            )

                                    nextOverviewEntryToLock :: _ ->
                                        DescribeBranch "I see an overview entry to lock."
                                            (lockTargetFromOverviewEntryAndEnsureIsInRange context.settings.attackMaxRange nextOverviewEntryToLock)
                                )

                        Just _ ->
                            DescribeBranch "I see a locked target."
                                (case context.parsedUserInterface |> shipUIModulesToActivateOnTarget |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                    -- TODO: Check previous memory reading too for module activity.
                                    Nothing ->
                                        DescribeBranch "All attack modules are active."
                                            (launchAndEngageDrones context.parsedUserInterface
                                                |> Maybe.withDefault
                                                    (DescribeBranch "No idling drones."
                                                        (if context.settings.maxTargetCount <= (context.parsedUserInterface.targets |> List.length) then
                                                            DescribeBranch "Enough locked targets." (EndDecisionPath Wait)

                                                         else
                                                            case overviewEntriesToLock of
                                                                [] ->
                                                                    DescribeBranch "I see no more overview entries to lock." (EndDecisionPath Wait)

                                                                nextOverviewEntryToLock :: _ ->
                                                                    DescribeBranch "Lock more targets."
                                                                        (lockTargetFromOverviewEntryAndEnsureIsInRange context.settings.attackMaxRange nextOverviewEntryToLock)
                                                        )
                                                    )
                                            )

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
    in
    ensureShipIsOrbitingDecision
        |> Maybe.withDefault decisionIfAlreadyOrbiting


enterAnomaly : ParsedUserInterface -> DecisionPathNode
enterAnomaly parsedUserInterface =
    case parsedUserInterface.probeScannerWindow of
        CanNotSeeIt ->
            DescribeBranch "Can not see the probe scanner window." (EndDecisionPath Wait)

        CanSee probeScannerWindow ->
            let
                matchingScanResults =
                    probeScannerWindow.scanResults |> List.filter probeScanResultsRepresentsMatchingAnomaly
            in
            case matchingScanResults |> listElementAtWrappedIndex (getEntropyIntFromUserInterface parsedUserInterface) of
                Nothing ->
                    DescribeBranch
                        ("I see " ++ (probeScannerWindow.scanResults |> List.length |> String.fromInt) ++ " scan results, and no matching anomaly.")
                        (EndDecisionPath Wait)

                Just anomalyScanResult ->
                    DescribeBranch "Warp to anomaly."
                        (EndDecisionPath
                            (Act
                                { firstAction = anomalyScanResult.uiNode |> clickOnUIElement MouseButtonRight
                                , followingSteps =
                                    [ ( "Click menu entry 'Warp to Within'"
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
                        )


ensureShipIsOrbiting : ShipUI -> OverviewWindowEntry -> Maybe DecisionPathNode
ensureShipIsOrbiting shipUI overviewEntryToOrbit =
    if (shipUI.indication |> maybeVisibleAndThen .maneuverType) == CanSee EveOnline.MemoryReading.ManeuverOrbit then
        Nothing

    else
        Just
            (DescribeBranch "Overview entry is in range. Lock target."
                (EndDecisionPath
                    (Act
                        { firstAction = overviewEntryToOrbit.uiNode |> clickOnUIElement MouseButtonLeft
                        , followingSteps =
                            [ ( "Use keyboard key 'W' to begin orbit. Key down.", always (VolatileHostInterface.KeyDown keyCodeLetterW |> Just) )
                            , ( "Use keyboard key 'W' to begin orbit. Key up.", always (VolatileHostInterface.KeyUp keyCodeLetterW |> Just) )
                            ]
                        }
                    )
                )
            )


keyCodeLetterW : VolatileHostInterface.VirtualKeyCode
keyCodeLetterW =
    VolatileHostInterface.VirtualKeyCodeFromInt 0x57


launchAndEngageDrones : ParsedUserInterface -> Maybe DecisionPathNode
launchAndEngageDrones parsedUserInterface =
    parsedUserInterface.dronesWindow
        |> maybeNothingFromCanNotSeeIt
        |> Maybe.andThen
            (\dronesWindow ->
                case ( dronesWindow.droneGroupInBay, dronesWindow.droneGroupInLocalSpace ) of
                    ( Just droneGroupInBay, Just droneGroupInLocalSpace ) ->
                        let
                            idlingDrones =
                                droneGroupInLocalSpace.drones
                                    |> List.filter (.uiNode >> .uiNode >> EveOnline.MemoryReading.getAllContainedDisplayTexts >> List.any (String.toLower >> String.contains "idle"))

                            dronesInBayQuantity =
                                droneGroupInBay.header.quantityFromTitle |> Maybe.withDefault 0

                            dronesInLocalSpaceQuantity =
                                droneGroupInLocalSpace.header.quantityFromTitle |> Maybe.withDefault 0
                        in
                        if 0 < (idlingDrones |> List.length) then
                            Just
                                (DescribeBranch "Engage idling drone(s)"
                                    (EndDecisionPath
                                        (Act
                                            { firstAction = droneGroupInLocalSpace.header.uiNode |> clickOnUIElement MouseButtonRight
                                            , followingSteps =
                                                [ ( "Click menu entry 'engage target'."
                                                  , lastContextMenuOrSubmenu
                                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "engage target")
                                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                                                  )
                                                ]
                                            }
                                        )
                                    )
                                )

                        else if 0 < dronesInBayQuantity && dronesInLocalSpaceQuantity < 5 then
                            Just
                                (DescribeBranch "Launch drones"
                                    (EndDecisionPath
                                        (Act
                                            { firstAction = droneGroupInBay.header.uiNode |> clickOnUIElement MouseButtonRight
                                            , followingSteps =
                                                [ ( "Click menu entry 'Launch drone'."
                                                  , lastContextMenuOrSubmenu
                                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Launch drone")
                                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
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
                if 0 < (droneGroupInLocalSpace.header.quantityFromTitle |> Maybe.withDefault 0) then
                    Just
                        (DescribeBranch "I see there are drones in local space. Return those to bay."
                            (EndDecisionPath
                                (Act
                                    { firstAction = droneGroupInLocalSpace.header.uiNode |> clickOnUIElement MouseButtonRight
                                    , followingSteps =
                                        [ ( "Click menu entry 'Return to drone bay'."
                                          , lastContextMenuOrSubmenu
                                                >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Return to drone bay")
                                                >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft)
                                          )
                                        ]
                                    }
                                )
                            )
                        )

                else
                    Nothing
            )


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
    case parseSettingsFromString defaultBotSettings (eventContext.configuration |> Maybe.withDefault "") of
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
        combatInfoLines =
            [ "Overview entries to attack: " ++ (parsedUserInterface |> allOverviewEntriesToAttack |> Maybe.map (List.length >> String.fromInt) |> Maybe.withDefault "Nothing") ]

        describeShip =
            case parsedUserInterface.shipUI of
                CanSee shipUI ->
                    "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    "I cannot see the ship UI. Please set up game client first."

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
    in
    [ describeShip ] ++ combatInfoLines ++ [ describeDrones ] |> String.join " "


allOverviewEntriesToAttack : ParsedUserInterface -> Maybe (List EveOnline.MemoryReading.OverviewWindowEntry)
allOverviewEntriesToAttack =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter shouldAttackOverviewEntry)


overviewEntryIsAlreadyTargetedOrTargeting : EveOnline.MemoryReading.OverviewWindowEntry -> Bool
overviewEntryIsAlreadyTargetedOrTargeting =
    .namesUnderSpaceObjectIcon
        >> Set.intersect ([ "targetedByMeIndicator", "targeting" ] |> Set.fromList)
        >> Set.isEmpty
        >> not


overviewEntryIsActiveTarget : EveOnline.MemoryReading.OverviewWindowEntry -> Bool
overviewEntryIsActiveTarget =
    .namesUnderSpaceObjectIcon
        >> Set.member "myActiveTargetIndicator"


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
    .shipUI
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen EveOnline.ParseUserInterface.groupShipUIModulesIntoRows
        >> Maybe.map .top
        >> Maybe.withDefault []


shipUIModulesToActivateAlways : ParsedUserInterface -> List ShipUIModule
shipUIModulesToActivateAlways =
    .shipUI
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen EveOnline.ParseUserInterface.groupShipUIModulesIntoRows
        >> Maybe.map .middle
        >> Maybe.withDefault []


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


lastContextMenuOrSubmenu : ParsedUserInterface -> Maybe EveOnline.MemoryReading.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


clickOnUIElement : MouseButton -> UIElement -> VolatileHostInterface.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromDisplayRegion)


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

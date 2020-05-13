{- EVE Online anomaly ratting bot version 2020-05-13

   Setup instructions for the EVE Online client:
   + Set the UI language to English.
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

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import Common.AppSettings as AppSettings
import Dict
import EveOnline.AppFramework exposing (AppEffect(..), getEntropyIntFromUserInterface)
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ParsedUserInterface
        , ShipUI
        , ShipUIModuleButton
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)
import Set


defaultBotSettings : BotSettings
defaultBotSettings =
    { anomalyName = ""
    , maxTargetCount = 3
    , botStepDelayMilliseconds = 1300
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleCommaSeparatedList
        {- Names to support with the `--app-settings`, see <https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#configuring-a-bot> -}
        ([ ( "anomaly-name"
           , AppSettings.ValueTypeString (\anomalyName -> \settings -> { settings | anomalyName = anomalyName })
           )
         , ( "bot-step-delay"
           , AppSettings.ValueTypeInteger (\delay settings -> { settings | botStepDelayMilliseconds = delay })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { anomalyName : String
    , maxTargetCount : Int
    , botStepDelayMilliseconds : Int
    }


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


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    }


type alias BotDecisionContext =
    { settings : BotSettings
    , memory : BotMemory
    , parsedUserInterface : ParsedUserInterface
    }


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings BotState


probeScanResultsRepresentsMatchingAnomaly : BotSettings -> EveOnline.ParseUserInterface.ProbeScanResult -> Bool
probeScanResultsRepresentsMatchingAnomaly settings probeScanResult =
    let
        anyContainedTextMatches predicate =
            probeScanResult.textsLeftToRight |> List.any predicate

        isCombatAnomaly =
            anyContainedTextMatches (String.toLower >> String.contains "combat")

        matchesName =
            (settings.anomalyName |> String.isEmpty)
                || anyContainedTextMatches (String.toLower >> String.contains (settings.anomalyName |> String.toLower))
    in
    isCombatAnomaly && matchesName


decideNextAction : BotDecisionContext -> DecisionPathNode
decideNextAction context =
    branchDependingOnDockedOrInSpace
        (DescribeBranch "I see no ship UI, assume we are docked." (EndDecisionPath Wait))
        (always Nothing)
        (\seeUndockingComplete ->
            DescribeBranch "I see we are in space, undocking complete." (decideNextActionWhenInSpace context seeUndockingComplete)
        )
        context.parsedUserInterface


decideNextActionWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideNextActionWhenInSpace context seeUndockingComplete =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        DescribeBranch "I see we are warping." (EndDecisionPath Wait)

    else
        case seeUndockingComplete |> shipUIModulesToActivateAlways |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
            Just inactiveModule ->
                DescribeBranch "I see an inactive module in the middle row. Activate the module."
                    (EndDecisionPath
                        (actWithoutFurtherReadings
                            ( "Click on the module.", [ inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft ] )
                        )
                    )

            Nothing ->
                combat context seeUndockingComplete enterAnomaly


combat : BotDecisionContext -> SeeUndockingComplete -> (BotDecisionContext -> DecisionPathNode) -> DecisionPathNode
combat context seeUndockingComplete continueIfCombatComplete =
    let
        overviewEntriesToAttack =
            seeUndockingComplete.overviewWindow.entries
                |> List.sortBy (.objectDistanceInMeters >> Result.withDefault 999999)
                |> List.filter shouldAttackOverviewEntry

        overviewEntriesToLock =
            overviewEntriesToAttack
                |> List.filter (overviewEntryIsTargetedOrTargeting >> not)

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
                                                        (DescribeBranch "No drones to return." (continueIfCombatComplete context))

                                             else
                                                DescribeBranch "Wait for target locking to complete." (EndDecisionPath Wait)
                                            )

                                    nextOverviewEntryToLock :: _ ->
                                        DescribeBranch "I see an overview entry to lock."
                                            (lockTargetFromOverviewEntry nextOverviewEntryToLock)
                                )

                        Just _ ->
                            DescribeBranch "I see a locked target."
                                (case seeUndockingComplete |> shipUIModulesToActivateOnTarget |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
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
                                                                        (lockTargetFromOverviewEntry nextOverviewEntryToLock)
                                                        )
                                                    )
                                            )

                                    Just inactiveModule ->
                                        DescribeBranch "I see an inactive module to activate on targets. Activate it."
                                            (EndDecisionPath
                                                (actWithoutFurtherReadings
                                                    ( "Click on the module."
                                                    , [ inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft ]
                                                    )
                                                )
                                            )
                                )
    in
    ensureShipIsOrbitingDecision
        |> Maybe.withDefault decisionIfAlreadyOrbiting


enterAnomaly : BotDecisionContext -> DecisionPathNode
enterAnomaly context =
    case context.parsedUserInterface.probeScannerWindow of
        CanNotSeeIt ->
            DescribeBranch "Can not see the probe scanner window." (EndDecisionPath Wait)

        CanSee probeScannerWindow ->
            let
                matchingScanResults =
                    probeScannerWindow.scanResults
                        |> List.filter (probeScanResultsRepresentsMatchingAnomaly context.settings)
            in
            case matchingScanResults |> listElementAtWrappedIndex (getEntropyIntFromUserInterface context.parsedUserInterface) of
                Nothing ->
                    DescribeBranch
                        ("I see " ++ (probeScannerWindow.scanResults |> List.length |> String.fromInt) ++ " scan results, and no matching anomaly.")
                        (EndDecisionPath Wait)

                Just anomalyScanResult ->
                    DescribeBranch "Warp to anomaly."
                        (EndDecisionPath
                            (Act
                                { actionsAlreadyDecided =
                                    ( "Rightclick on the scan result."
                                    , [ anomalyScanResult.uiNode |> clickOnUIElement MouseButtonRight ]
                                    )
                                , actionsDependingOnNewReadings =
                                    [ ( "Click menu entry 'Warp to Within'"
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
                                }
                            )
                        )


ensureShipIsOrbiting : ShipUI -> OverviewWindowEntry -> Maybe DecisionPathNode
ensureShipIsOrbiting shipUI overviewEntryToOrbit =
    if (shipUI.indication |> maybeVisibleAndThen .maneuverType) == CanSee EveOnline.ParseUserInterface.ManeuverOrbit then
        Nothing

    else
        Just
            (EndDecisionPath
                (actWithoutFurtherReadings
                    ( "Click on the overview entry and press the 'W' key."
                    , [ overviewEntryToOrbit.uiNode |> clickOnUIElement MouseButtonLeft
                      , VolatileHostInterface.KeyDown keyCodeLetterW
                      , VolatileHostInterface.KeyUp keyCodeLetterW
                      ]
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
                                    |> List.filter (.uiNode >> .uiNode >> EveOnline.ParseUserInterface.getAllContainedDisplayTexts >> List.any (String.toLower >> String.contains "idle"))

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
                                            { actionsAlreadyDecided =
                                                ( "Rightclick on the drones group."
                                                , [ droneGroupInLocalSpace.header.uiNode |> clickOnUIElement MouseButtonRight ]
                                                )
                                            , actionsDependingOnNewReadings =
                                                [ ( "Click menu entry 'engage target'."
                                                  , lastContextMenuOrSubmenu
                                                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "engage target")
                                                        >> Maybe.map (.uiNode >> clickOnUIElement MouseButtonLeft >> List.singleton)
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


actWithoutFurtherReadings : ( String, List VolatileHostInterface.EffectOnWindowStructure ) -> EndDecisionPathStructure
actWithoutFurtherReadings actionsAlreadyDecided =
    Act { actionsAlreadyDecided = actionsAlreadyDecided, actionsDependingOnNewReadings = [] }


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


initState : State
initState =
    EveOnline.AppFramework.initState
        { programState = Nothing
        , botMemory = { lastDockedStationNameFromInfoPanel = Nothing }
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { processEvent = processEveOnlineBotEvent
        , parseAppSettings = parseBotSettings
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.MemoryReadingCompleted parsedUserInterface ->
            let
                botSettings =
                    eventContext.appSettings |> Maybe.withDefault defaultBotSettings

                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory parsedUserInterface

                programStateIfEvalDecisionTreeNew =
                    let
                        originalDecision =
                            decideNextAction
                                { settings = botSettings, memory = botMemory, parsedUserInterface = parsedUserInterface }

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
                    [ parsedUserInterface |> describeUserInterfaceForMonitoring, describeActivity ]
                        |> String.join "\n"
            in
            ( { stateBefore | botMemory = botMemory, programState = programState }
            , EveOnline.AppFramework.ContinueSession
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


allOverviewEntriesToAttack : ParsedUserInterface -> Maybe (List EveOnline.ParseUserInterface.OverviewWindowEntry)
allOverviewEntriesToAttack =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter shouldAttackOverviewEntry)


overviewEntryIsTargetedOrTargeting : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsTargetedOrTargeting =
    .namesUnderSpaceObjectIcon
        >> Set.intersect ([ "targetedByMeIndicator", "targeting" ] |> Set.fromList)
        >> Set.isEmpty
        >> not


overviewEntryIsActiveTarget : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsActiveTarget =
    .namesUnderSpaceObjectIcon
        >> Set.member "myActiveTargetIndicator"


shouldAttackOverviewEntry : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
shouldAttackOverviewEntry =
    iconSpriteHasColorOfRat


iconSpriteHasColorOfRat : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
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
            currentReading.infoPanelContainer
                |> maybeVisibleAndThen .infoPanelLocationInfo
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


shipUIModulesToActivateOnTarget : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateOnTarget =
    .shipUI >> .moduleButtonsRows >> .top


shipUIModulesToActivateAlways : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateAlways =
    .shipUI >> .moduleButtonsRows >> .middle


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


lastContextMenuOrSubmenu : ParsedUserInterface -> Maybe EveOnline.ParseUserInterface.ContextMenu
lastContextMenuOrSubmenu =
    .contextMenus >> List.head


clickOnUIElement : MouseButton -> UIElement -> VolatileHostInterface.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.totalDisplayRegion |> centerFromDisplayRegion)


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


listElementAtWrappedIndex : Int -> List element -> Maybe element
listElementAtWrappedIndex indexToWrap list =
    if (list |> List.length) < 1 then
        Nothing

    else
        list |> List.drop (indexToWrap |> modBy (list |> List.length)) |> List.head

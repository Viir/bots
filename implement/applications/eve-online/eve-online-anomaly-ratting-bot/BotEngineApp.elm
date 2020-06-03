{- EVE Online anomaly ratting bot version 2020-06-03
   This bot uses the probe scanner to warp to anomalies and kills rats using drones and weapon modules.

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


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (listElementAtWrappedIndex)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , ReadingFromGameClient
        , ShipModulesMemory
        , UIElement
        , UseContextMenuCascadeNode
        , clickOnUIElement
        , getEntropyIntFromReadingFromGameClient
        , menuCascadeCompleted
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextEqual
        )
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , OverviewWindowEntry
        , ShipUI
        , ShipUIModuleButton
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        , maybeVisibleAndThen
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface
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


type alias TreeLeafAct =
    { actionsAlreadyDecided : ( String, List VolatileHostInterface.EffectOnWindowStructure )
    , actionsDependingOnNewReadings : List ( String, ReadingFromGameClient -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
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
            , remainingActions : List ( String, ReadingFromGameClient -> Maybe (List VolatileHostInterface.EffectOnWindowStructure) )
            }
    , botMemory : BotMemory
    }


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    , shipModules : ShipModulesMemory
    }


type alias BotDecisionContext =
    { eventContext : EveOnline.AppFramework.AppEventContext BotSettings
    , memory : BotMemory
    , readingFromGameClient : ReadingFromGameClient
    }


botSettingsFromDecisionContext : BotDecisionContext -> BotSettings
botSettingsFromDecisionContext decisionContext =
    decisionContext.eventContext.appSettings |> Maybe.withDefault defaultBotSettings


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
        (DescribeBranch "I see no ship UI, assume we are docked." askForHelpToGetUnstuck)
        (always Nothing)
        (\seeUndockingComplete ->
            DescribeBranch "I see we are in space, undocking complete." (decideNextActionWhenInSpace context seeUndockingComplete)
        )
        context.readingFromGameClient


decideNextActionWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideNextActionWhenInSpace context seeUndockingComplete =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        DescribeBranch "I see we are warping."
            ([ returnDronesToBay context.readingFromGameClient
             , readShipUIModuleButtonTooltips context
             ]
                |> List.filterMap identity
                |> List.head
                |> Maybe.withDefault waitForProgressInGame
            )

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
                context.readingFromGameClient.targets |> List.filter .isActiveTarget

        ensureShipIsOrbitingDecision =
            overviewEntriesToAttack
                |> List.head
                |> Maybe.andThen (\overviewEntryToAttack -> ensureShipIsOrbiting seeUndockingComplete.shipUI overviewEntryToAttack)

        decisionIfAlreadyOrbiting =
            case targetsToUnlock |> List.head of
                Just targetToUnlock ->
                    DescribeBranch "I see a target to unlock."
                        (useContextMenuCascade
                            ( "locked target", targetToUnlock.barAndImageCont |> Maybe.withDefault targetToUnlock.uiNode )
                            (useMenuEntryWithTextContaining "unlock" menuCascadeCompleted)
                        )

                Nothing ->
                    case context.readingFromGameClient.targets |> List.head of
                        Nothing ->
                            DescribeBranch "I see no locked target."
                                (case overviewEntriesToLock of
                                    [] ->
                                        DescribeBranch "I see no overview entry to lock."
                                            (if overviewEntriesToAttack |> List.isEmpty then
                                                returnDronesToBay context.readingFromGameClient
                                                    |> Maybe.withDefault
                                                        (DescribeBranch "No drones to return." (continueIfCombatComplete context))

                                             else
                                                DescribeBranch "Wait for target locking to complete." waitForProgressInGame
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
                                            (launchAndEngageDrones context.readingFromGameClient
                                                |> Maybe.withDefault
                                                    (DescribeBranch "No idling drones."
                                                        (if (context |> botSettingsFromDecisionContext).maxTargetCount <= (context.readingFromGameClient.targets |> List.length) then
                                                            DescribeBranch "Enough locked targets." waitForProgressInGame

                                                         else
                                                            case overviewEntriesToLock of
                                                                [] ->
                                                                    DescribeBranch "I see no more overview entries to lock." waitForProgressInGame

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
    case context.readingFromGameClient.probeScannerWindow of
        CanNotSeeIt ->
            DescribeBranch "I do not see the probe scanner window." askForHelpToGetUnstuck

        CanSee probeScannerWindow ->
            let
                matchingScanResults =
                    probeScannerWindow.scanResults
                        |> List.filter (probeScanResultsRepresentsMatchingAnomaly (context |> botSettingsFromDecisionContext))
            in
            case
                matchingScanResults
                    |> listElementAtWrappedIndex (getEntropyIntFromReadingFromGameClient context.readingFromGameClient)
            of
                Nothing ->
                    DescribeBranch
                        ("I see "
                            ++ (probeScannerWindow.scanResults |> List.length |> String.fromInt)
                            ++ " scan results, and no matching anomaly. Wait for a matching anomaly to appear."
                        )
                        waitForProgressInGame

                Just anomalyScanResult ->
                    DescribeBranch "Warp to anomaly."
                        (useContextMenuCascade
                            ( "Scan result", anomalyScanResult.uiNode )
                            (useMenuEntryWithTextContaining "Warp to Within"
                                (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
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


keyCodeLetterW : Common.EffectOnWindow.VirtualKeyCode
keyCodeLetterW =
    Common.EffectOnWindow.VirtualKeyCodeFromInt 0x57


launchAndEngageDrones : ReadingFromGameClient -> Maybe DecisionPathNode
launchAndEngageDrones readingFromGameClient =
    readingFromGameClient.dronesWindow
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
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                        (useMenuEntryWithTextContaining "engage target" menuCascadeCompleted)
                                    )
                                )

                        else if 0 < dronesInBayQuantity && dronesInLocalSpaceQuantity < 5 then
                            Just
                                (DescribeBranch "Launch drones"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInBay.header.uiNode )
                                        (useMenuEntryWithTextContaining "Launch drone" menuCascadeCompleted)
                                    )
                                )

                        else
                            Nothing

                    _ ->
                        Nothing
            )


returnDronesToBay : ReadingFromGameClient -> Maybe DecisionPathNode
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
                            (useContextMenuCascade
                                ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                (useMenuEntryWithTextContaining "Return to drone bay" menuCascadeCompleted)
                            )
                        )
            )


lockTargetFromOverviewEntry : OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry =
    DescribeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
        (useContextMenuCascadeOnOverviewEntry overviewEntry
            (useMenuEntryWithTextEqual "Lock target" menuCascadeCompleted)
        )


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips context =
    context.readingFromGameClient.shipUI
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


actWithoutFurtherReadings : ( String, List VolatileHostInterface.EffectOnWindowStructure ) -> EndDecisionPathStructure
actWithoutFurtherReadings actionsAlreadyDecided =
    Act { actionsAlreadyDecided = actionsAlreadyDecided, actionsDependingOnNewReadings = [] }


useContextMenuCascadeOnOverviewEntry :
    OverviewWindowEntry
    -> UseContextMenuCascadeNode
    -> DecisionPathNode
useContextMenuCascadeOnOverviewEntry overviewEntry useContextMenu =
    useContextMenuCascade
        ( "overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'", overviewEntry.uiNode )
        useContextMenu


type alias SeeUndockingComplete =
    { shipUI : EveOnline.ParseUserInterface.ShipUI
    , overviewWindow : EveOnline.ParseUserInterface.OverviewWindow
    }


branchDependingOnDockedOrInSpace :
    DecisionPathNode
    -> (EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode)
    -> (SeeUndockingComplete -> DecisionPathNode)
    -> ReadingFromGameClient
    -> DecisionPathNode
branchDependingOnDockedOrInSpace branchIfDocked branchIfCanSeeShipUI branchIfUndockingComplete readingFromGameClient =
    case readingFromGameClient.shipUI of
        CanNotSeeIt ->
            branchIfDocked

        CanSee shipUI ->
            branchIfCanSeeShipUI shipUI
                |> Maybe.withDefault
                    (case readingFromGameClient.overviewWindow of
                        CanNotSeeIt ->
                            DescribeBranch "I see no overview window, wait until undocking completed." waitForProgressInGame

                        CanSee overviewWindow ->
                            branchIfUndockingComplete
                                { shipUI = shipUI, overviewWindow = overviewWindow }
                    )


waitForProgressInGame : DecisionPathNode
waitForProgressInGame =
    EndDecisionPath Wait


askForHelpToGetUnstuck : DecisionPathNode
askForHelpToGetUnstuck =
    DescribeBranch "I am stuck here and need help to continue." (EndDecisionPath Wait)


initState : State
initState =
    EveOnline.AppFramework.initState
        { programState = Nothing
        , botMemory =
            { lastDockedStationNameFromInfoPanel = Nothing
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
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            let
                botMemory =
                    stateBefore.botMemory |> integrateCurrentReadingsIntoBotMemory readingFromGameClient

                decisionContext =
                    { eventContext = eventContext
                    , memory = botMemory
                    , readingFromGameClient = readingFromGameClient
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
                            case readingFromGameClient |> nextActionEffectFromUserInterface of
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
                    [ readingFromGameClient |> describeReadingFromGameClientForMonitoring, describeActivity ]
                        |> String.join "\n"
            in
            ( { stateBefore | botMemory = botMemory, programState = programState }
            , EveOnline.AppFramework.ContinueSession
                { effects = effectsRequests
                , millisecondsToNextReadingFromGame = (decisionContext |> botSettingsFromDecisionContext).botStepDelayMilliseconds
                , statusDescriptionText = statusMessage
                }
            )


describeReadingFromGameClientForMonitoring : ReadingFromGameClient -> String
describeReadingFromGameClientForMonitoring readingFromGameClient =
    let
        combatInfoLines =
            [ "Overview entries to attack: " ++ (readingFromGameClient |> allOverviewEntriesToAttack |> Maybe.map (List.length >> String.fromInt) |> Maybe.withDefault "Nothing") ]

        describeShip =
            case readingFromGameClient.shipUI of
                CanSee shipUI ->
                    "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                CanNotSeeIt ->
                    "I do not see the ship UI. Please set up game client first."

        describeDrones =
            case readingFromGameClient.dronesWindow of
                CanNotSeeIt ->
                    "I do not see the drones window."

                CanSee dronesWindow ->
                    "I see the drones window: In bay: "
                        ++ (dronesWindow.droneGroupInBay |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ ", in local space: "
                        ++ (dronesWindow.droneGroupInLocalSpace |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ "."
    in
    [ describeShip ] ++ combatInfoLines ++ [ describeDrones ] |> String.join " "


allOverviewEntriesToAttack : ReadingFromGameClient -> Maybe (List EveOnline.ParseUserInterface.OverviewWindowEntry)
allOverviewEntriesToAttack =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter shouldAttackOverviewEntry)


overviewEntryIsTargetedOrTargeting : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsTargetedOrTargeting overviewEntry =
    overviewEntry.commonIndications.targetedByMe || overviewEntry.commonIndications.targeting


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


integrateCurrentReadingsIntoBotMemory : ReadingFromGameClient -> BotMemory -> BotMemory
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


shipUIModulesToActivateOnTarget : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateOnTarget =
    .shipUI >> .moduleButtonsRows >> .top


shipUIModulesToActivateAlways : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateAlways =
    .shipUI >> .moduleButtonsRows >> .middle


useContextMenuCascade : ( String, UIElement ) -> UseContextMenuCascadeNode -> DecisionPathNode
useContextMenuCascade ( initialUIElementName, initialUIElement ) useContextMenu =
    { actionsAlreadyDecided =
        ( "Open context menu on " ++ initialUIElementName
        , [ initialUIElement |> clickOnUIElement MouseButtonRight
          ]
        )
    , actionsDependingOnNewReadings = useContextMenu |> EveOnline.AppFramework.unpackContextMenuTreeToListOfActionsDependingOnReadings
    }
        |> Act
        |> EndDecisionPath


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

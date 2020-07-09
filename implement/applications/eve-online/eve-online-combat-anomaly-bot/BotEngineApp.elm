{- EVE Online combat anomaly bot version 2020-07-09
   This bot uses the probe scanner to warp to combat anomalies and kills rats using drones and weapon modules.

   Setup instructions for the EVE Online client:
   + Set the UI language to English.
   + Undock, open probe scanner, overview window and drones window.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + In the ship UI, arrange the modules:
     + Place to use in combat (to activate on targets) in the top row.
     + Place modules that should always be active in the middle row.
     + Hide passive modules by disabling the check-box `Display Passive Modules`.
   + Configure the keyboard key 'W' to make the ship orbit.

   ## Configuration Settings
   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `anomaly-name` : Choose the name of anomalies to take. You can use this setting multiple times to select multiple names.

   Here is an example of a complete app-settings string:
   --app-settings="anomaly-name=Drone Patrol,anomaly-name=Drone Horde"
-}
{-
   app-catalog-tags:eve-online,anomaly,ratting
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200610 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (listElementAtWrappedIndex)
import Common.DecisionTree exposing (describeBranch, endDecisionPath)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , EndDecisionPathStructure(..)
        , ReadingFromGameClient
        , SeeUndockingComplete
        , ShipModulesMemory
        , actWithoutFurtherReadings
        , askForHelpToGetUnstuck
        , branchDependingOnDockedOrInSpace
        , clickOnUIElement
        , getEntropyIntFromReadingFromGameClient
        , menuCascadeCompleted
        , useContextMenuCascade
        , useContextMenuCascadeOnOverviewEntry
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextEqual
        , waitForProgressInGame
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
    { anomalyNames = []
    , maxTargetCount = 3
    , botStepDelayMilliseconds = 1300
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleCommaSeparatedList
        {- Names to support with the `--app-settings`, see <https://github.com/Viir/bots/blob/master/guide/how-to-run-a-bot.md#configuring-a-bot> -}
        ([ ( "anomaly-name"
           , AppSettings.ValueTypeString
                (\anomalyName ->
                    \settings ->
                        { settings | anomalyNames = anomalyName :: settings.anomalyNames }
                )
           )
         , ( "bot-step-delay"
           , AppSettings.ValueTypeInteger (\delay settings -> { settings | botStepDelayMilliseconds = delay })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { anomalyNames : List String
    , maxTargetCount : Int
    , botStepDelayMilliseconds : Int
    }


type alias BotState =
    EveOnline.AppFramework.AppStateWithMemoryAndDecisionTree BotMemory


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    , shipModules : ShipModulesMemory
    }


type alias BotDecisionContext =
    EveOnline.AppFramework.StepDecisionContext BotSettings BotMemory


botSettingsFromDecisionContext : BotDecisionContext -> BotSettings
botSettingsFromDecisionContext decisionContext =
    decisionContext.eventContext.appSettings |> Maybe.withDefault defaultBotSettings


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings BotState


probeScanResultsRepresentsMatchingAnomaly : BotSettings -> EveOnline.ParseUserInterface.ProbeScanResult -> Bool
probeScanResultsRepresentsMatchingAnomaly settings probeScanResult =
    let
        isCombatAnomaly =
            probeScanResult.cellsTexts
                |> Dict.get "Group"
                |> Maybe.map (String.toLower >> String.contains "combat")
                |> Maybe.withDefault False

        matchesNameFromSettings =
            (settings.anomalyNames |> List.isEmpty)
                || (settings.anomalyNames
                        |> List.any
                            (\anomalyName ->
                                probeScanResult.cellsTexts
                                    |> Dict.get "Name"
                                    |> Maybe.map (String.toLower >> (==) (anomalyName |> String.toLower |> String.trim))
                                    |> Maybe.withDefault False
                            )
                   )
    in
    isCombatAnomaly && matchesNameFromSettings


anomalyBotDecisionRoot : BotDecisionContext -> DecisionPathNode
anomalyBotDecisionRoot context =
    branchDependingOnDockedOrInSpace
        { ifDocked = askForHelpToGetUnstuck
        , ifSeeShipUI = always Nothing
        , ifUndockingComplete = decideNextActionWhenInSpace context
        }
        context.readingFromGameClient


decideNextActionWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideNextActionWhenInSpace context seeUndockingComplete =
    if seeUndockingComplete.shipUI |> isShipWarpingOrJumping then
        describeBranch "I see we are warping."
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
                describeBranch "I see an inactive module in the middle row. Activate the module."
                    (endDecisionPath
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

        seeingOtherPilotInOverview =
            seeUndockingComplete.overviewWindow.entries
                |> List.any (.objectAlliance >> Maybe.map (String.isEmpty >> not) >> Maybe.withDefault False)

        ensureShipIsOrbitingDecision =
            overviewEntriesToAttack
                |> List.head
                |> Maybe.andThen (\overviewEntryToAttack -> ensureShipIsOrbiting seeUndockingComplete.shipUI overviewEntryToAttack)

        decisionIfAlreadyOrbiting =
            case targetsToUnlock |> List.head of
                Just targetToUnlock ->
                    describeBranch "I see a target to unlock."
                        (useContextMenuCascade
                            ( "locked target", targetToUnlock.barAndImageCont |> Maybe.withDefault targetToUnlock.uiNode )
                            (useMenuEntryWithTextContaining "unlock" menuCascadeCompleted)
                        )

                Nothing ->
                    case context.readingFromGameClient.targets |> List.head of
                        Nothing ->
                            describeBranch "I see no locked target."
                                (case overviewEntriesToLock of
                                    [] ->
                                        describeBranch "I see no overview entry to lock."
                                            (if overviewEntriesToAttack |> List.isEmpty then
                                                returnDronesToBay context.readingFromGameClient
                                                    |> Maybe.withDefault
                                                        (describeBranch "No drones to return." (continueIfCombatComplete context))

                                             else
                                                describeBranch "Wait for target locking to complete." waitForProgressInGame
                                            )

                                    nextOverviewEntryToLock :: _ ->
                                        describeBranch "I see an overview entry to lock."
                                            (lockTargetFromOverviewEntry nextOverviewEntryToLock)
                                )

                        Just _ ->
                            describeBranch "I see a locked target."
                                (case seeUndockingComplete |> shipUIModulesToActivateOnTarget |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                    Nothing ->
                                        describeBranch "All attack modules are active."
                                            (launchAndEngageDrones context.readingFromGameClient
                                                |> Maybe.withDefault
                                                    (describeBranch "No idling drones."
                                                        (if (context |> botSettingsFromDecisionContext).maxTargetCount <= (context.readingFromGameClient.targets |> List.length) then
                                                            describeBranch "Enough locked targets." waitForProgressInGame

                                                         else
                                                            case overviewEntriesToLock of
                                                                [] ->
                                                                    describeBranch "I see no more overview entries to lock." waitForProgressInGame

                                                                nextOverviewEntryToLock :: _ ->
                                                                    describeBranch "Lock more targets."
                                                                        (lockTargetFromOverviewEntry nextOverviewEntryToLock)
                                                        )
                                                    )
                                            )

                                    Just inactiveModule ->
                                        describeBranch "I see an inactive module to activate on targets. Activate it."
                                            (endDecisionPath
                                                (actWithoutFurtherReadings
                                                    ( "Click on the module."
                                                    , [ inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft ]
                                                    )
                                                )
                                            )
                                )
    in
    if seeingOtherPilotInOverview then
        describeBranch
            "I see another pilot in the overview. Skip this anomaly."
            (returnDronesToBay context.readingFromGameClient
                |> Maybe.withDefault
                    (describeBranch "No drones to return." (continueIfCombatComplete context))
            )

    else
        ensureShipIsOrbitingDecision
            |> Maybe.withDefault decisionIfAlreadyOrbiting


enterAnomaly : BotDecisionContext -> DecisionPathNode
enterAnomaly context =
    case context.readingFromGameClient.probeScannerWindow of
        CanNotSeeIt ->
            describeBranch "I do not see the probe scanner window." askForHelpToGetUnstuck

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
                    describeBranch
                        ("I see "
                            ++ (probeScannerWindow.scanResults |> List.length |> String.fromInt)
                            ++ " scan results, and no matching anomaly. Wait for a matching anomaly to appear."
                        )
                        waitForProgressInGame

                Just anomalyScanResult ->
                    describeBranch "Warp to anomaly."
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
            (endDecisionPath
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
                                (describeBranch "Engage idling drone(s)"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                        (useMenuEntryWithTextContaining "engage target" menuCascadeCompleted)
                                    )
                                )

                        else if 0 < dronesInBayQuantity && dronesInLocalSpaceQuantity < 5 then
                            Just
                                (describeBranch "Launch drones"
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
                        (describeBranch "I see there are drones in local space. Return those to bay."
                            (useContextMenuCascade
                                ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                (useMenuEntryWithTextContaining "Return to drone bay" menuCascadeCompleted)
                            )
                        )
            )


lockTargetFromOverviewEntry : OverviewWindowEntry -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry =
    describeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
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
                endDecisionPath
                    (actWithoutFurtherReadings
                        ( "Read tooltip for module button"
                        , [ VolatileHostInterface.MouseMoveTo
                                { location = moduleButtonWithoutMemoryOfTooltip.uiNode.totalDisplayRegion |> centerFromDisplayRegion }
                          ]
                        )
                    )
            )


initState : State
initState =
    EveOnline.AppFramework.initState
        (EveOnline.AppFramework.initStateWithMemoryAndDecisionTree
            { lastDockedStationNameFromInfoPanel = Nothing
            , shipModules = EveOnline.AppFramework.initShipModulesMemory
            }
        )


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = parseBotSettings
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
        , statusTextFromState = statusTextFromState
        , decisionTreeRoot = anomalyBotDecisionRoot
        , millisecondsToNextReadingFromGame = botSettingsFromDecisionContext >> .botStepDelayMilliseconds
        }


statusTextFromState : BotDecisionContext -> String
statusTextFromState context =
    let
        readingFromGameClient =
            context.readingFromGameClient

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


updateMemoryForNewReadingFromGame : ReadingFromGameClient -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame currentReading botMemoryBefore =
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


shipUIModulesToActivateOnTarget : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateOnTarget =
    .shipUI >> .moduleButtonsRows >> .top


shipUIModulesToActivateAlways : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateAlways =
    .shipUI >> .moduleButtonsRows >> .middle


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

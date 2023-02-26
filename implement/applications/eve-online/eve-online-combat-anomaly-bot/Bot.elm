{- EVE Online combat anomaly bot version 2023-02-25

   This bot uses the probe scanner to find combat anomalies and kills rats using drones and weapon modules.

   ## Features

   + Automatically detects if another pilot is in an anomaly on arrival and switches to another anomaly if necessary.
   + Filtering for specific anomalies using bot settings.
   + Avoiding dangerous or too-powerful rats using bot settings.
   + Remembers observed properties of anomalies, like other pilots or dangerous rats, to inform the selection of anomalies in the future.

   ## Setting up the Game Client

   Despite being quite robust, this bot is less intelligent than a human. For example, its perception is more limited than ours, so we need to set up the game to ensure that the bot can see everything it needs. Following is the list of setup instructions for the EVE Online client:

   + Set the UI language to English.
   + Undock, open probe scanner, overview window and drones window.
   + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
   + In the ship UI, arrange the modules:
     + Place the modules to use in combat (to activate on targets) in the top row.
     + Hide passive modules by disabling the check-box `Display Passive Modules`.
   + Configure the keyboard key 'W' to make the ship orbit.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `anomaly-name` : Choose the name of anomalies to take. You can use this setting multiple times to select multiple names.
   + `hide-when-neutral-in-local` : Set this to 'yes' to make the bot dock in a station or structure when a neutral or hostile appears in the 'local' chat.
   + `avoid-rat` : Name of a rat to avoid, as it appears in the overview. You can use this setting multiple times to select multiple names.
   + `activate-module-always` : Text found in tooltips of ship modules that should always be active. For example: "shield hardener".
   + `anomaly-wait-time`: Minimum time to wait after arriving in an anomaly before considering it finished. Use this if you see anomalies in which rats arrive later than you arrive on grid.

   When using more than one setting, start a new line for each setting in the text input field.
   Here is an example of a complete settings string:

   ```
   anomaly-name = Drone Patrol
   anomaly-name = Drone Horde
   hide-when-neutral-in-local = yes
   avoid-rat = Infested Carrier
   activate-module-always = shield hardener
   ```

   To learn more about the anomaly bot, see <https://to.botlab.org/guide/app/eve-online-combat-anomaly-bot>

-}
{-
   catalog-tags:eve-online,anomaly,ratting
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2023_02_06 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (listElementAtWrappedIndex, stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.BotFramework
    exposing
        ( ModuleButtonTooltipMemory
        , ReadingFromGameClient
        , SeeUndockingComplete
        , ShipModulesMemory
        , UseContextMenuCascadeNode(..)
        , doEffectsClickModuleButton
        , localChatWindowFromUserInterface
        , menuCascadeCompleted
        , mouseClickOnUIElement
        , pickEntryFromLastContextMenuInCascade
        , shipUIIndicatesShipIsWarpingOrJumping
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        , useMenuEntryWithTextEqual
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , UpdateMemoryContext
        , askForHelpToGetUnstuck
        , branchDependingOnDockedOrInSpace
        , decideActionForCurrentStep
        , ensureInfoPanelLocationInfoIsExpanded
        , useContextMenuCascade
        , useContextMenuCascadeOnListSurroundingsButton
        , useContextMenuCascadeOnOverviewEntry
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface
    exposing
        ( OverviewWindowEntry
        , ShipUI
        , ShipUIModuleButton
        )
import Set


defaultBotSettings : BotSettings
defaultBotSettings =
    { hideWhenNeutralInLocal = AppSettings.No
    , anomalyNames = []
    , avoidRats = []
    , activateModulesAlways = []
    , maxTargetCount = 3
    , botStepDelayMilliseconds = 1400
    , anomalyWaitTimeSeconds = 15
    , orbitInCombat = AppSettings.Yes
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "hide-when-neutral-in-local"
           , AppSettings.valueTypeYesOrNo
                (\hide settings -> { settings | hideWhenNeutralInLocal = hide })
           )
         , ( "anomaly-name"
           , AppSettings.valueTypeString
                (\anomalyName settings ->
                    { settings | anomalyNames = String.trim anomalyName :: settings.anomalyNames }
                )
           )
         , ( "avoid-rat"
           , AppSettings.valueTypeString
                (\ratToAvoid settings ->
                    { settings | avoidRats = String.trim ratToAvoid :: settings.avoidRats }
                )
           )
         , ( "activate-module-always"
           , AppSettings.valueTypeString
                (\moduleName settings ->
                    { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways }
                )
           )
         , ( "anomaly-wait-time"
           , AppSettings.valueTypeInteger
                (\anomalyWaitTimeSeconds settings ->
                    { settings | anomalyWaitTimeSeconds = anomalyWaitTimeSeconds }
                )
           )
         , ( "orbit-in-combat"
           , AppSettings.valueTypeYesOrNo
                (\orbitInCombat settings ->
                    { settings | orbitInCombat = orbitInCombat }
                )
           )
         , ( "bot-step-delay"
           , AppSettings.valueTypeInteger
                (\delay settings ->
                    { settings | botStepDelayMilliseconds = delay }
                )
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


type alias BotSettings =
    { hideWhenNeutralInLocal : AppSettings.YesOrNo
    , anomalyNames : List String
    , avoidRats : List String
    , activateModulesAlways : List String
    , maxTargetCount : Int
    , anomalyWaitTimeSeconds : Int
    , botStepDelayMilliseconds : Int
    , orbitInCombat : AppSettings.YesOrNo
    }


type alias State =
    EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory


type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String
    , shipModules : ShipModulesMemory
    , shipWarpingInLastReading : Maybe Bool
    , visitedAnomalies : Dict.Dict String MemoryOfAnomaly
    }


type alias MemoryOfAnomaly =
    { arrivalTime : { milliseconds : Int }
    , otherPilotsFoundOnArrival : List String
    , ratsSeen : Set.Set String
    }


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


type ReasonToIgnoreProbeScanResult
    = ScanResultHasNoID
    | AvoidAnomaly ReasonToAvoidAnomaly


type ReasonToAvoidAnomaly
    = IsNoCombatAnomaly
    | DoesNotMatchAnomalyNameFromSettings
    | FoundOtherPilotOnArrival String
    | FoundRatToAvoid String


describeReasonToAvoidAnomaly : ReasonToAvoidAnomaly -> String
describeReasonToAvoidAnomaly reason =
    case reason of
        IsNoCombatAnomaly ->
            "Is not a combat anomaly"

        DoesNotMatchAnomalyNameFromSettings ->
            "Does not match an anomaly name from the settings"

        FoundOtherPilotOnArrival otherPilot ->
            "Found another pilot on arrival: " ++ otherPilot

        FoundRatToAvoid rat ->
            "Found a rat to avoid: " ++ rat


findReasonToIgnoreProbeScanResult : BotDecisionContext -> EveOnline.ParseUserInterface.ProbeScanResult -> Maybe ReasonToIgnoreProbeScanResult
findReasonToIgnoreProbeScanResult context probeScanResult =
    case probeScanResult.cellsTexts |> Dict.get "ID" of
        Nothing ->
            Just ScanResultHasNoID

        Just scanResultID ->
            let
                isCombatAnomaly =
                    probeScanResult.cellsTexts
                        |> Dict.get "Group"
                        |> Maybe.map (stringContainsIgnoringCase "combat")
                        |> Maybe.withDefault False

                matchesAnomalyNameFromSettings =
                    (context.eventContext.botSettings.anomalyNames |> List.isEmpty)
                        || (context.eventContext.botSettings.anomalyNames
                                |> List.any
                                    (\anomalyName ->
                                        probeScanResult.cellsTexts
                                            |> Dict.get "Name"
                                            |> Maybe.map (String.toLower >> (==) (anomalyName |> String.toLower |> String.trim))
                                            |> Maybe.withDefault False
                                    )
                           )
            in
            if not isCombatAnomaly then
                Just (AvoidAnomaly IsNoCombatAnomaly)

            else if not matchesAnomalyNameFromSettings then
                Just (AvoidAnomaly DoesNotMatchAnomalyNameFromSettings)

            else
                findReasonToAvoidAnomalyFromMemory context { anomalyID = scanResultID }
                    |> Maybe.map AvoidAnomaly


findReasonToAvoidAnomalyFromMemory : BotDecisionContext -> { anomalyID : String } -> Maybe ReasonToAvoidAnomaly
findReasonToAvoidAnomalyFromMemory context { anomalyID } =
    case memoryOfAnomalyWithID anomalyID context.memory of
        Nothing ->
            Nothing

        Just memoryOfAnomaly ->
            case memoryOfAnomaly.otherPilotsFoundOnArrival of
                otherPilotFoundOnArrival :: _ ->
                    Just (FoundOtherPilotOnArrival otherPilotFoundOnArrival)

                [] ->
                    let
                        ratsToAvoidSeen =
                            getRatsToAvoidSeenInAnomaly context.eventContext.botSettings memoryOfAnomaly
                    in
                    case ratsToAvoidSeen |> Set.toList of
                        ratToAvoid :: _ ->
                            Just (FoundRatToAvoid ratToAvoid)

                        [] ->
                            Nothing


getRatsToAvoidSeenInAnomaly : BotSettings -> MemoryOfAnomaly -> Set.Set String
getRatsToAvoidSeenInAnomaly settings =
    .ratsSeen >> Set.filter (shouldAvoidRatAccordingToSettings settings)


shouldAvoidRatAccordingToSettings : BotSettings -> String -> Bool
shouldAvoidRatAccordingToSettings settings ratName =
    settings.avoidRats |> List.map String.toLower |> List.member (ratName |> String.toLower)


memoryOfAnomalyWithID : String -> BotMemory -> Maybe MemoryOfAnomaly
memoryOfAnomalyWithID anomalyID =
    .visitedAnomalies >> Dict.get anomalyID


anomalyBotDecisionRoot : BotDecisionContext -> DecisionPathNode
anomalyBotDecisionRoot context =
    anomalyBotDecisionRootBeforeApplyingSettings context
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase
            context.eventContext.botSettings.botStepDelayMilliseconds


anomalyBotDecisionRootBeforeApplyingSettings : BotDecisionContext -> DecisionPathNode
anomalyBotDecisionRootBeforeApplyingSettings context =
    generalSetupInUserInterface context.readingFromGameClient
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                { ifDocked =
                    continueIfShouldHide
                        { ifShouldHide =
                            describeBranch "Stay docked." waitForProgressInGame
                        }
                        context
                        |> Maybe.withDefault (undockUsingStationWindow context)
                , ifSeeShipUI =
                    always
                        (continueIfShouldHide
                            { ifShouldHide =
                                returnDronesToBay context
                                    |> Maybe.withDefault
                                        (describeBranch
                                            "Dock to station or structure."
                                            (dockAtRandomStationOrStructure context)
                                        )
                            }
                            context
                        )
                , ifUndockingComplete = decideNextActionWhenInSpace context
                }
                context.readingFromGameClient
            )


generalSetupInUserInterface : ReadingFromGameClient -> Maybe DecisionPathNode
generalSetupInUserInterface readingFromGameClient =
    [ closeMessageBox, ensureInfoPanelLocationInfoIsExpanded ]
        |> List.filterMap
            (\maybeSetupDecisionFromGameReading ->
                maybeSetupDecisionFromGameReading readingFromGameClient
            )
        |> List.head


closeMessageBox : ReadingFromGameClient -> Maybe DecisionPathNode
closeMessageBox readingFromGameClient =
    readingFromGameClient.messageBoxes
        |> List.head
        |> Maybe.map
            (\messageBox ->
                describeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose =
                            .mainText
                                >> Maybe.map (String.trim >> String.toLower >> (\buttonText -> [ "close", "ok" ] |> List.member buttonText))
                                >> Maybe.withDefault False
                     in
                     case messageBox.buttons |> List.filter buttonCanBeUsedToClose |> List.head of
                        Nothing ->
                            describeBranch "I see no way to close this message box." askForHelpToGetUnstuck

                        Just buttonToUse ->
                            describeBranch ("Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'.")
                                (decideActionForCurrentStep
                                    (mouseClickOnUIElement MouseButtonLeft buttonToUse.uiNode)
                                )
                    )
            )


continueIfShouldHide : { ifShouldHide : DecisionPathNode } -> BotDecisionContext -> Maybe DecisionPathNode
continueIfShouldHide config context =
    case
        context.eventContext |> EveOnline.BotFramework.secondsToSessionEnd |> Maybe.andThen (nothingFromIntIfGreaterThan 200)
    of
        Just secondsToSessionEnd ->
            Just
                (describeBranch ("Session ends in " ++ (secondsToSessionEnd |> String.fromInt) ++ " seconds.")
                    config.ifShouldHide
                )

        Nothing ->
            if context.eventContext.botSettings.hideWhenNeutralInLocal /= AppSettings.Yes then
                Nothing

            else
                case context.readingFromGameClient |> localChatWindowFromUserInterface of
                    Nothing ->
                        Just (describeBranch "I don't see the local chat window." askForHelpToGetUnstuck)

                    Just localChatWindow ->
                        let
                            chatUserHasGoodStanding chatUser =
                                goodStandingPatterns
                                    |> List.any
                                        (\goodStandingPattern ->
                                            chatUser.standingIconHint
                                                |> Maybe.map (stringContainsIgnoringCase goodStandingPattern)
                                                |> Maybe.withDefault False
                                        )

                            subsetOfUsersWithNoGoodStanding =
                                localChatWindow.userlist
                                    |> Maybe.map .visibleUsers
                                    |> Maybe.withDefault []
                                    |> List.filter (chatUserHasGoodStanding >> not)
                        in
                        if 1 < (subsetOfUsersWithNoGoodStanding |> List.length) then
                            Just (describeBranch "There is an enemy or neutral in local chat." config.ifShouldHide)

                        else
                            Nothing


{-| 2020-07-11 Discovery by Viktor:
The entries for structures in the menu from the SurroundingsButton can be nested one level deeper than the ones for stations.
In other words, not all structures appear directly under the "structures" entry.
-}
dockAtRandomStationOrStructure : BotDecisionContext -> DecisionPathNode
dockAtRandomStationOrStructure context =
    let
        withTextContainingIgnoringCase textToSearch =
            List.filter (.text >> String.toLower >> (==) (textToSearch |> String.toLower)) >> List.head

        menuEntryIsSuitable menuEntry =
            [ "cyno beacon", "jump gate" ]
                |> List.any (\toAvoid -> menuEntry.text |> stringContainsIgnoringCase toAvoid)
                |> not

        chooseNextMenuEntry =
            { describeChoice = "Use 'Dock' if available or a random entry."
            , chooseEntry =
                pickEntryFromLastContextMenuInCascade
                    (\menuEntries ->
                        let
                            suitableMenuEntries =
                                List.filter menuEntryIsSuitable menuEntries
                        in
                        [ withTextContainingIgnoringCase "dock"
                        , List.filter (.text >> stringContainsIgnoringCase "station")
                            >> Common.Basics.listElementAtWrappedIndex
                                (context.randomIntegers |> List.head |> Maybe.withDefault 0)
                        , Common.Basics.listElementAtWrappedIndex
                            (context.randomIntegers |> List.head |> Maybe.withDefault 0)
                        ]
                            |> List.filterMap (\priority -> suitableMenuEntries |> priority)
                            |> List.head
                    )
            }
    in
    useContextMenuCascadeOnListSurroundingsButton
        (useMenuEntryWithTextContainingFirstOf [ "stations", "structures" ]
            (MenuEntryWithCustomChoice chooseNextMenuEntry
                (MenuEntryWithCustomChoice chooseNextMenuEntry
                    (MenuEntryWithCustomChoice chooseNextMenuEntry MenuCascadeCompleted)
                )
            )
        )
        context


decideNextActionWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideNextActionWhenInSpace context seeUndockingComplete =
    if seeUndockingComplete.shipUI |> shipUIIndicatesShipIsWarpingOrJumping then
        describeBranch "I see we are warping."
            ([ returnDronesToBay context
             , readShipUIModuleButtonTooltips context
             ]
                |> List.filterMap identity
                |> List.head
                |> Maybe.withDefault waitForProgressInGame
            )

    else
        case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> moduleIsActiveOrReloading >> not) |> List.head of
            Just ( inactiveModuleMatchingText, inactiveModule ) ->
                describeBranch ("I see inactive module '" ++ inactiveModuleMatchingText ++ "' to activate always. Activate it.")
                    (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)

            Nothing ->
                let
                    returnDronesAndEnterAnomaly { ifNoAcceptableAnomalyAvailable } =
                        returnDronesToBay context
                            |> Maybe.withDefault
                                (describeBranch "No drones to return."
                                    (enterAnomaly { ifNoAcceptableAnomalyAvailable = ifNoAcceptableAnomalyAvailable } context)
                                )

                    returnDronesAndEnterAnomalyOrWait =
                        returnDronesAndEnterAnomaly
                            { ifNoAcceptableAnomalyAvailable =
                                describeBranch "Wait for a matching anomaly to appear." waitForProgressInGame
                            }
                in
                case context.readingFromGameClient |> getCurrentAnomalyIDAsSeenInProbeScanner of
                    Nothing ->
                        describeBranch "Looks like we are not in an anomaly." returnDronesAndEnterAnomalyOrWait

                    Just anomalyID ->
                        case memoryOfAnomalyWithID anomalyID context.memory of
                            Nothing ->
                                describeBranch
                                    ("Program error: Did not find memory of anomaly " ++ anomalyID)
                                    waitForProgressInGame

                            Just memoryOfAnomaly ->
                                let
                                    arrivalInAnomalyAgeSeconds =
                                        (context.eventContext.timeInMilliseconds - memoryOfAnomaly.arrivalTime.milliseconds) // 1000
                                in
                                describeBranch ("We are in anomaly '" ++ anomalyID ++ "' since " ++ String.fromInt arrivalInAnomalyAgeSeconds ++ " seconds.")
                                    (case findReasonToAvoidAnomalyFromMemory context { anomalyID = anomalyID } of
                                        Just reasonToAvoidAnomaly ->
                                            describeBranch
                                                ("Found a reason to avoid this anomaly: "
                                                    ++ describeReasonToAvoidAnomaly reasonToAvoidAnomaly
                                                )
                                                (returnDronesAndEnterAnomaly
                                                    { ifNoAcceptableAnomalyAvailable =
                                                        describeBranch "Get out of this anomaly."
                                                            (dockAtRandomStationOrStructure context)
                                                    }
                                                )

                                        Nothing ->
                                            decideActionInAnomaly
                                                { arrivalInAnomalyAgeSeconds = arrivalInAnomalyAgeSeconds }
                                                context
                                                seeUndockingComplete
                                                returnDronesAndEnterAnomalyOrWait
                                    )


undockUsingStationWindow : BotDecisionContext -> DecisionPathNode
undockUsingStationWindow context =
    case context.readingFromGameClient.stationWindow of
        Nothing ->
            describeBranch "I do not see the station window." askForHelpToGetUnstuck

        Just stationWindow ->
            case stationWindow.undockButton of
                Nothing ->
                    case stationWindow.abortUndockButton of
                        Nothing ->
                            describeBranch "I do not see the undock button." askForHelpToGetUnstuck

                        Just _ ->
                            describeBranch "I see we are already undocking." waitForProgressInGame

                Just undockButton ->
                    describeBranch "Click on the button to undock."
                        (decideActionForCurrentStep
                            (mouseClickOnUIElement MouseButtonLeft undockButton)
                        )


decideActionInAnomaly :
    { arrivalInAnomalyAgeSeconds : Int }
    -> BotDecisionContext
    -> SeeUndockingComplete
    -> DecisionPathNode
    -> DecisionPathNode
decideActionInAnomaly { arrivalInAnomalyAgeSeconds } context seeUndockingComplete continueIfCombatComplete =
    let
        overviewEntriesToAttack =
            seeUndockingComplete.overviewWindows
                |> List.concatMap .entries
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

        waitTimeRemainingSeconds =
            context.eventContext.botSettings.anomalyWaitTimeSeconds - arrivalInAnomalyAgeSeconds

        decisionIfNoEnemyToAttack =
            if overviewEntriesToAttack |> List.isEmpty then
                if waitTimeRemainingSeconds <= 0 then
                    returnDronesToBay context
                        |> Maybe.withDefault
                            (describeBranch "No drones to return." continueIfCombatComplete)

                else
                    describeBranch
                        ("Wait before considering the anomaly finished: " ++ String.fromInt waitTimeRemainingSeconds ++ " seconds")
                        waitForProgressInGame

            else
                describeBranch "Wait for target locking to complete." waitForProgressInGame

        decisionToKillRats =
            case targetsToUnlock |> List.head of
                Just targetToUnlock ->
                    describeBranch "I see a target to unlock."
                        (useContextMenuCascade
                            ( "locked target", targetToUnlock.barAndImageCont |> Maybe.withDefault targetToUnlock.uiNode )
                            (useMenuEntryWithTextContaining "unlock" menuCascadeCompleted)
                            context
                        )

                Nothing ->
                    case context.readingFromGameClient.targets |> List.head of
                        Nothing ->
                            describeBranch "I see no locked target."
                                (case overviewEntriesToLock of
                                    [] ->
                                        describeBranch "I see no overview entry to lock."
                                            decisionIfNoEnemyToAttack

                                    nextOverviewEntryToLock :: _ ->
                                        describeBranch "I see an overview entry to lock."
                                            (lockTargetFromOverviewEntry
                                                nextOverviewEntryToLock
                                                context
                                            )
                                )

                        Just _ ->
                            describeBranch "I see a locked target."
                                (case seeUndockingComplete |> shipUIModulesToActivateOnTarget |> List.filter (.isActive >> Maybe.withDefault False >> not) |> List.head of
                                    Nothing ->
                                        describeBranch "All attack modules are active."
                                            (launchAndEngageDrones context
                                                |> Maybe.withDefault
                                                    (describeBranch "No idling drones."
                                                        (if context.eventContext.botSettings.maxTargetCount <= (context.readingFromGameClient.targets |> List.length) then
                                                            describeBranch "Enough locked targets." waitForProgressInGame

                                                         else
                                                            case overviewEntriesToLock of
                                                                [] ->
                                                                    describeBranch "I see no more overview entries to lock." waitForProgressInGame

                                                                nextOverviewEntryToLock :: _ ->
                                                                    describeBranch "Lock more targets."
                                                                        (lockTargetFromOverviewEntry
                                                                            nextOverviewEntryToLock
                                                                            context
                                                                        )
                                                        )
                                                    )
                                            )

                                    Just inactiveModule ->
                                        describeBranch "I see an inactive module to activate on targets. Activate it."
                                            (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)
                                )
    in
    if context.eventContext.botSettings.orbitInCombat == AppSettings.Yes then
        ensureShipIsOrbitingDecision |> Maybe.withDefault decisionToKillRats

    else
        decisionToKillRats


enterAnomaly : { ifNoAcceptableAnomalyAvailable : DecisionPathNode } -> BotDecisionContext -> DecisionPathNode
enterAnomaly { ifNoAcceptableAnomalyAvailable } context =
    case context.readingFromGameClient.probeScannerWindow of
        Nothing ->
            describeBranch "I do not see the probe scanner window." askForHelpToGetUnstuck

        Just probeScannerWindow ->
            let
                scanResultsWithReasonToIgnore =
                    probeScannerWindow.scanResults
                        |> List.map
                            (\scanResult ->
                                ( scanResult
                                , findReasonToIgnoreProbeScanResult context scanResult
                                )
                            )
            in
            case
                scanResultsWithReasonToIgnore
                    |> List.filter (Tuple.second >> (==) Nothing)
                    |> List.map Tuple.first
                    |> listElementAtWrappedIndex (context.randomIntegers |> List.head |> Maybe.withDefault 0)
            of
                Nothing ->
                    describeBranch
                        ("I see "
                            ++ (probeScannerWindow.scanResults |> List.length |> String.fromInt)
                            ++ " scan results, and no matching anomaly. Wait for a matching anomaly to appear."
                        )
                        ifNoAcceptableAnomalyAvailable

                Just anomalyScanResult ->
                    describeBranch "Warp to anomaly."
                        (useContextMenuCascade
                            ( "Scan result", anomalyScanResult.uiNode )
                            (useMenuEntryWithTextContaining "Warp to Within"
                                (useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted)
                            )
                            context
                        )


ensureShipIsOrbiting : ShipUI -> OverviewWindowEntry -> Maybe DecisionPathNode
ensureShipIsOrbiting shipUI overviewEntryToOrbit =
    if (shipUI.indication |> Maybe.andThen .maneuverType) == Just EveOnline.ParseUserInterface.ManeuverOrbit then
        Nothing

    else
        Just
            (describeBranch "Press the 'W' key and click on the overview entry."
                (decideActionForCurrentStep
                    ([ [ EffectOnWindow.KeyDown EffectOnWindow.vkey_W ]
                     , overviewEntryToOrbit.uiNode |> mouseClickOnUIElement MouseButtonLeft
                     , [ EffectOnWindow.KeyUp EffectOnWindow.vkey_W ]
                     ]
                        |> List.concat
                    )
                )
            )


launchAndEngageDrones : BotDecisionContext -> Maybe DecisionPathNode
launchAndEngageDrones context =
    context.readingFromGameClient.dronesWindow
        |> Maybe.andThen
            (\dronesWindow ->
                case ( dronesWindow.droneGroupInBay, dronesWindow.droneGroupInSpace ) of
                    ( Just droneGroupInBay, Just droneGroupInSpace ) ->
                        let
                            idlingDrones =
                                droneGroupInSpace
                                    |> EveOnline.ParseUserInterface.enumerateAllDronesFromDronesGroup
                                    |> List.filter
                                        (.uiNode
                                            >> .uiNode
                                            >> EveOnline.ParseUserInterface.getAllContainedDisplayTexts
                                            >> List.any (stringContainsIgnoringCase "idle")
                                        )

                            dronesInBayQuantity =
                                droneGroupInBay.header.quantityFromTitle
                                    |> Maybe.map .current
                                    |> Maybe.withDefault 0

                            dronesInSpaceQuantityCurrent =
                                droneGroupInSpace.header.quantityFromTitle
                                    |> Maybe.map .current
                                    |> Maybe.withDefault 0

                            dronesInSpaceQuantityLimit =
                                droneGroupInSpace.header.quantityFromTitle
                                    |> Maybe.andThen .maximum
                                    |> Maybe.withDefault 2
                        in
                        if 0 < (idlingDrones |> List.length) then
                            Just
                                (describeBranch "Engage idling drone(s)"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInSpace.header.uiNode )
                                        (useMenuEntryWithTextContaining "engage target" menuCascadeCompleted)
                                        context
                                    )
                                )

                        else if 0 < dronesInBayQuantity && dronesInSpaceQuantityCurrent < dronesInSpaceQuantityLimit then
                            Just
                                (describeBranch "Launch drones"
                                    (useContextMenuCascade
                                        ( "drones group", droneGroupInBay.header.uiNode )
                                        (useMenuEntryWithTextContaining "Launch drone" menuCascadeCompleted)
                                        context
                                    )
                                )

                        else
                            Nothing

                    _ ->
                        Nothing
            )


returnDronesToBay : BotDecisionContext -> Maybe DecisionPathNode
returnDronesToBay context =
    context.readingFromGameClient.dronesWindow
        |> Maybe.andThen .droneGroupInSpace
        |> Maybe.andThen
            (\droneGroupInLocalSpace ->
                if
                    (droneGroupInLocalSpace.header.quantityFromTitle
                        |> Maybe.map .current
                        |> Maybe.withDefault 0
                    )
                        < 1
                then
                    Nothing

                else
                    Just
                        (describeBranch "I see there are drones in space. Return those to bay."
                            (useContextMenuCascade
                                ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                (useMenuEntryWithTextContaining "Return to drone bay" menuCascadeCompleted)
                                context
                            )
                        )
            )


lockTargetFromOverviewEntry : OverviewWindowEntry -> BotDecisionContext -> DecisionPathNode
lockTargetFromOverviewEntry overviewEntry context =
    describeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
        (useContextMenuCascadeOnOverviewEntry
            (useMenuEntryWithTextEqual "Lock target" menuCascadeCompleted)
            overviewEntry
            context
        )


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.BotFrameworkSeparatingMemory.readShipUIModuleButtonTooltipWhereNotYetInMemory


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filterMap
            (\moduleButton ->
                moduleButton
                    |> EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                    |> Maybe.andThen (tooltipLooksLikeModuleToActivateAlways context)
                    |> Maybe.map (\moduleName -> ( moduleName, moduleButton ))
            )


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> ModuleButtonTooltipMemory -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .allContainedDisplayTextsWithRegion
        >> List.filterMap
            (\( tooltipText, _ ) ->
                context.eventContext.botSettings.activateModulesAlways
                    |> List.filterMap
                        (\moduleToActivateAlways ->
                            if tooltipText |> stringContainsIgnoringCase moduleToActivateAlways then
                                Just tooltipText

                            else
                                Nothing
                        )
                    |> List.head
            )
        >> List.head


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , statusTextFromDecisionContext = statusTextFromState
            , decideNextStep = anomalyBotDecisionRoot
            }
    }


initBotMemory : BotMemory
initBotMemory =
    { lastDockedStationNameFromInfoPanel = Nothing
    , shipModules = EveOnline.BotFramework.initShipModulesMemory
    , shipWarpingInLastReading = Nothing
    , visitedAnomalies = Dict.empty
    }


statusTextFromState : BotDecisionContext -> String
statusTextFromState context =
    let
        readingFromGameClient =
            context.readingFromGameClient

        describePerformance =
            "Visited anomalies: " ++ (context.memory.visitedAnomalies |> Dict.size |> String.fromInt) ++ "."

        describeCurrentReading =
            case readingFromGameClient.shipUI of
                Nothing ->
                    [ "I do not see the ship UI. Looks like we are docked." ]

                Just shipUI ->
                    let
                        describeShip =
                            "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."

                        describeDrones =
                            case readingFromGameClient.dronesWindow of
                                Nothing ->
                                    "I do not see the drones window."

                                Just dronesWindow ->
                                    "I see the drones window: In bay: "
                                        ++ (dronesWindow.droneGroupInBay
                                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                                |> Maybe.map (.current >> String.fromInt)
                                                |> Maybe.withDefault "Unknown"
                                           )
                                        ++ ", in space: "
                                        ++ (dronesWindow.droneGroupInSpace
                                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                                |> Maybe.map (.current >> String.fromInt)
                                                |> Maybe.withDefault "Unknown"
                                           )
                                        ++ "."

                        namesOfOtherPilotsInOverview =
                            getNamesOfOtherPilotsInOverview readingFromGameClient

                        describeAnomaly =
                            "Current anomaly: "
                                ++ (getCurrentAnomalyIDAsSeenInProbeScanner readingFromGameClient |> Maybe.withDefault "None")
                                ++ "."

                        describeOverview =
                            ("Seeing "
                                ++ (namesOfOtherPilotsInOverview |> List.length |> String.fromInt)
                                ++ " other pilots in the overview"
                            )
                                ++ (if namesOfOtherPilotsInOverview == [] then
                                        ""

                                    else
                                        ": " ++ (namesOfOtherPilotsInOverview |> String.join ", ")
                                   )
                                ++ "."
                    in
                    [ [ describeShip ]
                    , [ describeDrones ]
                    , [ describeAnomaly, describeOverview ]
                    ]
                        |> List.map (String.join " ")
    in
    [ [ describePerformance ]
    , describeCurrentReading
    ]
        |> List.concat
        |> String.join "\n"


clickModuleButtonButWaitIfClickedInPreviousStep : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUIModuleButton -> DecisionPathNode
clickModuleButtonButWaitIfClickedInPreviousStep context moduleButton =
    if doEffectsClickModuleButton moduleButton context.previousStepEffects then
        describeBranch "Already clicked on this module button in previous step." waitForProgressInGame

    else
        describeBranch "Click on this module button."
            (decideActionForCurrentStep
                (mouseClickOnUIElement MouseButtonLeft moduleButton.uiNode)
            )


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


moduleIsActiveOrReloading : EveOnline.ParseUserInterface.ShipUIModuleButton -> Bool
moduleIsActiveOrReloading moduleButton =
    (moduleButton.isActive |> Maybe.withDefault False)
        || ((moduleButton.rampRotationMilli |> Maybe.withDefault 0) /= 0)


iconSpriteHasColorOfRat : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
iconSpriteHasColorOfRat =
    .iconSpriteColorPercent
        >> Maybe.map
            (\colorPercent ->
                colorPercent.g * 3 < colorPercent.r && colorPercent.b * 3 < colorPercent.r && 60 < colorPercent.r && 50 < colorPercent.a
            )
        >> Maybe.withDefault False


updateMemoryForNewReadingFromGame : UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =
    let
        currentStationNameFromInfoPanel =
            context.readingFromGameClient.infoPanelContainer
                |> Maybe.andThen .infoPanelLocationInfo
                |> Maybe.andThen .expandedContent
                |> Maybe.andThen .currentStationName

        shipIsWarping =
            context.readingFromGameClient.shipUI
                |> Maybe.andThen .indication
                |> Maybe.andThen .maneuverType
                |> Maybe.map ((==) EveOnline.ParseUserInterface.ManeuverWarp)

        namesOfRatsInOverview =
            getNamesOfRatsInOverview context.readingFromGameClient

        weJustFinishedWarping =
            (botMemoryBefore.shipWarpingInLastReading == Just True) && (shipIsWarping == Just False)

        visitedAnomalies =
            if shipIsWarping == Just True then
                botMemoryBefore.visitedAnomalies

            else
                case context.readingFromGameClient |> getCurrentAnomalyIDAsSeenInProbeScanner of
                    Nothing ->
                        botMemoryBefore.visitedAnomalies

                    Just currentAnomalyID ->
                        let
                            anomalyMemoryBefore =
                                botMemoryBefore.visitedAnomalies
                                    |> Dict.get currentAnomalyID
                                    |> Maybe.withDefault
                                        { arrivalTime = { milliseconds = context.timeInMilliseconds }
                                        , otherPilotsFoundOnArrival = []
                                        , ratsSeen = Set.empty
                                        }

                            anomalyMemoryWithOtherPilotsOnArrival =
                                if weJustFinishedWarping then
                                    { anomalyMemoryBefore
                                        | otherPilotsFoundOnArrival = getNamesOfOtherPilotsInOverview context.readingFromGameClient
                                    }

                                else
                                    anomalyMemoryBefore

                            anomalyMemory =
                                { anomalyMemoryWithOtherPilotsOnArrival
                                    | ratsSeen =
                                        Set.union anomalyMemoryBefore.ratsSeen (Set.fromList namesOfRatsInOverview)
                                }
                        in
                        botMemoryBefore.visitedAnomalies |> Dict.insert currentAnomalyID anomalyMemory
    in
    { lastDockedStationNameFromInfoPanel =
        [ currentStationNameFromInfoPanel, botMemoryBefore.lastDockedStationNameFromInfoPanel ]
            |> List.filterMap identity
            |> List.head
    , shipModules =
        botMemoryBefore.shipModules
            |> EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory context.readingFromGameClient
    , shipWarpingInLastReading = shipIsWarping
    , visitedAnomalies = visitedAnomalies
    }


getCurrentAnomalyIDAsSeenInProbeScanner : ReadingFromGameClient -> Maybe String
getCurrentAnomalyIDAsSeenInProbeScanner =
    .probeScannerWindow
        >> Maybe.map getScanResultsForSitesOnGrid
        >> Maybe.withDefault []
        >> List.head
        >> Maybe.andThen (.cellsTexts >> Dict.get "ID")


getScanResultsForSitesOnGrid : EveOnline.ParseUserInterface.ProbeScannerWindow -> List EveOnline.ParseUserInterface.ProbeScanResult
getScanResultsForSitesOnGrid probeScannerWindow =
    probeScannerWindow.scanResults
        |> List.filter (scanResultLooksLikeItIsOnGrid >> Maybe.withDefault False)


scanResultLooksLikeItIsOnGrid : EveOnline.ParseUserInterface.ProbeScanResult -> Maybe Bool
scanResultLooksLikeItIsOnGrid =
    .cellsTexts
        >> Dict.get "Distance"
        >> Maybe.map (\text -> (text |> String.contains " m") || (text |> String.contains " km"))


getNamesOfOtherPilotsInOverview : ReadingFromGameClient -> List String
getNamesOfOtherPilotsInOverview readingFromGameClient =
    let
        pilotNamesFromLocalChat =
            readingFromGameClient
                |> localChatWindowFromUserInterface
                |> Maybe.andThen .userlist
                |> Maybe.map .visibleUsers
                |> Maybe.withDefault []
                |> List.filterMap .name

        overviewEntryRepresentsOtherPilot overviewEntry =
            (overviewEntry.objectName |> Maybe.map (\objectName -> pilotNamesFromLocalChat |> List.member objectName))
                |> Maybe.withDefault False
    in
    readingFromGameClient.overviewWindows
        |> List.concatMap .entries
        |> List.filter overviewEntryRepresentsOtherPilot
        |> List.map (.objectName >> Maybe.withDefault "do not see name of overview entry")


getNamesOfRatsInOverview : ReadingFromGameClient -> List String
getNamesOfRatsInOverview readingFromGameClient =
    let
        overviewEntryRepresentsRatOnGrid overviewEntry =
            iconSpriteHasColorOfRat overviewEntry
                && (overviewEntry.objectDistanceInMeters
                        |> Result.map (\distanceInMeters -> distanceInMeters < 300000)
                        |> Result.withDefault False
                   )
    in
    readingFromGameClient.overviewWindows
        |> List.concatMap .entries
        |> List.filter overviewEntryRepresentsRatOnGrid
        |> List.map (.objectName >> Maybe.withDefault "do not see name of overview entry")


shipUIModulesToActivateOnTarget : SeeUndockingComplete -> List ShipUIModuleButton
shipUIModulesToActivateOnTarget =
    .shipUI >> .moduleButtonsRows >> .top


nothingFromIntIfGreaterThan : Int -> Int -> Maybe Int
nothingFromIntIfGreaterThan limit originalInt =
    if limit < originalInt then
        Nothing

    else
        Just originalInt

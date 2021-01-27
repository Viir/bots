module EveOnline.AppFrameworkSeparatingMemory exposing (..)

import BotEngine.Interface_To_Host_20201207 as InterfaceToHost
import Common.DecisionPath
import Common.EffectOnWindow
import EveOnline.AppFramework
    exposing
        ( ReadingFromGameClient
        , SeeUndockingComplete
        , ShipModulesMemory
        , UIElement
        , UseContextMenuCascadeNode
        , clickOnUIElement
        , cornersFromDisplayRegion
        , doesPointIntersectRegion
        , getModuleButtonTooltipFromModuleButton
        , growRegionOnAllSides
        , subtractRegionsFromRegion
        , unpackContextMenuTreeToListOfActionsDependingOnReadings
        )
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion)


type EndDecisionPathStructure
    = ContinueSession ContinueSessionStructure
    | FinishSession


type alias ContinueSessionStructure =
    { effectsOnGameClient : List Common.EffectOnWindow.EffectOnWindowStructure
    , millisecondsToNextReadingFromGameBase : Maybe Int
    , millisecondsToNextReadingFromGameModifierPercent : Int
    }


type alias DecisionPathNode =
    Common.DecisionPath.DecisionPathNode EndDecisionPathStructure


type alias UpdateMemoryContext =
    { timeInMilliseconds : Int
    , readingFromGameClient : ReadingFromGameClient
    }


type alias StepDecisionContext appSettings appMemory =
    { eventContext : EveOnline.AppFramework.AppEventContext appSettings
    , readingFromGameClient : ReadingFromGameClient
    , memory : appMemory
    , previousStepEffects : List Common.EffectOnWindow.EffectOnWindowStructure
    , previousReadingFromGameClient : Maybe ReadingFromGameClient
    }


type alias AppState appMemory =
    { appMemory : appMemory
    , lastStepEffects : List Common.EffectOnWindow.EffectOnWindowStructure
    , lastReadingFromGameClient : Maybe ReadingFromGameClient
    }


millisecondsToNextReadingFromGameDefault : Int
millisecondsToNextReadingFromGameDefault =
    1500


initState : appMemory -> EveOnline.AppFramework.StateIncludingFramework appSettings (AppState appMemory)
initState appMemory =
    EveOnline.AppFramework.initState (initStateInBaseFramework appMemory)


initStateInBaseFramework : appMemory -> AppState appMemory
initStateInBaseFramework appMemory =
    { appMemory = appMemory
    , lastStepEffects = []
    , lastReadingFromGameClient = Nothing
    }


processEvent :
    { parseAppSettings : String -> Result String appSettings
    , selectGameClientInstance : Maybe appSettings -> List EveOnline.AppFramework.GameClientProcessSummary -> Result String { selectedProcess : EveOnline.AppFramework.GameClientProcessSummary, report : List String }
    , updateMemoryForNewReadingFromGame : UpdateMemoryContext -> appMemory -> appMemory
    , statusTextFromDecisionContext : StepDecisionContext appSettings appMemory -> String
    , decideNextStep : StepDecisionContext appSettings appMemory -> DecisionPathNode
    }
    -> InterfaceToHost.AppEvent
    -> EveOnline.AppFramework.StateIncludingFramework appSettings (AppState appMemory)
    -> ( EveOnline.AppFramework.StateIncludingFramework appSettings (AppState appMemory), InterfaceToHost.AppResponse )
processEvent appConfiguration =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = appConfiguration.parseAppSettings
        , selectGameClientInstance = appConfiguration.selectGameClientInstance
        , processEvent =
            processEventInBaseFramework
                { updateMemoryForNewReadingFromGame = appConfiguration.updateMemoryForNewReadingFromGame
                , statusTextFromDecisionContext = appConfiguration.statusTextFromDecisionContext
                , decideNextStep = appConfiguration.decideNextStep
                }
        }


processEventInBaseFramework :
    { updateMemoryForNewReadingFromGame : UpdateMemoryContext -> appMemory -> appMemory
    , statusTextFromDecisionContext : StepDecisionContext appSettings appMemory -> String
    , decideNextStep : StepDecisionContext appSettings appMemory -> DecisionPathNode
    }
    -> EveOnline.AppFramework.AppEventContext appSettings
    -> EveOnline.AppFramework.AppEvent
    -> AppState appMemory
    -> ( AppState appMemory, EveOnline.AppFramework.AppEventResponse )
processEventInBaseFramework config eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            let
                updateMemoryContext =
                    { timeInMilliseconds = eventContext.timeInMilliseconds
                    , readingFromGameClient = readingFromGameClient
                    }

                appMemory =
                    stateBefore.appMemory
                        |> config.updateMemoryForNewReadingFromGame updateMemoryContext

                decisionContext =
                    { eventContext = eventContext
                    , memory = appMemory
                    , readingFromGameClient = readingFromGameClient
                    , previousStepEffects = stateBefore.lastStepEffects
                    , previousReadingFromGameClient = stateBefore.lastReadingFromGameClient
                    }

                ( decisionStagesDescriptions, decisionLeaf ) =
                    config.decideNextStep decisionContext
                        |> Common.DecisionPath.unpackToDecisionStagesDescriptionsAndLeaf

                effectsOnGameClientWindow =
                    case decisionLeaf of
                        ContinueSession act ->
                            act.effectsOnGameClient

                        FinishSession ->
                            []

                effectsRequests =
                    if effectsOnGameClientWindow == [] then
                        []

                    else
                        [ effectsOnGameClientWindow |> EveOnline.AppFramework.EffectSequenceOnGameClientWindow ]

                describeActivity =
                    decisionStagesDescriptions
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"

                statusMessage =
                    [ config.statusTextFromDecisionContext decisionContext, describeActivity ]
                        |> String.join "\n"
            in
            ( { appMemory = appMemory
              , lastStepEffects = effectsOnGameClientWindow
              , lastReadingFromGameClient = Just readingFromGameClient
              }
            , case decisionLeaf of
                ContinueSession continueSession ->
                    let
                        millisecondsToNextReadingFromGame =
                            ((continueSession.millisecondsToNextReadingFromGameModifierPercent + 100)
                                * (continueSession.millisecondsToNextReadingFromGameBase
                                    |> Maybe.withDefault millisecondsToNextReadingFromGameDefault
                                  )
                            )
                                // 100
                    in
                    EveOnline.AppFramework.ContinueSession
                        { effects = effectsRequests
                        , millisecondsToNextReadingFromGame = millisecondsToNextReadingFromGame
                        , statusDescriptionText = statusMessage
                        }

                FinishSession ->
                    EveOnline.AppFramework.FinishSession { statusDescriptionText = statusMessage }
            )


useContextMenuCascadeOnOverviewEntry :
    UseContextMenuCascadeNode
    -> EveOnline.ParseUserInterface.OverviewWindowEntry
    -> StepDecisionContext a b
    -> DecisionPathNode
useContextMenuCascadeOnOverviewEntry useContextMenu overviewEntry context =
    useContextMenuCascade
        ( "overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'", overviewEntry.uiNode )
        useContextMenu
        context


useContextMenuCascadeOnListSurroundingsButton :
    UseContextMenuCascadeNode
    -> StepDecisionContext a b
    -> DecisionPathNode
useContextMenuCascadeOnListSurroundingsButton useContextMenu context =
    case context.readingFromGameClient.infoPanelContainer |> Maybe.andThen .infoPanelLocationInfo of
        Nothing ->
            Common.DecisionPath.describeBranch "I do not see the location info panel." askForHelpToGetUnstuck

        Just infoPanelLocationInfo ->
            useContextMenuCascade
                ( "surroundings button", infoPanelLocationInfo.listSurroundingsButton )
                useContextMenu
                context


useContextMenuCascade :
    ( String, UIElement )
    -> UseContextMenuCascadeNode
    -> StepDecisionContext a b
    -> DecisionPathNode
useContextMenuCascade ( initialUIElementName, initialUIElement ) useContextMenu context =
    let
        readingFromGameClient =
            context.readingFromGameClient

        beginCascade =
            let
                occludingRegionsWithSafetyMargin =
                    readingFromGameClient.contextMenus
                        |> List.map (.uiNode >> .totalDisplayRegion >> growRegionOnAllSides 2)

                regionsRemainingAfterOcclusion =
                    subtractRegionsFromRegion
                        { minuend = initialUIElement.totalDisplayRegion, subtrahend = occludingRegionsWithSafetyMargin }
            in
            case
                regionsRemainingAfterOcclusion
                    |> List.filter (\region -> 3 < region.width && 3 < region.height)
                    |> List.sortBy (\region -> negate (min region.width region.height))
                    |> List.head
            of
                Nothing ->
                    Common.DecisionPath.describeBranch
                        ("All of " ++ initialUIElementName ++ " is occluded by context menus.")
                        (Common.DecisionPath.describeBranch
                            "Click somewhere else to get rid of the occluding elements."
                            ({ x = 4, y = 4 }
                                |> Common.EffectOnWindow.effectsMouseClickAtLocation Common.EffectOnWindow.MouseButtonRight
                                |> decideActionForCurrentStep
                            )
                        )

                Just preferredRegion ->
                    Common.DecisionPath.describeBranch
                        ("Open context menu on " ++ initialUIElementName)
                        (preferredRegion
                            |> centerFromDisplayRegion
                            |> Common.EffectOnWindow.effectsMouseClickAtLocation Common.EffectOnWindow.MouseButtonRight
                            |> decideActionForCurrentStep
                        )
    in
    case context.previousReadingFromGameClient of
        Nothing ->
            beginCascade

        Just previousReadingFromGameClient ->
            case List.reverse context.readingFromGameClient.contextMenus of
                [] ->
                    beginCascade

                cascadeFirstElement :: cascadeFollowingElements ->
                    if
                        cornersFromDisplayRegion cascadeFirstElement.uiNode.totalDisplayRegion
                            |> List.any
                                (\corner ->
                                    doesPointIntersectRegion corner
                                        (initialUIElement.totalDisplayRegion |> growRegionOnAllSides 10)
                                )
                            |> not
                    then
                        beginCascade

                    else if
                        (0 < List.length cascadeFollowingElements)
                            && (List.length context.readingFromGameClient.contextMenus
                                    <= List.length previousReadingFromGameClient.contextMenus
                               )
                    then
                        beginCascade

                    else
                        case
                            useContextMenu
                                |> unpackContextMenuTreeToListOfActionsDependingOnReadings
                                |> List.drop (List.length cascadeFollowingElements)
                                |> List.head
                        of
                            Nothing ->
                                beginCascade

                            Just ( stepDescription, actionFromReading ) ->
                                Common.DecisionPath.describeBranch stepDescription
                                    (case actionFromReading context.readingFromGameClient of
                                        Nothing ->
                                            Common.DecisionPath.describeBranch "Failed step."
                                                askForHelpToGetUnstuck

                                        Just effectsToGameClient ->
                                            decideActionForCurrentStep effectsToGameClient
                                    )


ensureInfoPanelLocationInfoIsExpanded : ReadingFromGameClient -> Maybe DecisionPathNode
ensureInfoPanelLocationInfoIsExpanded readingFromGameClient =
    case readingFromGameClient.infoPanelContainer |> Maybe.andThen .infoPanelLocationInfo of
        Nothing ->
            Just
                (Common.DecisionPath.describeBranch "I do not see the location info panel. Enable the info panel."
                    (case readingFromGameClient.infoPanelContainer |> Maybe.andThen .icons |> Maybe.andThen .locationInfo of
                        Nothing ->
                            Common.DecisionPath.describeBranch "I do not see the icon for the location info panel." askForHelpToGetUnstuck

                        Just iconLocationInfoPanel ->
                            Common.DecisionPath.describeBranch
                                "Click on the icon to enable the info panel."
                                (iconLocationInfoPanel
                                    |> clickOnUIElement Common.EffectOnWindow.MouseButtonLeft
                                    |> decideActionForCurrentStep
                                )
                    )
                )

        Just infoPanelLocationInfo ->
            if 35 < infoPanelLocationInfo.uiNode.totalDisplayRegion.height then
                Nothing

            else
                Just
                    (Common.DecisionPath.describeBranch "Location info panel seems collapsed."
                        (Common.DecisionPath.describeBranch "Click to expand the info panel."
                            ({ x = infoPanelLocationInfo.uiNode.totalDisplayRegion.x + 8
                             , y = infoPanelLocationInfo.uiNode.totalDisplayRegion.y + 8
                             }
                                |> Common.EffectOnWindow.effectsMouseClickAtLocation
                                    Common.EffectOnWindow.MouseButtonLeft
                                |> decideActionForCurrentStep
                            )
                        )
                    )


branchDependingOnDockedOrInSpace :
    { ifDocked : DecisionPathNode
    , ifSeeShipUI : EveOnline.ParseUserInterface.ShipUI -> Maybe DecisionPathNode
    , ifUndockingComplete : SeeUndockingComplete -> DecisionPathNode
    }
    -> ReadingFromGameClient
    -> DecisionPathNode
branchDependingOnDockedOrInSpace { ifDocked, ifSeeShipUI, ifUndockingComplete } readingFromGameClient =
    case readingFromGameClient.shipUI of
        Nothing ->
            Common.DecisionPath.describeBranch "I see no ship UI, assume we are docked." ifDocked

        Just shipUI ->
            ifSeeShipUI shipUI
                |> Maybe.withDefault
                    (case readingFromGameClient.overviewWindow of
                        Nothing ->
                            Common.DecisionPath.describeBranch
                                "I see no overview window, wait until undocking completed."
                                waitForProgressInGame

                        Just overviewWindow ->
                            Common.DecisionPath.describeBranch "I see ship UI and overview, undocking complete."
                                (ifUndockingComplete
                                    { shipUI = shipUI, overviewWindow = overviewWindow }
                                )
                    )


waitForProgressInGame : DecisionPathNode
waitForProgressInGame =
    Common.DecisionPath.describeBranch "Wait for progress in game"
        (decideActionForCurrentStep [])
        |> updateMillisecondsToNextReadingFromGameModifierPercent (always 100)


askForHelpToGetUnstuck : DecisionPathNode
askForHelpToGetUnstuck =
    Common.DecisionPath.describeBranch "I am stuck here and need help to continue."
        (decideActionForCurrentStep [])
        |> updateMillisecondsToNextReadingFromGameModifierPercent (always 100)


readShipUIModuleButtonTooltipWhereNotYetInMemory :
    { a
        | readingFromGameClient : ReadingFromGameClient
        , memory : { b | shipModules : ShipModulesMemory }
    }
    -> Maybe DecisionPathNode
readShipUIModuleButtonTooltipWhereNotYetInMemory context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filter (getModuleButtonTooltipFromModuleButton context.memory.shipModules >> (==) Nothing)
        |> List.head
        |> Maybe.map
            (\moduleButtonWithoutMemoryOfTooltip ->
                Common.DecisionPath.describeBranch "Read tooltip for module button"
                    (decideActionForCurrentStep
                        [ Common.EffectOnWindow.MouseMoveTo
                            (moduleButtonWithoutMemoryOfTooltip.uiNode.totalDisplayRegion |> centerFromDisplayRegion)
                        ]
                    )
            )


updateMillisecondsToNextReadingFromGameModifierPercent : (Int -> Int) -> DecisionPathNode -> DecisionPathNode
updateMillisecondsToNextReadingFromGameModifierPercent update decisionPath =
    updateDecisionPathEndContinueSession
        (\continueSession ->
            { continueSession
                | millisecondsToNextReadingFromGameModifierPercent =
                    update continueSession.millisecondsToNextReadingFromGameModifierPercent
            }
        )
        decisionPath


setMillisecondsToNextReadingFromGameBase : Int -> DecisionPathNode -> DecisionPathNode
setMillisecondsToNextReadingFromGameBase millisecondsToNextReadingFromGameBase decisionPath =
    updateDecisionPathEndContinueSession
        (\continueSession ->
            { continueSession | millisecondsToNextReadingFromGameBase = Just millisecondsToNextReadingFromGameBase }
        )
        decisionPath


updateDecisionPathEndContinueSession : (ContinueSessionStructure -> ContinueSessionStructure) -> DecisionPathNode -> DecisionPathNode
updateDecisionPathEndContinueSession updateContinueSession decisionPath =
    Common.DecisionPath.continueDecisionPath
        (\pathEnd ->
            Common.DecisionPath.endDecisionPath
                (case pathEnd of
                    ContinueSession continueSession ->
                        ContinueSession (updateContinueSession continueSession)

                    FinishSession ->
                        pathEnd
                )
        )
        decisionPath


decideActionForCurrentStep : List Common.EffectOnWindow.EffectOnWindowStructure -> DecisionPathNode
decideActionForCurrentStep effects =
    Common.DecisionPath.endDecisionPath
        (ContinueSession
            { effectsOnGameClient = effects
            , millisecondsToNextReadingFromGameBase = Nothing
            , millisecondsToNextReadingFromGameModifierPercent = 0
            }
        )


{-| 2021-01-27:
The notifications functionality is currently work-in-progress.
For now, this wrapper helps app developers use the same API as is currently expected for the built-in notifications functionality.

One design goal is to support users customizing notifications quickly and independently of the app program code.
To achieve this goal, we let users work with the data they are already familiar with: The status text can be seen during a live run and is also prominently displayed when inspecting a session in the devtools. Using the status text as the data source also ensures users can easily reuse their notification rules with any app.

-}
processEventWithNotificationsShim :
    { parseAppSettings : String -> Result String appSettings
    , selectGameClientInstance : Maybe appSettings -> List EveOnline.AppFramework.GameClientProcessSummary -> Result String { selectedProcess : EveOnline.AppFramework.GameClientProcessSummary, report : List String }
    , updateMemoryForNewReadingFromGame : UpdateMemoryContext -> appMemory -> appMemory
    , statusTextFromDecisionContext : StepDecisionContext appSettings appMemory -> String
    , decideNextStep : StepDecisionContext appSettings appMemory -> DecisionPathNode
    , notificationsBeepSequenceFromStatusText : String -> List EveOnline.AppFramework.ConsoleBeepStructure
    }
    -> InterfaceToHost.AppEvent
    -> EveOnline.AppFramework.StateIncludingFramework appSettings (AppState appMemory)
    -> ( EveOnline.AppFramework.StateIncludingFramework appSettings (AppState appMemory), InterfaceToHost.AppResponse )
processEventWithNotificationsShim appConfiguration =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = appConfiguration.parseAppSettings
        , selectGameClientInstance = appConfiguration.selectGameClientInstance
        , processEvent =
            \eventContext event stateBefore ->
                let
                    ( state, responseBeforeNotifications ) =
                        processEventInBaseFramework
                            { updateMemoryForNewReadingFromGame = appConfiguration.updateMemoryForNewReadingFromGame
                            , statusTextFromDecisionContext = appConfiguration.statusTextFromDecisionContext
                            , decideNextStep = appConfiguration.decideNextStep
                            }
                            eventContext
                            event
                            stateBefore

                    response =
                        case responseBeforeNotifications of
                            EveOnline.AppFramework.ContinueSession continueSession ->
                                let
                                    beepSequence =
                                        appConfiguration.notificationsBeepSequenceFromStatusText continueSession.statusDescriptionText

                                    beepEffects =
                                        if beepSequence == [] then
                                            []

                                        else
                                            [ EveOnline.AppFramework.EffectConsoleBeepSequence beepSequence ]

                                    statusTextNotificationsLine =
                                        "notifications-shim: " ++ String.fromInt (List.length beepSequence) ++ " beeps."
                                in
                                EveOnline.AppFramework.ContinueSession
                                    { continueSession
                                        | effects =
                                            continueSession.effects ++ beepEffects
                                        , statusDescriptionText =
                                            String.join "\n" [ continueSession.statusDescriptionText, statusTextNotificationsLine ]
                                    }

                            EveOnline.AppFramework.FinishSession _ ->
                                responseBeforeNotifications
                in
                ( state, response )
        }

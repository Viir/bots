module EveOnline.AppFrameworkSeparatingMemory exposing (..)

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
    = ContinueSession ( String, List Common.EffectOnWindow.EffectOnWindowStructure )
    | FinishSession


type alias DecisionPathNode =
    Common.DecisionPath.DecisionPathNode EndDecisionPathStructure


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


initAppState : appMemory -> AppState appMemory
initAppState appMemory =
    { appMemory = appMemory
    , lastStepEffects = []
    , lastReadingFromGameClient = Nothing
    }


processEveOnlineAppEvent :
    { updateMemoryForNewReadingFromGame : EveOnline.AppFramework.AppEventContext appSettings -> ReadingFromGameClient -> appMemory -> appMemory
    , statusTextFromState : StepDecisionContext appSettings appMemory -> String
    , decideNextAction : StepDecisionContext appSettings appMemory -> DecisionPathNode
    , millisecondsToNextReadingFromGame : StepDecisionContext appSettings appMemory -> Int
    }
    -> EveOnline.AppFramework.AppEventContext appSettings
    -> EveOnline.AppFramework.AppEvent
    -> AppState appMemory
    -> ( AppState appMemory, EveOnline.AppFramework.AppEventResponse )
processEveOnlineAppEvent config eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            let
                appMemory =
                    stateBefore.appMemory
                        |> config.updateMemoryForNewReadingFromGame eventContext readingFromGameClient

                decisionContext =
                    { eventContext = eventContext
                    , memory = appMemory
                    , readingFromGameClient = readingFromGameClient
                    , previousStepEffects = stateBefore.lastStepEffects
                    , previousReadingFromGameClient = stateBefore.lastReadingFromGameClient
                    }

                ( decisionStagesDescriptions, decisionLeaf ) =
                    config.decideNextAction decisionContext
                        |> Common.DecisionPath.unpackToDecisionStagesDescriptionsAndLeaf

                ( currentStepDescription, effectsOnGameClientWindow ) =
                    case decisionLeaf of
                        ContinueSession act ->
                            act

                        FinishSession ->
                            ( "Finish session", [] )

                effectsRequests =
                    if effectsOnGameClientWindow == [] then
                        []

                    else
                        [ effectsOnGameClientWindow |> EveOnline.AppFramework.EffectSequenceOnGameClientWindow ]

                describeActivity =
                    (decisionStagesDescriptions ++ [ currentStepDescription ])
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"

                statusMessage =
                    [ config.statusTextFromState decisionContext, describeActivity ]
                        |> String.join "\n"
            in
            ( { appMemory = appMemory
              , lastStepEffects = effectsOnGameClientWindow
              , lastReadingFromGameClient = Just readingFromGameClient
              }
            , if decisionLeaf == FinishSession then
                EveOnline.AppFramework.FinishSession { statusDescriptionText = statusMessage }

              else
                EveOnline.AppFramework.ContinueSession
                    { effects = effectsRequests
                    , millisecondsToNextReadingFromGame = config.millisecondsToNextReadingFromGame decisionContext
                    , statusDescriptionText = statusMessage
                    }
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
                        ("All of "
                            ++ initialUIElementName
                            ++ " is occluded by context menus."
                        )
                        (Common.DecisionPath.endDecisionPath
                            (ContinueSession
                                ( "Click somewhere else to get rid of the occluding elements."
                                , Common.EffectOnWindow.effectsMouseClickAtLocation Common.EffectOnWindow.MouseButtonRight { x = 4, y = 4 }
                                )
                            )
                        )

                Just preferredRegion ->
                    ( "Open context menu on " ++ initialUIElementName
                    , preferredRegion
                        |> centerFromDisplayRegion
                        |> Common.EffectOnWindow.effectsMouseClickAtLocation Common.EffectOnWindow.MouseButtonRight
                    )
                        |> ContinueSession
                        |> Common.DecisionPath.endDecisionPath
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
                                case actionFromReading context.readingFromGameClient of
                                    Nothing ->
                                        Common.DecisionPath.describeBranch
                                            ("Failed step: " ++ stepDescription)
                                            askForHelpToGetUnstuck

                                    Just effectsToGameClient ->
                                        ( stepDescription
                                        , effectsToGameClient
                                        )
                                            |> ContinueSession
                                            |> Common.DecisionPath.endDecisionPath


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
                            Common.DecisionPath.endDecisionPath
                                (ContinueSession
                                    ( "Click on the icon to enable the info panel."
                                    , iconLocationInfoPanel |> clickOnUIElement Common.EffectOnWindow.MouseButtonLeft
                                    )
                                )
                    )
                )

        Just infoPanelLocationInfo ->
            if 35 < infoPanelLocationInfo.uiNode.totalDisplayRegion.height then
                Nothing

            else
                Just
                    (Common.DecisionPath.describeBranch "Location info panel seems collapsed."
                        (Common.DecisionPath.endDecisionPath
                            (ContinueSession
                                ( "Click to expand the info panel."
                                , Common.EffectOnWindow.effectsMouseClickAtLocation
                                    Common.EffectOnWindow.MouseButtonLeft
                                    { x = infoPanelLocationInfo.uiNode.totalDisplayRegion.x + 8
                                    , y = infoPanelLocationInfo.uiNode.totalDisplayRegion.y + 8
                                    }
                                )
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
    Common.DecisionPath.endDecisionPath (ContinueSession ( "Wait for progress in game", [] ))


askForHelpToGetUnstuck : DecisionPathNode
askForHelpToGetUnstuck =
    Common.DecisionPath.endDecisionPath (ContinueSession ( "I am stuck here and need help to continue.", [] ))


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
                Common.DecisionPath.endDecisionPath
                    (actWithoutFurtherReadings
                        ( "Read tooltip for module button"
                        , [ Common.EffectOnWindow.MouseMoveTo
                                (moduleButtonWithoutMemoryOfTooltip.uiNode.totalDisplayRegion |> centerFromDisplayRegion)
                          ]
                        )
                    )
            )


actWithoutFurtherReadings : ( String, List Common.EffectOnWindow.EffectOnWindowStructure ) -> EndDecisionPathStructure
actWithoutFurtherReadings =
    ContinueSession

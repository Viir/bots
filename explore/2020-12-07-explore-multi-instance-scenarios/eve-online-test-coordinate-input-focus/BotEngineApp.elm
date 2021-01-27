{- EVE Online bot to test coordinating sharing input focus

   See the `parseBotSettings` function to see the available app-settings.
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20201207 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree exposing (describeBranch, endDecisionPath)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , ReadingFromGameClient
        , ShipModulesMemory
        , UIElement
        , actWithoutFurtherReadings
        , askForHelpToGetUnstuck
        , branchDependingOnDockedOrInSpace
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion, getAllContainedDisplayTexts)


defaultBotSettings : BotSettings
defaultBotSettings =
    { itemNamePattern = ""
    , stepDistance = 1000
    , onlyPressEscapeKey = AppSettings.No
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignments { assignmentsSeparators = [ ",", "\n" ] }
        ([ ( "item-name-pattern"
           , AppSettings.valueTypeString (\itemNamePattern -> \settings -> { settings | itemNamePattern = itemNamePattern })
           )
         , ( "step-distance"
           , AppSettings.valueTypeInteger (\stepDistance -> \settings -> { settings | stepDistance = stepDistance })
           )
         , ( "only-press-escape-key"
           , AppSettings.valueTypeYesOrNo (\onlyPressEscapeKey -> \settings -> { settings | onlyPressEscapeKey = onlyPressEscapeKey })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { itemNamePattern : String
    , stepDistance : Int
    , onlyPressEscapeKey : AppSettings.YesOrNo
    }


type alias BotMemory =
    { lastSolarSystemName : Maybe String
    , jumpsCompleted : Int
    , shipModules : ShipModulesMemory
    }


type alias StateMemoryAndDecisionTree =
    EveOnline.AppFramework.AppStateWithMemoryAndDecisionTree BotMemory


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings StateMemoryAndDecisionTree


type alias BotDecisionContext =
    EveOnline.AppFramework.StepDecisionContext BotSettings BotMemory


initState : State
initState =
    EveOnline.AppFramework.initState
        (EveOnline.AppFramework.initStateWithMemoryAndDecisionTree
            { lastSolarSystemName = Nothing
            , jumpsCompleted = 0
            , shipModules = EveOnline.AppFramework.initShipModulesMemory
            }
        )


statusTextFromState : BotDecisionContext -> String
statusTextFromState _ =
    ""


botDecisionRoot : BotDecisionContext -> DecisionPathNode
botDecisionRoot context =
    if context.eventContext.appSettings.onlyPressEscapeKey == AppSettings.Yes then
        endDecisionPath
            (actWithoutFurtherReadings
                ( "Only press escape key."
                , [ EffectOnWindow.KeyDown EffectOnWindow.vkey_ESCAPE
                  , EffectOnWindow.KeyUp EffectOnWindow.vkey_ESCAPE
                  ]
                )
            )

    else
        branchDependingOnDockedOrInSpace
            { ifDocked = docked context
            , ifSeeShipUI = always Nothing
            , ifUndockingComplete = always (describeBranch "Not docked yet." askForHelpToGetUnstuck)
            }
            context.readingFromGameClient


docked : BotDecisionContext -> DecisionPathNode
docked context =
    case inventoryWindowWithOreHoldSelectedFromGameClient context.readingFromGameClient of
        Nothing ->
            describeBranch "I do not see an inventory with ore hold selected." askForHelpToGetUnstuck

        Just inventoryWindowWithOreHoldSelected ->
            dockedWithOreHoldSelected context inventoryWindowWithOreHoldSelected


dockedWithOreHoldSelected : BotDecisionContext -> EveOnline.ParseUserInterface.InventoryWindow -> DecisionPathNode
dockedWithOreHoldSelected context inventoryWindowWithOreHoldSelected =
    case inventoryWindowWithOreHoldSelected |> itemHangarFromInventoryWindow of
        Nothing ->
            describeBranch "I do not see the item hangar in the inventory." askForHelpToGetUnstuck

        Just itemHangar ->
            case
                inventoryWindowWithOreHoldSelected
                    |> selectedContainerFirstMatchingItemFromInventoryWindow context.eventContext.appSettings.itemNamePattern
            of
                Nothing ->
                    describeBranch "I see no matching item in the ore hold." waitForProgressInGame

                Just itemInInventory ->
                    describeBranch "I see at least one item in the ore hold. Move this to the item hangar."
                        (endDecisionPath
                            (actWithoutFurtherReadings
                                ( "Drag and drop."
                                , EffectOnWindow.effectsForDragAndDrop
                                    { startLocation = itemInInventory.totalDisplayRegion |> centerFromDisplayRegion
                                    , endLocation = itemHangar.totalDisplayRegion |> centerFromDisplayRegion
                                    , mouseButton = MouseButtonLeft
                                    }
                                )
                            )
                        )


inventoryWindowWithOreHoldSelectedFromGameClient : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindow
inventoryWindowWithOreHoldSelectedFromGameClient =
    .inventoryWindows
        >> List.filter inventoryWindowSelectedContainerIsOreHold
        >> List.head


inventoryWindowSelectedContainerIsOreHold : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsOreHold =
    .subCaptionLabelText >> Maybe.map (String.toLower >> String.contains "ore hold") >> Maybe.withDefault False


itemHangarFromInventoryWindow : EveOnline.ParseUserInterface.InventoryWindow -> Maybe UIElement
itemHangarFromInventoryWindow =
    .leftTreeEntries
        >> List.filter (.text >> String.toLower >> String.contains "item hangar")
        >> List.head
        >> Maybe.map .uiNode


selectedContainerFirstMatchingItemFromInventoryWindow : String -> EveOnline.ParseUserInterface.InventoryWindow -> Maybe UIElement
selectedContainerFirstMatchingItemFromInventoryWindow itemNamePattern =
    .selectedContainerInventory
        >> Maybe.andThen .itemsView
        >> Maybe.map
            (\itemsView ->
                case itemsView of
                    EveOnline.ParseUserInterface.InventoryItemsListView { items } ->
                        items

                    EveOnline.ParseUserInterface.InventoryItemsNotListView { items } ->
                        items
            )
        >> Maybe.andThen
            (List.filter
                (\item ->
                    (itemNamePattern == "")
                        || (item.uiNode |> getAllContainedDisplayTexts |> List.any (String.toLower >> String.contains (String.toLower itemNamePattern)))
                )
                >> List.head
            )


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> StateMemoryAndDecisionTree
    -> ( StateMemoryAndDecisionTree, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = always identity
        , decisionTreeRoot = botDecisionRoot
        , statusTextFromState = statusTextFromState
        , millisecondsToNextReadingFromGame = .eventContext >> .appSettings >> .stepDistance
        }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = parseBotSettings
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }

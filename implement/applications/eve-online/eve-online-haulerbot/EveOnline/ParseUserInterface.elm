module EveOnline.ParseUserInterface exposing (..)

{-| A library of building blocks to build programs that read from the EVE Online game client.

The EVE Online client's UI tree can contain thousands of nodes and tens of thousands of individual properties. Because of this large amount of data, navigating in there can be time-consuming.

This library helps us navigate the UI tree with functions to filter out redundant data and extract the interesting bits.

The types in this module provide names more closely related to players' experience, such as the overview window or ship modules.

To learn about the user interface structures in the EVE Online game client, see the guide at <https://to.botlab.org/guide/parsed-user-interface-of-the-eve-online-game-client>

-}

import Common.EffectOnWindow
import Dict
import EveOnline.MemoryReading
import Json.Decode
import Json.Encode
import List.Extra
import Maybe.Extra
import Regex
import Result.Extra
import Set


type alias ParsedUserInterface =
    { uiTree : UITreeNodeWithDisplayRegion
    , contextMenus : List ContextMenu
    , shipUI : Maybe ShipUI
    , targets : List Target
    , infoPanelContainer : Maybe InfoPanelContainer
    , overviewWindows : List OverviewWindow
    , selectedItemWindow : Maybe SelectedItemWindow
    , dronesWindow : Maybe DronesWindow
    , fittingWindow : Maybe FittingWindow
    , probeScannerWindow : Maybe ProbeScannerWindow
    , directionalScannerWindow : Maybe DirectionalScannerWindow
    , stationWindow : Maybe StationWindow
    , shipItemCards : List ShipItemCard
    , inventoryWindows : List InventoryWindow
    , chatWindowStacks : List ChatWindowStack
    , agentConversationWindows : List AgentConversationWindow
    , agentMissionInfoPanelEntries : List AgentMissionInfoPanelEntry
    , marketOrdersWindow : Maybe MarketOrdersWindow
    , surveyScanWindow : Maybe SurveyScanWindow
    , bookmarkLocationWindow : Maybe BookmarkLocationWindow
    , repairShopWindow : Maybe RepairShopWindow
    , characterSheetWindow : Maybe CharacterSheetWindow
    , fleetWindow : Maybe FleetWindow
    , locationsWindow : Maybe LocationsWindow
    , watchListPanel : Maybe WatchListPanel
    , standaloneBookmarkWindow : Maybe StandaloneBookmarkWindow
    , moduleButtonTooltip : Maybe ModuleButtonTooltip
    , heatStatusTooltip : Maybe HeatStatusTooltip
    , neocom : Maybe Neocom
    , messageBoxes : List MessageBox
    , layerAbovemain : Maybe LayerAbovemain
    , keyActivationWindow : Maybe KeyActivationWindow
    , compressionWindow : Maybe CompressionWindow
    , gameLogEntriesSinceLastReading : Maybe (List GameLogEntry)
    , incomingDamageSinceLastReading : Maybe IncomingDamage
    , outgoingDamageSinceLastReading : Maybe (List OutgoingDamageToTarget)
    , killsSinceLastReading : Maybe Int
    }


type alias UITreeNodeWithDisplayRegion =
    { uiNode : EveOnline.MemoryReading.UITreeNode
    , children : Maybe (List ChildOfNodeWithDisplayRegion)
    , selfDisplayRegion : DisplayRegion
    , totalDisplayRegion : DisplayRegion
    , totalDisplayRegionVisible : DisplayRegion
    }


type ChildOfNodeWithDisplayRegion
    = ChildWithRegion UITreeNodeWithDisplayRegion
    | ChildWithoutRegion EveOnline.MemoryReading.UITreeNode


type alias DisplayRegion =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


type alias Location2d =
    { x : Int
    , y : Int
    }


type alias ContextMenu =
    { uiNode : UITreeNodeWithDisplayRegion
    , entries : List ContextMenuEntry
    }


type alias ContextMenuEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , text : String
    }


type alias ShipUI =
    { uiNode : UITreeNodeWithDisplayRegion
    , capacitor : ShipUICapacitor
    , hitpointsPercent : Hitpoints
    , indication : Maybe ShipUIIndication
    , moduleButtons : List ShipUIModuleButton
    , moduleButtonsRows :
        { top : List ShipUIModuleButton
        , middle : List ShipUIModuleButton
        , bottom : List ShipUIModuleButton
        }
    , offensiveBuffButtons : List { uiNode : UITreeNodeWithDisplayRegion, name : String }
    , squadronsUI : Maybe SquadronsUI
    , stopButton : Maybe UITreeNodeWithDisplayRegion
    , maxSpeedButton : Maybe UITreeNodeWithDisplayRegion
    , heatGauges : Maybe ShipUIHeatGauges
    }


type alias ShipUIIndication =
    { uiNode : UITreeNodeWithDisplayRegion
    , maneuverType : Maybe ShipManeuverType
    }


type alias ShipUIModuleButton =
    { uiNode : UITreeNodeWithDisplayRegion
    , slotUINode : UITreeNodeWithDisplayRegion
    , isActive : Maybe Bool
    , isHiliteVisible : Bool
    , isBusy : Bool
    , rampRotationMilli : Maybe Int
    , stateFromDictEntries : ShipUIModuleButtonState
    }


type alias ShipUICapacitor =
    { uiNode : UITreeNodeWithDisplayRegion
    , pmarks : List ShipUICapacitorPmark
    , levelFromPmarksPercent : Maybe Int
    }


type alias ShipUICapacitorPmark =
    { uiNode : UITreeNodeWithDisplayRegion
    , colorPercent : Maybe ColorComponents
    }


type alias ShipUIHeatGauges =
    { uiNode : UITreeNodeWithDisplayRegion
    , gauges : List ShipUIHeatGauge
    }


type alias ShipUIHeatGauge =
    { uiNode : UITreeNodeWithDisplayRegion
    , rotationPercent : Maybe Int
    , heatPercent : Maybe Int
    }


type alias Hitpoints =
    { structure : Int
    , armor : Int
    , shield : Int
    }


type ShipManeuverType
    = ManeuverWarp
    | ManeuverJump
    | ManeuverOrbit
    | ManeuverApproach
    | ManeuverRange
    | ManeuverAlign


type alias SquadronsUI =
    { uiNode : UITreeNodeWithDisplayRegion
    , squadrons : List SquadronUI
    }


type alias SquadronUI =
    { uiNode : UITreeNodeWithDisplayRegion
    , abilities : List SquadronAbilityIcon
    , actionLabel : Maybe UITreeNodeWithDisplayRegion
    }


type alias SquadronAbilityIcon =
    { uiNode : UITreeNodeWithDisplayRegion
    , quantity : Maybe Int
    , ramp_active : Maybe Bool
    }


type alias InfoPanelContainer =
    { uiNode : UITreeNodeWithDisplayRegion
    , icons : Maybe InfoPanelIcons
    , infoPanelLocationInfo : Maybe InfoPanelLocationInfo
    , infoPanelRoute : Maybe InfoPanelRoute
    , infoPanelAgentMissions : Maybe InfoPanelAgentMissions
    }


type alias InfoPanelIcons =
    { uiNode : UITreeNodeWithDisplayRegion
    , search : Maybe UITreeNodeWithDisplayRegion
    , locationInfo : Maybe UITreeNodeWithDisplayRegion
    , route : Maybe UITreeNodeWithDisplayRegion
    , agentMissions : Maybe UITreeNodeWithDisplayRegion
    , dailyChallenge : Maybe UITreeNodeWithDisplayRegion
    }


type alias InfoPanelRoute =
    { uiNode : UITreeNodeWithDisplayRegion
    , routeElementMarker : List InfoPanelRouteRouteElementMarker
    }


type alias InfoPanelRouteRouteElementMarker =
    { uiNode : UITreeNodeWithDisplayRegion
    , numJumps : Maybe Int
    }


type alias InfoPanelLocationInfo =
    { uiNode : UITreeNodeWithDisplayRegion
    , listSurroundingsButton : UITreeNodeWithDisplayRegion
    , currentSolarSystemName : Maybe String
    , securityStatusPercent : Maybe Int
    , expandedContent : Maybe InfoPanelLocationInfoExpandedContent
    }


type alias InfoPanelLocationInfoExpandedContent =
    { currentStationName : Maybe String
    }


type alias InfoPanelAgentMissions =
    { uiNode : UITreeNodeWithDisplayRegion
    , entries : List InfoPanelAgentMissionsEntry
    }


type alias InfoPanelAgentMissionsEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    }


type alias Target =
    { uiNode : UITreeNodeWithDisplayRegion
    , barAndImageCont : Maybe UITreeNodeWithDisplayRegion
    , hitpointsPercent : Maybe Hitpoints
    , textsTopToBottom : List String
    , isActiveTarget : Bool
    , assignedContainerNode : Maybe UITreeNodeWithDisplayRegion
    , assignedIcons : List UITreeNodeWithDisplayRegion
    }


type alias OverviewWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , entriesHeaders : List ( String, UITreeNodeWithDisplayRegion )
    , entries : List OverviewWindowEntry
    , scrollControls : Maybe ScrollControls
    }


type alias OverviewWindowEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , textsLeftToRight : List String
    , cellsTexts : Dict.Dict String String
    , objectDistance : Maybe String
    , objectDistanceInMeters : Result String Int
    , objectName : Maybe String
    , objectType : Maybe String
    , objectAlliance : Maybe String
    , iconSpriteColorPercent : Maybe ColorComponents
    , namesUnderSpaceObjectIcon : Set.Set String
    , bgColorFillsPercent : List ColorComponents
    , rightAlignedIconsHints : List String
    , commonIndications : OverviewWindowEntryCommonIndications
    , opacityPercent : Maybe Int
    , objectItemID : Maybe String
    }


type alias OverviewWindowEntryCommonIndications =
    { targeting : Bool
    , targetedByMe : Bool
    , isJammingMe : Bool
    , isWarpDisruptingMe : Bool
    , isTrackingDisruptingMe : Bool
    , isSensorDampeningMe : Bool
    }


type alias SelectedItemWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , orbitButton : Maybe UITreeNodeWithDisplayRegion
    }


type alias FittingWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    }


type alias MarketOrdersWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    }


type alias SurveyScanWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , scanEntries : List UITreeNodeWithDisplayRegion
    }


type alias RepairShopWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , items : List UITreeNodeWithDisplayRegion
    , buttonGroup : Maybe UITreeNodeWithDisplayRegion
    , buttons : List { uiNode : UITreeNodeWithDisplayRegion, mainText : Maybe String }
    }


type alias CharacterSheetWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , skillGroups : List UITreeNodeWithDisplayRegion
    }


type alias ColorComponents =
    { a : Int, r : Int, g : Int, b : Int }


type alias DronesWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , droneGroups : List DronesWindowEntryGroupStructure
    , droneGroupInBay : Maybe DronesWindowEntryGroupStructure
    , droneGroupInSpace : Maybe DronesWindowEntryGroupStructure
    }


type alias DronesWindowEntryGroupStructure =
    { header : DronesWindowDroneGroupHeader
    , children : List DronesWindowEntry
    }


type DronesWindowEntry
    = DronesWindowEntryGroup DronesWindowEntryGroupStructure
    | DronesWindowEntryDrone DronesWindowEntryDroneStructure


type alias DronesWindowDroneGroupHeader =
    { uiNode : UITreeNodeWithDisplayRegion
    , mainText : Maybe String
    , quantityFromTitle : Maybe DronesWindowDroneGroupHeaderQuantity
    }


type alias DronesWindowDroneGroupHeaderQuantity =
    { current : Int
    , maximum : Maybe Int
    }


type alias DronesWindowEntryDroneStructure =
    { uiNode : UITreeNodeWithDisplayRegion
    , mainText : Maybe String
    , hitpointsPercent : Maybe Hitpoints
    }


type alias ProbeScannerWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , scanResults : List ProbeScanResult
    }


type alias ProbeScanResult =
    { uiNode : UITreeNodeWithDisplayRegion
    , textsLeftToRight : List String
    , cellsTexts : Dict.Dict String String
    , warpButton : Maybe UITreeNodeWithDisplayRegion
    }


type alias DirectionalScannerWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , scrollNode : Maybe UITreeNodeWithDisplayRegion
    , scanResults : List UITreeNodeWithDisplayRegion
    }


type alias StationWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , undockButton : Maybe UITreeNodeWithDisplayRegion
    , abortUndockButton : Maybe UITreeNodeWithDisplayRegion
    , agentsTab : Maybe StationWindowTab
    , agentEntries : List StationAgentEntry
    }


{-| A tab in the station lobby's tab strip. `isSelected` matters because the
lobby keeps every panel's nodes in the tree with real display regions
whether or not its tab is showing, so neither node presence nor a non-zero
region tells you what the player can actually click -- only the tab's own
`_selected` flag does.
-}
type alias StationWindowTab =
    { uiNode : UITreeNodeWithDisplayRegion
    , isSelected : Bool
    }


{-| One agent in the station lobby's Agents panel. `missionState` is empty
when the agent has no mission for us and reads "Accepted" (wrapped in the
game's own colour markup) once one is running, so it is the cheapest way to
tell where in the mission cycle we are without opening a conversation.
`isAvailable` comes from which "Available to you" / "Not available to you"
header the entry sits under -- the panel expresses that grouping purely
through ordering, not through nesting.
-}
type alias StationAgentEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , name : Maybe String
    , agentType : Maybe String
    , missionState : Maybe String
    , agentLocation : Maybe String
    , characterID : Maybe Int
    , conversationButton : Maybe UITreeNodeWithDisplayRegion
    , isAvailable : Bool
    }


{-| One ship in the station's Hangars/Ships panel, as a card.

Worth having only because of what a right-click on it offers: "Open Drone Bay"
there anchors the inventory to that ship, and that is the only context in which
a drop into the bay is accepted. See `tools/macos-host/reload_drones.py`.

-}
type alias ShipItemCard =
    { uiNode : UITreeNodeWithDisplayRegion
    , mainText : Maybe String
    }


type alias InventoryWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , leftTreeEntries : List InventoryWindowLeftTreeEntry
    , subCaptionLabelText : Maybe String
    , selectedContainerCapacityGauge : Maybe (Result String InventoryWindowCapacityGauge)
    , selectedContainerInventory : Maybe Inventory
    , buttonToSwitchToListView : Maybe UITreeNodeWithDisplayRegion
    , buttonToStackAll : Maybe UITreeNodeWithDisplayRegion
    , quickFilterInputBox : Maybe UITreeNodeWithDisplayRegion
    , quickFilterText : Maybe String
    }


type alias Inventory =
    { uiNode : UITreeNodeWithDisplayRegion
    , itemsView : Maybe InventoryItemsView
    , scrollControls : Maybe ScrollControls
    }


type InventoryItemsView
    = InventoryItemsListView { items : List InventoryItemsListViewEntry }
    | InventoryItemsNotListView { items : List UITreeNodeWithDisplayRegion }


type alias InventoryWindowLeftTreeEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , toggleBtn : Maybe UITreeNodeWithDisplayRegion
    , selectRegion : Maybe UITreeNodeWithDisplayRegion
    , text : String
    , children : List InventoryWindowLeftTreeEntryChild
    }


type InventoryWindowLeftTreeEntryChild
    = InventoryWindowLeftTreeEntryChild InventoryWindowLeftTreeEntry


type alias InventoryWindowCapacityGauge =
    { used : Int
    , maximum : Maybe Int
    , selected : Maybe Int
    }


type alias InventoryItemsListViewEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , cellsTexts : Dict.Dict String String
    }


type alias ChatWindowStack =
    { uiNode : UITreeNodeWithDisplayRegion
    , chatWindow : Maybe ChatWindow
    }


type alias ChatWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , name : Maybe String
    , userlist : Maybe ChatWindowUserlist
    }


type alias ChatWindowUserlist =
    { uiNode : UITreeNodeWithDisplayRegion
    , visibleUsers : List ChatUserEntry
    , scrollControls : Maybe ScrollControls
    }


type alias ChatUserEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , name : Maybe String
    , standingIconHint : Maybe String
    }


type alias ModuleButtonTooltip =
    { uiNode : UITreeNodeWithDisplayRegion
    , shortcut : Maybe { text : String, parseResult : Result String (List Common.EffectOnWindow.VirtualKeyCode) }
    , optimalRange : Maybe { asString : String, inMeters : Result String Int }
    }


type alias HeatStatusTooltip =
    { uiNode : UITreeNodeWithDisplayRegion
    , lowPercent : Maybe Int
    , mediumPercent : Maybe Int
    , highPercent : Maybe Int
    }


type alias Neocom =
    { uiNode : UITreeNodeWithDisplayRegion
    , inventoryButton : Maybe UITreeNodeWithDisplayRegion
    , clock : Maybe NeocomClock
    }


type alias NeocomClock =
    { uiNode : UITreeNodeWithDisplayRegion
    , text : String
    , parsedText : Result String { hour : Int, minute : Int }
    }


{-| The agent conversation. Which buttons are present is what identifies the
conversation's state: `RequestMission_Button` when the agent has nothing for
us, `AcceptMission_Button`/`DeclineMission_Button`/`DeferMission_Button` on a
pending offer, and `CompleteMission_Button`/`QuitMission_Button` while a
mission is running. The buttons are matched on `_name`, not on their label,
so the parsing does not depend on the client's UI language.
-}
type alias AgentConversationWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , agentCharacterID : Maybe Int
    , buttons : List AgentConversationButton
    , briefingHtml : Maybe String
    , objectiveHtml : Maybe String
    , offeredMissionName : Maybe String
    }


type alias AgentConversationButton =
    { uiNode : UITreeNodeWithDisplayRegion
    , name : String
    , mainText : Maybe String
    }


{-| The mission tracker in the info panel's job board, one per accepted
mission. `locationButton` is a single button whose label is always the next
travel step -- "Undock", "Set Destination", "Warp to Location", "Dock" -- and
which carries no label at all while the ship is on grid and it is the bot's
turn to act. `objectiveTitles` gains a "Complete Mission" entry once every
objective is done, which is the signal to head back to the agent.
-}
type alias AgentMissionInfoPanelEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , agentCharacterID : Maybe Int
    , missionName : Maybe String
    , objectiveTitles : List String
    , instructionTexts : List String
    , objectNamesToDestroy : List String
    , objectNamesToCarry : List String
    , objectNamesToApproach : List String
    , locationButton : Maybe AgentMissionLocationButton
    , isExpanded : Bool
    }


type alias AgentMissionLocationButton =
    { uiNode : UITreeNodeWithDisplayRegion
    , label : Maybe String
    }


type alias BookmarkLocationWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , submitButton : Maybe UITreeNodeWithDisplayRegion
    , cancelButton : Maybe UITreeNodeWithDisplayRegion
    }


type alias MessageBox =
    { uiNode : UITreeNodeWithDisplayRegion
    , buttonGroup : Maybe UITreeNodeWithDisplayRegion
    , buttons : List { uiNode : UITreeNodeWithDisplayRegion, mainText : Maybe String }
    }


type alias ScrollControls =
    { uiNode : UITreeNodeWithDisplayRegion
    , scrollHandle : Maybe UITreeNodeWithDisplayRegion
    }


type alias FleetWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , fleetMembers : List UITreeNodeWithDisplayRegion
    }


type alias WatchListPanel =
    { uiNode : UITreeNodeWithDisplayRegion
    , entries : List UITreeNodeWithDisplayRegion
    }


type alias StandaloneBookmarkWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , entries : List UITreeNodeWithDisplayRegion
    }


type alias LayerAbovemain =
    { uiNode : UITreeNodeWithDisplayRegion
    , quickMessage : Maybe QuickMessage
    }


type alias QuickMessage =
    { uiNode : UITreeNodeWithDisplayRegion
    , text : String
    }


type alias KeyActivationWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , activateButton : Maybe UITreeNodeWithDisplayRegion
    }


type alias CompressionWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , compressButton : Maybe UITreeNodeWithDisplayRegion
    , windowControls : Maybe WindowControls
    }


type alias LocationsWindow =
    { uiNode : UITreeNodeWithDisplayRegion
    , placeEntries : List LocationsWindowPlaceEntry
    }


type alias LocationsWindowPlaceEntry =
    { uiNode : UITreeNodeWithDisplayRegion
    , mainText : String
    }


type alias WindowControls =
    { uiNode : UITreeNodeWithDisplayRegion
    , minimizeButton : Maybe UITreeNodeWithDisplayRegion
    , closeButton : Maybe UITreeNodeWithDisplayRegion
    }


parseUITreeWithDisplayRegionFromUITree : EveOnline.MemoryReading.UITreeNode -> UITreeNodeWithDisplayRegion
parseUITreeWithDisplayRegionFromUITree uiTree =
    let
        selfDisplayRegion =
            uiTree |> getDisplayRegionFromDictEntries |> Maybe.withDefault { x = 0, y = 0, width = 0, height = 0 }
    in
    uiTree
        |> asUITreeNodeWithDisplayRegion
            { selfDisplayRegion = selfDisplayRegion
            , totalDisplayRegion = selfDisplayRegion
            , occludedRegions = []
            }


parseUserInterfaceFromUITree : UITreeNodeWithDisplayRegion -> ParsedUserInterface
parseUserInterfaceFromUITree uiTree =
    { uiTree = uiTree
    , contextMenus = parseContextMenusFromUITreeRoot uiTree
    , shipUI = parseShipUIFromUITreeRoot uiTree
    , targets = parseTargetsFromUITreeRoot uiTree
    , infoPanelContainer = parseInfoPanelContainerFromUIRoot uiTree
    , overviewWindows = parseOverviewWindowsFromUITreeRoot uiTree
    , selectedItemWindow = parseSelectedItemWindowFromUITreeRoot uiTree
    , dronesWindow = parseDronesWindowFromUITreeRoot uiTree
    , fittingWindow = parseFittingWindowFromUITreeRoot uiTree
    , probeScannerWindow = parseProbeScannerWindowFromUITreeRoot uiTree
    , directionalScannerWindow = parseDirectionalScannerWindowFromUITreeRoot uiTree
    , stationWindow = parseStationWindowFromUITreeRoot uiTree
    , shipItemCards = parseShipItemCardsFromUITreeRoot uiTree
    , inventoryWindows = parseInventoryWindowsFromUITreeRoot uiTree
    , moduleButtonTooltip = parseModuleButtonTooltipFromUITreeRoot uiTree
    , heatStatusTooltip = parseHeatStatusTooltipFromUITreeRoot uiTree
    , chatWindowStacks = parseChatWindowStacksFromUITreeRoot uiTree
    , agentConversationWindows = parseAgentConversationWindowsFromUITreeRoot uiTree
    , agentMissionInfoPanelEntries = parseAgentMissionInfoPanelEntriesFromUITreeRoot uiTree
    , marketOrdersWindow = parseMarketOrdersWindowFromUITreeRoot uiTree
    , surveyScanWindow = parseSurveyScanWindowFromUITreeRoot uiTree
    , bookmarkLocationWindow = parseBookmarkLocationWindowFromUITreeRoot uiTree
    , repairShopWindow = parseRepairShopWindowFromUITreeRoot uiTree
    , characterSheetWindow = parseCharacterSheetWindowFromUITreeRoot uiTree
    , fleetWindow = parseFleetWindowFromUITreeRoot uiTree
    , locationsWindow = parseLocationsWindowFromUITreeRoot uiTree
    , watchListPanel = parseWatchListPanelFromUITreeRoot uiTree
    , standaloneBookmarkWindow = parseStandaloneBookmarkWindowFromUITreeRoot uiTree
    , neocom = parseNeocomFromUITreeRoot uiTree
    , messageBoxes = parseMessageBoxesFromUITreeRoot uiTree
    , layerAbovemain = parseLayerAbovemainFromUITreeRoot uiTree
    , keyActivationWindow = parseKeyActivationWindowFromUITreeRoot uiTree
    , compressionWindow = parseCompressionWindowFromUITreeRoot uiTree
    , gameLogEntriesSinceLastReading = parseGameLogEntriesSinceLastReadingFromUITreeRoot uiTree
    , incomingDamageSinceLastReading = parseIncomingDamageSinceLastReadingFromUITreeRoot uiTree
    , outgoingDamageSinceLastReading = parseOutgoingDamageSinceLastReadingFromUITreeRoot uiTree
    , killsSinceLastReading = parseKillsSinceLastReadingFromUITreeRoot uiTree
    }


{-| One line EVE's own client wrote to its game log, as carried into a reading
by the macOS host in this fork. `channel` is the client's own bracketed
category -- `notify` for a refusal, `None` for travel -- and is a `Maybe`
because a node missing it is a host that did not say, not a line without one.
-}
type alias GameLogEntry =
    { timestamp : Maybe String
    , channel : Maybe String
    , text : String
    }


{-| What the client said in its own game log since the previous reading.

The client explains every refusal there and nowhere else -- "You cannot load or
unload <weapon> while it is active", "You are already managing 6 targets, as
many as you have skill to", "You cannot launch Acolyte I because you are already
controlling 5 drones" -- while a bot that sees only the UI tree has to infer each
of them from something else failing to change.

`Nothing` and `Just []` are different answers and must stay so. `Nothing` is a
host that provides no game log at all -- BotLab.exe, or this fork's host run
with `--no-game-log` -- and reading that as "the client said nothing" is how a
bot concludes a command was accepted because no refusal arrived.

The node this reads is **not from the game client**: the macOS host appends it
to the tree it emits, which is why its type name says so in full. It carries no
display region, so it is invisible to every other parser in this module, and its
text sits under `text` rather than `_setText`/`_text` so `getDisplayText` cannot
reach it and mistake a logged line for something rendered on screen.

Scoped to the reading by the host, which drains its queue as it builds the tree:
these are the lines written since the previous read, not a growing buffer that
would have a bot answering a refusal from four minutes ago.

-}
parseGameLogEntriesSinceLastReadingFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe (List GameLogEntry)
parseGameLogEntriesSinceLastReadingFromUITreeRoot uiTreeRoot =
    uiTreeRoot.uiNode.children
        |> Maybe.withDefault []
        |> List.map EveOnline.MemoryReading.unwrapUITreeNodeChild
        |> List.filter (.pythonObjectTypeName >> (==) syntheticGameLogNodeTypeName)
        |> List.head
        |> Maybe.map
            (\gameLogNode ->
                gameLogNode.children
                    |> Maybe.withDefault []
                    |> List.map EveOnline.MemoryReading.unwrapUITreeNodeChild
                    |> List.filterMap parseGameLogEntry
            )


syntheticGameLogNodeTypeName : String
syntheticGameLogNodeTypeName =
    "MacOsHostSyntheticGameLog"


parseGameLogEntry : EveOnline.MemoryReading.UITreeNode -> Maybe GameLogEntry
parseGameLogEntry entryNode =
    case getStringPropertyFromDictEntries "text" entryNode of
        Nothing ->
            Nothing

        Just text ->
            Just
                { timestamp = getStringPropertyFromDictEntries "timestamp" entryNode
                , channel = getStringPropertyFromDictEntries "channel" entryNode
                , text = text
                }


{-| How much damage the client's own combat log says arrived since the last
reading, as carried by the macOS host in this fork.

`damage` is the total in hitpoints, `hits` the number of shots that landed
(misses cost nothing and are not counted), and `topAttacker` whichever name did
the most of it -- enough for a decision to say what is shooting without carrying
a list of shots.

**This is the one instrument here that does not go through the ship's HUD.**
`ShipUI.hitpointsPercent` is a float read out of a gauge widget in live memory,
and it is not reliably true: across eight recorded runs it produced -1021821%,
2132822% and 8362% among others, always for exactly one reading and always
surrounded by sane values, which is what a read landing on a reallocated object
looks like. A number the client states outright cannot fail that way.

`Nothing` and `Just { damage = 0, ... }` are different answers and must stay so,
for the same reason they are for `gameLogEntriesSinceLastReading`. `Nothing` is
a host that does not carry this at all -- BotLab.exe, or this fork's host run
with `--no-game-log` -- and reading it as "no damage taken" is how a bot
concludes it is safe because nothing is listening.

The node this reads is **not from the game client**: the macOS host appends it
to the tree it emits, which is why its type name says so in full. It carries no
display region, so no other parser in this module can reach it, and its values
sit under plain keys rather than `_setText`/`_text` so `getDisplayText` cannot
mistake them for something rendered on screen.

Scoped to the reading by the host, which drains its queue as it builds the tree,
so this is the fire taken since the previous read rather than a running total.

-}
type alias IncomingDamage =
    { damage : Int
    , hits : Int
    , topAttacker : Maybe String
    }


parseIncomingDamageSinceLastReadingFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe IncomingDamage
parseIncomingDamageSinceLastReadingFromUITreeRoot uiTreeRoot =
    uiTreeRoot.uiNode.children
        |> Maybe.withDefault []
        |> List.map EveOnline.MemoryReading.unwrapUITreeNodeChild
        |> List.filter (.pythonObjectTypeName >> (==) syntheticIncomingDamageNodeTypeName)
        |> List.head
        |> Maybe.map
            (\damageNode ->
                { damage = damageNode |> getIntPropertyFromDictEntries "damage" |> Maybe.withDefault 0
                , hits = damageNode |> getIntPropertyFromDictEntries "hits" |> Maybe.withDefault 0
                , topAttacker = getStringPropertyFromDictEntries "topAttacker" damageNode
                }
            )


syntheticIncomingDamageNodeTypeName : String
syntheticIncomingDamageNodeTypeName =
    "MacOsHostSyntheticIncomingDamage"


getIntPropertyFromDictEntries : String -> EveOnline.MemoryReading.UITreeNode -> Maybe Int
getIntPropertyFromDictEntries dictEntryKey node =
    node.dictEntriesOfInterest
        |> Dict.get dictEntryKey
        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.int >> Result.toMaybe)


{-| What this ship's own shots achieved since the last reading, per target, as
carried by the macOS host in this fork.

`hits` counts the shots that **landed** on that target -- a miss carries no
damage number in the client's log and is not counted -- and `damage` is what
those hits took off it. So `hits = 12, damage = 0` is the client stating that
twelve shots connected with an object and achieved nothing, which is a fact
about that object that no other reading in this system reports.

**Issue #90.** Run 27 locked an `Infested Asteroid` and shot it for roughly 290
consecutive readings, every shot landing for zero, while nine real rats sat on
the same overview untouched and the mission objective was already finished. The
bot could not see it: the host summed the _incoming_ half of the combat channel
for #32 and matched the outgoing half nowhere, so no field in any reading said
how much damage this ship was dealing.

**Per target rather than one total**, unlike `IncomingDamage`, because the
question is about one object. Guns and drones engage different things in the
same reading -- run 27's drones were landing real damage on a rat in the very
readings its guns were achieving nothing on the asteroid -- so a single sum
would have read as healthy throughout the incident this exists for.

`Nothing` and `Just []` are different answers, and the fail-safe direction here
is the **opposite** of the retreat's. `Just []` is "the client reported no shot
landing this reading"; `Nothing` is "this host does not carry the channel", and
a bot that read the second as evidence would conclude every target is immune on
a host that simply has no game log. Absent means unknown, and unknown must keep
shooting.

The node this reads is **not from the game client**: the macOS host appends it
to the tree it emits, which is why its type name says so in full. It carries no
display region, so no other parser in this module can reach it, and its values
sit under plain keys rather than `_setText`/`_text` so `getDisplayText` cannot
mistake a target's name for something rendered on screen.

Scoped to the reading by the host, which drains its queue as it builds the tree,
so this is what the shots since the previous read achieved rather than a running
total.

**`hits` and `misses` are separate counts and summing them is the one mistake to
avoid here.** A landed shot for zero damage says the guns cannot hurt this
object; a miss says they cannot hit it, which is a range or tracking problem and
resolves on its own. Issue #267 measured the difference rather than assuming it:
across 5,631 episodes in the client's own logs, no target that ever landed a
shot for zero was hurt afterwards, while targets the guns went on to kill
absorbed runs of up to 702 consecutive misses first. So a rule may read both,
and no rule may treat one as the other.

`misses` defaults to zero rather than to `Nothing`, which is the one place this
record takes a default instead of reporting absence. A host older than #267
writes no such key, and reading that as "no shots missed" is exactly the
behaviour those hosts already had -- so the default degrades to the previous
rule rather than inventing evidence. The distinction that must not be lost, "is
this channel here at all", is carried by the `Maybe` around the whole list and
is untouched.

-}
type alias OutgoingDamageToTarget =
    { name : String
    , hits : Int
    , damage : Int
    , misses : Int
    }


parseOutgoingDamageSinceLastReadingFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe (List OutgoingDamageToTarget)
parseOutgoingDamageSinceLastReadingFromUITreeRoot uiTreeRoot =
    uiTreeRoot.uiNode.children
        |> Maybe.withDefault []
        |> List.map EveOnline.MemoryReading.unwrapUITreeNodeChild
        |> List.filter (.pythonObjectTypeName >> (==) syntheticOutgoingDamageNodeTypeName)
        |> List.head
        |> Maybe.map
            (\outgoingDamageNode ->
                outgoingDamageNode.children
                    |> Maybe.withDefault []
                    |> List.map EveOnline.MemoryReading.unwrapUITreeNodeChild
                    |> List.filterMap parseOutgoingDamageToTarget
            )


parseOutgoingDamageToTarget : EveOnline.MemoryReading.UITreeNode -> Maybe OutgoingDamageToTarget
parseOutgoingDamageToTarget targetNode =
    case getStringPropertyFromDictEntries "name" targetNode of
        Nothing ->
            Nothing

        Just name ->
            Just
                { name = name
                , hits = targetNode |> getIntPropertyFromDictEntries "hits" |> Maybe.withDefault 0
                , damage = targetNode |> getIntPropertyFromDictEntries "damage" |> Maybe.withDefault 0
                , misses = targetNode |> getIntPropertyFromDictEntries "misses" |> Maybe.withDefault 0
                }


syntheticOutgoingDamageNodeTypeName : String
syntheticOutgoingDamageNodeTypeName =
    "MacOsHostSyntheticOutgoingDamage"


{-| How many rats the client paid a bounty for since the last reading.

The fourth of the host's synthetic nodes, and the one that carries the least:
one number, because the `(bounty)` channel it is summed from says nothing else.
Across the 17,388 bounty lines in the recorded client sessions there are two
wordings and neither names a target, so this count can never be split per rat,
per name or per anomaly -- which is a property rather than a shortfall, since
an anomaly is a pocket of identically named rats and a name-keyed fold over one
is what PR #274 found reporting a stall on a rat that was never in it.

**What it counts is what the client paid, not what this ship killed.** A rat a
fleetmate finished that this ship damaged still pays and is counted; a rat this
ship killed whose bounty went elsewhere is not; and anything with no bounty --
a structure, a wreck -- writes no line however thoroughly it is destroyed. No
rule may read this as "kills by this ship".

**`Nothing` is "this host does not carry the channel" and `Just 0` is "the
client reported nothing dying this reading"**, which is the same distinction the
other three synthetic nodes keep and the same one that must never be collapsed:
a session that killed nothing and a session nobody counted read identically
otherwise.

The count is read **strictly**, with no default. A node present without the key
is a host disagreeing with this parser about the node's own shape, and the safe
answer to that is "we do not know" rather than a fabricated zero -- a defaulted
count is one that reports a quiet grid for a broken channel.

-}
parseKillsSinceLastReadingFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe Int
parseKillsSinceLastReadingFromUITreeRoot uiTreeRoot =
    uiTreeRoot.uiNode.children
        |> Maybe.withDefault []
        |> List.map EveOnline.MemoryReading.unwrapUITreeNodeChild
        |> List.filter (.pythonObjectTypeName >> (==) syntheticKillsNodeTypeName)
        |> List.head
        |> Maybe.andThen (getIntPropertyFromDictEntries "kills")


syntheticKillsNodeTypeName : String
syntheticKillsNodeTypeName =
    "MacOsHostSyntheticKills"


asUITreeNodeWithDisplayRegion :
    { selfDisplayRegion : DisplayRegion, totalDisplayRegion : DisplayRegion, occludedRegions : List DisplayRegion }
    -> EveOnline.MemoryReading.UITreeNode
    -> UITreeNodeWithDisplayRegion
asUITreeNodeWithDisplayRegion { selfDisplayRegion, totalDisplayRegion, occludedRegions } uiNode =
    { uiNode = uiNode
    , children =
        uiNode.children
            |> Maybe.map
                (List.foldl
                    (\currentChild ( mappedSiblings, occludedRegionsFromSiblings ) ->
                        let
                            currentChildResult =
                                currentChild
                                    |> EveOnline.MemoryReading.unwrapUITreeNodeChild
                                    |> asUITreeNodeWithInheritedOffset
                                        { x = totalDisplayRegion.x, y = totalDisplayRegion.y }
                                        { occludedRegions = occludedRegionsFromSiblings ++ occludedRegions }

                            newOccludedRegionsFromSiblings =
                                currentChildResult
                                    |> justCaseWithDisplayRegion
                                    |> Maybe.map listDescendantsWithDisplayRegion
                                    |> Maybe.withDefault []
                                    |> List.filter (.uiNode >> nodeOccludesFollowingNodes)
                                    |> List.map .totalDisplayRegion
                        in
                        ( currentChildResult :: mappedSiblings
                        , newOccludedRegionsFromSiblings ++ occludedRegionsFromSiblings
                        )
                    )
                    ( [], [] )
                    >> Tuple.first
                    >> List.reverse
                )
    , selfDisplayRegion = selfDisplayRegion
    , totalDisplayRegion = totalDisplayRegion
    , totalDisplayRegionVisible =
        subtractRegionsFromRegion { minuend = totalDisplayRegion, subtrahend = occludedRegions }
            |> List.sortBy (areaFromDisplayRegion >> Maybe.withDefault -1 >> negate)
            |> List.head
            |> Maybe.withDefault { x = -1, y = -1, width = 0, height = 0 }
    }


asUITreeNodeWithInheritedOffset :
    { x : Int, y : Int }
    -> { occludedRegions : List DisplayRegion }
    -> EveOnline.MemoryReading.UITreeNode
    -> ChildOfNodeWithDisplayRegion
asUITreeNodeWithInheritedOffset inheritedOffset { occludedRegions } rawNode =
    case getDisplayRegionFromDictEntries rawNode of
        Nothing ->
            ChildWithoutRegion rawNode

        Just selfRegion ->
            ChildWithRegion
                (asUITreeNodeWithDisplayRegion
                    { selfDisplayRegion = selfRegion
                    , totalDisplayRegion =
                        { x = inheritedOffset.x + selfRegion.x
                        , y = inheritedOffset.y + selfRegion.y
                        , width = selfRegion.width
                        , height = selfRegion.height
                        }
                    , occludedRegions = occludedRegions
                    }
                    rawNode
                )


getDisplayRegionFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe DisplayRegion
getDisplayRegionFromDictEntries uiNode =
    let
        fixedNumberFromJsonValue =
            Json.Decode.decodeValue
                (Json.Decode.oneOf
                    [ jsonDecodeIntFromIntOrString
                    , Json.Decode.field "int_low32" jsonDecodeIntFromIntOrString
                    ]
                )

        fixedNumberFromPropertyName : String -> Maybe Int
        fixedNumberFromPropertyName propertyName =
            case Dict.get propertyName uiNode.dictEntriesOfInterest of
                Just jsonValue ->
                    case fixedNumberFromJsonValue jsonValue of
                        Ok number ->
                            Just number

                        Err _ ->
                            Nothing

                Nothing ->
                    Nothing
    in
    case
        ( ( fixedNumberFromPropertyName "_displayX", fixedNumberFromPropertyName "_displayY" )
        , ( fixedNumberFromPropertyName "_displayWidth", fixedNumberFromPropertyName "_displayHeight" )
        )
    of
        ( ( Just displayX, Just displayY ), ( Just displayWidth, Just displayHeight ) ) ->
            Just { x = displayX, y = displayY, width = displayWidth, height = displayHeight }

        _ ->
            Nothing


parseContextMenusFromUITreeRoot : UITreeNodeWithDisplayRegion -> List ContextMenu
parseContextMenusFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listChildrenWithDisplayRegion
            |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map String.toLower >> (==) (Just "l_menu"))
            |> List.head
    of
        Nothing ->
            []

        Just layerMenu ->
            layerMenu
                |> listChildrenWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "menu")
                |> List.map parseContextMenu


parseInfoPanelContainerFromUIRoot : UITreeNodeWithDisplayRegion -> Maybe InfoPanelContainer
parseInfoPanelContainerFromUIRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InfoPanelContainer")
            |> List.sortBy (.uiNode >> EveOnline.MemoryReading.countDescendantsInUITreeNode >> negate)
            |> List.head
    of
        Nothing ->
            Nothing

        Just containerNode ->
            Just
                { uiNode = containerNode
                , icons = parseInfoPanelIconsFromInfoPanelContainer containerNode
                , infoPanelLocationInfo = parseInfoPanelLocationInfoFromInfoPanelContainer containerNode
                , infoPanelRoute = parseInfoPanelRouteFromInfoPanelContainer containerNode
                , infoPanelAgentMissions = parseInfoPanelAgentMissionsFromInfoPanelContainer containerNode
                }


parseInfoPanelIconsFromInfoPanelContainer : UITreeNodeWithDisplayRegion -> Maybe InfoPanelIcons
parseInfoPanelIconsFromInfoPanelContainer infoPanelContainerNode =
    case
        infoPanelContainerNode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) "iconCont") >> Maybe.withDefault False)
            |> List.sortBy (.totalDisplayRegion >> .y)
            |> List.head
    of
        Nothing ->
            Nothing

        Just iconContainerNode ->
            let
                iconNodeFromTexturePathEnd texturePathEnd =
                    iconContainerNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter
                            (.uiNode
                                >> getTexturePathFromDictEntries
                                >> Maybe.map (String.endsWith texturePathEnd)
                                >> Maybe.withDefault False
                            )
                        |> List.head
            in
            Just
                { uiNode = iconContainerNode
                , search = iconNodeFromTexturePathEnd "search.png"
                , locationInfo = iconNodeFromTexturePathEnd "LocationInfo.png"
                , route = iconNodeFromTexturePathEnd "Route.png"
                , agentMissions = iconNodeFromTexturePathEnd "Missions.png"
                , dailyChallenge = iconNodeFromTexturePathEnd "dailyChallenge.png"
                }


parseInfoPanelLocationInfoFromInfoPanelContainer : UITreeNodeWithDisplayRegion -> Maybe InfoPanelLocationInfo
parseInfoPanelLocationInfoFromInfoPanelContainer infoPanelContainerNode =
    case
        infoPanelContainerNode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InfoPanelLocationInfo")
            |> List.head
    of
        Nothing ->
            Nothing

        Just infoPanelNode ->
            let
                securityStatusPercent =
                    infoPanelNode.uiNode
                        |> getAllContainedDisplayTexts
                        |> List.filterMap parseSecurityStatusPercentFromUINodeText
                        |> List.head

                currentSolarSystemName =
                    case
                        infoPanelNode.uiNode
                            |> getAllContainedDisplayTexts
                            |> List.filterMap parseCurrentSolarSystemFromUINodeText
                            |> List.head
                    of
                        Just currentSolarSystemNameOld ->
                            {-
                               Might be obsolete since the new branch introduced 2024-05-26.
                               Prevalence of this variant is unknown.
                            -}
                            Just (String.trim currentSolarSystemNameOld)

                        Nothing ->
                            infoPanelNode
                                |> listDescendantsWithDisplayRegion
                                {-
                                   2024-05-26: Observed property '_name': "headerLabelSystemName"
                                -}
                                |> List.filter
                                    (.uiNode
                                        >> getNameFromDictEntries
                                        >> Maybe.map (String.toLower >> String.contains "labelsystemname")
                                        >> Maybe.withDefault False
                                    )
                                |> List.concatMap (.uiNode >> getAllContainedDisplayTexts)
                                |> List.head

                maybeListSurroundingsButton =
                    infoPanelNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ListSurroundingsBtn")
                        |> List.head

                expandedContent =
                    infoPanelNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter
                            (\uiNode ->
                                (uiNode.uiNode.pythonObjectTypeName |> String.contains "Container")
                                    && (uiNode.uiNode |> getNameFromDictEntries |> Maybe.withDefault "" |> String.contains "mainCont")
                            )
                        |> List.head
                        |> Maybe.map
                            (\expandedContainer ->
                                { currentStationName =
                                    expandedContainer.uiNode
                                        |> getAllContainedDisplayTexts
                                        |> List.filterMap parseCurrentStationNameFromInfoPanelLocationInfoLabelText
                                        |> List.head
                                }
                            )
            in
            maybeListSurroundingsButton
                |> Maybe.map
                    (\listSurroundingsButton ->
                        { uiNode = infoPanelNode
                        , listSurroundingsButton = listSurroundingsButton
                        , currentSolarSystemName = currentSolarSystemName
                        , securityStatusPercent = securityStatusPercent
                        , expandedContent = expandedContent
                        }
                    )


parseSecurityStatusPercentFromUINodeText : String -> Maybe Int
parseSecurityStatusPercentFromUINodeText =
    Maybe.Extra.oneOf
        [ getSubstringBetweenXmlTagsAfterMarker "hint='Security status'"
        , getSubstringBetweenXmlTagsAfterMarker "hint=\"Security status\"><color="
        ]
        >> Maybe.andThen (String.trim >> String.toFloat)
        >> Maybe.map ((*) 100 >> round)


parseCurrentSolarSystemFromUINodeText : String -> Maybe String
parseCurrentSolarSystemFromUINodeText =
    Maybe.Extra.oneOf
        [ getSubstringBetweenXmlTagsAfterMarker "alt='Current Solar System'"
        , getSubstringBetweenXmlTagsAfterMarker "alt=\"Current Solar System\""
        ]


parseCurrentStationNameFromInfoPanelLocationInfoLabelText : String -> Maybe String
parseCurrentStationNameFromInfoPanelLocationInfoLabelText =
    getSubstringBetweenXmlTagsAfterMarker "alt='Current Station'"
        >> Maybe.map String.trim


parseInfoPanelRouteFromInfoPanelContainer : UITreeNodeWithDisplayRegion -> Maybe InfoPanelRoute
parseInfoPanelRouteFromInfoPanelContainer infoPanelContainerNode =
    case
        infoPanelContainerNode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InfoPanelRoute")
            |> List.head
    of
        Nothing ->
            Nothing

        Just infoPanelRouteNode ->
            let
                routeElementMarker =
                    infoPanelRouteNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "AutopilotDestinationIcon")
                        |> List.map
                            (\uiNode ->
                                { uiNode = uiNode
                                , numJumps = uiNode.uiNode |> getIntPropertyFromDictEntries "numJumps"
                                }
                            )
            in
            Just { uiNode = infoPanelRouteNode, routeElementMarker = routeElementMarker }


parseInfoPanelAgentMissionsFromInfoPanelContainer : UITreeNodeWithDisplayRegion -> Maybe InfoPanelAgentMissions
parseInfoPanelAgentMissionsFromInfoPanelContainer infoPanelContainerNode =
    case
        infoPanelContainerNode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InfoPanelAgentMissions")
            |> List.head
    of
        Nothing ->
            Nothing

        Just infoPanelNode ->
            let
                entries =
                    infoPanelNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "MissionEntry")
                        |> List.map (\uiNode -> { uiNode = uiNode })
            in
            Just
                { uiNode = infoPanelNode
                , entries = entries
                }


parseContextMenu : UITreeNodeWithDisplayRegion -> ContextMenu
parseContextMenu contextMenuUINode =
    let
        entriesUINodes =
            contextMenuUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "menuentry")

        entries =
            entriesUINodes
                |> List.map
                    (\entryUINode ->
                        let
                            text =
                                entryUINode
                                    |> listDescendantsWithDisplayRegion
                                    |> List.filterMap (.uiNode >> getDisplayText)
                                    |> List.sortBy (String.length >> negate)
                                    |> List.head
                                    |> Maybe.withDefault ""
                        in
                        { text = text
                        , uiNode = entryUINode
                        }
                    )
                |> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
    in
    { uiNode = contextMenuUINode
    , entries = entries
    }


parseShipUIFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe ShipUI
parseShipUIFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ShipUI")
            |> List.head
    of
        Nothing ->
            Nothing

        Just shipUINode ->
            case
                shipUINode
                    |> listDescendantsWithDisplayRegion
                    |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "CapacitorContainer")
                    |> List.head
            of
                Nothing ->
                    Nothing

                Just capacitorUINode ->
                    let
                        descendantNodesFromPythonObjectTypeNameEqual pythonObjectTypeName =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) pythonObjectTypeName)

                        capacitor =
                            capacitorUINode |> parseShipUICapacitorFromUINode

                        {-
                           speedGaugeElement =
                               shipUINode
                                   |> listDescendantsWithDisplayRegion
                                   |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SpeedGauge")
                                   |> List.head
                        -}
                        maybeIndicationNode =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.toLower >> String.contains "indicationcontainer") >> Maybe.withDefault False)
                                |> List.head

                        indication =
                            maybeIndicationNode
                                |> Maybe.map (parseShipUIIndication >> Just)
                                |> Maybe.withDefault Nothing

                        moduleButtons =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ShipSlot")
                                |> List.filterMap
                                    (\slotNode ->
                                        slotNode
                                            |> listDescendantsWithDisplayRegion
                                            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ModuleButton")
                                            |> List.head
                                            |> Maybe.map
                                                (\moduleButtonNode ->
                                                    parseShipUIModuleButton { slotNode = slotNode, moduleButtonNode = moduleButtonNode }
                                                )
                                    )

                        getLastValuePercentFromGaugeName gaugeName =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) gaugeName) >> Maybe.withDefault False)
                                |> List.head
                                |> Maybe.andThen (.uiNode >> .dictEntriesOfInterest >> Dict.get "_lastValue")
                                |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)
                                |> Maybe.map ((*) 100 >> round)

                        maybeHitpointsPercent =
                            case ( getLastValuePercentFromGaugeName "structureGauge", getLastValuePercentFromGaugeName "armorGauge", getLastValuePercentFromGaugeName "shieldGauge" ) of
                                ( Just structure, Just armor, Just shield ) ->
                                    Just { structure = structure, armor = armor, shield = shield }

                                _ ->
                                    Nothing

                        offensiveBuffButtons : List { uiNode : UITreeNodeWithDisplayRegion, name : String }
                        offensiveBuffButtons =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filterMap
                                    (\uiNode ->
                                        case getNameFromDictEntries uiNode.uiNode of
                                            Nothing ->
                                                Nothing

                                            Just name ->
                                                Just { uiNode = uiNode, name = name }
                                    )

                        squadronsUI =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SquadronsUI")
                                |> List.head
                                |> Maybe.map parseSquadronsUI

                        heatGauges =
                            shipUINode
                                |> listDescendantsWithDisplayRegion
                                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "HeatGauges")
                                |> List.head
                                |> Maybe.map parseShipUIHeatGaugesFromUINode
                    in
                    maybeHitpointsPercent
                        |> Maybe.map
                            (\hitpointsPercent ->
                                { uiNode = shipUINode
                                , capacitor = capacitor
                                , hitpointsPercent = hitpointsPercent
                                , indication = indication
                                , moduleButtons = moduleButtons
                                , moduleButtonsRows = groupShipUIModulesIntoRows capacitor moduleButtons
                                , offensiveBuffButtons = offensiveBuffButtons
                                , squadronsUI = squadronsUI
                                , stopButton = descendantNodesFromPythonObjectTypeNameEqual "StopButton" |> List.head
                                , maxSpeedButton = descendantNodesFromPythonObjectTypeNameEqual "MaxSpeedButton" |> List.head
                                , heatGauges = heatGauges
                                }
                            )


parseShipUIModuleButton : { slotNode : UITreeNodeWithDisplayRegion, moduleButtonNode : UITreeNodeWithDisplayRegion } -> ShipUIModuleButton
parseShipUIModuleButton { slotNode, moduleButtonNode } =
    let
        rotationFloatFromRampName rampName =
            slotNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just rampName))
                |> List.filterMap (.uiNode >> getRotationFloatFromDictEntries)
                |> List.head

        rampRotationMilli =
            case ( rotationFloatFromRampName "leftRamp", rotationFloatFromRampName "rightRamp" ) of
                ( Just leftRampRotationFloat, Just rightRampRotationFloat ) ->
                    if
                        (leftRampRotationFloat < 0 || pi * 2.01 < leftRampRotationFloat)
                            || (rightRampRotationFloat < 0 || pi * 2.01 < rightRampRotationFloat)
                    then
                        Nothing

                    else
                        Just (max 0 (min 1000 (round (1000 - ((leftRampRotationFloat + rightRampRotationFloat) * 500) / pi))))

                _ ->
                    Nothing
    in
    { uiNode = moduleButtonNode
    , slotUINode = slotNode
    , isActive =
        moduleButtonNode.uiNode.dictEntriesOfInterest
            |> Dict.get "ramp_active"
            |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.bool >> Result.toMaybe)
    , isHiliteVisible =
        slotNode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Sprite")
            |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "hilite"))
            |> List.isEmpty
            |> not
    , isBusy =
        slotNode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Sprite")
            |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "busy"))
            |> List.isEmpty
            |> not
    , rampRotationMilli = rampRotationMilli
    , stateFromDictEntries = parseShipUIModuleButtonState moduleButtonNode.uiNode
    }


{-| What a module button says about **itself**, straight out of its own
`dictEntriesOfInterest`.

The module-state fields above this one all read the slot's sprites, and #35
walked a top-row button's whole subtree to see which sprites are there. One is:
`underlay`. There is no `hilite` and no `busy` on this build, so
`isHiliteVisible` and `isBusy` cannot be anything but `False` however the module
behaves. That much of the note in CLAUDE.md was right. The conclusion drawn from
it -- that this client does not expose the state -- was not: the state is on the
button itself, as twelve dict entries nothing had ever read.

**`ramp_active` is a duty cycle, not an on/off state.** That is the correction
that matters most here, and it is measured rather than argued: 92 read-only
samples over 240s of run 9 caught the weapon's `ramp_active` flipping fourteen
times while `isInActiveState` stayed `True` throughout -- the gun never switched
off. The `False` half of that oscillation is the gap between cycles. `isActive`
reads this entry and reports it as "running", and #34 is what that costs: a
counter gated on "no gun reads as firing" resets inside every cycle, and a wait
for "the ramp to stop" is satisfied by the gap rather than by the guns going
quiet.

**Absent and `False` are different facts.** For the first ~60s of that sample no
module carried `ramp_active` at all -- not `False`, missing -- and it appeared
per module as each one first cycled. `waitingForActiveTarget` did the same later,
absent until 141s and then `0` on all four modules at once. So every field here
is a `Maybe`, and an entry that does not decode stays `Nothing` rather than
becoming a guessed `False`: only one of those two answers is safe to act on.

**Nothing decides anything from these.** The meanings above come from one 240s
window on one fit, and the leg #34 actually needed has no observations at all:
`isDeactivating` -- named for exactly the state that wait cared about -- was
never once `True`, because nothing switched a module off while the sampler ran.
`effect_activating` was seen pulsing `1` exactly once, 2.6s before a cycle
began. So these are parsed to be logged and read back, and `isActive`, `isBusy`
and `isHiliteVisible` keep the meanings they had.

Both decoders accept either JSON shape. This build sends booleans for
`ramp_active` and its neighbours and plain numbers for `waitingForActiveTarget`
and the rest, but one that sent `true` where this one sends `1` would otherwise
turn a field silently into `Nothing` -- which is the same "the signal is dead"
reading this whole issue is about.

The field names are the client's own keys, unchanged, so that a value in the log
and a value in the tree are the same name and no translation table has to be
right. Reading them costs twelve dictionary lookups on a node the caller already
holds -- no traversal, which each sprite field above does do. That is why this
takes the bare `UITreeNode` and not the node with its display region: it has
nothing to walk with.

-}
type alias ShipUIModuleButtonState =
    { ramp_active : Maybe Bool
    , isInActiveState : Maybe Bool
    , isDeactivating : Maybe Bool
    , effect_activating : Maybe Int
    , online : Maybe Bool
    , blinking : Maybe Bool
    , grey : Maybe Bool
    , quantity : Maybe Int
    , autoreload : Maybe Int
    , autorepeat : Maybe Int
    , isMaster : Maybe Bool
    , waitingForActiveTarget : Maybe Int
    }


parseShipUIModuleButtonState : EveOnline.MemoryReading.UITreeNode -> ShipUIModuleButtonState
parseShipUIModuleButtonState moduleButtonNode =
    let
        flag dictEntryKey =
            getModuleButtonStateFlagFromDictEntries dictEntryKey moduleButtonNode

        number dictEntryKey =
            getModuleButtonStateNumberFromDictEntries dictEntryKey moduleButtonNode
    in
    { ramp_active = flag "ramp_active"
    , isInActiveState = flag "isInActiveState"
    , isDeactivating = flag "isDeactivating"
    , effect_activating = number "effect_activating"
    , online = flag "online"
    , blinking = flag "blinking"
    , grey = flag "grey"
    , quantity = number "quantity"
    , autoreload = number "autoreload"
    , autorepeat = number "autorepeat"
    , isMaster = flag "isMaster"
    , waitingForActiveTarget = number "waitingForActiveTarget"
    }


getModuleButtonStateFlagFromDictEntries : String -> EveOnline.MemoryReading.UITreeNode -> Maybe Bool
getModuleButtonStateFlagFromDictEntries dictEntryKey uiNode =
    uiNode.dictEntriesOfInterest
        |> Dict.get dictEntryKey
        |> Maybe.andThen (Json.Decode.decodeValue jsonDecodeBoolFromBoolOrInt >> Result.toMaybe)


getModuleButtonStateNumberFromDictEntries : String -> EveOnline.MemoryReading.UITreeNode -> Maybe Int
getModuleButtonStateNumberFromDictEntries dictEntryKey uiNode =
    uiNode.dictEntriesOfInterest
        |> Dict.get dictEntryKey
        |> Maybe.andThen (Json.Decode.decodeValue jsonDecodeIntFromIntOrBool >> Result.toMaybe)


jsonDecodeBoolFromBoolOrInt : Json.Decode.Decoder Bool
jsonDecodeBoolFromBoolOrInt =
    Json.Decode.oneOf
        [ Json.Decode.bool
        , Json.Decode.int |> Json.Decode.map ((/=) 0)
        ]


jsonDecodeIntFromIntOrBool : Json.Decode.Decoder Int
jsonDecodeIntFromIntOrBool =
    Json.Decode.oneOf
        [ Json.Decode.int
        , Json.Decode.bool
            |> Json.Decode.map
                (\asBool ->
                    if asBool then
                        1

                    else
                        0
                )
        ]


parseShipUICapacitorFromUINode : UITreeNodeWithDisplayRegion -> ShipUICapacitor
parseShipUICapacitorFromUINode capacitorUINode =
    let
        pmarks =
            capacitorUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) "pmark") >> Maybe.withDefault False)
                |> List.map
                    (\pmarkUINode ->
                        { uiNode = pmarkUINode
                        , colorPercent = pmarkUINode.uiNode |> getColorPercentFromDictEntries
                        }
                    )

        maybePmarksFills =
            pmarks
                |> List.map (.colorPercent >> Maybe.map (\colorPercent -> colorPercent.a < 20))
                |> Maybe.Extra.combine

        levelFromPmarksPercent =
            maybePmarksFills
                |> Maybe.andThen
                    (\pmarksFills ->
                        if (pmarksFills |> List.length) < 1 then
                            Nothing

                        else
                            Just (((pmarksFills |> List.filter identity |> List.length) * 100) // (pmarksFills |> List.length))
                    )
    in
    { uiNode = capacitorUINode
    , pmarks = pmarks
    , levelFromPmarksPercent = levelFromPmarksPercent
    }


parseShipUIHeatGaugesFromUINode : UITreeNodeWithDisplayRegion -> ShipUIHeatGauges
parseShipUIHeatGaugesFromUINode gaugesUINode =
    let
        heatGaugesRotationZeroValues =
            [ -213, -108, -3 ]

        heatValuePercentFromRotationPercent rotationPercent =
            heatGaugesRotationZeroValues
                |> List.map
                    (\gaugeRotationZero ->
                        if rotationPercent <= gaugeRotationZero && gaugeRotationZero - 100 <= rotationPercent then
                            Just -(rotationPercent - gaugeRotationZero)

                        else
                            Nothing
                    )
                |> List.filterMap identity
                |> List.head

        gauges =
            gaugesUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) "heatGauge") >> Maybe.withDefault False)
                |> List.map
                    (\gaugeUiNode ->
                        let
                            rotationPercent =
                                gaugeUiNode.uiNode
                                    |> getRotationFloatFromDictEntries
                                    |> Maybe.map ((*) 100 >> round)
                        in
                        { uiNode = gaugeUiNode
                        , rotationPercent = rotationPercent
                        , heatPercent = rotationPercent |> Maybe.andThen heatValuePercentFromRotationPercent
                        }
                    )
    in
    { uiNode = gaugesUINode
    , gauges = gauges
    }


groupShipUIModulesIntoRows :
    ShipUICapacitor
    -> List ShipUIModuleButton
    -> { top : List ShipUIModuleButton, middle : List ShipUIModuleButton, bottom : List ShipUIModuleButton }
groupShipUIModulesIntoRows capacitor modules =
    let
        verticalDistanceThreshold =
            20

        verticalCenterOfUINode uiNode =
            uiNode.totalDisplayRegion.y + uiNode.totalDisplayRegion.height // 2

        capacitorVerticalCenter =
            verticalCenterOfUINode capacitor.uiNode
    in
    modules
        |> List.foldr
            (\shipModule previousRows ->
                if verticalCenterOfUINode shipModule.uiNode < capacitorVerticalCenter - verticalDistanceThreshold then
                    { previousRows | top = shipModule :: previousRows.top }

                else if verticalCenterOfUINode shipModule.uiNode > capacitorVerticalCenter + verticalDistanceThreshold then
                    { previousRows | bottom = shipModule :: previousRows.bottom }

                else
                    { previousRows | middle = shipModule :: previousRows.middle }
            )
            { top = [], middle = [], bottom = [] }


parseShipUIIndication : UITreeNodeWithDisplayRegion -> ShipUIIndication
parseShipUIIndication indicationUINode =
    let
        displayTexts =
            indicationUINode.uiNode |> getAllContainedDisplayTexts

        maneuverType =
            [ ( "Warp", ManeuverWarp )
            , ( "Jump", ManeuverJump )
            , ( "Orbit", ManeuverOrbit )
            , ( "Approach", ManeuverApproach )
            , ( "Range", ManeuverRange )
            , ( "Aligning", ManeuverAlign )

            -- Sample `session-2022-05-23T23-00-32-87ba97.zip` shared by Abaddon at https://forum.botlab.org/t/i-want-to-add-korean-support-on-eve-online-bot-what-should-i-do/4370/9
            , ( "워프 드라이브 가동", ManeuverWarp )

            -- Sample `session-2022-05-26T03-13-42-83df2b.zip` shared by Abaddon at https://forum.botlab.org/t/i-want-to-add-korean-support-on-eve-online-bot-what-should-i-do/4370/14
            , ( "점프 중", ManeuverJump )
            ]
                |> List.filterMap
                    (\( pattern, candidateManeuverType ) ->
                        if displayTexts |> List.any (String.contains pattern) then
                            Just candidateManeuverType

                        else
                            Nothing
                    )
                |> List.head
    in
    { uiNode = indicationUINode, maneuverType = maneuverType }


parseSquadronsUI : UITreeNodeWithDisplayRegion -> SquadronsUI
parseSquadronsUI squadronsUINode =
    { uiNode = squadronsUINode
    , squadrons =
        squadronsUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SquadronUI")
            |> List.map parseSquadronUI
    }


parseSquadronUI : UITreeNodeWithDisplayRegion -> SquadronUI
parseSquadronUI squadronUINode =
    { uiNode = squadronUINode
    , abilities =
        squadronUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "AbilityIcon")
            |> List.map parseSquadronAbilityIcon
    , actionLabel =
        squadronUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SquadronActionLabel")
            |> List.head
    }


parseSquadronAbilityIcon : UITreeNodeWithDisplayRegion -> SquadronAbilityIcon
parseSquadronAbilityIcon abilityIconUINode =
    { uiNode = abilityIconUINode
    , quantity =
        abilityIconUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.toLower >> String.contains "quantity") >> Maybe.withDefault False)
            |> List.concatMap (.uiNode >> getAllContainedDisplayTexts)
            |> List.head
            |> Maybe.andThen (String.trim >> String.toInt)
    , ramp_active =
        abilityIconUINode.uiNode.dictEntriesOfInterest
            |> Dict.get "ramp_active"
            |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.bool >> Result.toMaybe)
    }


parseTargetsFromUITreeRoot : UITreeNodeWithDisplayRegion -> List Target
parseTargetsFromUITreeRoot =
    listDescendantsWithDisplayRegion
        >> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "TargetInBar")
        >> List.map parseTarget


parseTarget : UITreeNodeWithDisplayRegion -> Target
parseTarget targetNode =
    let
        textsTopToBottom =
            targetNode
                |> getAllContainedDisplayTextsWithRegion
                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> .y)
                |> List.map Tuple.first

        barAndImageCont =
            targetNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "barAndImageCont"))
                |> List.head

        isActiveTarget =
            targetNode.uiNode
                |> EveOnline.MemoryReading.listDescendantsInUITreeNode
                |> List.any
                    (\node ->
                        -- 'ActiveTargetOnBracket' was the class name in an
                        -- older game client; the current one renamed it to
                        -- 'ActiveTargetIndicator'. Checking both since which
                        -- name shows up isn't otherwise load-bearing.
                        (node.pythonObjectTypeName == "ActiveTargetOnBracket")
                            || (node.pythonObjectTypeName == "ActiveTargetIndicator")
                    )

        assignedContainerNode =
            targetNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.toLower >> String.contains "assigned") >> Maybe.withDefault False)
                |> List.sortBy (.totalDisplayRegion >> .width)
                |> List.head

        assignedIcons =
            assignedContainerNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (\uiNode -> [ "Sprite", "Icon" ] |> List.member uiNode.uiNode.pythonObjectTypeName)
    in
    { uiNode = targetNode
    , barAndImageCont = barAndImageCont
    , hitpointsPercent = parseTargetHitpointsPercent targetNode
    , textsTopToBottom = textsTopToBottom
    , isActiveTarget = isActiveTarget
    , assignedContainerNode = assignedContainerNode
    , assignedIcons = assignedIcons
    }


{-| What the target bar's three rings say about the thing being shot at.

**The rings carry no width to take a ratio of**, which is what makes this
unlike `DronesWindowEntryDroneStructure.hitpointsPercent` next door. Read live
with targets locked, every node under a `TargetInBar`'s `TargetHealthBars` --
the `shieldBar`, `armorBar` and `hullBar` containers, each one's `_Left` and
`_Right` sprite, and `healthBarBackground` -- reports the identical 141x141
region, the bounding box of the whole ring. The two sprites per bar are the two
halves of a circle (`shieldLeft.png` and `shieldRight.png`, with `baseRotation`
0 and -3pi/4), so the fraction is drawn by rotating an arc and never appears in
a display region at all. A ratio of widths here answers 0% for a full shield.

The client stores the fraction itself, as `lastState` on the named container,
which makes this `ShipUI`'s `_lastValue` read rather than the drone's geometry.
Watched changing under fire on one `Centii Plague`: `shieldBar` went 1 ->
0.8089 -> 4.39e-06 as the shield collapsed and then climbed back through
1.88e-05, 4.29e-05 and 1.24e-04 as it regenerated, with `armorBar` going 1 ->
0.2484 in the same window and `hullBar` still at 1. So the three layers move
independently and separately, which is the whole point of reading all three: a
shot doing nothing is a shield that does not move while armour and hull sit at
100%, and one combined figure hides exactly that.

**All three or none.** `Nothing` is a target whose bars this reading could not
read, and it must not be rendered as `0%` anywhere -- a fabricated zero is a
hull about to explode as far as any later rule is concerned, which is
`loadRefusalFromGameLog`'s rule about absent evidence applied to a gauge.

The value is **not** clamped or filtered. `ShipUI.hitpointsPercent` is the same
kind of read and CLAUDE.md records it producing -1021821% and 2132822% for
single readings; a garbage value silently clamped to 0 or 100 reads exactly like
a real one, and nothing acts on this field yet, so an operator seeing the raw
number is the only way a run can show whether it reads sanely.

-}
parseTargetHitpointsPercent : UITreeNodeWithDisplayRegion -> Maybe Hitpoints
parseTargetHitpointsPercent targetNode =
    let
        barPercentFromContainerName containerName =
            targetNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just containerName))
                |> List.head
                |> Maybe.andThen (.uiNode >> .dictEntriesOfInterest >> Dict.get "lastState")
                |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)
                |> Maybe.map ((*) 100 >> round)
    in
    Maybe.map3
        (\shield armor structure -> { shield = shield, armor = armor, structure = structure })
        (barPercentFromContainerName "shieldBar")
        (barPercentFromContainerName "armorBar")
        (barPercentFromContainerName "hullBar")


parseOverviewWindowsFromUITreeRoot : UITreeNodeWithDisplayRegion -> List OverviewWindow
parseOverviewWindowsFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter
            (.uiNode
                >> .pythonObjectTypeName
                >> (List.member >> (|>) [ "OverView", "OverviewWindow", "OverviewWindowOld" ])
            )
        |> List.map parseOverviewWindow


parseOverviewWindow : UITreeNodeWithDisplayRegion -> OverviewWindow
parseOverviewWindow overviewWindowNode =
    let
        scrollNode =
            overviewWindowNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "scroll")
                |> List.head

        scrollControlsNode =
            let
                scrollDescendants =
                    scrollNode
                        |> Maybe.map listDescendantsWithDisplayRegion
                        |> Maybe.withDefault []
            in
            {- This client build has no node type containing "ScrollControls":
               the overview's scrollbar is a plain `Scrollbar` holding a
               `ScrollHandle`, so the original lookup always returned Nothing
               and the window looked unscrollable. Fall back to the Scrollbar,
               whose descendants include the handle `parseScrollControls`
               looks for, keeping the original match first for builds that do
               use that type.
            -}
            (scrollDescendants
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "ScrollControls")
                |> List.head
            )
                |> Maybe.Extra.or
                    (scrollDescendants
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Scrollbar")
                        |> List.head
                    )

        headersContainerNode =
            scrollNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "headers")
                |> List.head

        entriesHeaders =
            headersContainerNode
                |> Maybe.map getAllContainedDisplayTextsWithRegion
                |> Maybe.withDefault []

        entries =
            overviewWindowNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "OverviewScrollEntry")
                |> List.map (parseOverviewWindowEntry entriesHeaders)
    in
    { uiNode = overviewWindowNode
    , entriesHeaders = entriesHeaders
    , entries = entries
    , scrollControls = scrollControlsNode |> Maybe.map parseScrollControls
    }


parseOverviewWindowEntry : List ( String, UITreeNodeWithDisplayRegion ) -> UITreeNodeWithDisplayRegion -> OverviewWindowEntry
parseOverviewWindowEntry entriesHeaders overviewEntryNode =
    let
        textsLeftToRight =
            overviewEntryNode
                |> getAllContainedDisplayTextsWithRegion
                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> .x)
                |> List.map Tuple.first

        listViewEntry =
            parseListViewEntry entriesHeaders overviewEntryNode

        objectDistance =
            listViewEntry.cellsTexts
                |> Dict.get "Distance"

        objectDistanceInMeters =
            objectDistance
                |> Maybe.map parseOverviewEntryDistanceInMetersFromText
                |> Maybe.withDefault (Err "Did not find the 'Distance' cell text.")

        spaceObjectIconNode =
            overviewEntryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SpaceObjectIcon")
                |> List.head

        iconSpriteColorPercent =
            spaceObjectIconNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "iconSprite"))
                |> List.head
                |> Maybe.andThen (.uiNode >> getColorPercentFromDictEntries)

        namesUnderSpaceObjectIcon =
            spaceObjectIconNode
                |> Maybe.map (.uiNode >> EveOnline.MemoryReading.listDescendantsInUITreeNode)
                |> Maybe.withDefault []
                |> List.filterMap getNameFromDictEntries
                |> Set.fromList

        bgColorFillsPercent =
            overviewEntryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Fill")
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) "bgColor") >> Maybe.withDefault False)
                |> List.filterMap (\fillUiNode -> fillUiNode.uiNode |> getColorPercentFromDictEntries)

        rightAlignedIconsHints =
            overviewEntryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) "rightAlignedIconContainer") >> Maybe.withDefault False)
                |> List.concatMap listDescendantsWithDisplayRegion
                |> List.filterMap (.uiNode >> getHintTextFromDictEntries)

        rightAlignedIconsHintsContainsTextIgnoringCase textToSearch =
            rightAlignedIconsHints |> List.any (String.toLower >> String.contains (textToSearch |> String.toLower))

        commonIndications =
            { targeting = namesUnderSpaceObjectIcon |> Set.member "targeting"
            , targetedByMe = namesUnderSpaceObjectIcon |> Set.member "targetedByMeIndicator"
            , isJammingMe = rightAlignedIconsHintsContainsTextIgnoringCase "is jamming me"
            , isWarpDisruptingMe = rightAlignedIconsHintsContainsTextIgnoringCase "is warp disrupting me"
            , isTrackingDisruptingMe = rightAlignedIconsHintsContainsTextIgnoringCase "is tracking disrupting me"
            , isSensorDampeningMe = rightAlignedIconsHintsContainsTextIgnoringCase "is sensor dampening me"
            }

        opacityPercent =
            overviewEntryNode.uiNode
                |> getOpacityFloatFromDictEntries
                |> Maybe.map ((*) 100 >> round)
    in
    { uiNode = overviewEntryNode
    , textsLeftToRight = textsLeftToRight
    , cellsTexts = listViewEntry.cellsTexts
    , objectDistance = objectDistance
    , objectDistanceInMeters = objectDistanceInMeters
    , objectName = listViewEntry.cellsTexts |> Dict.get "Name"
    , objectType = listViewEntry.cellsTexts |> Dict.get "Type"
    , objectAlliance = listViewEntry.cellsTexts |> Dict.get "Alliance"
    , iconSpriteColorPercent = iconSpriteColorPercent
    , namesUnderSpaceObjectIcon = namesUnderSpaceObjectIcon
    , bgColorFillsPercent = bgColorFillsPercent
    , rightAlignedIconsHints = rightAlignedIconsHints
    , commonIndications = commonIndications
    , opacityPercent = opacityPercent
    , objectItemID =
        -- EVE's own id for the object this row refers to, kept as text: it is
        -- ~9e18, past what a JSON number survives intact (see tree_walker's
        -- emit_integer_json). Used to remember which wrecks have already been
        -- opened, since nothing about a row's text distinguishes an emptied
        -- wreck from a full one.
        overviewEntryNode.uiNode.dictEntriesOfInterest
            |> Dict.get "itemID"
            |> Maybe.andThen
                (Json.Decode.decodeValue
                    (Json.Decode.oneOf
                        [ Json.Decode.string
                        , Json.Decode.int |> Json.Decode.map String.fromInt
                        ]
                    )
                    >> Result.toMaybe
                )
    }


parseOverviewEntryDistanceInMetersFromText : String -> Result String Int
parseOverviewEntryDistanceInMetersFromText distanceDisplayTextBeforeTrim =
    case distanceDisplayTextBeforeTrim |> String.trim |> String.split " " |> List.reverse of
        unitText :: reversedNumberTexts ->
            case parseDistanceUnitInMeters unitText of
                Nothing ->
                    Err ("Failed to parse distance unit text of '" ++ unitText ++ "'")

                Just unitInMeters ->
                    case
                        reversedNumberTexts |> List.reverse |> String.join " " |> parseNumberTruncatingAfterOptionalDecimalSeparator
                    of
                        Err parseNumberError ->
                            Err ("Failed to parse number: " ++ parseNumberError)

                        Ok parsedNumber ->
                            Ok (parsedNumber * unitInMeters)

        _ ->
            Err "Expecting at least one whitespace character separating number and unit."


parseDistanceUnitInMeters : String -> Maybe Int
parseDistanceUnitInMeters unitText =
    case String.trim unitText of
        "m" ->
            Just 1

        "km" ->
            Just 1000

        _ ->
            Nothing


parseSelectedItemWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe SelectedItemWindow
parseSelectedItemWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        -- The macOS client names this window 'SelectedItemWnd'; 'ActiveItem' is
        -- the name the upstream parser was written against and matches nothing
        -- here, which read as "no panel" rather than as an error.
        |> List.filter
            (.uiNode
                >> .pythonObjectTypeName
                >> (\typeName -> List.member typeName [ "ActiveItem", "SelectedItemWnd" ])
            )
        |> List.head
        |> Maybe.map parseSelectedItemWindow


parseSelectedItemWindow : UITreeNodeWithDisplayRegion -> SelectedItemWindow
parseSelectedItemWindow windowNode =
    let
        actionButtonFromTexturePathEnding texturePathEnding =
            windowNode
                |> listDescendantsWithDisplayRegion
                |> List.filter
                    (.uiNode
                        >> getTexturePathFromDictEntries
                        >> Maybe.map (String.toLower >> String.endsWith (String.toLower texturePathEnding))
                        >> Maybe.withDefault False
                    )
                |> List.head

        orbitButton =
            actionButtonFromTexturePathEnding "44_32_21.png"
    in
    { uiNode = windowNode, orbitButton = orbitButton }


parseDronesWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe DronesWindow
parseDronesWindowFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter
                (.uiNode
                    >> .pythonObjectTypeName
                    >> (List.member >> (|>) [ "DroneView", "DronesWindow" ])
                )
            |> List.head
    of
        Nothing ->
            Nothing

        Just windowNode ->
            let
                {-
                   scrollNode =
                       windowNode
                           |> listDescendantsWithDisplayRegion
                           |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "scroll")
                           |> List.head
                -}
                droneGroupHeaders =
                    windowNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "DroneGroupHeader")
                        |> List.filterMap parseDronesWindowDroneGroupHeader

                droneEntries =
                    windowNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter
                            (.uiNode
                                >> .pythonObjectTypeName
                                >> (\pythonTypeName ->
                                        {-
                                           2023-01-02 Observed: 'DroneInBayEntry'
                                        -}
                                        String.startsWith "Drone" pythonTypeName
                                            && String.endsWith "Entry" pythonTypeName
                                   )
                            )
                        |> List.map parseDronesWindowDroneEntry

                droneGroups =
                    [ droneEntries |> List.map DronesWindowEntryDrone
                    , droneGroupHeaders
                        |> List.map (\header -> { header = header, children = [] })
                        |> List.map DronesWindowEntryGroup
                    ]
                        |> List.concat
                        |> dronesGroupTreesFromFlatListOfEntries

                droneGroupFromHeaderTextPart headerTextPart =
                    droneGroups
                        |> List.filter (.header >> .mainText >> Maybe.withDefault "" >> String.toLower >> String.contains (headerTextPart |> String.toLower))
                        |> List.sortBy (.header >> .mainText >> Maybe.map String.length >> Maybe.withDefault 999)
                        |> List.head
            in
            Just
                { uiNode = windowNode
                , droneGroups = droneGroups
                , droneGroupInBay = droneGroupFromHeaderTextPart "in bay"
                , droneGroupInSpace = droneGroupFromHeaderTextPart "in space"
                }


dronesGroupTreesFromFlatListOfEntries : List DronesWindowEntry -> List DronesWindowEntryGroupStructure
dronesGroupTreesFromFlatListOfEntries entriesBeforeOrdering =
    let
        verticalOffsetFromEntry entry =
            case entry of
                DronesWindowEntryDrone droneEntry ->
                    droneEntry.uiNode.totalDisplayRegion.y

                DronesWindowEntryGroup groupEntry ->
                    groupEntry.header.uiNode.totalDisplayRegion.y

        entriesOrderedVertically =
            entriesBeforeOrdering
                |> List.sortBy verticalOffsetFromEntry
    in
    entriesOrderedVertically
        |> List.filterMap
            (\entry ->
                case entry of
                    DronesWindowEntryDrone _ ->
                        Nothing

                    DronesWindowEntryGroup group ->
                        Just group
            )
        |> List.head
        |> Maybe.map
            (\topmostGroupEntry ->
                let
                    entriesUpToSibling =
                        entriesOrderedVertically
                            |> List.Extra.dropWhile
                                (verticalOffsetFromEntry
                                    >> (\offset -> offset <= verticalOffsetFromEntry (DronesWindowEntryGroup topmostGroupEntry))
                                )
                            |> List.Extra.takeWhile
                                (\entry ->
                                    case entry of
                                        DronesWindowEntryDrone _ ->
                                            True

                                        DronesWindowEntryGroup group ->
                                            topmostGroupEntry.header.uiNode.totalDisplayRegion.x
                                                < (group.header.uiNode.totalDisplayRegion.x - 3)
                                )

                    childGroupTrees =
                        dronesGroupTreesFromFlatListOfEntries entriesUpToSibling

                    childDrones =
                        entriesUpToSibling
                            |> List.Extra.takeWhile
                                (\entry ->
                                    case entry of
                                        DronesWindowEntryDrone _ ->
                                            True

                                        DronesWindowEntryGroup _ ->
                                            False
                                )

                    children =
                        [ childDrones, childGroupTrees |> List.map DronesWindowEntryGroup ]
                            |> List.concat
                            |> List.sortBy verticalOffsetFromEntry

                    topmostGroupTree =
                        { header = topmostGroupEntry.header
                        , children = children
                        }

                    bottommostDescendantOffset =
                        enumerateDescendantsOfDronesGroup topmostGroupTree
                            |> List.map verticalOffsetFromEntry
                            |> List.maximum
                            |> Maybe.withDefault (verticalOffsetFromEntry (DronesWindowEntryGroup topmostGroupTree))

                    entriesBelow =
                        entriesOrderedVertically
                            |> List.Extra.dropWhile (verticalOffsetFromEntry >> (\offset -> offset <= bottommostDescendantOffset))
                in
                topmostGroupTree :: dronesGroupTreesFromFlatListOfEntries entriesBelow
            )
        |> Maybe.withDefault []


enumerateAllDronesFromDronesGroup : DronesWindowEntryGroupStructure -> List DronesWindowEntryDroneStructure
enumerateAllDronesFromDronesGroup =
    enumerateDescendantsOfDronesGroup
        >> List.filterMap
            (\entry ->
                case entry of
                    DronesWindowEntryDrone drone ->
                        Just drone

                    DronesWindowEntryGroup _ ->
                        Nothing
            )


enumerateDescendantsOfDronesGroup : DronesWindowEntryGroupStructure -> List DronesWindowEntry
enumerateDescendantsOfDronesGroup group =
    group.children
        |> List.concatMap
            (\child ->
                case child of
                    DronesWindowEntryDrone _ ->
                        [ child ]

                    DronesWindowEntryGroup childGroup ->
                        child :: enumerateDescendantsOfDronesGroup childGroup
            )


parseDronesWindowDroneGroupHeader : UITreeNodeWithDisplayRegion -> Maybe DronesWindowDroneGroupHeader
parseDronesWindowDroneGroupHeader groupHeaderUiNode =
    case
        groupHeaderUiNode
            |> getAllContainedDisplayTextsWithRegion
            |> List.sortBy (Tuple.second >> .totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0)
            |> List.map Tuple.first
            |> List.head
    of
        Nothing ->
            Nothing

        Just mainText ->
            let
                quantityFromTitle =
                    mainText
                        |> parseQuantityFromDroneGroupTitleText
                        |> Result.withDefault Nothing
            in
            Just
                { uiNode = groupHeaderUiNode
                , mainText = Just mainText
                , quantityFromTitle = quantityFromTitle
                }


parseQuantityFromDroneGroupTitleText : String -> Result String (Maybe DronesWindowDroneGroupHeaderQuantity)
parseQuantityFromDroneGroupTitleText droneGroupTitleText =
    case droneGroupTitleText |> String.split "(" |> List.drop 1 of
        [] ->
            Ok Nothing

        [ textAfterOpeningParenthesis ] ->
            case textAfterOpeningParenthesis |> String.split ")" |> List.head of
                Nothing ->
                    Err "Missing closing parens"

                Just textInParens ->
                    case
                        textInParens
                            |> String.split "/"
                            |> List.map String.trim
                            |> List.map
                                (\numberText ->
                                    numberText
                                        |> String.toInt
                                        |> Result.fromMaybe ("Failed to parse to integer from '" ++ numberText ++ "'")
                                )
                            |> Result.Extra.combine
                    of
                        Err err ->
                            Err ("Failed to parse numbers in parentheses: " ++ err)

                        Ok integersInParens ->
                            case integersInParens of
                                [ singleNumber ] ->
                                    Ok (Just { current = singleNumber, maximum = Nothing })

                                [ firstNumber, secondNumber ] ->
                                    Ok (Just { current = firstNumber, maximum = Just secondNumber })

                                _ ->
                                    Err "Found unexpected number of numbers in parentheses."

        _ ->
            Err "Found unexpected number of parentheses."


parseDronesWindowDroneEntry : UITreeNodeWithDisplayRegion -> DronesWindowEntryDroneStructure
parseDronesWindowDroneEntry droneEntryNode =
    let
        mainText =
            droneEntryNode
                |> getAllContainedDisplayTextsWithRegion
                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0)
                |> List.map Tuple.first
                |> List.head

        gaugeValuePercentFromContainerName containerName =
            droneEntryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just containerName))
                |> List.head
                |> Maybe.andThen
                    (\gaugeNode ->
                        let
                            gaudeDescendantFromName gaugeDescendantName =
                                gaugeNode
                                    |> listDescendantsWithDisplayRegion
                                    |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just gaugeDescendantName))
                                    |> List.head
                        in
                        gaudeDescendantFromName "droneGaugeBar"
                            |> Maybe.andThen
                                (\gaugeBar ->
                                    gaudeDescendantFromName "droneGaugeBarDmg"
                                        |> Maybe.map
                                            (\droneGaugeBarDmg ->
                                                ((gaugeBar.totalDisplayRegion.width - droneGaugeBarDmg.totalDisplayRegion.width) * 100)
                                                    // gaugeBar.totalDisplayRegion.width
                                            )
                                )
                    )

        hitpointsPercent =
            gaugeValuePercentFromContainerName "gauge_shield"
                |> Maybe.andThen
                    (\shieldPercent ->
                        gaugeValuePercentFromContainerName "gauge_armor"
                            |> Maybe.andThen
                                (\armorPercent ->
                                    gaugeValuePercentFromContainerName "gauge_struct"
                                        |> Maybe.map
                                            (\structPercent ->
                                                { shield = shieldPercent
                                                , armor = armorPercent
                                                , structure = structPercent
                                                }
                                            )
                                )
                    )
    in
    { uiNode = droneEntryNode
    , mainText = mainText
    , hitpointsPercent = hitpointsPercent
    }


parseProbeScannerWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe ProbeScannerWindow
parseProbeScannerWindowFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ProbeScannerWindow")
            |> List.head
    of
        Nothing ->
            Nothing

        Just windowNode ->
            let
                scanResultsNodes =
                    windowNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ScanResultNew")

                scrollNode =
                    windowNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.contains "ResultsContainer") >> Maybe.withDefault False)
                        |> List.concatMap listDescendantsWithDisplayRegion
                        |> List.filter
                            (\node ->
                                (node.uiNode.pythonObjectTypeName |> String.toLower |> String.contains "scroll")
                                    || (node.uiNode
                                            |> getNameFromDictEntries
                                            |> Maybe.map (String.toLower >> String.contains "scroll")
                                            |> Maybe.withDefault False
                                       )
                            )
                        |> List.head

                headersContainerNode =
                    scrollNode

                entriesHeaders =
                    headersContainerNode
                        |> Maybe.map getAllContainedDisplayTextsWithRegion
                        |> Maybe.withDefault []

                scanResults =
                    scanResultsNodes
                        |> List.map (parseProbeScanResult entriesHeaders)
            in
            Just { uiNode = windowNode, scanResults = scanResults }


parseProbeScanResult : List ( String, UITreeNodeWithDisplayRegion ) -> UITreeNodeWithDisplayRegion -> ProbeScanResult
parseProbeScanResult entriesHeaders scanResultNode =
    let
        textsLeftToRight =
            scanResultNode
                |> getAllContainedDisplayTextsWithRegion
                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> .x)
                |> List.map Tuple.first

        cellsTexts =
            scanResultNode
                |> getAllContainedDisplayTextsWithRegion
                |> List.filterMap
                    (\( cellText, cell ) ->
                        let
                            cellMiddle =
                                cell.totalDisplayRegion.x + (cell.totalDisplayRegion.width // 2)

                            maybeHeader =
                                entriesHeaders
                                    |> List.filter
                                        (\( _, header ) ->
                                            header.totalDisplayRegion.x
                                                < cellMiddle
                                                + 1
                                                && cellMiddle
                                                < header.totalDisplayRegion.x
                                                + header.totalDisplayRegion.width
                                                - 1
                                        )
                                    |> List.head
                        in
                        maybeHeader
                            |> Maybe.map (\( headerText, _ ) -> ( headerText, cellText ))
                    )
                |> Dict.fromList

        warpButton =
            scanResultNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getTexturePathFromDictEntries >> Maybe.map (String.endsWith "44_32_18.png") >> Maybe.withDefault False)
                |> List.head
    in
    { uiNode = scanResultNode
    , textsLeftToRight = textsLeftToRight
    , cellsTexts = cellsTexts
    , warpButton = warpButton
    }


parseDirectionalScannerWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe DirectionalScannerWindow
parseDirectionalScannerWindowFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "DirectionalScanner")
            |> List.head
    of
        Nothing ->
            Nothing

        Just windowNode ->
            let
                scrollNode =
                    windowNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "scroll")
                        |> List.sortBy (.totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0 >> negate)
                        |> List.head

                scanResultsNodes =
                    scrollNode
                        |> Maybe.map listDescendantsWithDisplayRegion
                        |> Maybe.withDefault []
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "DirectionalScanResultEntry")
            in
            Just
                { uiNode = windowNode
                , scrollNode = scrollNode
                , scanResults = scanResultsNodes
                }


parseStationWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe StationWindow
parseStationWindowFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "LobbyWnd")
            |> List.head
    of
        Nothing ->
            Nothing

        Just windowNode ->
            let
                buttonFromDisplayText textToSearch =
                    let
                        textToSearchLowercase =
                            String.toLower textToSearch

                        textMatches text =
                            text == textToSearchLowercase || (text |> String.contains (">" ++ textToSearchLowercase ++ "<"))
                    in
                    findButtonInDescendantsByDisplayTextsPredicate
                        (List.any (String.toLower >> textMatches))
                        windowNode

                {- One button occupies this slot and it carries three labels in
                   turn: "Undock" while docked, then "Abort Undock", then
                   "Undocking...". Only the first is a button to press. Pressing
                   either of the others cancels the undock that is already under
                   way, which is the loop.

                   `buttonFromDisplayText` matches a *whole* label -- equality, or
                   the label wrapped in tags -- so "Abort Undock" matched neither
                   "undock" nor "undocking", and "Undocking..." misses the
                   `"undocking"` matcher that was plainly written for it, because
                   the ellipsis is part of the label. Both states therefore left
                   `undockButton` and `abortUndockButton` empty, which every caller
                   reads as "I do not see the undock button".

                   saxrat's run 43 spent 10,310 readings there, asking for help
                   while docked, against only 12 that reached the already-undocking
                   branch the bot already had, and clicked undock 20,486 times in
                   between. Matching "abort" alone cut that to 3 in three minutes
                   but did not free the ship: 256 clicks still met 132 waits,
                   because the third label was still invisible.

                   Matched on substrings, because these are phrases rather than
                   words and the client decorates them. "abort" is the wording the
                   mission runner's `labelUndoesStepInProgress` has flown without
                   looping; "undocking" is the word this parser already chose for
                   the same state.
                -}
                buttonUndoingTheUndock =
                    findButtonInDescendantsByDisplayTextsPredicate
                        (List.any
                            (String.toLower
                                >> (\text ->
                                        String.contains "abort" text
                                            || String.contains "undocking" text
                                   )
                            )
                        )
                        windowNode
            in
            Just
                { uiNode = windowNode
                , undockButton =
                    case buttonUndoingTheUndock of
                        Just _ ->
                            Nothing

                        Nothing ->
                            buttonFromDisplayText "undock"
                , abortUndockButton = buttonUndoingTheUndock
                , agentsTab = parseStationWindowAgentsTab windowNode
                , agentEntries = parseStationAgentEntries windowNode
                }


parseStationWindowAgentsTab : UITreeNodeWithDisplayRegion -> Maybe StationWindowTab
parseStationWindowAgentsTab windowNode =
    windowNode
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "stationInformationTabAgents"))
        |> List.head
        |> Maybe.map
            (\tabNode ->
                { uiNode = tabNode
                , isSelected =
                    tabNode.uiNode.dictEntriesOfInterest
                        |> Dict.get "_selected"
                        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.bool >> Result.toMaybe)
                        |> Maybe.withDefault False
                }
            )


{-| The Agents panel groups its entries under "Available to you" /
"Not available to you" headers by _ordering_ only -- the entries are
siblings of the headers, not children of them -- so which group an entry
belongs to has to be recovered by comparing vertical positions against the
headers above it.
-}
parseStationAgentEntries : UITreeNodeWithDisplayRegion -> List StationAgentEntry
parseStationAgentEntries windowNode =
    let
        descendants =
            windowNode |> listDescendantsWithDisplayRegion

        headers =
            descendants
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Header")
                |> List.filterMap
                    (\headerNode ->
                        headerNode.uiNode
                            |> getAllContainedDisplayTexts
                            |> List.head
                            |> Maybe.map (\text -> ( headerNode.totalDisplayRegion.y, text ))
                    )

        isUnderAvailableHeader entryY =
            headers
                |> List.filter (\( headerY, _ ) -> headerY <= entryY)
                |> List.sortBy (Tuple.first >> negate)
                |> List.head
                |> Maybe.map (Tuple.second >> String.toLower >> String.contains "not available" >> not)
                -- No header at all above the entry: treat it as available
                -- rather than silently skipping every agent in the station.
                |> Maybe.withDefault True
    in
    descendants
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "AgentEntry")
        |> List.map
            (\entryNode ->
                { uiNode = entryNode
                , name = entryNode.uiNode |> getNameFromDictEntries
                , agentType = entryNode.uiNode |> getStringPropertyFromDictEntries "agentType"
                , missionState = entryNode.uiNode |> getStringPropertyFromDictEntries "missionState"
                , agentLocation = entryNode.uiNode |> getStringPropertyFromDictEntries "agentLocation"
                , characterID =
                    entryNode.uiNode.dictEntriesOfInterest
                        |> Dict.get "charID"
                        |> Maybe.andThen (Json.Decode.decodeValue jsonDecodeIntFromIntOrString >> Result.toMaybe)
                , conversationButton =
                    entryNode
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "AgentConversationIcon")
                        |> List.head
                , isAvailable = isUnderAvailableHeader entryNode.totalDisplayRegion.y
                }
            )


{-| The ship cards in the station's Hangars/Ships panel.

Found by node type anywhere under the root, rather than scoped to the panel
that holds them, because no reading has been captured that says which container
that panel is -- and a wrong container filter would not fail loudly here, it
would report no cards at all and leave the bot blind to a card plainly on
screen. `reload_drones.py` locates the card the same way and works.

`mainText` is the widest text on the card, which is the ship's name; it is for
the decision log rather than for choosing between cards.

-}
parseShipItemCardsFromUITreeRoot : UITreeNodeWithDisplayRegion -> List ShipItemCard
parseShipItemCardsFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ShipItemCard")
        |> List.map
            (\cardNode ->
                { uiNode = cardNode
                , mainText =
                    cardNode
                        |> getAllContainedDisplayTextsWithRegion
                        |> List.sortBy (Tuple.second >> .totalDisplayRegion >> .width >> negate)
                        |> List.head
                        |> Maybe.map Tuple.first
                }
            )


parseInventoryWindowsFromUITreeRoot : UITreeNodeWithDisplayRegion -> List InventoryWindow
parseInventoryWindowsFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (\uiNode -> [ "InventoryPrimary", "ActiveShipCargo" ] |> List.member uiNode.uiNode.pythonObjectTypeName)
        |> List.map parseInventoryWindow


parseInventoryWindow : UITreeNodeWithDisplayRegion -> InventoryWindow
parseInventoryWindow windowUiNode =
    let
        selectedContainerCapacityGaugeNode =
            windowUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "CapacityGauge")
                |> List.head

        selectedContainerCapacityGauge =
            selectedContainerCapacityGaugeNode
                |> Maybe.map (.uiNode >> EveOnline.MemoryReading.listDescendantsInUITreeNode)
                |> Maybe.withDefault []
                |> List.filterMap getDisplayText
                |> List.sortBy (String.length >> negate)
                |> List.head
                |> Maybe.map parseInventoryCapacityGaugeText

        leftTreeEntriesRootNodes =
            windowUiNode |> getContainedTreeViewEntryRootNodes

        leftTreeEntries =
            leftTreeEntriesRootNodes |> List.map parseInventoryWindowTreeViewEntry

        rightContainerNode =
            windowUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter
                    (\uiNode ->
                        (uiNode.uiNode.pythonObjectTypeName == "Container")
                            && (uiNode.uiNode |> getNameFromDictEntries |> Maybe.map (String.contains "right") |> Maybe.withDefault False)
                    )
                |> List.head

        subCaptionLabelText =
            rightContainerNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.startsWith "subCaptionLabel") >> Maybe.withDefault False)
                |> List.concatMap (.uiNode >> getAllContainedDisplayTexts)
                |> List.head

        maybeSelectedContainerInventoryNode =
            rightContainerNode
                |> Maybe.andThen
                    (listDescendantsWithDisplayRegion
                        >> List.filter
                            (\uiNode ->
                                [ "ShipCargo", "ShipDroneBay", "ShipGeneralMiningHold", "StationItems", "ShipFleetHangar", "StructureItemHangar" ]
                                    |> List.member uiNode.uiNode.pythonObjectTypeName
                            )
                        >> List.head
                    )

        selectedContainerInventory =
            maybeSelectedContainerInventoryNode
                |> Maybe.map parseInventory

        buttonToSwitchToListView =
            rightContainerNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter
                    (\uiNode ->
                        (uiNode.uiNode.pythonObjectTypeName |> String.contains "ButtonIcon")
                            && ((uiNode.uiNode |> getTexturePathFromDictEntries |> Maybe.withDefault "") |> String.endsWith "38_16_190.png")
                    )
                |> List.head

        quickFilterInputBox =
            windowUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "quickFilterInputBox"))
                |> List.head

        buttonToStackAll =
            rightContainerNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter
                    (\uiNode ->
                        (uiNode.uiNode.pythonObjectTypeName |> String.contains "ButtonIcon")
                            && (uiNode.uiNode |> getHintTextFromDictEntries |> Maybe.map (String.contains "Stack All") |> Maybe.withDefault False)
                    )
                |> List.head
    in
    { uiNode = windowUiNode
    , leftTreeEntries = leftTreeEntries
    , subCaptionLabelText = subCaptionLabelText
    , selectedContainerCapacityGauge = selectedContainerCapacityGauge
    , selectedContainerInventory = selectedContainerInventory
    , buttonToSwitchToListView = buttonToSwitchToListView
    , buttonToStackAll = buttonToStackAll
    , quickFilterInputBox = quickFilterInputBox
    , quickFilterText =
        -- The box's own rendered contents. Distinct from the placeholder,
        -- which is a sibling `LabelOverride` reading "Search" -- taking the
        -- longest text would pick that up on an empty box, so read the
        -- `textLabel` child specifically.
        quickFilterInputBox
            |> Maybe.map listDescendantsWithDisplayRegion
            |> Maybe.withDefault []
            |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "textLabel"))
            |> List.filterMap (.uiNode >> getDisplayText)
            |> List.head
    }


parseInventory : UITreeNodeWithDisplayRegion -> Inventory
parseInventory inventoryNode =
    let
        listViewItemNodes =
            inventoryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Item")
                |> subsequenceNotContainedInAnyOtherWithDisplayRegion

        scrollNode =
            inventoryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "scroll")
                |> List.head

        scrollControlsNode =
            scrollNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "ScrollControls")
                |> List.head

        headersContainerNode =
            scrollNode
                |> Maybe.andThen
                    (getMostPopulousDescendantWithDisplayRegionMatchingPredicate
                        (predicateAny
                            [ .uiNode >> .pythonObjectTypeName >> String.toLower >> String.contains "headers"
                            , .uiNode
                                >> getNameFromDictEntries
                                >> Maybe.map (String.toLower >> String.contains "headers")
                                >> Maybe.withDefault False
                            ]
                        )
                    )

        entriesHeaders =
            headersContainerNode
                |> Maybe.map getAllContainedDisplayTextsWithRegion
                |> Maybe.withDefault []
                |> List.Extra.uniqueBy Tuple.first

        notListViewItemNodes =
            inventoryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "InvItem")
                |> subsequenceNotContainedInAnyOtherWithDisplayRegion

        itemsView =
            if 0 < (listViewItemNodes |> List.length) then
                Just
                    (InventoryItemsListView
                        { items =
                            listViewItemNodes
                                |> List.map (parseInventoryItemsListViewEntry entriesHeaders)
                        }
                    )

            else if 0 < (notListViewItemNodes |> List.length) then
                Just (InventoryItemsNotListView { items = notListViewItemNodes })

            else
                Nothing
    in
    { uiNode = inventoryNode
    , itemsView = itemsView
    , scrollControls = scrollControlsNode |> Maybe.map parseScrollControls
    }


parseInventoryItemsListViewEntry :
    List ( String, UITreeNodeWithDisplayRegion )
    -> UITreeNodeWithDisplayRegion
    -> InventoryItemsListViewEntry
parseInventoryItemsListViewEntry entriesHeaders inventoryEntryNode =
    let
        listViewEntry =
            parseListViewEntry entriesHeaders inventoryEntryNode
    in
    { uiNode = inventoryEntryNode
    , cellsTexts = listViewEntry.cellsTexts
    }


parseListViewEntry :
    List ( String, UITreeNodeWithDisplayRegion )
    -> UITreeNodeWithDisplayRegion
    -> { cellsTexts : Dict.Dict String String }
parseListViewEntry entriesHeaders listViewEntryNode =
    {-
       Observations show two different kinds of representations of the texts in the cells in a list view:

       + Each cell text in a dedicated UI element. (Overview entry)
       + All cell texts in a single UI element, separated by a tab-tag (<t>) (Inventory item)

       Following is an example of the latter case:
       Condensed Scordite<t><right>200<t>Scordite<t><t><t><right>30 m3<t><right>2.290,00 ISK
    -}
    case entriesHeaders |> List.head of
        Nothing ->
            { cellsTexts = Dict.empty }

        Just leftmostHeader ->
            let
                headerRegionMatchesCellRegion headerRegion cellRegion =
                    (headerRegion.x < cellRegion.x + 3)
                        && (headerRegion.x + headerRegion.width > cellRegion.x + cellRegion.width - 3)

                cellsTexts =
                    listViewEntryNode
                        |> getAllContainedDisplayTextsWithRegion
                        |> List.concatMap
                            (\( cellText, cell ) ->
                                let
                                    distanceFromLeftmostHeader =
                                        cell.totalDisplayRegion.x - (Tuple.second leftmostHeader).totalDisplayRegion.x

                                    maybeHeaderByCellRegion =
                                        entriesHeaders
                                            |> List.filter
                                                (\( _, header ) ->
                                                    headerRegionMatchesCellRegion
                                                        header.totalDisplayRegion
                                                        cell.totalDisplayRegion
                                                )
                                            |> List.head
                                in
                                case maybeHeaderByCellRegion of
                                    Just ( headerText, _ ) ->
                                        [ ( headerText, cellText ) ]

                                    Nothing ->
                                        if abs distanceFromLeftmostHeader < 4 then
                                            []

                                        else
                                            cellText
                                                |> String.split "<t>"
                                                |> List.map String.trim
                                                |> List.indexedMap Tuple.pair
                                                |> List.filterMap
                                                    (\( cellIndex, cellSubText ) ->
                                                        entriesHeaders
                                                            |> List.drop cellIndex
                                                            |> List.head
                                                            |> Maybe.map
                                                                (\( headerText, _ ) ->
                                                                    ( headerText, cellSubText )
                                                                )
                                                    )
                            )
                        |> Dict.fromList
            in
            { cellsTexts = cellsTexts }


getContainedTreeViewEntryRootNodes : UITreeNodeWithDisplayRegion -> List UITreeNodeWithDisplayRegion
getContainedTreeViewEntryRootNodes parentNode =
    let
        leftTreeEntriesAllNodes =
            parentNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.startsWith "TreeViewEntry")

        isContainedInTreeEntry candidate =
            leftTreeEntriesAllNodes
                |> List.concatMap listDescendantsWithDisplayRegion
                |> List.member candidate
    in
    leftTreeEntriesAllNodes
        |> List.filter (isContainedInTreeEntry >> not)


parseInventoryWindowTreeViewEntry : UITreeNodeWithDisplayRegion -> InventoryWindowLeftTreeEntry
parseInventoryWindowTreeViewEntry treeEntryNode =
    let
        topContNode =
            treeEntryNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.startsWith "topCont_") >> Maybe.withDefault False)
                |> List.sortBy (.totalDisplayRegion >> .y)
                |> List.head

        toggleBtn =
            topContNode
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map ((==) "toggleBtn") >> Maybe.withDefault False)
                |> List.head

        text =
            topContNode
                |> Maybe.map getAllContainedDisplayTextsWithRegion
                |> Maybe.withDefault []
                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> .y)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault ""

        childrenNodes =
            treeEntryNode |> getContainedTreeViewEntryRootNodes

        children =
            childrenNodes |> List.map (parseInventoryWindowTreeViewEntry >> InventoryWindowLeftTreeEntryChild)
    in
    { uiNode = treeEntryNode
    , toggleBtn = toggleBtn
    , selectRegion = topContNode
    , text = text
    , children = children
    }


unwrapInventoryWindowLeftTreeEntryChild : InventoryWindowLeftTreeEntryChild -> InventoryWindowLeftTreeEntry
unwrapInventoryWindowLeftTreeEntryChild child =
    case child of
        InventoryWindowLeftTreeEntryChild unpacked ->
            unpacked


parseInventoryCapacityGaugeText : String -> Result String InventoryWindowCapacityGauge
parseInventoryCapacityGaugeText capacityText =
    let
        parseMaybeNumber =
            Maybe.map (String.trim >> parseNumberTruncatingAfterOptionalDecimalSeparator >> Result.map Just)
                >> Maybe.withDefault (Ok Nothing)

        continueWithTexts { usedText, maybeMaximumText, maybeSelectedText } =
            case usedText |> parseNumberTruncatingAfterOptionalDecimalSeparator of
                Err parseNumberError ->
                    Err ("Failed to parse used number: " ++ parseNumberError)

                Ok used ->
                    case maybeMaximumText |> parseMaybeNumber of
                        Err parseNumberError ->
                            Err ("Failed to parse maximum number: " ++ parseNumberError)

                        Ok maximum ->
                            case maybeSelectedText |> parseMaybeNumber of
                                Err parseNumberError ->
                                    Err ("Failed to parse selected number: " ++ parseNumberError)

                                Ok selected ->
                                    Ok { used = used, maximum = maximum, selected = selected }

        continueAfterSeparatingBySlash { beforeSlashText, afterSlashMaybeText } =
            case beforeSlashText |> String.trim |> String.split ")" of
                [ onlyUsedText ] ->
                    continueWithTexts { usedText = onlyUsedText, maybeMaximumText = afterSlashMaybeText, maybeSelectedText = Nothing }

                [ firstPart, secondPart ] ->
                    continueWithTexts { usedText = secondPart, maybeMaximumText = afterSlashMaybeText, maybeSelectedText = Just (firstPart |> String.replace "(" "") }

                _ ->
                    Err ("Unexpected number of components in text before slash '" ++ beforeSlashText ++ "'")
    in
    case capacityText |> String.replace "m³" "" |> String.split "/" of
        [ withoutSlash ] ->
            continueAfterSeparatingBySlash { beforeSlashText = withoutSlash, afterSlashMaybeText = Nothing }

        [ partBeforeSlash, partAfterSlash ] ->
            continueAfterSeparatingBySlash { beforeSlashText = partBeforeSlash, afterSlashMaybeText = Just partAfterSlash }

        _ ->
            Err ("Unexpected number of components in capacityText '" ++ capacityText ++ "'")


parseModuleButtonTooltipFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe ModuleButtonTooltip
parseModuleButtonTooltipFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ModuleButtonTooltip")
            |> List.head
    of
        Nothing ->
            Nothing

        Just uiNode ->
            Just (parseModuleButtonTooltip uiNode)


parseModuleButtonTooltip : UITreeNodeWithDisplayRegion -> ModuleButtonTooltip
parseModuleButtonTooltip tooltipUINode =
    let
        upperRightCornerFromDisplayRegion region =
            { x = region.x + region.width, y = region.y }

        distanceSquared a b =
            let
                distanceX =
                    a.x - b.x

                distanceY =
                    a.y - b.y
            in
            distanceX * distanceX + distanceY * distanceY

        shortcutCandidates =
            tooltipUINode
                |> getAllContainedDisplayTextsWithRegion
                |> List.map
                    (\( text, textUINode ) ->
                        { text = text
                        , distanceUpperRightCornerSquared =
                            distanceSquared
                                (textUINode.totalDisplayRegion |> upperRightCornerFromDisplayRegion)
                                (tooltipUINode.totalDisplayRegion |> upperRightCornerFromDisplayRegion)
                        }
                    )
                |> List.sortBy .distanceUpperRightCornerSquared

        shortcut =
            shortcutCandidates
                |> List.filter (\textAndDistance -> textAndDistance.distanceUpperRightCornerSquared < 1000)
                |> List.head
                |> Maybe.map (\{ text } -> { text = text, parseResult = text |> parseModuleButtonTooltipShortcut })

        optimalRangeString =
            tooltipUINode.uiNode
                |> getAllContainedDisplayTexts
                |> List.filterMap
                    (\text ->
                        "Optimal range (|within)\\s*([\\d\\.]+\\s*[km]+)"
                            |> Regex.fromString
                            |> Maybe.andThen (\regex -> text |> Regex.find regex |> List.head)
                            |> Maybe.andThen (.submatches >> List.drop 1 >> List.head)
                            |> Maybe.andThen identity
                            |> Maybe.map String.trim
                    )
                |> List.head

        optimalRange =
            optimalRangeString
                |> Maybe.map (\asString -> { asString = asString, inMeters = asString |> parseOverviewEntryDistanceInMetersFromText })
    in
    { uiNode = tooltipUINode
    , shortcut = shortcut
    , optimalRange = optimalRange
    }


parseModuleButtonTooltipShortcut : String -> Result String (List Common.EffectOnWindow.VirtualKeyCode)
parseModuleButtonTooltipShortcut shortcutText =
    shortcutText
        |> String.split "-"
        |> List.concatMap (String.split "+")
        |> List.map String.trim
        |> List.filter (String.length >> (<) 0)
        |> List.foldl
            (\nextKeyText previousResult ->
                previousResult
                    |> Result.andThen
                        (\previousKeys ->
                            case nextKeyText |> parseKeyShortcutText of
                                Just nextKey ->
                                    Ok (nextKey :: previousKeys)

                                Nothing ->
                                    Err ("Unknown key text: '" ++ nextKeyText ++ "'")
                        )
            )
            (Ok [])
        |> Result.map List.reverse


parseHeatStatusTooltipFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe HeatStatusTooltip
parseHeatStatusTooltipFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "TooltipPanel")
        |> List.filter
            (getAllContainedDisplayTextsWithRegion
                >> List.sortBy (Tuple.second >> .totalDisplayRegion >> .y)
                >> List.head
                >> Maybe.map (Tuple.first >> String.contains "Heat Status")
                >> Maybe.withDefault False
            )
        |> List.head
        |> Maybe.map parseHeatStatusTooltip


parseHeatStatusTooltip : UITreeNodeWithDisplayRegion -> HeatStatusTooltip
parseHeatStatusTooltip tooltipNode =
    let
        parsePercentFromPrefix prefix =
            tooltipNode.uiNode
                |> getAllContainedDisplayTexts
                |> List.map String.trim
                |> List.filter (String.toLower >> String.startsWith prefix)
                |> List.head
                |> Maybe.map (String.split " " >> List.filter (String.isEmpty >> not) >> List.drop 1 >> String.join "")
                |> Maybe.andThen (String.split "%" >> List.head)
                |> Maybe.andThen String.toInt
    in
    { uiNode = tooltipNode
    , lowPercent = parsePercentFromPrefix "low"
    , mediumPercent = parsePercentFromPrefix "medium"
    , highPercent = parsePercentFromPrefix "high"
    }


parseKeyShortcutText : String -> Maybe Common.EffectOnWindow.VirtualKeyCode
parseKeyShortcutText keyText =
    [ ( "CTRL", Common.EffectOnWindow.vkey_LCONTROL )
    , ( "STRG", Common.EffectOnWindow.vkey_LCONTROL )
    , ( "ALT", Common.EffectOnWindow.vkey_LMENU )
    , ( "SHIFT", Common.EffectOnWindow.vkey_LSHIFT )
    , ( "UMSCH", Common.EffectOnWindow.vkey_LSHIFT )
    , ( "F1", Common.EffectOnWindow.vkey_F1 )
    , ( "F2", Common.EffectOnWindow.vkey_F2 )
    , ( "F3", Common.EffectOnWindow.vkey_F3 )
    , ( "F4", Common.EffectOnWindow.vkey_F4 )
    , ( "F5", Common.EffectOnWindow.vkey_F5 )
    , ( "F6", Common.EffectOnWindow.vkey_F6 )
    , ( "F7", Common.EffectOnWindow.vkey_F7 )
    , ( "F8", Common.EffectOnWindow.vkey_F8 )
    , ( "F9", Common.EffectOnWindow.vkey_F9 )
    , ( "F10", Common.EffectOnWindow.vkey_F10 )
    , ( "F11", Common.EffectOnWindow.vkey_F11 )
    , ( "F12", Common.EffectOnWindow.vkey_F12 )
    ]
        |> Dict.fromList
        |> Dict.get (keyText |> String.toUpper)


parseChatWindowStacksFromUITreeRoot : UITreeNodeWithDisplayRegion -> List ChatWindowStack
parseChatWindowStacksFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ChatWindowStack")
        |> List.map parseChatWindowStack


parseChatWindowStack : UITreeNodeWithDisplayRegion -> ChatWindowStack
parseChatWindowStack chatWindowStackUiNode =
    let
        chatWindowNode =
            chatWindowStackUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "XmppChatWindow")
                |> List.head
    in
    { uiNode = chatWindowStackUiNode
    , chatWindow = chatWindowNode |> Maybe.map parseChatWindow
    }


parseChatWindow : UITreeNodeWithDisplayRegion -> ChatWindow
parseChatWindow chatWindowUiNode =
    let
        userlistNode =
            chatWindowUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> getNameFromDictEntries >> Maybe.map (String.toLower >> String.contains "userlist") >> Maybe.withDefault False)
                |> List.head
    in
    { uiNode = chatWindowUiNode
    , name = getNameFromDictEntries chatWindowUiNode.uiNode
    , userlist = userlistNode |> Maybe.map parseChatWindowUserlist
    }


parseChatWindowUserlist : UITreeNodeWithDisplayRegion -> ChatWindowUserlist
parseChatWindowUserlist userlistNode =
    let
        visibleUsers =
            userlistNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (\uiNode -> [ "XmppChatSimpleUserEntry", "XmppChatUserEntry" ] |> List.member uiNode.uiNode.pythonObjectTypeName)
                |> List.map parseChatUserEntry

        scrollControls =
            userlistNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "ScrollControls")
                |> List.head
                |> Maybe.map parseScrollControls
    in
    { uiNode = userlistNode, visibleUsers = visibleUsers, scrollControls = scrollControls }


parseChatUserEntry : UITreeNodeWithDisplayRegion -> ChatUserEntry
parseChatUserEntry chatUserUiNode =
    let
        standingIconNode =
            chatUserUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "FlagIconWithState")
                |> List.head

        name =
            chatUserUiNode.uiNode
                |> getAllContainedDisplayTexts
                |> List.sortBy String.length
                |> List.reverse
                |> List.head

        standingIconHint =
            standingIconNode
                |> Maybe.andThen (.uiNode >> getHintTextFromDictEntries)
    in
    { uiNode = chatUserUiNode
    , name = name
    , standingIconHint = standingIconHint
    }


parseAgentConversationWindowsFromUITreeRoot : UITreeNodeWithDisplayRegion -> List AgentConversationWindow
parseAgentConversationWindowsFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "AgentDialogueWindow")
        |> List.map parseAgentConversationWindow


parseAgentConversationWindow : UITreeNodeWithDisplayRegion -> AgentConversationWindow
parseAgentConversationWindow windowUINode =
    let
        briefingHtml =
            windowUINode.uiNode |> getStringPropertyFromDictEntries "briefingHtml"
    in
    { uiNode = windowUINode
    , agentCharacterID =
        windowUINode.uiNode
            |> getNameFromDictEntries
            |> Maybe.andThen (idSuffixAfterSeparator "_")
    , buttons =
        windowUINode
            |> listDescendantsWithDisplayRegion
            |> List.filterMap
                (\descendant ->
                    case descendant.uiNode |> getNameFromDictEntries of
                        Just name ->
                            if String.endsWith "_Button" name then
                                Just
                                    { uiNode = descendant
                                    , name = name
                                    , mainText =
                                        descendant.uiNode
                                            |> getAllContainedDisplayTexts
                                            |> List.head
                                    }

                            else
                                Nothing

                        Nothing ->
                            Nothing
                )
    , briefingHtml = briefingHtml
    , objectiveHtml = windowUINode.uiNode |> getStringPropertyFromDictEntries "objectiveHtml"
    , offeredMissionName = briefingHtml |> Maybe.andThen subheaderTextFromHtml
    }


{-| The mission's own name, as the first `<span id=subheader>` in the agent's
briefing. This is the only place it can be read _before_ the mission is
accepted -- the info panel's mission tracker does not exist until then -- so
it is what any "should I take this mission?" decision has to work from.
-}
subheaderTextFromHtml : String -> Maybe String
subheaderTextFromHtml html =
    case html |> String.split "<span id=subheader>" |> List.drop 1 |> List.head of
        Nothing ->
            Nothing

        Just afterOpeningTag ->
            afterOpeningTag
                |> String.split "</span>"
                |> List.head
                |> Maybe.map (stripHtmlTags >> String.trim)
                |> Maybe.andThen
                    (\text ->
                        if String.isEmpty text then
                            Nothing

                        else
                            Just text
                    )


{-| Inner texts of any HTML links in a string.
-}
linkTextsFromHtml : String -> List String
linkTextsFromHtml html =
    Regex.find
        (Regex.fromString "<a[^>]*>([^<]*)</a>" |> Maybe.withDefault Regex.never)
        html
        |> List.filterMap (.submatches >> List.head >> Maybe.andThen identity)
        |> List.map String.trim
        |> List.filter (String.isEmpty >> not)


stripHtmlTags : String -> String
stripHtmlTags =
    Regex.replace
        (Regex.fromString "<[^>]*>" |> Maybe.withDefault Regex.never)
        (always "")


parseAgentMissionInfoPanelEntriesFromUITreeRoot : UITreeNodeWithDisplayRegion -> List AgentMissionInfoPanelEntry
parseAgentMissionInfoPanelEntriesFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "AgentMissionInfoPanelEntry")
        |> List.map parseAgentMissionInfoPanelEntry


parseAgentMissionInfoPanelEntry : UITreeNodeWithDisplayRegion -> AgentMissionInfoPanelEntry
parseAgentMissionInfoPanelEntry entryNode =
    let
        descendants =
            entryNode |> listDescendantsWithDisplayRegion

        labelsOfType typeName =
            descendants |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) typeName)

        textsOf nodes =
            nodes |> List.filterMap (.uiNode >> getDisplayText)

        largeLabels =
            labelsOfType "EveLabelLarge"

        missionNameNodes =
            largeLabels
                |> List.filter (.uiNode >> getNameFromDictEntries >> (/=) (Just "title"))

        objectiveTitles =
            largeLabels
                |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "title"))
                |> textsOf

        instructionTexts =
            labelsOfType "EveLabelMedium"
                |> List.filter (.uiNode >> getNameFromDictEntries >> (/=) (Just "label"))
                |> textsOf

        -- The layout this parser was written against: one button whose label is
        -- whatever the next travel step happens to be, named for its purpose.
        singleLocationButton =
            descendants
                |> List.filter
                    (.uiNode
                        >> getNameFromDictEntries
                        >> Maybe.map (String.startsWith "missionObjective_button_location")
                        >> Maybe.withDefault False
                    )
                |> List.head

        -- The other layout, and it renders no such button. An objective chain
        -- (`ObjectiveChainEntry` -> `ObjectiveEntry` -> per-task widgets) gives
        -- each task its own button and shows only the one that is currently
        -- available, hiding the rest with `_display` False. Run 14 sat docked
        -- for 750 readings on "Technological Secrets (3 of 3)" printing "the
        -- tracker offers no travel step from here" while the panel held
        --
        --     TravelToLocationButtonTaskWidget  _name=objective_task_travel_to_agent
        --       EveLabelMedium  _name=label  Set Destination      (displayed)
        --     ButtonTaskWidget                _name=objective_task_talk_to_agent
        --       EveLabelMedium  _name=label  Start Conversation   (_display False)
        --
        -- so the step was rendered, labelled and named -- just named something
        -- no rule here had ever heard of. Matched on the *type* name rather
        -- than `_name`, because `_name` carries the objective ("travel_to_agent",
        -- "talk_to_agent") and would need a new literal per objective, while
        -- the type says what the widget is. The suffix covers both, which is
        -- deliberate: the single button above also changes label from travel to
        -- "Start Conversation" at hand-in, so a rule that took only the travel
        -- widget would cross the grid and then strand the ship at the agent.
        --
        -- **The display filter is the selection, not a safety net.** Both
        -- buttons are always present; which one is shown is the client saying
        -- which task is live. Picking the hidden one yields a button
        -- `missionTravelStep` then discards, which is the same stall by another
        -- route.
        objectiveChainTaskButton =
            descendants
                |> List.filter
                    (.uiNode
                        >> .pythonObjectTypeName
                        >> String.endsWith "ButtonTaskWidget"
                    )
                |> List.filter (.uiNode >> nodeIsDisplayedFromDictEntries)
                |> List.head

        locationButton =
            case singleLocationButton of
                Just button ->
                    Just button

                Nothing ->
                    objectiveChainTaskButton
    in
    { uiNode = entryNode
    , agentCharacterID =
        entryNode.uiNode
            |> getNameFromDictEntries
            |> Maybe.andThen (idSuffixAfterSeparator ":")
    , missionName =
        -- The mission's own name is the one large label that is not an
        -- objective title; objective titles all carry _name = "title".
        missionNameNodes |> textsOf |> List.head
    , objectiveTitles = objectiveTitles
    , instructionTexts = instructionTexts
    , objectNamesToDestroy =
        -- An objective that names a specific object to kill spells it out as
        -- an HTML link, e.g. `You need to destroy the <a href="showinfo:18012//
        -- 9002294932000162109">Drone Silo</a>`. Reading the name from there
        -- means mission structures are handled automatically, instead of each
        -- one having to be listed in the bot settings by hand before its
        -- mission can be run.
        instructionTexts
            |> List.filter (String.toLower >> String.contains "destroy")
            |> List.concatMap linkTextsFromHtml
    , objectNamesToCarry =
        -- An objective that wants something aboard names it the same way a
        -- combat one names its target: `You need <a href="showinfo:29253">
        -- Political Envoy</a> in your cargo hold`. Gated on the cargo-hold
        -- wording so the destination link in a travel objective is not
        -- mistaken for freight.
        --
        -- The wording varies more than it looks: "in your cargo hold" on the
        -- courier arc mission, "in your cargohold" (one word) on "Get the
        -- Relic", and "Retrieve <a>Prisoner</a> from the cargo Container" on
        -- "Escaped Dissident", which mentions no hold at all. Each variant in
        -- turn silently produced no cargo to fetch and left the bot idling.
        --
        -- Matched on these phrases rather than the bare word "cargo", which
        -- would also catch the *delivery* instruction "Bring 15 x <a>Small
        -- Sealed Cargo Containers</a> to ..." -- there the item's own name
        -- contains "Cargo Containers", and treating that as something to go
        -- and fetch would send the bot hunting for cargo it is already
        -- carrying.
        instructionTexts
            |> List.filter
                (\instruction ->
                    let
                        lowered =
                            String.toLower instruction
                    in
                    [ "cargo hold", "cargohold", "retrieve" ]
                        |> List.any (\phrase -> String.contains phrase lowered)
                )
            |> List.concatMap linkTextsFromHtml
    , objectNamesToApproach =
        -- Some missions are satisfied just by getting close to something:
        -- "You need to approach <a ...>Fire Cloud</a>". Named the same way as
        -- a destroy target, so the same link extraction applies.
        instructionTexts
            |> List.filter (String.toLower >> String.contains "approach")
            |> List.concatMap linkTextsFromHtml
    , locationButton =
        locationButton
            |> Maybe.map
                (\buttonNode ->
                    { uiNode = buttonNode
                    , label =
                        buttonNode
                            |> listDescendantsWithDisplayRegion
                            |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "label"))
                            |> textsOf
                            |> List.filter (String.trim >> String.isEmpty >> not)
                            |> List.head
                    }
                )
    , isExpanded =
        -- A collapsed entry keeps only its header row: the objectives and the
        -- travel button are gone, which is indistinguishable from "on grid,
        -- nothing to travel to" unless the collapsed state itself is read.
        --
        -- **`_expanded` is not that state, and reading it is what run 30 was.**
        -- This was `Dict.get "_expanded" |> Maybe.withDefault True`, and the
        -- key is present on the entry and read `True` while the entry was
        -- collapsed -- measured on the live client, against a
        -- `content_container` of `384x0` in the same reading. So
        -- `expandMissionTrackerIfCollapsed` answered `Nothing`, the branch it
        -- guards was never reached, and the bot printed `A mission is running
        -- but the tracker offers no travel step from here` **512 times** while
        -- four manual clicks on the header opened it (`384x0` -> `384x135`) and
        -- the run resumed. Run 28 lost a whole session to the same thing.
        --
        -- The client's own layout is the observable that does distinguish
        -- them: the content container is present in both states and carries a
        -- height only when the entry is open. Measured collapsed at `384x0`
        -- and expanded at `384x135`, `384x144` and `384x186` as an objective
        -- grew, so the test is "has any height at all" rather than a size.
        --
        -- `_isCollapsed` is also on the entry and reads `False` while expanded,
        -- but it has never been observed in the collapsed state and so is not
        -- relied on here. It is the obvious thing to check first if this ever
        -- needs revisiting.
        entryNode
            |> listDescendantsWithDisplayRegion
            |> List.filter
                (.uiNode >> getNameFromDictEntries >> (==) (Just "content_container"))
            |> List.head
            |> Maybe.map (.totalDisplayRegion >> .height)
            |> missionEntryIsExpandedFromContentHeight
    }


{-| Whether a mission tracker entry is open, from its content's height.

Separated from the reading for the reason `idSuffixAfterSeparator` is: the rule
is the part that can be wrong, and a rule reachable only by parsing a whole live
UI tree is a rule no test case can execute. The walk finds the container; this
decides what its height means.

`Nothing` -- no container to measure -- reads as **expanded**, which is the
direction that fails the way the old bug did rather than a worse way. A client
naming that node something else leaves the tracker shut and the bot waiting,
which is what run 30 already did; the other answer would have the bot clicking a
header it can never open for a whole session.

-}
missionEntryIsExpandedFromContentHeight : Maybe Int -> Bool
missionEntryIsExpandedFromContentHeight contentHeight =
    case contentHeight of
        Just height ->
            height > 0

        Nothing ->
            True


{-| Pulls the numeric id out of the composite element names the mission UI
uses to tie a node to an agent, e.g. "AgentConversation\_3008771" or
"agent\_missions:3008771".
-}
idSuffixAfterSeparator : String -> String -> Maybe Int
idSuffixAfterSeparator separator name =
    name
        |> String.split separator
        |> List.reverse
        |> List.head
        |> Maybe.andThen String.toInt


parseMarketOrdersWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe MarketOrdersWindow
parseMarketOrdersWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "MarketOrdersWnd")
        |> List.head
        |> Maybe.map parseMarketOrdersWindow


parseMarketOrdersWindow : UITreeNodeWithDisplayRegion -> MarketOrdersWindow
parseMarketOrdersWindow windowUINode =
    { uiNode = windowUINode
    }


parseFittingWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe FittingWindow
parseFittingWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "FittingWindow")
        |> List.head
        |> Maybe.map parseFittingWindow


parseFittingWindow : UITreeNodeWithDisplayRegion -> FittingWindow
parseFittingWindow windowUINode =
    { uiNode = windowUINode
    }


parseSurveyScanWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe SurveyScanWindow
parseSurveyScanWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SurveyScanView")
        |> List.head
        |> Maybe.map parseSurveyScanWindow


parseSurveyScanWindow : UITreeNodeWithDisplayRegion -> SurveyScanWindow
parseSurveyScanWindow windowUINode =
    { uiNode = windowUINode
    , scanEntries =
        windowUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SurveyScanEntry")
    }


parseBookmarkLocationWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe BookmarkLocationWindow
parseBookmarkLocationWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "BookmarkLocationWindow")
        |> List.head
        |> Maybe.map parseBookmarkLocationWindow


parseBookmarkLocationWindow : UITreeNodeWithDisplayRegion -> BookmarkLocationWindow
parseBookmarkLocationWindow windowUINode =
    { uiNode = windowUINode
    , submitButton = findButtonInDescendantsContainingDisplayText "submit" windowUINode
    , cancelButton = findButtonInDescendantsContainingDisplayText "cancel" windowUINode
    }


parseRepairShopWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe RepairShopWindow
parseRepairShopWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "RepairShopWindow")
        |> List.head
        |> Maybe.map parseRepairShopWindow


parseRepairShopWindow : UITreeNodeWithDisplayRegion -> RepairShopWindow
parseRepairShopWindow windowUINode =
    let
        buttonGroup =
            windowUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "ButtonGroup")
                |> List.head

        buttons =
            buttonGroup
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "Button")
                |> List.map
                    (\buttonNode ->
                        { uiNode = buttonNode
                        , mainText =
                            buttonNode
                                |> getAllContainedDisplayTextsWithRegion
                                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0)
                                |> List.map Tuple.first
                                |> List.head
                        }
                    )
    in
    { uiNode = windowUINode
    , items =
        windowUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "Item")
    , buttonGroup = buttonGroup
    , buttons = buttons
    }


parseCharacterSheetWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe CharacterSheetWindow
parseCharacterSheetWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "CharacterSheetWindow")
        |> List.head
        |> Maybe.map parseCharacterSheetWindow


parseCharacterSheetWindow : UITreeNodeWithDisplayRegion -> CharacterSheetWindow
parseCharacterSheetWindow windowUINode =
    let
        skillGroups =
            windowUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "SkillGroupGauge")
    in
    { uiNode = windowUINode
    , skillGroups = skillGroups
    }


parseFleetWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe FleetWindow
parseFleetWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "FleetWindow")
        |> List.head
        |> Maybe.map parseFleetWindow


parseFleetWindow : UITreeNodeWithDisplayRegion -> FleetWindow
parseFleetWindow windowUINode =
    let
        fleetMembers =
            windowUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "FleetMember")
    in
    { uiNode = windowUINode
    , fleetMembers = fleetMembers
    }


parseWatchListPanelFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe WatchListPanel
parseWatchListPanelFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "WatchListPanel")
        |> List.head
        |> Maybe.map parseWatchListPanel


parseWatchListPanel : UITreeNodeWithDisplayRegion -> WatchListPanel
parseWatchListPanel windowUINode =
    let
        entries =
            windowUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "WatchListEntry")
    in
    { uiNode = windowUINode
    , entries = entries
    }


parseStandaloneBookmarkWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe StandaloneBookmarkWindow
parseStandaloneBookmarkWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "StandaloneBookmarkWnd")
        |> List.head
        |> Maybe.map parseStandaloneBookmarkWindow


parseStandaloneBookmarkWindow : UITreeNodeWithDisplayRegion -> StandaloneBookmarkWindow
parseStandaloneBookmarkWindow windowUINode =
    let
        entries =
            windowUINode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "PlaceEntry")
    in
    { uiNode = windowUINode
    , entries = entries
    }


parseNeocomFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe Neocom
parseNeocomFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "NeocomContainer")
        |> List.head
        |> Maybe.map parseNeocom


parseNeocom : UITreeNodeWithDisplayRegion -> Neocom
parseNeocom neocomUiNode =
    let
        maybeClockTextAndNode =
            neocomUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "InGameClock")
                |> List.concatMap getAllContainedDisplayTextsWithRegion
                |> List.head

        clock =
            maybeClockTextAndNode
                |> Maybe.map
                    (\( clockText, clockNode ) ->
                        { uiNode = clockNode
                        , text = clockText
                        , parsedText = parseNeocomClockText clockText
                        }
                    )

        inventoryButton =
            neocomUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ButtonInventory")
                |> List.head
    in
    { uiNode = neocomUiNode
    , inventoryButton = inventoryButton
    , clock = clock
    }


parseNeocomClockText : String -> Result String { hour : Int, minute : Int }
parseNeocomClockText clockText =
    case clockText |> String.split ":" of
        [ hourText, minuteText ] ->
            case hourText |> String.trim |> String.toInt of
                Nothing ->
                    Err ("Failed to parse hour: '" ++ hourText ++ "'")

                Just hour ->
                    case minuteText |> String.trim |> String.toInt of
                        Nothing ->
                            Err ("Failed to parse minute: '" ++ minuteText ++ "'")

                        Just minute ->
                            Ok { hour = hour, minute = minute }

        _ ->
            Err "Expecting exactly two substrings separated by a colon (:)."


parseKeyActivationWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe KeyActivationWindow
parseKeyActivationWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "KeyActivationWindow")
        |> List.head
        |> Maybe.map parseKeyActivationWindow


parseKeyActivationWindow : UITreeNodeWithDisplayRegion -> KeyActivationWindow
parseKeyActivationWindow windowUiNode =
    let
        activateButton =
            windowUiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ActivateButton")
                |> List.head
    in
    { uiNode = windowUiNode
    , activateButton = activateButton
    }


parseCompressionWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe CompressionWindow
parseCompressionWindowFromUITreeRoot uiTreeRoot =
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "CompressionWindow")
        |> List.head
        |> Maybe.map parseCompressionWindow


parseCompressionWindow : UITreeNodeWithDisplayRegion -> CompressionWindow
parseCompressionWindow windowUiNode =
    let
        compressButton =
            findButtonInDescendantsContainingDisplayText "Compress" windowUiNode
    in
    { uiNode = windowUiNode
    , windowControls = parseWindowControlsFromWindow windowUiNode
    , compressButton = compressButton
    }


parseLocationsWindowFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe LocationsWindow
parseLocationsWindowFromUITreeRoot uiTreeRoot =
    {-
       2024-09-02 'Locations' window as shared by Paul with 'session-recording-2024-08-26T22-54-47.zip'
       For discussion of the 'Locations' window, see <https://forum.botlab.org/t/the-mining-robot-cant-find-its-way-home/4922/5>
    -}
    uiTreeRoot
        |> listDescendantsWithDisplayRegion
        |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "LocationsWindow")
        |> List.head
        |> Maybe.map parseLocationsWindow


parseLocationsWindow : UITreeNodeWithDisplayRegion -> LocationsWindow
parseLocationsWindow windowNode =
    let
        placeEntries : List LocationsWindowPlaceEntry
        placeEntries =
            windowNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "PlaceEntry")
                |> List.filterMap parseLocationsWindowPlaceEntry
    in
    { uiNode = windowNode
    , placeEntries = placeEntries
    }


parseLocationsWindowPlaceEntry : UITreeNodeWithDisplayRegion -> Maybe LocationsWindowPlaceEntry
parseLocationsWindowPlaceEntry entryNode =
    {-
       Screenshots show a grid layout of cells with text in each cell aligned in columns.
       But at least in 'session-recording-2024-08-26T22-54-47.zip', the text appeared in a single node of type "EveLabelMedium"
       As already seen in other windows, that text appears split into the cells texts by '<t>' tags.
       Following is a middle part of an observed text in a 'EveLabelMedium' node in a 'PlaceEntry' node:
       ...<t>Refinery<t>0<t>Y5C-YD<t>...
    -}
    case
        entryNode
            |> getAllContainedDisplayTextsWithRegion
            |> List.sortBy (Tuple.second >> .totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0)
            |> List.map Tuple.first
            |> List.head
    of
        Nothing ->
            Nothing

        Just mainText ->
            Just { uiNode = entryNode, mainText = mainText }


parseWindowControlsFromWindow : UITreeNodeWithDisplayRegion -> Maybe WindowControls
parseWindowControlsFromWindow =
    listDescendantsWithDisplayRegion
        >> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "WindowControls")
        >> List.head
        >> Maybe.map parseWindowControls


parseWindowControls : UITreeNodeWithDisplayRegion -> WindowControls
parseWindowControls controlsNode =
    let
        nodeFromTexturePathContainingAny texturePathSubstrings =
            controlsNode
                |> listDescendantsWithDisplayRegion
                |> List.filter
                    (.uiNode
                        >> getTexturePathFromDictEntries
                        >> Maybe.map
                            (\texturePath ->
                                texturePathSubstrings
                                    |> List.any
                                        (\substring ->
                                            texturePath
                                                |> String.toLower
                                                |> String.contains (String.toLower substring)
                                        )
                            )
                        >> Maybe.withDefault False
                    )
                |> List.head

        -- The macOS client keeps these icons under 'system_icons' with a size
        -- suffix. 'eveicon/window/...' is the path the upstream parser was
        -- written against and matches nothing here, so every window read as
        -- having no controls rather than as an error.
        minimizeButton =
            nodeFromTexturePathContainingAny
                [ "eveicon/window/minimize", "system_icons/minimize_16px" ]

        closeButton =
            nodeFromTexturePathContainingAny
                [ "eveicon/window/close", "system_icons/close_16px" ]
    in
    { uiNode = controlsNode
    , minimizeButton = minimizeButton
    , closeButton = closeButton
    }


parseMessageBoxesFromUITreeRoot : UITreeNodeWithDisplayRegion -> List MessageBox
parseMessageBoxesFromUITreeRoot uiTreeRoot =
    let
        messageBoxNodes =
            uiTreeRoot
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "MessageBox")

        modalLayers =
            uiTreeRoot
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "LayerCore")
                |> List.filter
                    (.uiNode
                        >> getNameFromDictEntries
                        >> Maybe.map (String.toLower >> String.contains "modal")
                        >> Maybe.withDefault False
                    )

        modalHybridWindowNodes =
            modalLayers
                |> List.concatMap listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "HybridWindow")
    in
    [ messageBoxNodes
    , modalHybridWindowNodes
    ]
        |> List.concat
        |> List.map parseMessageBox


parseMessageBox : UITreeNodeWithDisplayRegion -> MessageBox
parseMessageBox uiNode =
    let
        buttonGroup =
            uiNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "ButtonGroup")
                |> List.head

        buttons =
            buttonGroup
                |> Maybe.map listDescendantsWithDisplayRegion
                |> Maybe.withDefault []
                |> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "Button")
                |> List.map
                    (\buttonNode ->
                        { uiNode = buttonNode
                        , mainText =
                            buttonNode
                                |> getAllContainedDisplayTextsWithRegion
                                |> List.sortBy (Tuple.second >> .totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0)
                                |> List.map Tuple.first
                                |> List.head
                        }
                    )
    in
    { buttonGroup = buttonGroup
    , buttons = buttons
    , uiNode = uiNode
    }


findButtonInDescendantsContainingDisplayText : String -> UITreeNodeWithDisplayRegion -> Maybe UITreeNodeWithDisplayRegion
findButtonInDescendantsContainingDisplayText displayText =
    findButtonInDescendantsByDisplayTextsPredicate
        (List.any (String.toLower >> String.contains (String.toLower displayText)))


findButtonInDescendantsByDisplayTextsPredicate : (List String -> Bool) -> UITreeNodeWithDisplayRegion -> Maybe UITreeNodeWithDisplayRegion
findButtonInDescendantsByDisplayTextsPredicate displayTextsPredicate =
    listDescendantsWithDisplayRegion
        {-
           2023-01-12 discovered name: UndockButton
        -}
        >> List.filter (.uiNode >> .pythonObjectTypeName >> String.contains "Button")
        >> List.filter (.uiNode >> getAllContainedDisplayTexts >> displayTextsPredicate)
        >> List.sortBy (.totalDisplayRegion >> areaFromDisplayRegion >> Maybe.withDefault 0)
        >> List.head


parseScrollControls : UITreeNodeWithDisplayRegion -> ScrollControls
parseScrollControls scrollControlsNode =
    let
        scrollHandle =
            scrollControlsNode
                |> listDescendantsWithDisplayRegion
                |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "ScrollHandle")
                |> List.head
    in
    { uiNode = scrollControlsNode
    , scrollHandle = scrollHandle
    }


parseLayerAbovemainFromUITreeRoot : UITreeNodeWithDisplayRegion -> Maybe LayerAbovemain
parseLayerAbovemainFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> getNameFromDictEntries >> (==) (Just "l_abovemain"))
            |> List.head
    of
        Nothing ->
            Nothing

        Just layerAboveMainUINode ->
            Just
                { uiNode = layerAboveMainUINode
                , quickMessage = parseQuickMessage layerAboveMainUINode
                }


parseQuickMessage : UITreeNodeWithDisplayRegion -> Maybe QuickMessage
parseQuickMessage layerAboveMainUINode =
    case
        layerAboveMainUINode
            |> listDescendantsWithDisplayRegion
            |> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "QuickMessage")
            |> List.head
    of
        Nothing ->
            Nothing

        Just quickMessageUINode ->
            let
                text =
                    quickMessageUINode.uiNode
                        |> getAllContainedDisplayTexts
                        |> List.head
                        |> Maybe.withDefault ""
            in
            Just
                { uiNode = quickMessageUINode
                , text = text
                }


getSubstringBetweenXmlTagsAfterMarker : String -> String -> Maybe String
getSubstringBetweenXmlTagsAfterMarker marker =
    String.split marker
        >> List.drop 1
        >> List.head
        >> Maybe.andThen (String.split ">" >> List.drop 1 >> List.head)
        >> Maybe.andThen (String.split "<" >> List.head)


parseNumberTruncatingAfterOptionalDecimalSeparator : String -> Result String Int
parseNumberTruncatingAfterOptionalDecimalSeparator numberDisplayText =
    let
        expectedSeparators : List String
        expectedSeparators =
            [ ",", ".", "’", "'", " ", "\u{00A0}", "\u{202F}" ]

        groupsTexts : List String
        groupsTexts =
            expectedSeparators
                |> List.foldl (\separator -> List.concatMap (String.split separator))
                    [ String.trim numberDisplayText ]

        lastGroupIsFraction : Bool
        lastGroupIsFraction =
            case List.reverse groupsTexts of
                lastGroupText :: _ :: _ ->
                    String.length lastGroupText < 3

                _ ->
                    False

        integerText : String
        integerText =
            String.join ""
                (if lastGroupIsFraction then
                    groupsTexts |> List.reverse |> List.drop 1 |> List.reverse

                 else
                    groupsTexts
                )
    in
    integerText
        |> String.toInt
        |> Result.fromMaybe ("Failed to parse to integer: " ++ integerText)


centerFromDisplayRegion : DisplayRegion -> Location2d
centerFromDisplayRegion region =
    { x = region.x + region.width // 2, y = region.y + region.height // 2 }


getDisplayText : EveOnline.MemoryReading.UITreeNode -> Maybe String
getDisplayText uiNode =
    [ "_setText", "_text" ]
        |> List.filterMap
            (\displayTextPropertyName ->
                uiNode.dictEntriesOfInterest
                    |> Dict.get displayTextPropertyName
                    |> Maybe.andThen getDisplayTextFromDictEntry
            )
        |> List.sortBy (String.length >> negate)
        |> List.head


getDisplayTextFromDictEntry : Json.Encode.Value -> Maybe String
getDisplayTextFromDictEntry dictEntryValue =
    case
        Json.Decode.decodeValue
            (Json.Decode.oneOf
                [ Json.Decode.string

                {-
                   2024-05-26: Observed in info panel:
                   Property '_setText' contained not string but a python object of type 'Link', which in turn references a dictionary.
                   That dictionary contains a key '_text' with the actual text.
                -}
                , Json.Decode.andThen
                    (\asNode ->
                        case getDisplayText asNode of
                            Just text ->
                                Json.Decode.succeed text

                            Nothing ->
                                Json.Decode.fail "Failed to extract text from Link object"
                    )
                    EveOnline.MemoryReading.uiTreeNodeDecoder
                ]
            )
            dictEntryValue
    of
        Err _ ->
            Nothing

        Ok ok ->
            Just ok


getAllContainedDisplayTexts : EveOnline.MemoryReading.UITreeNode -> List String
getAllContainedDisplayTexts uiNode =
    uiNode
        :: (uiNode |> EveOnline.MemoryReading.listDescendantsInUITreeNode)
        |> List.filterMap getDisplayText


getAllContainedDisplayTextsWithRegion : UITreeNodeWithDisplayRegion -> List ( String, UITreeNodeWithDisplayRegion )
getAllContainedDisplayTextsWithRegion uiNode =
    uiNode
        :: listDescendantsWithDisplayRegion uiNode
        |> List.filterMap
            (\descendant ->
                case getDisplayText descendant.uiNode of
                    Nothing ->
                        Nothing

                    Just displayText ->
                        if 0 < String.length displayText then
                            Just ( displayText, descendant )

                        else
                            Nothing
            )


getNameFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe String
getNameFromDictEntries =
    getStringPropertyFromDictEntries "_name"


getElementIdFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe String
getElementIdFromDictEntries =
    getStringPropertyFromDictEntries "_elementId"


getHintTextFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe String
getHintTextFromDictEntries =
    getStringPropertyFromDictEntries "_hint"


{-| Whether the client is rendering this node, from `_display`.

Absent means shown -- the client writes the key to hide something, not to
reveal it, and the overview's own rows carry no `_display` at all while plainly
on screen. `Bot.elm` has the identical function for the same reason; this copy
exists because `parseAgentMissionInfoPanelEntry` has to pick between two task
buttons where the hidden one is the wrong answer, and a parser cannot ask the
bot.

-}
nodeIsDisplayedFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Bool
nodeIsDisplayedFromDictEntries uiNode =
    uiNode.dictEntriesOfInterest
        |> Dict.get "_display"
        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.bool >> Result.toMaybe)
        |> Maybe.withDefault True


getTexturePathFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe String
getTexturePathFromDictEntries node =
    getStringPropertyFromDictEntries "texturePath" node
        |> Maybe.Extra.or (getStringPropertyFromDictEntries "_texturePath" node)


getStringPropertyFromDictEntries : String -> EveOnline.MemoryReading.UITreeNode -> Maybe String
getStringPropertyFromDictEntries dictEntryKey uiNode =
    uiNode.dictEntriesOfInterest
        |> Dict.get dictEntryKey
        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.string >> Result.toMaybe)


getColorPercentFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe ColorComponents
getColorPercentFromDictEntries =
    .dictEntriesOfInterest
        >> Dict.get "_color"
        >> Maybe.andThen (Json.Decode.decodeValue jsonDecodeColorPercent >> Result.toMaybe)


jsonDecodeColorPercent : Json.Decode.Decoder ColorComponents
jsonDecodeColorPercent =
    Json.Decode.map4 ColorComponents
        (Json.Decode.field "aPercent" jsonDecodeIntFromIntOrString)
        (Json.Decode.field "rPercent" jsonDecodeIntFromIntOrString)
        (Json.Decode.field "gPercent" jsonDecodeIntFromIntOrString)
        (Json.Decode.field "bPercent" jsonDecodeIntFromIntOrString)


getRotationFloatFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe Float
getRotationFloatFromDictEntries =
    .dictEntriesOfInterest
        >> Dict.get "_rotation"
        >> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)


getOpacityFloatFromDictEntries : EveOnline.MemoryReading.UITreeNode -> Maybe Float
getOpacityFloatFromDictEntries =
    .dictEntriesOfInterest
        >> Dict.get "_opacity"
        >> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)


jsonDecodeIntFromIntOrString : Json.Decode.Decoder Int
jsonDecodeIntFromIntOrString =
    Json.Decode.oneOf
        [ Json.Decode.int
        , Json.Decode.string
            |> Json.Decode.andThen
                (\asString ->
                    case asString |> String.toInt of
                        Just asInt ->
                            Json.Decode.succeed asInt

                        Nothing ->
                            Json.Decode.fail ("Failed to parse integer from string '" ++ asString ++ "'")
                )
        ]


getHorizontalOffsetFromParentAndWidth : EveOnline.MemoryReading.UITreeNode -> Maybe { offset : Int, width : Int }
getHorizontalOffsetFromParentAndWidth uiNode =
    let
        roundedNumberFromPropertyName propertyName =
            uiNode.dictEntriesOfInterest
                |> Dict.get propertyName
                |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)
                |> Maybe.map round
    in
    case ( roundedNumberFromPropertyName "_displayX", roundedNumberFromPropertyName "_width" ) of
        ( Just offset, Just width ) ->
            Just { offset = offset, width = width }

        _ ->
            Nothing


areaFromDisplayRegion : DisplayRegion -> Maybe Int
areaFromDisplayRegion region =
    if region.width < 0 || region.height < 0 then
        Nothing

    else
        Just (region.width * region.height)


getVerticalOffsetFromParent : EveOnline.MemoryReading.UITreeNode -> Maybe Int
getVerticalOffsetFromParent =
    .dictEntriesOfInterest
        >> Dict.get "_displayY"
        >> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)
        >> Maybe.map round


{-| Returns the subsequence of items not contained in any of the other ones
-}
subsequenceNotContainedInAnyOtherWithDisplayRegion :
    List UITreeNodeWithDisplayRegion
    -> List UITreeNodeWithDisplayRegion
subsequenceNotContainedInAnyOtherWithDisplayRegion original =
    original
        |> List.filter
            (\item ->
                original
                    |> List.any (\other -> item /= other && nodeDescendantsContainWithDisplayRegion item other)
                    |> not
            )


nodeDescendantsContainWithDisplayRegion : UITreeNodeWithDisplayRegion -> UITreeNodeWithDisplayRegion -> Bool
nodeDescendantsContainWithDisplayRegion =
    treeNodeDescendantsContain listChildrenWithDisplayRegion


{-| Returns True if the set of descendants of the second node contains the first node.
(Order of arguments is same as in `List.member`)
To learn more about these kinds of trees, see <https://en.wikipedia.org/wiki/Tree_(graph_theory)>
-}
treeNodeDescendantsContain : (node -> List node) -> node -> node -> Bool
treeNodeDescendantsContain childrenFromNode contained containing =
    let
        children =
            childrenFromNode containing
    in
    List.member contained children
        || List.any (treeNodeDescendantsContain childrenFromNode contained) children


getMostPopulousDescendantWithDisplayRegionMatchingPredicate :
    (UITreeNodeWithDisplayRegion -> Bool)
    -> UITreeNodeWithDisplayRegion
    -> Maybe UITreeNodeWithDisplayRegion
getMostPopulousDescendantWithDisplayRegionMatchingPredicate predicate parent =
    listDescendantsWithDisplayRegion parent
        |> List.filter predicate
        |> List.sortBy countDescendantsInUITreeNodeWithDisplayRegion
        |> List.reverse
        |> List.head


countDescendantsInUITreeNodeWithDisplayRegion : UITreeNodeWithDisplayRegion -> Int
countDescendantsInUITreeNodeWithDisplayRegion parent =
    parent.children
        |> Maybe.withDefault []
        |> List.filterMap unwrapUITreeNodeWithDisplayRegionChild
        |> List.map (countDescendantsInUITreeNodeWithDisplayRegion >> (+) 1)
        |> List.sum


unwrapUITreeNodeWithDisplayRegionChild : ChildOfNodeWithDisplayRegion -> Maybe UITreeNodeWithDisplayRegion
unwrapUITreeNodeWithDisplayRegionChild child =
    case child of
        ChildWithRegion node ->
            Just node

        ChildWithoutRegion _ ->
            Nothing


getMostPopulousDescendantMatchingPredicate :
    (EveOnline.MemoryReading.UITreeNode -> Bool)
    -> EveOnline.MemoryReading.UITreeNode
    -> Maybe EveOnline.MemoryReading.UITreeNode
getMostPopulousDescendantMatchingPredicate predicate parent =
    EveOnline.MemoryReading.listDescendantsInUITreeNode parent
        |> List.filter predicate
        |> List.sortBy EveOnline.MemoryReading.countDescendantsInUITreeNode
        |> List.reverse
        |> List.head


listDescendantsWithDisplayRegion : UITreeNodeWithDisplayRegion -> List UITreeNodeWithDisplayRegion
listDescendantsWithDisplayRegion parent =
    parent
        |> listChildrenWithDisplayRegion
        |> List.concatMap (\child -> child :: listDescendantsWithDisplayRegion child)


listChildrenWithDisplayRegion : UITreeNodeWithDisplayRegion -> List UITreeNodeWithDisplayRegion
listChildrenWithDisplayRegion parent =
    parent.children
        |> Maybe.withDefault []
        |> List.filterMap justCaseWithDisplayRegion


justCaseWithDisplayRegion : ChildOfNodeWithDisplayRegion -> Maybe UITreeNodeWithDisplayRegion
justCaseWithDisplayRegion child =
    case child of
        ChildWithoutRegion _ ->
            Nothing

        ChildWithRegion childWithRegion ->
            Just childWithRegion


nodeOccludesFollowingNodes : EveOnline.MemoryReading.UITreeNode -> Bool
nodeOccludesFollowingNodes node =
    Set.member node.pythonObjectTypeName pythonObjectTypesKnownToOccludeFollowingElements


pythonObjectTypesKnownToOccludeFollowingElements : Set.Set String
pythonObjectTypesKnownToOccludeFollowingElements =
    Set.fromList
        [ -- session-recording-2022-12-09T12-32-56.zip: In Overview window: "SortHeaders"
          "SortHeaders"
        , "ContextMenu"
        , "OverviewWindow"
        , "DronesWindow"
        , "SelectedItemWnd"
        , "InventoryPrimary"
        , "ChatWindowStack"
        ]


subtractRegionsFromRegion :
    { minuend : DisplayRegion
    , subtrahend : List DisplayRegion
    }
    -> List DisplayRegion
subtractRegionsFromRegion { minuend, subtrahend } =
    subtrahend
        |> List.foldl
            (\subtrahendPart previousResults ->
                previousResults
                    |> List.concatMap
                        (\minuendPart ->
                            subtractRegionFromRegion { subtrahend = subtrahendPart, minuend = minuendPart }
                        )
            )
            [ minuend ]


subtractRegionFromRegion :
    { minuend : DisplayRegion
    , subtrahend : DisplayRegion
    }
    -> List DisplayRegion
subtractRegionFromRegion { minuend, subtrahend } =
    let
        minuendRight =
            minuend.x + minuend.width

        minuendBottom =
            minuend.y + minuend.height

        subtrahendRight =
            subtrahend.x + subtrahend.width

        subtrahendBottom =
            subtrahend.y + subtrahend.height
    in
    {-
       Similar to approach from https://stackoverflow.com/questions/3765283/how-to-subtract-a-rectangle-from-another/15228510#15228510
       We want to support finding the largest rectangle, so we let them overlap here.

       ----------------------------
       |  A  |       A      |  A  |
       |  B  |              |  C  |
       |--------------------------|
       |  B  |  subtrahend  |  C  |
       |--------------------------|
       |  B  |              |  C  |
       |  D  |      D       |  D  |
       ----------------------------
    -}
    [ { left = minuend.x
      , top = minuend.y
      , right = minuendRight
      , bottom = minuendBottom |> min subtrahend.y
      }
    , { left = minuend.x
      , top = minuend.y
      , right = minuendRight |> min subtrahend.x
      , bottom = minuendBottom
      }
    , { left = minuend.x |> max subtrahendRight
      , top = minuend.y
      , right = minuendRight
      , bottom = minuendBottom
      }
    , { left = minuend.x
      , top = minuend.y |> max subtrahendBottom
      , right = minuendRight
      , bottom = minuendBottom
      }
    ]
        |> List.map
            (\rect ->
                { x = rect.left
                , y = rect.top
                , width = rect.right - rect.left
                , height = rect.bottom - rect.top
                }
            )
        |> List.filter (\rect -> 0 < rect.width && 0 < rect.height)
        |> listUnique


regionsOverlap : DisplayRegion -> DisplayRegion -> Bool
regionsOverlap regionA regionB =
    subtractRegionFromRegion
        { minuend = regionA
        , subtrahend = regionB
        }
        /= [ regionA ]


predicateAny : List (a -> Bool) -> a -> Bool
predicateAny predicates candidate =
    predicates
        |> List.any (\predicate -> predicate candidate)


{-| Remove duplicate values, keeping the first instance of each element which appears more than once.
-}
listUnique : List element -> List element
listUnique =
    List.foldr
        (\nextElement elements ->
            if elements |> List.member nextElement then
                elements

            else
                nextElement :: elements
        )
        []

# Parsed User Interface of the EVE Online Game Client

The parsed user interface is a common way to access parts of the user interface of the game client. It helps you navigate and find things faster.

The UI tree in the EVE Online client can contain thousands of nodes and tens of thousands of individual properties. Because of this large amount of data, navigating in there can be time-consuming. To make this easier, this library filters and transforms the memory reading result into a form that contains less redundant information and uses names more closely related to the experience of players; for example, the overview window or ship modules.

In the program code, we find the implementation in the module [`EveOnline.ParseUserInterface`](https://github.com/Viir/bots/blob/7a6fc657af8c1464a840aef2a0ff2c27e145078f/implement/applications/eve-online/eve-online-mining-bot/src/EveOnline/ParseUserInterface.elm).

Years of feedback from developers have shaped this library to contain shortcuts to the often used UI elements. Let's look at the root type to get a general idea of what we can find there:

```Elm
type alias ParsedUserInterface =
    { uiTree : UITreeNodeWithDisplayRegion
    , contextMenus : List ContextMenu
    , shipUI : MaybeVisible ShipUI
    , targets : List Target
    , infoPanelContainer : MaybeVisible InfoPanelContainer
    , overviewWindow : MaybeVisible OverviewWindow
    , selectedItemWindow : MaybeVisible SelectedItemWindow
    , dronesWindow : MaybeVisible DronesWindow
    , fittingWindow : MaybeVisible FittingWindow
    , probeScannerWindow : MaybeVisible ProbeScannerWindow
    , stationWindow : MaybeVisible StationWindow
    , inventoryWindows : List InventoryWindow
    , chatWindowStacks : List ChatWindowStack
    , agentConversationWindows : List AgentConversationWindow
    , marketOrdersWindow : MaybeVisible MarketOrdersWindow
    , moduleButtonTooltip : MaybeVisible ModuleButtonTooltip
    , neocom : MaybeVisible Neocom
    , messageBoxes : List MessageBox
    , layerAbovemain : MaybeVisible UITreeNodeWithDisplayRegion
    }
```

Using the `uiTree` field, we can access the raw UI tree. All the other fields contain derivations of the UI tree for easier access.

In case the names aren't clear, this annotated screenshot of the game client illustrates what is what, at least for some of the more popular elements:

![Some elements of the parsed user interface](./image/2020-03-11-eve-online-parsed-user-interface-names.png)

## ShipUI

### Modules

Some bots classify ship modules by their display location because this is faster than reading the tooltips. When you bot descriptions, you often find instructions to arrange modules into the three rows by use.
To access the modules grouped into these rows, use the function [`groupShipUIModulesIntoRows`](https://github.com/Viir/bots/blob/7a6fc657af8c1464a840aef2a0ff2c27e145078f/implement/applications/eve-online/eve-online-mining-bot/src/EveOnline/ParseUserInterface.elm#L377-L378):

`groupShipUIModulesIntoRows` returns this record with the fields `top`, `middle`, and `bottom`. Each of these rows is a list of modules:

```Elm
type alias ShipUIModulesGroupedIntoRows =
    { top : List ShipUIModule
    , middle : List ShipUIModule
    , bottom : List ShipUIModule
    }
```

![Ship UI modules grouped into rows](./image/2020-03-11-eve-online-ship-ui-module-rows-names.png)

The [mining bot example project](https://github.com/Viir/bots/blob/7a6fc657af8c1464a840aef2a0ff2c27e145078f/implement/applications/eve-online/eve-online-mining-bot/src/Bot.elm) also uses modules this way.

## Inventory Window

To work with items in the inventory, use the property `selectedContainerInventory` in the inventory window. In the property `itemsView`, you get this list of items visible in the selected container:

![Inventory items](./image/2020-03-11-eve-online-parsed-user-interface-inventory-inspect.png)

Are looking for an item with a specific name? You could use the filtering function in the game client, but there is an easier way: Using the function `getAllContainedDisplayTexts` on the inventory item, you can filter the list of items immediately.

As you can also see in the screenshot of the live inspector, we get the used, selected, and maximum capacity of the selected container with the property `selectedContainerCapacityGauge`. You can compare the `used` and `maximum` values to see if the container is (almost) full. The [mining bot does this](https://github.com/Viir/bots/blob/7a6fc657af8c1464a840aef2a0ff2c27e145078f/implement/applications/eve-online/eve-online-mining-bot/src/Bot.elm#L865-L870) on the ore hold to know when to travel to the unload location.

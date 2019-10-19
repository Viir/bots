{- This is an asteroid mining bot for EVE Online, based on a process suggested by MutantWizard:
    + https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/43?u=viir
    + https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/70?u=viir

    Setup instructions for the EVE Online client:
    + Disable `Run clients with 64 bit` in the settings, because this bot only works with the 32-bit version of the EVE Online client.
    + Set the UI language to English.
    + In Overview window, make asteroids visible.
    + Set the Overview window to sort objects in space by distance with the nearest entry at the top.
    + In the Inventory window select the ‘List’ view.
    + Setup inventory window so that Ore Hold is always selected.
    + In the ship UI, hide all modules which are no miners.
    + Enable the info panel ‘System info’.
    + Create bookmark 'mining' for the asteroid belt.
    + Create bookmark 'unload' for the station.
    + Before starting this bot, start the game client and dock in a station in the same system containing your mining bookmark.

   bot-catalog-tags:eve-online,mining
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import Sanderling.Sanderling as Sanderling exposing (MouseButton(..), centerFromRegion, effectMouseClickAtLocation)
import Sanderling.SanderlingMemoryMeasurement as SanderlingMemoryMeasurement
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , OverviewWindowEntry
        , ShipUi
        , ShipUiModule
        , UIElement
        , maybeNothingFromCanNotSeeIt
        )
import Sanderling.SimpleSanderling as SimpleSanderling exposing (BotEventAtTime, BotRequest(..))


type alias MemoryMeasurement =
    SanderlingMemoryMeasurement.MemoryMeasurementReducedWithNamedNodes


type BotProgramSequenceName
    = TravelToAsteroidBelt
    | MineInBelt
    | TravelToStation
    | TransferFromOreHold


type BotProgramStepResult
    = ApplyEffectAndFinishStep Sanderling.EffectOnWindowStructure
    | FinishStep
    | RepeatStep
    | JumpToNewSequence BotProgramSequenceName


type alias BotProgramStep =
    ( String, MemoryMeasurement -> BotProgramStepResult )


type alias BotProgramSequence =
    { steps : List BotProgramStep
    , continueWith : BotProgramSequenceName
    }


type alias SimpleState =
    { remainingSequence : BotProgramSequence
    }


type alias State =
    SimpleSanderling.StateIncludingSetup SimpleState


asteroidBookmarkName : String
asteroidBookmarkName =
    "mining"


stationBookmarkName : String
stationBookmarkName =
    "unload"


generalStepDelayMilliseconds : Int
generalStepDelayMilliseconds =
    2000


getProgramSequence : BotProgramSequenceName -> BotProgramSequence
getProgramSequence sequenceName =
    case sequenceName of
        TravelToAsteroidBelt ->
            { steps =
                [ ( "Undock ship: open menu"
                  , activeShipUiElementFromInventoryWindow
                        >> Maybe.map (clickLocationOnInventoryShipEntry >> effectMouseClickAtLocation MouseButtonRight >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Undock ship: click menu entry"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Undock")
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Travel to asteroid belt: wait for overview window"
                  , .overviewWindow
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map (always FinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Travel to asteroid belt: open solar system menu"
                  , .infoPanelCurrentSystem
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map (.listSurroundingsButton >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Travel to asteroid belt: open bookmark"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase asteroidBookmarkName)
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Travel to asteroid belt: click menu entry 'Warp to Location'"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Warp to Location")
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Travel to asteroid belt: click menu entry to start warp"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "Within 0 m")
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                ]
            , continueWith = MineInBelt
            }

        MineInBelt ->
            { steps =
                [ ( "when warp ends"
                  , .shipUi
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map isShipWarpingOrJumping
                        >> Maybe.withDefault True
                        >> mapBoolToOtherType { true = RepeatStep, false = FinishStep }
                  )
                , ( "right click first ore asteroid"
                  , firstAsteroidFromOverviewWindow
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonRight >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "and approach"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "approach")
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "(for reliability wait until ship stopped)"
                  , shipIsStopped
                        >> Maybe.withDefault False
                        >> mapBoolToOtherType { true = FinishStep, false = RepeatStep }
                  )
                , ( "when in range right click ore asteroid"
                  , firstAsteroidFromOverviewWindowInRange
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonRight >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "and lock target"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "lock")
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )

                -- Assume all visible modules are miners: Setup EVE Online client to hide any other module.
                , ( "click first high slot with mining laser"
                  , shipUiModules
                        >> List.head
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "click second high slot with mining laser"
                  , shipUiModules
                        >> List.drop 1
                        >> List.head
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "wait until ore hold full or asteroid depleted (both mining lasers stopped)"
                  , \memoryMeasurement ->
                        if memoryMeasurement |> isOreHoldFull |> Maybe.withDefault False then
                            FinishStep

                        else if memoryMeasurement |> shipUiModules |> List.all (.isActive >> (==) (Just False)) then
                            JumpToNewSequence MineInBelt

                        else
                            RepeatStep
                  )
                ]
            , continueWith = TravelToStation
            }

        TravelToStation ->
            { steps =
                [ ( "Travel to station: open solar system menu"
                  , .infoPanelCurrentSystem
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map (.listSurroundingsButton >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "Travel to station: open bookmark"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase stationBookmarkName)
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                , ( "and dock"
                  , getLastMenu
                        >> Maybe.andThen (menuEntryContainingTextIgnoringCase "dock")
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndFinishStep)
                        >> Maybe.withDefault RepeatStep
                  )
                ]
            , continueWith = TransferFromOreHold
            }

        TransferFromOreHold ->
            { steps =
                [ ( "click and hold to drag ore from ore hold to item hangar"
                  , \memoryMeasurement ->
                        case memoryMeasurement |> inventoryWindowItemHangar of
                            Nothing ->
                                RepeatStep

                            Just itemHangar ->
                                case memoryMeasurement |> inventoryWindowSelectedContainerFirstItem of
                                    Nothing ->
                                        JumpToNewSequence TravelToAsteroidBelt

                                    Just itemInInventory ->
                                        { startLocation = itemInInventory.region |> centerFromRegion
                                        , endLocation = itemHangar.region |> centerFromRegion
                                        , mouseButton = MouseButtonLeft
                                        }
                                            |> Sanderling.SimpleDragAndDrop
                                            |> ApplyEffectAndFinishStep
                  )
                ]

            -- https://forum.botengine.org/t/how-to-automate-mining-asteroids-in-eve-online/628/44?u=viir
            , continueWith = TransferFromOreHold
            }


initState : State
initState =
    SimpleSanderling.initState
        { remainingSequence = { steps = [], continueWith = TravelToAsteroidBelt } }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleSanderling.processEvent simpleProcessEvent


simpleProcessEvent : BotEventAtTime -> SimpleState -> { newState : SimpleState, requests : List BotRequest, statusMessage : String }
simpleProcessEvent eventAtTime stateBefore =
    case eventAtTime.event of
        SimpleSanderling.MemoryMeasurementCompleted memoryMeasurement ->
            let
                remainingSequenceBefore =
                    if 0 < (stateBefore.remainingSequence.steps |> List.length) then
                        stateBefore.remainingSequence

                    else
                        getProgramSequence stateBefore.remainingSequence.continueWith

                ( stepResult, stepDescription ) =
                    -- 'remainingSequence' stores only the remaining steps, so we always execute the first of the steps in there.
                    case remainingSequenceBefore.steps |> List.head of
                        Nothing ->
                            ( FinishStep, "Error: no step remaining" )

                        Just ( currentStepDescription, decideBasedOnMemoryMeasurement ) ->
                            ( decideBasedOnMemoryMeasurement memoryMeasurement, currentStepDescription )

                advancedSequence =
                    { remainingSequenceBefore | steps = remainingSequenceBefore.steps |> List.drop 1 }

                ( remainingSequence, effects ) =
                    case stepResult of
                        FinishStep ->
                            ( advancedSequence, [] )

                        ApplyEffectAndFinishStep effect ->
                            ( advancedSequence, [ effect ] )

                        RepeatStep ->
                            ( remainingSequenceBefore, [] )

                        JumpToNewSequence sequenceName ->
                            ( getProgramSequence sequenceName, [] )

                effectsRequests =
                    effects |> List.map EffectOnGameClientWindow

                requests =
                    effectsRequests ++ [ TakeMemoryMeasurementAfterDelayInMilliseconds generalStepDelayMilliseconds ]
            in
            { newState = { stateBefore | remainingSequence = remainingSequence }
            , requests = requests
            , statusMessage = stepDescription
            }

        SimpleSanderling.SetBotConfiguration botConfiguration ->
            { newState = stateBefore
            , requests = []
            , statusMessage =
                if botConfiguration |> String.isEmpty then
                    ""

                else
                    "I have a problem with this configuration: I am not programmed to support configuration at all. Maybe the bot catalog (https://to.botengine.org/bot-catalog) has a bot which better matches your use case?"
            }


activeShipUiElementFromInventoryWindow : MemoryMeasurement -> Maybe UIElement
activeShipUiElementFromInventoryWindow =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .leftTreeEntries
        -- Assume upmost entry is active ship.
        >> Maybe.andThen (List.sortBy (.uiElement >> .region >> .top) >> List.head)
        >> Maybe.map .uiElement


shipUiModules : MemoryMeasurement -> List ShipUiModule
shipUiModules =
    .shipUi >> maybeNothingFromCanNotSeeIt >> Maybe.map .modules >> Maybe.withDefault []


shipIsStopped : MemoryMeasurement -> Maybe Bool
shipIsStopped =
    .shipUi >> maybeNothingFromCanNotSeeIt >> Maybe.andThen .shipIsStopped


{-| Returns the menu entry containing the string from the parameter `textToSearch`.
If there are multiple such entries, these are sorted by the length of their text, minus whitespaces in the beginning and the end.
The one with the shortest text is returned.
-}
menuEntryContainingTextIgnoringCase : String -> SanderlingMemoryMeasurement.Menu -> Maybe SanderlingMemoryMeasurement.MenuEntry
menuEntryContainingTextIgnoringCase textToSearch =
    .entries
        >> List.filter (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))
        >> List.sortBy (.text >> String.trim >> String.length)
        >> List.head


getLastMenu : MemoryMeasurement -> Maybe SanderlingMemoryMeasurement.Menu
getLastMenu =
    .menus >> List.reverse >> List.head


firstAsteroidFromOverviewWindow : MemoryMeasurement -> Maybe OverviewWindowEntry
firstAsteroidFromOverviewWindow =
    overviewWindowEntriesRepresentingAsteroids >> List.head


firstAsteroidFromOverviewWindowInRange : MemoryMeasurement -> Maybe OverviewWindowEntry
firstAsteroidFromOverviewWindowInRange =
    firstAsteroidFromOverviewWindow
        >> Maybe.andThen
            (\asteroid ->
                if asteroid |> overviewWindowEntryIsInRange |> Maybe.withDefault False then
                    Just asteroid

                else
                    Nothing
            )


overviewWindowEntryIsInRange : OverviewWindowEntry -> Maybe Bool
overviewWindowEntryIsInRange =
    .distanceInMeters >> Result.map (\distanceInMeters -> distanceInMeters < 1000) >> Result.toMaybe


overviewWindowEntriesRepresentingAsteroids : MemoryMeasurement -> List OverviewWindowEntry
overviewWindowEntriesRepresentingAsteroids =
    .overviewWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map (.entries >> List.filter overviewWindowEntryRepresentsAnAsteroid)
        >> Maybe.withDefault []


overviewWindowEntryRepresentsAnAsteroid : OverviewWindowEntry -> Bool
overviewWindowEntryRepresentsAnAsteroid entry =
    (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "asteroid"))
        && (entry.textsLeftToRight |> List.any (String.toLower >> String.contains "belt") |> not)


isOreHoldFull : MemoryMeasurement -> Maybe Bool
isOreHoldFull =
    oreHoldFillPercent
        >> Maybe.map (\fillPercent -> fillPercent >= 99)


oreHoldFillPercent : MemoryMeasurement -> Maybe Int
oreHoldFillPercent =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen .selectedContainedCapacityGauge
        >> Maybe.map (\capacity -> capacity.used * 100 // capacity.maximum)


inventoryWindowSelectedContainerFirstItem : MemoryMeasurement -> Maybe UIElement
inventoryWindowSelectedContainerFirstItem =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen .selectedContainerInventory
        >> Maybe.andThen (.listViewItems >> List.head)


inventoryWindowItemHangar : MemoryMeasurement -> Maybe UIElement
inventoryWindowItemHangar =
    .inventoryWindow
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .leftTreeEntries
        >> Maybe.andThen (List.filter (.text >> String.toLower >> String.contains "item hangar") >> List.head)
        >> Maybe.map .uiElement


clickOnUIElement : MouseButton -> UIElement -> Sanderling.EffectOnWindowStructure
clickOnUIElement mouseButton uiElement =
    effectMouseClickAtLocation mouseButton (uiElement.region |> centerFromRegion)


{-| The region of a ship entry in the inventory window can contain child nodes (e.g. 'Ore Hold').
For this reason, we don't click on the center but stay close to the top.
-}
clickLocationOnInventoryShipEntry : UIElement -> Sanderling.Location2d
clickLocationOnInventoryShipEntry uiElement =
    { x = (uiElement.region.left + uiElement.region.right) // 2
    , y = uiElement.region.top + 7
    }


infoPanelRouteFirstMarkerFromMemoryMeasurement : MemoryMeasurement -> Maybe InfoPanelRouteRouteElementMarker
infoPanelRouteFirstMarkerFromMemoryMeasurement =
    .infoPanelRoute
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.map .routeElementMarker
        >> Maybe.map (List.sortBy (\routeMarker -> routeMarker.uiElement.region.left + routeMarker.uiElement.region.top))
        >> Maybe.andThen List.head


isShipWarpingOrJumping : ShipUi -> Bool
isShipWarpingOrJumping =
    .indication
        >> maybeNothingFromCanNotSeeIt
        >> Maybe.andThen (.maneuverType >> maybeNothingFromCanNotSeeIt)
        >> Maybe.map
            (\maneuverType ->
                [ SanderlingMemoryMeasurement.Warp, SanderlingMemoryMeasurement.Jump ]
                    |> List.member maneuverType
            )
        -- If the ship is just floating in space, there might be no indication displayed.
        >> Maybe.withDefault False


mapBoolToOtherType : { true : a, false : a } -> Bool -> a
mapBoolToOtherType { true, false } bool =
    if bool then
        true

    else
        false

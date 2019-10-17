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
import Regex
import Sanderling.Sanderling as Sanderling exposing (MouseButton(..), centerFromRegion, effectMouseClickAtLocation)
import Sanderling.SanderlingMemoryMeasurement as SanderlingMemoryMeasurement
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , MemoryMeasurementShipUi
        , OverviewWindowEntry
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
    = ApplyEffectAndContinue Sanderling.EffectOnWindowStructure
    | Continue
    | JumpToSequence BotProgramSequenceName
    | Wait


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
                        >> Maybe.map (clickLocationOnInventoryShipEntry >> effectMouseClickAtLocation MouseButtonRight >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Undock ship: click menu entry"
                  , menuEntryInLastMenuContainingTextIgnoringCase "Undock"
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Travel to asteroid belt: wait for overview window"
                  , .overviewWindow
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map (always Continue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Travel to asteroid belt: open solar system menu"
                  , .infoPanelCurrentSystem
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map (.listSurroundingsButton >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Travel to asteroid belt: open bookmark"
                  , menuEntryInLastMenuContainingTextIgnoringCase asteroidBookmarkName
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Travel to asteroid belt: click menu entry 'Warp to Within'"
                  , menuEntryInLastMenuContainingRegex menuEntry_Warp_to_Within_regex
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Travel to asteroid belt: click menu entry to start warp"
                  , menuEntryInLastMenuContainingTextIgnoringCase "Within 0 m"
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
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
                        >> mapBoolToOtherType { true = Wait, false = Continue }
                  )
                , ( "right click first ore asteroid"
                  , firstAsteroidFromOverviewWindow
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonRight >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "and approach"
                  , menuEntryInLastMenuContainingTextIgnoringCase "approach"
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "(for reliability wait until ship stopped)"
                  , shipIsStopped
                        >> Maybe.withDefault False
                        >> mapBoolToOtherType { true = Continue, false = Wait }
                  )
                , ( "when in range right click ore asteroid"
                  , firstAsteroidFromOverviewWindowInRange
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonRight >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "and lock target"
                  , menuEntryInLastMenuContainingTextIgnoringCase "lock"
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )

                -- Assume all visible modules are miners: Setup EVE Online client to hide any other module.
                , ( "click first high slot with mining laser"
                  , shipUiModules
                        >> List.head
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "click second high slot with mining laser"
                  , shipUiModules
                        >> List.drop 1
                        >> List.head
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "wait until ore hold full or asteroid depleted (both mining lasers stopped)"
                  , \memoryMeasurement ->
                        if memoryMeasurement |> isOreHoldFull |> Maybe.withDefault False then
                            Continue

                        else if memoryMeasurement |> shipUiModules |> List.all (.isActive >> (==) (Just False)) then
                            JumpToSequence MineInBelt

                        else
                            Wait
                  )
                ]
            , continueWith = TravelToStation
            }

        TravelToStation ->
            { steps =
                [ ( "Travel to station: open solar system menu"
                  , .infoPanelCurrentSystem
                        >> maybeNothingFromCanNotSeeIt
                        >> Maybe.map (.listSurroundingsButton >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "Travel to station: open bookmark"
                  , menuEntryInLastMenuContainingTextIgnoringCase stationBookmarkName
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
                  )
                , ( "and dock"
                  , menuEntryInLastMenuContainingTextIgnoringCase "dock"
                        >> Maybe.map (.uiElement >> clickOnUIElement MouseButtonLeft >> ApplyEffectAndContinue)
                        >> Maybe.withDefault Wait
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
                                Wait

                            Just itemHangar ->
                                case memoryMeasurement |> inventoryWindowSelectedContainerFirstItem of
                                    Nothing ->
                                        JumpToSequence TravelToAsteroidBelt

                                    Just itemInInventory ->
                                        { startLocation = itemInInventory.region |> centerFromRegion
                                        , endLocation = itemHangar.region |> centerFromRegion
                                        , mouseButton = MouseButtonLeft
                                        }
                                            |> Sanderling.SimpleDragAndDrop
                                            |> ApplyEffectAndContinue
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
                            ( Continue, "Error: no step remaining" )

                        Just ( currentStepDescription, decideBasedOnMemoryMeasurement ) ->
                            ( decideBasedOnMemoryMeasurement memoryMeasurement, currentStepDescription )

                advancedSequence =
                    { remainingSequenceBefore | steps = remainingSequenceBefore.steps |> List.drop 1 }

                ( remainingSequence, effects ) =
                    case stepResult of
                        Continue ->
                            ( advancedSequence, [] )

                        ApplyEffectAndContinue effect ->
                            ( advancedSequence, [ effect ] )

                        Wait ->
                            ( remainingSequenceBefore, [] )

                        JumpToSequence sequenceName ->
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


{-| <https://regex101.com/?regex=Warp%20to%20Within%28%3F%3D%5Cs%2A%24%29&testString=Warp%20to%20Within%0AWarp%20to%20Within%200%0AWarp%20to%20Within%20df%0AWarp%20to%20Within%20%0A>
-}
menuEntry_Warp_to_Within_regex : Regex.Regex
menuEntry_Warp_to_Within_regex =
    "Warp to Within(?=\\s*$)" |> Regex.fromStringWith { caseInsensitive = True, multiline = False } |> Maybe.withDefault Regex.never


menuEntryInLastMenuContainingTextIgnoringCase : String -> MemoryMeasurement -> Maybe SanderlingMemoryMeasurement.MemoryMeasurementMenuEntry
menuEntryInLastMenuContainingTextIgnoringCase textToSearch =
    menuEntryInLastMenuMatchingPredicate (.text >> String.toLower >> String.contains (textToSearch |> String.toLower))


menuEntryInLastMenuContainingRegex : Regex.Regex -> MemoryMeasurement -> Maybe SanderlingMemoryMeasurement.MemoryMeasurementMenuEntry
menuEntryInLastMenuContainingRegex regex =
    menuEntryInLastMenuMatchingPredicate (.text >> String.toLower >> Regex.contains regex)


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


menuEntryInLastMenuMatchingPredicate : (SanderlingMemoryMeasurement.MemoryMeasurementMenuEntry -> Bool) -> MemoryMeasurement -> Maybe SanderlingMemoryMeasurement.MemoryMeasurementMenuEntry
menuEntryInLastMenuMatchingPredicate predicate =
    .menus
        >> List.reverse
        >> List.head
        >> Maybe.andThen (.entries >> List.filter predicate >> List.head)


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


isShipWarpingOrJumping : MemoryMeasurementShipUi -> Bool
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

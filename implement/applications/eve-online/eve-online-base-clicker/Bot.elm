{- EVE Online base clicker bot

   This bot just clicks one of the entries in the overview window.

   To learn more about developing for EVE Online, see <https://to.botlab.org/guide/developing-for-eve-online>

-}
{-
   catalog-tags:eve-online,template
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2022_12_03 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.BotFramework
    exposing
        ( ReadingFromGameClient
        , clickOnUIElement
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , EndDecisionPathStructure(..)
        , decideActionForCurrentStep
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface
    exposing
        ( OverviewWindowEntry
        )


{-| Sources for the defaults:

  - <https://forum.botlab.org/t/mining-bot-wont-approach/3162>

-}
defaultBotSettings : BotSettings
defaultBotSettings =
    {}


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    {}


type alias BotMemory =
    {}


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


type alias State =
    EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory


baseClickerBotDecisionRoot : BotDecisionContext -> DecisionPathNode
baseClickerBotDecisionRoot context =
    case context.readingFromGameClient.overviewWindow of
        Nothing ->
            describeBranch
                "I do not see the overview window in the game client. Open the overview window manually"
                waitForProgressInGame

        Just overviewWindow ->
            describeBranch
                ("I see the overview window in the game client, showing " ++ String.fromInt (List.length overviewWindow.entries) ++ " entries")
                (case overviewWindow.entries |> List.head of
                    Nothing ->
                        describeBranch
                            "There is no entry in the overview window. Waiting for an object to appear in the overview..."
                            waitForProgressInGame

                    Just overviewEntry ->
                        describeBranch
                            "I see an entry in the overview and click on it."
                            (decideActionForCurrentStep
                                (clickOnUIElement MouseButtonLeft overviewEntry.uiNode)
                            )
                )


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            , decideNextStep = baseClickerBotDecisionRoot
            }
    }


initBotMemory : BotMemory
initBotMemory =
    {}


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        readingFromGameClient =
            context.readingFromGameClient

        describeShip =
            case readingFromGameClient.shipUI of
                Just shipUI ->
                    [ "Shield HP at " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%."
                    ]
                        |> String.join " "

                Nothing ->
                    case
                        readingFromGameClient.infoPanelContainer
                            |> Maybe.andThen .infoPanelLocationInfo
                            |> Maybe.andThen .expandedContent
                            |> Maybe.andThen .currentStationName
                    of
                        Just stationName ->
                            "I am docked at '" ++ stationName ++ "'."

                        Nothing ->
                            "I do not see if I am docked or in space. Please set up game client first."

        describeDrones =
            case readingFromGameClient.dronesWindow of
                Nothing ->
                    "I do not see the drones window."

                Just dronesWindow ->
                    "I see the drones window: In bay: "
                        ++ (dronesWindow.droneGroupInBay |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ ", in local space: "
                        ++ (dronesWindow.droneGroupInLocalSpace |> Maybe.andThen (.header >> .quantityFromTitle) |> Maybe.map String.fromInt |> Maybe.withDefault "Unknown")
                        ++ "."

        describeMiningHold =
            "mining hold filled "
                ++ (readingFromGameClient
                        |> inventoryWindowWithMiningHoldSelectedFromGameClient
                        |> Maybe.andThen capacityGaugeUsedPercent
                        |> Maybe.map String.fromInt
                        |> Maybe.withDefault "Unknown"
                   )
                ++ "%."

        describeCurrentReading =
            [ describeMiningHold, describeShip, describeDrones ] |> String.join " "
    in
    [ "Current reading: " ++ describeCurrentReading
    ]
        |> String.join "\n"


updateMemoryForNewReadingFromGame : EveOnline.BotFrameworkSeparatingMemory.UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =
    botMemoryBefore


capacityGaugeUsedPercent : EveOnline.ParseUserInterface.InventoryWindow -> Maybe Int
capacityGaugeUsedPercent =
    .selectedContainerCapacityGauge
        >> Maybe.andThen Result.toMaybe
        >> Maybe.andThen
            (\capacity -> capacity.maximum |> Maybe.map (\maximum -> capacity.used * 100 // maximum))


inventoryWindowWithMiningHoldSelectedFromGameClient : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.InventoryWindow
inventoryWindowWithMiningHoldSelectedFromGameClient =
    .inventoryWindows
        >> List.filter inventoryWindowSelectedContainerIsMiningHold
        >> List.head


inventoryWindowSelectedContainerIsMiningHold : EveOnline.ParseUserInterface.InventoryWindow -> Bool
inventoryWindowSelectedContainerIsMiningHold =
    .subCaptionLabelText >> Maybe.map (stringContainsIgnoringCase "mining hold") >> Maybe.withDefault False

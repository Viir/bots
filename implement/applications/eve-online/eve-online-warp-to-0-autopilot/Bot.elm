{- EVE Online warp-to-0 auto-pilot version 2025-10-14

   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.

   Before starting the bot, set up the game client as follows:

   + Set the UI language to English.
   + Set the in-game autopilot route.
   + Make sure the autopilot info panel is expanded, so that the route is visible.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `activate-module-always` : Text found in tooltips of ship modules that should always be active. For example: "cloaking device".

   To learn more about the autopilot, see <https://to.botlab.org/guide/app/eve-online-autopilot-bot>

-}
{-
   catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import BotLab.NotificationsShim
import Color
import Common.Basics exposing (stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow exposing (Location2d, MouseButton(..))
import Common.PromptParser as PromptParser
import Dict
import EveOnline.BotFramework
    exposing
        ( BotEvent(..)
        , ModuleButtonTooltipMemory
        , PixelValueRGB
        , ReadingFromGameClient
        , ShipModulesMemory
        , infoPanelRouteFirstMarkerFromReadingFromGameClient
        , menuCascadeCompleted
        , shipUIIndicatesShipIsWarpingOrJumping
        , useMenuEntryWithTextContainingFirstOf
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , UpdateMemoryContext
        , branchDependingOnDockedOrInSpace
        , clickModuleButtonButWaitIfClickedInPreviousStep
        , useContextMenuCascade
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion)


defaultBotSettings : BotSettings
defaultBotSettings =
    { activateModulesAlways = [] }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    PromptParser.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "activate-module-always"
           , { alternativeNames = []
             , description = "Text found in tooltips of ship modules that should always be active. For example: 'cloaking device'."
             , valueParser =
                PromptParser.valueTypeString
                    (\moduleName settings ->
                        { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways }
                    )
             }
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { activateModulesAlways : List String
    }


type alias BotMemory =
    { lastSolarSystemName : Maybe String
    , jumpsCompleted : Int
    , shipModules : ShipModulesMemory
    , didTravelEnRoute : Bool
    , lastReadingsWithoutRoute : Int
    }


type alias State =
    BotLab.NotificationsShim.StateWithNotifications
        (EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory)


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


initBotMemory : BotMemory
initBotMemory =
    { lastSolarSystemName = Nothing
    , jumpsCompleted = 0
    , shipModules = EveOnline.BotFramework.initShipModulesMemory
    , didTravelEnRoute = False
    , lastReadingsWithoutRoute = 0
    }


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        describeSessionPerformance =
            "jumps completed: " ++ (context.memory.jumpsCompleted |> String.fromInt)

        describeCurrentReading =
            [ [ "current solar system: "
                    ++ (currentSolarSystemNameFromReading context.readingFromGameClient |> Maybe.withDefault "Unknown")
              ]
            , if List.isEmpty context.eventContext.botSettings.activateModulesAlways then
                []

              else
                [ "Ship module buttons: " ++ describeShipModuleButtons context ]
            ]
                |> List.concat
                |> String.join "\n"
    in
    [ describeSessionPerformance
    , describeCurrentReading
    ]
        |> String.join "\n"


autopilotBotDecisionRoot : BotDecisionContext -> DecisionPathNode
autopilotBotDecisionRoot context =
    (case infoPanelRouteFirstMarkerFromReadingFromGameClient context.readingFromGameClient of
        Nothing ->
            {-
               Adapt to observation from session-recording-2024-06-02T13-10-35, as discussed on Discord — 03/06/2024 18:44:
               > Looks like in event 1101 the list of route markers was empty in the memory reading. Might be a sporadic fail to read that part of the UI. Probably the solution is not rely only on the last reading but consider previous readings as well.
            -}
            if context.memory.didTravelEnRoute && 3 < context.memory.lastReadingsWithoutRoute then
                describeBranch
                    "I see no route in the info panel. We finished traveling the route."
                    (Common.DecisionPath.endDecisionPath
                        EveOnline.BotFrameworkSeparatingMemory.FinishSession
                    )

            else
                describeBranch
                    "I see no route in the info panel. I will start when a route is set."
                    (decideStepWhenInSpaceWaiting context)

        Just infoPanelRouteFirstMarker ->
            branchDependingOnDockedOrInSpace
                { ifDocked =
                    describeBranch
                        "To continue, undock manually."
                        waitForProgressInGame
                , ifSeeShipUI =
                    decideStepWhenInSpace
                        context
                        { infoPanelRouteFirstMarker = infoPanelRouteFirstMarker }
                }
                context.readingFromGameClient
    )
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase 2000


decideStepWhenInSpace :
    BotDecisionContext
    -> { infoPanelRouteFirstMarker : EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker }
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
decideStepWhenInSpace context { infoPanelRouteFirstMarker } shipUI =
    if shipUIIndicatesShipIsWarpingOrJumping shipUI then
        describeBranch
            "I see the ship is warping or jumping. I wait until that maneuver ends."
            (decideStepWhenInSpaceWaiting context)

    else
        useContextMenuCascade
            ( "route element icon", infoPanelRouteFirstMarker.uiNode )
            (useMenuEntryWithTextContainingFirstOf
                [ "dock"

                -- https://forum.botlab.org/t/i-want-to-add-korean-support-on-eve-online-bot-what-should-i-do/4370/14
                , "도킹"
                , "jump"

                -- https://forum.botlab.org/t/i-want-to-add-korean-support-on-eve-online-bot-what-should-i-do/4370
                , "점프 - 스타게이트 사용"
                ]
                menuCascadeCompleted
            )
            context


decideStepWhenInSpaceWaiting : BotDecisionContext -> DecisionPathNode
decideStepWhenInSpaceWaiting context =
    case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> moduleButtonLooksActive context >> Maybe.withDefault False >> not) |> List.head of
        Just ( inactiveModuleMatchingText, inactiveModule ) ->
            describeBranch ("I see inactive module '" ++ inactiveModuleMatchingText ++ "' to activate always. Activate it.")
                (describeBranch "Click on the module."
                    (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)
                )

        Nothing ->
            readShipUIModuleButtonTooltips context |> Maybe.withDefault waitForProgressInGame


updateMemoryForNewReadingFromGame : UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context memoryBefore =
    let
        ( lastSolarSystemName, newJumpsCompleted ) =
            case currentSolarSystemNameFromReading context.readingFromGameClient of
                Nothing ->
                    ( memoryBefore.lastSolarSystemName, 0 )

                Just currentSolarSystemName ->
                    ( Just currentSolarSystemName
                    , if
                        (memoryBefore.lastSolarSystemName /= Nothing)
                            && (memoryBefore.lastSolarSystemName /= Just currentSolarSystemName)
                      then
                        1

                      else
                        0
                    )

        doesTravelEnRoute : Bool
        doesTravelEnRoute =
            case infoPanelRouteFirstMarkerFromReadingFromGameClient context.readingFromGameClient of
                Nothing ->
                    False

                Just _ ->
                    case context.readingFromGameClient.shipUI of
                        Nothing ->
                            False

                        Just shipUI ->
                            shipUIIndicatesShipIsWarpingOrJumping shipUI

        lastReadingsWithoutRoute =
            if doesTravelEnRoute then
                0

            else
                memoryBefore.lastReadingsWithoutRoute + 1
    in
    { jumpsCompleted = memoryBefore.jumpsCompleted + newJumpsCompleted
    , lastSolarSystemName = lastSolarSystemName
    , shipModules =
        EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory
            context.readingFromGameClient
            memoryBefore.shipModules
    , didTravelEnRoute = memoryBefore.didTravelEnRoute || doesTravelEnRoute
    , lastReadingsWithoutRoute = lastReadingsWithoutRoute
    }


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    case context.readingFromGameClient.shipUI of
        Nothing ->
            []

        Just shipUI ->
            shipUI.moduleButtons
                |> List.filterMap
                    (\moduleButton ->
                        case
                            EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton
                                context.memory.shipModules
                                moduleButton
                        of
                            Nothing ->
                                Nothing

                            Just moduleButtonTooltip ->
                                case tooltipLooksLikeModuleToActivateAlways context moduleButtonTooltip of
                                    Nothing ->
                                        Nothing

                                    Just moduleName ->
                                        Just ( moduleName, moduleButton )
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
            , decideNextStep = autopilotBotDecisionRoot
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            }
    }
        |> BotLab.NotificationsShim.addNotifications notificationsFunction


notificationsFunction : { statusText : String } -> List BotLab.NotificationsShim.Notification
notificationsFunction botResponse =
    [ ( "undock manually"
      , BotLab.NotificationsShim.consoleBeepNotification
            [ { frequency = 0
              , durationInMs = 200
              }
            , { frequency = 400
              , durationInMs = 300
              }
            , { frequency = 500
              , durationInMs = 300
              }
            ]
      )
    ]
        |> List.filterMap
            (\( keyword, notification ) ->
                if botResponse.statusText |> String.toLower |> String.contains (String.toLower keyword) then
                    Just notification

                else
                    Nothing
            )


currentSolarSystemNameFromReading : ReadingFromGameClient -> Maybe String
currentSolarSystemNameFromReading readingFromGameClient =
    readingFromGameClient.infoPanelContainer
        |> Maybe.andThen .infoPanelLocationInfo
        |> Maybe.andThen .currentSolarSystemName


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.BotFrameworkSeparatingMemory.readShipUIModuleButtonTooltipWhereNotYetInMemory


locationToMeasureGlowFromModuleButton : EveOnline.ParseUserInterface.ShipUIModuleButton -> Location2d
locationToMeasureGlowFromModuleButton moduleButton =
    let
        moduleButtonCenter =
            moduleButton.uiNode.totalDisplayRegion |> centerFromDisplayRegion
    in
    { x = moduleButtonCenter.x - 20, y = moduleButtonCenter.y }


describeShipModuleButtons : BotDecisionContext -> String
describeShipModuleButtons context =
    case context.readingFromGameClient.shipUI of
        Nothing ->
            "I see no ship UI"

        Just shipUI ->
            let
                moduleButtonsRowsList =
                    [ shipUI.moduleButtonsRows.top
                    , shipUI.moduleButtonsRows.middle
                    , shipUI.moduleButtonsRows.bottom
                    ]

                describeGreenessOfPixelValue { activeIndicationSampledPixels, activeIndicationPixelGreenessPercent } =
                    Maybe.withDefault "None" (Maybe.map String.fromInt activeIndicationPixelGreenessPercent)
                        ++ " % ("
                        ++ String.fromInt (List.length activeIndicationSampledPixels)
                        ++ " sampled pixels)"

                describeAllModuleButtonsGreeness =
                    moduleButtonsRowsList
                        |> List.indexedMap
                            (\rowIndex row ->
                                row
                                    |> List.indexedMap
                                        (\columnIndex moduleButton ->
                                            let
                                                maybeGreennessText =
                                                    moduleButtonImageProcessing context moduleButton
                                                        |> describeGreenessOfPixelValue
                                            in
                                            "["
                                                ++ String.fromInt rowIndex
                                                ++ ","
                                                ++ String.fromInt columnIndex
                                                ++ "]: "
                                                ++ maybeGreennessText
                                        )
                                    |> String.join ", "
                            )
                        |> String.join "\n"
            in
            "I see "
                ++ (moduleButtonsRowsList |> List.map List.length |> List.sum |> String.fromInt)
                ++ " module buttons in total, with greenness as follows:\n"
                ++ describeAllModuleButtonsGreeness


moduleButtonLooksActive : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUIModuleButton -> Maybe Bool
moduleButtonLooksActive context moduleButton =
    if moduleButton.isActive == Just True then
        moduleButton.isActive

    else
        {-
           Adapt to discovery in March 2021 by Victor Santamaría Caballero and Samuel Pagé:
           Some module buttons don't have the ramp:
           https://forum.botlab.org/t/cloaking-device-in-warp-to-0-bot/3917/3
        -}
        case (moduleButtonImageProcessing context moduleButton).activeIndicationPixelGreenessPercent of
            Nothing ->
                moduleButton.isActive

            Just greenness ->
                Just (4 < greenness)


moduleButtonImageProcessing :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUIModuleButton
    -> { activeIndicationSampledPixels : List PixelValueRGB, activeIndicationPixelGreenessPercent : Maybe Int }
moduleButtonImageProcessing context moduleButton =
    let
        measurementLocation : Location2d
        measurementLocation =
            locationToMeasureGlowFromModuleButton moduleButton

        sampledLocations : List ( Int, Int )
        sampledLocations =
            [ ( -1, 0 )
            , ( -1, 1 )
            , ( 0, 0 )
            , ( 0, 1 )
            , ( 1, 0 )
            , ( 1, 1 )
            ]
                |> List.map
                    (\( offsetX, offsetY ) ->
                        ( measurementLocation.x // 2 + offsetX
                        , measurementLocation.y // 2 + offsetY
                        )
                    )

        activeIndicationSampledPixels : List PixelValueRGB
        activeIndicationSampledPixels =
            sampledLocations
                |> List.filterMap context.screenshot.pixels_2x2

        activeIndicationSampledPixelsGreenessPercents : List Int
        activeIndicationSampledPixelsGreenessPercents =
            List.map greenessPercentFromPixelValue activeIndicationSampledPixels

        activeIndicationPixelGreenessPercent : Maybe Int
        activeIndicationPixelGreenessPercent =
            if 0 < List.length activeIndicationSampledPixelsGreenessPercents then
                activeIndicationSampledPixelsGreenessPercents
                    |> List.sort
                    |> List.drop (List.length activeIndicationSampledPixelsGreenessPercents // 2)
                    |> List.head

            else
                Nothing
    in
    { activeIndicationSampledPixels = activeIndicationSampledPixels
    , activeIndicationPixelGreenessPercent = activeIndicationPixelGreenessPercent
    }


greenessPercentFromPixelValue : PixelValueRGB -> Int
greenessPercentFromPixelValue pixelValue =
    -- https://www.w3.org/TR/css-color-3/#hsl-color
    let
        hsla : { hue : Float, saturation : Float, lightness : Float, alpha : Float }
        hsla =
            Color.toHsla (Color.rgb255 pixelValue.red pixelValue.green pixelValue.blue)

        hueGreenessFactor : Float
        hueGreenessFactor =
            max 0 (1 - (abs (hsla.hue - 0.333) * 4))
    in
    round ((hueGreenessFactor * hsla.saturation) * 100)

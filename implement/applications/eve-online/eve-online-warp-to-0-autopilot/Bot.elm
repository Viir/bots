{- EVE Online Warp-to-0 auto-pilot version 2022-01-29

   This bot makes your travels faster and safer by directly warping to gates/stations. It follows the route set in the in-game autopilot and uses the context menu to initiate jump and dock commands.

   Before starting the bot, set up the game client as follows:

   + Set the UI language to English.
   + Set the in-game autopilot route.
   + Make sure the autopilot info panel is expanded, so that the route is visible.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.

   + `module-to-activate-always` : Text found in tooltips of ship modules that should always be active. For example: "cloaking device".

   To learn about the autopilot, see https://to.botlab.org/guide/app/eve-online-autopilot-bot

-}
{-
   catalog-tags:eve-online,auto-pilot,travel
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Color
import Common.AppSettings as AppSettings
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow exposing (Location2d, MouseButton(..))
import Dict
import EveOnline.BotFramework
    exposing
        ( BotEvent(..)
        , PixelValueRGB
        , ReadingFromGameClient
        , SeeUndockingComplete
        , ShipModulesMemory
        , clickOnUIElement
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
        , decideActionForCurrentStep
        , useContextMenuCascade
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface exposing (centerFromDisplayRegion, getAllContainedDisplayTexts)


defaultBotSettings : BotSettings
defaultBotSettings =
    { modulesToActivateAlways = [] }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "module-to-activate-always"
           , AppSettings.valueTypeString (\moduleName -> \settings -> { settings | modulesToActivateAlways = moduleName :: settings.modulesToActivateAlways })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


type alias BotSettings =
    { modulesToActivateAlways : List String
    }


type alias BotMemory =
    { lastSolarSystemName : Maybe String
    , jumpsCompleted : Int
    , shipModules : ShipModulesMemory
    }


type alias State =
    EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory


type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


initBotMemory : BotMemory
initBotMemory =
    { lastSolarSystemName = Nothing
    , jumpsCompleted = 0
    , shipModules = EveOnline.BotFramework.initShipModulesMemory
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
            , if List.isEmpty context.eventContext.botSettings.modulesToActivateAlways then
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
    branchDependingOnDockedOrInSpace
        { ifDocked = describeBranch "To continue, undock manually." waitForProgressInGame
        , ifSeeShipUI = always Nothing
        , ifUndockingComplete = decideStepWhenInSpace context
        }
        context.readingFromGameClient
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase 2000


decideStepWhenInSpace : BotDecisionContext -> SeeUndockingComplete -> DecisionPathNode
decideStepWhenInSpace context undockingComplete =
    case context.readingFromGameClient |> infoPanelRouteFirstMarkerFromReadingFromGameClient of
        Nothing ->
            describeBranch "I see no route in the info panel. I will start when a route is set."
                (decideStepWhenInSpaceWaiting context)

        Just infoPanelRouteFirstMarker ->
            if undockingComplete.shipUI |> shipUIIndicatesShipIsWarpingOrJumping then
                describeBranch
                    "I see the ship is warping or jumping. I wait until that maneuver ends."
                    (decideStepWhenInSpaceWaiting context)

            else
                useContextMenuCascade
                    ( "route element icon", infoPanelRouteFirstMarker.uiNode )
                    (useMenuEntryWithTextContainingFirstOf
                        [ "dock", "jump" ]
                        menuCascadeCompleted
                    )
                    context


decideStepWhenInSpaceWaiting : BotDecisionContext -> DecisionPathNode
decideStepWhenInSpaceWaiting context =
    case context |> knownModulesToActivateAlways |> List.filter (Tuple.second >> moduleButtonLooksActive context >> Maybe.withDefault False >> not) |> List.head of
        Just ( inactiveModuleMatchingText, inactiveModule ) ->
            describeBranch ("I see inactive module '" ++ inactiveModuleMatchingText ++ "' to activate always. Activate it.")
                (describeBranch "Click on the module."
                    (decideActionForCurrentStep
                        (inactiveModule.uiNode |> clickOnUIElement MouseButtonLeft)
                    )
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
    in
    { jumpsCompleted = memoryBefore.jumpsCompleted + newJumpsCompleted
    , lastSolarSystemName = lastSolarSystemName
    , shipModules =
        EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory
            context.readingFromGameClient
            memoryBefore.shipModules
    }


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


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> EveOnline.ParseUserInterface.ModuleButtonTooltip -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .uiNode
        >> .uiNode
        >> getAllContainedDisplayTexts
        >> List.filterMap
            (\tooltipText ->
                context.eventContext.botSettings.modulesToActivateAlways
                    |> List.filterMap
                        (\moduleToActivateAlways ->
                            if tooltipText |> String.toLower |> String.contains (moduleToActivateAlways |> String.toLower) then
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
        EveOnline.BotFrameworkSeparatingMemory.processEventWithImageProcessing
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , screenshotRegionsToRead = screenshotRegionsToRead
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , decideNextStep = autopilotBotDecisionRoot
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            }
    }


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


screenshotRegionsToRead :
    ReadingFromGameClient
    -> { rects1x1 : List EveOnline.BotFrameworkSeparatingMemory.Rect2dStructure }
screenshotRegionsToRead memoryReading =
    let
        shipModuleButtons =
            case memoryReading.shipUI of
                Nothing ->
                    []

                Just shipUI ->
                    shipUI.moduleButtons
    in
    { rects1x1 =
        shipModuleButtons
            |> List.map locationToMeasureGlowFromModuleButton
            |> List.map (\location -> { x = location.x, y = location.y, width = 1, height = 1 })
    }


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

                describeGreenessOfPixelValue { activeIndicationPixelGreenAbsolute, activeIndicationPixelGreenessPercent } =
                    String.fromInt activeIndicationPixelGreenessPercent
                        ++ " % ("
                        ++ String.fromInt activeIndicationPixelGreenAbsolute
                        ++ ")"

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
                                                        |> Maybe.map describeGreenessOfPixelValue
                                            in
                                            "["
                                                ++ String.fromInt rowIndex
                                                ++ ","
                                                ++ String.fromInt columnIndex
                                                ++ "]: "
                                                ++ (maybeGreennessText |> Maybe.withDefault "??")
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
        case moduleButtonImageProcessing context moduleButton of
            Nothing ->
                moduleButton.isActive

            Just greenness ->
                Just (4 < greenness.activeIndicationPixelGreenessPercent)


moduleButtonImageProcessing :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUIModuleButton
    -> Maybe { activeIndicationPixelGreenAbsolute : Int, activeIndicationPixelGreenessPercent : Int }
moduleButtonImageProcessing context moduleButton =
    let
        measurementLocation =
            locationToMeasureGlowFromModuleButton moduleButton
    in
    context.readingFromGameClientImage.pixels1x1
        |> Dict.get ( measurementLocation.x, measurementLocation.y )
        |> Maybe.map
            (\pixelValue ->
                { activeIndicationPixelGreenAbsolute = pixelValue.green
                , activeIndicationPixelGreenessPercent = greenessPercentFromPixelValue pixelValue
                }
            )


greenessPercentFromPixelValue : PixelValueRGB -> Int
greenessPercentFromPixelValue pixelValue =
    -- https://www.w3.org/TR/css-color-3/#hsl-color
    let
        hsla =
            Color.toHsla (Color.rgb255 pixelValue.red pixelValue.green pixelValue.blue)

        hueGreenessFactor =
            max 0 (1 - (abs (hsla.hue - 0.333) * 4))
    in
    round ((hueGreenessFactor * hsla.saturation) * 100)

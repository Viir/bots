{- EVE Online demo distinguish rect and cross in autopilot route

   For the scenario from https://forum.botlab.org/t/i-want-to-distinguish-rect-and-cross-for-route/4310

-}
{-
   catalog-tags:eve-online,mining
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Common.AppSettings as AppSettings
import Dict
import EveOnline.BotFramework
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , EndDecisionPathStructure(..)
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface
import Set


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


type AutoPilotRouteMarkerType
    = RectMarker
    | CrossMarker


type alias MarkerClassificationReport =
    { centerColor : EveOnline.BotFramework.PixelValueRGB
    , class : AutoPilotRouteMarkerType
    }


initBotMemory : BotMemory
initBotMemory =
    {}


imageReadingLocationsForMarker :
    EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
    -> { center : ( Int, Int ), corner : ( Int, Int ) }
imageReadingLocationsForMarker routeMarker =
    let
        displayRegion =
            routeMarker.uiNode.totalDisplayRegion

        centerLocation =
            ( displayRegion.x + displayRegion.width // 2
            , displayRegion.y + displayRegion.height // 2
            )

        cornerLocation =
            ( displayRegion.x + displayRegion.width // 2 - 2
            , displayRegion.y + displayRegion.height // 2 - 2
            )
    in
    { center = centerLocation
    , corner = cornerLocation
    }


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEventWithImageProcessing
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , screenshotRegionsToRead = screenshotRegionsToRead
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            , decideNextStep = botDecisionRoot
            }
    }


screenshotRegionsToRead :
    EveOnline.BotFramework.ReadingFromGameClient
    -> { rects1x1 : List EveOnline.BotFrameworkSeparatingMemory.Rect2dStructure }
screenshotRegionsToRead readingFromGameClient =
    { rects1x1 =
        getAutopilotRouteMarkers readingFromGameClient
            |> List.map .screenshotRegionToRead
    }


getAutopilotRouteMarkers :
    EveOnline.BotFramework.ReadingFromGameClient
    ->
        List
            { uiNode : EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
            , screenshotRegionToRead : EveOnline.BotFrameworkSeparatingMemory.Rect2dStructure
            , classification : BotDecisionContext -> Maybe MarkerClassificationReport
            }
getAutopilotRouteMarkers readingFromGameClient =
    readingFromGameClient.infoPanelContainer
        |> Maybe.andThen .infoPanelRoute
        |> Maybe.map .routeElementMarker
        |> Maybe.withDefault []
        |> List.sortBy (\routeMarker -> routeMarker.uiNode.totalDisplayRegion.x + routeMarker.uiNode.totalDisplayRegion.y)
        |> List.map
            (\uiNode ->
                { uiNode = uiNode
                , screenshotRegionToRead = uiNode.uiNode.totalDisplayRegion
                , classification =
                    \context -> classifyMarker context.readingFromGameClientImage.pixels1x1 uiNode
                }
            )


{-| Classify the shape of an autopilot route marker from the info panel into 'rectangular' or 'cross'. For an example, see the screenshot shared by a876691666 at <https://forum.botlab.org/t/i-want-to-distinguish-rect-and-cross-for-route/4310>

To distinguish these two shapes, take the color of a pixel in a corner and compare it with the center color. In the rectangular shape, both colors should be very similar. If the marker has a cross shape, the colors will be different.

-}
classifyMarker :
    Dict.Dict ( Int, Int ) EveOnline.BotFramework.PixelValueRGB
    -> EveOnline.ParseUserInterface.InfoPanelRouteRouteElementMarker
    -> Maybe MarkerClassificationReport
classifyMarker pixelsDict routeMarker =
    let
        readingLocations =
            imageReadingLocationsForMarker routeMarker
    in
    case Dict.get readingLocations.center pixelsDict of
        Nothing ->
            Nothing

        Just centerColor ->
            case Dict.get readingLocations.corner pixelsDict of
                Nothing ->
                    Nothing

                Just cornerColor ->
                    let
                        differencesSum =
                            [ cornerColor.red - centerColor.red
                            , cornerColor.green - centerColor.green
                            , cornerColor.blue - centerColor.blue
                            ]
                                |> List.map abs
                                |> List.sum

                        class =
                            if differencesSum < 30 then
                                RectMarker

                            else
                                CrossMarker
                    in
                    Just { centerColor = centerColor, class = class }


statusTextFromDecisionContext : BotDecisionContext -> String
statusTextFromDecisionContext context =
    let
        autopilotRouteMarkers =
            context.readingFromGameClient
                |> getAutopilotRouteMarkers
                |> List.map (\marker -> ( marker.classification context, marker ))

        labelFromClass class =
            case class of
                Nothing ->
                    "Unidentified"

                Just RectMarker ->
                    "Rect"

                Just CrossMarker ->
                    "Cross"

        aggregatedByClass =
            autopilotRouteMarkers
                |> List.map (Tuple.first >> Maybe.map .class >> labelFromClass)
                |> Set.fromList
                |> Set.toList
                |> List.map
                    (\class ->
                        ( class
                        , autopilotRouteMarkers
                            |> List.filter (Tuple.first >> Maybe.map .class >> labelFromClass >> (==) class)
                        )
                    )
                |> Dict.fromList

        listSumsText =
            aggregatedByClass
                |> Dict.toList
                |> List.sortBy Tuple.first
                |> List.map
                    (\( classLabel, instances ) ->
                        classLabel ++ ": " ++ String.fromInt (List.length instances)
                    )
                |> String.join ", "

        instancesListText =
            autopilotRouteMarkers
                |> List.map (Tuple.first >> Maybe.map .class >> labelFromClass)
                |> String.join ", "

        describeFirstCenterColor =
            case autopilotRouteMarkers of
                [] ->
                    "No marker"

                ( firstMarkerClassification, _ ) :: _ ->
                    case firstMarkerClassification |> Maybe.map .centerColor of
                        Nothing ->
                            "No color"

                        Just centerColor ->
                            describeColor centerColor

        describeRouteMarkers =
            "Found "
                ++ String.fromInt (List.length autopilotRouteMarkers)
                ++ " markers in the autopilot route: "
                ++ listSumsText
                ++ ": "
                ++ instancesListText
                ++ ". Center of the first marker: "
                ++ describeFirstCenterColor
    in
    [ describeRouteMarkers
    , statusTextGeneralGuide
    ]
        |> String.join "\n"


describeColor : EveOnline.BotFramework.PixelValueRGB -> String
describeColor color =
    [ ( "red", .red ), ( "green", .green ), ( "blue", .blue ) ]
        |> List.map
            (\( name, getter ) ->
                name ++ ": " ++ String.fromInt (getter color)
            )
        |> String.join ", "


statusTextGeneralGuide : String
statusTextGeneralGuide =
    """
EVE Online demo distinguish rect and cross in autopilot route
For the scenario from https://forum.botlab.org/t/i-want-to-distinguish-rect-and-cross-for-route/4310
"""


botDecisionRoot : BotDecisionContext -> DecisionPathNode
botDecisionRoot context =
    waitForProgressInGame


updateMemoryForNewReadingFromGame : EveOnline.BotFrameworkSeparatingMemory.UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =
    botMemoryBefore

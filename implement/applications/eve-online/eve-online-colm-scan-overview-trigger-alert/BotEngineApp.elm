{- Colm EVE Online bot version 2020-06-22
   Scan overview and trigger alert part as described by Colm at https://forum.botengine.org/t/danger-warning/3394
-}
{-
   app-catalog-tags:custom-app,eve-online
   authors-forum-usernames:colm,viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200610 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))
import EveOnline.AppFramework exposing (AppEffect(..))
import EveOnline.ParseUserInterface exposing (MaybeVisible(..))


type alias BotState =
    { lastSeenPlayerOverviewEntries : List EveOnline.ParseUserInterface.OverviewWindowEntry
    }


type alias State =
    EveOnline.AppFramework.StateIncludingFramework () BotState


isPlayerEntry : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
isPlayerEntry =
    always True


initState : State
initState =
    EveOnline.AppFramework.initState
        { lastSeenPlayerOverviewEntries = []
        }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { processEvent = processEveOnlineBotEvent
        , parseAppSettings = AppSettings.parseAllowOnlyEmpty ()
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext ()
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            let
                ( state, effects, statusDescriptionText ) =
                    case readingFromGameClient.overviewWindow of
                        CanNotSeeIt ->
                            ( stateBefore
                            , []
                            , "I do not see the overview window."
                            )

                        CanSee overviewWindow ->
                            let
                                playerOverviewEntries =
                                    overviewWindow.entries |> List.filter isPlayerEntry

                                describeOverview =
                                    "I see the overview window with "
                                        ++ (overviewWindow.entries |> List.length |> String.fromInt)
                                        ++ " entries, "
                                        ++ (playerOverviewEntries |> List.length |> String.fromInt)
                                        ++ " of which are players."

                                wasPlayerEntryAlreadyVisibleInPreviousReading candidateEntry =
                                    stateBefore.lastSeenPlayerOverviewEntries
                                        |> List.any (areEntriesRepresentingTheSamePlayer candidateEntry)

                                newPlayerEntries =
                                    playerOverviewEntries
                                        |> List.filter (wasPlayerEntryAlreadyVisibleInPreviousReading >> not)

                                { describeNewPlayerEntries, newPlayerEffects } =
                                    case newPlayerEntries |> List.head of
                                        Nothing ->
                                            { describeNewPlayerEntries = "Found no new player.", newPlayerEffects = [] }

                                        Just newPlayer ->
                                            { describeNewPlayerEntries =
                                                "Found new player: "
                                                    ++ (newPlayer.objectName |> Maybe.withDefault "")
                                                    ++ ", "
                                                    ++ (newPlayer.objectType |> Maybe.withDefault "")
                                            , newPlayerEffects =
                                                [ EffectConsoleBeepSequence
                                                    [ { durationInMs = 300, frequency = 100 }
                                                    , { durationInMs = 300, frequency = 150 }
                                                    ]
                                                ]
                                            }
                            in
                            ( { stateBefore | lastSeenPlayerOverviewEntries = playerOverviewEntries }
                            , newPlayerEffects
                            , [ describeOverview, describeNewPlayerEntries ] |> String.join "\n"
                            )
            in
            ( state
            , EveOnline.AppFramework.ContinueSession
                { millisecondsToNextReadingFromGame = 500
                , effects = effects
                , statusDescriptionText = statusDescriptionText
                }
            )


areEntriesRepresentingTheSamePlayer : EveOnline.ParseUserInterface.OverviewWindowEntry -> EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
areEntriesRepresentingTheSamePlayer entryA entryB =
    [ entryA.objectName, entryA.objectType ] == [ entryB.objectName, entryB.objectType ]

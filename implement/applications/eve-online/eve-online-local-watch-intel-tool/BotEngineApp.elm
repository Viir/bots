{- EVE Online Intel Bot - Local Watch Script
   This app watches local and counts the number of pilots that are hostile or neutral.
   It plays an alarm sound when the number of hostile or neutral pilots increases.
   See the discussion at https://forum.botengine.org/t/local-intel-bot/3413/6?u=viir

   The detection code below works for English language in the game client.
   To use another language, adapt the `badStandingPatterns` list below.
-}
{-
   app-catalog-tags:eve-online,intel,local-watch
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import Dict
import Set
import String.Extra
import BotEngine.Interface_To_Host_20200610 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))
import EveOnline.AppFramework exposing (AppEffect(..))
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , canNotSeeItFromMaybeNothing
        )

defaultBotSettings : BotSettings
defaultBotSettings =
    { selectInstancePilotName = Nothing }

parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleCommaSeparatedList
        ([ ( "select-instance-pilot-name"
           , AppSettings.ValueTypeString (\pilotName -> \settings -> { settings | selectInstancePilotName = Just pilotName })
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings

type alias BotSettings =
    { selectInstancePilotName : Maybe String }

type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias AppState =
    { lastReadingPilotsWithBadStanding : Set.Set String
    }


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings AppState


badStandingPatterns : List String
badStandingPatterns =
    [ "bad standing", "terrible standing", "no standing", "neutral standing", "is at war", "below -5", "criminal", "kill right", ]


initState : State
initState =
    EveOnline.AppFramework.initState { lastReadingPilotsWithBadStanding = Set.empty }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = parseBotSettings
        , selectGameClientInstance =
            Maybe.andThen .selectInstancePilotName
                >> Maybe.map EveOnline.AppFramework.selectGameClientInstanceWithPilotName
                >> Maybe.withDefault EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> AppState
    -> ( AppState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            let
                ( state, response ) =
                    stateBefore |> processReadingFromGameClient readingFromGameClient
            in
            ( state
            , EveOnline.AppFramework.ContinueSession
                { effects = response.effects
                , millisecondsToNextReadingFromGame = 2000
                , statusDescriptionText = response.statusDescriptionText
                }
            )


processReadingFromGameClient : ReadingFromGameClient -> AppState -> ( AppState, { effects : List AppEffect, statusDescriptionText : String } )
processReadingFromGameClient readingFromGameClient stateBefore =
    case readingFromGameClient |> localChatWindowFromUserInterface of
        CanNotSeeIt ->
            ( stateBefore
            , { effects =
                    [ EveOnline.AppFramework.EffectConsoleBeepSequence
                        [ { frequency = 700, durationInMs = 100 }
                        , { frequency = 0, durationInMs = 100 }
                        , { frequency = 700, durationInMs = 100 }
                        , { frequency = 400, durationInMs = 100 }
                        ]
                    ]
              , statusDescriptionText = "I don't see the local chat window."
              }
            )

        CanSee localChatWindow ->
            let
                chatUserHasBadStanding chatUser =
                    badStandingPatterns
                        |> List.any
                            (\badStandingPattern ->
                                chatUser.standingIconHint
                                    |> Maybe.map (String.toLower >> String.contains badStandingPattern)
                                    |> Maybe.withDefault False
                            )

                pilotsWithBadStanding =
                    localChatWindow.visibleUsers
                        |> List.filter (chatUserHasBadStanding)
                        |> List.map (.name >> Maybe.withDefault "")
                        |> Set.fromList

                newPilotsWithBadStanding =
                    Set.diff pilotsWithBadStanding stateBefore.lastReadingPilotsWithBadStanding

                chatWindowReport =
                    "I see "
                        ++ (localChatWindow.visibleUsers |> List.length |> String.fromInt)
                        ++ " users in the local chat. "
                        ++ (pilotsWithBadStanding |> Set.size |> String.fromInt)
                        ++ " with bad standing."

                newArrivalsReport =
                    if newPilotsWithBadStanding == Set.empty then
                        "There are no new pilots that are hostile or neutral."

                    else
                        "There are "
                            ++ (newPilotsWithBadStanding |> Set.size |> String.fromInt)
                            ++ " new pilots that are hostile or neutral: "
                            ++ (newPilotsWithBadStanding |> Set.toList |> List.map (String.Extra.surround "'") |> String.join ", ")
                            ++ "."

                alarmRequests =
                    if newPilotsWithBadStanding /= Set.empty then
                        [ EveOnline.AppFramework.EffectConsoleBeepSequence
                            [ { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            , { frequency = 0, durationInMs = 1000 }
                            , { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            ]
                        ]

                    else
                        []
            in
            ( { stateBefore | lastReadingPilotsWithBadStanding = pilotsWithBadStanding }
            , { effects = alarmRequests
              , statusDescriptionText = [ chatWindowReport, newArrivalsReport ] |> String.join "\n"
              }
            )


localChatWindowFromUserInterface : ReadingFromGameClient -> MaybeVisible EveOnline.ParseUserInterface.ChatWindow
localChatWindowFromUserInterface =
    .chatWindowStacks
        >> List.filterMap .chatWindow
        >> List.filter (.name >> Maybe.map (String.endsWith "_local") >> Maybe.withDefault False)
        >> List.head
        >> canNotSeeItFromMaybeNothing
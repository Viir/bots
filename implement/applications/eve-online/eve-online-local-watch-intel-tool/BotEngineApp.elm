{- EVE Online Intel Bot - Local Watch Script
   This app watches local and counts the number of pilots that are hostile or neutral.
   It plays an alarm sound when the number of hostile or neutral pilots increases.
   See the discussion at https://forum.botengine.org/t/local-intel-bot/3413/6?u=viir

   The detection code below works for English language in the game client.
   To use another language, adapt the `goodStandingPatterns` list below.
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

import BotEngine.Interface_To_Host_20200610 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))
import EveOnline.AppFramework exposing (AppEffect(..))
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , canNotSeeItFromMaybeNothing
        )
import Set
import String.Extra


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias AppState =
    { lastReadingPilotsWithNoGoodStanding : Set.Set String
    }


type alias State =
    EveOnline.AppFramework.StateIncludingFramework () AppState


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


initState : State
initState =
    EveOnline.AppFramework.initState { lastReadingPilotsWithNoGoodStanding = Set.empty }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = AppSettings.parseAllowOnlyEmpty ()
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext ()
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
                chatUserHasGoodStanding chatUser =
                    goodStandingPatterns
                        |> List.any
                            (\goodStandingPattern ->
                                chatUser.standingIconHint
                                    |> Maybe.map (String.toLower >> String.contains goodStandingPattern)
                                    |> Maybe.withDefault False
                            )

                pilotsWithNoGoodStanding =
                    localChatWindow.visibleUsers
                        |> List.filter (chatUserHasGoodStanding >> not)
                        |> List.map (.name >> Maybe.withDefault "")
                        |> Set.fromList

                newPilotsWithNoGoodStanding =
                    Set.diff pilotsWithNoGoodStanding stateBefore.lastReadingPilotsWithNoGoodStanding

                chatWindowReport =
                    "I see "
                        ++ (localChatWindow.visibleUsers |> List.length |> String.fromInt)
                        ++ " users in the local chat. "
                        ++ (pilotsWithNoGoodStanding |> Set.size |> String.fromInt)
                        ++ " with no good standing."

                newArrivalsReport =
                    if newPilotsWithNoGoodStanding == Set.empty then
                        "There are no new pilots that are hostile or neutral."

                    else
                        "There are "
                            ++ (newPilotsWithNoGoodStanding |> Set.size |> String.fromInt)
                            ++ " new pilots that are hostile or neutral: "
                            ++ (newPilotsWithNoGoodStanding |> Set.toList |> List.map (String.Extra.surround "'") |> String.join ", ")
                            ++ "."

                alarmRequests =
                    if newPilotsWithNoGoodStanding /= Set.empty then
                        [ EveOnline.AppFramework.EffectConsoleBeepSequence
                            [ { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            ]
                        ]

                    else
                        []
            in
            ( { stateBefore | lastReadingPilotsWithNoGoodStanding = pilotsWithNoGoodStanding }
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

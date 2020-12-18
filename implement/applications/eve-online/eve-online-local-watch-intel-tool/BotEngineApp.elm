{- EVE Online Intel Bot - Local Watch Script - Smirnoff 2020-12-18
   This app watches local and plays an alarm sound when a pilot with bad standing appears.

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

import BotEngine.Interface_To_Host_20201207 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))
import EveOnline.AppFramework exposing (AppEffect(..))
import EveOnline.ParseUserInterface


type alias ReadingFromGameClient =
    EveOnline.ParseUserInterface.ParsedUserInterface


type alias AppState =
    {}


type alias State =
    EveOnline.AppFramework.StateIncludingFramework () AppState


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


initState : State
initState =
    EveOnline.AppFramework.initState {}


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
                ( effects, statusMessage ) =
                    botEffectsFromGameClientState readingFromGameClient
            in
            ( stateBefore
            , EveOnline.AppFramework.ContinueSession
                { effects = effects
                , millisecondsToNextReadingFromGame = 2000
                , statusDescriptionText = statusMessage
                }
            )


botEffectsFromGameClientState : ReadingFromGameClient -> ( List AppEffect, String )
botEffectsFromGameClientState readingFromGameClient =
    case readingFromGameClient |> localChatWindowFromUserInterface of
        Nothing ->
            ( [ EveOnline.AppFramework.EffectConsoleBeepSequence
                    [ { frequency = 700, durationInMs = 100 }
                    , { frequency = 0, durationInMs = 100 }
                    , { frequency = 700, durationInMs = 100 }
                    , { frequency = 400, durationInMs = 100 }
                    ]
              ]
            , "I don't see the local chat window."
            )

        Just localChatWindow ->
            let
                chatUserHasGoodStanding chatUser =
                    goodStandingPatterns
                        |> List.any
                            (\goodStandingPattern ->
                                chatUser.standingIconHint
                                    |> Maybe.map (String.toLower >> String.contains goodStandingPattern)
                                    |> Maybe.withDefault False
                            )

                visibleUsers =
                    localChatWindow.userlist
                        |> Maybe.map .visibleUsers
                        |> Maybe.withDefault []

                subsetOfUsersWithNoGoodStanding =
                    visibleUsers
                        |> List.filter (chatUserHasGoodStanding >> not)

                chatWindowReport =
                    "I see "
                        ++ (visibleUsers |> List.length |> String.fromInt)
                        ++ " users in the local chat. "
                        ++ (subsetOfUsersWithNoGoodStanding |> List.length |> String.fromInt)
                        ++ " with no good standing."

                alarmRequests =
                    if 1 < (subsetOfUsersWithNoGoodStanding |> List.length) then
                        [ EveOnline.AppFramework.EffectConsoleBeepSequence
                            [ { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            ]
                        ]

                    else
                        []
            in
            ( alarmRequests, chatWindowReport )


localChatWindowFromUserInterface : ReadingFromGameClient -> Maybe EveOnline.ParseUserInterface.ChatWindow
localChatWindowFromUserInterface =
    .chatWindowStacks
        >> List.filterMap .chatWindow
        >> List.filter (.name >> Maybe.map (String.endsWith "_local") >> Maybe.withDefault False)
        >> List.head

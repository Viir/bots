{- EVE Online Intel Bot - Local Watch Script - 2021-01-26
   This bot watches local and plays an alarm sound when a pilot with bad standing appears.
-}
{-
   bot-catalog-tags:eve-online,intel,local-watch
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
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , ReadingFromGameClient
        , UseContextMenuCascadeNode(..)
        , localChatWindowFromUserInterface
        )


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


{-| To support the feature that finishes the session some time of inactivity, it needs to remember the time of the last activity.
-}
type alias BotState =
    {}


type alias State =
    EveOnline.AppFramework.StateIncludingFramework {} BotState


initState : State
initState =
    EveOnline.AppFramework.initState {}


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = AppSettings.parseAllowOnlyEmpty {}
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext {}
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted parsedUserInterface ->
            let
                ( effects, statusMessage ) =
                    botEffectsFromGameClientState parsedUserInterface
            in
            ( stateBefore
            , EveOnline.AppFramework.ContinueSession
                { effects = effects
                , millisecondsToNextReadingFromGame = 2000
                , statusDescriptionText = statusMessage
                }
            )


botEffectsFromGameClientState : ReadingFromGameClient -> ( List AppEffect, String )
botEffectsFromGameClientState parsedUserInterface =
    case parsedUserInterface |> localChatWindowFromUserInterface of
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

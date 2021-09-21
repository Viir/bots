{- EVE Online Intel Bot - Local Watch Script - 2021-09-21
   This bot watches local and plays an alarm sound when a pilot with bad standing appears.
-}
{-
   bot-catalog-tags:eve-online,intel,local-watch
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))
import EveOnline.BotFramework
    exposing
        ( BotEventResponseEffect(..)
        , ReadingFromGameClient
        , UseContextMenuCascadeNode(..)
        , localChatWindowFromUserInterface
        )


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


type alias BotState =
    {}


type alias State =
    EveOnline.BotFramework.StateIncludingFramework {} BotState


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = initState
    , processEvent = processEvent
    }


initState : State
initState =
    EveOnline.BotFramework.initState {}


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotEventResponse )
processEvent =
    EveOnline.BotFramework.processEvent
        { parseBotSettings = AppSettings.parseAllowOnlyEmpty {}
        , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }


processEveOnlineBotEvent :
    EveOnline.BotFramework.BotEventContext BotState
    -> EveOnline.BotFramework.BotEvent
    -> BotState
    -> ( BotState, EveOnline.BotFramework.BotEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.BotFramework.ReadingFromGameClientCompleted parsedUserInterface _ ->
            let
                ( effects, statusMessage ) =
                    botEffectsFromGameClientState parsedUserInterface
            in
            ( stateBefore
            , EveOnline.BotFramework.ContinueSession
                { effects = effects
                , millisecondsToNextReadingFromGame = 2000
                , statusDescriptionText = statusMessage
                , screenshotRegionsToRead = always { rects1x1 = [] }
                }
            )


botEffectsFromGameClientState : ReadingFromGameClient -> ( List BotEventResponseEffect, String )
botEffectsFromGameClientState parsedUserInterface =
    case parsedUserInterface |> localChatWindowFromUserInterface of
        Nothing ->
            ( [ EveOnline.BotFramework.EffectConsoleBeepSequence
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
                        [ EveOnline.BotFramework.EffectConsoleBeepSequence
                            [ { frequency = 700, durationInMs = 100 }
                            , { frequency = 0, durationInMs = 100 }
                            , { frequency = 700, durationInMs = 500 }
                            ]
                        ]

                    else
                        []
            in
            ( alarmRequests, chatWindowReport )

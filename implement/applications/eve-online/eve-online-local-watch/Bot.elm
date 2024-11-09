{- EVE Online Intel Bot - Local Watch Script - 2024-11-09

   This bot watches local and plays an alarm sound when a pilot with bad standing appears.
-}
{-
   catalog-tags:eve-online,intel,local-watch
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import BotLab.NotificationsShim
import Common.EffectOnWindow exposing (MouseButton(..))
import Common.PromptParser as PromptParser
import EveOnline.BotFramework
    exposing
        ( ReadingFromGameClient
        , UseContextMenuCascadeNode(..)
        , localChatWindowFromUserInterface
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( waitForProgressInGame
        )


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


type alias BotMemory =
    {}


type alias State =
    BotLab.NotificationsShim.StateWithNotifications
        (EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework {} BotMemory)


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState {}
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = PromptParser.parseAllowOnlyEmpty {}
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = always identity
            , decideNextStep =
                always waitForProgressInGame
                    >> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase 2000
            , statusTextFromDecisionContext = .readingFromGameClient >> botEffectsFromGameClientState
            }
    }
        |> BotLab.NotificationsShim.addNotifications notificationsFunction


notificationsFunction : { statusText : String } -> List BotLab.NotificationsShim.Notification
notificationsFunction botResponse =
    [ ( "don't see the local chat window."
      , BotLab.NotificationsShim.consoleBeepNotification
            [ { frequency = 700, durationInMs = 100 }
            , { frequency = 0, durationInMs = 100 }
            , { frequency = 700, durationInMs = 100 }
            , { frequency = 400, durationInMs = 100 }
            ]
      )
    , ( "there is a pilot with bad standing"
      , BotLab.NotificationsShim.consoleBeepNotification
            [ { frequency = 700, durationInMs = 100 }
            , { frequency = 0, durationInMs = 100 }
            , { frequency = 700, durationInMs = 500 }
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


botEffectsFromGameClientState : ReadingFromGameClient -> String
botEffectsFromGameClientState parsedUserInterface =
    case parsedUserInterface |> localChatWindowFromUserInterface of
        Nothing ->
            "I don't see the local chat window."

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

                alarmTriggers =
                    if 1 < (subsetOfUsersWithNoGoodStanding |> List.length) then
                        [ "There is a pilot with bad standing" ]

                    else
                        []
            in
            chatWindowReport :: alarmTriggers |> String.join "\n"

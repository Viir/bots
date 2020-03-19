{- EVE Online Intel Bot - Local Watch Script
   This bot watches local and plays an alarm sound when a pilot with bad standing appears.
-}
{-
   bot-catalog-tags:eve-online,intel,local-watch
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200213 as InterfaceToHost
import EveOnline.BotFramework exposing (BotEffect(..))
import EveOnline.MemoryReading
    exposing
        ( MaybeVisible(..)
        , ParsedUserInterface
        , canNotSeeItFromMaybeNothing
        )


goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


{-| To support the feature that finishes the session some time of inactivity, it needs to remember the time of the last activity.
-}
type alias BotState =
    {}


type alias State =
    EveOnline.BotFramework.StateIncludingFramework BotState


initState : State
initState =
    EveOnline.BotFramework.initState {}


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.BotFramework.processEvent processEveOnlineBotEvent


processEveOnlineBotEvent :
    EveOnline.BotFramework.BotEventContext
    -> EveOnline.BotFramework.BotEvent
    -> BotState
    -> ( BotState, EveOnline.BotFramework.BotEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.BotFramework.MemoryReadingCompleted parsedUserInterface ->
            let
                ( effects, statusMessage ) =
                    botEffectsFromGameClientState parsedUserInterface
            in
            ( stateBefore
            , EveOnline.BotFramework.ContinueSession
                { effects = effects
                , millisecondsToNextReadingFromGame = 2000
                , statusDescriptionText = statusMessage
                }
            )


botEffectsFromGameClientState : ParsedUserInterface -> ( List BotEffect, String )
botEffectsFromGameClientState parsedUserInterface =
    case parsedUserInterface |> localChatWindowFromUserInterface of
        CanNotSeeIt ->
            ( [ EveOnline.BotFramework.EffectConsoleBeepSequence
                    [ { frequency = 700, durationInMs = 100 }
                    , { frequency = 0, durationInMs = 100 }
                    , { frequency = 700, durationInMs = 100 }
                    , { frequency = 400, durationInMs = 100 }
                    ]
              ]
            , "I don't see the local chat window."
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

                subsetOfUsersWithNoGoodStanding =
                    localChatWindow.visibleUsers
                        |> List.filter (chatUserHasGoodStanding >> not)

                chatWindowReport =
                    "I see "
                        ++ (localChatWindow.visibleUsers |> List.length |> String.fromInt)
                        ++ " users in the local chat. "
                        ++ (subsetOfUsersWithNoGoodStanding |> List.length |> String.fromInt)
                        ++ " with no good standing."
                        ++ "\nList of pilot names:\n"
                        ++ stringLocalUsersFromList localChatWindow.visibleUsers

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


stringLocalUsersFromList : List EveOnline.MemoryReading.ChatUserEntry -> String
stringLocalUsersFromList users =
    users
        |> List.map getUserName
        |> String.concat


getUserName : EveOnline.MemoryReading.ChatUserEntry -> String
getUserName user =
    user.name
        |> Maybe.withDefault "Failed to read this users name"


localChatWindowFromUserInterface : ParsedUserInterface -> MaybeVisible EveOnline.MemoryReading.ChatWindow
localChatWindowFromUserInterface =
    .chatWindowStacks
        >> List.filterMap .chatWindow
        >> List.filter (.name >> Maybe.map (String.endsWith "_local") >> Maybe.withDefault False)
        >> List.head
        >> canNotSeeItFromMaybeNothing

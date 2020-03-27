{- EVE Online Intel Bot - Local Watch Script - Nevrosix adaption to alert on warp disrupt
   2020-03-26 Nevrosix #9603:
   > can you help me adapt the local watch bot to alert when I am ward disrupted?
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

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import EveOnline.BotFramework exposing (BotEffect(..))
import EveOnline.ParseUserInterface
    exposing
        ( MaybeVisible(..)
        , ParsedUserInterface
        )


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
    case parsedUserInterface.shipUI of
        CanNotSeeIt ->
            ( [ EveOnline.BotFramework.EffectConsoleBeepSequence
                    [ { frequency = 700, durationInMs = 300 }
                    , { frequency = 0, durationInMs = 300 }
                    , { frequency = 700, durationInMs = 300 }
                    , { frequency = 400, durationInMs = 300 }
                    ]
              ]
            , "I don't see the ship UI."
            )

        CanSee shipUI ->
            let
                shipUIReport =
                    "shipUI.offensiveBuffButtonNames: "
                        ++ (shipUI.offensiveBuffButtonNames |> String.join ", ")

                alarmRequests =
                    if shipUI.offensiveBuffButtonNames |> List.member "warpScrambler" then
                        [ EveOnline.BotFramework.EffectConsoleBeepSequence
                            [ { frequency = 700, durationInMs = 300 }
                            , { frequency = 0, durationInMs = 300 }
                            , { frequency = 700, durationInMs = 500 }
                            ]
                        ]

                    else
                        []
            in
            ( alarmRequests, shipUIReport )

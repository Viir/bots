{- Just demo sound effects. -}
{-
   bot-catalog-tags:eve-online,demo,framework
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200318 as InterfaceToHost
import EveOnline.BotFramework exposing (BotEffect(..))
import EveOnline.MemoryReading
    exposing
        ( InfoPanelRouteRouteElementMarker
        , MaybeVisible(..)
        , ParsedUserInterface
        , ShipUI
        , centerFromDisplayRegion
        , maybeNothingFromCanNotSeeIt
        )
import EveOnline.VolatileHostInterface as VolatileHostInterface exposing (MouseButton(..), effectMouseClickAtLocation)


finishSessionAfterInactivityMinutes : Int
finishSessionAfterInactivityMinutes =
    3


{-| To support the feature that finishes the session some time of inactivity, it needs to remember the time of the last activity.
-}
type alias BotState =
    { lastActivityTime : Int
    }


type alias State =
    EveOnline.BotFramework.StateIncludingFramework BotState


initState : State
initState =
    EveOnline.BotFramework.initState { lastActivityTime = 0 }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    EveOnline.BotFramework.processEvent processEveOnlineBotEvent


processEveOnlineBotEvent :
    EveOnline.BotFramework.BotEventContext
    -> EveOnline.BotFramework.BotEvent
    -> BotState
    -> ( BotState, EveOnline.BotFramework.BotEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    ( stateBefore
    , EveOnline.BotFramework.ContinueSession
        { statusDescriptionText = "Playing sound...."
        , millisecondsToNextReadingFromGame = 3000
        , effects =
            [ EffectConsoleBeepSequence
                [ { frequency = 100, durationInMs = 500 }
                , { frequency = 130, durationInMs = 500 }
                , { frequency = 160, durationInMs = 500 }
                , { frequency = 190, durationInMs = 500 }
                ]
            ]
        }
    )

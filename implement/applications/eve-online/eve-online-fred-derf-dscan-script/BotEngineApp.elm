{- EVE Online fred derf dscan script 2020-10-03
   https://forum.botengine.org/t/converting-from-old-engine-to-new/3624
-}
{-
   app-catalog-tags:eve-online
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree exposing (endDecisionPath)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import EveOnline.AppFramework
    exposing
        ( AppEffect(..)
        , DecisionPathNode
        , actWithoutFurtherReadings
        )


defaultBotSettings : BotSettings
defaultBotSettings =
    {}


type alias BotSettings =
    {}


type alias BotMemory =
    {}


type alias StateMemoryAndDecisionTree =
    EveOnline.AppFramework.AppStateWithMemoryAndDecisionTree BotMemory


type alias State =
    EveOnline.AppFramework.StateIncludingFramework BotSettings StateMemoryAndDecisionTree


type alias BotDecisionContext =
    EveOnline.AppFramework.StepDecisionContext BotSettings BotMemory


initState : State
initState =
    EveOnline.AppFramework.initState
        (EveOnline.AppFramework.initStateWithMemoryAndDecisionTree {})


dscanScriptRoot : BotDecisionContext -> DecisionPathNode
dscanScriptRoot context =
    endDecisionPath
        (actWithoutFurtherReadings
            ( "Press the 'V' key."
            , [ EffectOnWindow.KeyDown EffectOnWindow.vkey_V
              , EffectOnWindow.KeyUp EffectOnWindow.vkey_V
              ]
            )
        )


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext BotSettings
    -> EveOnline.AppFramework.AppEvent
    -> StateMemoryAndDecisionTree
    -> ( StateMemoryAndDecisionTree, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent =
    EveOnline.AppFramework.processEveOnlineAppEventWithMemoryAndDecisionTree
        { updateMemoryForNewReadingFromGame = always identity
        , decisionTreeRoot = dscanScriptRoot
        , statusTextFromState = always ""
        , millisecondsToNextReadingFromGame =
            \context -> ((context.eventContext.timeInMilliseconds * 1234) |> modBy 7000) + 2000
        }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { parseAppSettings = AppSettings.parseAllowOnlyEmpty defaultBotSettings
        , selectGameClientInstance = always EveOnline.AppFramework.selectGameClientInstanceWithTopmostWindow
        , processEvent = processEveOnlineBotEvent
        }

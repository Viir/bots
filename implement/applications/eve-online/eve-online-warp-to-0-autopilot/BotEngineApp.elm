{- 2020-06-15 Demo for Bas how to read survey scan entries from UI tree
   See the question at https://forum.botengine.org/t/just-another-newbie-with-questions-learn-from-scratch/3383
-}
{-
   app-catalog-tags:eve-online,memory-reading,demo
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
import EveOnline.ParseUserInterface exposing (MaybeVisible(..))


{-| To support the feature that finishes the session some time of inactivity, it needs to remember the time of the last activity.
-}
type alias BotState =
    {}


type alias State =
    EveOnline.AppFramework.StateIncludingFramework () BotState


initState : State
initState =
    EveOnline.AppFramework.initState {}


parseSurveyScanEntriesFromUITreeRoot : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion -> List EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
parseSurveyScanEntriesFromUITreeRoot =
    EveOnline.ParseUserInterface.listDescendantsWithDisplayRegion
        >> List.filter (.uiNode >> .pythonObjectTypeName >> (==) "SurveyScanEntry")


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    EveOnline.AppFramework.processEvent
        { processEvent = processEveOnlineBotEvent
        , parseAppSettings = AppSettings.parseAllowOnlyEmpty ()
        }


processEveOnlineBotEvent :
    EveOnline.AppFramework.AppEventContext ()
    -> EveOnline.AppFramework.AppEvent
    -> BotState
    -> ( BotState, EveOnline.AppFramework.AppEventResponse )
processEveOnlineBotEvent eventContext event stateBefore =
    case event of
        EveOnline.AppFramework.ReadingFromGameClientCompleted readingFromGameClient ->
            ( stateBefore
            , EveOnline.AppFramework.ContinueSession
                { effects = []
                , millisecondsToNextReadingFromGame = 500
                , statusDescriptionText =
                    "I see "
                        ++ (readingFromGameClient.uiTree |> parseSurveyScanEntriesFromUITreeRoot |> List.length |> String.fromInt)
                        ++ " survey scan entries."
                }
            )

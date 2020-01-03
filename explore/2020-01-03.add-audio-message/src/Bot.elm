{- Demonstrate how add an audio message.
   Use the `--bot-configuration` parameter to specify the path to the WAV file.

   Example integrated in bot for Ivar (https://forum.botengine.org/t/how-to-add-audio-message-if-neutral-or-enemy-hits-local/93/12?u=viir)

   As base, I used the bot from https://github.com/Viir/bots/tree/225c680115328d9ba0223760cec85d56f2ea9a87/implement/templates/send-input-to-window

   https://stackoverflow.com/questions/42845506/how-to-play-a-sound-in-netcore/54670829#54670829

   bot-catalog-tags:demo,notification
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import BotEngine.SimpleBotFramework as SimpleBotFramework


type alias SimpleState =
    {}


type alias State =
    SimpleBotFramework.State SimpleState


initState : State
initState =
    SimpleBotFramework.initState {}


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleBotFramework.processEvent simpleProcessEvent


simpleProcessEvent : SimpleBotFramework.BotEvent -> SimpleState -> ( SimpleState, SimpleBotFramework.BotResponse )
simpleProcessEvent _ stateBefore =
    ( stateBefore
    , SimpleBotFramework.FinishSession { statusDescriptionText = "Unused." }
    )

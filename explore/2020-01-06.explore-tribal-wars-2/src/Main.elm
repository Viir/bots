module Main exposing
    ( interfaceToHost_deserializeState
    , interfaceToHost_initState
    , interfaceToHost_processEvent
    , interfaceToHost_serializeState
    , main
    )

import Bot
import BotEngine.Interface_To_Host_20190808 as InterfaceToHost


interfaceToHost_initState : Bot.State
interfaceToHost_initState =
    Bot.initState


interfaceToHost_processEvent : String -> Bot.State -> ( Bot.State, String )
interfaceToHost_processEvent =
    InterfaceToHost.wrapForSerialInterface_processEvent Bot.processEvent


interfaceToHost_serializeState : Bot.State -> String
interfaceToHost_serializeState =
    always ""


interfaceToHost_deserializeState : String -> Bot.State
interfaceToHost_deserializeState =
    always interfaceToHost_initState


{-| Define the Elm entry point. Don't change this function.
-}
main : Program Int Bot.State String
main =
    InterfaceToHost.elmEntryPoint interfaceToHost_initState interfaceToHost_processEvent interfaceToHost_serializeState (interfaceToHost_deserializeState >> always interfaceToHost_initState)

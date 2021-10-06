{- EVE Online Intel Bot - chuckyone Local Watch - 2021-10-06

   This bot watches the local chat window and plays an alarm sound when more than one pilot without blue color appears.
   The classification into blue and not blue is based on the sample shared by chuckyone at https://forum.botlab.org/t/how-to-add-audio-message-if-neutral-or-enemy-hits-local/93/20
-}
{-
   catalog-tags:eve-online,local-watch
   authors-forum-usernames:viir,chuckyone
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.EffectOnWindow exposing (MouseButton(..))
import Dict
import EveOnline.BotFramework
    exposing
        ( BotEventResponseEffect(..)
        , ReadingFromGameClient
        , UseContextMenuCascadeNode(..)
        , localChatWindowFromUserInterface
        )
import EveOnline.ParseUserInterface


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
        EveOnline.BotFramework.ReadingFromGameClientCompleted parsedUserInterface readingFromGameClientImage ->
            let
                ( effects, statusMessage ) =
                    botEffectsFromGameClientState parsedUserInterface readingFromGameClientImage
            in
            ( stateBefore
            , EveOnline.BotFramework.ContinueSession
                { effects = effects
                , millisecondsToNextReadingFromGame = 2000
                , statusDescriptionText = statusMessage
                , screenshotRegionsToRead = screenshotRegionsToRead
                }
            )


screenshotRegionsToRead : ReadingFromGameClient -> { rects1x1 : List EveOnline.BotFramework.Rect2dStructure }
screenshotRegionsToRead parsedUserInterface =
    let
        rects1x1 =
            parsedUserInterface
                |> getPilotsWithRegionToReadInImage
                |> Result.map (List.map Tuple.second)
                |> Result.withDefault []
    in
    { rects1x1 = rects1x1 }


getPilotsWithRegionToReadInImage : ReadingFromGameClient -> Result String (List ( EveOnline.ParseUserInterface.ChatUserEntry, EveOnline.BotFramework.Rect2dStructure ))
getPilotsWithRegionToReadInImage parsedUserInterface =
    case parsedUserInterface |> localChatWindowFromUserInterface of
        Nothing ->
            Err "I don't see the local chat window."

        Just localChatWindow ->
            localChatWindow.userlist
                |> Maybe.map .visibleUsers
                |> Maybe.withDefault []
                |> List.map
                    (\chatUser ->
                        let
                            originalRegion =
                                chatUser.uiNode.totalDisplayRegion
                        in
                        ( chatUser, { originalRegion | width = 20 } )
                    )
                |> Ok


botEffectsFromGameClientState : ReadingFromGameClient -> EveOnline.BotFramework.ReadingFromGameClientImage -> ( List BotEventResponseEffect, String )
botEffectsFromGameClientState parsedUserInterface readingFromGameClientImage =
    case getPilotsWithRegionToReadInImage parsedUserInterface of
        Err error ->
            ( [ EveOnline.BotFramework.EffectConsoleBeepSequence
                    [ { frequency = 700, durationInMs = 100 }
                    , { frequency = 0, durationInMs = 100 }
                    , { frequency = 700, durationInMs = 100 }
                    , { frequency = 400, durationInMs = 100 }
                    ]
              ]
            , error
            )

        Ok visibleUsers ->
            let
                isBlue pixelValue =
                    pixelValue.red * 2 < pixelValue.blue && pixelValue.green * 2 < pixelValue.blue

                chatUserIsBlue ( chatUser, regionToCheck ) =
                    let
                        pixelsInRegionToCheck =
                            List.range regionToCheck.y (regionToCheck.y + regionToCheck.height)
                                |> List.concatMap
                                    (\y ->
                                        List.range regionToCheck.x (regionToCheck.x + regionToCheck.width)
                                            |> List.filterMap
                                                (\x ->
                                                    readingFromGameClientImage.pixels1x1 |> Dict.get ( x, y )
                                                )
                                    )
                    in
                    List.any isBlue pixelsInRegionToCheck

                subsetOfUsersNotBlue =
                    visibleUsers
                        |> List.filter (chatUserIsBlue >> not)

                chatWindowReport =
                    "I see "
                        ++ (visibleUsers |> List.length |> String.fromInt)
                        ++ " users in the local chat. "
                        ++ (subsetOfUsersNotBlue |> List.length |> String.fromInt)
                        ++ " not blue."

                alarmRequests =
                    if 1 < (subsetOfUsersNotBlue |> List.length) then
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

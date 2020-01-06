{- Explore farming barbarian villages in Tribal Wars 2

   This version only reads your villages.

   The bot automatically opens a new web browser window. The first time you run it, it might take more time because it needs to download the web browser software.
   When the web browser has opened, navigate to Tribal Wars 2 and log in to your account, so you see your villages.
   You then will probably at an URL like https://es.tribalwars2.com/game.php?world=es77&character_id=123456#
   The bot then outputs the number of villages and the ID of the currently selected village. When you change the village in-game, you can see the output from the bot changing as well to indicate the new selected village.

   bot-catalog-tags:exploration,tribal-wars-2
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20190808 as InterfaceToHost
import Dict
import Json.Decode
import Limbara.SimpleLimbara as SimpleLimbara exposing (BotEventAtTime, BotRequest(..))


type alias SimpleState =
    { lastRunJavascriptResult :
        Maybe
            { response : SimpleLimbara.RunJavascriptInCurrentPageResponseStructure
            , parseResult : Result Json.Decode.Error RootInformationStructure
            }
    , gameRootInformation : Maybe TribalWars2RootInformation
    , ownVillagesDetails : Dict.Dict Int VillageDetails
    }


type alias State =
    SimpleLimbara.StateIncludingSetup SimpleState


type ResponseFromBrowser
    = RootInformation RootInformationStructure
    | ReadSelectedCharacterVillageDetailsResponse ReadSelectedCharacterVillageDetailsResponseStructure


type alias RootInformationStructure =
    { location : String
    , tribalWars2 : Maybe TribalWars2RootInformation
    }


type alias TribalWars2RootInformation =
    { readyVillages : List Int
    , selectedVillageId : Int
    }


type alias ReadSelectedCharacterVillageDetailsResponseStructure =
    { villageId : Int
    , villageDetails : VillageDetails
    }


type alias VillageDetails =
    { locationX : Int
    , locationY : Int
    }


initState : State
initState =
    SimpleLimbara.initState
        { lastRunJavascriptResult = Nothing
        , gameRootInformation = Nothing
        , ownVillagesDetails = Dict.empty
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleLimbara.processEvent simpleProcessEvent


simpleProcessEvent : BotEventAtTime -> SimpleState -> { newState : SimpleState, request : BotRequest, statusMessage : String }
simpleProcessEvent eventAtTime stateBefore =
    let
        state =
            case eventAtTime.event of
                SimpleLimbara.SetBotConfiguration _ ->
                    stateBefore

                SimpleLimbara.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
                    let
                        parseAsRootInfoResult =
                            runJavascriptInCurrentPageResponse.directReturnValueAsString
                                |> Json.Decode.decodeString decodeRootInformation

                        stateAfterIntegrateResponse =
                            { stateBefore
                                | lastRunJavascriptResult =
                                    Just
                                        { response = runJavascriptInCurrentPageResponse
                                        , parseResult = parseAsRootInfoResult
                                        }
                            }

                        parseResult =
                            runJavascriptInCurrentPageResponse.directReturnValueAsString
                                |> Json.Decode.decodeString decodeResponseFromBrowser
                    in
                    case parseResult of
                        Err _ ->
                            stateAfterIntegrateResponse

                        Ok (RootInformation rootInformation) ->
                            case rootInformation.tribalWars2 of
                                Nothing ->
                                    stateAfterIntegrateResponse

                                Just gameRootInformation ->
                                    { stateAfterIntegrateResponse | gameRootInformation = Just gameRootInformation }

                        Ok (ReadSelectedCharacterVillageDetailsResponse readVillageDetailsResponse) ->
                            { stateAfterIntegrateResponse
                                | ownVillagesDetails =
                                    stateAfterIntegrateResponse.ownVillagesDetails
                                        |> Dict.insert readVillageDetailsResponse.villageId readVillageDetailsResponse.villageDetails
                            }
    in
    { newState = state
    , request = requestToFramework state
    , statusMessage = statusMessageFromState state
    }


requestToFramework : SimpleState -> BotRequest
requestToFramework state =
    let
        javascript =
            case state.gameRootInformation of
                Nothing ->
                    readRootInformationScript

                Just gameRootInformation ->
                    let
                        villagesWithoutDetails =
                            gameRootInformation.readyVillages
                                |> List.filter (\villageId -> state.ownVillagesDetails |> Dict.member villageId |> not)
                    in
                    case villagesWithoutDetails of
                        [] ->
                            readRootInformationScript

                        villageWithoutDetailsId :: _ ->
                            readSelectedCharacterVillageDetailsScript villageWithoutDetailsId
    in
    SimpleLimbara.RunJavascriptInCurrentPageRequest
        { javascript = javascript
        , requestId = "request-id"
        , timeToWaitForCallbackMilliseconds = 5000
        }


readRootInformationScript : String
readRootInformationScript =
    """
(function () {
tribalWars2 = (function(){
    if (typeof angular == 'undefined' || !(angular.element(document.body).injector().has('modelDataService'))) return { NotInTribalWars: true};

    modelDataService = angular.element(document.body).injector().get('modelDataService');
    selectedCharacter = modelDataService.getSelectedCharacter()
    if (selectedCharacter == null)
        return { NotInTribalWars: true};

    return { InTribalWars2 :
        { readyVillages : selectedCharacter.data.readyVillages
        , selectedVillageId : selectedCharacter.data.selectedVillage.data.villageId }
        };
})();

return JSON.stringify({ location : location.href, tribalWars2 : tribalWars2});
})()
"""


decodeResponseFromBrowser : Json.Decode.Decoder ResponseFromBrowser
decodeResponseFromBrowser =
    Json.Decode.oneOf
        [ decodeRootInformation |> Json.Decode.map RootInformation
        , decodeReadSelectedCharacterVillageDetailsResponse |> Json.Decode.map ReadSelectedCharacterVillageDetailsResponse
        ]


decodeRootInformation : Json.Decode.Decoder RootInformationStructure
decodeRootInformation =
    Json.Decode.map2 RootInformationStructure
        (Json.Decode.field "location" Json.Decode.string)
        (Json.Decode.field "tribalWars2"
            (Json.Decode.oneOf
                [ Json.Decode.field "NotInTribalWars" (Json.Decode.succeed Nothing)
                , Json.Decode.field "InTribalWars2" (decodeTribalWars2RootInformation |> Json.Decode.map Just)
                ]
            )
        )


decodeTribalWars2RootInformation : Json.Decode.Decoder TribalWars2RootInformation
decodeTribalWars2RootInformation =
    Json.Decode.map2 TribalWars2RootInformation
        (Json.Decode.field "readyVillages" (Json.Decode.list Json.Decode.int))
        (Json.Decode.field "selectedVillageId" Json.Decode.int)


readSelectedCharacterVillageDetailsScript : Int -> String
readSelectedCharacterVillageDetailsScript villageId =
    """
(function () {
    modelDataService = angular.element(document.body).injector().get('modelDataService');

    return JSON.stringify(modelDataService.getSelectedCharacter().data.villages[""" ++ "\"" ++ (villageId |> String.fromInt) ++ "\"" ++ """]);
})()
"""


decodeSelectedCharacterVillageDetails : Json.Decode.Decoder VillageDetails
decodeSelectedCharacterVillageDetails =
    Json.Decode.field "data"
        (Json.Decode.map2 VillageDetails
            (Json.Decode.field "x" Json.Decode.int)
            (Json.Decode.field "y" Json.Decode.int)
        )


decodeReadSelectedCharacterVillageDetailsResponse : Json.Decode.Decoder ReadSelectedCharacterVillageDetailsResponseStructure
decodeReadSelectedCharacterVillageDetailsResponse =
    Json.Decode.map2 ReadSelectedCharacterVillageDetailsResponseStructure
        (Json.Decode.field "data" (Json.Decode.field "villageId" Json.Decode.int))
        decodeSelectedCharacterVillageDetails


statusMessageFromState : SimpleState -> String
statusMessageFromState state =
    let
        jsRunResult =
            "lastRunJavascriptResult:\n"
                ++ (state.lastRunJavascriptResult |> Maybe.map .response |> describeMaybe describeRunJavascriptInCurrentPageResponseStructure)

        aboutGame =
            case state.gameRootInformation of
                Nothing ->
                    "Did not yet read game root information."

                Just gameRootInformation ->
                    "Found "
                        ++ (gameRootInformation.readyVillages |> List.length |> String.fromInt)
                        ++ " villages. Currently selected is "
                        ++ (gameRootInformation.selectedVillageId |> String.fromInt)
                        ++ "."
    in
    [ jsRunResult, aboutGame ] |> String.join "\n"


describeRunJavascriptInCurrentPageResponseStructure : SimpleLimbara.RunJavascriptInCurrentPageResponseStructure -> String
describeRunJavascriptInCurrentPageResponseStructure response =
    "{ directReturnValueAsString = "
        ++ describeString 300 response.directReturnValueAsString
        ++ "\n"
        ++ ", callbackReturnValueAsString = "
        ++ describeMaybe (describeString 300) response.callbackReturnValueAsString
        ++ "\n}"


describeString : Int -> String -> String
describeString maxLength string =
    "\"" ++ (string |> stringEllipsis maxLength "...") ++ "\""


describeMaybe : (just -> String) -> Maybe just -> String
describeMaybe describeJust maybe =
    case maybe of
        Nothing ->
            "Nothing"

        Just just ->
            describeJust just


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append

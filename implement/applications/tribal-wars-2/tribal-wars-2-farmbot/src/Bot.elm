{- Tribal Wars 2 farmbot version 2020-01-15

   This version scans the map for barbarian villages and sends attacks.

   The bot automatically opens a new web browser window. The first time you run it, it might take more time because it needs to download the web browser software.
   When the web browser has opened, navigate to Tribal Wars 2 and log in to your account, so you see your villages.
   You then will probably at an URL like https://es.tribalwars2.com/game.php?world=es77&character_id=123456#
   The bot then outputs the number of villages and the ID of the currently selected village. When you change the village in-game, you can see the output from the bot changing as well to indicate the new selected village.

   This bot uses an army preset to send attacks to the barbarian villages. If there is no preset, the attacking does not work.

   bot-catalog-tags:tribal-wars-2,farmbot
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
import Json.Encode
import Limbara.SimpleLimbara as SimpleLimbara exposing (BotEvent, BotRequest(..))
import Set


type alias SimpleState =
    { timeInMilliseconds : Int
    , lastRunJavascriptResult :
        Maybe
            { response : SimpleLimbara.RunJavascriptInCurrentPageResponseStructure
            , parseResult : Result Json.Decode.Error RootInformationStructure
            }
    , gameRootInformation : Maybe TribalWars2RootInformation
    , ownVillagesDetails : Dict.Dict Int VillageDetails
    , lastJumpToCoordinates : Maybe { timeInMilliseconds : Int, coordinates : VillageCoordinates }
    , searchVillageByCoordinatesResults : Dict.Dict ( Int, Int ) VillageByCoordinatesResult
    , sentAttackByCoordinates : Dict.Dict ( Int, Int ) ()
    , parseResponseError : Maybe Json.Decode.Error
    }


type alias State =
    SimpleLimbara.StateIncludingSetup SimpleState


type ResponseFromBrowser
    = RootInformation RootInformationStructure
    | ReadSelectedCharacterVillageDetailsResponse ReadSelectedCharacterVillageDetailsResponseStructure
    | VillageByCoordinatesResponse VillageByCoordinatesResponseStructure
    | SendFirstPresetAsAttackToCoordinatesResponse SendFirstPresetAsAttackToCoordinatesResponseStructure


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


type alias VillageByCoordinatesResponseStructure =
    { villageCoordinates : VillageCoordinates
    , jumpToVillage : Bool
    }


type alias SendFirstPresetAsAttackToCoordinatesResponseStructure =
    { villageCoordinates : VillageCoordinates
    }


type alias VillageDetails =
    { locationX : Int
    , locationY : Int
    }


type VillageByCoordinatesResult
    = NoVillageThere
    | VillageThere VillageByCoordinatesDetails


type alias VillageByCoordinatesDetails =
    { villageId : Int
    , affiliation : VillageByCoordinatesAffiliation
    }


type VillageByCoordinatesAffiliation
    = AffiliationBarbarian
    | AffiliationOther


type alias VillageCoordinates =
    { x : Int
    , y : Int
    }


initState : State
initState =
    SimpleLimbara.initState
        { timeInMilliseconds = 0
        , lastRunJavascriptResult = Nothing
        , gameRootInformation = Nothing
        , ownVillagesDetails = Dict.empty
        , lastJumpToCoordinates = Nothing
        , searchVillageByCoordinatesResults = Dict.empty
        , sentAttackByCoordinates = Dict.empty
        , parseResponseError = Nothing
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleLimbara.processEvent simpleProcessEvent


simpleProcessEvent : BotEvent -> SimpleState -> { newState : SimpleState, request : BotRequest, statusMessage : String }
simpleProcessEvent event stateBefore =
    let
        state =
            case event of
                SimpleLimbara.SetBotConfiguration _ ->
                    stateBefore

                SimpleLimbara.ArrivedAtTime { timeInMilliseconds } ->
                    { stateBefore | timeInMilliseconds = timeInMilliseconds }

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
                        Err error ->
                            { stateAfterIntegrateResponse | parseResponseError = Just error }

                        Ok parseSuccess ->
                            let
                                stateAfterParseSuccess =
                                    { stateAfterIntegrateResponse | parseResponseError = Nothing }
                            in
                            case parseSuccess of
                                RootInformation rootInformation ->
                                    case rootInformation.tribalWars2 of
                                        Nothing ->
                                            stateAfterIntegrateResponse

                                        Just gameRootInformation ->
                                            { stateAfterParseSuccess | gameRootInformation = Just gameRootInformation }

                                ReadSelectedCharacterVillageDetailsResponse readVillageDetailsResponse ->
                                    { stateAfterParseSuccess
                                        | ownVillagesDetails =
                                            stateAfterParseSuccess.ownVillagesDetails
                                                |> Dict.insert readVillageDetailsResponse.villageId readVillageDetailsResponse.villageDetails
                                    }

                                VillageByCoordinatesResponse readVillageByCoordinatesResponse ->
                                    let
                                        stateAfterRememberJump =
                                            if readVillageByCoordinatesResponse.jumpToVillage then
                                                { stateAfterParseSuccess
                                                    | lastJumpToCoordinates =
                                                        Just
                                                            { timeInMilliseconds = stateBefore.timeInMilliseconds
                                                            , coordinates = readVillageByCoordinatesResponse.villageCoordinates
                                                            }
                                                }

                                            else
                                                stateAfterParseSuccess
                                    in
                                    case runJavascriptInCurrentPageResponse.callbackReturnValueAsString of
                                        Nothing ->
                                            -- This case indicates the timeout while waiting for the result from the callback.
                                            stateAfterRememberJump

                                        Just callbackReturnValueAsString ->
                                            case callbackReturnValueAsString |> Json.Decode.decodeString decodeVillageByCoordinatesResult of
                                                Err error ->
                                                    { stateAfterRememberJump | parseResponseError = Just error }

                                                Ok villageByCoordinates ->
                                                    { stateAfterRememberJump
                                                        | searchVillageByCoordinatesResults =
                                                            stateAfterRememberJump.searchVillageByCoordinatesResults
                                                                |> Dict.insert
                                                                    ( readVillageByCoordinatesResponse.villageCoordinates.x, readVillageByCoordinatesResponse.villageCoordinates.y )
                                                                    villageByCoordinates
                                                    }

                                SendFirstPresetAsAttackToCoordinatesResponse sendFirstPresetAsAttackToCoordinatesResponse ->
                                    let
                                        sentAttackByCoordinates =
                                            stateAfterParseSuccess.sentAttackByCoordinates
                                                |> Dict.insert
                                                    ( sendFirstPresetAsAttackToCoordinatesResponse.villageCoordinates.x
                                                    , sendFirstPresetAsAttackToCoordinatesResponse.villageCoordinates.y
                                                    )
                                                    ()
                                    in
                                    { stateAfterParseSuccess | sentAttackByCoordinates = sentAttackByCoordinates }
    in
    { newState = state
    , request = requestToFramework state
    , statusMessage = statusMessageFromState state
    }


requestToFramework : SimpleState -> BotRequest
requestToFramework state =
    let
        maybeRecentlyJumpedToCoordinates =
            state.lastJumpToCoordinates
                |> Maybe.andThen
                    (\lastJumpToCoordinates ->
                        if state.timeInMilliseconds - lastJumpToCoordinates.timeInMilliseconds < 1100 then
                            Just lastJumpToCoordinates.coordinates

                        else
                            Nothing
                    )
    in
    case maybeRecentlyJumpedToCoordinates of
        Just recentlyJumpedToCoordinates ->
            SimpleLimbara.RunJavascriptInCurrentPageRequest
                { javascript = startVillageByCoordinatesScript recentlyJumpedToCoordinates { jumpToVillage = False }
                , requestId = "request-id"
                , timeToWaitForCallbackMilliseconds = 1000
                }

        Nothing ->
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

                                barbarianVillagesWithoutAttacks =
                                    state
                                        |> locatedBarbarianVillages
                                        |> Dict.filter
                                            (\coordinates _ ->
                                                (state.sentAttackByCoordinates |> Dict.get coordinates) == Nothing
                                            )
                            in
                            case villagesWithoutDetails of
                                villageWithoutDetailsId :: _ ->
                                    readSelectedCharacterVillageDetailsScript villageWithoutDetailsId

                                [] ->
                                    case barbarianVillagesWithoutAttacks |> Dict.toList |> List.head of
                                        Just ( ( x, y ), barbarianVillage ) ->
                                            let
                                                coordinates =
                                                    { x = x, y = y }

                                                needToJumpThere =
                                                    case state.lastJumpToCoordinates of
                                                        Nothing ->
                                                            True

                                                        Just lastJumpToCoordinates ->
                                                            lastJumpToCoordinates.coordinates
                                                                /= coordinates
                                                                || lastJumpToCoordinates.timeInMilliseconds
                                                                < state.timeInMilliseconds
                                                                - 7000
                                            in
                                            if needToJumpThere then
                                                startVillageByCoordinatesScript coordinates { jumpToVillage = True }

                                            else
                                                startSendFirstPresetAsAttackToCoordinatesScript coordinates

                                        Nothing ->
                                            let
                                                allCoordinatesToInspect =
                                                    state.ownVillagesDetails
                                                        |> Dict.values
                                                        |> List.map (\village -> { x = village.locationX, y = village.locationY })
                                                        |> coordinatesToSearchFromOwnVillagesCoordinates 10

                                                remainingCoordinatesToInspect =
                                                    allCoordinatesToInspect
                                                        |> List.filter (\coordinates -> state.searchVillageByCoordinatesResults |> Dict.member ( coordinates.x, coordinates.y ) |> not)
                                            in
                                            case remainingCoordinatesToInspect |> List.head of
                                                Nothing ->
                                                    readRootInformationScript

                                                Just coordinates ->
                                                    startVillageByCoordinatesScript coordinates { jumpToVillage = False }
            in
            SimpleLimbara.RunJavascriptInCurrentPageRequest
                { javascript = javascript
                , requestId = "request-id"
                , timeToWaitForCallbackMilliseconds = 1000
                }


locatedBarbarianVillages : SimpleState -> Dict.Dict ( Int, Int ) VillageByCoordinatesDetails
locatedBarbarianVillages =
    .searchVillageByCoordinatesResults
        >> Dict.toList
        >> List.filterMap
            (\( coordinates, byCoordinatesResult ) ->
                case byCoordinatesResult of
                    NoVillageThere ->
                        Nothing

                    VillageThere village ->
                        if village.affiliation == AffiliationBarbarian then
                            Just ( coordinates, village )

                        else
                            Nothing
            )
        >> Dict.fromList


coordinatesToSearchFromOwnVillagesCoordinates : Int -> List VillageCoordinates -> List VillageCoordinates
coordinatesToSearchFromOwnVillagesCoordinates radius ownVillagesCoordinates =
    let
        coordinatesFromSingleOwnVillageCoordinates ownVillageCoordinates =
            List.range -radius radius
                |> List.concatMap
                    (\offsetX ->
                        List.range -radius radius
                            |> List.map (\offsetY -> ( ownVillageCoordinates.x + offsetX, ownVillageCoordinates.y + offsetY ))
                    )

        squareDistanceBetweenCoordinates coordsA coordsB =
            let
                distX =
                    coordsA.x - coordsB.x

                distY =
                    coordsA.y - coordsB.y
            in
            distX * distX + distY * distY

        squareDistanceToClosestOwnVillage coordinates =
            ownVillagesCoordinates
                |> List.map (squareDistanceBetweenCoordinates coordinates)
                |> List.minimum
                |> Maybe.withDefault 0

        allCoordinates : Set.Set ( Int, Int )
        allCoordinates =
            ownVillagesCoordinates
                |> List.concatMap coordinatesFromSingleOwnVillageCoordinates
                |> Set.fromList
    in
    allCoordinates
        |> Set.toList
        |> List.map (\( x, y ) -> { x = x, y = y })
        |> List.sortBy squareDistanceToClosestOwnVillage


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
        , decodeVillageByCoordinatesResponse |> Json.Decode.map VillageByCoordinatesResponse
        , decodeSendFirstPresetAsAttackToCoordinatesResponse |> Json.Decode.map SendFirstPresetAsAttackToCoordinatesResponse
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


{-| Example result:
{"coordinates":{"x":498,"y":502},"villageByCoordinates":{"id":24,"name":"Pueblo de e.é45","x":498,"y":502,"character\_id":null,"province\_name":"Daufahlsur","character\_name":null,"character\_points":null,"points":96,"fortress":0,"tribe\_id":null,"tribe\_name":null,"tribe\_tag":null,"tribe\_points":null,"attack\_protection":0,"barbarian\_boost":null,"flags":{},"affiliation":"barbarian"}}

When there is no village:
{"coordinates":{"x":499,"y":502},"villageByCoordinates":{"villages":[]}}

-}
startVillageByCoordinatesScript : VillageCoordinates -> { jumpToVillage : Bool } -> String
startVillageByCoordinatesScript coordinates { jumpToVillage } =
    let
        argumentJson =
            [ ( "coordinates", coordinates |> jsonEncodeCoordinates )
            , ( "jumpToVillage", jumpToVillage |> Json.Encode.bool )
            ]
                |> Json.Encode.object
                |> Json.Encode.encode 0
    in
    """
(function readVillageByCoordinates(argument) {
        coordinates = argument.coordinates;
        jumpToVillage = argument.jumpToVillage;

        autoCompleteService = angular.element(document.body).injector().get('autoCompleteService');
        mapService = angular.element(document.body).injector().get('mapService');

        autoCompleteService.villageByCoordinates(coordinates, function(villageData) {
            //  console.log(JSON.stringify({ coordinates : coordinates, villageByCoordinates: villageData}));
            ____callback____(JSON.stringify(villageData));

            if(jumpToVillage)
            {
                if(villageData.id == null)
                {
                    //  console.log("Did not find village at " + JSON.stringify(coordinates));
                }
                else
                {
                    mapService.jumpToVillage(coordinates.x, coordinates.y, villageData.id);
                }
            }
        });

        return JSON.stringify({ startedVillageByCoordinates : argument });
})(""" ++ argumentJson ++ ")"


jsonEncodeCoordinates : { x : Int, y : Int } -> Json.Encode.Value
jsonEncodeCoordinates { x, y } =
    [ ( "x", x ), ( "y", y ) ] |> List.map (Tuple.mapSecond Json.Encode.int) |> Json.Encode.object


decodeVillageByCoordinatesResponse : Json.Decode.Decoder VillageByCoordinatesResponseStructure
decodeVillageByCoordinatesResponse =
    Json.Decode.field "startedVillageByCoordinates"
        (Json.Decode.map2 VillageByCoordinatesResponseStructure
            (Json.Decode.field "coordinates"
                (Json.Decode.map2 VillageCoordinates
                    (Json.Decode.field "x" Json.Decode.int)
                    (Json.Decode.field "y" Json.Decode.int)
                )
            )
            (Json.Decode.field "jumpToVillage" Json.Decode.bool)
        )


decodeVillageByCoordinatesResult : Json.Decode.Decoder VillageByCoordinatesResult
decodeVillageByCoordinatesResult =
    Json.Decode.oneOf
        [ Json.Decode.keyValuePairs (Json.Decode.list Json.Decode.value)
            |> Json.Decode.andThen
                (\keyValuePairs ->
                    case keyValuePairs of
                        [ ( singlePropertyName, singlePropertyValue ) ] ->
                            if singlePropertyName == "villages" then
                                Json.Decode.succeed NoVillageThere

                            else
                                Json.Decode.fail "Other property name."

                        _ ->
                            Json.Decode.fail "Other number of properties."
                )
        , decodeVillageByCoordinatesDetails |> Json.Decode.map VillageThere
        ]


decodeVillageByCoordinatesDetails : Json.Decode.Decoder VillageByCoordinatesDetails
decodeVillageByCoordinatesDetails =
    Json.Decode.map2 VillageByCoordinatesDetails
        (Json.Decode.field "id" Json.Decode.int)
        (Json.Decode.field "affiliation" Json.Decode.string
            |> Json.Decode.map
                (\affiliation ->
                    case affiliation |> String.toLower of
                        "barbarian" ->
                            AffiliationBarbarian

                        _ ->
                            AffiliationOther
                )
        )


startSendFirstPresetAsAttackToCoordinatesScript : { x : Int, y : Int } -> String
startSendFirstPresetAsAttackToCoordinatesScript { x, y } =
    """
(function sendFirstPresetAsAttackToCoordinates(coordinates) {
    autoCompleteService = angular.element(document.body).injector().get('autoCompleteService');
    presetListService = angular.element(document.body).injector().get('presetListService');
    socketService = angular.element(document.body).injector().get('socketService');
    routeProvider = angular.element(document.body).injector().get('routeProvider');
    mapService = angular.element(document.body).injector().get('mapService');
    presetService = angular.element(document.body).injector().get('presetService');

    sendPresetAttack = function sendPresetAttack(preset, targetVillageId) {
        //  TODO: Get 'type' from 'conf/commandTypes'.TYPES.ATTACK
        type = 'attack';

        socketService.emit(routeProvider.GET_ATTACKING_FACTOR, {
            'target_id'		: targetVillageId
        }, function(data) {
            var targetData = {
                'id'				: targetVillageId,
                'attackProtection'	: data.attack_protection,
                'barbarianVillage'	: data.owner_id === null
            };

            mapService.updateVillageOwner(targetData.id, data.owner_id);

            presetService.sendPreset(preset.id, type, targetData.id, targetData.attackProtection, targetData.barbarianVillage, false, function() {
                //  $scope.closeWindow();
            });
        });
    };

    preset = null;

    var presets = presetListService.getPresets();

    for (var key of Object.keys(presets)) {
        preset = presets[key];
        break;
    }

    if(preset == null)
    {
        //  console.log("Did not find preset");
        return;
    }

    autoCompleteService.villageByCoordinates(coordinates, function(villageData) {
        //  console.log(JSON.stringify({ coordinates : coordinates, villageByCoordinates: villageData}));

        if(villageData.id == null)
        {
            //  console.log("Did not find village at " + JSON.stringify(coordinates));
            return; // No village here.
        }

        //  mapService.jumpToVillage(coordinates.x, coordinates.y, villageData.id);

        sendPresetAttack(preset, villageData.id);
    });

    return JSON.stringify({ startedSendPresetAttackByCoordinates : coordinates });
})({x:""" ++ (x |> String.fromInt) ++ ", y:" ++ (y |> String.fromInt) ++ "})"


decodeSendFirstPresetAsAttackToCoordinatesResponse : Json.Decode.Decoder SendFirstPresetAsAttackToCoordinatesResponseStructure
decodeSendFirstPresetAsAttackToCoordinatesResponse =
    Json.Decode.field "startedSendPresetAttackByCoordinates"
        (Json.Decode.map2 VillageCoordinates
            (Json.Decode.field "x" Json.Decode.int)
            (Json.Decode.field "y" Json.Decode.int)
        )
        |> Json.Decode.map SendFirstPresetAsAttackToCoordinatesResponseStructure


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

        villagesByCoordinates =
            state.searchVillageByCoordinatesResults
                |> Dict.toList
                |> List.filterMap
                    (\( coordinates, scanResult ) ->
                        case scanResult of
                            NoVillageThere ->
                                Nothing

                            VillageThere village ->
                                Just ( coordinates, village )
                    )
                |> Dict.fromList

        villagesByCoordinatesReport =
            "Searched "
                ++ (state.searchVillageByCoordinatesResults |> Dict.size |> String.fromInt)
                ++ " coordindates and found "
                ++ (villagesByCoordinates |> Dict.size |> String.fromInt)
                ++ " villages, "
                ++ (villagesByCoordinates |> Dict.filter (\_ village -> village.affiliation == AffiliationBarbarian) |> Dict.size |> String.fromInt)
                ++ " of wich are barbarian villages."

        sentAttacks =
            "Sent " ++ (state.sentAttackByCoordinates |> Dict.size |> String.fromInt) ++ " attacks."

        parseResponseErrorReport =
            case state.parseResponseError of
                Nothing ->
                    ""

                Just parseResponseError ->
                    Json.Decode.errorToString parseResponseError
    in
    [ aboutGame, villagesByCoordinatesReport, sentAttacks, parseResponseErrorReport, jsRunResult ] |> String.join "\n"


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

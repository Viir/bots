{- Tribal Wars 2 farmbot version 2020-01-17
   This farmbot searches for barbarian villages around your villages and then attacks them.

   The bot automatically opens a new web browser window. The first time you run it, it might take more time because it needs to download the web browser software.
   When the web browser has opened, navigate to Tribal Wars 2 and log in to your account, so you see your villages.
   Then the browsers address bar will probably show an URL like https://es.tribalwars2.com/game.php?world=es77&character_id=123456#

   This bot uses the army presets configured in the game to attack barbarian villages.
   It picks an army preset that matches the following three criteria:

   + The preset name contains the string 'farm'.
   + The preset is enabled for the currently selected village.
   + The village has enough units available for the preset.

   If no army preset matches this filter, the bot does not attack.
   If multiple army presets match these criteria, priority is determined by alphabetical ordering of the presets.

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
    , ownVillagesDetails : Dict.Dict Int { timeInMilliseconds : Int, villageDetails : VillageDetails }
    , getArmyPresetsResult : Maybe (List ArmyPreset)
    , lastJumpToCoordinates : Maybe { timeInMilliseconds : Int, coordinates : VillageCoordinates }
    , searchVillageByCoordinatesResults : Dict.Dict ( Int, Int ) VillageByCoordinatesResult
    , sentAttackByCoordinates : Dict.Dict ( Int, Int ) ()
    , lastAttackTimeInMilliseconds : Maybe Int
    , parseResponseError : Maybe Json.Decode.Error
    }


type alias State =
    SimpleLimbara.StateIncludingSetup SimpleState


type ResponseFromBrowser
    = RootInformation RootInformationStructure
    | ReadSelectedCharacterVillageDetailsResponse ReadSelectedCharacterVillageDetailsResponseStructure
    | VillageByCoordinatesResponse VillageByCoordinatesResponseStructure
    | GetPresetsResponse (List ArmyPreset)
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
    { coordinates : VillageCoordinates
    , units : Dict.Dict String VillageUnitCount
    }


type alias VillageUnitCount =
    { available : Int }


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


type alias ArmyPreset =
    { id : Int
    , name : String
    , units : Dict.Dict String Int
    , assigned_villages : List Int
    }


type alias VillageCoordinates =
    { x : Int
    , y : Int
    }


farmArmyPresetNamePattern : String
farmArmyPresetNamePattern =
    "farm"


initState : State
initState =
    SimpleLimbara.initState
        { timeInMilliseconds = 0
        , lastRunJavascriptResult = Nothing
        , gameRootInformation = Nothing
        , ownVillagesDetails = Dict.empty
        , getArmyPresetsResult = Nothing
        , lastJumpToCoordinates = Nothing
        , searchVillageByCoordinatesResults = Dict.empty
        , sentAttackByCoordinates = Dict.empty
        , lastAttackTimeInMilliseconds = Nothing
        , parseResponseError = Nothing
        }


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    SimpleLimbara.processEvent processWebBrowserBotEvent


processWebBrowserBotEvent : BotEvent -> SimpleState -> { newState : SimpleState, request : Maybe BotRequest, statusMessage : String }
processWebBrowserBotEvent event stateBefore =
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
                                                |> Dict.insert readVillageDetailsResponse.villageId
                                                    { timeInMilliseconds = stateBefore.timeInMilliseconds, villageDetails = readVillageDetailsResponse.villageDetails }
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
                                    { stateAfterParseSuccess
                                        | sentAttackByCoordinates = sentAttackByCoordinates
                                        , lastAttackTimeInMilliseconds = Just stateBefore.timeInMilliseconds
                                    }

                                GetPresetsResponse armyPresets ->
                                    { stateBefore | getArmyPresetsResult = Just armyPresets }
    in
    { newState = state
    , request = requestToFramework state
    , statusMessage = statusMessageFromState state
    }


requestToFramework : SimpleState -> Maybe BotRequest
requestToFramework state =
    let
        waitAfterJumpedToCoordinates =
            state.lastJumpToCoordinates
                |> Maybe.map
                    (\lastJumpToCoordinates -> state.timeInMilliseconds - lastJumpToCoordinates.timeInMilliseconds < 1100)
                |> Maybe.withDefault False
    in
    if waitAfterJumpedToCoordinates then
        Nothing

    else
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

                            selectedVillageUpdateTimeMinimumMilli =
                                (state.lastAttackTimeInMilliseconds |> Maybe.withDefault 0)
                                    |> max (state.timeInMilliseconds - 15000)

                            selectedVillageUpdatedDetails =
                                state.ownVillagesDetails
                                    |> Dict.get gameRootInformation.selectedVillageId
                                    |> Maybe.andThen
                                        (\selectedVillageDetailsResponse ->
                                            if selectedVillageDetailsResponse.timeInMilliseconds <= selectedVillageUpdateTimeMinimumMilli then
                                                Nothing

                                            else
                                                Just selectedVillageDetailsResponse.villageDetails
                                        )

                            barbarianVillagesWithoutAttacks =
                                state
                                    |> locatedBarbarianVillages
                                    |> Dict.filter
                                        (\coordinates _ ->
                                            (state.sentAttackByCoordinates |> Dict.get coordinates) == Nothing
                                        )
                        in
                        case villagesWithoutDetails of
                            villageWithoutDetails :: _ ->
                                readSelectedCharacterVillageDetailsScript villageWithoutDetails

                            [] ->
                                case selectedVillageUpdatedDetails of
                                    Nothing ->
                                        readSelectedCharacterVillageDetailsScript gameRootInformation.selectedVillageId

                                    Just selectedVillageDetails ->
                                        let
                                            selectedVillageAttackOptions =
                                                computeVillageAttackOptions
                                                    (state.getArmyPresetsResult |> Maybe.withDefault [])
                                                    ( gameRootInformation.selectedVillageId, selectedVillageDetails )
                                        in
                                        case selectedVillageAttackOptions.farmPresetsMatchingAvailableUnits |> List.head of
                                            Nothing ->
                                                getPresetsScript

                                            Just bestPreset ->
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
                                                            startSendFirstPresetAsAttackToCoordinatesScript
                                                                coordinates
                                                                { presetId = bestPreset.id }

                                                    Nothing ->
                                                        let
                                                            allCoordinatesToInspect =
                                                                state.ownVillagesDetails
                                                                    |> Dict.values
                                                                    |> List.map (.villageDetails >> .coordinates)
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
            |> Just


type alias VillageAttackOptions =
    { farmPresetFilter : String
    , farmPresets : List ArmyPreset
    , farmPresetsEnabledForThisVillage : List ArmyPreset
    , farmPresetsMatchingAvailableUnits : List ArmyPreset
    }


computeVillageAttackOptions : List ArmyPreset -> ( Int, VillageDetails ) -> VillageAttackOptions
computeVillageAttackOptions presets ( villageId, villageDetails ) =
    let
        farmPresetFilter =
            farmArmyPresetNamePattern

        farmPresets =
            presets
                |> List.filter (.name >> String.toLower >> String.contains (farmPresetFilter |> String.toLower))
                |> List.sortBy (.name >> String.toLower)

        farmPresetsEnabledForThisVillage =
            farmPresets
                |> List.filter (.assigned_villages >> List.member villageId)

        farmPresetsMatchingAvailableUnits =
            farmPresetsEnabledForThisVillage
                |> List.filter
                    (\preset ->
                        preset.units
                            |> Dict.toList
                            |> List.all
                                (\( unitId, presetUnitCount ) ->
                                    presetUnitCount
                                        <= (villageDetails.units |> Dict.get unitId |> Maybe.map .available |> Maybe.withDefault 0)
                                )
                    )
    in
    { farmPresetFilter = farmPresetFilter
    , farmPresets = farmPresets
    , farmPresetsEnabledForThisVillage = farmPresetsEnabledForThisVillage
    , farmPresetsMatchingAvailableUnits = farmPresetsMatchingAvailableUnits
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
        , decodeGetPresetsResponse |> Json.Decode.map GetPresetsResponse
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

    return JSON.stringify({ selectedCharacterVillage : modelDataService.getSelectedCharacter().data.villages[""" ++ "\"" ++ (villageId |> String.fromInt) ++ "\"" ++ """] });
})()
"""


decodeReadSelectedCharacterVillageDetailsResponse : Json.Decode.Decoder ReadSelectedCharacterVillageDetailsResponseStructure
decodeReadSelectedCharacterVillageDetailsResponse =
    Json.Decode.field "selectedCharacterVillage"
        (Json.Decode.map2 ReadSelectedCharacterVillageDetailsResponseStructure
            (Json.Decode.field "data" (Json.Decode.field "villageId" Json.Decode.int))
            decodeSelectedCharacterVillageDetails
        )


decodeSelectedCharacterVillageDetails : Json.Decode.Decoder VillageDetails
decodeSelectedCharacterVillageDetails =
    Json.Decode.map2 VillageDetails
        decodeVillageDetailsCoordinates
        decodeVillageDetailsUnits


decodeVillageDetailsCoordinates : Json.Decode.Decoder VillageCoordinates
decodeVillageDetailsCoordinates =
    Json.Decode.field "data"
        (Json.Decode.map2 VillageCoordinates
            (Json.Decode.field "x" Json.Decode.int)
            (Json.Decode.field "y" Json.Decode.int)
        )


decodeVillageDetailsUnits : Json.Decode.Decoder (Dict.Dict String VillageUnitCount)
decodeVillageDetailsUnits =
    Json.Decode.field "unitInfo"
        (Json.Decode.field "units"
            (Json.Decode.keyValuePairs decodeVillageDetailsUnitCount)
        )
        |> Json.Decode.map Dict.fromList


{-| 2020-01-16 Observed names: 'in\_town', 'support', 'total', 'available', 'own', 'inside', 'recruiting'
-}
decodeVillageDetailsUnitCount : Json.Decode.Decoder VillageUnitCount
decodeVillageDetailsUnitCount =
    Json.Decode.map VillageUnitCount
        (Json.Decode.field "available" Json.Decode.int)


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


getPresetsScript : String
getPresetsScript =
    """
(function getPresets() {
        presetListService = angular.element(document.body).injector().get('presetListService');

        return JSON.stringify({ getPresets: presetListService.getPresets() });
})()"""


decodeGetPresetsResponse : Json.Decode.Decoder (List ArmyPreset)
decodeGetPresetsResponse =
    Json.Decode.field "getPresets" (Json.Decode.keyValuePairs decodePreset)
        |> Json.Decode.map (List.map Tuple.second)


decodePreset : Json.Decode.Decoder ArmyPreset
decodePreset =
    Json.Decode.map4 ArmyPreset
        (Json.Decode.field "id" Json.Decode.int)
        (Json.Decode.field "name" Json.Decode.string)
        (Json.Decode.field "units" (Json.Decode.keyValuePairs Json.Decode.int)
            |> Json.Decode.map Dict.fromList
        )
        (Json.Decode.field "assigned_villages" (Json.Decode.list Json.Decode.int))


startSendFirstPresetAsAttackToCoordinatesScript : { x : Int, y : Int } -> { presetId : Int } -> String
startSendFirstPresetAsAttackToCoordinatesScript coordinates { presetId } =
    let
        argumentJson =
            [ ( "coordinates", coordinates |> jsonEncodeCoordinates )
            , ( "presetId", presetId |> Json.Encode.int )
            ]
                |> Json.Encode.object
                |> Json.Encode.encode 0
    in
    """
(function sendFirstPresetAsAttackToCoordinates(argument) {
    coordinates = argument.coordinates;
    presetId = argument.presetId;

    autoCompleteService = angular.element(document.body).injector().get('autoCompleteService');
    socketService = angular.element(document.body).injector().get('socketService');
    routeProvider = angular.element(document.body).injector().get('routeProvider');
    mapService = angular.element(document.body).injector().get('mapService');
    presetService = angular.element(document.body).injector().get('presetService');

    sendPresetAttack = function sendPresetAttack(presetId, targetVillageId) {
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

            presetService.sendPreset(presetId, type, targetData.id, targetData.attackProtection, targetData.barbarianVillage, false, function() {
                //  $scope.closeWindow();
            });
        });
    };

    autoCompleteService.villageByCoordinates(coordinates, function(villageData) {
        //  console.log(JSON.stringify({ coordinates : coordinates, villageByCoordinates: villageData}));

        if(villageData.id == null)
        {
            //  console.log("Did not find village at " + JSON.stringify(coordinates));
            return; // No village here.
        }

        //  mapService.jumpToVillage(coordinates.x, coordinates.y, villageData.id);

        sendPresetAttack(presetId, villageData.id);
    });

    return JSON.stringify({ startedSendPresetAttackByCoordinates : coordinates });
})(""" ++ argumentJson ++ ")"


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
                    let
                        selectedVillageDetails =
                            state.ownVillagesDetails
                                |> Dict.get gameRootInformation.selectedVillageId
                                |> Maybe.map
                                    (\villageDetailsResponse ->
                                        let
                                            sumOfAvailableUnits =
                                                villageDetailsResponse.villageDetails.units
                                                    |> Dict.values
                                                    |> List.map .available
                                                    |> List.sum

                                            lastUpdateAge =
                                                (state.timeInMilliseconds - villageDetailsResponse.timeInMilliseconds)
                                                    // 1000

                                            attackOptions =
                                                computeVillageAttackOptions
                                                    (state.getArmyPresetsResult |> Maybe.withDefault [])
                                                    ( gameRootInformation.selectedVillageId, villageDetailsResponse.villageDetails )

                                            attackOptionsReport =
                                                villageAttackOptionsDisplayText attackOptions
                                        in
                                        [ "(" ++ (villageDetailsResponse.villageDetails.coordinates |> villageCoordinatesDisplayText) ++ ")"
                                        , "last update " ++ (lastUpdateAge |> String.fromInt) ++ " s ago"
                                        , (sumOfAvailableUnits |> String.fromInt) ++ " available units"
                                        , attackOptionsReport
                                        ]
                                            |> String.join ", "
                                    )
                                |> Maybe.withDefault "No details this village."
                    in
                    "Found "
                        ++ (gameRootInformation.readyVillages |> List.length |> String.fromInt)
                        ++ " villages. Currently selected is "
                        ++ (gameRootInformation.selectedVillageId |> String.fromInt)
                        ++ " ("
                        ++ selectedVillageDetails
                        ++ ")"

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
    [ aboutGame
    , villagesByCoordinatesReport
    , sentAttacks
    , parseResponseErrorReport
    , jsRunResult
    ]
        |> String.join "\n"


villageAttackOptionsDisplayText : VillageAttackOptions -> String
villageAttackOptionsDisplayText villageAttackOptions =
    case villageAttackOptions.farmPresetsMatchingAvailableUnits |> List.head of
        Nothing ->
            if (villageAttackOptions.farmPresetsEnabledForThisVillage |> List.length) == 0 then
                if (villageAttackOptions.farmPresets |> List.length) == 0 then
                    "Found no army presets matching the filter '" ++ villageAttackOptions.farmPresetFilter ++ "'."

                else
                    "Found " ++ (villageAttackOptions.farmPresets |> List.length |> String.fromInt) ++ " army presets for farming, but none enabled for this village."

            else
                "Found " ++ (villageAttackOptions.farmPresetsEnabledForThisVillage |> List.length |> String.fromInt) ++ " farming army presets enabled for this village, but not sufficient units available for any of them."

        Just bestPreset ->
            "Best matching army preset for this village is '" ++ bestPreset.name ++ "'."


villageCoordinatesDisplayText : VillageCoordinates -> String
villageCoordinatesDisplayText { x, y } =
    (x |> String.fromInt) ++ "|" ++ (y |> String.fromInt)


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

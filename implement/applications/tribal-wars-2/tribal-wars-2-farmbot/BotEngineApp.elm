{- Tribal Wars 2 farmbot version 2020-10-25
   I search for barbarian villages around your villages and then attack them.

   When starting, I first open a new web browser window. This might take more on the first run because I need to download the web browser software.
   When the web browser has opened, navigate to Tribal Wars 2 and log in to your account, so you see your villages.
   Then the browsers address bar will probably show an URL like https://es.tribalwars2.com/game.php?world=es77&character_id=123456#

   When I see the game is loaded, I start searching for barbarian villages.
   As soon I have found one, I begin attacking it, using the army presets that you configured in the game.
   To attack, I pick an army preset that matches the following three criteria:

   + The preset name contains the string 'farm'.
   + The preset is enabled for the currently selected village.
   + The village has enough units available for the preset.

   If multiple army presets match these criteria, I use the first one by alphabetical order.
   If no army preset matches this filter, I activate another village which has a matching preset and enough available units.
   If there is no village with a matching preset and enough units, I stop attacking.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.
   Following is a list of available settings:

   + `number-of-farm-cycles` : Number of farm cycles before the bot stops. The default is only one (`1`) cycle.
   + `break-duration` : Duration of breaks between farm cycles, in minutes. You can also specify a range like `60-120`. It will then pick a random value in this range.
   + `farm-barb-min-points`: Minimum points of barbarian villages to attack.
   + `farm-barb-max-distance`: Maximum distance of barbarian villages to attack.
   + `farm-avoid-coordinates`: List of village coordinates to avoid when farming. Here is an example with two coordinates: '567|456 413|593'
   + `character-to-farm`: Name of a (player) character to farm like barbarians.
   + `farm-army-preset-pattern`: Text for filtering the army presets to use for farm attacks. Army presets only pass the filter when their name contains this text.

   When using more than one setting, start a new line for each setting in the text input field.
   Here is an example of `app-settings` for three farm cycles with breaks of 20 to 40 minutes in between:

   number-of-farm-cycles = 3
   break-duration = 20 - 40

-}
{-
   app-catalog-tags:tribal-wars-2,farmbot
   authors-forum-usernames:viir
-}


module BotEngineApp exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200824 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.DecisionTree
    exposing
        ( DecisionPathNode
        , continueDecisionTree
        , describeBranch
        , endDecisionPath
        , unpackToDecisionStagesDescriptionsAndLeaf
        )
import Dict
import Json.Decode
import Json.Encode
import List.Extra
import Result.Extra
import String.Extra
import WebBrowser.BotFramework as BotFramework exposing (BotEvent, BotResponse)


initBotSettings : BotSettings
initBotSettings =
    { numberOfFarmCycles = 1
    , breakDurationMinMinutes = 90
    , breakDurationMaxMinutes = 120
    , farmBarbarianVillageMinimumPoints = Nothing
    , farmBarbarianVillageMaximumDistance = 50
    , farmAvoidCoordinates = []
    , charactersToFarm = []
    , farmArmyPresetPatterns = []
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignments { assignmentsSeparators = [ ",", "\n" ] }
        ([ ( "number-of-farm-cycles"
           , AppSettings.valueTypeInteger (\numberOfFarmCycles settings -> { settings | numberOfFarmCycles = numberOfFarmCycles })
           )
         , ( "break-duration"
           , parseBotSettingBreakDurationMinutes
           )
         , ( "farm-barb-min-points"
           , AppSettings.valueTypeInteger (\minimumPoints settings -> { settings | farmBarbarianVillageMinimumPoints = Just minimumPoints })
           )
         , ( "farm-barb-max-distance"
           , AppSettings.valueTypeInteger (\maxDistance settings -> { settings | farmBarbarianVillageMaximumDistance = maxDistance })
           )
         , ( "farm-avoid-coordinates"
           , parseSettingFarmAvoidCoordinates
           )
         , ( "character-to-farm"
           , AppSettings.valueTypeString
                (\characterName ->
                    \settings ->
                        { settings | charactersToFarm = characterName :: settings.charactersToFarm }
                )
           )
         , ( "farm-army-preset-pattern"
           , AppSettings.valueTypeString
                (\presetPattern ->
                    \settings ->
                        { settings | farmArmyPresetPatterns = presetPattern :: settings.farmArmyPresetPatterns }
                )
           )
         ]
            |> Dict.fromList
        )
        initBotSettings


implicitSettingsFromExplicitSettings : BotSettings -> BotSettings
implicitSettingsFromExplicitSettings settings =
    { settings
        | farmArmyPresetPatterns =
            if settings.farmArmyPresetPatterns == [] then
                [ farmArmyPresetNamePatternDefault ]

            else
                settings.farmArmyPresetPatterns
    }


farmArmyPresetNamePatternDefault : String
farmArmyPresetNamePatternDefault =
    "farm"


restartGameClientInterval : Int
restartGameClientInterval =
    60 * 30


gameRootInformationQueryInterval : Int
gameRootInformationQueryInterval =
    60


waitDurationAfterReloadWebPage : Int
waitDurationAfterReloadWebPage =
    15


numberOfAttacksLimitPerVillage : Int
numberOfAttacksLimitPerVillage =
    50


ownVillageInfoMaxAge : Int
ownVillageInfoMaxAge =
    600


selectedVillageInfoMaxAge : Int
selectedVillageInfoMaxAge =
    30


readFromGameTimeoutCountThresholdToRestart : Int
readFromGameTimeoutCountThresholdToRestart =
    5


type alias BotState =
    { timeInMilliseconds : Int
    , settings : BotSettings
    , currentActivity : Maybe { beginTimeInMilliseconds : Int, decision : DecisionPathNode InFarmCycleResponse }
    , lastRequestToPageId : Int
    , pendingRequestToPageRequestId : Maybe String
    , lastRunJavascriptResult :
        Maybe
            { timeInMilliseconds : Int
            , response : BotFramework.RunJavascriptInCurrentPageResponseStructure
            , parseResult : Result Json.Decode.Error RootInformationStructure
            }
    , lastPageLocation : Maybe String
    , gameRootInformationResult : Maybe { timeInMilliseconds : Int, gameRootInformation : TribalWars2RootInformation }
    , ownVillagesDetails : Dict.Dict Int { timeInMilliseconds : Int, villageDetails : VillageDetails }
    , getArmyPresetsResult : Maybe (List ArmyPreset)
    , lastJumpToCoordinates : Maybe { timeInMilliseconds : Int, coordinates : VillageCoordinates }
    , coordinatesLastCheck : Dict.Dict ( Int, Int ) { timeInMilliseconds : Int, result : VillageByCoordinatesResult }
    , numberOfReadsFromCoordinates : Int
    , readFromGameConsecutiveTimeoutsCount : Int
    , farmState : FarmState
    , lastAttackTimeInMilliseconds : Maybe Int
    , lastActivatedVillageTimeInMilliseconds : Maybe Int
    , lastReloadPageTimeInSeconds : Maybe Int
    , reloadPageCount : Int
    , completedFarmCycles : List FarmCycleConclusion
    , lastRequestReportListResult :
        Maybe
            { request : RequestReportListResponseStructure
            , decodeResponseResult : Result Json.Decode.Error RequestReportListCallbackDataStructure
            }
    , parseResponseError : Maybe Json.Decode.Error
    , cache_relativeCoordinatesToSearchForFarmsPartitions : List (List VillageCoordinates)
    }


type alias BotSettings =
    { numberOfFarmCycles : Int
    , breakDurationMinMinutes : Int
    , breakDurationMaxMinutes : Int
    , farmBarbarianVillageMinimumPoints : Maybe Int
    , farmBarbarianVillageMaximumDistance : Int
    , farmAvoidCoordinates : List VillageCoordinates
    , charactersToFarm : List String
    , farmArmyPresetPatterns : List String
    }


type alias FarmCycleState =
    { sentAttackByCoordinates : Dict.Dict ( Int, Int ) ()
    }


type alias FarmCycleConclusion =
    { beginTime : Int
    , completionTime : Int
    , attacksCount : Int
    , villagesResults : Dict.Dict Int VillageCompletedStructure
    }


type FarmState
    = InFarmCycle { beginTime : Int } FarmCycleState
    | InBreak { lastCycleCompletionTime : Int, nextCycleStartTime : Int }


type alias State =
    BotFramework.StateIncludingSetup BotState


type ResponseFromBrowser
    = RootInformation RootInformationStructure
    | ReadSelectedCharacterVillageDetailsResponse ReadSelectedCharacterVillageDetailsResponseStructure
    | VillageByCoordinatesResponse VillageByCoordinatesResponseStructure
    | GetPresetsResponse (List ArmyPreset)
    | ActivatedVillageResponse
    | SendPresetAttackToCoordinatesResponse SendPresetAttackToCoordinatesResponseStructure
    | RequestReportListResponse RequestReportListResponseStructure


type alias RootInformationStructure =
    { location : String
    , tribalWars2 : Maybe TribalWars2RootInformation
    }


type alias TribalWars2RootInformation =
    { readyVillages : List Int
    , selectedVillageId : Int
    , getTotalVillagesResult : Int
    }


type alias ReadSelectedCharacterVillageDetailsResponseStructure =
    { villageId : Int
    , villageDetails : VillageDetails
    }


type alias VillageByCoordinatesResponseStructure =
    { villageCoordinates : VillageCoordinates
    , jumpToVillage : Bool
    }


type alias RequestReportListResponseStructure =
    { offset : Int
    , count : Int
    }


type alias RequestReportListCallbackDataStructure =
    { offset : Int
    , total : Int
    , reports : List RequestReportListCallbackDataReportStructure
    }


type alias RequestReportListCallbackDataReportStructure =
    { id : Int
    , time_created : Int
    , result : BattleReportResult
    }


type BattleReportResult
    = BattleReportResult_NO_CASUALTIES
    | BattleReportResult_CASUALTIES
    | BattleReportResult_DEFEAT


type alias SendPresetAttackToCoordinatesResponseStructure =
    { villageCoordinates : VillageCoordinates
    }


type alias VillageDetails =
    { coordinates : VillageCoordinates
    , name : String
    , units : Dict.Dict String VillageUnitCount
    , commands : VillageCommands
    }


type alias VillageUnitCount =
    { available : Int }


type alias VillageCommands =
    { outgoing : List VillageCommand
    }


type alias VillageCommand =
    { time_start : Int
    }


type VillageByCoordinatesResult
    = NoVillageThere
    | VillageThere VillageByCoordinatesDetails


type alias VillageByCoordinatesDetails =
    { villageId : Int
    , affiliation : VillageByCoordinatesAffiliation
    , points : Maybe Int
    , characterName : Maybe String
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


type InFarmCycleResponse
    = ContinueFarmCycle ContinueFarmCycleStructure
    | FinishFarmCycle { villagesResults : Dict.Dict Int VillageCompletedStructure }


type alias ContinueFarmCycleStructure =
    Maybe ContinueFarmCycleActivity


type ContinueFarmCycleActivity
    = RequestToPage RequestToPageStructure
    | RestartWebBrowser


type RequestToPageStructure
    = ReadRootInformationRequest
    | ReadSelectedCharacterVillageDetailsRequest { villageId : Int }
    | ReadArmyPresets
    | VillageByCoordinatesRequest { coordinates : VillageCoordinates, jumpToVillage : Bool }
    | SendPresetAttackToCoordinatesRequest { coordinates : VillageCoordinates, presetId : Int }
    | VillageMenuActivateVillageRequest
    | ReadBattleReportListRequest


type VillageCompletedStructure
    = NoMatchingArmyPresetEnabledForThisVillage
    | NotEnoughUnits
    | ExhaustedAttackLimit
    | AllFarmsInSearchedAreaAlreadyAttackedInThisCycle


type VillageEndDecisionPathStructure
    = CompletedThisVillage VillageCompletedStructure
    | ContinueWithThisVillage ActionFromVillage


type ActionFromVillage
    = GetVillageInfoAtCoordinates VillageCoordinates
    | AttackAtCoordinates ArmyPreset VillageCoordinates


initState : State
initState =
    BotFramework.initState
        { timeInMilliseconds = 0
        , settings = initBotSettings
        , currentActivity = Nothing
        , lastRequestToPageId = 0
        , pendingRequestToPageRequestId = Nothing
        , lastRunJavascriptResult = Nothing
        , lastPageLocation = Nothing
        , gameRootInformationResult = Nothing
        , ownVillagesDetails = Dict.empty
        , getArmyPresetsResult = Nothing
        , lastJumpToCoordinates = Nothing
        , coordinatesLastCheck = Dict.empty
        , numberOfReadsFromCoordinates = 0
        , readFromGameConsecutiveTimeoutsCount = 0
        , farmState = InFarmCycle { beginTime = 0 } initFarmCycle
        , lastAttackTimeInMilliseconds = Nothing
        , lastActivatedVillageTimeInMilliseconds = Nothing
        , lastReloadPageTimeInSeconds = Nothing
        , reloadPageCount = 0
        , completedFarmCycles = []
        , lastRequestReportListResult = Nothing
        , parseResponseError = Nothing
        , cache_relativeCoordinatesToSearchForFarmsPartitions = []
        }


reasonToRestartGameClientFromBotState : BotState -> Maybe String
reasonToRestartGameClientFromBotState state =
    if restartGameClientInterval < (state.timeInMilliseconds // 1000) - (state.lastReloadPageTimeInSeconds |> Maybe.withDefault 0) then
        Just ("Last restart was more than " ++ (restartGameClientInterval |> String.fromInt) ++ " seconds ago.")

    else if readFromGameTimeoutCountThresholdToRestart < state.readFromGameConsecutiveTimeoutsCount then
        Just ("Reading from game timed out consecutively more than " ++ (readFromGameTimeoutCountThresholdToRestart |> String.fromInt) ++ " times.")

    else
        Nothing


initFarmCycle : FarmCycleState
initFarmCycle =
    { sentAttackByCoordinates = Dict.empty }


processEvent : InterfaceToHost.AppEvent -> State -> ( State, InterfaceToHost.AppResponse )
processEvent =
    BotFramework.processEvent processWebBrowserBotEvent


processWebBrowserBotEvent : BotEvent -> BotState -> { newState : BotState, response : BotResponse, statusMessage : String }
processWebBrowserBotEvent event stateBeforeIntegrateEvent =
    case stateBeforeIntegrateEvent |> integrateWebBrowserBotEvent event of
        Err integrateEventError ->
            { newState = stateBeforeIntegrateEvent
            , response = BotFramework.FinishSession
            , statusMessage = "Error: " ++ integrateEventError
            }

        Ok stateBefore ->
            let
                maybeCurrentActivityToWaitFor : Maybe { decisionTree : DecisionPathNode InFarmCycleResponse, activityType : String }
                maybeCurrentActivityToWaitFor =
                    case stateBefore.currentActivity of
                        Nothing ->
                            Nothing

                        Just currentActivity ->
                            let
                                pendingRequestTimeInMilliseconds =
                                    case stateBefore.lastRunJavascriptResult of
                                        Nothing ->
                                            Just currentActivity.beginTimeInMilliseconds

                                        Just lastRunJavascriptResult ->
                                            if currentActivity.beginTimeInMilliseconds <= lastRunJavascriptResult.timeInMilliseconds then
                                                Nothing

                                            else
                                                Just currentActivity.beginTimeInMilliseconds

                                waitTimeAfterLastRunJavascriptResult =
                                    if stateBefore.pendingRequestToPageRequestId == Nothing then
                                        300

                                    else
                                        3000

                                waitTimeLimits =
                                    [ ( "lastRunJavascriptResult"
                                      , stateBefore.lastRunJavascriptResult
                                            |> Maybe.map (.timeInMilliseconds >> (+) waitTimeAfterLastRunJavascriptResult)
                                      )
                                    , ( "pending request"
                                      , pendingRequestTimeInMilliseconds |> Maybe.map ((+) 3000)
                                      )
                                    ]
                                        |> List.filterMap
                                            (\( activityType, maybeWaitTimeLimit ) ->
                                                maybeWaitTimeLimit
                                                    |> Maybe.map (\waitTimeLimit -> ( activityType, waitTimeLimit ))
                                            )

                                effectiveWaitTimeLimits =
                                    waitTimeLimits
                                        |> List.filter (\( _, waitTimeLimit ) -> stateBefore.timeInMilliseconds < waitTimeLimit)
                            in
                            case effectiveWaitTimeLimits |> List.head of
                                Just ( activityType, _ ) ->
                                    -- TODO: Forward the time we want to get notified to the framework, based on the remaining time to the limit.
                                    Just { decisionTree = currentActivity.decision, activityType = activityType }

                                Nothing ->
                                    Nothing
            in
            let
                ( activityDecision, maybeUpdatedState ) =
                    case maybeCurrentActivityToWaitFor of
                        Just currentActivityToWaitFor ->
                            ( currentActivityToWaitFor.decisionTree
                                |> continueDecisionTree
                                    (always (endDecisionPath (BotFramework.ContinueSession Nothing)))
                                |> Common.DecisionTree.mapLastDescriptionBeforeLeaf
                                    (\originalLeafDescription ->
                                        originalLeafDescription ++ " waiting for completion (" ++ currentActivityToWaitFor.activityType ++ ")"
                                    )
                            , Nothing
                            )

                        Nothing ->
                            decideNextAction
                                { lastPageLocation = stateBeforeIntegrateEvent.lastPageLocation }
                                { stateBefore | currentActivity = Nothing }
                                |> Tuple.mapSecond Just

                ( activityDecisionStages, responseToFramework ) =
                    activityDecision
                        |> unpackToDecisionStagesDescriptionsAndLeaf

                newState =
                    maybeUpdatedState |> Maybe.withDefault stateBefore
            in
            { newState = newState
            , response = responseToFramework
            , statusMessage = statusMessageFromState newState { activityDecisionStages = activityDecisionStages }
            }


decideNextAction : { lastPageLocation : Maybe String } -> BotState -> ( DecisionPathNode BotResponse, BotState )
decideNextAction { lastPageLocation } stateBefore =
    case stateBefore.farmState of
        InBreak farmBreak ->
            let
                minutesSinceLastFarmCycleCompletion =
                    (stateBefore.timeInMilliseconds // 1000 - farmBreak.lastCycleCompletionTime) // 60

                minutesToNextFarmCycleStart =
                    (farmBreak.nextCycleStartTime - stateBefore.timeInMilliseconds // 1000) // 60
            in
            if minutesToNextFarmCycleStart < 1 then
                ( describeBranch "Start next farm cycle."
                    (endDecisionPath (BotFramework.ContinueSession Nothing))
                , { stateBefore | farmState = InFarmCycle { beginTime = stateBefore.timeInMilliseconds // 1000 } initFarmCycle }
                )

            else
                ( describeBranch
                    ("Next farm cycle starts in "
                        ++ (minutesToNextFarmCycleStart |> String.fromInt)
                        ++ " minutes. Last cycle completed "
                        ++ (minutesSinceLastFarmCycleCompletion |> String.fromInt)
                        ++ " minutes ago."
                    )
                    (endDecisionPath (BotFramework.ContinueSession Nothing))
                , stateBefore
                )

        InFarmCycle farmCycleBegin farmCycleState ->
            let
                decisionInFarmCycle =
                    decideInFarmCycle stateBefore farmCycleState

                ( _, decisionInFarmCycleLeaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf decisionInFarmCycle

                ( newLeaf, maybeActivityInFarmCycle, updatedStateInFarmCycle ) =
                    case decisionInFarmCycleLeaf of
                        ContinueFarmCycle continueFarmCycleActivity ->
                            let
                                ( maybeRequest, updatedStateFromContinueCycle ) =
                                    case continueFarmCycleActivity of
                                        Nothing ->
                                            ( Nothing, stateBefore )

                                        Just activity ->
                                            let
                                                ( requestToFramework, updatedStateForActivity ) =
                                                    case activity of
                                                        RequestToPage requestToPage ->
                                                            let
                                                                requestComponents =
                                                                    componentsForRequestToPage requestToPage

                                                                requestToPageId =
                                                                    stateBefore.lastRequestToPageId + 1

                                                                requestToPageIdString =
                                                                    requestToPageId |> String.fromInt
                                                            in
                                                            ( BotFramework.RunJavascriptInCurrentPageRequest
                                                                { javascript = requestComponents.javascript
                                                                , requestId = requestToPageIdString
                                                                , timeToWaitForCallbackMilliseconds =
                                                                    case requestComponents.waitForCallbackDuration of
                                                                        Just waitForCallbackDuration ->
                                                                            waitForCallbackDuration

                                                                        Nothing ->
                                                                            0
                                                                }
                                                            , { stateBefore
                                                                | lastRequestToPageId = requestToPageId
                                                                , pendingRequestToPageRequestId = Just requestToPageIdString
                                                              }
                                                            )

                                                        RestartWebBrowser ->
                                                            ( BotFramework.RestartWebBrowser { pageGoToUrl = lastPageLocation }
                                                            , { stateBefore
                                                                | lastReloadPageTimeInSeconds = Just (stateBefore.timeInMilliseconds // 1000)
                                                                , reloadPageCount = stateBefore.reloadPageCount + 1
                                                                , readFromGameConsecutiveTimeoutsCount = 0
                                                              }
                                                            )
                                            in
                                            ( Just requestToFramework
                                            , updatedStateForActivity
                                            )
                            in
                            ( endDecisionPath (BotFramework.ContinueSession maybeRequest)
                            , Just decisionInFarmCycle
                            , updatedStateFromContinueCycle
                            )

                        FinishFarmCycle { villagesResults } ->
                            let
                                completedFarmCycles =
                                    { beginTime = farmCycleBegin.beginTime
                                    , completionTime = stateBefore.timeInMilliseconds // 1000
                                    , attacksCount = farmCycleState.sentAttackByCoordinates |> Dict.size
                                    , villagesResults = villagesResults
                                    }
                                        :: stateBefore.completedFarmCycles

                                currentTimeInSeconds =
                                    stateBefore.timeInMilliseconds // 1000

                                breakLengthRange =
                                    (stateBefore.settings.breakDurationMaxMinutes
                                        - stateBefore.settings.breakDurationMinMinutes
                                    )
                                        * 60

                                breakLengthRandomComponent =
                                    if breakLengthRange == 0 then
                                        0

                                    else
                                        stateBefore.timeInMilliseconds |> modBy breakLengthRange

                                breakLength =
                                    (stateBefore.settings.breakDurationMinMinutes * 60) + breakLengthRandomComponent

                                nextCycleStartTime =
                                    currentTimeInSeconds + breakLength

                                farmState =
                                    InBreak
                                        { lastCycleCompletionTime = currentTimeInSeconds
                                        , nextCycleStartTime = nextCycleStartTime
                                        }

                                stateAfterFinishingFarmCycle =
                                    { stateBefore
                                        | farmState = farmState
                                        , completedFarmCycles = completedFarmCycles
                                    }
                            in
                            ( describeBranch "Finish farm cycle."
                                (if stateBefore.settings.numberOfFarmCycles <= (stateAfterFinishingFarmCycle.completedFarmCycles |> List.length) then
                                    describeBranch
                                        ("Finish session because I finished all " ++ (stateAfterFinishingFarmCycle.completedFarmCycles |> List.length |> String.fromInt) ++ " configured farm cycles.")
                                        (endDecisionPath BotFramework.FinishSession)

                                 else
                                    describeBranch "Enter break."
                                        (endDecisionPath (BotFramework.ContinueSession Nothing))
                                )
                            , Nothing
                            , stateAfterFinishingFarmCycle
                            )

                currentActivity =
                    maybeActivityInFarmCycle
                        |> Maybe.map
                            (\activityInFarmCycle ->
                                { decision = activityInFarmCycle, beginTimeInMilliseconds = stateBefore.timeInMilliseconds }
                            )
            in
            ( decisionInFarmCycle
                |> continueDecisionTree (always newLeaf)
            , { updatedStateInFarmCycle | currentActivity = currentActivity }
            )


parseBotSettingBreakDurationMinutes : String -> Result String (BotSettings -> BotSettings)
parseBotSettingBreakDurationMinutes breakDurationString =
    let
        boundsParseResults =
            breakDurationString
                |> String.split "-"
                |> List.map (\boundString -> boundString |> String.trim |> String.toInt |> Result.fromMaybe ("Failed to parse '" ++ boundString ++ "'"))
    in
    boundsParseResults
        |> Result.Extra.combine
        |> Result.andThen
            (\bounds ->
                case ( bounds |> List.minimum, bounds |> List.maximum ) of
                    ( Just minimum, Just maximum ) ->
                        Ok (\settings -> { settings | breakDurationMinMinutes = minimum, breakDurationMaxMinutes = maximum })

                    _ ->
                        Err "Missing value"
            )


parseSettingFarmAvoidCoordinates : String -> Result String (BotSettings -> BotSettings)
parseSettingFarmAvoidCoordinates listOfCoordinatesAsString =
    listOfCoordinatesAsString
        |> parseSettingListCoordinates
        |> Result.map (\farmAvoidCoordinates -> \settings -> { settings | farmAvoidCoordinates = farmAvoidCoordinates })


parseSettingListCoordinates : String -> Result String (List VillageCoordinates)
parseSettingListCoordinates listOfCoordinatesAsString =
    let
        coordinatesParseResults : List (Result String VillageCoordinates)
        coordinatesParseResults =
            listOfCoordinatesAsString
                |> String.split " "
                |> List.filter (String.isEmpty >> not)
                |> List.map
                    (\coordinatesAsString ->
                        (case coordinatesAsString |> String.split "|" |> List.map String.trim of
                            [ xAsString, yAsString ] ->
                                case ( xAsString |> String.toInt, yAsString |> String.toInt ) of
                                    ( Just x, Just y ) ->
                                        Ok { x = x, y = y }

                                    _ ->
                                        Err "Failed to parse component as integer."

                            _ ->
                                Err "Unexpected number of components."
                        )
                            |> Result.mapError
                                (\errorInCoordinate ->
                                    "Failed to parse coordinates string '" ++ coordinatesAsString ++ "': " ++ errorInCoordinate
                                )
                    )
    in
    coordinatesParseResults
        |> Result.Extra.combine


integrateWebBrowserBotEvent : BotEvent -> BotState -> Result String BotState
integrateWebBrowserBotEvent event stateBefore =
    case event of
        BotFramework.SetAppSettings settingsString ->
            let
                parseSettingsResult =
                    parseBotSettings settingsString
            in
            parseSettingsResult
                |> Result.map
                    (\newSettings ->
                        { stateBefore
                            | settings = newSettings
                            , cache_relativeCoordinatesToSearchForFarmsPartitions =
                                relativeCoordinatesToSearchForFarmsPartitions newSettings
                        }
                    )
                |> Result.mapError (\parseError -> "Failed to parse these app-settings: " ++ parseError)

        BotFramework.ArrivedAtTime { timeInMilliseconds } ->
            Ok { stateBefore | timeInMilliseconds = timeInMilliseconds }

        BotFramework.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            Ok
                (integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse stateBefore)


integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse : BotFramework.RunJavascriptInCurrentPageResponseStructure -> BotState -> BotState
integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse stateBefore =
    let
        pendingRequestToPageRequestId =
            if Just runJavascriptInCurrentPageResponse.requestId == stateBefore.pendingRequestToPageRequestId then
                Nothing

            else
                stateBefore.pendingRequestToPageRequestId

        parseAsRootInfoResult =
            runJavascriptInCurrentPageResponse.directReturnValueAsString
                |> Json.Decode.decodeString decodeRootInformation

        lastPageLocation =
            case parseAsRootInfoResult of
                Ok parseAsRootInfoSuccess ->
                    Just parseAsRootInfoSuccess.location

                _ ->
                    stateBefore.lastPageLocation

        stateAfterIntegrateResponse =
            { stateBefore
                | pendingRequestToPageRequestId = pendingRequestToPageRequestId
                , lastRunJavascriptResult =
                    Just
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , response = runJavascriptInCurrentPageResponse
                        , parseResult = parseAsRootInfoResult
                        }
                , lastPageLocation = lastPageLocation
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
                            { stateAfterParseSuccess
                                | gameRootInformationResult =
                                    Just
                                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                                        , gameRootInformation = gameRootInformation
                                        }
                            }

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
                            { stateAfterRememberJump
                                | readFromGameConsecutiveTimeoutsCount = stateAfterRememberJump.readFromGameConsecutiveTimeoutsCount + 1
                            }

                        Just callbackReturnValueAsString ->
                            case callbackReturnValueAsString |> Json.Decode.decodeString decodeVillageByCoordinatesResult of
                                Err error ->
                                    { stateAfterRememberJump
                                        | parseResponseError = Just error
                                        , readFromGameConsecutiveTimeoutsCount = 0
                                    }

                                Ok villageByCoordinates ->
                                    { stateAfterRememberJump
                                        | coordinatesLastCheck =
                                            stateAfterRememberJump.coordinatesLastCheck
                                                |> Dict.insert
                                                    ( readVillageByCoordinatesResponse.villageCoordinates.x, readVillageByCoordinatesResponse.villageCoordinates.y )
                                                    { timeInMilliseconds = stateAfterRememberJump.timeInMilliseconds
                                                    , result = villageByCoordinates
                                                    }
                                        , numberOfReadsFromCoordinates = stateAfterRememberJump.numberOfReadsFromCoordinates + 1
                                        , readFromGameConsecutiveTimeoutsCount = 0
                                    }

                SendPresetAttackToCoordinatesResponse sendPresetAttackToCoordinatesResponse ->
                    let
                        updatedFarmState =
                            case stateAfterParseSuccess.farmState of
                                InFarmCycle farmCycleBegin currentFarmCycleBefore ->
                                    let
                                        sentAttackByCoordinates =
                                            currentFarmCycleBefore.sentAttackByCoordinates
                                                |> Dict.insert
                                                    ( sendPresetAttackToCoordinatesResponse.villageCoordinates.x
                                                    , sendPresetAttackToCoordinatesResponse.villageCoordinates.y
                                                    )
                                                    ()
                                    in
                                    Just
                                        (InFarmCycle farmCycleBegin
                                            { currentFarmCycleBefore | sentAttackByCoordinates = sentAttackByCoordinates }
                                        )

                                InBreak _ ->
                                    Nothing
                    in
                    { stateAfterParseSuccess
                        | farmState = updatedFarmState |> Maybe.withDefault stateAfterParseSuccess.farmState
                        , lastAttackTimeInMilliseconds = Just stateBefore.timeInMilliseconds
                    }

                GetPresetsResponse armyPresets ->
                    { stateBefore | getArmyPresetsResult = Just armyPresets }

                ActivatedVillageResponse ->
                    { stateBefore | lastActivatedVillageTimeInMilliseconds = Just stateBefore.timeInMilliseconds }

                RequestReportListResponse requestReportList ->
                    let
                        decodeReportListResult =
                            runJavascriptInCurrentPageResponse.callbackReturnValueAsString
                                |> Maybe.withDefault "Looks like the callback was not invoked in time."
                                |> Json.Decode.decodeString decodeRequestReportListCallbackData

                        -- TODO: Remember specific case of timeout: This information is useful to decide when and how to retry.
                    in
                    { stateBefore
                        | lastRequestReportListResult = Just { request = requestReportList, decodeResponseResult = decodeReportListResult }
                    }


maintainGameClient : BotState -> Maybe (DecisionPathNode InFarmCycleResponse)
maintainGameClient botState =
    case botState.lastRunJavascriptResult of
        Nothing ->
            describeBranch
                "Test if web browser is already open."
                (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadRootInformationRequest))))
                |> Just

        Just _ ->
            case botState |> lastReloadPageAgeInSecondsFromState |> Maybe.andThen (nothingFromIntIfGreaterThan waitDurationAfterReloadWebPage) of
                Just lastReloadPageAgeInSeconds ->
                    describeBranch
                        ("Waiting because reloaded web page " ++ (lastReloadPageAgeInSeconds |> String.fromInt) ++ " seconds ago.")
                        (endDecisionPath (ContinueFarmCycle Nothing))
                        |> Just

                Nothing ->
                    case botState |> reasonToRestartGameClientFromBotState of
                        Just reasonToRestartGameClient ->
                            describeBranch
                                ("Restart the game client (" ++ reasonToRestartGameClient ++ ").")
                                (endDecisionPath (ContinueFarmCycle (Just RestartWebBrowser)))
                                |> Just

                        Nothing ->
                            Nothing


decideInFarmCycle : BotState -> FarmCycleState -> DecisionPathNode InFarmCycleResponse
decideInFarmCycle botState farmCycleState =
    maintainGameClient botState
        |> Maybe.withDefault (decideInFarmCycleWhenNotWaitingGlobally botState farmCycleState)


decideInFarmCycleWhenNotWaitingGlobally : BotState -> FarmCycleState -> DecisionPathNode InFarmCycleResponse
decideInFarmCycleWhenNotWaitingGlobally botState farmCycleState =
    let
        sufficientlyNewGameRootInformation =
            botState.gameRootInformationResult
                |> Result.fromMaybe "did not receive any yet"
                |> Result.andThen
                    (\gameRootInformationResult ->
                        let
                            updateTimeMinimumMilli =
                                (botState.lastActivatedVillageTimeInMilliseconds |> Maybe.withDefault 0)
                                    |> max (botState.timeInMilliseconds - gameRootInformationQueryInterval * 1000)
                        in
                        if gameRootInformationResult.timeInMilliseconds <= updateTimeMinimumMilli then
                            Err "last received is not recent enough"

                        else if areAllVillagesLoaded gameRootInformationResult.gameRootInformation then
                            Ok gameRootInformationResult.gameRootInformation

                        else
                            Err
                                "last received has not all villages loaded yet"
                    )
    in
    case sufficientlyNewGameRootInformation of
        Err error ->
            describeBranch ("Read game root info (" ++ error ++ ")")
                (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadRootInformationRequest))))

        Ok gameRootInformation ->
            decideInFarmCycleWithGameRootInformation botState farmCycleState gameRootInformation


decideInFarmCycleWithGameRootInformation : BotState -> FarmCycleState -> TribalWars2RootInformation -> DecisionPathNode InFarmCycleResponse
decideInFarmCycleWithGameRootInformation botState farmCycleState gameRootInformation =
    let
        ownVillageUpdateTimeMinimumMilli =
            botState.timeInMilliseconds - (ownVillageInfoMaxAge * 1000)

        sufficientyFreshOwnVillagesDetails =
            botState.ownVillagesDetails
                |> Dict.filter (\_ response -> ownVillageUpdateTimeMinimumMilli < response.timeInMilliseconds)

        ownVillagesNeedingDetailsUpdate =
            gameRootInformation.readyVillages
                |> List.filter (\villageId -> sufficientyFreshOwnVillagesDetails |> Dict.member villageId |> not)

        selectedVillageUpdateTimeMinimumMilli =
            (botState.lastAttackTimeInMilliseconds |> Maybe.withDefault 0)
                |> max (botState.timeInMilliseconds - (selectedVillageInfoMaxAge * 1000))

        selectedVillageUpdatedDetails =
            sufficientyFreshOwnVillagesDetails
                |> Dict.get gameRootInformation.selectedVillageId
                |> Maybe.andThen
                    (\selectedVillageDetailsResponse ->
                        if selectedVillageDetailsResponse.timeInMilliseconds <= selectedVillageUpdateTimeMinimumMilli then
                            Nothing

                        else
                            Just selectedVillageDetailsResponse.villageDetails
                    )

        describeSelectedVillageDetails =
            botState.ownVillagesDetails
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
                                (botState.timeInMilliseconds - villageDetailsResponse.timeInMilliseconds)
                                    // 1000

                            outgoingCommandsCount =
                                villageDetailsResponse.villageDetails.commands.outgoing |> List.length
                        in
                        [ (villageDetailsResponse.villageDetails.coordinates |> villageCoordinatesDisplayText)
                            ++ " '"
                            ++ villageDetailsResponse.villageDetails.name
                            ++ "'."
                        , "Last update " ++ (lastUpdateAge |> String.fromInt) ++ " s ago."
                        , (sumOfAvailableUnits |> String.fromInt) ++ " available units."
                        , (outgoingCommandsCount |> String.fromInt) ++ " outgoing commands."
                        ]
                            |> String.join " "
                    )
                |> Maybe.withDefault "No details yet for this village."

        describeSelectedVillage =
            "Currently selected village is "
                ++ (gameRootInformation.selectedVillageId |> String.fromInt)
                ++ " ("
                ++ describeSelectedVillageDetails
                ++ ")"

        continueFromDecisionInVillage : VillageEndDecisionPathStructure -> DecisionPathNode InFarmCycleResponse
        continueFromDecisionInVillage decisionInVillage =
            case decisionInVillage of
                ContinueWithThisVillage (GetVillageInfoAtCoordinates coordinates) ->
                    describeBranch
                        ("Search for village at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                        (endDecisionPath
                            (ContinueFarmCycle
                                (Just (RequestToPage (VillageByCoordinatesRequest { coordinates = coordinates, jumpToVillage = False })))
                            )
                        )

                ContinueWithThisVillage (AttackAtCoordinates armyPreset coordinates) ->
                    describeBranch
                        ("Farm at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                        (case requestToJumpToVillageIfNotYetDone botState coordinates of
                            Just jumpToVillageRequest ->
                                describeBranch
                                    ("Jump to village at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                                    (endDecisionPath (ContinueFarmCycle (Just (RequestToPage jumpToVillageRequest))))

                            Nothing ->
                                describeBranch
                                    ("Send attack using preset '" ++ armyPreset.name ++ "'.")
                                    (endDecisionPath
                                        (ContinueFarmCycle
                                            (Just
                                                (RequestToPage
                                                    (SendPresetAttackToCoordinatesRequest { coordinates = coordinates, presetId = armyPreset.id })
                                                )
                                            )
                                        )
                                    )
                        )

                CompletedThisVillage currentVillageCompletion ->
                    describeBranch
                        ("Current village is completed ("
                            ++ (describeVillageCompletion currentVillageCompletion).decisionBranch
                            ++ ")."
                        )
                        (let
                            otherVillagesWithDetails =
                                gameRootInformation.readyVillages
                                    |> List.filterMap
                                        (\otherVillageId ->
                                            sufficientyFreshOwnVillagesDetails
                                                |> Dict.get otherVillageId
                                                |> Maybe.map
                                                    (\otherVillageDetailsResponse ->
                                                        ( otherVillageId, otherVillageDetailsResponse.villageDetails )
                                                    )
                                        )
                                    |> Dict.fromList
                                    |> Dict.remove gameRootInformation.selectedVillageId

                            otherVillagesDetailsAndDecisions =
                                otherVillagesWithDetails
                                    |> Dict.map
                                        (\otherVillageId otherVillageDetails ->
                                            ( otherVillageDetails
                                            , decideNextActionForVillage botState farmCycleState ( otherVillageId, otherVillageDetails )
                                            )
                                        )

                            otherVillagesWithAvailableAction =
                                otherVillagesDetailsAndDecisions
                                    |> Dict.toList
                                    |> List.filter
                                        (\( _, ( _, otherVillageDecisionPath ) ) ->
                                            case otherVillageDecisionPath |> unpackToDecisionStagesDescriptionsAndLeaf |> Tuple.second of
                                                CompletedThisVillage _ ->
                                                    False

                                                ContinueWithThisVillage _ ->
                                                    True
                                        )
                         in
                         case otherVillagesWithAvailableAction |> List.head of
                            Nothing ->
                                let
                                    villagesResults =
                                        otherVillagesDetailsAndDecisions
                                            |> Dict.map (always Tuple.second)
                                            |> Dict.toList
                                            |> List.filterMap
                                                (\( otherVillageId, otherVillageDecisionPath ) ->
                                                    case otherVillageDecisionPath |> unpackToDecisionStagesDescriptionsAndLeaf |> Tuple.second of
                                                        CompletedThisVillage otherVillageCompletion ->
                                                            Just ( otherVillageId, otherVillageCompletion )

                                                        ContinueWithThisVillage _ ->
                                                            Nothing
                                                )
                                            |> Dict.fromList
                                            |> Dict.insert gameRootInformation.selectedVillageId currentVillageCompletion
                                in
                                describeBranch "All villages completed."
                                    (endDecisionPath (FinishFarmCycle { villagesResults = villagesResults }))

                            Just ( villageToActivateId, ( villageToActivateDetails, _ ) ) ->
                                describeBranch
                                    ("Switch to village " ++ (villageToActivateId |> String.fromInt) ++ " at " ++ (villageToActivateDetails.coordinates |> villageCoordinatesDisplayText) ++ ".")
                                    (endDecisionPath
                                        (ContinueFarmCycle
                                            (Just
                                                (RequestToPage
                                                    (requestToJumpToVillageIfNotYetDone botState villageToActivateDetails.coordinates
                                                        |> Maybe.withDefault VillageMenuActivateVillageRequest
                                                    )
                                                )
                                            )
                                        )
                                    )
                        )

        readBattleReportList =
            describeBranch "Read report list"
                (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadBattleReportListRequest))))
    in
    {-
       Disable reading battle report list for to clean up status message.
          case botState.lastRequestReportListResult of
              Nothing ->
                  readBattleReportList

              Just readReportListResult ->
    -}
    case ownVillagesNeedingDetailsUpdate of
        ownVillageNeedingDetailsUpdate :: _ ->
            describeBranch
                ("Read status of own village " ++ (ownVillageNeedingDetailsUpdate |> String.fromInt) ++ ".")
                (endDecisionPath
                    (ContinueFarmCycle
                        (Just (RequestToPage (ReadSelectedCharacterVillageDetailsRequest { villageId = ownVillageNeedingDetailsUpdate })))
                    )
                )

        [] ->
            describeBranch describeSelectedVillage
                (case selectedVillageUpdatedDetails of
                    Nothing ->
                        describeBranch
                            ("Read status of current selected village (" ++ (gameRootInformation.selectedVillageId |> String.fromInt) ++ ")")
                            (endDecisionPath
                                (ContinueFarmCycle
                                    (Just (RequestToPage (ReadSelectedCharacterVillageDetailsRequest { villageId = gameRootInformation.selectedVillageId })))
                                )
                            )

                    Just selectedVillageDetails ->
                        case botState.getArmyPresetsResult |> Maybe.withDefault [] of
                            [] ->
                                {- 2020-01-28 Observation: We get an empty list here at least sometimes at the beginning of a session.
                                   The number of presets we get can increase with the next query.

                                   -- TODO: Add timeout for getting presets.
                                -}
                                describeBranch
                                    "Did not find any army presets. Maybe loading is not completed yet."
                                    (describeBranch
                                        "Read army presets."
                                        (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadArmyPresets))))
                                    )

                            _ ->
                                decideNextActionForVillage
                                    botState
                                    farmCycleState
                                    ( gameRootInformation.selectedVillageId, selectedVillageDetails )
                                    |> continueDecisionTree continueFromDecisionInVillage
                )


describeVillageCompletion : VillageCompletedStructure -> { decisionBranch : String, cycleStatsGroup : String }
describeVillageCompletion villageCompletion =
    case villageCompletion of
        NoMatchingArmyPresetEnabledForThisVillage ->
            { decisionBranch = "No matching preset for this village.", cycleStatsGroup = "No preset" }

        NotEnoughUnits ->
            { decisionBranch = "Not enough units.", cycleStatsGroup = "Out of units" }

        ExhaustedAttackLimit ->
            { decisionBranch = "Exhausted the attack limit.", cycleStatsGroup = "Attack limit" }

        AllFarmsInSearchedAreaAlreadyAttackedInThisCycle ->
            { decisionBranch = "All farms in the search area have already been attacked in this farm cycle.", cycleStatsGroup = "Out of farms" }


lastReloadPageAgeInSecondsFromState : BotState -> Maybe Int
lastReloadPageAgeInSecondsFromState state =
    state.lastReloadPageTimeInSeconds
        |> Maybe.map (\lastReloadPageTimeInSeconds -> state.timeInMilliseconds // 1000 - lastReloadPageTimeInSeconds)


requestToJumpToVillageIfNotYetDone : BotState -> VillageCoordinates -> Maybe RequestToPageStructure
requestToJumpToVillageIfNotYetDone state coordinates =
    let
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
        Just (VillageByCoordinatesRequest { coordinates = coordinates, jumpToVillage = True })

    else
        Nothing


decideNextActionForVillage : BotState -> FarmCycleState -> ( Int, VillageDetails ) -> DecisionPathNode VillageEndDecisionPathStructure
decideNextActionForVillage botState farmCycleState ( villageId, villageDetails ) =
    pickBestMatchingArmyPresetForVillage
        (implicitSettingsFromExplicitSettings botState.settings)
        (botState.getArmyPresetsResult |> Maybe.withDefault [])
        ( villageId, villageDetails )
        (decideNextActionForVillageAfterChoosingPreset botState farmCycleState ( villageId, villageDetails ))


decideNextActionForVillageAfterChoosingPreset : BotState -> FarmCycleState -> ( Int, VillageDetails ) -> ArmyPreset -> DecisionPathNode VillageEndDecisionPathStructure
decideNextActionForVillageAfterChoosingPreset botState farmCycleState ( villageId, villageDetails ) armyPreset =
    let
        villageInfoCheckFromCoordinates coordinates =
            botState.coordinatesLastCheck |> Dict.get ( coordinates.x, coordinates.y )

        numberOfCommandsFromThisVillage =
            villageDetails.commands.outgoing |> List.length
    in
    if numberOfAttacksLimitPerVillage <= (villageDetails.commands.outgoing |> List.length) then
        describeBranch
            ("Number of commands from this village is " ++ (numberOfCommandsFromThisVillage |> String.fromInt) ++ ".")
            (endDecisionPath (CompletedThisVillage ExhaustedAttackLimit))

    else
        let
            sentAttackToCoordinates coordinates =
                (farmCycleState.sentAttackByCoordinates
                    |> Dict.get ( coordinates.x, coordinates.y )
                )
                    /= Nothing

            firstMatchFromRelativeCoordinates =
                List.map (offsetVillageCoordinates villageDetails.coordinates)
                    >> List.filter
                        (\coordinates ->
                            if sentAttackToCoordinates coordinates then
                                False

                            else
                                case villageInfoCheckFromCoordinates coordinates of
                                    Nothing ->
                                        True

                                    Just coordinatesCheck ->
                                        case coordinatesCheck.result of
                                            NoVillageThere ->
                                                False

                                            VillageThere village ->
                                                villageMatchesSettingsForFarm botState.settings coordinates village
                        )
                    >> List.head

            nextRemainingCoordinates =
                {- 2020-03-15 Specialize for runtime expenses:
                   Adapt to limitations of the current Elm runtime:
                   Process the coordinates in partitions to reduce computations of results we will not use anyway. In the end, we only take the first element, but the current runtime performs a more eager evaluation.
                -}
                botState.cache_relativeCoordinatesToSearchForFarmsPartitions
                    |> List.foldl
                        (\coordinatesPartition result ->
                            if result /= Nothing then
                                result

                            else
                                firstMatchFromRelativeCoordinates coordinatesPartition
                        )
                        Nothing
        in
        nextRemainingCoordinates
            |> Maybe.map
                (\nextCoordinates ->
                    let
                        isCoordinatesInfoRecentEnoughToAttack =
                            case villageInfoCheckFromCoordinates nextCoordinates of
                                Nothing ->
                                    False

                                Just coordinatesInfo ->
                                    -- Avoid attacking a village that only recently was conquered by a player: Recheck the coordinates if the last check was too long ago.
                                    botState.timeInMilliseconds < coordinatesInfo.timeInMilliseconds + 10000
                    in
                    if isCoordinatesInfoRecentEnoughToAttack then
                        AttackAtCoordinates armyPreset nextCoordinates

                    else
                        GetVillageInfoAtCoordinates nextCoordinates
                )
            |> Maybe.map ContinueWithThisVillage
            |> Maybe.withDefault (CompletedThisVillage AllFarmsInSearchedAreaAlreadyAttackedInThisCycle)
            |> endDecisionPath


villageMatchesSettingsForFarm : BotSettings -> VillageCoordinates -> VillageByCoordinatesDetails -> Bool
villageMatchesSettingsForFarm settings villageCoordinates village =
    let
        ownedByCharacterToFarm =
            case village.characterName of
                Nothing ->
                    False

                Just characterName ->
                    if characterName == "" then
                        False

                    else
                        settings.charactersToFarm |> List.member characterName
    in
    (((village.affiliation == AffiliationBarbarian)
        && (settings.farmBarbarianVillageMinimumPoints
                |> Maybe.map
                    (\farmBarbarianVillageMinimumPoints ->
                        case village.points of
                            Nothing ->
                                False

                            Just villagePoints ->
                                farmBarbarianVillageMinimumPoints <= villagePoints
                    )
                |> Maybe.withDefault True
           )
     )
        || ownedByCharacterToFarm
    )
        && (settings.farmAvoidCoordinates |> List.member villageCoordinates |> not)


pickBestMatchingArmyPresetForVillage :
    BotSettings
    -> List ArmyPreset
    -> ( Int, VillageDetails )
    -> (ArmyPreset -> DecisionPathNode VillageEndDecisionPathStructure)
    -> DecisionPathNode VillageEndDecisionPathStructure
pickBestMatchingArmyPresetForVillage settings presets ( villageId, villageDetails ) continueWithArmyPreset =
    if presets |> List.isEmpty then
        describeBranch "Did not find any army presets."
            (endDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

    else
        let
            farmPresetFilter =
                settings.farmArmyPresetPatterns

            farmPresetsMaybeEmpty =
                presets
                    |> List.filter
                        (\preset ->
                            farmPresetFilter
                                |> List.any
                                    (\presetFilter ->
                                        String.contains
                                            (String.toLower presetFilter)
                                            (String.toLower preset.name)
                                    )
                        )
                    |> List.sortBy (.name >> String.toLower)
        in
        case farmPresetsMaybeEmpty of
            [] ->
                describeBranch
                    ("Found no army presets matching the patterns ["
                        ++ (farmPresetFilter |> List.map (String.Extra.surround "'") |> String.join ", ")
                        ++ "]."
                    )
                    (endDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

            farmPresets ->
                case
                    farmPresets
                        |> List.filter (.assigned_villages >> List.member villageId)
                of
                    [] ->
                        describeBranch
                            ("Found " ++ (farmPresets |> List.length |> String.fromInt) ++ " army presets for farming, but none enabled for this village.")
                            (endDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

                    farmPresetsEnabledForThisVillage ->
                        let
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
                        case farmPresetsMatchingAvailableUnits |> List.head of
                            Nothing ->
                                describeBranch
                                    ("Found " ++ (farmPresetsEnabledForThisVillage |> List.length |> String.fromInt) ++ " farming army presets enabled for this village, but not sufficient units available for any of these.")
                                    (endDecisionPath (CompletedThisVillage NotEnoughUnits))

                            Just bestMatchingPreset ->
                                describeBranch
                                    ("Best matching army preset for this village is '" ++ bestMatchingPreset.name ++ "'.")
                                    (continueWithArmyPreset bestMatchingPreset)


relativeCoordinatesToSearchForFarms : BotSettings -> List VillageCoordinates
relativeCoordinatesToSearchForFarms botSettings =
    coordinatesInCircleOrderedByDistance botSettings.farmBarbarianVillageMaximumDistance


relativeCoordinatesToSearchForFarmsPartitions : BotSettings -> List (List VillageCoordinates)
relativeCoordinatesToSearchForFarmsPartitions =
    relativeCoordinatesToSearchForFarms
        >> List.Extra.greedyGroupsOf 400


coordinatesInCircleOrderedByDistance : Int -> List VillageCoordinates
coordinatesInCircleOrderedByDistance radius =
    List.range -radius radius
        |> List.concatMap
            (\offsetX ->
                List.range -radius radius
                    |> List.map (\offsetY -> ( offsetX, offsetY ))
            )
        |> List.map (\( x, y ) -> ( { x = x, y = y }, x * x + y * y ))
        |> List.filter (\( _, distanceSquared ) -> distanceSquared <= radius * radius)
        |> List.sortBy Tuple.second
        |> List.map Tuple.first


offsetVillageCoordinates : VillageCoordinates -> VillageCoordinates -> VillageCoordinates
offsetVillageCoordinates coordsA coordsB =
    { x = coordsA.x + coordsB.x, y = coordsA.y + coordsB.y }


squareDistanceBetweenCoordinates : VillageCoordinates -> VillageCoordinates -> Int
squareDistanceBetweenCoordinates coordsA coordsB =
    let
        distX =
            coordsA.x - coordsB.x

        distY =
            coordsA.y - coordsB.y
    in
    distX * distX + distY * distY


componentsForRequestToPage : RequestToPageStructure -> { javascript : String, waitForCallbackDuration : Maybe Int }
componentsForRequestToPage requestToPage =
    case requestToPage of
        ReadRootInformationRequest ->
            { javascript = readRootInformationScript, waitForCallbackDuration = Nothing }

        ReadSelectedCharacterVillageDetailsRequest { villageId } ->
            { javascript = readSelectedCharacterVillageDetailsScript villageId, waitForCallbackDuration = Nothing }

        ReadArmyPresets ->
            { javascript = getPresetsScript, waitForCallbackDuration = Nothing }

        VillageByCoordinatesRequest { coordinates, jumpToVillage } ->
            { javascript = startVillageByCoordinatesScript coordinates { jumpToVillage = jumpToVillage }, waitForCallbackDuration = Just 800 }

        SendPresetAttackToCoordinatesRequest { coordinates, presetId } ->
            { javascript = startSendPresetAttackToCoordinatesScript coordinates { presetId = presetId }, waitForCallbackDuration = Nothing }

        VillageMenuActivateVillageRequest ->
            { javascript = villageMenuActivateVillageScript, waitForCallbackDuration = Nothing }

        ReadBattleReportListRequest ->
            { javascript = startRequestReportListScript { offset = 0, count = 25 }, waitForCallbackDuration = Just 3000 }


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

    // Adapted formatting to strange syntax in google Chrome ->

    return { InTribalWars2 : {
            readyVillages : selectedCharacter.data.readyVillages
            , selectedVillageId : selectedCharacter.data.selectedVillage.data.villageId
            , getTotalVillagesResult : selectedCharacter.getTotalVillages()
            }
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
        , decodeRequestReportListResponse |> Json.Decode.map RequestReportListResponse
        , decodeGetPresetsResponse |> Json.Decode.map GetPresetsResponse
        , decodeActivatedVillageResponse |> Json.Decode.map (always ActivatedVillageResponse)
        , decodeSendPresetAttackToCoordinatesResponse |> Json.Decode.map SendPresetAttackToCoordinatesResponse
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
    Json.Decode.map3 TribalWars2RootInformation
        (Json.Decode.field "readyVillages" (Json.Decode.list Json.Decode.int))
        (Json.Decode.field "selectedVillageId" Json.Decode.int)
        (Json.Decode.field "getTotalVillagesResult" Json.Decode.int)


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
    Json.Decode.map4 VillageDetails
        decodeVillageDetailsCoordinates
        (Json.Decode.field "data" (Json.Decode.field "name" Json.Decode.string))
        decodeVillageDetailsUnits
        decodeVillageDetailsCommands


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


decodeVillageDetailsCommands : Json.Decode.Decoder VillageCommands
decodeVillageDetailsCommands =
    Json.Decode.map VillageCommands
        (Json.Decode.at [ "data", "commands", "outgoing" ] (Json.Decode.list decodeVillageDetailsCommand))


decodeVillageDetailsCommand : Json.Decode.Decoder VillageCommand
decodeVillageDetailsCommand =
    Json.Decode.map VillageCommand
        (Json.Decode.field "time_start" Json.Decode.int)


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


{-| 2020-03-22 There are also villages without 'points':
{ "x": 597, "y": 545, "name": "Freund einladen", "id": -2, "affiliation": "other" }
-}
decodeVillageByCoordinatesDetails : Json.Decode.Decoder VillageByCoordinatesDetails
decodeVillageByCoordinatesDetails =
    Json.Decode.map4 VillageByCoordinatesDetails
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
        (Json.Decode.maybe (Json.Decode.field "points" Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field "character_name" Json.Decode.string))


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


startSendPresetAttackToCoordinatesScript : { x : Int, y : Int } -> { presetId : Int } -> String
startSendPresetAttackToCoordinatesScript coordinates { presetId } =
    let
        argumentJson =
            [ ( "coordinates", coordinates |> jsonEncodeCoordinates )
            , ( "presetId", presetId |> Json.Encode.int )
            ]
                |> Json.Encode.object
                |> Json.Encode.encode 0
    in
    """
(function sendPresetAttackToCoordinates(argument) {
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
            'target_id' : targetVillageId
        }, function(data) {
            var targetData = {
                'id' : targetVillageId,
                'attackProtection' : data.attack_protection,
                'barbarianVillage' : data.owner_id === null
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


decodeSendPresetAttackToCoordinatesResponse : Json.Decode.Decoder SendPresetAttackToCoordinatesResponseStructure
decodeSendPresetAttackToCoordinatesResponse =
    Json.Decode.field "startedSendPresetAttackByCoordinates"
        (Json.Decode.map2 VillageCoordinates
            (Json.Decode.field "x" Json.Decode.int)
            (Json.Decode.field "y" Json.Decode.int)
        )
        |> Json.Decode.map SendPresetAttackToCoordinatesResponseStructure


villageMenuActivateVillageScript : String
villageMenuActivateVillageScript =
    """
(function () {
    getXPathResultFirstNode = function getXPathResultFirstNode(xpath) {        
        return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
    };

    var contextMenuEntry = getXPathResultFirstNode("//*[contains(@class, 'context-menu-item') and contains(@class, 'activate')]//*[contains(@ng-click, 'openSubMenu')]");
    
    contextMenuEntry.click();

    return JSON.stringify({ activatedVillage : true });
})();
"""


decodeActivatedVillageResponse : Json.Decode.Decoder ()
decodeActivatedVillageResponse =
    Json.Decode.field "activatedVillage" (Json.Decode.succeed ())


{-| What values does `requestReportList` support for the `filters` parameter?
2020-05-20 I used `JSON.stringify` on a value for `filters` coming from the `ReportListController` (`$scope.activeFilters` in the calling site) and got this:

"{"BATTLE\_RESULTS":{"1":false,"2":false,"3":false},"BATTLE\_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS\_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full\_haul":false,"forwarded":false,"character":false}}"

The above `filters` variant was with all visible; at least that was the intention. Let's see what `filters` we find when using the filters in the UI:

Victory with casualties:

"{"BATTLE\_RESULTS":{"1":false,"2":true,"3":false},"BATTLE\_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS\_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full\_haul":false,"forwarded":false,"character":false}}"

Defeat:

"{"BATTLE\_RESULTS":{"1":false,"2":false,"3":true},"BATTLE\_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS\_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full\_haul":false,"forwarded":false,"character":false}}"

-}
startRequestReportListScript : { offset : Int, count : Int } -> String
startRequestReportListScript request =
    let
        argumentJson =
            [ ( "offset", request.offset |> Json.Encode.int )
            , ( "count", request.count |> Json.Encode.int )
            ]
                |> Json.Encode.object
                |> Json.Encode.encode 0
    in
    """
(function requestReportList(argument) {

        reportService = angular.element(document.body).injector().get('reportService');

        reportService.requestReportList('battle', argument.offset, argument.count, null, { "BATTLE_RESULTS": { "1": false, "2": false, "3": false }, "BATTLE_TYPES": { "attack": true, "defense": true, "support": true, "scouting": true }, "OTHERS_TYPES": { "trade": true, "system": true, "misc": true }, "MISC": { "favourite": false, "full_haul": false, "forwarded": false, "character": false } }, function (reportsData) {


            /*
            TODO: Remove.
            Inspect if the callback given to requestReportList is invoked with a proper value.
            */
            console.log(JSON.stringify(reportsData));


            ____callback____(JSON.stringify(reportsData));


            /*
            TODO: Remove.
            */
            console.log("Returned from callback");
        });

        return JSON.stringify({ startedRequestReportList : argument });
})(""" ++ argumentJson ++ ")"


decodeRequestReportListResponse : Json.Decode.Decoder RequestReportListResponseStructure
decodeRequestReportListResponse =
    Json.Decode.field "startedRequestReportList"
        (Json.Decode.map2 RequestReportListResponseStructure
            (Json.Decode.field "offset" Json.Decode.int)
            (Json.Decode.field "count" Json.Decode.int)
        )


decodeRequestReportListCallbackData : Json.Decode.Decoder RequestReportListCallbackDataStructure
decodeRequestReportListCallbackData =
    Json.Decode.map3 RequestReportListCallbackDataStructure
        (Json.Decode.field "offset" Json.Decode.int)
        (Json.Decode.field "total" Json.Decode.int)
        (Json.Decode.field "reports" (Json.Decode.list decodeRequestReportListCallbackDataReport))


decodeRequestReportListCallbackDataReport : Json.Decode.Decoder RequestReportListCallbackDataReportStructure
decodeRequestReportListCallbackDataReport =
    Json.Decode.map3 RequestReportListCallbackDataReportStructure
        (Json.Decode.field "id" Json.Decode.int)
        (Json.Decode.field "time_created" Json.Decode.int)
        (Json.Decode.field "result" decodeBattleReportResult)


decodeBattleReportResult : Json.Decode.Decoder BattleReportResult
decodeBattleReportResult =
    Json.Decode.int
        |> Json.Decode.andThen
            (\resultInteger ->
                [ ( 1, BattleReportResult_NO_CASUALTIES )
                , ( 2, BattleReportResult_CASUALTIES )
                , ( 3, BattleReportResult_DEFEAT )
                ]
                    |> Dict.fromList
                    |> Dict.get resultInteger
                    |> Maybe.map Json.Decode.succeed
                    |> Maybe.withDefault (Json.Decode.fail ("Unknown report result type '" ++ (resultInteger |> String.fromInt) ++ "'"))
            )


statusMessageFromState : BotState -> { activityDecisionStages : List String } -> String
statusMessageFromState state { activityDecisionStages } =
    case state.lastRunJavascriptResult of
        Nothing ->
            "Opening web browser."

        Just _ ->
            let
                sentAttacks =
                    countSentAttacks state

                describeSessionPerformance =
                    [ ( "attacks sent", sentAttacks.inSession )
                    , ( "coordinates read", state.numberOfReadsFromCoordinates )
                    , ( "completed farm cycles", state.completedFarmCycles |> List.length )
                    ]
                        |> List.map (\( metric, amount ) -> metric ++ ": " ++ (amount |> String.fromInt))
                        |> String.join ", "

                jsRunResult =
                    "lastRunJavascriptResult:\n"
                        ++ (state.lastRunJavascriptResult |> Maybe.map .response |> describeMaybe describeRunJavascriptInCurrentPageResponseStructure)

                villagesByCoordinates =
                    state.coordinatesLastCheck
                        |> Dict.toList
                        |> List.filterMap
                            (\( coordinates, scanResult ) ->
                                case scanResult.result of
                                    NoVillageThere ->
                                        Nothing

                                    VillageThere village ->
                                        Just ( coordinates, village )
                            )
                        |> Dict.fromList

                barbarianVillages =
                    villagesByCoordinates |> Dict.filter (\_ village -> village.affiliation == AffiliationBarbarian)

                villagesMatchingSettingsForFarm =
                    villagesByCoordinates
                        |> Dict.filter (\( x, y ) village -> villageMatchesSettingsForFarm state.settings { x = x, y = y } village)

                numberOfVillagesAvoidedBySettings =
                    (barbarianVillages |> Dict.size) - (villagesMatchingSettingsForFarm |> Dict.size)

                coordinatesChecksReport =
                    "Checked "
                        ++ (state.coordinatesLastCheck |> Dict.size |> String.fromInt)
                        ++ " unique coordinates and found "
                        ++ (villagesByCoordinates |> Dict.size |> String.fromInt)
                        ++ " villages, "
                        ++ (barbarianVillages |> Dict.size |> String.fromInt)
                        ++ " of which are barbarian villages"
                        ++ (if numberOfVillagesAvoidedBySettings < 1 then
                                ""

                            else
                                " (" ++ (numberOfVillagesAvoidedBySettings |> String.fromInt) ++ " avoided by current settings)"
                           )
                        ++ "."

                sentAttacksReportPartCurrentCycle =
                    case sentAttacks.inCurrentCycle of
                        Nothing ->
                            []

                        Just inCurrentCycle ->
                            [ "Sent " ++ (inCurrentCycle |> String.fromInt) ++ " attacks in the current cycle." ]

                completedFarmCyclesReportLines =
                    case state.completedFarmCycles |> List.head of
                        Nothing ->
                            []

                        Just lastCompletedFarmCycle ->
                            let
                                completionAgeInMinutes =
                                    (state.timeInMilliseconds // 1000 - lastCompletedFarmCycle.completionTime) // 60

                                farmCycleConclusionDescription =
                                    describeFarmCycleConclusion lastCompletedFarmCycle
                            in
                            [ "Completed "
                                ++ (state.completedFarmCycles |> List.length |> describeOrdinalNumber)
                                ++ " farm cycle "
                                ++ (completionAgeInMinutes |> String.fromInt)
                                ++ " minutes ago with "
                                ++ farmCycleConclusionDescription.villagesReport
                                ++ " "
                                ++ farmCycleConclusionDescription.attacksReport
                            , "---"
                            ]

                inGameReport =
                    case state.gameRootInformationResult of
                        Nothing ->
                            "I did not yet read game root information. Please log in to the game so that you see your villages."

                        Just gameRootInformationResult ->
                            let
                                gameRootInformation =
                                    gameRootInformationResult.gameRootInformation

                                ownVillagesReport =
                                    "Found "
                                        ++ (gameRootInformation.getTotalVillagesResult |> String.fromInt)
                                        ++ " own villages"
                                        ++ (if areAllVillagesLoaded gameRootInformation then
                                                ""

                                            else
                                                ", but only " ++ (gameRootInformation.readyVillages |> List.length |> String.fromInt) ++ " loaded yet"
                                           )
                                        ++ "."
                            in
                            ownVillagesReport

                parseResponseErrorReport =
                    case state.parseResponseError of
                        Nothing ->
                            ""

                        Just parseResponseError ->
                            Json.Decode.errorToString parseResponseError

                debugInspectionLines =
                    [ jsRunResult ]

                enableDebugInspection =
                    False

                reloadReportLines =
                    state
                        |> lastReloadPageAgeInSecondsFromState
                        |> Maybe.map
                            (\lastReloadPageAgeInSeconds ->
                                [ "Reloaded the web page "
                                    ++ (state.reloadPageCount |> String.fromInt)
                                    ++ " times, last time was "
                                    ++ ((lastReloadPageAgeInSeconds // 60) |> String.fromInt)
                                    ++ " minutes ago."
                                ]
                            )
                        |> Maybe.withDefault []

                readBattleReportsReport =
                    case state.lastRequestReportListResult of
                        Nothing ->
                            "Did not yet read battle reports."

                        Just requestReportListResult ->
                            let
                                responseReport =
                                    case requestReportListResult.decodeResponseResult of
                                        Ok requestReportListResponse ->
                                            "Received IDs of " ++ (requestReportListResponse.reports |> List.length |> String.fromInt) ++ " reports"

                                        Err decodeError ->
                                            "Failed to decode the response: " ++ Json.Decode.errorToString decodeError
                            in
                            "Read the list of battle reports: " ++ responseReport

                settingsReport =
                    "Settings: "
                        ++ ([ ( "cycles", state.settings.numberOfFarmCycles |> String.fromInt )
                            , ( "breaks"
                              , (state.settings.breakDurationMinMinutes |> String.fromInt)
                                    ++ " - "
                                    ++ (state.settings.breakDurationMaxMinutes |> String.fromInt)
                              )
                            , ( "max dist", state.settings.farmBarbarianVillageMaximumDistance |> String.fromInt )
                            ]
                                |> List.map (\( settingName, settingValue ) -> settingName ++ ": " ++ settingValue)
                                |> String.join ", "
                           )

                activityDescription =
                    activityDecisionStages
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"
            in
            [ [ "Session performance: " ++ describeSessionPerformance ]
            , completedFarmCyclesReportLines
            , sentAttacksReportPartCurrentCycle
            , [ coordinatesChecksReport ]
            , [ inGameReport ]
            , [ readBattleReportsReport ]
            , reloadReportLines
            , [ parseResponseErrorReport ]
            , if enableDebugInspection then
                debugInspectionLines

              else
                []
            , [ "", "Current activity:" ]
            , [ activityDescription ]
            , [ "---", settingsReport ]
            ]
                |> List.concat
                |> String.join "\n"


areAllVillagesLoaded : TribalWars2RootInformation -> Bool
areAllVillagesLoaded rootInfo =
    rootInfo.getTotalVillagesResult == (rootInfo.readyVillages |> List.length)


describeOrdinalNumber : Int -> String
describeOrdinalNumber number =
    [ ( 1, "first" )
    , ( 2, "second" )
    , ( 3, "third" )
    , ( 4, "fourth" )
    ]
        |> Dict.fromList
        |> Dict.get number
        |> Maybe.withDefault ((number |> String.fromInt) ++ "th")


describeFarmCycleConclusion : FarmCycleConclusion -> { villagesReport : String, attacksReport : String }
describeFarmCycleConclusion conclusion =
    let
        countVillagesForResultKind villageResultKind =
            conclusion.villagesResults
                |> Dict.values
                |> List.filter ((==) villageResultKind)
                |> List.length

        villagesResultsReport =
            [ NoMatchingArmyPresetEnabledForThisVillage
            , ExhaustedAttackLimit
            , NotEnoughUnits
            , AllFarmsInSearchedAreaAlreadyAttackedInThisCycle
            ]
                |> List.filterMap
                    (\villageResultKind ->
                        let
                            villagesWithThisResult =
                                countVillagesForResultKind villageResultKind
                        in
                        if villagesWithThisResult < 1 then
                            Nothing

                        else
                            Just
                                ((describeVillageCompletion villageResultKind).cycleStatsGroup
                                    ++ ": "
                                    ++ (villagesWithThisResult |> String.fromInt)
                                )
                    )
                |> String.join ", "

        durationInMinutes =
            (conclusion.completionTime - conclusion.beginTime) // 60
    in
    { villagesReport =
        (conclusion.villagesResults |> Dict.size |> String.fromInt)
            ++ " villages ("
            ++ villagesResultsReport
            ++ ")."
    , attacksReport =
        "Sent "
            ++ (conclusion.attacksCount |> String.fromInt)
            ++ " attacks in "
            ++ (durationInMinutes |> String.fromInt)
            ++ " minutes."
    }


countSentAttacks : BotState -> { inSession : Int, inCurrentCycle : Maybe Int }
countSentAttacks state =
    let
        countInFarmCycle =
            .sentAttackByCoordinates >> Dict.size

        attackSentInEarlierCycles =
            state.completedFarmCycles |> List.map .attacksCount |> List.sum

        inCurrentCycle =
            case state.farmState of
                InFarmCycle _ farmCycle ->
                    Just (farmCycle |> countInFarmCycle)

                InBreak _ ->
                    Nothing
    in
    { inSession = attackSentInEarlierCycles + (inCurrentCycle |> Maybe.withDefault 0), inCurrentCycle = inCurrentCycle }


villageCoordinatesDisplayText : VillageCoordinates -> String
villageCoordinatesDisplayText { x, y } =
    (x |> String.fromInt) ++ "|" ++ (y |> String.fromInt)


describeRunJavascriptInCurrentPageResponseStructure : BotFramework.RunJavascriptInCurrentPageResponseStructure -> String
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


nothingFromIntIfGreaterThan : Int -> Int -> Maybe Int
nothingFromIntIfGreaterThan limit originalInt =
    if limit < originalInt then
        Nothing

    else
        Just originalInt

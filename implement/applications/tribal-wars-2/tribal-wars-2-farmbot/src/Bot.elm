{- Tribal Wars 2 farmbot version 2020-03-18
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

   All settings are optional; you only need it in case the defaults don't fit your use-case.
   You can adjust two settings:

   + 'number-of-farm-cycles' : Number of farm cycles before the bot stops completely. The default is 1.
   + 'break-duration' : Duration of breaks between farm cycles, in minutes. You can also specify a range like '60-120'. I will then pick a random value in this range.

   Here is an example of applying a configuration for three farm cycles with breaks of 20 to 40 minutes in between:
   --bot-configuration="number-of-farm-cycles = 3, break-duration = 20 - 40"
-}
{-
   bot-catalog-tags:tribal-wars-2,farmbot
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , initState
    , processEvent
    )

import BotEngine.Interface_To_Host_20200213 as InterfaceToHost
import Dict
import Json.Decode
import Json.Encode
import List.Extra
import Result.Extra
import Set
import WebBrowser.BotFramework as BotFramework exposing (BotEvent, BotResponse)


defaultBotSettings : BotSettings
defaultBotSettings =
    { numberOfFarmCycles = 1
    , breakDurationMinMinutes = 90
    , breakDurationMaxMinutes = 120
    }


parseBotSettingsNames : Dict.Dict String (String -> Result String (BotSettings -> BotSettings))
parseBotSettingsNames =
    [ ( "number-of-farm-cycles", parseBotSettingInt (\numberOfFarmCycles settings -> { settings | numberOfFarmCycles = numberOfFarmCycles }) )
    , ( "break-duration", parseBotSettingBreakDurationMinutes )
    ]
        |> Dict.fromList


farmArmyPresetNamePattern : String
farmArmyPresetNamePattern =
    "farm"


restartGameClientInterval : Int
restartGameClientInterval =
    60 * 15


waitDurationAfterReloadWebPage : Int
waitDurationAfterReloadWebPage =
    15


numberOfAttacksLimitPerVillage : Int
numberOfAttacksLimitPerVillage =
    50


ownVillageInfoMaxAge : Int
ownVillageInfoMaxAge =
    120


selectedVillageInfoMaxAge : Int
selectedVillageInfoMaxAge =
    15


searchFarmsRadiusAroundOwnVillage : Int
searchFarmsRadiusAroundOwnVillage =
    30


readFromGameTimeoutCountThresholdToRestart : Int
readFromGameTimeoutCountThresholdToRestart =
    5


type alias BotState =
    { timeInMilliseconds : Int
    , settings : BotSettings
    , currentActivity : Maybe { beginTimeInMilliseconds : Int, decision : DecisionPathNode InFarmCycleResponse }
    , lastRunJavascriptResult :
        Maybe
            { timeInMilliseconds : Int
            , response : BotFramework.RunJavascriptInCurrentPageResponseStructure
            , parseResult : Result Json.Decode.Error RootInformationStructure
            }
    , gameRootInformationResult : Maybe { timeInMilliseconds : Int, gameRootInformation : TribalWars2RootInformation }
    , ownVillagesDetails : Dict.Dict Int { timeInMilliseconds : Int, villageDetails : VillageDetails }
    , getArmyPresetsResult : Maybe (List ArmyPreset)
    , lastJumpToCoordinates : Maybe { timeInMilliseconds : Int, coordinates : VillageCoordinates }
    , coordinatesLastCheck : Dict.Dict ( Int, Int ) { timeInMilliseconds : Int, result : VillageByCoordinatesResult }
    , readFromGameConsecutiveTimeoutsCount : Int
    , farmState : FarmState
    , lastAttackTimeInMilliseconds : Maybe Int
    , lastActivatedVillageTimeInMilliseconds : Maybe Int
    , lastReloadPageTimeInSeconds : Maybe Int
    , reloadPageCount : Int
    , completedFarmCycles : List FarmCycleState
    , parseResponseError : Maybe Json.Decode.Error
    }


type alias BotSettings =
    { numberOfFarmCycles : Int
    , breakDurationMinMinutes : Int
    , breakDurationMaxMinutes : Int
    }


type alias FarmCycleState =
    { sentAttackByCoordinates : Dict.Dict ( Int, Int ) ()
    }


type FarmState
    = InFarmCycle FarmCycleState
    | InBreak { lastCycleCompletionTime : Int, nextCycleStartTime : Int }


type alias State =
    BotFramework.StateIncludingSetup BotState


type ResponseFromBrowser
    = RootInformation RootInformationStructure
    | ReadSelectedCharacterVillageDetailsResponse ReadSelectedCharacterVillageDetailsResponseStructure
    | VillageByCoordinatesResponse VillageByCoordinatesResponseStructure
    | GetPresetsResponse (List ArmyPreset)
    | ActivatedVillageResponse
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
    | FinishFarmCycle


type alias ContinueFarmCycleStructure =
    Maybe ContinueFarmCycleActivity


type ContinueFarmCycleActivity
    = RunJavascript String
    | ReloadWebPage


type VillageCompletedStructure
    = NoMatchingArmyPresetEnabledForThisVillage
    | NotEnoughUnits
    | ExhaustedAttackLimit
    | AllFarmsInSearchedAreaAlreadyAttackedInThisCycle


type VillageEndDecisionPathStructure
    = CompletedThisVillage VillageCompletedStructure
    | ContinueWithThisVillage ActionFromVillage


type DecisionPathNode leaf
    = DescribeBranch String (DecisionPathNode leaf)
    | EndDecisionPath leaf


type ActionFromVillage
    = GetVillageInfoAtCoordinates VillageCoordinates
    | AttackAtCoordinates ArmyPreset VillageCoordinates


initState : State
initState =
    BotFramework.initState
        { timeInMilliseconds = 0
        , settings = defaultBotSettings
        , currentActivity = Nothing
        , lastRunJavascriptResult = Nothing
        , gameRootInformationResult = Nothing
        , ownVillagesDetails = Dict.empty
        , getArmyPresetsResult = Nothing
        , lastJumpToCoordinates = Nothing
        , coordinatesLastCheck = Dict.empty
        , readFromGameConsecutiveTimeoutsCount = 0
        , farmState = InFarmCycle initFarmCycle
        , lastAttackTimeInMilliseconds = Nothing
        , lastActivatedVillageTimeInMilliseconds = Nothing
        , lastReloadPageTimeInSeconds = Nothing
        , reloadPageCount = 0
        , completedFarmCycles = []
        , parseResponseError = Nothing
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


processEvent : InterfaceToHost.BotEvent -> State -> ( State, InterfaceToHost.BotResponse )
processEvent =
    BotFramework.processEvent processWebBrowserBotEvent


processWebBrowserBotEvent : BotEvent -> BotState -> { newState : BotState, response : BotResponse, statusMessage : String }
processWebBrowserBotEvent event stateBeforeIntegrateEvent =
    case stateBeforeIntegrateEvent |> integrateWebBrowserBotEvent event of
        Err integrateEventError ->
            { newState = stateBeforeIntegrateEvent, response = BotFramework.FinishSession, statusMessage = "Error: " ++ integrateEventError }

        Ok stateBefore ->
            let
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
                                            if currentActivity.beginTimeInMilliseconds < lastRunJavascriptResult.timeInMilliseconds then
                                                Nothing

                                            else
                                                Just currentActivity.beginTimeInMilliseconds

                                waitTimeLimits =
                                    [ stateBefore.lastRunJavascriptResult |> Maybe.map (.timeInMilliseconds >> (+) 500)
                                    , pendingRequestTimeInMilliseconds |> Maybe.map ((+) 3000)
                                    ]
                                        |> List.filterMap identity
                            in
                            if stateBefore.timeInMilliseconds < (waitTimeLimits |> List.maximum |> Maybe.withDefault 0) then
                                Just currentActivity.decision

                            else
                                Nothing
            in
            let
                ( activityDecision, maybeUpdatedState ) =
                    case maybeCurrentActivityToWaitFor of
                        Just currentActivityToWaitFor ->
                            ( currentActivityToWaitFor
                                |> continueDecisionTree
                                    (always
                                        (DescribeBranch "Wait for completion of request to framework."
                                            (EndDecisionPath (BotFramework.ContinueSession Nothing))
                                        )
                                    )
                            , Nothing
                            )

                        Nothing ->
                            decideNextAction { stateBefore | currentActivity = Nothing }
                                |> Tuple.mapSecond Just
                                |> Tuple.mapFirst
                                    (continueDecisionTree
                                        (\originalLeaf -> DescribeBranch "Request to framework." (EndDecisionPath originalLeaf))
                                    )

                ( activityDecisionStages, responseToFramework ) =
                    activityDecision
                        |> unpackToDecisionStagesDescriptionsAndLeaf

                activityDescription =
                    activityDecisionStages
                        |> List.indexedMap
                            (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                        |> String.join "\n"
            in
            { newState = maybeUpdatedState |> Maybe.withDefault stateBefore
            , response = responseToFramework
            , statusMessage = statusMessageFromState stateBefore ++ "\nCurrent activity:\n" ++ activityDescription
            }


decideNextAction : BotState -> ( DecisionPathNode BotResponse, BotState )
decideNextAction stateBefore =
    case stateBefore.farmState of
        InBreak farmBreak ->
            let
                minutesSinceLastFarmCycleCompletion =
                    (stateBefore.timeInMilliseconds // 1000 - farmBreak.lastCycleCompletionTime) // 60

                minutesToNextFarmCycleStart =
                    (farmBreak.nextCycleStartTime - stateBefore.timeInMilliseconds // 1000) // 60
            in
            if minutesToNextFarmCycleStart < 1 then
                ( DescribeBranch "Start next farm cycle."
                    (EndDecisionPath (BotFramework.ContinueSession Nothing))
                , { stateBefore | farmState = InFarmCycle initFarmCycle }
                )

            else
                ( DescribeBranch
                    ("Next farm cycle starts in "
                        ++ (minutesToNextFarmCycleStart |> String.fromInt)
                        ++ " minutes. Last cycle completed "
                        ++ (minutesSinceLastFarmCycleCompletion |> String.fromInt)
                        ++ " minutes ago."
                    )
                    (EndDecisionPath (BotFramework.ContinueSession Nothing))
                , stateBefore
                )

        InFarmCycle farmCycleState ->
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
                                                ( javascriptToRun, updatedStateForActivity ) =
                                                    case activity of
                                                        RunJavascript javascript ->
                                                            ( javascript, stateBefore )

                                                        ReloadWebPage ->
                                                            ( reloadPageScript
                                                            , { stateBefore
                                                                | lastReloadPageTimeInSeconds = Just (stateBefore.timeInMilliseconds // 1000)
                                                                , reloadPageCount = stateBefore.reloadPageCount + 1
                                                                , readFromGameConsecutiveTimeoutsCount = 0
                                                              }
                                                            )
                                            in
                                            ( Just
                                                (BotFramework.RunJavascriptInCurrentPageRequest
                                                    { javascript = javascriptToRun
                                                    , requestId = "request-id"
                                                    , timeToWaitForCallbackMilliseconds = 1000
                                                    }
                                                )
                                            , updatedStateForActivity
                                            )
                            in
                            ( EndDecisionPath (BotFramework.ContinueSession maybeRequest)
                            , Just decisionInFarmCycle
                            , updatedStateFromContinueCycle
                            )

                        FinishFarmCycle ->
                            let
                                completedFarmCycles =
                                    farmCycleState :: stateBefore.completedFarmCycles

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
                            ( DescribeBranch "There is nothing left to do in this farm cycle."
                                (if stateBefore.settings.numberOfFarmCycles <= (stateAfterFinishingFarmCycle.completedFarmCycles |> List.length) then
                                    DescribeBranch
                                        ("Finished all " ++ (stateAfterFinishingFarmCycle.completedFarmCycles |> List.length |> String.fromInt) ++ " farm cycles.")
                                        (EndDecisionPath BotFramework.FinishSession)

                                 else
                                    DescribeBranch "Enter break."
                                        (EndDecisionPath (BotFramework.ContinueSession Nothing))
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


parseBotSettingInt : (Int -> BotSettings -> BotSettings) -> String -> Result String (BotSettings -> BotSettings)
parseBotSettingInt integrateInt argumentAsString =
    case argumentAsString |> String.toInt of
        Nothing ->
            Err ("Failed to parse '" ++ argumentAsString ++ "' as integer.")

        Just int ->
            Ok (integrateInt int)


parseSettingsFromString : BotSettings -> String -> Result String BotSettings
parseSettingsFromString settingsBefore settingsString =
    let
        assignments =
            settingsString |> String.split ","

        assignmentFunctionResults =
            assignments
                |> List.map String.trim
                |> List.filter (String.isEmpty >> not)
                |> List.map
                    (\assignment ->
                        case assignment |> String.split "=" |> List.map String.trim of
                            [ settingName, assignedValue ] ->
                                case parseBotSettingsNames |> Dict.get settingName of
                                    Nothing ->
                                        Err ("Unknown setting name '" ++ settingName ++ "'.")

                                    Just parseFunction ->
                                        parseFunction assignedValue
                                            |> Result.mapError (\parseError -> "Failed to parse value for setting '" ++ settingName ++ "': " ++ parseError)

                            _ ->
                                Err ("Failed to parse assignment '" ++ assignment ++ "'.")
                    )
    in
    assignmentFunctionResults
        |> Result.Extra.combine
        |> Result.map
            (\assignmentFunctions ->
                assignmentFunctions
                    |> List.foldl (\assignmentFunction previousSettings -> assignmentFunction previousSettings)
                        settingsBefore
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


integrateWebBrowserBotEvent : BotEvent -> BotState -> Result String BotState
integrateWebBrowserBotEvent event stateBefore =
    case event of
        BotFramework.SetBotConfiguration configurationString ->
            let
                parseSettingsResult =
                    parseSettingsFromString defaultBotSettings configurationString
            in
            parseSettingsResult
                |> Result.map (\newSettings -> { stateBefore | settings = newSettings })
                |> Result.mapError (\parseError -> "Failed to parse bot settings: " ++ parseError)

        BotFramework.ArrivedAtTime { timeInMilliseconds } ->
            Ok { stateBefore | timeInMilliseconds = timeInMilliseconds }

        BotFramework.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            Ok
                (integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse stateBefore)


integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse : BotFramework.RunJavascriptInCurrentPageResponseStructure -> BotState -> BotState
integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse stateBefore =
    let
        parseAsRootInfoResult =
            runJavascriptInCurrentPageResponse.directReturnValueAsString
                |> Json.Decode.decodeString decodeRootInformation

        stateAfterIntegrateResponse =
            { stateBefore
                | lastRunJavascriptResult =
                    Just
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , response = runJavascriptInCurrentPageResponse
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
                                        , readFromGameConsecutiveTimeoutsCount = 0
                                    }

                SendFirstPresetAsAttackToCoordinatesResponse sendFirstPresetAsAttackToCoordinatesResponse ->
                    let
                        updatedFarmState =
                            case stateAfterParseSuccess.farmState of
                                InFarmCycle currentFarmCycleBefore ->
                                    let
                                        sentAttackByCoordinates =
                                            currentFarmCycleBefore.sentAttackByCoordinates
                                                |> Dict.insert
                                                    ( sendFirstPresetAsAttackToCoordinatesResponse.villageCoordinates.x
                                                    , sendFirstPresetAsAttackToCoordinatesResponse.villageCoordinates.y
                                                    )
                                                    ()
                                    in
                                    { currentFarmCycleBefore
                                        | sentAttackByCoordinates = sentAttackByCoordinates
                                    }
                                        |> InFarmCycle
                                        |> Just

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


decideInFarmCycle : BotState -> FarmCycleState -> DecisionPathNode InFarmCycleResponse
decideInFarmCycle botState farmCycleState =
    case botState |> lastReloadPageAgeInSecondsFromState |> Maybe.andThen (nothingFromIntIfGreaterThan waitDurationAfterReloadWebPage) of
        Just lastReloadPageAgeInSeconds ->
            DescribeBranch
                ("Waiting because reloaded web page " ++ (lastReloadPageAgeInSeconds |> String.fromInt) ++ " seconds ago.")
                (EndDecisionPath (ContinueFarmCycle Nothing))

        Nothing ->
            case botState |> reasonToRestartGameClientFromBotState of
                Just reasonToRestartGameClient ->
                    DescribeBranch
                        ("Restart the game client (" ++ reasonToRestartGameClient ++ ").")
                        (EndDecisionPath (ContinueFarmCycle (Just ReloadWebPage)))

                Nothing ->
                    let
                        waitAfterJumpedToCoordinates =
                            botState.lastJumpToCoordinates
                                |> Maybe.map
                                    (\lastJumpToCoordinates -> botState.timeInMilliseconds - lastJumpToCoordinates.timeInMilliseconds < 1100)
                                |> Maybe.withDefault False
                    in
                    if waitAfterJumpedToCoordinates then
                        DescribeBranch
                            "Waiting after jumping to village."
                            (EndDecisionPath (ContinueFarmCycle Nothing))

                    else
                        decideInFarmCycleWhenNotWaitingGlobally botState farmCycleState


decideInFarmCycleWhenNotWaitingGlobally : BotState -> FarmCycleState -> DecisionPathNode InFarmCycleResponse
decideInFarmCycleWhenNotWaitingGlobally botState farmCycleState =
    let
        sufficientlyNewGameRootInformation =
            botState.gameRootInformationResult
                |> Maybe.andThen
                    (\gameRootInformationResult ->
                        let
                            updateTimeMinimumMilli =
                                (botState.lastActivatedVillageTimeInMilliseconds |> Maybe.withDefault 0)
                                    |> max (botState.timeInMilliseconds - 15000)
                        in
                        if gameRootInformationResult.timeInMilliseconds <= updateTimeMinimumMilli then
                            Nothing

                        else
                            Just gameRootInformationResult.gameRootInformation
                    )
    in
    case sufficientlyNewGameRootInformation of
        Nothing ->
            DescribeBranch
                "Game root information is not recent enough."
                (EndDecisionPath (ContinueFarmCycle (Just (RunJavascript readRootInformationScript))))

        Just gameRootInformation ->
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
            "Found "
                ++ (gameRootInformation.readyVillages |> List.length |> String.fromInt)
                ++ " own villages. Currently selected is "
                ++ (gameRootInformation.selectedVillageId |> String.fromInt)
                ++ " ("
                ++ describeSelectedVillageDetails
                ++ ")"

        continueFromDecisionInVillage : VillageEndDecisionPathStructure -> DecisionPathNode InFarmCycleResponse
        continueFromDecisionInVillage decisionInVillage =
            case decisionInVillage of
                ContinueWithThisVillage (GetVillageInfoAtCoordinates coordinates) ->
                    DescribeBranch
                        ("Search for village at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                        (EndDecisionPath
                            (ContinueFarmCycle
                                (Just (RunJavascript (startVillageByCoordinatesScript coordinates { jumpToVillage = False })))
                            )
                        )

                ContinueWithThisVillage (AttackAtCoordinates armyPreset coordinates) ->
                    DescribeBranch
                        ("Farm at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                        (case scriptToJumpToVillageIfNotYetDone botState coordinates of
                            Just jumpToVillageScript ->
                                DescribeBranch
                                    ("Jump to village at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                                    (EndDecisionPath (ContinueFarmCycle (Just (RunJavascript jumpToVillageScript))))

                            Nothing ->
                                DescribeBranch
                                    ("Send attack using preset '" ++ armyPreset.name ++ "'.")
                                    (EndDecisionPath
                                        (ContinueFarmCycle
                                            (Just
                                                (RunJavascript
                                                    (startSendFirstPresetAsAttackToCoordinatesScript coordinates { presetId = armyPreset.id })
                                                )
                                            )
                                        )
                                    )
                        )

                CompletedThisVillage completion ->
                    let
                        describeCompletion =
                            case completion of
                                NoMatchingArmyPresetEnabledForThisVillage ->
                                    "No matching preset for this village."

                                NotEnoughUnits ->
                                    "Not enough units."

                                ExhaustedAttackLimit ->
                                    "Exhausted the attack limit."

                                AllFarmsInSearchedAreaAlreadyAttackedInThisCycle ->
                                    "All farms in the search area have already been attacked in this farm cycle."
                    in
                    DescribeBranch
                        ("Current village is completed (" ++ describeCompletion ++ ").")
                        (let
                            otherVillagesWithDetails =
                                gameRootInformation.readyVillages
                                    |> Set.fromList
                                    |> Set.remove gameRootInformation.selectedVillageId
                                    |> Set.toList
                                    |> List.filterMap
                                        (\otherVillageId ->
                                            sufficientyFreshOwnVillagesDetails
                                                |> Dict.get otherVillageId
                                                |> Maybe.map
                                                    (\otherVillageDetailsResponse ->
                                                        ( otherVillageId, otherVillageDetailsResponse.villageDetails )
                                                    )
                                        )

                            otherVillagesWithAvailableAction =
                                otherVillagesWithDetails
                                    |> List.filter
                                        (decideNextActionForVillage botState farmCycleState
                                            >> (\otherVillageDecisionPath ->
                                                    case otherVillageDecisionPath |> unpackToDecisionStagesDescriptionsAndLeaf |> Tuple.second of
                                                        CompletedThisVillage _ ->
                                                            False

                                                        ContinueWithThisVillage _ ->
                                                            True
                                               )
                                        )
                         in
                         case otherVillagesWithAvailableAction |> List.head of
                            Nothing ->
                                DescribeBranch "All villages completed."
                                    (EndDecisionPath FinishFarmCycle)

                            Just ( villageToActivateId, villageToActivateDetails ) ->
                                DescribeBranch
                                    ("Switch to village " ++ (villageToActivateId |> String.fromInt) ++ " at " ++ (villageToActivateDetails.coordinates |> villageCoordinatesDisplayText) ++ ".")
                                    (EndDecisionPath
                                        (ContinueFarmCycle
                                            (Just
                                                (RunJavascript
                                                    (scriptToJumpToVillageIfNotYetDone botState villageToActivateDetails.coordinates
                                                        |> Maybe.withDefault villageMenuActivateVillageScript
                                                    )
                                                )
                                            )
                                        )
                                    )
                        )
    in
    case ownVillagesNeedingDetailsUpdate of
        ownVillageNeedingDetailsUpdate :: _ ->
            DescribeBranch
                ("Read status of own village " ++ (ownVillageNeedingDetailsUpdate |> String.fromInt) ++ ".")
                (EndDecisionPath
                    (ContinueFarmCycle
                        (Just (RunJavascript (readSelectedCharacterVillageDetailsScript ownVillageNeedingDetailsUpdate)))
                    )
                )

        [] ->
            DescribeBranch describeSelectedVillage
                (case selectedVillageUpdatedDetails of
                    Nothing ->
                        DescribeBranch
                            ("Read status of current selected village (" ++ (gameRootInformation.selectedVillageId |> String.fromInt) ++ ")")
                            (EndDecisionPath
                                (ContinueFarmCycle
                                    (Just (RunJavascript (readSelectedCharacterVillageDetailsScript gameRootInformation.selectedVillageId)))
                                )
                            )

                    Just selectedVillageDetails ->
                        case botState.getArmyPresetsResult |> Maybe.withDefault [] of
                            [] ->
                                {- 2020-01-28 Observation: We get an empty list here at least sometimes at the beginning of a session.
                                   The number of presets we get can increase with the next query.

                                   -- TODO: Add timeout for getting presets.
                                -}
                                DescribeBranch
                                    "Did not find any army presets. Maybe loading is not completed yet. Load army presets."
                                    (EndDecisionPath (ContinueFarmCycle (Just (RunJavascript getPresetsScript))))

                            _ ->
                                decideNextActionForVillage
                                    botState
                                    farmCycleState
                                    ( gameRootInformation.selectedVillageId, selectedVillageDetails )
                                    |> continueDecisionTree continueFromDecisionInVillage
                )


lastReloadPageAgeInSecondsFromState : BotState -> Maybe Int
lastReloadPageAgeInSecondsFromState state =
    state.lastReloadPageTimeInSeconds
        |> Maybe.map (\lastReloadPageTimeInSeconds -> state.timeInMilliseconds // 1000 - lastReloadPageTimeInSeconds)


scriptToJumpToVillageIfNotYetDone : BotState -> VillageCoordinates -> Maybe String
scriptToJumpToVillageIfNotYetDone state coordinates =
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
        Just (startVillageByCoordinatesScript coordinates { jumpToVillage = True })

    else
        Nothing


decideNextActionForVillage : BotState -> FarmCycleState -> ( Int, VillageDetails ) -> DecisionPathNode VillageEndDecisionPathStructure
decideNextActionForVillage botState farmCycleState ( villageId, villageDetails ) =
    pickBestMatchingArmyPresetForVillage
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
        DescribeBranch
            ("Number of commands from this village is " ++ (numberOfCommandsFromThisVillage |> String.fromInt) ++ ".")
            (EndDecisionPath (CompletedThisVillage ExhaustedAttackLimit))

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
                                                village.affiliation == AffiliationBarbarian
                        )
                    >> List.head

            nextRemainingCoordinates =
                {- 2020-03-15 Specialize for runtime expenses:
                   Adapt to limitations of the current Elm runtime:
                   Process the coordinates in partitions to reduce computations of results we will not use anyway. In the end, we only take the first element, but the current runtime performs a more eager evaluation.
                -}
                relativeCoordinatesToSearchForFarmsPartitions
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
            |> EndDecisionPath


pickBestMatchingArmyPresetForVillage :
    List ArmyPreset
    -> ( Int, VillageDetails )
    -> (ArmyPreset -> DecisionPathNode VillageEndDecisionPathStructure)
    -> DecisionPathNode VillageEndDecisionPathStructure
pickBestMatchingArmyPresetForVillage presets ( villageId, villageDetails ) continueWithArmyPreset =
    if presets |> List.isEmpty then
        DescribeBranch "Did not find any army presets."
            (EndDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

    else
        let
            farmPresetFilter =
                farmArmyPresetNamePattern

            farmPresetsMaybeEmpty =
                presets
                    |> List.filter (.name >> String.toLower >> String.contains (farmPresetFilter |> String.toLower))
                    |> List.sortBy (.name >> String.toLower)
        in
        case farmPresetsMaybeEmpty of
            [] ->
                DescribeBranch ("Found no army presets matching the filter '" ++ farmPresetFilter ++ "'.")
                    (EndDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

            farmPresets ->
                case
                    farmPresets
                        |> List.filter (.assigned_villages >> List.member villageId)
                of
                    [] ->
                        DescribeBranch
                            ("Found " ++ (farmPresets |> List.length |> String.fromInt) ++ " army presets for farming, but none enabled for this village.")
                            (EndDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

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
                                DescribeBranch
                                    ("Found " ++ (farmPresetsEnabledForThisVillage |> List.length |> String.fromInt) ++ " farming army presets enabled for this village, but not sufficient units available for any of these.")
                                    (EndDecisionPath (CompletedThisVillage NotEnoughUnits))

                            Just bestMatchingPreset ->
                                DescribeBranch
                                    ("Best matching army preset for this village is '" ++ bestMatchingPreset.name ++ "'.")
                                    (continueWithArmyPreset bestMatchingPreset)


relativeCoordinatesToSearchForFarms : List VillageCoordinates
relativeCoordinatesToSearchForFarms =
    coordinatesInCircleOrderedByDistance searchFarmsRadiusAroundOwnVillage


relativeCoordinatesToSearchForFarmsPartitions : List (List VillageCoordinates)
relativeCoordinatesToSearchForFarmsPartitions =
    relativeCoordinatesToSearchForFarms
        |> List.Extra.greedyGroupsOf 400


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


reloadPageScript : String
reloadPageScript =
    """window.location.reload()"""


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
        , decodeActivatedVillageResponse |> Json.Decode.map (always ActivatedVillageResponse)
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
            'target_id'\t\t: targetVillageId
        }, function(data) {
            var targetData = {
                'id'\t\t\t\t: targetVillageId,
                'attackProtection'\t: data.attack_protection,
                'barbarianVillage'\t: data.owner_id === null
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


statusMessageFromState : BotState -> String
statusMessageFromState state =
    let
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

        coordinatesChecksReport =
            "Checked "
                ++ (state.coordinatesLastCheck |> Dict.size |> String.fromInt)
                ++ " coordinates and found "
                ++ (villagesByCoordinates |> Dict.size |> String.fromInt)
                ++ " villages, "
                ++ (villagesByCoordinates |> Dict.filter (\_ village -> village.affiliation == AffiliationBarbarian) |> Dict.size |> String.fromInt)
                ++ " of wich are barbarian villages."

        sentAttacks =
            countSentAttacks state

        sentAttacksReportPartSession =
            "Sent " ++ (sentAttacks.inSession |> String.fromInt) ++ " attacks in this session"

        sentAttacksReportPartCurrentCycle =
            case sentAttacks.inCurrentCycle of
                Nothing ->
                    "."

                Just inCurrentCycle ->
                    ", " ++ (inCurrentCycle |> String.fromInt) ++ " in the current cycle."

        completedFarmCyclesReportLines =
            case state.completedFarmCycles of
                [] ->
                    []

                completedFarmCycles ->
                    [ "Completed "
                        ++ (completedFarmCycles |> List.length |> String.fromInt)
                        ++ " of "
                        ++ (state.settings.numberOfFarmCycles |> String.fromInt)
                        ++ " farm cycles."
                    ]

        sentAttacksReport =
            sentAttacksReportPartSession ++ sentAttacksReportPartCurrentCycle

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
                                ++ (gameRootInformation.readyVillages |> List.length |> String.fromInt)
                                ++ " own villages."
                    in
                    [ [ ownVillagesReport ]
                    , completedFarmCyclesReportLines
                    , [ sentAttacksReport ]
                    , [ coordinatesChecksReport ]
                    ]
                        |> List.concat
                        |> String.join "\n"

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

        allReportLines =
            [ [ inGameReport ]
            , reloadReportLines
            , [ parseResponseErrorReport ]
            , if enableDebugInspection then
                debugInspectionLines

              else
                []
            ]
                |> List.concat
    in
    allReportLines
        |> String.join "\n"


countSentAttacks : BotState -> { inSession : Int, inCurrentCycle : Maybe Int }
countSentAttacks state =
    let
        countInFarmCycle =
            .sentAttackByCoordinates >> Dict.size

        attackSentInEarlierCycles =
            state.completedFarmCycles |> List.map countInFarmCycle |> List.sum

        inCurrentCycle =
            case state.farmState of
                InFarmCycle farmCycle ->
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


continueDecisionTree : (originalLeaf -> DecisionPathNode newLeaf) -> DecisionPathNode originalLeaf -> DecisionPathNode newLeaf
continueDecisionTree continueLeaf originalNode =
    case originalNode of
        DescribeBranch branch childNode ->
            DescribeBranch branch (continueDecisionTree continueLeaf childNode)

        EndDecisionPath leaf ->
            continueLeaf leaf


unpackToDecisionStagesDescriptionsAndLeaf : DecisionPathNode leaf -> ( List String, leaf )
unpackToDecisionStagesDescriptionsAndLeaf node =
    case node of
        EndDecisionPath leaf ->
            ( [], leaf )

        DescribeBranch branchDescription childNode ->
            let
                ( childDecisionsDescriptions, leaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf childNode
            in
            ( branchDescription :: childDecisionsDescriptions, leaf )


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

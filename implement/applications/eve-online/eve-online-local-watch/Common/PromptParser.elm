module Common.PromptParser exposing (..)

{-| This module helps you build bot prompt parsers.
We prevent confusion and ambiguity about interpreting the prompt text by listing a concrete set of known and understood terms and parsing it into a structured representation.
If the given bot prompt text does not conform with the configured format, the functions in this framework generate specific messages for the user to explain available settings and how to use them.

    The parsers built with this framework also provide additional commands, 'list settings' and 'explain setting', to make it easy for users to list all supported settings and their descriptions.

-}

import Dict
import JaroWinkler
import List.Extra
import Result.Extra
import String.Extra


type YesOrNo
    = Yes
    | No


type alias SettingConfig appSettings =
    { alternativeNames : List String
    , description : String
    , valueParser : SettingValueType appSettings
    }


type alias SettingValueType appSettings =
    String -> Result String (appSettings -> appSettings)


type alias IntervalInt =
    { minimum : Int, maximum : Int }


messageOnlyAcceptEmptyAppSettings : String
messageOnlyAcceptEmptyAppSettings =
    "I got a settings string that is not empty, but I only accept an empty settings string. I am not programmed to support any settings. Maybe there is another program that better suits your use case?"


{-| Build a setting that only accepts the strings `Yes` or `No`.
-}
valueTypeYesOrNo : (YesOrNo -> appSettings -> appSettings) -> SettingValueType appSettings
valueTypeYesOrNo =
    listAllSupportedValues { supportedValues = [ ( "yes", Yes ), ( "no", No ) ], ignoreCase = True }


{-| Build a setting that only accepts strings representing valid integers and maps them to integer values.
Here are some examples for supported values: `-1` `0`, `1234`.
-}
valueTypeInteger : (Int -> appSettings -> appSettings) -> SettingValueType appSettings
valueTypeInteger integrateSettingValue =
    \settingValueAsString ->
        case settingValueAsString |> String.toInt of
            Nothing ->
                Err ("Failed to parse '" ++ settingValueAsString ++ "' as integer.")

            Just int ->
                Ok (integrateSettingValue int)


{-| Build a setting that accepts any string.
-}
valueTypeString : (String -> appSettings -> appSettings) -> SettingValueType appSettings
valueTypeString integrateSettingValue =
    integrateSettingValue >> Ok


{-| This function builds a settings-string parser that only accepts an empty settings string.
-}
parseAllowOnlyEmpty : appSettings -> String -> Result String appSettings
parseAllowOnlyEmpty appSettings appSettingsString =
    if String.isEmpty appSettingsString then
        Ok appSettings

    else
        Err messageOnlyAcceptEmptyAppSettings


{-| This function builds a settings-string parser with two purposes:

  - Mapping an unstructured settings string into a structured representation for easy consumption by other program parts.
  - If the given settings string does not conform with the configured format, generate specific error messages for the user to explain available settings and how to use them.

This function parses a plain string into a value of any type, combining parsers from multiple named settings.
Use the dictionary argument to specify the settings to support in the settings string. The key of a dictionary entry is the name of the setting in the settings string. If the settings string contains an unsupported setting name, this framework generates an error message pointing out the most similar settings name and listing available settings. A parser for an individual setting from the dictionary can fail depending on the string found for this setting. In this case, this framework generates an error message, pointing out the name of the setting for which parsing the value failed.
This framework expects to find an equals sign (`=`) in each setting, separating the setting name and the assigned value.

-}
parseSimpleListOfAssignmentsSeparatedByNewlines :
    Dict.Dict String (SettingConfig appSettings)
    -> appSettings
    -> String
    -> Result String appSettings
parseSimpleListOfAssignmentsSeparatedByNewlines =
    parseSimpleListOfAssignments { assignmentsSeparators = [ "\n" ] }


{-| This function builds a settings-string parser with two purposes:

  - Mapping an unstructured settings string into a structured representation for easy consumption by other program parts.
  - If the given settings string does not conform with the configured format, generate specific error messages for the user to explain available settings and how to use them.

This function parses a plain string into a value of any type, combining parsers from multiple named settings.
Use the dictionary argument to specify the settings to support in the settings string. The key of a dictionary entry is the name of the setting in the settings string. If the settings string contains an unsupported setting name, this framework generates an error message pointing out the most similar settings name and listing available settings. A parser for an individual setting from the dictionary can fail depending on the string found for this setting. In this case, this framework generates an error message, pointing out the name of the setting for which parsing the value failed.
This framework expects to find an equals sign (`=`) in each setting, separating the setting name and the assigned value.

-}
parseSimpleListOfAssignments :
    { assignmentsSeparators : List String }
    -> Dict.Dict String (SettingConfig appSettings)
    -> appSettings
    -> String
    -> Result String appSettings
parseSimpleListOfAssignments { assignmentsSeparators } namedSettings defaultSettings settingsString =
    case guideOnSettingsHandler settingsString of
        Just guideHandler ->
            Err (guideHandler namedSettings)

        Nothing ->
            let
                assignments =
                    assignmentsSeparators
                        |> List.foldl (\assignmentSeparator -> List.concatMap (String.split assignmentSeparator))
                            [ settingsString ]

                assignmentValueSeparator =
                    "="

                assignmentFunctionResults =
                    assignments
                        |> List.map String.trim
                        |> List.filter (String.isEmpty >> not)
                        |> List.map
                            (\assignment ->
                                case namedSettings |> Dict.toList of
                                    [] ->
                                        Err messageOnlyAcceptEmptyAppSettings

                                    firstNamedSetting :: _ ->
                                        case assignment |> String.split assignmentValueSeparator of
                                            settingNameBeforeTrim :: assignedValueFirstElement :: assignedValueOtherElements ->
                                                let
                                                    settingName =
                                                        String.trim settingNameBeforeTrim

                                                    assignedValue =
                                                        (assignedValueFirstElement :: assignedValueOtherElements)
                                                            |> String.join assignmentValueSeparator
                                                            |> String.trim
                                                in
                                                getSettingByNameOrGuide settingName namedSettings
                                                    |> Result.andThen
                                                        (\settingConfig ->
                                                            settingConfig.valueParser assignedValue
                                                                |> Result.mapError
                                                                    ((++) ("Failed to parse value for setting '" ++ settingName ++ "': "))
                                                        )

                                            _ ->
                                                [ "Failed to parse assignment '"
                                                    ++ assignment
                                                    ++ "': Did not find the equals sign '=' in this text."
                                                , "Here is an example of an assignment:"
                                                , Tuple.first firstNamedSetting ++ " = 1234"
                                                ]
                                                    |> String.join "\n"
                                                    |> Err
                            )
            in
            assignmentFunctionResults
                |> Result.Extra.combine
                |> Result.map
                    (List.foldl (\assignmentFunction previousSettings -> assignmentFunction previousSettings)
                        defaultSettings
                    )


guideOnSettingsHandler : String -> Maybe (Dict.Dict String (SettingConfig appSettings) -> String)
guideOnSettingsHandler settingsString =
    let
        settingsStringWords =
            String.words (String.toLower settingsString)
    in
    case settingsStringWords of
        [ "list", "setting" ] ->
            Just respondToCommandListSettings

        [ "list", "settings" ] ->
            Just respondToCommandListSettings

        [ "explain", "settings" ] ->
            Just respondToCommandListSettings

        [ "explain", "setting", settingName ] ->
            Just (explainSettingHandler settingName)

        [ "list", "setting", settingName ] ->
            Just (explainSettingHandler settingName)

        [ "explain", "setting" ] ->
            Just (listSettingsTextWithHeading >> (++) "Missing setting name. ")

        _ ->
            Nothing


explainSettingHandler : String -> Dict.Dict String (SettingConfig appSettings) -> String
explainSettingHandler settingName namedSettings =
    getSettingByNameOrGuide settingName namedSettings
        |> Result.Extra.unpack
            identity
            (\selectedSetting -> "Description of setting '" ++ settingName ++ "':\n" ++ selectedSetting.description)


getSettingByNameOrGuide :
    String
    -> Dict.Dict String (SettingConfig appSettings)
    -> Result String (SettingConfig appSettings)
getSettingByNameOrGuide settingName namedSettings =
    case Dict.get settingName namedSettings of
        Just settingConfig ->
            Ok settingConfig

        Nothing ->
            case
                namedSettings
                    |> Dict.toList
                    |> List.Extra.find
                        (\( _, settingConfig ) ->
                            settingConfig.alternativeNames
                                |> List.member settingName
                        )
            of
                Just ( _, settingConfig ) ->
                    Ok settingConfig

                Nothing ->
                    let
                        settingsNamesWithSimilarity : List ( String, Int )
                        settingsNamesWithSimilarity =
                            namedSettings
                                |> Dict.foldl
                                    (\primaryName settingConfig aggregate ->
                                        settingConfig.alternativeNames
                                            ++ [ primaryName ]
                                            ++ aggregate
                                    )
                                    []
                                |> List.map
                                    (\supportedSettingName ->
                                        ( supportedSettingName
                                        , round (1000 * JaroWinkler.similarity supportedSettingName settingName)
                                        )
                                    )
                                |> List.sortBy (Tuple.second >> negate)

                        pointOutSimilarSettingNameLines =
                            case
                                settingsNamesWithSimilarity
                                    |> List.filter (Tuple.second >> (<=) 500)
                            of
                                ( mostSimilarSettingName, _ ) :: _ ->
                                    [ "Did you mean '" ++ mostSimilarSettingName ++ "'?" ]

                                _ ->
                                    []
                    in
                    [ [ "Unknown setting name '" ++ settingName ++ "'." ]
                    , pointOutSimilarSettingNameLines
                    , [ listSettingsTextWithHeading namedSettings ]
                    ]
                        |> List.concat
                        |> String.join "\n"
                        |> Err


respondToCommandListSettings : Dict.Dict String (SettingConfig appSettings) -> String
respondToCommandListSettings namedSettings =
    [ "Are you looking for a list of all settings?"
    , listSettingsTextWithHeading namedSettings
    ]
        |> String.join " "


listSettingsTextWithHeading : Dict.Dict String (SettingConfig appSettings) -> String
listSettingsTextWithHeading namedSettings =
    "Following is a list of the "
        ++ String.fromInt (Dict.size namedSettings)
        ++ " setting names that I understand:\n"
        ++ (namedSettings
                |> Dict.keys
                |> List.map (String.Extra.surround "'")
                |> String.join "\n"
           )


listAllSupportedValues :
    { supportedValues : List ( String, settingValue ), ignoreCase : Bool }
    -> (settingValue -> appSettings -> appSettings)
    -> SettingValueType appSettings
listAllSupportedValues { supportedValues, ignoreCase } integrateSettingValue =
    let
        valuesAreSimilarEnough a b =
            if ignoreCase then
                (a |> String.toLower) == (b |> String.toLower)

            else
                a == b
    in
    \settingValueAsString ->
        case supportedValues |> List.filter (Tuple.first >> valuesAreSimilarEnough settingValueAsString) |> List.head of
            Maybe.Nothing ->
                Err
                    ("The setting value '"
                        ++ settingValueAsString
                        ++ "' matches none of the supported values ("
                        ++ (supportedValues |> List.map Tuple.first |> List.map (String.Extra.surround "'") |> String.join ", ")
                        ++ ")"
                    )

            Just ( _, settingValue ) ->
                Ok (integrateSettingValue settingValue)


parseIntervalIntFromPointOrIntervalString : String -> Result String IntervalInt
parseIntervalIntFromPointOrIntervalString intervalAsString =
    let
        boundsParseResults =
            intervalAsString
                |> String.split "-"
                |> List.map (\boundString -> boundString |> String.trim |> String.toInt |> Result.fromMaybe ("Failed to parse '" ++ boundString ++ "'"))
    in
    boundsParseResults
        |> Result.Extra.combine
        |> Result.andThen
            (\bounds ->
                case ( bounds |> List.minimum, bounds |> List.maximum ) of
                    ( Just minimum, Just maximum ) ->
                        Ok { minimum = minimum, maximum = maximum }

                    _ ->
                        Err "Missing value"
            )

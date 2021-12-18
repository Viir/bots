module Common.AppSettings exposing (..)

{-| This module helps you build settings-string parsers with two purposes:

  - Mapping an unstructured settings string into a structured representation for easy consumption by other program parts.
  - If the given settings string does not conform with the configured format, generate specific error messages for the user to explain available settings and how to use them.

-}

import Dict
import JaroWinkler
import Result.Extra
import String.Extra


type YesOrNo
    = Yes
    | No


type alias SettingValueType appSettings =
    String -> Result String (appSettings -> appSettings)


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
parseSimpleListOfAssignmentsSeparatedByNewlines : Dict.Dict String (SettingValueType appSettings) -> appSettings -> String -> Result String appSettings
parseSimpleListOfAssignmentsSeparatedByNewlines =
    parseSimpleListOfAssignments { assignmentsSeparators = [ "\n" ] }


{-| This function builds a settings-string parser with two purposes:

  - Mapping an unstructured settings string into a structured representation for easy consumption by other program parts.
  - If the given settings string does not conform with the configured format, generate specific error messages for the user to explain available settings and how to use them.

This function parses a plain string into a value of any type, combining parsers from multiple named settings.
Use the dictionary argument to specify the settings to support in the settings string. The key of a dictionary entry is the name of the setting in the settings string. If the settings string contains an unsupported setting name, this framework generates an error message pointing out the most similar settings name and listing available settings. A parser for an individual setting from the dictionary can fail depending on the string found for this setting. In this case, this framework generates an error message, pointing out the name of the setting for which parsing the value failed.
This framework expects to find an equals sign (`=`) in each setting, separating the setting name and the assigned value.

-}
parseSimpleListOfAssignments : { assignmentsSeparators : List String } -> Dict.Dict String (SettingValueType appSettings) -> appSettings -> String -> Result String appSettings
parseSimpleListOfAssignments { assignmentsSeparators } namedSettings defaultSettings settingsString =
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
                                        case namedSettings |> Dict.get settingName of
                                            Nothing ->
                                                let
                                                    settingsNamesWithSimilarity =
                                                        namedSettings
                                                            |> Dict.keys
                                                            |> List.map
                                                                (\supportedSettingName ->
                                                                    ( supportedSettingName
                                                                    , JaroWinkler.similarity supportedSettingName settingName
                                                                    )
                                                                )
                                                            |> List.sortBy (Tuple.second >> negate)

                                                    pointOutSimilarSettingNameLines =
                                                        case
                                                            settingsNamesWithSimilarity
                                                                |> List.filter (Tuple.second >> (<=) 0.5)
                                                        of
                                                            ( mostSimilarSettingName, _ ) :: _ ->
                                                                [ "Did you mean '" ++ mostSimilarSettingName ++ "'?" ]

                                                            _ ->
                                                                []
                                                in
                                                [ [ "Unknown setting name '" ++ settingName ++ "'." ]
                                                , pointOutSimilarSettingNameLines
                                                , [ "Here is a list of supported settings names: "
                                                        ++ (namedSettings |> Dict.keys |> List.map (String.Extra.surround "'") |> String.join ", ")
                                                  ]
                                                ]
                                                    |> List.concat
                                                    |> String.join "\n"
                                                    |> Err

                                            Just parseFunction ->
                                                parseFunction assignedValue
                                                    |> Result.mapError (\parseError -> "Failed to parse value for setting '" ++ settingName ++ "': " ++ parseError)

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
            (\assignmentFunctions ->
                assignmentFunctions
                    |> List.foldl (\assignmentFunction previousSettings -> assignmentFunction previousSettings)
                        defaultSettings
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

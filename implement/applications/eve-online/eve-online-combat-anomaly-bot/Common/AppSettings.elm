module Common.AppSettings exposing (..)

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
    "I received an app-settings string that is not empty, but I only accept an empty app-settings string. I am not programmed to support any app settings. Maybe there is another app which better matches your use case?"


valueTypeYesOrNo : (YesOrNo -> appSettings -> appSettings) -> SettingValueType appSettings
valueTypeYesOrNo =
    listAllSupportedValues { supportedValues = [ ( "yes", Yes ), ( "no", No ) ], ignoreCase = True }


valueTypeInteger : (Int -> appSettings -> appSettings) -> SettingValueType appSettings
valueTypeInteger integrateSettingValue =
    \settingValueAsString ->
        case settingValueAsString |> String.toInt of
            Nothing ->
                Err ("Failed to parse '" ++ settingValueAsString ++ "' as integer.")

            Just int ->
                Ok (integrateSettingValue int)


valueTypeString : (String -> appSettings -> appSettings) -> SettingValueType appSettings
valueTypeString integrateSettingValue =
    integrateSettingValue >> Ok


parseAllowOnlyEmpty : appSettings -> String -> Result String appSettings
parseAllowOnlyEmpty appSettings appSettingsString =
    if appSettingsString |> String.isEmpty then
        Ok appSettings

    else
        Err messageOnlyAcceptEmptyAppSettings


parseSimpleCommaSeparatedListOfAssignments : Dict.Dict String (SettingValueType appSettings) -> appSettings -> String -> Result String appSettings
parseSimpleCommaSeparatedListOfAssignments =
    parseSimpleListOfAssignments { assignmentsSeparators = [ "," ] }


parseSimpleListOfAssignments : { assignmentsSeparators : List String } -> Dict.Dict String (SettingValueType appSettings) -> appSettings -> String -> Result String appSettings
parseSimpleListOfAssignments { assignmentsSeparators } namedSettings defaultSettings settingsString =
    let
        assignments =
            assignmentsSeparators
                |> List.foldl (\assignmentSeparator -> List.concatMap (String.split assignmentSeparator))
                    [ settingsString ]

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
                                case assignment |> String.split "=" |> List.map String.trim of
                                    [ settingName, assignedValue ] ->
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

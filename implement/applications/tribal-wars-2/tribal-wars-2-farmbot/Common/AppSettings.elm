module Common.AppSettings exposing (..)

import Dict
import Result.Extra


type SettingValueType appSettings
    = ValueTypeInteger (Int -> appSettings -> appSettings)
    | ValueTypeString (String -> appSettings -> appSettings)
    | ValueTypeCustom (String -> Result String (appSettings -> appSettings))


parseAllowOnlyEmpty : appSettings -> String -> Result String appSettings
parseAllowOnlyEmpty appSettings appSettingsString =
    if appSettingsString |> String.isEmpty then
        Ok appSettings

    else
        Err "I received an app-settings string that is not empty, but I only accept an empty app-settings string. I am not programmed to support any app settings. Maybe there is another app which better matches your use case?"


parseSimpleCommaSeparatedList : Dict.Dict String (SettingValueType appSettings) -> appSettings -> String -> Result String appSettings
parseSimpleCommaSeparatedList namedSettings defaultSettings settingsString =
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
                                case namedSettings |> Dict.get settingName of
                                    Nothing ->
                                        Err ("Unknown setting name '" ++ settingName ++ "'.")

                                    Just parseFunction ->
                                        parseSettingValueFromString parseFunction assignedValue
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
                        defaultSettings
            )


parseSettingValueFromString : SettingValueType appSettings -> String -> Result String (appSettings -> appSettings)
parseSettingValueFromString valueType settingValueAsString =
    case valueType of
        ValueTypeInteger integrateInt ->
            case settingValueAsString |> String.toInt of
                Nothing ->
                    Err ("Failed to parse '" ++ settingValueAsString ++ "' as integer.")

                Just int ->
                    Ok (integrateInt int)

        ValueTypeString integrateString ->
            Ok (integrateString settingValueAsString)

        ValueTypeCustom custom ->
            custom settingValueAsString

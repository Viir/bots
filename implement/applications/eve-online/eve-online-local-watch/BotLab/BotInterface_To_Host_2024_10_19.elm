module BotLab.BotInterface_To_Host_2024_10_19 exposing (..)

{-| This module contains types for the interface between a bot and the botlab client.
The structures in these types reflect the standard interface for player agents to observe their environment and act in their environment.
The interface allows both bots and humans to take the role of the player agent.

To learn more about the common bot interface, see <https://to.botlab.org/guide/common-bot-interface>

-}


type alias BotConfig state =
    { init : state
    , processEvent : BotEvent -> state -> ( state, BotEventResponse )
    }


type alias BotEvent =
    { timeInMilliseconds : Int
    , eventAtTime : BotEventAtTime
    }


type BotEventAtTime
    = TimeArrivedEvent
    | BotSettingsChangedEvent String
    | SessionDurationPlannedEvent { timeInMilliseconds : Int }
    | TaskCompletedEvent CompletedTaskStructure


type BotEventResponse
    = ContinueSession ContinueSessionStructure
    | FinishSession FinishSessionStructure


type alias CompletedTaskStructure =
    { taskId : String
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = CreateVolatileProcessResponse (Result CreateVolatileProcessErrorStructure CreateVolatileProcessComplete)
    | RequestToVolatileProcessResponse (Result RequestToVolatileProcessError RequestToVolatileProcessComplete)
    | OpenWindowResponse (Result String OpenWindowSuccess)
    | InvokeMethodOnWindowResponse String (Result InvokeMethodOnWindowError InvokeMethodOnWindowResult)
    | RandomBytesResponse (List Int)
    | WindowsInputResponse WindowsInputResponseStruct
    | CompleteWithoutResult


type alias CreateVolatileProcessErrorStructure =
    { exceptionToString : String
    }


type alias CreateVolatileProcessComplete =
    { processId : String }


type RequestToVolatileProcessError
    = ProcessNotFound
    | FailedToAcquireInputFocus


type alias RequestToVolatileProcessComplete =
    { exceptionToString : Maybe String
    , returnValueToString : Maybe String
    , durationInMilliseconds : Int
    , acquireInputFocusDurationMilliseconds : Int
    }


type alias ReleaseVolatileProcessStructure =
    { processId : String }


type alias ContinueSessionStructure =
    { statusText : String
    , startTasks : List StartTaskStructure
    , notifyWhenArrivedAtTime : Maybe { timeInMilliseconds : Int }
    }


type alias FinishSessionStructure =
    { statusText : String
    }


{-| Tasks can yield some result to return to the bot. That is why we use the identifier.
-}
type alias StartTaskStructure =
    { taskId : String
    , task : Task
    }


type Task
    = CreateVolatileProcess CreateVolatileProcessStructure
    | RequestToVolatileProcess RequestToVolatileProcessConsideringInputFocusStructure
    | ReleaseVolatileProcess ReleaseVolatileProcessStructure
    | OpenWindowRequest OpenWindowRequestStruct
    | InvokeMethodOnWindowRequest String MethodOnWindow
    | WindowsInputRequest (List WindowsInputSequenceItem)
    | RandomBytesRequest Int


type MethodOnWindow
    = CloseWindowMethod
    | ChromeDevToolsProtocolRuntimeEvaluateMethod ChromeDevToolsProtocolRuntimeEvaluateParams
    | SetZoomFactorOnWebViewMethod SetZoomFactorOnWebViewMethodParams
    | ReadFromWindowMethod


type InvokeMethodOnWindowError
    = WindowNotFoundError { windowsIds : List String }
    | MethodNotAvailableError
    | ReadFromWindowError String


type InvokeMethodOnWindowResult
    = ChromeDevToolsProtocolRuntimeEvaluateMethodResult (Result String ChromeDevToolsProtocolRuntimeEvaluateMethodSuccess)
    | ReadFromWindowMethodResult ReadFromWindowCompleteStruct
    | InvokeMethodOnWindowResultWithoutValue


type alias ReadFromWindowCompleteStruct =
    { readingId : String

    -- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowtexta
    , windowText : String

    -- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect
    , windowRect : WinApiRectStruct

    -- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclientrect
    , clientRect : WinApiRectStruct

    -- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-clienttoscreen
    , clientRectLeftUpperToScreen : WinApiPointStruct
    , windowDpi : Int
    , imageData : ImageDataFromReadingCompleteStruct
    }


type alias ImageDataFromReadingCompleteStruct =
    { screenshotCrops_original : List ImageCrop
    , screenshotCrops_binned_2x2 : List ImageCrop
    , screenshotCrops_binned_4x4 : List ImageCrop
    }


type alias ImageCrop =
    { offset : WinApiPointStruct
    , widthPixels : Int
    , pixelsString : String
    }


type alias ChromeDevToolsProtocolRuntimeEvaluateParams =
    { expression : String
    , awaitPromise : Bool
    }


type alias SetZoomFactorOnWebViewMethodParams =
    { zoomFactorMikro : Int
    }


type alias ChromeDevToolsProtocolRuntimeEvaluateMethodSuccess =
    { returnValueJsonSerialized : String
    }


type alias OpenWindowRequestStruct =
    { windowType : Maybe WindowType
    , userGuide : String
    }


type alias OpenWindowSuccess =
    { windowId : String
    , osProcessId : String
    }


type WindowType
    = WebBrowserWindow WebBrowserWindowParameters


{-| Use 'Nothing' to inherit the defaults from the environment.
-}
type alias WebBrowserWindowParameters =
    { -- https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.winforms.corewebview2creationproperties.userdatafolder?view=webview2-dotnet-1.0.1343.22
      userDataFolder : Maybe String

    -- https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2environmentoptions.language?view=webview2-dotnet-1.0.1343.22
    , language : Maybe String

    -- https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.winforms.corewebview2creationproperties.isinprivatemodeenabled?view=webview2-dotnet-1.0.1343.22
    , isInPrivateModeEnabled : Maybe Bool

    -- https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2environmentoptions.additionalbrowserarguments?view=webview2-dotnet-1.0.1343.22
    , additionalBrowserArguments : String
    }


type alias CreateVolatileProcessStructure =
    { programCode : String }


type RequestToVolatileProcessConsideringInputFocusStructure
    = RequestRequiringInputFocus RequestToVolatileProcessRequiringInputFocusStructure
    | RequestNotRequiringInputFocus RequestToVolatileProcessStructure


type alias RequestToVolatileProcessRequiringInputFocusStructure =
    { request : RequestToVolatileProcessStructure
    , acquireInputFocus : AcquireInputFocusStructure
    }


type alias RequestToVolatileProcessStructure =
    { processId : String
    , request : String
    }


type alias AcquireInputFocusStructure =
    { maximumDelayMilliseconds : Int
    }


{-| <https://learn.microsoft.com/en-us/windows/win32/api/windef/ns-windef-rect>
-}
type alias WinApiRectStruct =
    { left : Int
    , top : Int
    , right : Int
    , bottom : Int
    }


{-| <https://learn.microsoft.com/en-us/windows/win32/api/windef/ns-windef-point>
-}
type alias WinApiPointStruct =
    { x : Int
    , y : Int
    }



{-

   [System.Text.Json.Serialization.JsonConverter(typeof(Pine.Json.JsonConverterForChoiceType))]
   public abstract record WindowsInputSequenceItem
   {
       public record WaitMilliseconds(
           int Milliseconds)
           : WindowsInputSequenceItem;

       public record KeyDown(
           int KeyCode,
           bool Extended)
           : WindowsInputSequenceItem;

       public record KeyUp(
           int KeyCode,
           bool Extended)
           : WindowsInputSequenceItem;

       public record MouseMoveAbsolute(
           int X,
           int Y)
           : WindowsInputSequenceItem;

       public record MouseMoveRelative(
           int X,
           int Y)
           : WindowsInputSequenceItem;

       public record ButtonDown(
           int Button)
           : WindowsInputSequenceItem;

       public record ButtonUp(
           int Button)
           : WindowsInputSequenceItem;

       public record ButtonScroll(
           int Button,
           int Direction,
           int Offset)
           : WindowsInputSequenceItem;

       public record CharacterDown(
           int Character)
           : WindowsInputSequenceItem;

       public record CharacterUp(
           int Character)
           : WindowsInputSequenceItem;
   }
-}


type WindowsInputSequenceItem
    = WaitMilliseconds Int
    | KeyDown Int Bool
    | KeyUp Int Bool
    | MouseMoveAbsolute Int Int
    | MouseMoveRelative Int Int
    | ButtonDown Int
    | ButtonUp Int
    | ButtonScroll Int Int Int
    | CharacterDown Int
    | CharacterUp Int
    | BringWindowToForeground String
    | AbortIfWindowNotInForeground String


type alias WindowsInputResponseStruct =
    { completedStepsCount : Int
    , abortedStepsCount : Int
    , totalTimeMilliseconds : Int
    , errorMessages : List String
    }

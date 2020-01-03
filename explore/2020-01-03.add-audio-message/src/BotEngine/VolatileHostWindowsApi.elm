module BotEngine.VolatileHostWindowsApi exposing (
    RequestToVolatileHost(..)
    , ResponseFromVolatileHost(..)
    , ReadFileContentResultStructure(..)
    , TaskOnWindowStructure(..)
    , Location2d
    , MouseButton(..)
    , KeyboardKey(..)
    , WindowId
    , buildScriptToGetResponseFromVolatileHost
    , deserializeResponseFromVolatileHost
    , setupScript)


import Json.Decode
import Json.Encode


type RequestToVolatileHost
    = GetForegroundWindow
    | GetWindowText WindowId
    | TaskOnWindow TaskOnIdentifiedWindowStructure
    | PlayAudioFromWavFile String


type ResponseFromVolatileHost
    = GetForegroundWindowResult WindowId
    | GetWindowTextResult String
    | TakeScreenshotResult TakeScreenshotResultStructure
    | NoReturnValue


type alias TaskOnIdentifiedWindowStructure =
    { windowId : WindowId
    , task : TaskOnWindowStructure
    }


type alias TakeScreenshotResultStructure =
    { pixels : List (List PixelValue) }


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


type ReadFileContentResultStructure
    = DidNotFindFileAtSpecifiedPath
    | ExceptionAsString String
    | FileContentAsBase64 String


type WindowId
    = WindowHandleFromInt Int


type TaskOnWindowStructure
    = BringWindowToForeground
    | MoveMouseToLocation Location2d
    | MouseButtonDown MouseButton
    | MouseButtonUp MouseButton
    | KeyboardKeyDown KeyboardKey
    | KeyboardKeyUp KeyboardKey
    | TakeScreenshot


type alias Location2d =
    { x : Int, y : Int }


type KeyboardKey
    = KeyboardKeyFromVirtualKeyCode Int


type MouseButton
    = MouseButtonLeft
    | MouseButtonRight


buildScriptToGetResponseFromVolatileHost : RequestToVolatileHost -> String
buildScriptToGetResponseFromVolatileHost request =
    "serialRequest("
        ++ (request
                |> encodeRequestToVolatileHost
                |> Json.Encode.encode 0
                |> Json.Encode.string
                |> Json.Encode.encode 0
           )
        ++ ")"


encodeRequestToVolatileHost : RequestToVolatileHost -> Json.Encode.Value
encodeRequestToVolatileHost request =
    case request of
        GetForegroundWindow ->
            Json.Encode.object [ ( "GetForegroundWindow", Json.Encode.object [ ] ) ]
        GetWindowText getWindowText ->
            Json.Encode.object [ ( "GetWindowText", getWindowText |> encodeWindowId ) ]
        TaskOnWindow taskOnWindow ->
            Json.Encode.object [ ( "TaskOnWindow", taskOnWindow |> encodeTaskOnIdentifiedWindowStructure ) ]
        PlayAudioFromWavFile file ->
            Json.Encode.object [ ( "PlayAudioFromWavFile", file |> Json.Encode.string ) ]


deserializeResponseFromVolatileHost : String -> Result Json.Decode.Error ResponseFromVolatileHost
deserializeResponseFromVolatileHost =
    Json.Decode.decodeString decodeResponseFromVolatileHost


decodeResponseFromVolatileHost : Json.Decode.Decoder ResponseFromVolatileHost
decodeResponseFromVolatileHost =
    Json.Decode.oneOf
        [ Json.Decode.field "GetForegroundWindowResult" decodeWindowId
            |> Json.Decode.map GetForegroundWindowResult
        , Json.Decode.field "GetWindowTextResult" Json.Decode.string
            |> Json.Decode.map GetWindowTextResult
        , Json.Decode.field "TakeScreenshotResult" jsonDecodeTakeScreenshotResult
            |> Json.Decode.map TakeScreenshotResult
        , Json.Decode.field "NoReturnValue" (jsonDecodeSucceedWhenNotNull NoReturnValue)
        ]


jsonDecodeTakeScreenshotResult : Json.Decode.Decoder TakeScreenshotResultStructure
jsonDecodeTakeScreenshotResult =
    Json.Decode.field "pixels" (Json.Decode.list (Json.Decode.list jsonDecodePixelValue))
        |> Json.Decode.map TakeScreenshotResultStructure


jsonDecodePixelValue : Json.Decode.Decoder PixelValue
jsonDecodePixelValue =
    Json.Decode.int
        |> Json.Decode.map
            (\asInt ->
                { red = asInt // (256 * 256)
                , green = asInt // 256 |> modBy 256
                , blue = asInt |> modBy 256
                }
            )


encodeWindowId : WindowId -> Json.Encode.Value
encodeWindowId windowId =
    case windowId of
    WindowHandleFromInt windowHandleFromInt ->
        [("WindowHandleFromInt", windowHandleFromInt |> Json.Encode.int )]
            |> Json.Encode.object


decodeWindowId : Json.Decode.Decoder WindowId
decodeWindowId =
    Json.Decode.oneOf
        [ Json.Decode.field "WindowHandleFromInt" Json.Decode.int
            |> Json.Decode.map WindowHandleFromInt
        ]


encodeTaskOnIdentifiedWindowStructure : TaskOnIdentifiedWindowStructure -> Json.Encode.Value
encodeTaskOnIdentifiedWindowStructure taskOnIdentifiedWindow =
    [ ( "windowId", taskOnIdentifiedWindow.windowId |> encodeWindowId )
    , ( "task", taskOnIdentifiedWindow.task |> encodeTaskOnWindowStructure )
    ]
        |> Json.Encode.object


encodeTaskOnWindowStructure : TaskOnWindowStructure -> Json.Encode.Value
encodeTaskOnWindowStructure taskOnWindow =
    case taskOnWindow of
    BringWindowToForeground ->
        [("BringWindowToForeground", [] |> Json.Encode.object )]
            |> Json.Encode.object
    MoveMouseToLocation moveMouseToLocation ->
        [("MoveMouseToLocation", moveMouseToLocation |> jsonEncodeLocation2d )]
            |> Json.Encode.object
    MouseButtonDown mouseButtonDown ->
        [("MouseButtonDown", mouseButtonDown |> jsonEncodeMouseButton )]
            |> Json.Encode.object
    MouseButtonUp mouseButtonUp ->
        [("MouseButtonUp", mouseButtonUp |> jsonEncodeMouseButton )]
            |> Json.Encode.object
    KeyboardKeyDown keyboardKeyDown ->
        [("KeyboardKeyDown", keyboardKeyDown |> jsonEncodeKeyboardKey )]
            |> Json.Encode.object
    KeyboardKeyUp keyboardKeyUp ->
        [("KeyboardKeyUp", keyboardKeyUp |> jsonEncodeKeyboardKey )]
            |> Json.Encode.object
    TakeScreenshot ->
        [("TakeScreenshot", [] |> Json.Encode.object )]
            |> Json.Encode.object


jsonEncodeLocation2d : Location2d -> Json.Encode.Value
jsonEncodeLocation2d location =
    [ ( "x", location.x |> Json.Encode.int )
    , ( "y", location.y |> Json.Encode.int )
    ]
        |> Json.Encode.object


jsonEncodeMouseButton : MouseButton -> Json.Encode.Value
jsonEncodeMouseButton mouseButton =
    case mouseButton of
        MouseButtonLeft ->
            [ ( "MouseButtonLeft", [] |> Json.Encode.object ) ] |> Json.Encode.object

        MouseButtonRight ->
            [ ( "MouseButtonRight", [] |> Json.Encode.object ) ] |> Json.Encode.object


jsonEncodeKeyboardKey : KeyboardKey -> Json.Encode.Value
jsonEncodeKeyboardKey keyboardKey =
    case keyboardKey of
        KeyboardKeyFromVirtualKeyCode keyCode->
            [ ( "KeyboardKeyFromVirtualKeyCode", keyCode |> Json.Encode.int ) ] |> Json.Encode.object


jsonDecodeSucceedWhenNotNull : a -> Json.Decode.Decoder a
jsonDecodeSucceedWhenNotNull valueIfNotNull =
    Json.Decode.value
        |> Json.Decode.andThen
            (\asValue ->
                if asValue == Json.Encode.null then
                    Json.Decode.fail "Is null."

                else
                    Json.Decode.succeed valueIfNotNull
            )


setupScript : String
setupScript =
    """
#r "mscorlib"
#r "netstandard"
#r "System"
#r "System.Collections.Immutable"
#r "System.ComponentModel.Primitives"
#r "System.IO.Compression"
#r "System.Net"
#r "System.Net.WebClient"
#r "System.Private.Uri"
#r "System.Linq"
#r "System.Security.Cryptography.Algorithms"
#r "System.Security.Cryptography.Primitives"

// "Newtonsoft.Json"
#r "sha256:B9B4E633EA6C728BAD5F7CBBEF7F8B842F7E10181731DBE5EC3CD995A6F60287"

//  "WindowsInput"
#r "sha256:81110D44256397F0F3C572A20CA94BB4C669E5DE89F9348ABAD263FBD81C54B9"

//  "System.Drawing.Common"
#r "sha256:C5333AA60281006DFCFBBC0BC04C217C581EFF886890565E994900FB60448B02"

//  "System.Drawing.Primitives"
#r "sha256:CA24032E6D39C44A01D316498E18FE9A568D59C6009842029BC129AA6B989BCD"

//  https://www.nuget.org/packages/NAudio/1.9.0
#r "sha256:161207925F0A5BC0652649F1F25B5CCB7270B2C51E0782FD5308158596BF7C1A"


using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Security.Cryptography;
using System.Runtime.InteropServices;



public class Request
{
    public TaskOnIdentifiedWindowStructure TaskOnWindow;

    public object GetForegroundWindow;

    public WindowId GetWindowText;

    public string PlayAudioFromWavFile;

    public class TaskOnIdentifiedWindowStructure
    {
        public WindowId windowId;

        public TaskOnWindowStructure task;
    }

    public class TaskOnWindowStructure
    {
        public object BringWindowToForeground;

        public Location2d MoveMouseToLocation;

        public MouseButton MouseButtonDown;

        public MouseButton MouseButtonUp;

        public KeyboardKey KeyboardKeyDown;

        public KeyboardKey KeyboardKeyUp;

        public object TakeScreenshot;
    }

    public class Location2d
    {
        public int x, y;
    }

    public class MouseButton
    {
        public object MouseButtonLeft;
        public object MouseButtonRight;
    }

    public class KeyboardKey
    {
        public int KeyboardKeyFromVirtualKeyCode;
    }
}

public class Response
{
    public WindowId GetForegroundWindowResult;

    public object NoReturnValue;

    public string GetWindowTextResult;

    public TakeScreenshotResultStructure TakeScreenshotResult;

    public class TakeScreenshotResultStructure
    {
        public int[][] pixels;
    }
}


public class WindowId
{
    public long WindowHandleFromInt;
}


byte[] SHA256FromByteArray(byte[] array)
{
    using (var hasher = new SHA256Managed())
        return hasher.ComputeHash(buffer: array);
}

string ToStringBase16(byte[] array) => BitConverter.ToString(array).Replace("-", "");


string serialRequest(string serializedRequest)
{
    var requestStructure = Newtonsoft.Json.JsonConvert.DeserializeObject<Request>(serializedRequest);

    var response = request(requestStructure);

    return SerializeToJsonForBot(response);
}

public Response request(Request request)
{
    SetProcessDPIAware();

    string GetWindowText(WindowId windowId)
    {
        var windowHandle = new IntPtr(windowId.WindowHandleFromInt);

        var windowTitle = new System.Text.StringBuilder(capacity: 256);

        WinApi.GetWindowText(windowHandle, windowTitle, windowTitle.Capacity);

        return windowTitle.ToString();
    }

    if (request.GetForegroundWindow != null)
    {
        return new Response
        {
            GetForegroundWindowResult = GetForegroundWindow()
        };
    }

    if (request.GetWindowText != null)
    {
        return new Response
        {
            GetWindowTextResult = GetWindowText(request.GetWindowText),
        };
    }

    if (request.TaskOnWindow != null)
    {
        return performTaskOnWindow(request.TaskOnWindow);
    }

    if (request.PlayAudioFromWavFile != null)
    {
        var file = request.PlayAudioFromWavFile;

        //  https://stackoverflow.com/questions/42845506/how-to-play-a-sound-in-netcore/54670829#54670829

        using (var waveOut = new NAudio.Wave.WaveOutEvent())
            using (var wavReader = new NAudio.Wave.WaveFileReader(file))
            {
                waveOut.Init(wavReader);
                waveOut.Play();
                System.Threading.Thread.Sleep(1000);
            }

        return new Response { NoReturnValue = new object() };
    }

    throw new Exception("Unexpected request value.");
}

public WindowId GetForegroundWindow() =>
    new WindowId { WindowHandleFromInt = WinApi.GetForegroundWindow().ToInt64() };

Response performTaskOnWindow(Request.TaskOnIdentifiedWindowStructure taskOnIdentifiedWindow)
{
    var windowHandle = new IntPtr(taskOnIdentifiedWindow.windowId.WindowHandleFromInt);

    var inputSimulator = new WindowsInput.InputSimulator();

    var task = taskOnIdentifiedWindow.task;

    if (task.BringWindowToForeground != null)
    {
        WinApi.SetForegroundWindow(windowHandle);
        WinApi.ShowWindow(windowHandle, WinApi.SW_RESTORE);
        return new Response { NoReturnValue = new object() };
    }

    if (task.MoveMouseToLocation != null)
    {
        var windowRect = new WinApi.Rect();
        if (WinApi.GetWindowRect(windowHandle, ref windowRect) == IntPtr.Zero)
            throw new Exception("GetWindowRect failed");

        WinApi.SetCursorPos(
            task.MoveMouseToLocation.x + windowRect.left,
            task.MoveMouseToLocation.y + windowRect.top);

        return new Response { NoReturnValue = new object() };
    }

    if (task.MouseButtonDown != null)
    {
        if (task.MouseButtonDown.MouseButtonLeft != null)
            inputSimulator.Mouse.LeftButtonDown();

        if (task.MouseButtonDown.MouseButtonRight != null)
            inputSimulator.Mouse.RightButtonDown();

        return new Response { NoReturnValue = new object() };
    }

    if (task.MouseButtonUp != null)
    {
        if (task.MouseButtonUp.MouseButtonLeft != null)
            inputSimulator.Mouse.LeftButtonUp();

        if (task.MouseButtonUp.MouseButtonRight != null)
            inputSimulator.Mouse.RightButtonUp();

        return new Response { NoReturnValue = new object() };
    }

    if (task.KeyboardKeyDown != null)
    {
        inputSimulator.Keyboard.KeyDown((WindowsInput.Native.VirtualKeyCode)task.KeyboardKeyDown.KeyboardKeyFromVirtualKeyCode);
        return new Response { NoReturnValue = new object() };
    }

    if (task.KeyboardKeyUp != null)
    {
        inputSimulator.Keyboard.KeyUp((WindowsInput.Native.VirtualKeyCode)task.KeyboardKeyUp.KeyboardKeyFromVirtualKeyCode);
        return new Response { NoReturnValue = new object() };
    }

    if (task.TakeScreenshot != null)
    {
        return new Response
        {
            TakeScreenshotResult = new Response.TakeScreenshotResultStructure
            {
                pixels = GetScreenshotOfWindowAsPixelsValues(windowHandle)
            }
        };
    }

    throw new Exception("Unexpected task in request: " + task);
}

void SetProcessDPIAware()
{
    //  https://www.google.com/search?q=GetWindowRect+dpi
    //  https://github.com/dotnet/wpf/issues/859
    //  https://github.com/dotnet/winforms/issues/135
    WinApi.SetProcessDPIAware();
}

public byte[] GetScreenshotOfWindowAsImageFileBMP(IntPtr windowHandle)
{
    var screenshotAsBitmap = GetScreenshotOfWindowAsBitmap(windowHandle);

    if (screenshotAsBitmap == null)
        return null;

    using (var stream = new System.IO.MemoryStream())
    {
        screenshotAsBitmap.Save(stream, format: System.Drawing.Imaging.ImageFormat.Bmp);
        return stream.ToArray();
    }
}

public int[][] GetScreenshotOfWindowAsPixelsValues(IntPtr windowHandle)
{
    var screenshotAsBitmap = GetScreenshotOfWindowAsBitmap(windowHandle);

    if (screenshotAsBitmap == null)
        return null;

    var bitmapData = screenshotAsBitmap.LockBits(
        new System.Drawing.Rectangle(0, 0, screenshotAsBitmap.Width, screenshotAsBitmap.Height),
        System.Drawing.Imaging.ImageLockMode.ReadOnly,
        System.Drawing.Imaging.PixelFormat.Format24bppRgb);

    int byteCount = bitmapData.Stride * screenshotAsBitmap.Height;
    byte[] pixelsArray = new byte[byteCount];
    IntPtr ptrFirstPixel = bitmapData.Scan0;
    Marshal.Copy(ptrFirstPixel, pixelsArray, 0, pixelsArray.Length);

    screenshotAsBitmap.UnlockBits(bitmapData);

    var pixels = new int[screenshotAsBitmap.Height][];

    for (var rowIndex = 0; rowIndex < screenshotAsBitmap.Height; ++rowIndex)
    {
        var rowPixelValues = new int[screenshotAsBitmap.Width];

        for (var columnIndex = 0; columnIndex < screenshotAsBitmap.Width; ++columnIndex)
        {
            var pixelBeginInArray = bitmapData.Stride * rowIndex + columnIndex * 3;

            var red = pixelsArray[pixelBeginInArray + 2];
            var green = pixelsArray[pixelBeginInArray + 1];
            var blue = pixelsArray[pixelBeginInArray + 0];

            rowPixelValues[columnIndex] = (red << 16) | (green << 8) | blue;
        }

        pixels[rowIndex] = rowPixelValues;
    }

    return pixels;
}

public System.Drawing.Bitmap GetScreenshotOfWindowAsBitmap(IntPtr windowHandle)
{
    SetProcessDPIAware();

    var windowRect = new WinApi.Rect();
    if (WinApi.GetWindowRect(windowHandle, ref windowRect) == IntPtr.Zero)
        return null;

    int width = windowRect.right - windowRect.left;
    int height = windowRect.bottom - windowRect.top;

    var asBitmap = new System.Drawing.Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format24bppRgb);

    System.Drawing.Graphics.FromImage(asBitmap).CopyFromScreen(
        windowRect.left,
        windowRect.top,
        0,
        0,
        new System.Drawing.Size(width, height),
        System.Drawing.CopyPixelOperation.SourceCopy);

    return asBitmap;
}


static public class WinApi
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    public enum MouseButton
    {
        Left = 0,
        Middle = 1,
        Right = 2,
    }

    [DllImport("user32.dll")]
    static public extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    static public extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll", SetLastError = true)]
    static public extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    static public extern int SetForegroundWindow(IntPtr hWnd);

    public const int SW_RESTORE = 9;

    [DllImport("user32.dll")]
    static public extern IntPtr ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    static public extern IntPtr GetWindowRect(IntPtr hWnd, ref Rect rect);

    [DllImport("user32.dll", SetLastError = false)]
    static public extern IntPtr GetDesktopWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static public extern bool SetCursorPos(int x, int y);
}

string SerializeToJsonForBot<T>(T value) =>
    Newtonsoft.Json.JsonConvert.SerializeObject(
        value,
        //  Use settings to get same derivation as at https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L91-L97
        new Newtonsoft.Json.JsonSerializerSettings
        {
            //  Bot code does not expect properties with null values, see https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
            NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,

            //	https://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
            ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
        });

"Setup Completed"
"""

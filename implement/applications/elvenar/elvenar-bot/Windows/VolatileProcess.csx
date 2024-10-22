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

//  "System.Drawing.Common"
#r "sha256:C5333AA60281006DFCFBBC0BC04C217C581EFF886890565E994900FB60448B02"

//  "System.Drawing.Primitives"
#r "sha256:CA24032E6D39C44A01D316498E18FE9A568D59C6009842029BC129AA6B989BCD"

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Security.Cryptography;
using System.Runtime.InteropServices;


int readingFromGameCount = 0;
var generalStopwatch = System.Diagnostics.Stopwatch.StartNew();

var readingFromGameHistory = new Queue<ReadingFromGameClient>();


public class Request
{
    public object ListWindowsRequest;

    public TaskOnIdentifiedWindowRequestStruct TaskOnWindowRequest;

    public GetImageDataFromReadingRequestStruct? GetImageDataFromReadingRequest;

    public object GetForegroundWindow;

    public string GetWindowText;

    public GetImageDataFromReadingRequestStruct? GetImageDataFromReading;

    public class TaskOnIdentifiedWindowRequestStruct
    {
        public string windowId;

        public TaskOnWindowRequestStruct task;
    }

    public class TaskOnWindowRequestStruct
    {
        public object BringWindowToForeground;

        public ReadFromWindowStructure ReadFromWindowRequest;
    }

    public class ReadFromWindowStructure
    {
        public GetImageDataFromReadingStructure getImageData;
    }

    public struct GetImageDataFromReadingRequestStruct
    {
        public string readingId;

        public GetImageDataFromReadingStructure getImageData;
    }

    public struct GetImageDataFromReadingStructure
    {
        public Rect2d[] crops_1x1_r8g8b8;

        public Rect2d[] crops_2x2_r8g8b8;
    }
}

public class Response
{
    public WindowSummaryStruct[] ListWindowsResponse;

    public TaskOnIdentifiedWindowResponseStruct TaskOnWindowResponse;

    public object ReadingNotFound;

    public GetImageDataFromReadingCompleteStruct? GetImageDataFromReadingComplete;

    public object NoReturnValue;

    public string GetWindowTextResult;

    public string GetForegroundWindowResult;

    public struct WindowSummaryStruct
    {
        public string windowId;

        public string windowTitle;

        public int windowZIndex;
    }

    public class TaskOnIdentifiedWindowResponseStruct
    {
        public string windowId;

        public TaskOnWindowResponseStruct result;
    }

    public class TaskOnWindowResponseStruct
    {
        public object WindowNotFound;

        public ReadFromWindowCompleteStruct ReadFromWindowComplete;
    }

    public class ReadFromWindowCompleteStruct
    {
        public string readingId;

        public Location2d windowSize;

        public Location2d windowClientRectOffset;

        public Location2d windowClientAreaSize;

        public GetImageDataFromReadingResultStructure imageData;
    }

    public struct GetImageDataFromReadingCompleteStruct
    {
        public string windowId;

        public string readingId;

        public GetImageDataFromReadingResultStructure imageData;
    }

    public struct GetImageDataFromReadingResultStructure
    {
        public ImageCropRGB[] crops_1x1_r8g8b8;

        public IReadOnlyList<ImageCropRGB> crops_2x2_r8g8b8;
    }
}


struct ReadingFromGameClient
{
    public string windowId = null;

    public string readingId = null;

    public ReadOnlyMemory<int>[] pixels_1x1_R8G8B8 = null;

    private readonly IDictionary<Location2d, ReadOnlyMemory<int>[]> pixels_2x2_R8G8B8_by_offset = new Dictionary<Location2d, ReadOnlyMemory<int>[]>();

    public ReadingFromGameClient() { }

    public ReadOnlyMemory<int>[] Pixels_2x2_R8G8B8_by_offset(Location2d offset)
    {
        if (pixels_2x2_R8G8B8_by_offset.TryGetValue(offset, out var pixels))
        {
            return pixels;
        }

        pixels = Build_pixels_2x2_R8G8B8_by_offset(offset);

        pixels_2x2_R8G8B8_by_offset[offset] = pixels;

        return pixels;
    }

    public ReadOnlyMemory<int>[] Build_pixels_2x2_R8G8B8_by_offset(Location2d offset)
    {
        var offsetRows = pixels_1x1_R8G8B8.Skip(offset.y).ToList();

        var pixels_2x2_R8G8B8 =
            Enumerable.Range(0, offsetRows.Count / 2)
            .Select(rowIndex =>
            {
                var row0Pixels = offsetRows[rowIndex * 2];
                var row1Pixels = offsetRows[rowIndex * 2 + 1];

                var offsetRow0Pixels = row0Pixels.Slice(offset.x);
                var offsetRow1Pixels = row1Pixels.Slice(offset.x);

                var binnedRowLength = Math.Min(offsetRow0Pixels.Length, offsetRow1Pixels.Length) / 2;

                var binnedRow = new int[binnedRowLength];

                for (int x = 0; x < binnedRowLength; ++x)
                {
                    var p0 = offsetRow0Pixels.Span[x * 2];
                    var p1 = offsetRow0Pixels.Span[x * 2 + 1];
                    var p2 = offsetRow1Pixels.Span[x * 2];
                    var p3 = offsetRow1Pixels.Span[x * 2 + 1];

                    var r0 = (p0 >> 16) & 0xff;
                    var g0 = (p0 >> 8) & 0xff;
                    var b0 = p0 & 0xff;

                    var r1 = (p1 >> 16) & 0xff;
                    var g1 = (p1 >> 8) & 0xff;
                    var b1 = p1 & 0xff;

                    var r2 = (p2 >> 16) & 0xff;
                    var g2 = (p2 >> 8) & 0xff;
                    var b2 = p2 & 0xff;

                    var r3 = (p3 >> 16) & 0xff;
                    var g3 = (p3 >> 8) & 0xff;
                    var b3 = p3 & 0xff;

                    binnedRow[x] =
                        (((r0 + r1 + r2 + r3) / 4) << 16) |
                        (((g0 + g1 + g2 + g3) / 4) << 8) |
                        (((b0 + b1 + b2 + b3) / 4));
                }

                return (ReadOnlyMemory<int>)binnedRow;
            })
            .ToArray();

        return pixels_2x2_R8G8B8;
    }
}

public struct ImageCropRGB
{
    public Location2d offset;

    public int[][] pixels;
}

public struct Rect2d
{
    public int x, y, width, height;
}

public record struct Location2d(int x, int y);


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

    string GetWindowText(string windowId)
    {
        var windowHandle = new IntPtr(Int64.Parse(windowId));

        return GetWindowTextFromHandle(windowHandle);
    }

    if (request.ListWindowsRequest != null)
    {
        return new Response
        {
            ListWindowsResponse = ListWindowsSummaries(windowCountLimit: 4).ToArray(),
        };
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

    if (request.TaskOnWindowRequest != null)
    {
        return performTaskOnWindow(request.TaskOnWindowRequest);
    }

    if (request.GetImageDataFromReadingRequest?.readingId != null)
    {
        var historyEntry =
            readingFromGameHistory
            .Cast<ReadingFromGameClient?>()
            .FirstOrDefault(c => c?.readingId == request.GetImageDataFromReadingRequest?.readingId);

        if (historyEntry == null)
        {
            return new Response
            {
                ReadingNotFound = new object()
            };
        }

        return new Response
        {
            GetImageDataFromReadingComplete = new Response.GetImageDataFromReadingCompleteStruct
            {
                windowId = historyEntry.Value.windowId,
                readingId = request.GetImageDataFromReadingRequest?.readingId,
                imageData = CompileImageDataFromReadingResult(
                    request.GetImageDataFromReadingRequest.Value.getImageData, historyEntry.Value),
            }
        };
    }

    throw new Exception("Unexpected request value.");
}

public string GetForegroundWindow() =>
    WinApi.GetForegroundWindow().ToInt64().ToString();

Response performTaskOnWindow(
    Request.TaskOnIdentifiedWindowRequestStruct taskOnIdentifiedWindow)
{
    var windowHandle = new IntPtr(Int64.Parse(taskOnIdentifiedWindow.windowId));

    Response ResponseFromResultOnWindow(Response.TaskOnWindowResponseStruct resultOnWindow)
    {
        return new Response
        {
            TaskOnWindowResponse = new Response.TaskOnIdentifiedWindowResponseStruct
            {
                windowId = taskOnIdentifiedWindow.windowId,
                result = resultOnWindow
            }
        };
    }

    var windowRect = new WinApi.Rect();
    if (!WinApi.GetWindowRect(windowHandle, ref windowRect))
    {
        return ResponseFromResultOnWindow(
            new Response.TaskOnWindowResponseStruct
            {
                WindowNotFound = new object()
            });
    }

    var task = taskOnIdentifiedWindow.task;

    if (task.BringWindowToForeground != null)
    {
        WinApi.SetForegroundWindow(windowHandle);
        WinApi.ShowWindow(windowHandle, WinApi.SW_RESTORE);
        return new Response { NoReturnValue = new object() };
    }

    if (task.ReadFromWindowRequest != null)
    {
        var readingFromGameIndex = System.Threading.Interlocked.Increment(ref readingFromGameCount);

        var readingId = readingFromGameIndex.ToString("D6") + "-" + generalStopwatch.ElapsedMilliseconds;

        var pixels_1x1_R8G8B8 = GetScreenshotOfWindowAsPixelsValues_R8G8B8(windowHandle);

        var windowClientRect = new WinApi.Rect();
        WinApi.GetClientRect(windowHandle, ref windowClientRect);

        var clientRectOffsetFromScreen = new WinApi.Point(0, 0);
        WinApi.ClientToScreen(windowHandle, ref clientRectOffsetFromScreen);

        var windowSize =
            new Location2d
            {
                x = windowRect.right - windowRect.left,
                y = windowRect.bottom - windowRect.top
            };

        var windowClientRectOffset =
            new Location2d
            {
                x = clientRectOffsetFromScreen.x - windowRect.left,
                y = clientRectOffsetFromScreen.y - windowRect.top
            };

        var windowClientAreaSize =
            new Location2d
            {
                x = windowClientRect.right - windowClientRect.left,
                y = windowClientRect.bottom - windowClientRect.top
            };

        var historyEntry = new ReadingFromGameClient
        {
            windowId = taskOnIdentifiedWindow.windowId,
            readingId = readingId,
            pixels_1x1_R8G8B8 = pixels_1x1_R8G8B8,
        };

        readingFromGameHistory.Enqueue(historyEntry);

        while (4 < readingFromGameHistory.Count)
        {
            readingFromGameHistory.Dequeue();
        }

        var imageData = CompileImageDataFromReadingResult(task.ReadFromWindowRequest.getImageData, historyEntry);

        return ResponseFromResultOnWindow(
            new Response.TaskOnWindowResponseStruct
            {
                ReadFromWindowComplete = new Response.ReadFromWindowCompleteStruct
                {
                    readingId = readingId,
                    windowSize = windowSize,
                    windowClientRectOffset = windowClientRectOffset,
                    windowClientAreaSize = windowClientAreaSize,
                    imageData = imageData
                }
            });
    }

    throw new Exception("Unexpected task in request:\n" + Newtonsoft.Json.JsonConvert.SerializeObject(task));
}


System.Collections.Generic.IReadOnlyList<Response.WindowSummaryStruct> ListWindowsSummaries(int windowCountLimit)
{
    var windowHandlesInZOrder =
        WinApi.EnumerateWindowHandlesInZOrderStartingFromForegroundWindow()
        .Take(windowCountLimit)
        .ToList();

    int? zIndexFromWindowHandle(IntPtr windowHandleToSearch) =>
        windowHandlesInZOrder
        .Select((windowHandle, index) => (windowHandle, index: (int?)index))
        .FirstOrDefault(handleAndIndex => handleAndIndex.windowHandle == windowHandleToSearch)
        .index;

    var windows =
        windowHandlesInZOrder
        .Select(windowHandle =>
        {
            return new Response.WindowSummaryStruct
            {
                windowId = windowHandle.ToInt64().ToString(),
                windowTitle = GetWindowTextFromHandle(windowHandle),
                windowZIndex = zIndexFromWindowHandle(windowHandle) ?? 9999,
            };
        })
        .ToList();

    return windows;
}

string GetWindowTextFromHandle(IntPtr windowHandle)
{
    var windowTitle = new System.Text.StringBuilder(capacity: 256);

    WinApi.GetWindowText(windowHandle, windowTitle, windowTitle.Capacity);

    return windowTitle.ToString();
}

Response.GetImageDataFromReadingResultStructure CompileImageDataFromReadingResult(
    Request.GetImageDataFromReadingStructure request,
    ReadingFromGameClient historyEntry)
{
    ImageCropRGB[] crops_1x1_r8g8b8 = null;
    IReadOnlyList<ImageCropRGB> crops_2x2_r8g8b8 = null;

    if (historyEntry.pixels_1x1_R8G8B8 != null)
    {
        crops_1x1_r8g8b8 =
            request.crops_1x1_r8g8b8
            .Select(rect =>
            {
                var cropPixels = CopyRectangularCrop(historyEntry.pixels_1x1_R8G8B8, rect);

                return new ImageCropRGB
                {
                    pixels = cropPixels.Select(memory => memory.ToArray()).ToArray(),
                    offset = new Location2d { x = rect.x, y = rect.y },
                };
            }).ToArray();

        crops_2x2_r8g8b8 =
            request.crops_2x2_r8g8b8
            .Select(rect =>
            {
                var wrappedOffsetX = rect.x % 2;
                var wrappedOffsetY = rect.y % 2;

                var binnedPixels =
                    historyEntry.Pixels_2x2_R8G8B8_by_offset(
                        new Location2d { x = wrappedOffsetX, y = wrappedOffsetY });

                var cropPixels =
                    CopyRectangularCrop(
                        binnedPixels,
                        new Rect2d { x = rect.x / 2, y = rect.y / 2, width = rect.width, height = rect.height });

                return new ImageCropRGB
                {
                    pixels = cropPixels.Select(memory => memory.ToArray()).ToArray(),
                    offset = new Location2d { x = rect.x, y = rect.y },
                };
            }).ToArray();
    }

    return new Response.GetImageDataFromReadingResultStructure
    {
        crops_1x1_r8g8b8 = crops_1x1_r8g8b8,
        crops_2x2_r8g8b8 = crops_2x2_r8g8b8 ?? ImmutableList<ImageCropRGB>.Empty
    };
}

ReadOnlyMemory<int>[] CopyRectangularCrop(ReadOnlyMemory<int>[] original, Rect2d rect)
{
    return
        original
        .Skip(rect.y)
        .Take(rect.height)
        .Select(rowPixels =>
        {
            if (rect.x == 0 && rect.width == rowPixels.Length)
                return rowPixels;

            var sliceLength = Math.Min(rect.width, rowPixels.Length - rect.x);

            return rowPixels.Slice(rect.x, sliceLength);
        })
        .ToArray();
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

public ReadOnlyMemory<int>[] GetScreenshotOfWindowAsPixelsValues_R8G8B8(IntPtr windowHandle)
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

    var pixels = new ReadOnlyMemory<int>[screenshotAsBitmap.Height];

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
    if (!WinApi.GetWindowRect(windowHandle, ref windowRect))
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

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int x;
        public int y;

        public Point(int x, int y)
        {
            this.x = x;
            this.y = y;
        }
    }

    public enum MouseButton
    {
        Left = 0,
        Middle = 1,
        Right = 2,
    }

    [DllImport("user32.dll", SetLastError = true)]
    static public extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    static public extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll", SetLastError = true)]
    static public extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    static public extern int SetForegroundWindow(IntPtr hWnd);

    public const int SW_RESTORE = 9;

    [DllImport("user32.dll")]
    static public extern IntPtr ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    static public extern bool GetWindowRect(IntPtr hWnd, ref Rect rect);

    [DllImport("user32.dll")]
    static public extern IntPtr GetClientRect(IntPtr hWnd, ref Rect rect);

    [DllImport("user32.dll", SetLastError = false)]
    static public extern IntPtr GetDesktopWindow();

    [DllImport("user32.dll", SetLastError = false)]
    static public extern IntPtr GetTopWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = false)]
    static public extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static public extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    static public extern bool ClientToScreen(IntPtr hWnd, ref Point lpPoint);

    [DllImport("user32.dll")]
    static public extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    /*
    https://stackoverflow.com/questions/19867402/how-can-i-use-enumwindows-to-find-windows-with-a-specific-caption-title/20276701#20276701
    https://stackoverflow.com/questions/295996/is-the-order-in-which-handles-are-returned-by-enumwindows-meaningful/296014#296014
    */
    public static IEnumerable<IntPtr> EnumerateWindowHandlesInZOrderStartingFromForegroundWindow()
    {
        var windowHandle = GetForegroundWindow();

        while (windowHandle != IntPtr.Zero)
        {
            yield return windowHandle;

            // https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getnextwindow
            // https://stackoverflow.com/questions/798295/how-can-i-use-getnextwindow-in-c/798303#798303
            windowHandle = GetWindow(windowHandle, 2);
        }
    }
}

string SerializeToJsonForBot<T>(T value) =>
    Newtonsoft.Json.JsonConvert.SerializeObject(
        value,
        //  Use settings to get same derivation as at https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L91-L97
        new Newtonsoft.Json.JsonSerializerSettings
        {
            //  Bot code does not expect properties with null values, see https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
            NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,

            //\thttps://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
            ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
        });

string InterfaceToHost_Request(string request)
{
    return serialRequest(request);
}

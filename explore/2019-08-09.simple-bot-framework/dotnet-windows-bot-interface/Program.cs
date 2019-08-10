using System;
using System.Runtime.InteropServices;

namespace dotnet_windows_bot_interface
{
    class Program
    {
        static void Main(string[] args)
        {
            var waitTimeInSeconds = 1;

            //  Before continuing, give the user some time to activate the window we want to work with.
            Console.WriteLine("Please activate the window I should work in. I will read the active window in " + waitTimeInSeconds + " seconds.");
            System.Threading.Thread.Sleep(TimeSpan.FromSeconds(waitTimeInSeconds));

            //  Test the request/response code as if used from the bot.

            var windowToWorkOn =
                request(new Request { GetForegroundWindow = true })
                .GetForegroundWindowResult;

            var windowTitle =
                request(new Request { GetWindowText = windowToWorkOn }).GetWindowTextResult;

            Console.WriteLine("I identified a window with the title '" + windowTitle + "' as the window to work in.");

            //  if (false)
            {
                //  Test sequence to use with MS Paint. (When testing this with Paint.NET, no lines were drawn)

                foreach (var taskSequence in demoSequenceToTestMousePathOnPaint())
                {
                    foreach (var task in taskSequence)
                    {
                        request(
                            new Request
                            {
                                TaskOnWindow =
                                    new Request.TaskOnIdentifiedWindowStructure
                                    {
                                        windowId = windowToWorkOn,
                                        task = task,
                                    }
                            });
                    }

                    waitMilliseconds(44);
                }
            }

            var windowToWorkOnHandle = new IntPtr(windowToWorkOn.WindowHandleFromInt);

            var screenshotImageFile = GetScreenshotOfWindowAsImageFileBMP(windowToWorkOnHandle);

            if (screenshotImageFile == null)
            {
                Console.WriteLine("I failed to get a screenshot of the window.");
                return;
            }

            var filePath = System.IO.Path.Combine(Environment.CurrentDirectory, "test", DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH-mm-ss") + ".screenshot.bmp");

            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(filePath));

            System.IO.File.WriteAllBytes(filePath, screenshotImageFile);

            Console.WriteLine("I got a screenshot of the window, and saved it to file '" + filePath + "'.");
        }

        static public Response request(Request request)
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
                performTaskOnWindow(request.TaskOnWindow);
                return new Response { NoReturnValue = new object() };
            }

            throw new Exception("Unexpected request value.");
        }

        static public WindowId GetForegroundWindow() =>
            new WindowId { WindowHandleFromInt = WinApi.GetForegroundWindow().ToInt64() };

        static public byte[] GetScreenshotOfWindowAsImageFileBMP(IntPtr windowHandle)
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

        static public System.Drawing.Bitmap GetScreenshotOfWindowAsBitmap(IntPtr windowHandle)
        {
            SetProcessDPIAware();

            var windowRect = new WinApi.Rect();
            if (WinApi.GetWindowRect(windowHandle, ref windowRect) == IntPtr.Zero)
                return null;

            int width = windowRect.right - windowRect.left;
            int height = windowRect.bottom - windowRect.top;

            var asBitmap = new System.Drawing.Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format24bppRgb);

            //  Where from could we get the scale to apply to compute the rect in screen coordinates?
            Console.WriteLine("System.Drawing.Graphics.FromImage(asBitmap).DpiX: " + System.Drawing.Graphics.FromImage(asBitmap).DpiX);

            Console.WriteLine("System.Drawing.Graphics.FromHwnd(GetDesktopWindow()).DpiX: " + System.Drawing.Graphics.FromHwnd(WinApi.GetDesktopWindow()).DpiX);
            Console.WriteLine("System.Drawing.Graphics.FromHwnd(windowHandle).DpiX: " + System.Drawing.Graphics.FromHwnd(windowHandle).DpiX);

            System.Drawing.Graphics.FromImage(asBitmap).CopyFromScreen(
                windowRect.left,
                windowRect.top,
                0,
                0,
                new System.Drawing.Size(width, height),
                System.Drawing.CopyPixelOperation.SourceCopy);

            return asBitmap;
        }

        static void SetProcessDPIAware()
        {
            //  https://www.google.com/search?q=GetWindowRect+dpi
            //  https://github.com/dotnet/wpf/issues/859
            //  https://github.com/dotnet/winforms/issues/135
            WinApi.SetProcessDPIAware();
        }

        static void waitMilliseconds(int milliseconds) =>
             System.Threading.Thread.Sleep(milliseconds);

        static void performTaskOnWindow(Request.TaskOnIdentifiedWindowStructure taskOnIdentifiedWindow)
        {
            var windowHandle = new IntPtr(taskOnIdentifiedWindow.windowId.WindowHandleFromInt);

            var windowRect = new WinApi.Rect();
            if (WinApi.GetWindowRect(windowHandle, ref windowRect) == IntPtr.Zero)
                return;

            var inputSimulator = new WindowsInput.InputSimulator();

            var task = taskOnIdentifiedWindow.task;

            if (task.BringWindowToForeground != null)
            {
                WinApi.SetForegroundWindow(windowHandle);
                WinApi.ShowWindow(windowHandle, WinApi.SW_RESTORE);
            }

            if (task.MoveMouseToLocation != null)
            {
                WinApi.SetCursorPos(
                    task.MoveMouseToLocation.x + windowRect.left,
                    task.MoveMouseToLocation.y + windowRect.top);
            }

            if (task.MouseButtonDown != null)
            {
                if (task.MouseButtonDown.MouseButtonLeft != null)
                    inputSimulator.Mouse.LeftButtonDown();

                if (task.MouseButtonDown.MouseButtonRight != null)
                    inputSimulator.Mouse.RightButtonDown();
            }

            if (task.MouseButtonUp != null)
            {
                if (task.MouseButtonUp.MouseButtonLeft != null)
                    inputSimulator.Mouse.LeftButtonUp();

                if (task.MouseButtonUp.MouseButtonRight != null)
                    inputSimulator.Mouse.RightButtonUp();
            }

            if (task.KeyboardKeyDown != null)
                inputSimulator.Keyboard.KeyDown((WindowsInput.Native.VirtualKeyCode)task.KeyboardKeyDown.KeyboardKeyFromVirtualKeyCode);

            if (task.KeyboardKeyUp != null)
                inputSimulator.Keyboard.KeyUp((WindowsInput.Native.VirtualKeyCode)task.KeyboardKeyUp.KeyboardKeyFromVirtualKeyCode);
        }

        static Request.TaskOnWindowStructure[][] demoSequenceToTestMousePathOnPaint() =>
            new[]
            {
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        BringWindowToForeground = true,
                    },
                },
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        MoveMouseToLocation = new Request.Location2d { x = 100, y = 250 },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        MouseButtonDown = new Request.MouseButton{ MouseButtonLeft = true },
                    },
                },
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        MoveMouseToLocation = new Request.Location2d { x = 200, y = 300 },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        MouseButtonUp = new Request.MouseButton{ MouseButtonLeft = true },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        MouseButtonDown = new Request.MouseButton{ MouseButtonRight = true },
                    },
                },
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        MoveMouseToLocation = new Request.Location2d { x = 300, y = 230 },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        MouseButtonUp = new Request.MouseButton{ MouseButtonRight = true },
                    },
                },
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        MoveMouseToLocation = new Request.Location2d { x = 160, y = 235 },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        MouseButtonDown = new Request.MouseButton{ MouseButtonLeft = true },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        MouseButtonUp = new Request.MouseButton{ MouseButtonLeft = true },
                    },
                },
                //  2019-06-09 MS Paint did also draw when space key was pressed. Next, we draw a line without a mouse button, by holding the space key down.
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        MoveMouseToLocation = new Request.Location2d { x = 180, y = 230 },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        KeyboardKeyDown = new Request.KeyboardKey{ KeyboardKeyFromVirtualKeyCode = (int)WindowsInput.Native.VirtualKeyCode.SPACE }
                    },
                },
                new []
                {
                    new Request.TaskOnWindowStructure
                    {
                        MoveMouseToLocation = new Request.Location2d { x = 210, y = 240 },
                    },
                    new Request.TaskOnWindowStructure
                    {
                        KeyboardKeyUp = new Request.KeyboardKey{ KeyboardKeyFromVirtualKeyCode = (int)WindowsInput.Native.VirtualKeyCode.SPACE }
                    },
                },
            };
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

    public class Request
    {
        public TaskOnIdentifiedWindowStructure TaskOnWindow;

        public object GetForegroundWindow;

        public WindowId GetWindowText;

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
    }

    public class WindowId
    {
        public long WindowHandleFromInt;
    }
}

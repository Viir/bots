using System.Runtime.InteropServices;

namespace BotEngine.Windows.Console
{
    static class Windows
    {
        //  https://docs.microsoft.com/en-us/windows/desktop/inputdev/virtual-key-codes

        public const int VK_CONTROL = 0x11;
        public const int VK_MENU = 0x12;

        //  https://www.pinvoke.net/default.aspx/user32.getasynckeystate
        [DllImport("User32.dll")]
        static public extern ushort GetAsyncKeyState(System.Int32 vKey);

        //  https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-getasynckeystate
        static public bool IsKeyDown(int vKey) => (GetAsyncKeyState(vKey) & 0x8000) != 0;
    }
}

using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PlayPointer.Windows;

internal static class Native
{
    internal const int Popup = unchecked((int)0x80000000);
    internal const int Topmost = 0x00000008;
    internal const int Transparent = 0x00000020;
    internal const int ToolWindow = 0x00000080;
    internal const int Layered = 0x00080000;
    internal const int NoActivate = 0x08000000;
    internal const int WmMouseActivate = 0x0021;
    internal const int WmSettingChange = 0x001A;
    internal const int WmDisplayChange = 0x007E;
    internal const int WmHotKey = 0x0312;
    internal const int WmDpiChanged = 0x02E0;
    internal const int WmMouseMove = 0x0200;
    internal const int WmLeftDown = 0x0201;
    internal const int WmLeftUp = 0x0202;
    internal const int WmMouseWheel = 0x020A;
    internal const int WmMouseHWheel = 0x020E;
    internal const int WmSetCursor = 0x0020;
    internal const int WmEraseBackground = 0x0014;
    internal const int WmNcHitTest = 0x0084;
    internal const int MaNoActivate = 3;
    internal const int HtClient = 1;
    internal const int SmSwapButton = 23;
    internal const int VkLButton = 0x01;
    internal const int VkRButton = 0x02;
    internal const int VkMenu = 0x12;
    internal const uint ModAlt = 0x0001;
    internal const uint ModControl = 0x0002;
    internal const uint ModNoRepeat = 0x4000;
    internal const uint SwpNoSize = 0x0001;
    internal const uint SwpNoMove = 0x0002;
    internal const uint SwpNoActivate = 0x0010;
    internal const int SwHide = 0;
    internal const int SwShowNa = 8;
    internal const uint SndAsync = 0x0001;
    internal const uint SndNoDefault = 0x0002;
    internal const uint SndFileName = 0x00020000;

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point32(int x, int y)
    {
        internal int X = x, Y = y;
        internal readonly Point DrawingPoint => new(X, Y);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Size32(int width, int height)
    {
        internal int Width = width, Height = height;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct BitmapInfoHeader
    {
        internal uint Size;
        internal int Width, Height;
        internal ushort Planes, BitCount;
        internal uint Compression, SizeImage;
        internal int XPelsPerMeter, YPelsPerMeter;
        internal uint ClrUsed, ClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct BlendFunction
    {
        internal byte Operation, Flags, ConstantAlpha, AlphaFormat;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UpdateLayeredWindow(nint window, nint targetDc, ref Point32 position,
        ref Size32 size, nint sourceDc, ref Point32 source, uint colorKey, ref BlendFunction blend, uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ShowWindow(nint window, int command);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetCursorPos(out Point32 position);

    [DllImport("user32.dll")]
    internal static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ClientToScreen(nint window, ref Point32 point);

    [DllImport("user32.dll")]
    internal static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    internal static extern uint GetDpiForWindow(nint window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern nint LoadCursor(nint instance, nint name);

    [DllImport("user32.dll")]
    internal static extern nint SetCursor(nint cursor);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint key);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(nint window, int id);

    [DllImport("gdi32.dll", SetLastError = true)]
    internal static extern nint CreateCompatibleDC(nint deviceContext);

    [DllImport("gdi32.dll", SetLastError = true)]
    internal static extern nint CreateDIBSection(nint deviceContext, ref BitmapInfoHeader info,
        uint usage, out nint bits, nint section, uint offset);

    [DllImport("gdi32.dll", SetLastError = true)]
    internal static extern nint SelectObject(nint deviceContext, nint obj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteObject(nint obj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteDC(nint deviceContext);

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PlaySound(string? fileName, nint module, uint flags);

    internal static bool KeyDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    internal static Win32Exception LastError(string action)
    {
        int code = Marshal.GetLastWin32Error();
        return new Win32Exception(code, $"{action} (код Windows: {code}).");
    }
}

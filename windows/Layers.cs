using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace PlayPointer.Windows;

// The DIB is both the managed drawing surface and the source for UpdateLayeredWindow.
internal sealed class LayerBuffer : IDisposable
{
    private nint dc, dib, previous, bits;
    private Bitmap? bitmap;
    private Graphics? graphics;
    private readonly Size size;

    internal LayerBuffer(Size size)
    {
        this.size = size;
        try
        {
            dc = Native.CreateCompatibleDC(0);
            if (dc == 0) throw Native.LastError("Не удалось создать слой");
            var info = new Native.BitmapInfoHeader
            {
                Size = (uint)Marshal.SizeOf<Native.BitmapInfoHeader>(),
                Width = size.Width,
                Height = -size.Height, // Top-down BGRA rows.
                Planes = 1,
                BitCount = 32
            };
            dib = Native.CreateDIBSection(dc, ref info, 0, out bits, 0, 0);
            if (dib == 0 || bits == 0) throw Native.LastError("Не удалось создать буфер слоя");
            previous = Native.SelectObject(dc, dib);
            if (previous == 0 || previous == -1) throw Native.LastError("Не удалось подключить буфер слоя");
            bitmap = new Bitmap(size.Width, size.Height, checked(size.Width * 4), PixelFormat.Format32bppPArgb, bits);
            graphics = Graphics.FromImage(bitmap);
            graphics.PageUnit = GraphicsUnit.Pixel;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Clear();
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal Graphics Graphics => graphics!;

    internal void Clear()
    {
        Graphics.CompositingMode = CompositingMode.SourceCopy;
        Graphics.Clear(Color.FromArgb(0));
        Graphics.CompositingMode = CompositingMode.SourceOver;
    }

    internal unsafe void FillAlpha(byte alpha)
    {
        new Span<uint>((void*)bits, checked(size.Width * size.Height)).Fill((uint)alpha << 24);
    }

    internal void Present(nint window, Point position)
    {
        Graphics.Flush(FlushIntention.Sync);
        var destination = new Native.Point32(position.X, position.Y);
        var dimensions = new Native.Size32(size.Width, size.Height);
        var source = new Native.Point32(0, 0);
        var blend = new Native.BlendFunction { ConstantAlpha = 255, AlphaFormat = 1 };
        if (!Native.UpdateLayeredWindow(window, 0, ref destination, ref dimensions, dc, ref source, 0, ref blend, 2))
            throw Native.LastError("Не удалось обновить слой");
    }

    public void Dispose()
    {
        graphics?.Dispose();
        bitmap?.Dispose();
        if (previous != 0 && previous != -1) Native.SelectObject(dc, previous);
        if (dib != 0) Native.DeleteObject(dib);
        if (dc != 0) Native.DeleteDC(dc);
        graphics = null;
        bitmap = null;
        dc = dib = previous = bits = 0;
    }
}

internal class LayerWindow : NativeWindow, IDisposable
{
    private bool shown;

    internal LayerWindow(Rectangle bounds, bool acceptsMouse = false)
    {
        CreateHandle(new CreateParams
        {
            Caption = "PlayPointer overlay",
            Style = Native.Popup,
            ExStyle = Native.Layered | Native.ToolWindow | Native.NoActivate | Native.Topmost
                | (acceptsMouse ? 0 : Native.Transparent),
            X = bounds.X, Y = bounds.Y, Width = bounds.Width, Height = bounds.Height
        });
    }

    internal void ShowLayer()
    {
        if (shown) return;
        Native.ShowWindow(Handle, Native.SwShowNa);
        shown = true;
    }

    internal void HideLayer()
    {
        if (!shown) return;
        Native.ShowWindow(Handle, Native.SwHide);
        shown = false;
    }

    protected override void WndProc(ref Message message)
    {
        // The controller positions these windows in physical desktop pixels.
        if (message.Msg is Native.WmDpiChanged or Native.WmEraseBackground)
        {
            message.Result = 0;
            return;
        }
        if (message.Msg == Native.WmMouseActivate)
        {
            message.Result = Native.MaNoActivate;
            return;
        }
        base.WndProc(ref message);
    }

    public virtual void Dispose() => DestroyHandle();
}

internal sealed class DrawInputWindow : LayerWindow
{
    private readonly Action<int, Point, bool> onMouse;

    internal DrawInputWindow(Rectangle bounds, Action<int, Point, bool> onMouse) : base(bounds, acceptsMouse: true)
    {
        this.onMouse = onMouse;
        try
        {
            // A nonzero per-pixel alpha keeps the input window hittable.
            // UpdateLayeredWindow retains the uploaded image after the DIB is released.
            using var buffer = new LayerBuffer(bounds.Size);
            buffer.FillAlpha(1);
            buffer.Present(Handle, bounds.Location);
        }
        catch { Dispose(); throw; }
    }

    protected override void WndProc(ref Message message)
    {
        switch (message.Msg)
        {
            case Native.WmNcHitTest:
                message.Result = Native.HtClient;
                return;
            case Native.WmSetCursor:
                Native.SetCursor(Native.LoadCursor(0, 32515)); // IDC_CROSS
                message.Result = 1;
                return;
            case Native.WmMouseMove:
            case Native.WmLeftDown:
            case Native.WmLeftUp:
                long value = message.LParam.ToInt64();
                var point = new Native.Point32(unchecked((short)value), unchecked((short)(value >> 16)));
                if (Native.ClientToScreen(Handle, ref point))
                    onMouse?.Invoke(message.Msg, point.DrawingPoint, (message.WParam.ToInt64() & 1) != 0);
                message.Result = 0;
                return;
            case Native.WmMouseWheel:
            case Native.WmMouseHWheel:
                message.Result = 0;
                return;
        }
        base.WndProc(ref message);
    }
}

internal sealed class InkTile : LayerWindow
{
    private readonly LayerBuffer buffer;
    internal Rectangle Bounds { get; }
    internal bool Dirty { get; private set; }

    internal InkTile(Rectangle bounds) : base(bounds)
    {
        Bounds = bounds;
        try { buffer = new LayerBuffer(bounds.Size); }
        catch { base.Dispose(); throw; }
    }

    internal void Add(Point start, Point end, Color color, float width)
    {
        var a = new Point(start.X - Bounds.X, start.Y - Bounds.Y);
        var b = new Point(end.X - Bounds.X, end.Y - Bounds.Y);
        if (a == b)
        {
            using var brush = new SolidBrush(color);
            buffer.Graphics.FillEllipse(brush, a.X - width / 2, a.Y - width / 2, width, width);
        }
        else
        {
            using var pen = new Pen(color, width) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            buffer.Graphics.DrawLine(pen, a, b);
        }
        Dirty = true;
    }

    internal void Present()
    {
        buffer.Present(Handle, Bounds.Location);
        ShowLayer();
        Dirty = false;
    }

    public override void Dispose()
    {
        base.Dispose();
        buffer.Dispose();
    }
}

internal sealed class InkCanvas : IDisposable
{
    private const int TileSize = 512;
    private Rectangle[] screens = [];
    private readonly Dictionary<Rectangle, InkTile> tiles = [];
    internal IEnumerable<InkTile> Tiles => tiles.Values;

    internal void SetScreens(IEnumerable<Rectangle> areas)
    {
        Clear();
        screens = areas.ToArray();
    }

    internal void Add(Point start, Point end, Color color, float width)
    {
        int padding = (int)Math.Ceiling(width / 2) + 2;
        var bounds = Rectangle.FromLTRB(Math.Min(start.X, end.X) - padding, Math.Min(start.Y, end.Y) - padding,
            Math.Max(start.X, end.X) + padding + 1, Math.Max(start.Y, end.Y) + padding + 1);
        foreach (Rectangle screen in screens)
        {
            Rectangle region = Rectangle.Intersect(bounds, screen);
            if (region.Width <= 0 || region.Height <= 0) continue;
            for (int y = (region.Top - screen.Top) / TileSize; y <= (region.Bottom - 1 - screen.Top) / TileSize; ++y)
            for (int x = (region.Left - screen.Left) / TileSize; x <= (region.Right - 1 - screen.Left) / TileSize; ++x)
            {
                int left = screen.Left + x * TileSize, top = screen.Top + y * TileSize;
                var area = Rectangle.FromLTRB(left, top, Math.Min(left + TileSize, screen.Right), Math.Min(top + TileSize, screen.Bottom));
                if (!tiles.TryGetValue(area, out var tile))
                {
                    tile = new InkTile(area);
                    tiles.Add(area, tile);
                }
                tile.Add(start, end, color, width);
            }
        }
    }

    internal void Clear()
    {
        foreach (var tile in tiles.Values) tile.Dispose();
        tiles.Clear();
    }

    public void Dispose() => Clear();
}

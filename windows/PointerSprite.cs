using System.Drawing.Drawing2D;

namespace PlayPointer.Windows;

internal sealed class PointerSprite : LayerWindow
{
    private static readonly Color[] Rainbow = [Color.Red, Color.Orange, Color.Gold, Color.LimeGreen, Color.DeepSkyBlue, Color.MediumPurple];
    private readonly List<(PointF Point, long Time)> trail = [];
    private LayerBuffer? buffer;
    private Size bufferSize;
    private Artwork? idle, pressed, alternate;
    private PointerStyle style = PointerCatalog.Laser;
    private Point? lastCursor;
    private PointF? cat;
    private Point pulseOrigin;
    private long pulseAt = -1000;
    private long lastRendered = -1000;
    private int reaction;
    private float lastScale;
    private bool dirty = true;

    internal PointerSprite() : base(new Rectangle(0, 0, 1, 1)) { }

    internal void SetStyle(PointerStyle newStyle)
    {
        Artwork? nextIdle = null, nextPressed = null, nextAlternate = null;
        try
        {
            nextIdle = Artwork.Load(newStyle.Asset, newStyle.Pixelated);
            nextPressed = Artwork.Load(newStyle.Pressed, newStyle.Pixelated);
            nextAlternate = Artwork.Load(newStyle.Alternate, newStyle.Pixelated);
        }
        catch
        {
            nextIdle?.Dispose();
            nextPressed?.Dispose();
            nextAlternate?.Dispose();
            throw;
        }
        idle?.Dispose();
        pressed?.Dispose();
        alternate?.Dispose();
        idle = nextIdle;
        pressed = nextPressed;
        alternate = nextAlternate;
        style = newStyle;
        Reset();
    }

    internal void Reset()
    {
        trail.Clear();
        lastCursor = null;
        cat = null;
        pulseAt = -1000;
        dirty = true;
        HideLayer();
    }

    internal void Pulse(Point cursor, long time, int button)
    {
        pulseOrigin = cursor;
        pulseAt = time;
        reaction = button;
        dirty = true;
    }

    internal void Render(Point cursor, Rectangle screen, float scale, long now, bool reducedMotion)
    {
        bool moved = lastCursor != cursor || lastScale != scale;
        long elapsed = now - pulseAt;
        bool animatePulse = elapsed < 360 || lastRendered - pulseAt < 360;
        bool animateTrail = trail.Count > 0;
        if (!moved && !dirty && !animatePulse && !animateTrail && !style.IsCat) return;
        if (lastCursor is Point previous && DistanceSquared(previous, cursor) > (330 * scale) * (330 * scale))
        {
            trail.Clear();
            cat = null;
        }
        float span = style.Kind == PointerKind.Nyan ? 280 : style.IsCat ? 194 : 166;
        int side = (int)Math.Ceiling(span * 2 * scale);
        var size = new Size(side, side);
        if (bufferSize != size)
        {
            buffer?.Dispose();
            buffer = null;
            bufferSize = Size.Empty;
            buffer = new LayerBuffer(size);
            bufferSize = size;
        }
        var origin = new Point(cursor.X - side / 2, cursor.Y - side / 2);
        buffer!.Clear();
        var g = buffer.Graphics;
        g.ResetTransform();
        g.TranslateTransform(-origin.X, -origin.Y);
        Artwork? frame = elapsed < 190 ? (reaction == 1 ? alternate ?? pressed : pressed) ?? idle : idle;
        RectangleF artRect = RectangleF.Empty;
        if (frame is not null)
        {
            float targetSize = style.Kind switch
            {
                PointerKind.Pixel => style.Id == "pixel" ? 126 : 49,
                PointerKind.PixelCat => 87,
                PointerKind.Cat => 105,
                PointerKind.Nyan => style.Id == "funny21" ? 107 : 100,
                PointerKind.Bongo => 108,
                _ => 146
            };
            float factor = targetSize * scale / Math.Max(frame.Image.Width, frame.Image.Height);
            float width = frame.Image.Width * factor, height = frame.Image.Height * factor;
            if (style.IsCat)
            {
                float offsetX = cursor.X > screen.Right - 125 * scale ? -52 * scale : 52 * scale;
                float offsetY = cursor.Y > screen.Bottom - 105 * scale ? -46 * scale : 49 * scale;
                var target = new PointF(cursor.X + offsetX, cursor.Y + offsetY);
                var old = cat ?? target;
                var next = reducedMotion ? target : new PointF(old.X + (target.X - old.X) * 0.25f, old.Y + (target.Y - old.Y) * 0.25f);
                if (DistanceSquared(target, next) <= 0.25f) next = target;
                cat = next;
                if (!moved && !dirty && !animatePulse && old == next) return;
                artRect = new RectangleF(next.X - width / 2, next.Y - height / 2, width, height);
            }
            else
            {
                artRect = new RectangleF(cursor.X - frame.Hotspot.X * factor, cursor.Y - frame.Hotspot.Y * factor, width, height);
            }
            if (style.Kind == PointerKind.Nyan && !reducedMotion)
            {
                var tail = new PointF(artRect.Left + width * 0.20f, artRect.Top + height * 0.42f);
                if (moved && (trail.Count == 0 || DistanceSquared(trail[^1].Point, tail) >= 4))
                    trail.Add((tail, now));
                trail.RemoveAll(point => now - point.Time > 480 || DistanceSquared(point.Point, cursor) > MathF.Pow(220 * scale, 2));
                DrawTrail(g, scale, now);
            }
            else trail.Clear();

            g.InterpolationMode = style.Pixelated ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(frame.Image, artRect, new RectangleF(PointF.Empty, frame.Image.Size), GraphicsUnit.Pixel);
        }

        if (animatePulse && elapsed < 360 && !reducedMotion)
        {
            float progress = elapsed / 360f;
            var pulse = new PointF(pulseOrigin.X, pulseOrigin.Y);
            using var ring = new Pen(Color.FromArgb((int)(210 * (1 - progress)), style.Color), 2.1f * scale);
            float radius = (8 + 19 * progress) * scale;
            g.DrawEllipse(ring, pulse.X - radius, pulse.Y - radius, radius * 2, radius * 2);
            if (style.Kind == PointerKind.Wand) DrawSparks(g, pulse, scale, progress);
            if (style.Kind == PointerKind.Bongo) DrawNotes(g, artRect, scale, progress, reaction);
        }

        Color hotColor = style.IsCat || style.Kind == PointerKind.Laser ? PointerCatalog.Laser.Color : style.Color;
        float hotRadius = (style.IsCat || frame is null ? 4.8f : 2.7f) * scale;
        using var dot = new SolidBrush(hotColor);
        using var edge = new Pen(Color.FromArgb(225, Color.White), 1.25f * scale);
        g.FillEllipse(dot, cursor.X - hotRadius, cursor.Y - hotRadius, hotRadius * 2, hotRadius * 2);
        g.DrawEllipse(edge, cursor.X - hotRadius, cursor.Y - hotRadius, hotRadius * 2, hotRadius * 2);

        buffer.Present(Handle, origin);
        ShowLayer();
        lastCursor = cursor;
        lastScale = scale;
        lastRendered = now;
        dirty = false;
    }

    internal void Raise()
    {
        Native.SetWindowPos(Handle, -1, 0, 0, 0, 0, Native.SwpNoSize | Native.SwpNoMove | Native.SwpNoActivate);
    }

    private void DrawTrail(Graphics g, float scale, long now)
    {
        for (int i = 1; i < trail.Count; i++)
        {
            var a = trail[i - 1];
            var b = trail[i];
            int opacity = (int)(208 * Math.Clamp(1 - (now - b.Time) / 480f, 0, 1));
            for (int c = 0; c < Rainbow.Length; ++c)
            {
                using var pen = new Pen(Color.FromArgb(opacity, Rainbow[c]), 2.7f * scale);
                float y = (c - 2.5f) * 2.7f * scale;
                g.DrawLine(pen, a.Point.X, a.Point.Y + y, b.Point.X, b.Point.Y + y);
            }
        }
    }

    private static void DrawSparks(Graphics g, PointF point, float scale, float progress)
    {
        using var pen = new Pen(Color.FromArgb((int)(230 * (1 - progress)), 244, 172, 33), 2f * scale);
        for (int i = 0; i < 8; ++i)
        {
            float angle = (i + 0.5f) * MathF.Tau / 8;
            float spread = (12 + 32 * progress) * scale;
            float x = MathF.Cos(angle), y = MathF.Sin(angle);
            g.DrawLine(pen, point.X + x * spread, point.Y + y * spread,
                point.X + x * (spread + 6 * scale), point.Y + y * (spread + 6 * scale));
        }
    }

    private static void DrawNotes(Graphics g, RectangleF artRect, float scale, float progress, int reaction)
    {
        using var brush = new SolidBrush(Color.FromArgb((int)(235 * (1 - progress)), 127, 87, 221));
        using var pen = new Pen(brush, 1.6f * scale);
        for (int i = 0; i < 2; ++i)
        {
            float x = artRect.Left + artRect.Width * 0.60f + (reaction == 0 ? -1 : 1) * (i * 13 + 9 * progress) * scale;
            float y = artRect.Top + (3 - i * 10 - 27 * progress) * scale;
            g.FillEllipse(brush, x, y, 6 * scale, 4 * scale);
            g.DrawLine(pen, x + 5 * scale, y + scale, x + 5 * scale, y - 9 * scale);
            g.DrawLine(pen, x + 5 * scale, y - 9 * scale, x + 10 * scale, y - 7 * scale);
        }
    }

    private static float DistanceSquared(PointF a, PointF b)
    {
        float dx = a.X - b.X, dy = a.Y - b.Y;
        return dx * dx + dy * dy;
    }

    public override void Dispose()
    {
        base.Dispose();
        buffer?.Dispose();
        idle?.Dispose();
        pressed?.Dispose();
        alternate?.Dispose();
    }
}

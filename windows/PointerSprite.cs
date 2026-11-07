using System.Drawing.Drawing2D;

namespace PlayPointer.Windows;

internal sealed class PointerSprite : LayerWindow
{
    private const float DefaultSpan = 166;
    private const float BongoSize = 162;
    private static readonly Color[] Rainbow = [Color.Red, Color.Orange, Color.Gold, Color.LimeGreen, Color.DeepSkyBlue, Color.MediumPurple];
    private readonly List<(PointF Point, long Time, int Segment)> trail = [];
    private readonly PointF[] mirrorCorners = new PointF[3];
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
    private float bongoSpan = DefaultSpan;
    private int nyanDirection = -1, trailSegment;
    private float nyanTurnDistance;
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
        bongoSpan = style.Kind == PointerKind.Bongo ? BongoSpan(idle, pressed, alternate) : DefaultSpan;
        Reset();
    }

    internal void Reset()
    {
        trail.Clear();
        lastCursor = null;
        cat = null;
        nyanDirection = -1;
        nyanTurnDistance = 0;
        trailSegment = 0;
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
        bool flyingNyan = style.Id == "funny21";
        if (lastCursor is Point previous && DistanceSquared(previous, cursor) > (330 * scale) * (330 * scale))
        {
            trail.Clear();
            cat = null;
            nyanTurnDistance = 0;
        }
        else if (flyingNyan && lastCursor is Point last)
        {
            if (scale != lastScale) trailSegment++;
            UpdateNyanDirection(cursor.X - last.X, scale);
        }
        float span = style.Kind switch
        {
            PointerKind.Nyan => 280,
            PointerKind.Bongo => bongoSpan,
            _ => style.IsCat ? 194 : DefaultSpan
        };
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
        bool catChaser = style.Id == "catChaser";
        bool chasePose = catChaser && elapsed < 160 && pressed is not null
            && DistanceSquared(cursor, pulseOrigin) <= (85 * scale) * (85 * scale);
        bool showReaction = catChaser ? chasePose : elapsed < 190;
        Artwork? frame = showReaction ? (reaction == 1 ? alternate ?? pressed : pressed) ?? idle : idle;
        RectangleF artRect = RectangleF.Empty;
        if (frame is not null)
        {
            var (hotspot, baseFactor) = FrameGeometry(frame);
            float factor = baseFactor * scale;
            float width = frame.Image.Width * factor, height = frame.Image.Height * factor;
            bool mirrored = flyingNyan && nyanDirection < 0;
            if (mirrored) hotspot.X = frame.Image.Width - hotspot.X;
            if (chasePose)
            {
                artRect = new RectangleF(pulseOrigin.X - hotspot.X * factor, pulseOrigin.Y - hotspot.Y * factor, width, height);
                cat = new PointF(artRect.Left + width / 2, artRect.Top + height / 2);
            }
            else if (style.IsCat)
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
                artRect = new RectangleF(cursor.X - hotspot.X * factor, cursor.Y - hotspot.Y * factor, width, height);
            }
            if (style.Kind == PointerKind.Nyan && !reducedMotion)
            {
                var emitter = frame.TrailEmitter ?? new PointF(frame.Image.Width * 0.20f, frame.Image.Height * 0.42f);
                if (mirrored) emitter.X = frame.Image.Width - emitter.X;
                var tail = new PointF(artRect.Left + emitter.X * factor, artRect.Top + emitter.Y * factor);
                if (moved && (trail.Count == 0 || trail[^1].Segment != trailSegment || DistanceSquared(trail[^1].Point, tail) >= 4))
                    trail.Add((tail, now, trailSegment));
                trail.RemoveAll(point => now - point.Time > 480 || DistanceSquared(point.Point, cursor) > MathF.Pow(220 * scale, 2));
                DrawTrail(g, scale, now);
            }
            else trail.Clear();

            g.InterpolationMode = style.Pixelated ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            var source = new RectangleF(PointF.Empty, frame.Image.Size);
            if (mirrored)
            {
                mirrorCorners[0] = new PointF(artRect.Right, artRect.Top);
                mirrorCorners[1] = new PointF(artRect.Left, artRect.Top);
                mirrorCorners[2] = new PointF(artRect.Right, artRect.Bottom);
                g.DrawImage(frame.Image, mirrorCorners, source, GraphicsUnit.Pixel);
            }
            else g.DrawImage(frame.Image, artRect, source, GraphicsUnit.Pixel);
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

        if (!flyingNyan || frame is null) DrawHotspot(g, cursor, scale, frame is null);

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

    private void UpdateNyanDirection(int dx, float scale)
    {
        if (dx == 0) return;
        if (Math.Sign(dx) == nyanDirection)
        {
            nyanTurnDistance = 0;
            return;
        }
        nyanTurnDistance += Math.Abs(dx);
        if (nyanTurnDistance < 6 * scale) return;
        nyanDirection = Math.Sign(dx);
        nyanTurnDistance = 0;
        trailSegment++;
    }

    private void DrawHotspot(Graphics g, Point cursor, float scale, bool missingFrame)
    {
        Color hotColor = style.IsCat || style.Kind == PointerKind.Laser ? PointerCatalog.Laser.Color : style.Color;
        float hotRadius = (style.IsCat || missingFrame ? 4.8f : 2.7f) * scale;
        using var dot = new SolidBrush(hotColor);
        using var edge = new Pen(Color.FromArgb(225, Color.White), 1.25f * scale);
        g.FillEllipse(dot, cursor.X - hotRadius, cursor.Y - hotRadius, hotRadius * 2, hotRadius * 2);
        g.DrawEllipse(edge, cursor.X - hotRadius, cursor.Y - hotRadius, hotRadius * 2, hotRadius * 2);
    }

    private (PointF Hotspot, float Factor) FrameGeometry(Artwork frame)
    {
        if (style.Kind == PointerKind.Bongo) return BongoGeometry(frame, idle);
        float targetSize = style.Kind switch
        {
            PointerKind.Pixel => style.Id == "pixel" ? 126 : 49,
            PointerKind.PixelCat => 87,
            PointerKind.Cat => 105,
            PointerKind.Nyan => style.Id == "funny21" ? 107 : 100,
            _ => 146
        };
        return (frame.Hotspot, targetSize / Math.Max(frame.Image.Width, frame.Image.Height));
    }

    private static (PointF Hotspot, float Factor) BongoGeometry(Artwork frame, Artwork? idle)
    {
        // The keyboard and arrow use the same canvas coordinates in every pose.
        var reference = idle is not null && idle.CanvasSize == frame.CanvasSize ? idle : frame;
        var hotspot = new PointF(reference.Hotspot.X + reference.CropOrigin.X - frame.CropOrigin.X,
            reference.Hotspot.Y + reference.CropOrigin.Y - frame.CropOrigin.Y);
        float factor = BongoSize / Math.Max(reference.Image.Width, reference.Image.Height);
        return (hotspot, factor);
    }

    private static float BongoSpan(Artwork? idle, params Artwork?[] frames)
    {
        float span = DefaultSpan;
        foreach (var frame in frames)
        {
            if (frame is null) continue;
            var (tip, factor) = BongoGeometry(frame, idle);
            float horizontal = Math.Max(-tip.X, Math.Max(tip.X, frame.Image.Width - tip.X));
            float vertical = Math.Max(-tip.Y, Math.Max(tip.Y, frame.Image.Height - tip.Y));
            span = Math.Max(span, MathF.Ceiling(Math.Max(horizontal, vertical) * factor + 3));
        }
        return span;
    }

    private void DrawTrail(Graphics g, float scale, long now)
    {
        for (int i = 1; i < trail.Count; i++)
        {
            var a = trail[i - 1];
            var b = trail[i];
            if (a.Segment != b.Segment) continue;
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

using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace PlayPointer.Windows;

internal sealed class ComicHandRenderer : IDisposable
{
    private readonly Bitmap head;
    private readonly PointF tip;
    private readonly float cuffX, cuffY, armWidth, headHeight;
    private readonly Color armColor;
    private readonly List<ArmStrip> strips = [];
    private readonly PointF[] headCorners = new PointF[3];

    internal ComicHandRenderer(string path)
    {
        using var source = new Bitmap(path);
        var whole = new Rectangle(Point.Empty, source.Size);
        using var image = source.Clone(whole, PixelFormat.Format32bppPArgb);
        int seam = (int)MathF.Round(image.Height * 0.45576923076923076f);
        var pixels = image.LockBits(whole, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        int left = image.Width, right = -1, top = -1, tipLeft = image.Width, tipRight = -1;
        int rodLeft = image.Width, rodRight = -1, rodAlpha = 255;
        try
        {
            var row = new byte[image.Width * 4];
            for (int y = 0; y <= seam; y++)
            {
                Marshal.Copy(pixels.Scan0 + y * pixels.Stride, row, 0, row.Length);
                for (int x = 0; x < image.Width; x++)
                {
                    int alpha = row[x * 4 + 3];
                    if (alpha <= 128) continue;
                    if (top < 0) top = y;
                    if (y == top) { tipLeft = Math.Min(tipLeft, x); tipRight = Math.Max(tipRight, x); }
                    left = Math.Min(left, x);
                    right = Math.Max(right, x);
                    if (y == seam) { rodLeft = Math.Min(rodLeft, x); rodRight = Math.Max(rodRight, x); }
                }
                if (y == seam && rodRight >= rodLeft)
                    rodAlpha = row[((rodLeft + rodRight) / 2) * 4 + 3];
            }
        }
        finally { image.UnlockBits(pixels); }
        if (top < 0 || rodRight < rodLeft || seam <= top)
            throw new InvalidDataException("Не удалось измерить комиксную руку.");
        var crop = Rectangle.FromLTRB(Math.Max(0, left - 2), Math.Max(0, top - 2),
            Math.Min(image.Width, right + 3), seam);
        head = image.Clone(crop, PixelFormat.Format32bppPArgb);
        tip = new PointF((tipLeft + tipRight + 1) / 2f - crop.X, top + 0.5f - crop.Y);
        cuffX = (rodLeft + rodRight + 1) / 2f - crop.X;
        cuffY = seam - crop.Y;
        armWidth = rodRight - rodLeft + 1;
        headHeight = seam - top;
        armColor = Color.FromArgb(rodAlpha, Color.Black);
    }

    internal ComicPose Pose(Point cursor, Rectangle screen, float scale, long elapsed, float strength, bool reducedMotion)
    {
        float response = 0;
        if (!reducedMotion && elapsed is >= 0 and < 280)
            response = elapsed < 160 ? 0.09f * strength * MathF.Sin(MathF.PI * elapsed / 160f)
                : -0.025f * strength * MathF.Sin(MathF.PI * (elapsed - 160) / 120f);
        float factor = 166 * scale / headHeight;
        return ComicPose.Create(cursor, screen, tip, cuffX, cuffY, head.Size,
            factor * (1 + response * 0.55f), factor * (1 - response), armWidth);
    }

    internal void DrawHead(Graphics graphics, ComicPose pose)
    {
        headCorners[0] = pose.Map(PointF.Empty);
        headCorners[1] = pose.Map(new PointF(head.Width, 0));
        headCorners[2] = pose.Map(new PointF(0, head.Height));
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.PixelOffsetMode = PixelOffsetMode.Half;
        graphics.DrawImage(head, headCorners, new RectangleF(PointF.Empty, head.Size), GraphicsUnit.Pixel);
    }

    internal void DrawArm(ComicPose pose, Rectangle screen)
    {
        var areas = pose.ArmStrips(screen);
        long allocated = 0;
        int active = 0;
        using var gradient = new LinearGradientBrush(pose.Cuff, pose.Grip, armColor, Color.Transparent);
        foreach (Rectangle area in areas)
        {
            allocated += (long)area.Width * area.Height;
            if (allocated > 4 * 1024 * 1024 || active >= 96) break;
            if (active == strips.Count) strips.Add(new ArmStrip());
            strips[active++].Render(area, pose.Arm, gradient);
        }
        for (int index = strips.Count - 1; index >= active; index--)
        {
            strips[index].Dispose();
            strips.RemoveAt(index);
        }
    }

    internal void Hide() { foreach (var strip in strips) strip.HideLayer(); }
    internal void Raise() { foreach (var strip in strips) strip.Raise(); }
    public void Dispose()
    {
        foreach (var strip in strips) strip.Dispose();
        head.Dispose();
    }

    private sealed class ArmStrip : LayerWindow
    {
        private LayerBuffer? buffer;
        private Size size;
        internal ArmStrip() : base(new Rectangle(0, 0, 1, 1)) { }
        internal void Render(Rectangle area, PointF[] arm, Brush fill)
        {
            if (size != area.Size)
            {
                buffer?.Dispose();
                buffer = null;
                size = Size.Empty;
                buffer = new LayerBuffer(area.Size);
                size = area.Size;
            }
            buffer!.Clear();
            var graphics = buffer.Graphics;
            graphics.ResetTransform();
            graphics.TranslateTransform(-area.X, -area.Y);
            graphics.FillPolygon(fill, arm);
            buffer.Present(Handle, area.Location);
            ShowLayer();
        }
        internal void Raise() => Native.SetWindowPos(Handle, -1, 0, 0, 0, 0,
            Native.SwpNoSize | Native.SwpNoMove | Native.SwpNoActivate);
        public override void Dispose() { base.Dispose(); buffer?.Dispose(); }
    }
}

internal sealed record ComicPose(PointF Cursor, PointF Tip, PointF Right, PointF Down,
    float ScaleX, float ScaleY, PointF Cuff, PointF Grip, PointF[] Arm, Rectangle Bounds)
{
    internal PointF Map(PointF point) => new(Cursor.X + Right.X * (point.X - Tip.X) * ScaleX + Down.X * (point.Y - Tip.Y) * ScaleY,
        Cursor.Y + Right.Y * (point.X - Tip.X) * ScaleX + Down.Y * (point.Y - Tip.Y) * ScaleY);

    internal static ComicPose Create(PointF cursor, Rectangle screen, PointF tip, float cuffX, float cuffY,
        Size head, float scaleX, float scaleY, float armWidth)
    {
        var grip = new PointF(cursor.X + screen.Width * 0.30f, screen.Bottom + screen.Height * 0.12f);
        float dx = grip.X - cursor.X, dy = grip.Y - cursor.Y;
        float reach = MathF.Sqrt(dx * dx + dy * dy);
        float offsetX = (cuffX - tip.X) * scaleX, offsetY = (cuffY - tip.Y) * scaleY;
        float length = Math.Max(screen.Height * 0.05f, MathF.Sqrt(Math.Max(0, reach * reach - offsetX * offsetX)) - offsetY);
        float rotation = MathF.Atan2(dy, dx) - MathF.Atan2(length + offsetY, offsetX);
        var right = new PointF(MathF.Cos(rotation), MathF.Sin(rotation));
        var down = new PointF(-right.Y, right.X);
        var cuff = new PointF(cursor.X + right.X * offsetX + down.X * offsetY,
            cursor.Y + right.Y * offsetX + down.Y * offsetY);
        grip = new PointF(cuff.X + down.X * length, cuff.Y + down.Y * length);
        float half = armWidth * scaleX / 2;
        var arm = new[] { new PointF(cuff.X - right.X * half, cuff.Y - right.Y * half),
            new PointF(cuff.X + right.X * half, cuff.Y + right.Y * half),
            new PointF(grip.X + right.X * half, grip.Y + right.Y * half),
            new PointF(grip.X - right.X * half, grip.Y - right.Y * half) };
        var pose = new ComicPose(cursor, tip, right, down, scaleX, scaleY, cuff, grip, arm, Rectangle.Empty);
        PointF[] corners = [pose.Map(PointF.Empty), pose.Map(new PointF(head.Width, 0)),
            pose.Map(new PointF(0, head.Height)), pose.Map(new PointF(head.Width, head.Height))];
        var bounds = Rectangle.FromLTRB((int)MathF.Floor(corners.Min(p => p.X)) - 3, (int)MathF.Floor(corners.Min(p => p.Y)) - 3,
            (int)MathF.Ceiling(corners.Max(p => p.X)) + 3, (int)MathF.Ceiling(corners.Max(p => p.Y)) + 3);
        return pose with { Bounds = bounds };
    }

    internal IEnumerable<Rectangle> ArmStrips(Rectangle screen)
    {
        int top = Math.Max(screen.Top, (int)MathF.Floor(Arm.Min(p => p.Y)) - 2);
        int bottom = Math.Min(screen.Bottom, (int)MathF.Ceiling(Arm.Max(p => p.Y)) + 2);
        for (int y = top; y < bottom; y += 128)
        {
            int endY = Math.Min(bottom, y + 128);
            float left = float.PositiveInfinity, right = float.NegativeInfinity;
            for (int index = 0; index < Arm.Length; index++)
            {
                var a = Arm[index];
                var b = Arm[(index + 1) % Arm.Length];
                if (a.Y >= y - 2 && a.Y <= endY + 2) { left = Math.Min(left, a.X); right = Math.Max(right, a.X); }
                foreach (float edge in new[] { (float)y - 2, endY + 2f })
                {
                    if (a.Y == b.Y || edge < Math.Min(a.Y, b.Y) || edge > Math.Max(a.Y, b.Y)) continue;
                    float x = a.X + (b.X - a.X) * (edge - a.Y) / (b.Y - a.Y);
                    left = Math.Min(left, x);
                    right = Math.Max(right, x);
                }
            }
            if (!float.IsFinite(left)) continue;
            int startX = Math.Max(screen.Left, (int)MathF.Floor(left) - 2);
            int endX = Math.Min(screen.Right, (int)MathF.Ceiling(right) + 2);
            for (int x = startX; x < endX; x += 1024)
                yield return new Rectangle(x, y, Math.Min(1024, endX - x), endY - y);
        }
    }
}

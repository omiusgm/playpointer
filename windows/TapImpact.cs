using System.Drawing;

namespace PlayPointer.Windows;

internal sealed class TapImpact
{
    private long? lastPrimaryAt;
    private int series;

    internal static float BaseStrength(int level) => Math.Clamp(level, 0, 4) switch
    {
        0 => 0.35f,
        1 => 0.65f,
        2 => 1f,
        3 => 1.3f,
        _ => 1.6f
    };

    internal float AcceptPrimary(long now, int level)
    {
        long gap = lastPrimaryAt is long previous ? now - previous : long.MaxValue;
        series = gap is >= 0 and <= 260 ? Math.Min(series + 1, 3) : 0;
        lastPrimaryAt = now;
        return Math.Min(2f, BaseStrength(level) * (1 + series * 0.1f));
    }

    internal void Reset()
    {
        lastPrimaryAt = null;
        series = 0;
    }

    internal static Rectangle IncludePulse(Rectangle canvas, Point cursor, Point pulse, float scale)
    {
        double dx = (double)cursor.X - pulse.X, dy = (double)cursor.Y - pulse.Y;
        double limit = 260 * scale;
        if (dx * dx + dy * dy > limit * limit) return canvas;
        int padding = (int)Math.Ceiling(108 * scale);
        var impact = new Rectangle(pulse.X - padding, pulse.Y - padding, padding * 2, padding * 2);
        var expanded = Rectangle.Union(canvas, impact);
        int step = Math.Max(1, (int)Math.Ceiling(32 * scale));
        long width = (expanded.Width + step - 1) / step * step;
        long height = (expanded.Height + step - 1) / step * step;
        // A fast pointer warp must never allocate a desktop-sized transparent window.
        return width * height <= 4096L * 4096
            ? expanded : canvas;
    }
}

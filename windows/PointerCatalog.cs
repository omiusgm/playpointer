using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace PlayPointer.Windows;

internal enum PointerKind { Standard, Pixel, Cat, PixelCat, Wand, Nyan, Bongo, Laser }

internal sealed record PointerStyle(string Id, string Title, string Group, string? Asset, int Ink, PointerKind Kind, bool Reacts)
{
    internal Color Color => Color.FromArgb(255, (Ink >> 16) & 255, (Ink >> 8) & 255, Ink & 255);
    internal bool IsCat => Kind is PointerKind.Cat or PointerKind.PixelCat;
    internal bool Pixelated => Kind is PointerKind.Pixel or PointerKind.PixelCat or PointerKind.Nyan;
    internal string? Pressed => Reacts && Asset is not null ? Asset + "_pressed" : null;
    internal string? Alternate => Kind == PointerKind.Bongo ? Asset + "_alternate" : null;
    public override string ToString() => Title;
}

internal static class PointerCatalog
{
    internal const string Cats = "Котики";
    internal const string Fun = "Персонажи и предметы";
    internal const string Hands = "Руки";
    internal const string Basic = "Точки и стрелки";

    private static PointerStyle Style(string id, string title, int ink, string group = Hands,
        string? asset = null, PointerKind kind = PointerKind.Standard, bool reacts = false) =>
        new(id, title, group, asset ?? "hand_" + id, ink, kind, reacts);

    internal static readonly PointerStyle Laser = new("laser", "Лазерная точка", Basic, null, 0xFA3A51, PointerKind.Laser, false);

    internal static readonly IReadOnlyList<PointerStyle> All = new PointerStyle[]
    {
        Laser,
        Style("catLaser", "Лапка за лазером", 0xD78461, Cats, asset: "hand_cat_laser", kind: PointerKind.Cat),
        Style("catChaser", "Котик за лазером", 0xD78461, Cats, asset: "hand_cat_chaser", kind: PointerKind.Cat, reacts: true),
        Style("catPixel", "Пиксельный кот", 0xD78461, Cats, asset: "hand_cat_pixel", kind: PointerKind.PixelCat, reacts: true),
        Style("catFish", "Котик с рыбкой", 0xD78461, Cats, asset: "hand_cat_fish", kind: PointerKind.Cat, reacts: true),
        Style("funny01", "Весёлая стрелка", 0x7E79E8, Fun),
        Style("funny02", "Милая стрелочка", 0x7E79E8, Fun, reacts: true),
        Style("funny03", "Алмазный меч", 0x7E79E8, Fun),
        Style("funny04", "Карандаш", 0x7E79E8, Fun),
        Style("funny05", "Динозаврик", 0x7E79E8, Fun),
        Style("funny06", "Инопланетянин", 0x7E79E8, Fun),
        Style("funny07", "Пицца", 0x7E79E8, Fun, asset: "hand_pizza_clean"),
        Style("funny08", "Морковка", 0x7E79E8, Fun),
        Style("funny09", "Мышь-космонавт", 0x7E79E8, Fun),
        Style("funny10", "Волшебная палочка", 0x7E79E8, Fun, asset: "hand_wand_v2", kind: PointerKind.Wand),
        Style("funny11", "Nyan Cat", 0x7E79E8, Fun, kind: PointerKind.Nyan),
        Style("funny21", "Летящий Nyan Cat", 0x7E79E8, Fun, asset: "hand_nyan_flight", kind: PointerKind.Nyan),
        Style("funny22", "Музыкальный котик", 0x7E79E8, Cats, asset: "hand_bongo_cat", kind: PointerKind.Bongo, reacts: true),
        Style("funny12", "Космическое зелье", 0x7E79E8, Fun),
        Style("funny13", "Северное сияние", 0x7E79E8, Fun),
        Style("funny14", "Six Seven", 0x7E79E8, Fun),
        Style("funny16", "Это голубь?", 0x7E79E8, Fun, asset: "hand_funny16_v2"),
        Style("funny17", "Забери мои деньги", 0x7E79E8, Fun, reacts: true),
        Style("funny18", "Бирюзовый пиксель", 0x31B6D2, Basic, kind: PointerKind.Pixel),
        Style("funny19", "Розовый пиксель", 0xDF53B6, Basic, kind: PointerKind.Pixel),
        Style("funny20", "Помни", 0xE74A5A, Fun),
        Style("squeaky", "Резиновая игрушка", 0xE67F98),
        Style("rocket", "Карманная ракета", 0x3284B4, asset: "hand_rocket_3d"),
        Style("lavender", "Лавандовая рука", 0x7E79E8),
        Style("glove", "Перчатка", 0x7E79E8),
        Style("coral", "Коралловая рука", 0xFA3A51),
        Style("plush", "Плюшевая рука", 0x2F86F0),
        Style("robot", "Робот", 0x16A87A),
        Style("pink", "Жвачка", 0xEE4F98),
        Style("blue", "Небо", 0x2F86F0),
        Style("mint", "Мята", 0x16A87A),
        Style("lemon", "Лимон", 0xF2B705),
        Style("black", "Полночь", 0x1D1D21),
        Style("chrome", "Хром", 0x6B7380),
        Style("holo", "Голограмма", 0x7E79E8),
        Style("fuzzy", "Пушистая", 0x7E79E8),
        Style("wood", "Дерево", 0x9A5E2C),
        Style("marble", "Мрамор", 0x6B7380),
        Style("terrazzo", "Терраццо", 0xF0561D),
        Style("glass", "Стекло", 0x1597E5),
        Style("jelly", "Желе", 0xA33FE6),
        Style("pastel", "Пастель", 0xEE4F98),
        Style("pixel", "Пиксель", 0x1D1D21, kind: PointerKind.Pixel),
        Style("lowpoly", "Полигональная", 0x7E79E8),
        Style("knit", "Вязаная", 0x7E79E8),
        Style("skeleton", "Скелет", 0x9A5E2C),
        Style("astro", "Космонавт", 0x2F86F0),
        Style("space", "Космос", 0xFA3A51),
        Style("monster", "Монстр", 0x3E9E2E),
        Style("water", "Вода", 0x1597E5),
        Style("lava", "Лава", 0xF0561D),
        Style("grass", "Трава", 0x3E9E2E),
        Style("cactus", "Кактус", 0x3E9E2E),
        Style("choco", "Шоколад", 0x9A5E2C),
        Style("cloud", "Облако", 0x2F86F0),
        Style("mech", "Механизм", 0xF0561D),
        Style("neon", "Неон", 0xE0309A),
        Style("leaf", "Лист", 0x3E9E2E),
        Style("cookie", "Пряник", 0x9A5E2C),
    }.Where(style => style.Asset is null || File.Exists(Artwork.PathFor(style.Asset))).ToArray();
}

internal sealed class Artwork : IDisposable
{
    internal Bitmap Image { get; }
    internal PointF Hotspot { get; }

    private Artwork(Bitmap image, PointF hotspot)
    {
        Image = image;
        Hotspot = hotspot;
    }

    internal static string PathFor(string name) => Path.Combine(AppContext.BaseDirectory, "assets", name + ".png");

    internal static Artwork? Load(string? name, bool pixelated)
    {
        if (name is null || !File.Exists(PathFor(name))) return null;
        using var source = System.Drawing.Image.FromFile(PathFor(name));
        const int maxSize = 440;
        float scale = Math.Min(1f, (float)maxSize / Math.Max(source.Width, source.Height));
        int width = Math.Max(1, (int)MathF.Round(source.Width * scale));
        int height = Math.Max(1, (int)MathF.Round(source.Height * scale));
        using var sample = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(sample))
        {
            graphics.InterpolationMode = pixelated ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.Half;
            graphics.CompositingMode = CompositingMode.SourceCopy;
            graphics.DrawImage(source, new Rectangle(0, 0, width, height), 0, 0, source.Width, source.Height, GraphicsUnit.Pixel);
        }

        int left = width, right = -1, top = height, bottom = -1;
        int tipY = -1, tipLeft = width, tipRight = -1;
        var data = sample.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var row = new byte[width * 4];
            for (int y = 0; y < height; y++)
            {
                Marshal.Copy(data.Scan0 + y * data.Stride, row, 0, row.Length);
                for (int x = 0; x < width; x++)
                {
                    int alpha = row[x * 4 + 3];
                    if (alpha > 38)
                    {
                        left = Math.Min(left, x);
                        right = Math.Max(right, x);
                        top = Math.Min(top, y);
                        bottom = Math.Max(bottom, y);
                    }
                    if (alpha < 150 || (tipY >= 0 && tipY != y) || (name == "hand_bongo_cat" && x >= width * 0.27f)) continue;
                    tipY = y;
                    tipLeft = Math.Min(tipLeft, x);
                    tipRight = Math.Max(tipRight, x);
                }
            }
        }
        finally { sample.UnlockBits(data); }
        if (right < left) return null;

        var crop = Rectangle.Intersect(new Rectangle(0, 0, width, height),
            Rectangle.FromLTRB(left - 2, top - 2, right + 3, bottom + 3));
        var image = sample.Clone(crop, PixelFormat.Format32bppPArgb);
        var tip = new PointF(tipY < 0 ? image.Width / 2f : (tipLeft + tipRight + 1) / 2f - crop.X,
            tipY < 0 ? 0 : tipY + 0.5f - crop.Y);
        return new Artwork(image, tip);
    }

    public void Dispose() => Image.Dispose();
}

using System.Buffers.Binary;

namespace PlayPointer.Windows;

internal static class CustomPointers
{
    internal const string Group = "Свои указатели";
    internal const int MaxSide = 4096;
    internal const int MaxMegabytes = 16;
    private const string Prefix = "custom:";
    private const int MaxTitleLength = 48;
    private const string ImageFile = "pointer.png";
    private const string TitleFile = "title.txt";

    private static string Root => Path.Combine(Settings.DataDirectory, "Pointers");

    internal static string? ImagePath(string asset)
    {
        if (!asset.StartsWith(Prefix, StringComparison.Ordinal)
            || !Guid.TryParseExact(asset[Prefix.Length..], "N", out var id))
            return null;
        return Path.Combine(Root, id.ToString("N"), ImageFile);
    }

    internal static IReadOnlyList<PointerStyle> Load()
    {
        var styles = new List<PointerStyle>();
        try
        {
            foreach (string folder in Directory.EnumerateDirectories(Root))
            {
                if (!Guid.TryParseExact(Path.GetFileName(folder), "N", out var id)) continue;
                string image = Path.Combine(folder, ImageFile);
                string title = Path.Combine(folder, TitleFile);
                try
                {
                    if (!File.Exists(image) || new FileInfo(title).Length > 512) continue;
                    styles.Add(CreateStyle(id, NormalizeTitle(File.ReadAllText(title))));
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return styles.OrderBy(style => style.Title, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    internal static PointerStyle Import(string path, string idea)
    {
        string title = NormalizeTitle(string.IsNullOrWhiteSpace(idea) ? Path.GetFileNameWithoutExtension(path) : idea);
        using var input = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        using (Artwork.LoadCustom(input)) { }
        input.Position = 0;

        var id = Guid.NewGuid();
        string root = Root;
        string name = id.ToString("N");
        string staging = Path.Combine(root, name + ".tmp");
        Directory.CreateDirectory(staging);
        try
        {
            using (var output = File.Open(Path.Combine(staging, ImageFile), FileMode.CreateNew, FileAccess.Write, FileShare.None))
                input.CopyTo(output);
            File.WriteAllText(Path.Combine(staging, TitleFile), title);
            Directory.Move(staging, Path.Combine(root, name));
        }
        finally
        {
            try { Directory.Delete(staging, recursive: true); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return CreateStyle(id, title);
    }

    internal static Size ReadPngSize(Stream input)
    {
        if (input.Length > MaxMegabytes * 1024L * 1024L)
            throw new InvalidDataException($"Размер файла превышает {MaxMegabytes} МБ. Выберите PNG поменьше.");

        ReadOnlySpan<byte> signature = [137, 80, 78, 71, 13, 10, 26, 10];
        Span<byte> header = stackalloc byte[33];
        if (input.ReadAtLeast(header, header.Length, false) != header.Length
            || !header[..8].SequenceEqual(signature)
            || BinaryPrimitives.ReadUInt32BigEndian(header[8..12]) != 13
            || !header[12..16].SequenceEqual("IHDR"u8)
            || BinaryPrimitives.ReadUInt32BigEndian(header[29..]) != PngCrc(header[12..29]))
            throw new InvalidDataException("Не удалось прочитать PNG. Скачайте исходный файл или выберите другой PNG.");

        uint width = BinaryPrimitives.ReadUInt32BigEndian(header[16..20]);
        uint height = BinaryPrimitives.ReadUInt32BigEndian(header[20..24]);
        if (width is < 8 or > MaxSide || height is < 8 or > MaxSide)
            throw new InvalidDataException($"Ширина и высота PNG должны быть от 8 до {MaxSide} пикселей.");

        ReadOnlySpan<byte> iend = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
        Span<byte> tail = stackalloc byte[12];
        input.Seek(-tail.Length, SeekOrigin.End);
        input.ReadExactly(tail);
        if (!tail.SequenceEqual(iend))
            throw new InvalidDataException("Файл PNG повреждён или скачался не полностью. Скачайте его заново.");

        input.Position = 0;
        return new Size((int)width, (int)height);
    }

    private static uint PngCrc(ReadOnlySpan<byte> chunk)
    {
        uint crc = uint.MaxValue;
        foreach (byte value in chunk)
        {
            crc ^= value;
            for (int bit = 0; bit < 8; bit++)
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320u : 0);
        }
        return ~crc;
    }

    private static PointerStyle CreateStyle(Guid id, string title)
    {
        string asset = Prefix + id.ToString("N");
        return new PointerStyle(asset, title, Group, asset, 0x7E79E8, PointerKind.Standard, false);
    }

    private static string NormalizeTitle(string text)
    {
        string title = string.Concat(text.Where(character => !char.IsControl(character))).Trim();
        if (title.Length > MaxTitleLength)
        {
            int length = char.IsHighSurrogate(title[MaxTitleLength - 1]) ? MaxTitleLength - 1 : MaxTitleLength;
            title = title[..length].TrimEnd();
        }
        return title.Length == 0 ? "Свой указатель" : title;
    }
}

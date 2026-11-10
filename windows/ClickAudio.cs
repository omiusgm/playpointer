namespace PlayPointer.Windows;

internal static class ClickAudio
{
    internal const string Standard = "tap_thock.wav";

    // The buffers stay pinned and reachable for the lifetime of asynchronous WinMM playback.
    private static readonly Dictionary<string, byte[]> clips = LoadClips();

    internal static void Warm() => _ = clips.Count;

    internal static unsafe void Play(string name)
    {
        if (!clips.TryGetValue(name, out var bytes)) return;
        fixed (byte* wave = bytes)
            Native.PlaySound((nint)wave, 0, Native.SndMemory | Native.SndAsync | Native.SndNoDefault);
    }

    internal static void Stop() => Native.PlaySound(0, 0, 0);

    private static Dictionary<string, byte[]> LoadClips()
    {
        string[] names = [Standard, "tap_squeak.wav", "tap_magic.wav", "tap_bongo_left.wav", "tap_bongo_right.wav"];
        var result = new Dictionary<string, byte[]>(names.Length);
        foreach (string name in names)
        {
            try
            {
                string path = Path.Combine(AppContext.BaseDirectory, "assets", "sounds", name);
                byte[] data = File.ReadAllBytes(path);
                var pinned = GC.AllocateUninitializedArray<byte>(data.Length, pinned: true);
                data.CopyTo(pinned, 0);
                result.Add(name, pinned);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return result;
    }
}

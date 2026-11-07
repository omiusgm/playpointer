using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text.Json;
using Timer = System.Windows.Forms.Timer;

namespace PlayPointer.Windows;

internal enum PointerMode { Off, Control, Draw }

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var singleInstance = new Mutex(true, @"Local\PlayPointer.Windows", out bool created);
        if (!created)
        {
            MessageBox.Show("PlayPointer уже запущен. Откройте его значок рядом с часами.", "PlayPointer", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        using var app = new PlayPointerContext();
        Application.Run(app);
    }
}

internal sealed record Settings(string Style = "lavender", bool Sound = true, bool Motion = true)
{
    private static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PlayPointer", "preferences.json");

    internal static Settings Load()
    {
        try { return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new Settings(); }
    }

    internal void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(this));
            File.Move(temp, FilePath, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}

internal sealed class PlayPointerContext : ApplicationContext
{
    private readonly Timer timer = new() { Interval = 15 };
    private readonly HotkeyWindow hotkeys;
    private readonly ControlPanel panel;
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu = new();
    private readonly ToolStripMenuItem controlItem, drawItem, stopItem, clearItem;
    private readonly Icon icon;
    private readonly InkCanvas canvas = new();
    private readonly List<DrawInputWindow> inputWindows = [];
    private Settings settings = Settings.Load();
    private PointerStyle style;
    private PointerSprite? sprite;
    private PointerMode mode;
    private CatalogWindow? catalog;
    private Screen[] screens = [];
    private Rectangle lastScreen;
    private Point? inkPoint;
    private bool inputShown, primary, secondary, menuOpen, dialogOpen, disposed;
    private long rebuildAt;
    private float monitorScale = 1;
    private string? error;
    private int bongoNext;

    internal PlayPointerContext()
    {
        style = PointerCatalog.All.FirstOrDefault(item => item.Id == settings.Style)
            ?? PointerCatalog.All.FirstOrDefault(item => item.Id == "lavender") ?? PointerCatalog.Laser;
        using (var iconStream = typeof(Program).Assembly.GetManifestResourceStream("PlayPointer.Windows.PlayPointer.ico"))
        {
            if (iconStream is null) icon = (Icon)SystemIcons.Application.Clone();
            else
            {
                using var source = new Icon(iconStream);
                icon = (Icon)source.Clone();
            }
        }
        hotkeys = new HotkeyWindow(OnHotkey, DisplayChanged);
        panel = new ControlPanel(this, icon, settings);
        panel.VisibleChanged += (_, _) =>
        {
            if (!disposed && !panel.Visible && mode == PointerMode.Draw) SetMode(PointerMode.Control);
        };
        panel.FormClosed += (_, e) => { if (e.CloseReason == CloseReason.WindowsShutDown) ExitThread(); };
        AddMenu("Открыть панель", ShowPanel);
        AddMenu("Каталог указателей…", ShowCatalog);
        menu.Items.Add(new ToolStripSeparator());
        controlItem = AddMenu("Управление", () => SetMode(PointerMode.Control));
        drawItem = AddMenu("Рисование", () => SetMode(PointerMode.Draw));
        clearItem = AddMenu("Стереть рисунок", Clear);
        stopItem = AddMenu("Выключить указатель", () => SetMode(PointerMode.Off));
        menu.Items.Add(new ToolStripSeparator());
        AddMenu("Завершить PlayPointer", ExitThread);
        menu.Opening += (_, _) => { menuOpen = true; PauseInput(); };
        menu.Closed += (_, _) => menuOpen = false;
        tray = new NotifyIcon { Icon = icon, ContextMenuStrip = menu, Visible = true };
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowPanel(); };
        timer.Tick += (_, _) => Tick();
        ShowPanel();
        UpdateUi();
    }

    private ToolStripMenuItem AddMenu(string text, Action action)
    {
        var item = new ToolStripMenuItem(text);
        item.Click += (_, _) => action();
        menu.Items.Add(item);
        return item;
    }

    internal void SetMode(PointerMode next)
    {
        if (mode == next) return;
        try
        {
            error = null;
            if (next == PointerMode.Off)
            {
                Disable();
            }
            else
            {
                if (mode == PointerMode.Off)
                {
                    SetScreens();
                    sprite = new PointerSprite();
                    sprite.SetStyle(style);
                    ReadButtons();
                }
                if (next == PointerMode.Draw)
                {
                    // Keep the panel within reach even if a shortcut could not be registered.
                    if (!panel.Visible) panel.Show();
                    MakeInput();
                }
                else RemoveInput();
                mode = next;
                timer.Start();
                Tick();
            }
            UpdateUi();
        }
        catch (Exception e) when (OverlayError(e)) { Fail(e); }
    }

    internal void Clear()
    {
        canvas.Clear();
        inkPoint = null;
    }

    internal void SetSound(bool enabled)
    {
        settings = settings with { Sound = enabled };
        settings.Save();
        if (!enabled) Native.PlaySound(null, 0, 0);
    }

    internal void SetMotion(bool enabled)
    {
        settings = settings with { Motion = enabled };
        settings.Save();
        sprite?.Reset();
    }

    internal void ShowCatalog()
    {
        PauseInput();
        sprite?.Reset();
        if (catalog is not null) { catalog.Activate(); return; }
        catalog = new CatalogWindow(style, SelectStyle, icon);
        catalog.FormClosed += (_, _) => catalog = null;
        catalog.Show();
        catalog.Activate();
    }

    internal void ShowAbout()
    {
        dialogOpen = true;
        PauseInput();
        sprite?.Reset();
        try
        {
            MessageBox.Show(panel,
                "PlayPointer · предварительная версия для Windows 11 x64\n\nАвтор PlayPointer: Владимир Кривошеев.\nНа основе TinyHand Камрана Ахмеда, лицензия MIT.\n\nБлог и обратная связь: t.me/Krivosheevblog",
                "О программе", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        finally { dialogOpen = false; }
    }

    private void SelectStyle(PointerStyle next)
    {
        try
        {
            sprite?.SetStyle(next);
            style = next;
            bongoNext = 0;
            settings = settings with { Style = next.Id };
            settings.Save();
            error = null;
            UpdateUi();
        }
        catch (Exception e) when (OverlayError(e)) { Fail(e); }
    }

    private void ShowPanel()
    {
        if (!panel.Visible) panel.Show();
        if (panel.WindowState == FormWindowState.Minimized) panel.WindowState = FormWindowState.Normal;
        RaisePanel();
        panel.Activate();
    }

    private void RaisePanel()
    {
        if (panel.Visible)
            Native.SetWindowPos(panel.Handle, -1, 0, 0, 0, 0, Native.SwpNoMove | Native.SwpNoSize | Native.SwpNoActivate);
    }

    private void SetScreens()
    {
        screens = Screen.AllScreens;
        var work = screens.Select(screen => screen.WorkingArea).Where(area => area.Width > 0 && area.Height > 0).Distinct();
        canvas.SetScreens(work);
        lastScreen = Rectangle.Empty;
        inkPoint = null;
    }

    private void MakeInput()
    {
        foreach (var area in screens.Select(s => s.WorkingArea).Where(r => r.Width > 0 && r.Height > 0).Distinct())
            inputWindows.Add(new DrawInputWindow(area, OnDrawMouse));
        if (inputWindows.Count == 0) throw new InvalidOperationException("Не найден экран для рисования.");
    }

    private void ResumeInput()
    {
        if (inputShown) return;
        foreach (var window in inputWindows) window.ShowLayer();
        inputShown = true;
        sprite?.Raise();
        RaisePanel();
    }

    private void PauseInput()
    {
        inkPoint = null;
        if (!inputShown) return;
        foreach (var window in inputWindows) window.HideLayer();
        inputShown = false;
    }

    private void RemoveInput()
    {
        PauseInput();
        foreach (var window in inputWindows) window.Dispose();
        inputWindows.Clear();
    }

    private void Tick()
    {
        if (sprite is null) return;
        try
        {
            long now = Environment.TickCount64;
            if (rebuildAt != 0 && now >= rebuildAt)
            {
                rebuildAt = 0;
                RemoveInput();
                SetScreens();
                sprite.Reset();
                if (mode == PointerMode.Draw) MakeInput();
            }
            if (!Native.GetCursorPos(out var position))
            {
                PauseInput();
                sprite.Reset();
                ReadButtons();
                return;
            }
            Point cursor = position.DrawingPoint;
            var screen = screens.FirstOrDefault(s => s.Bounds.Contains(cursor));
            if (screen is null)
            {
                PauseInput();
                sprite.Reset();
                ReadButtons();
                return;
            }
            if (lastScreen != screen.Bounds)
            {
                lastScreen = screen.Bounds;
                monitorScale = hotkeys.MeasureScale(lastScreen);
            }

            bool uiBusy = menuOpen || dialogOpen || catalog is not null;
            if (uiBusy || mode != PointerMode.Draw || Native.KeyDown(Native.VkMenu)) PauseInput();
            else ResumeInput();
            bool overPanel = panel.Visible && panel.WindowState != FormWindowState.Minimized && panel.Bounds.Contains(cursor);
            bool wasPrimary = primary, wasSecondary = secondary;
            ReadButtons();
            if (!primary || overPanel || !screen.WorkingArea.Contains(cursor)) inkPoint = null;
            bool pointerVisible = !uiBusy && !overPanel;
            if (pointerVisible)
            {
                if (!inputShown && ((!wasPrimary && primary) || (!wasSecondary && secondary)))
                    React(cursor, now, !wasPrimary && primary);
                else if (inputShown && !wasSecondary && secondary && style.Kind != PointerKind.Bongo)
                    React(cursor, now, false);
                sprite.Render(cursor, screen.Bounds, monitorScale, now, !settings.Motion || !SystemInformation.UIEffectsEnabled);
            }
            else sprite.Reset();
            bool addedInk = false;
            foreach (var tile in canvas.Tiles)
            {
                if (!tile.Dirty) continue;
                tile.Present();
                addedInk = true;
            }
            if (addedInk) sprite.Raise();
        }
        catch (Exception e) when (OverlayError(e)) { Fail(e); }
    }

    private void ReadButtons()
    {
        bool swapped = Native.GetSystemMetrics(Native.SmSwapButton) != 0;
        primary = Native.KeyDown(swapped ? Native.VkRButton : Native.VkLButton);
        secondary = Native.KeyDown(swapped ? Native.VkLButton : Native.VkRButton);
    }

    private void OnDrawMouse(int message, Point cursor, bool primaryHeld)
    {
        if (!inputShown || mode != PointerMode.Draw || Native.KeyDown(Native.VkMenu)) return;
        try
        {
            if (message == Native.WmLeftDown)
            {
                inkPoint = cursor;
                canvas.Add(cursor, cursor, style.Color, 5 * monitorScale);
                React(cursor, Environment.TickCount64, true);
                return;
            }
            if (message == Native.WmMouseMove && !primaryHeld)
            {
                inkPoint = null;
                return;
            }
            if (inkPoint is Point previous && previous != cursor)
            {
                int dx = previous.X - cursor.X, dy = previous.Y - cursor.Y;
                if ((long)dx * dx + (long)dy * dy <= 400 * 400 * monitorScale * monitorScale)
                    canvas.Add(previous, cursor, style.Color, 5 * monitorScale);
                else inkPoint = null;
            }
            if (message == Native.WmLeftUp) inkPoint = null;
            else if (inkPoint is not null) inkPoint = cursor;
        }
        catch (Exception e) when (OverlayError(e))
        {
            // Defer destruction until this input window has returned from WndProc.
            PauseInput();
            panel.BeginInvoke(() => Fail(e));
        }
    }

    private void React(Point cursor, long now, bool primaryButton)
    {
        int reaction = 0;
        if (style.Kind == PointerKind.Bongo)
        {
            if (!primaryButton) return;
            reaction = bongoNext;
            bongoNext ^= 1;
        }
        sprite?.Pulse(cursor, now, reaction);
        if (!settings.Sound) return;
        string sound = style.Kind switch
        {
            PointerKind.Bongo => reaction == 0 ? "tap_bongo_left.wav" : "tap_bongo_right.wav",
            PointerKind.Wand => "tap_magic.wav",
            _ when style.Id == "squeaky" => "tap_squeak.wav",
            _ => "tap_click.wav"
        };
        var path = Path.Combine(AppContext.BaseDirectory, "assets", "sounds", sound);
        if (File.Exists(path)) Native.PlaySound(path, 0, Native.SndFileName | Native.SndAsync | Native.SndNoDefault);
    }

    private void DisplayChanged() => rebuildAt = Environment.TickCount64 + 150;

    private void OnHotkey(int action)
    {
        switch (action)
        {
            case 1: SetMode(mode == PointerMode.Off ? PointerMode.Control : PointerMode.Off); break;
            case 2: SetMode(mode == PointerMode.Draw ? PointerMode.Control : PointerMode.Draw); break;
            case 3: Clear(); break;
            case 4: SetMode(PointerMode.Off); break;
        }
    }

    private void UpdateUi()
    {
        panel.UpdateState(mode, style, hotkeys.Description, error);
        controlItem.Checked = mode == PointerMode.Control;
        drawItem.Checked = mode == PointerMode.Draw;
        clearItem.Enabled = stopItem.Enabled = mode != PointerMode.Off;
        tray.Text = "PlayPointer · " + (mode switch
        {
            PointerMode.Control => "Управление",
            PointerMode.Draw => "Рисование",
            _ => "Выключен"
        });
    }

    private void Disable()
    {
        mode = PointerMode.Off;
        timer.Stop();
        RemoveInput();
        Clear();
        sprite?.Dispose();
        sprite = null;
        Native.PlaySound(null, 0, 0);
    }

    private void Fail(Exception exception)
    {
        Disable();
        error = exception is Win32Exception or InvalidOperationException
            ? exception.Message : "Не удалось запустить слой или загрузить указатель. Указатель выключен.";
        ShowPanel();
        UpdateUi();
    }

    private static bool OverlayError(Exception e) => e is Win32Exception or ExternalException or ArgumentException
        or InvalidOperationException or OutOfMemoryException or IOException or UnauthorizedAccessException;

    protected override void ExitThreadCore()
    {
        if (disposed) return;
        disposed = true;
        Disable();
        timer.Dispose();
        tray.Visible = false;
        tray.Dispose();
        menu.Dispose();
        catalog?.Dispose();
        panel.Dispose();
        hotkeys.Dispose();
        canvas.Dispose();
        icon.Dispose();
        base.ExitThreadCore();
    }
}

internal sealed class HotkeyWindow : NativeWindow, IDisposable
{
    private readonly Action<int> onHotkey;
    private readonly Action onDisplayChange;
    private readonly HashSet<int> registered = [];
    private static readonly (int Id, Keys Key, string Label)[] shortcuts =
    [
        (1, Keys.H, "H — вкл./выкл."),
        (2, Keys.D, "D — сменить режим"),
        (3, Keys.X, "X — стереть"),
        (4, Keys.Escape, "Esc — выключить")
    ];

    internal HotkeyWindow(Action<int> onHotkey, Action onDisplayChange)
    {
        this.onHotkey = onHotkey;
        this.onDisplayChange = onDisplayChange;
        CreateHandle(new CreateParams { Caption = "PlayPointer hotkeys", Style = Native.Popup,
            ExStyle = Native.NoActivate | Native.ToolWindow, Width = 1, Height = 1 });
        foreach (var shortcut in shortcuts)
        {
            if (Native.RegisterHotKey(Handle, shortcut.Id, Native.ModControl | Native.ModAlt | Native.ModNoRepeat, (uint)shortcut.Key))
                registered.Add(shortcut.Id);
        }
    }

    internal string Description
    {
        get
        {
            string available = registered.Count == 0 ? "Горячие клавиши недоступны. Используйте панель или значок рядом с часами."
                : "Ctrl+Alt + " + string.Join(", ", shortcuts.Where(item => registered.Contains(item.Id)).Select(item => item.Label));
            return registered.Count is > 0 and < 4 ? available + ". Остальные сочетания заняты." : available;
        }
    }

    internal float MeasureScale(Rectangle monitor)
    {
        const uint noZOrder = 4;
        Native.SetWindowPos(Handle, 0, monitor.Left + monitor.Width / 2, monitor.Top + monitor.Height / 2,
            0, 0, Native.SwpNoSize | Native.SwpNoActivate | noZOrder);
        uint dpi = Native.GetDpiForWindow(Handle);
        return dpi == 0 ? 1 : Math.Clamp(dpi / 96f, 0.75f, 4f);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == Native.WmHotKey)
        {
            onHotkey(unchecked((int)message.WParam));
            return;
        }
        if (message.Msg == Native.WmDisplayChange || (message.Msg == Native.WmSettingChange && message.WParam == 47))
            onDisplayChange();
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        foreach (int id in registered) Native.UnregisterHotKey(Handle, id);
        DestroyHandle();
    }
}

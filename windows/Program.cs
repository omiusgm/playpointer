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
    private bool inputShown, menuOpen, dialogOpen, disposed;
    private long rebuildAt, modeStartedAt;
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
        hotkeys = new HotkeyWindow(OnHotkey, DisplayChanged, OnRawMouseDown);
        ClickAudio.Warm();
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
                }
                if (next == PointerMode.Draw)
                {
                    // Keep the panel within reach even if a shortcut could not be registered.
                    if (!panel.Visible) panel.Show();
                    MakeInput();
                }
                else RemoveInput();
                mode = next;
                modeStartedAt = Environment.TickCount64;
                hotkeys.SetRawMouse(true);
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
        if (!enabled) ClickAudio.Stop();
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
                return;
            }
            Point cursor = position.DrawingPoint;
            var screen = screens.FirstOrDefault(s => s.Bounds.Contains(cursor));
            if (screen is null)
            {
                PauseInput();
                sprite.Reset();
                return;
            }
            if (lastScreen != screen.Bounds)
            {
                lastScreen = screen.Bounds;
                monitorScale = hotkeys.MeasureScale(lastScreen);
            }

            bool uiBusy = UiBusy;
            if (uiBusy || mode != PointerMode.Draw || Native.KeyDown(Native.VkMenu)) PauseInput();
            else ResumeInput();
            bool overPanel = OverPanel(cursor);
            // A release outside our draw windows can finish ink, but polling never creates a click.
            if (inkPoint is not null && (!PrimaryHeld() || overPanel || !screen.WorkingArea.Contains(cursor))) inkPoint = null;
            bool pointerVisible = !uiBusy && !overPanel;
            if (pointerVisible)
            {
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

    private bool UiBusy => menuOpen || dialogOpen || catalog is not null;

    private bool OverPanel(Point cursor) =>
        panel.Visible && panel.WindowState != FormWindowState.Minimized && panel.Bounds.Contains(cursor);

    private static bool ButtonsSwapped => Native.GetSystemMetrics(Native.SmSwapButton) != 0;

    private static bool PrimaryHeld() => Native.KeyDown(ButtonsSwapped ? Native.VkRButton : Native.VkLButton);

    private bool IsCurrentMouseMessage()
    {
        long now = Environment.TickCount64;
        int messageAge = unchecked((int)now - Native.GetMessageTime());
        return messageAge <= now - modeStartedAt;
    }

    private void OnRawMouseDown(ushort buttons, Point cursor)
    {
        if (mode == PointerMode.Off || sprite is null || UiBusy || !IsCurrentMouseMessage()
            || OverPanel(cursor) || !screens.Any(screen => screen.Bounds.Contains(cursor)))
            return;

        bool swapped = ButtonsSwapped;
        bool primary = (buttons & (swapped ? Native.RawRightDown : Native.RawLeftDown)) != 0;
        bool secondary = (buttons & (swapped ? Native.RawLeftDown : Native.RawRightDown)) != 0;
        // The draw windows own primary reactions whenever their input layer is showing.
        // Alt passthrough starts using Raw Input after the draw windows are hidden.
        bool reactToPrimary = primary && !inputShown;
        if (!reactToPrimary && !secondary) return;
        try { React(cursor, Environment.TickCount64, reactToPrimary); }
        catch (Exception e) when (OverlayError(e)) { Fail(e); }
    }

    private void OnDrawMouse(int message, Point cursor, bool primaryHeld)
    {
        if (!inputShown || mode != PointerMode.Draw || Native.KeyDown(Native.VkMenu)) return;
        try
        {
            if (message == Native.WmLeftDown)
            {
                if (!IsCurrentMouseMessage() || UiBusy || OverPanel(cursor)) return;
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
        if (style.Id == "catChaser" && !primaryButton) return;
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
            _ => ClickAudio.Standard
        };
        ClickAudio.Play(sound);
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
        string shortcuts = hotkeys.Description;
        if (mode != PointerMode.Off && !hotkeys.RawMouseRegistered)
            shortcuts += "\nWindows не передаёт фоновые события мыши. Реакция на основную кнопку доступна при рисовании.";
        panel.UpdateState(mode, style, shortcuts, error);
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
        hotkeys.SetRawMouse(false);
        timer.Stop();
        RemoveInput();
        Clear();
        sprite?.Dispose();
        sprite = null;
        ClickAudio.Stop();
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
    private readonly Action<ushort, Point> onRawMouseDown;
    private readonly HashSet<int> registered = [];
    internal bool RawMouseRegistered { get; private set; }
    private static readonly (int Id, Keys Key, string Label)[] shortcuts =
    [
        (1, Keys.H, "H — вкл./выкл."),
        (2, Keys.D, "D — сменить режим"),
        (3, Keys.X, "X — стереть"),
        (4, Keys.Escape, "Esc — выключить")
    ];

    internal HotkeyWindow(Action<int> onHotkey, Action onDisplayChange, Action<ushort, Point> onRawMouseDown)
    {
        this.onHotkey = onHotkey;
        this.onDisplayChange = onDisplayChange;
        this.onRawMouseDown = onRawMouseDown;
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

    internal void SetRawMouse(bool enabled)
    {
        if (RawMouseRegistered != enabled && Native.RegisterRawMouse(Handle, enabled))
            RawMouseRegistered = enabled;
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == Native.WmInput)
        {
            if (RawMouseRegistered)
            {
                ushort buttons = Native.ReadRawMouseDown(message.LParam);
                if (buttons != 0) onRawMouseDown(buttons, Native.MouseMessagePosition());
            }
            base.WndProc(ref message); // DefWindowProc performs the foreground raw-input cleanup.
            return;
        }
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
        SetRawMouse(false);
        foreach (int id in registered) Native.UnregisterHotKey(Handle, id);
        DestroyHandle();
    }
}

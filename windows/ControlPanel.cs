using System.Diagnostics;

namespace PlayPointer.Windows;

internal sealed class ControlPanel : Form
{
    private readonly Label current = new() { AutoSize = true };
    private readonly Label status = new() { AutoSize = true, MaximumSize = new Size(415, 0) };
    private readonly Label hotkeys = new() { AutoSize = true, MaximumSize = new Size(415, 0) };
    private readonly Button control = new() { Text = "Управление", AutoSize = true };
    private readonly Button draw = new() { Text = "Рисование", AutoSize = true };
    private readonly Button stop = new() { Text = "Выключить", AutoSize = true };
    private readonly Button clear = new() { Text = "Стереть рисунок", AutoSize = true };

    internal ControlPanel(PlayPointerContext app, Icon icon, Settings settings)
    {
        Text = "PlayPointer · Windows Preview";
        Icon = icon;
        Font = SystemFonts.MessageBoxFont;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(452, 370);
        MinimumSize = new Size(470, 410);
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        MaximizeBox = false;
        MinimizeBox = false;
        FormBorderStyle = FormBorderStyle.FixedDialog;

        var stack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            Padding = new Padding(16, 13, 14, 8), AutoScroll = true
        };
        Controls.Add(stack);
        var title = new Label { Text = "PlayPointer", AutoSize = true,
            Font = new Font(Font.FontFamily, 24, FontStyle.Bold), Margin = new Padding(3, 0, 3, 2) };
        stack.Controls.Add(title);
        stack.Controls.Add(new Label
        {
            Text = "Предварительная версия для Windows 11 x64", AutoSize = true, Margin = new Padding(3, 0, 3, 14)
        });
        control.Click += (_, _) => app.SetMode(PointerMode.Control);
        draw.Click += (_, _) => app.SetMode(PointerMode.Draw);
        stop.Click += (_, _) => app.SetMode(PointerMode.Off);
        clear.Click += (_, _) => app.Clear();
        stack.Controls.Add(Row(control, draw, stop));
        status.Margin = new Padding(3, 6, 3, 10);
        stack.Controls.Add(status);

        var catalog = new Button { Text = "Каталог указателей…", AutoSize = true };
        catalog.Click += (_, _) => app.ShowCatalog();
        stack.Controls.Add(Row(catalog, clear));
        current.Margin = new Padding(3, 6, 3, 12);
        stack.Controls.Add(current);
        var sound = new CheckBox { Text = "Звуки нажатий", Checked = settings.Sound, AutoSize = true };
        var motion = new CheckBox { Text = "Анимация и следы", Checked = settings.Motion, AutoSize = true };
        sound.CheckedChanged += (_, _) => app.SetSound(sound.Checked);
        motion.CheckedChanged += (_, _) => app.SetMotion(motion.Checked);
        stack.Controls.Add(Row(sound, motion));
        hotkeys.Margin = new Padding(3, 10, 3, 10);
        stack.Controls.Add(hotkeys);

        var report = new LinkLabel { Text = "Сообщить об ошибке", AutoSize = true, Margin = new Padding(3, 6, 10, 3) };
        report.LinkClicked += (_, _) => OpenBlog(this);
        var about = new LinkLabel { Text = "О программе", AutoSize = true, Margin = new Padding(3, 6, 3, 3) };
        about.LinkClicked += (_, _) => app.ShowAbout();
        stack.Controls.Add(Row(report, about));
        var trayHint = new Label { Text = "Закрытие панели оставляет PlayPointer рядом с часами.", AutoSize = true, Margin = new Padding(3, 3, 3, 3) };
        stack.Controls.Add(trayHint);
        FormClosing += (_, e) =>
        {
            if (e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            Hide();
        };
    }

    private static FlowLayoutPanel Row(params Control[] controls)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 0, 3) };
        row.Controls.AddRange(controls);
        return row;
    }

    internal void UpdateState(PointerMode mode, PointerStyle style, string shortcuts, string? error)
    {
        control.Enabled = mode != PointerMode.Control;
        draw.Enabled = mode != PointerMode.Draw;
        stop.Enabled = mode != PointerMode.Off;
        clear.Enabled = mode != PointerMode.Off;
        current.Text = $"Указатель: {style.Title}";
        status.Text = error ?? (mode switch
        {
            PointerMode.Control => "Управление: щёлкайте и перетаскивайте как обычно.",
            PointerMode.Draw => "Рисование: нажмите основную кнопку мыши и ведите её. Удерживайте Alt, чтобы временно вернуть управление.",
            _ => "Указатель выключен. Выберите режим выше."
        });
        hotkeys.Text = shortcuts;
    }

    internal static void OpenBlog(IWin32Window? owner)
    {
        const string blog = "https://t.me/Krivosheevblog";
        try { Process.Start(new ProcessStartInfo(blog) { UseShellExecute = true }); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            MessageBox.Show(owner, $"Не удалось открыть браузер. Адрес блога: {blog}", "PlayPointer", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}

internal sealed class CatalogWindow : Form
{
    private readonly ListBox list = new() { Dock = DockStyle.Fill, IntegralHeight = false, DisplayMember = nameof(PointerStyle.Title) };
    private readonly ComboBox category = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 230 };
    private readonly TextBox search = new() { Width = 230, PlaceholderText = "Найти указатель" };
    private readonly PictureBox preview = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, AccessibleName = "Образец указателя" };
    private readonly Button choose = new() { Text = "Выбрать", AutoSize = true };
    private Artwork? artwork;

    internal CatalogWindow(PointerStyle selected, Action<PointerStyle> onChoose, Icon icon)
    {
        Text = "Каталог указателей · PlayPointer";
        Icon = icon;
        Font = SystemFonts.MessageBoxFont;
        AutoScaleMode = AutoScaleMode.Dpi;
        TopMost = true;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(560, 405);
        MinimumSize = new Size(485, 350);
        MaximizeBox = false;
        AccessibleDescription = "Выберите категорию и указатель, чтобы посмотреть образец.";
        category.AccessibleName = "Категория";
        search.AccessibleName = "Поиск по названию";
        list.AccessibleName = "Указатели";
        category.Items.AddRange(["Все указатели", PointerCatalog.Cats, PointerCatalog.Fun, PointerCatalog.Hands, PointerCatalog.Basic]);
        category.SelectedIndex = 0;

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(12), ColumnCount = 2, RowCount = 3 };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 49));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 51));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var filters = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        filters.Controls.AddRange([category, search]);
        var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill };
        var close = new Button { Text = "Закрыть", AutoSize = true, DialogResult = DialogResult.Cancel };
        close.Click += (_, _) => Close();
        buttons.Controls.AddRange([choose, close]);
        root.Controls.Add(filters, 0, 0);
        root.SetColumnSpan(filters, 2);
        root.Controls.Add(list, 0, 1);
        root.Controls.Add(preview, 1, 1);
        root.Controls.Add(buttons, 0, 2);
        root.SetColumnSpan(buttons, 2);
        Controls.Add(root);
        CancelButton = close;
        AcceptButton = choose;
        choose.Click += (_, _) => Pick();
        list.DoubleClick += (_, _) => Pick();
        list.SelectedIndexChanged += (_, _) => ShowPreview();
        category.SelectedIndexChanged += (_, _) => Fill();
        search.TextChanged += (_, _) => Fill();
        Fill(selected);

        void Pick()
        {
            if (list.SelectedItem is not PointerStyle item) return;
            onChoose(item);
            Close();
        }
    }

    private void Fill(PointerStyle? selection = null)
    {
        selection ??= list.SelectedItem as PointerStyle;
        var options = PointerCatalog.All.Where(style => (category.SelectedIndex == 0 || style.Group == (string?)category.SelectedItem)
            && style.Title.Contains(search.Text.Trim(), StringComparison.CurrentCultureIgnoreCase)).ToArray();
        list.BeginUpdate();
        try
        {
            list.Items.Clear();
            list.Items.AddRange(options);
            list.SelectedIndex = selection is null ? -1 : Array.IndexOf(options, selection);
            if (list.SelectedIndex < 0 && options.Length > 0) list.SelectedIndex = 0;
        }
        finally { list.EndUpdate(); }
        choose.Enabled = options.Length > 0;
    }

    private void ShowPreview()
    {
        ReleasePreview();
        if (list.SelectedItem is not PointerStyle style) return;
        if (style.Asset is null)
        {
            var image = new Bitmap(100, 100);
            using var g = Graphics.FromImage(image);
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var brush = new SolidBrush(style.Color);
            g.FillEllipse(brush, 42, 42, 16, 16);
            preview.Image = image;
            return;
        }
        try
        {
            artwork = Artwork.Load(style.Asset, style.Pixelated);
            preview.Image = artwork?.Image;
        }
        catch (Exception e) when (e is IOException or ArgumentException or OutOfMemoryException or System.Runtime.InteropServices.ExternalException) { }
    }

    private void ReleasePreview()
    {
        var previous = preview.Image;
        preview.Image = null;
        if (artwork is not null) artwork.Dispose();
        else previous?.Dispose();
        artwork = null;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) ReleasePreview();
        base.Dispose(disposing);
    }
}

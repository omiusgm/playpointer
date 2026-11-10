using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PlayPointer.Windows;

internal sealed class CustomPointerDialog : Form
{
    private readonly TextBox idea = new()
    {
        Dock = DockStyle.Top, MaxLength = 180, PlaceholderText = "Например, маленькая ракета из фетра",
        AccessibleName = "Идея указателя"
    };

    private readonly Label status = new()
    {
        AutoSize = true, MaximumSize = new Size(460, 0), Visible = false,
        LiveSetting = System.Windows.Forms.Automation.AutomationLiveSetting.Polite
    };
    internal PointerStyle? AddedPointer { get; private set; }

    internal CustomPointerDialog(Icon icon)
    {
        Text = "Свой указатель · PlayPointer";
        Icon = icon;
        Font = SystemFonts.MessageBoxFont;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(498, 302);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;

        var body = new TableLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, ColumnCount = 1, Padding = new Padding(16) };
        body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Controls.Add(body);

        var header = Label("Свой указатель");
        header.Font = new Font(Font.FontFamily, 17, FontStyle.Bold);
        body.Controls.Add(header);
        body.Controls.Add(Label("Опишите наконечник для ChatGPT или добавьте готовый PNG."));
        body.Controls.Add(Label("Идея указателя"));
        body.Controls.Add(idea);

        var copy = new Button { Text = "Скопировать запрос", AutoSize = true };
        var open = new Button { Text = "Открыть ChatGPT", AutoSize = true };
        copy.Click += (_, _) => CopyPrompt();
        open.Click += (_, _) => OpenChatGpt();
        body.Controls.Add(ButtonRow(copy, open));
        body.Controls.Add(Label("Вставьте скопированный запрос в чат и скачайте готовое изображение."));
        body.Controls.Add(Label($"Подойдёт PNG с прозрачным фоном до {CustomPointers.MaxSide} × {CustomPointers.MaxSide} пикселей и {CustomPointers.MaxMegabytes} МБ."));
        body.Controls.Add(status);

        var import = new Button { Text = "Выбрать PNG…", AutoSize = true };
        var cancel = new Button { Text = "Отмена", AutoSize = true, DialogResult = DialogResult.Cancel };
        import.Click += (_, _) => Import();
        body.Controls.Add(ButtonRow(import, cancel));
        CancelButton = cancel;
        AcceptButton = import;
    }

    internal static string BuildPrompt(string text)
    {
        string idea = string.IsNullOrWhiteSpace(text) ? "маленькая ракета из фетра" : text.Trim();
        return $"""
            Создай PNG с одним объектом для наконечника указателя PlayPointer.
            Тема изображения — {idea}.

            Размести объект вертикально по центру. Сделай один чёткий кончик в самой верхней части объекта. Покажи объект целиком и оставь прозрачный отступ со всех сторон, чтобы края не были обрезаны.
            Фон должен быть действительно прозрачным (альфа-канал PNG). Не рисуй палку, подставку, тень на фоне, рамку, текст, шахматку или любой другой фон. Нужен один готовый PNG.
            """;
    }

    private bool CopyPrompt()
    {
        try
        {
            Clipboard.SetText(BuildPrompt(idea.Text));
            SetStatus("Запрос скопирован. Откройте ChatGPT и вставьте его в чат.");
            return true;
        }
        catch (ExternalException)
        {
            SetStatus("Не удалось скопировать запрос. Попробуйте ещё раз.");
            return false;
        }
    }

    private void OpenChatGpt()
    {
        if (!CopyPrompt()) return;
        try
        {
            using var browser = Process.Start(new ProcessStartInfo("https://chatgpt.com/") { UseShellExecute = true });
            SetStatus("Вставьте скопированный запрос в чат и отправьте его.");
        }
        catch (Exception e) when (e is Win32Exception or InvalidOperationException)
        {
            SetStatus("Не удалось открыть браузер. Откройте chatgpt.com и вставьте запрос вручную.");
        }
    }

    private void Import()
    {
        using var picker = new OpenFileDialog
        {
            Title = "Выберите PNG своего указателя", Filter = "PNG-изображения (*.png)|*.png",
            CheckFileExists = true, Multiselect = false, RestoreDirectory = true
        };
        if (picker.ShowDialog(this) != DialogResult.OK) return;

        try
        {
            AddedPointer = PointerCatalog.Import(picker.FileName, idea.Text);
            DialogResult = DialogResult.OK;
        }
        catch (InvalidDataException e) { SetStatus(e.Message); }
        catch (UnauthorizedAccessException) { SetStatus("Нет доступа к PNG или папке PlayPointer. Проверьте разрешения."); }
        catch (IOException) { SetStatus("Не удалось прочитать или сохранить PNG. Проверьте доступ к файлу и свободное место."); }
        catch (Exception e) when (e is ArgumentException or ExternalException or OutOfMemoryException)
        {
            SetStatus("Не удалось прочитать PNG. Скачайте исходный файл или выберите другой PNG.");
        }
    }

    private void SetStatus(string message)
    {
        status.Visible = true;
        status.Text = message;
    }

    private static Label Label(string text) => new()
    {
        Text = text, AutoSize = true, MaximumSize = new Size(460, 0), Margin = new Padding(3, 3, 3, 5)
    };

    private static FlowLayoutPanel ButtonRow(params Control[] buttons)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 3, 0, 3) };
        row.Controls.AddRange(buttons);
        return row;
    }
}

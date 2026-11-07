import AppKit
import ApplicationServices
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, pointers, appearance, drawing, sound, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Основные"
        case .pointers: return "Указатели"
        case .appearance: return "Внешний вид"
        case .drawing: return "Рисование"
        case .sound: return "Звук"
        case .about: return "О программе"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .pointers: return "hand.point.up.left.fill"
        case .appearance: return "sparkles"
        case .drawing: return "pencil.tip"
        case .sound: return "speaker.wave.2.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(white: 0.55)
        case .pointers: return Color(red: 0.55, green: 0.42, blue: 0.95)
        case .appearance: return Color(red: 0.95, green: 0.45, blue: 0.6)
        case .drawing: return Color(red: 0.96, green: 0.58, blue: 0.2)
        case .sound: return Color(red: 0.2, green: 0.55, blue: 0.98)
        case .about: return Color(white: 0.45)
        }
    }
}

final class SettingsModel: ObservableObject {
    @Published var section: SettingsSection = .general
    @Published private var revision = 0

    var applyToggleShortcut: ((Shortcut) -> Bool)?
    var applyClearShortcut: ((Shortcut) -> Bool)?
    var applyPointerMode: ((PointerMode) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var updater: Updater?
    @Published var shortcutError: String?

    private var observer: Any?
    private var handsObserver: Any?
    @Published var handMessage: String?

    init() {
        observer = NotificationCenter.default.addObserver(forName: Preferences.changed, object: nil, queue: .main) { [weak self] _ in
            self?.revision += 1
        }
        handsObserver = NotificationCenter.default.addObserver(forName: CustomHands.changed, object: nil, queue: .main) { [weak self] _ in
            self?.revision += 1
        }
        HandAsset.preloadThumbnails(PointerStyle.allCases.compactMap(\.assetName)) { [weak self] in
            self?.revision += 1
        }
    }

    struct HandDraft {
        let image: CGImage
        let ink: UInt32
    }

    @Published var makingHand = false
    @Published var handIdea = ""
    @Published var handName = ""
    @Published var draft: HandDraft?
    @Published var draftError: String?
    @Published var promptCopied = false

    func startMakingHand() {
        draft = nil
        draftError = nil
        promptCopied = false
        handMessage = nil
        makingHand = true
    }

    private var copiedReset: DispatchWorkItem?

    func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HandMaker.prompt(for: handIdea), forType: .string)
        promptCopied = true
        copiedReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in self?.promptCopied = false }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: reset)
    }

    func openChatGPT() {
        var parts = URLComponents(string: "https://chatgpt.com/")
        parts?.queryItems = [URLQueryItem(name: "q", value: HandMaker.prompt(for: handIdea))]
        if let url = parts?.url {
            NSWorkspace.shared.open(url)
        }
    }

    func chooseHandFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .webP, .image]
        panel.allowsMultipleSelection = false
        panel.message = "Выберите PNG с изображением руки"
        panel.prompt = "Выбрать"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        loadDraft(url)
    }

    func loadDraft(_ url: URL) {
        do {
            let made = try HandMaker.make(from: url)
            draft = HandDraft(image: made.image, ink: made.ink)
            draftError = nil
            handName = CustomHands.suggestedName(for: url)
        } catch let problem as HandMaker.Problem {
            draft = nil
            draftError = problem.message
        } catch {
            draft = nil
            draftError = "Не удалось открыть файл."
        }
    }

    func saveDraft() {
        guard let draft = draft else {
            return
        }
        do {
            let style = try CustomHands.add(draft.image, ink: draft.ink, name: handName)
            if let name = style.assetName {
                _ = HandAsset.thumbnail(name)
            }
            handMessage = "«\(style.title)» выбран."
            selectPointer(style)
            self.draft = nil
            handIdea = ""
            makingHand = false
        } catch {
            draftError = "Не удалось сохранить указатель."
        }
    }

    func selectPointer(_ style: PointerStyle) {
        PointerStyle.saved = style
        if !Preferences.recordRecentStyle(style) {
            NotificationCenter.default.post(name: Preferences.changed, object: nil)
        }
    }

    func removeHand(_ style: PointerStyle) {
        if PointerStyle.saved == style {
            PointerStyle.saved = .lavender
        }
        CustomHands.remove(style)
        handMessage = nil
        NotificationCenter.default.post(name: Preferences.changed, object: nil)
        revision += 1
    }

    func refresh() {
        revision += 1
    }

    func binding<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { value in
            set(value)
            self.revision += 1
        })
    }

    private var previewSound: TapSound?

    func warmPreview() {
        if previewSound == nil {
            previewSound = TapSound()
        }
        previewSound?.warm()
    }

    func preview(_ choice: TapSoundChoice) {
        if previewSound == nil {
            previewSound = TapSound(choice)
        }
        previewSound?.load(choice)
        previewSound?.play()
    }

    func resetAll() {
        let alert = NSAlert()
        alert.messageText = "Сбросить настройки?"
        alert.informativeText = "Будут восстановлены исходные сочетания клавиш и параметры внешнего вида, рисования и звука. Автозапуск и разрешение универсального доступа сохранятся."
        alert.addButton(withTitle: "Сбросить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Preferences.resetAll()
        _ = applyToggleShortcut?(.toggleDefault)
        _ = applyClearShortcut?(.clearDefault)
        shortcutError = nil
        revision += 1
    }

}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            page
        }
        .ignoresSafeArea()
        .frame(minWidth: 760, minHeight: 540)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                SidebarRow(section: section, selected: model.section == section) {
                    model.section = section
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                }
                Text("PlayPointer").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .padding(.top, 52)
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(VisualEffect(material: .sidebar))
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if model.section == .pointers && model.makingHand {
                    Button {
                        model.makingHand = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            Text(SettingsSection.pointers.title).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.bottom, -14)
                }
                Text(model.section == .pointers && model.makingHand ? "Создать свою руку" : model.section.title)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.top, 6)
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .general: GeneralPage(model: model)
        case .pointers:
            if model.makingHand {
                MakeHandPage(model: model)
            } else {
                PointersPage(model: model)
            }
        case .appearance: AppearancePage(model: model)
        case .drawing: DrawingPage(model: model)
        case .sound: SoundPage(model: model)
        case .about: AboutPage(model: model)
        }
    }
}

private struct GeneralPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !AXIsProcessTrusted() {
                Card(title: "Разрешение") {
                    Row("Доступ для рисования", detail: "Разрешите PlayPointer обрабатывать нажатия мыши для рисования.") {
                        PillButton(title: "Открыть настройки") {
                            WelcomeWindow.openDrawingSettings()
                        }
                    }
                }
            }
            Card(title: "Сочетания клавиш") {
                Row("Включить или выключить указатель") {
                    ShortcutField(shortcut: Preferences.toggleShortcut, model: model) { model.applyToggleShortcut?($0) ?? false }
                }
                Row("Стереть рисунок") {
                    ShortcutField(shortcut: Preferences.clearShortcut, model: model) { model.applyClearShortcut?($0) ?? false }
                }
            }
            if let error = model.shortcutError {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }
            Card(title: "Режим указателя") {
                Row("Режим", detail: Preferences.pointerMode == .control
                    ? "Щёлкайте, перетаскивайте и прокручивайте в приложениях."
                    : "Рисуйте на экране, удерживая кнопку мыши.") {
                    Picker("Режим указателя", selection: model.binding({ Preferences.pointerMode }, { model.applyPointerMode?($0) })) {
                        ForEach(PointerMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .focusable(false)
                }
                Row("Клавиша для работы с приложениями", detail: "Удерживайте при рисовании, чтобы щёлкать и перетаскивать.") {
                    Picker("", selection: model.binding({ Preferences.interactKey }, { Preferences.interactKey = $0 })) {
                        ForEach(InteractKey.allCases, id: \.self) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .focusable(false)
                }
                if Preferences.interactKey != .off {
                    Row("Вид указателя при удержании", detail: Preferences.interactKeepsHand ? "Рука видна и в меню." : "Обычный курсор виден и в меню.") {
                        Picker("", selection: model.binding({ Preferences.interactKeepsHand }, { Preferences.interactKeepsHand = $0 })) {
                            Text("Обычный курсор").tag(false)
                            Text("Рука").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .focusable(false)
                    }
                }
            }
            Card(title: "Автозапуск") {
                Row("Запускать PlayPointer при входе") {
                    Toggle("", isOn: model.binding({ Preferences.launchAtLogin }, { Preferences.launchAtLogin = $0 }))
                        .toggleStyle(.switch).labelsHidden().focusable(false)
                }
                if let updater = model.updater {
                    Row("Проверять обновления автоматически") {
                        Toggle("", isOn: model.binding({ updater.automaticallyChecks }, { updater.automaticallyChecks = $0 }))
                            .toggleStyle(.switch).labelsHidden().focusable(false)
                    }
                }
            }
        }
    }
}

private struct PointersPage: View {
    @ObservedObject var model: SettingsModel
    @State private var choosingPointer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Card(title: nil) {
                Row("Текущий указатель", detail: PointerStyle.saved.title) {
                    PillButton(title: "Выбрать указатель…") { choosingPointer = true }
                        .popover(isPresented: $choosingPointer, arrowEdge: .bottom) {
                            PointerCatalog(selected: PointerStyle.saved) { style in
                                model.selectPointer(style)
                                choosingPointer = false
                            }
                        }
                }
            }
            Text("На нижней панели сначала идут недавние указатели. Прокрутите ряд двумя пальцами или нажмите «+», чтобы увидеть остальные.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            YourHands(model: model)
        }
    }
}

/// Shared scrollable pointer catalog.
struct PointerCatalog: View {
    let selected: PointerStyle?
    var width: CGFloat = 400
    var height: CGFloat = 340
    let onPick: (PointerStyle) -> Void
    @State private var thumbnails: [PointerStyle: NSImage] = [:]
    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 72), spacing: 4)]

    init(selected: PointerStyle?, width: CGFloat = 400, height: CGFloat = 340, onPick: @escaping (PointerStyle) -> Void) {
        self.selected = selected
        self.width = width
        self.height = height
        self.onPick = onPick
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Кошачьи указатели", PointerStyle.catStyles)
                section("Забавные указатели", PointerStyle.funStyles)
                section("Остальные", PointerStyle.originalStyles + [.laser])
                if !PointerStyle.customHands.isEmpty {
                    section("Свои", PointerStyle.customHands)
                }
            }
            .padding(12)
        }
        .frame(width: width, height: height)
        .onAppear {
            let styles = PointerStyle.allCases
            HandAsset.preloadThumbnails(styles.compactMap(\.assetName)) {
                thumbnails = styles.reduce(into: [:]) { icons, style in
                    icons[style] = pointerIcon(style)
                }
            }
        }
    }

    private func section(_ title: String, _ styles: [PointerStyle]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary).padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(styles, id: \.self) { style in
                    PickerCell(style: style, icon: thumbnails[style] ?? pointerIcon(style),
                               selected: style == selected) {
                        onPick(style)
                    }
                }
            }
        }
    }
}

private struct PickerCell: View {
    let style: PointerStyle
    let icon: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 42, height: 42)
                }
            }
            .frame(width: 62, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(style.title)
        .onHover { hovering = $0 }
    }
}

private struct YourHands: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Мои руки")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                TextButton(title: "Создать руку…") { model.startMakingHand() }
            }
            .padding(.horizontal, 4)
            if PointerStyle.customHands.isEmpty {
                Text("Создайте свою руку в ChatGPT или другом генераторе изображений.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            } else {
                HStack(spacing: 6) {
                    ForEach(PointerStyle.customHands, id: \.self) { style in
                        CustomHandChip(style: style, model: model)
                    }
                }
            }
            if let message = model.handMessage {
                Text(message).font(.system(size: 11)).foregroundColor(.secondary).padding(.horizontal, 4)
            }
        }
    }
}

private struct CustomHandChip: View {
    let style: PointerStyle
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.selectPointer(style)
            } label: {
                HStack(spacing: 6) {
                    if let icon = pointerIcon(style) {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                    }
                    Text(style.title).font(.system(size: 12)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help("Выбрать «\(style.title)»")

            Button {
                model.removeHand(style)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Удалить «\(style.title)»")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(PointerStyle.saved == style ? 0.13 : 0.05)))
    }
}

private struct AppearancePage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Card(title: "Указатель") {
            Row("Размер") {
                HStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 10)).foregroundColor(.secondary)
                    Slider(value: model.binding({ Double(Preferences.pointerSize) }, { Preferences.pointerSize = CGFloat($0) }),
                           in: Double(Preferences.pointerSizeRange.lowerBound)...Double(Preferences.pointerSizeRange.upperBound))
                        .frame(width: 180)
                        .focusable(false)
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 16)).foregroundColor(.secondary)
                }
            }
            Row("Тень под указателем") {
                Toggle("", isOn: model.binding({ Preferences.showShadow }, { Preferences.showShadow = $0 }))
                    .toggleStyle(.switch).labelsHidden().focusable(false)
            }
        }
    }
}

private struct DrawingPage: View {
    @ObservedObject var model: SettingsModel
    private static let choices: [(String, Double)] = [
        ("Через 3 секунды", 3),
        ("Через 6 секунд", 6),
        ("Через 10 секунд", 10),
        ("Только вручную", 0),
    ]

    var body: some View {
        Card(title: "Линии") {
            Row("Цвет линий", detail: Preferences.inkChoice == .match ? "Как у указателя." : "Для всех указателей выбран цвет «\(Preferences.inkChoice.title.lowercased())».") {
                HStack(spacing: 8) {
                    ForEach(InkChoice.allCases, id: \.self) { choice in
                        InkSwatch(choice: choice, selected: Preferences.inkChoice == choice) {
                            Preferences.inkChoice = choice
                            model.refresh()
                        }
                    }
                }
            }
            Row("Стирание линий", detail: "Стереть вручную можно клавишами \(Preferences.clearShortcut.localizedDisplay).") {
                Picker("", selection: model.binding({ Preferences.fadeSeconds }, { Preferences.fadeSeconds = $0 })) {
                    ForEach(DrawingPage.choices, id: \.1) { choice in
                        Text(choice.0).tag(choice.1)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .focusable(false)
            }
            Row("Кнопка цвета на панели", detail: "Меняйте цвет прямо во время показа.") {
                Toggle("", isOn: model.binding({ Preferences.showInkButton }, { Preferences.showInkButton = $0 }))
                    .toggleStyle(.switch).labelsHidden().focusable(false)
            }
        }
    }
}

private struct SoundPage: View {
    @ObservedObject var model: SettingsModel
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 8)]

    var body: some View {
        let on = Preferences.handSound
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Звук касания")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 8) {
                    SoundTile(title: "Без звука", symbol: "speaker.slash.fill", selected: !on) {
                        Preferences.handSound = false
                        model.refresh()
                    }
                    ForEach(TapSoundChoice.allCases, id: \.self) { choice in
                        SoundTile(title: choice.title, symbol: "waveform", selected: on && Preferences.tapSound == choice) {
                            Preferences.tapSound = choice
                            Preferences.handSound = true
                            model.preview(choice)
                            model.refresh()
                        }
                    }
                }
                Text("Выберите звук, чтобы прослушать его. Он звучит при каждом касании.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            Card(title: nil) {
                Row("Звук лазерной точки", detail: "По умолчанию лазерная точка работает без звука.") {
                    Toggle("", isOn: model.binding({ Preferences.laserSound }, { Preferences.laserSound = $0 }))
                        .toggleStyle(.switch).labelsHidden().focusable(false)
                        .disabled(!on)
                }
            }
            .opacity(on ? 1 : 0.5)
        }
        .onAppear { model.warmPreview() }
    }
}

private struct InkSwatch: View {
    let choice: InkChoice
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let color = choice.color {
                    Circle().fill(Color(cgColor: color))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(choice == .black ? 0.35 : 0.15), lineWidth: 1))
                } else {
                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                }
            }
            .frame(width: 20, height: 20)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .scaleEffect(hovering && !selected ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(choice.title)
        .onHover { hovering = $0 }
    }
}

private struct SoundTile: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

private struct AboutPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "разработка"
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PlayPointer").font(.system(size: 18, weight: .bold))
                    Text("Версия \(version)").font(.system(size: 12)).foregroundColor(.secondary)
                    Text("Рука-указатель для Mac. Бесплатно и с открытым кодом.").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                if let updater = model.updater {
                    PillButton(title: "Проверить обновления") { updater.checkForUpdates() }
                }
            }
            Card(title: nil) {
                LinkRow(title: "Разработчик PlayPointer", detail: "Владимир Кривошеев · «Огонь внутри»", url: "https://t.me/Krivosheevblog")
                LinkRow(title: "Исходный проект", detail: "tinyhand.app", url: "https://tinyhand.app")
                LinkRow(title: "Исходный код", detail: "github.com/omiusgm/playpointer", url: "https://github.com/omiusgm/playpointer")
                LinkRow(title: "Автор TinyHand", detail: "Камран Ахмед · @nilbuild", url: "https://x.com/nilbuild")
                LinkRow(title: "Лицензия", detail: "MIT", url: "https://github.com/omiusgm/playpointer/blob/main/LICENSE")
            }
            HStack {
                Spacer()
                TextButton(title: "Сбросить настройки…") { model.resetAll() }
            }
        }
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(symbol: section.symbol, tint: section.tint)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.1 : hovering ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

private struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
            .frame(width: 24, height: 24)
            .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(.white))
    }
}

private struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                _VariadicView.Tree(Separated()) {
                    content
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
        }
    }
}

private struct Separated: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail = detail {
                    Text(detail).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

private struct LinkRow: View {
    let title: String
    let detail: String
    let url: String
    @State private var hovering = false

    var body: some View {
        Button {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        } label: {
            HStack {
                Text(title).font(.system(size: 13)).foregroundColor(.primary)
                Spacer()
                Text(detail).font(.system(size: 12)).foregroundColor(.secondary)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.primary.opacity(hovering ? 0.04 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

private struct TextButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(hovering ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

private struct PillButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(hovering ? 0.14 : 0.09)))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

private struct MakeHandPage: View {
    @ObservedObject var model: SettingsModel
    @State private var dropping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Step(number: 1, title: "Опишите руку", detail: "Какой она должна быть?") {
                PlainField(placeholder: "Например, из горчичной пряжи", text: $model.handIdea)
                    .frame(maxWidth: 420)
            }
            Step(number: 2, title: "Создайте изображение", detail: "Откройте запрос в ChatGPT или скопируйте его для другого генератора. Скачайте результат в PNG с прозрачным фоном.") {
                HStack(spacing: 8) {
                    PrimaryButton(title: "Открыть в ChatGPT", symbol: "arrow.up.right") { model.openChatGPT() }
                    PrimaryButton(title: model.promptCopied ? "Скопировано" : "Копировать запрос", symbol: model.promptCopied ? "checkmark" : "doc.on.doc", primary: false) {
                        model.copyPrompt()
                    }
                }
            }
            Step(number: 3, title: "Добавьте изображение", detail: nil) {
                if let draft = model.draft {
                    preview(draft)
                } else {
                    dropZone
                }
            }
        }
    }

    private var dropZone: some View {
        Button {
            model.chooseHandFile()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: model.draftError == nil ? "square.and.arrow.down" : "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(model.draftError == nil ? .secondary : .orange)
                Text(model.draftError ?? "Перетащите сюда PNG или щёлкните, чтобы выбрать файл")
                    .font(.system(size: 12))
                    .foregroundColor(model.draftError == nil ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if model.draftError != nil {
                    Text("Щёлкните, чтобы выбрать другой файл")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(dropping ? 0.07 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(dropping ? Color.accentColor : Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let provider = providers.first else {
                return false
            }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else {
                    return
                }
                DispatchQueue.main.async { model.loadDraft(url) }
            }
            return true
        }
    }

    private func preview(_ draft: SettingsModel.HandDraft) -> some View {
        HStack(alignment: .center, spacing: 22) {
            Image(nsImage: NSImage(cgImage: draft.image.cropping(to: CGRect(x: 112, y: 90, width: 800, height: 1000)) ?? draft.image, size: NSSize(width: 144, height: 180)))
                .resizable()
                .interpolation(.high)
                .frame(width: 144, height: 180)
                .padding(.vertical, 10)
                .frame(width: 170)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.91, green: 0.81, blue: 0.71))
                )
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Название").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    PlainField(placeholder: "Моя рука", text: Binding(get: { model.handName }, set: { model.handName = String($0.prefix(16)) }))
                        .frame(width: 220)
                }
                Text("На изображении должна быть видна тыльная сторона кисти. Если видна ладонь, попробуйте другое изображение.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                HStack(spacing: 10) {
                    PrimaryButton(title: "Добавить руку", symbol: nil) { model.saveDraft() }
                    TextButton(title: "Выбрать другое изображение") { model.chooseHandFile() }
                }
            }
        }
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    let detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.75)))
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let detail = detail {
                        Text(detail).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
        }
    }
}

private struct PlainField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .modifier(NoFocusEffect())
    }
}

private struct NoFocusEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let symbol: String?
    var primary = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol = symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(primary ? .white : .primary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(primary
                ? Color.accentColor.opacity(hovering ? 0.88 : 1)
                : Color.primary.opacity(hovering ? 0.14 : 0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}
private struct ShortcutField: NSViewRepresentable {
    let shortcut: Shortcut
    let model: SettingsModel
    let apply: (Shortcut) -> Bool

    func makeNSView(context: Context) -> ShortcutRecorder {
        let r = ShortcutRecorder(shortcut: shortcut)
        r.onRecording = { model.onRecording?($0) }
        r.onChange = { s in
            let ok = apply(s)
            model.shortcutError = ok ? nil : "Не удалось назначить \(s.localizedDisplay). Попробуйте другое сочетание."
            return ok
        }
        return r
    }

    func updateNSView(_ nsView: ShortcutRecorder, context: Context) {
        nsView.show(shortcut)
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private let blankIcon = NSImage(size: NSSize(width: 64, height: 64))

private func pointerIcon(_ style: PointerStyle) -> NSImage? {
    guard let name = style.assetName else {
        return Toolbar.icon(for: style)
    }
    return HandAsset.cachedThumbnail(name) ?? blankIcon
}

import AppKit
import ApplicationServices

final class WelcomeWindow: NSObject {
    var onTryIt: (() -> Void)?
    var onTryDrawing: (() -> Bool)?
    var simulateUntrusted = false

    private final class Card: NSWindow {
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) {
            onCancel?()
        }
    }

    private var window: Card?
    private var drawingHelp: Card?
    private var timer: Timer?
    private var forDrawing = false
    private var tapUnavailable = false
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private let helpButton = NSButton(title: "Как дать доступ?", target: nil, action: nil)
    private static let cardSize = CGSize(width: 340, height: 300)
    private static let drawingRecovery = """
        После обновления PlayPointer в списке может остаться разрешение прежней версии. Выберите PlayPointer в списке и нажмите «−». \
        Нажмите «+», добавьте PlayPointer из папки «Программы» и включите доступ. Если карточка не обновилась, выйдите из PlayPointer, \
        откройте его снова и выберите «Рисование». Нажмите «Начать рисовать».
        """
    private let tip = NSTextField(wrappingLabelWithString: "Переключатель уже включён?\n\(WelcomeWindow.drawingRecovery)")

    static let shownKey = "welcomeShown"

    private static var usesDeviceAccessSettings: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    func show(forDrawing: Bool = false) {
        self.forDrawing = forDrawing
        tapUnavailable = false
        if window == nil {
            build()
        }
        refresh()
        UserDefaults.standard.set(true, forKey: WelcomeWindow.shownKey)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.invalidateShadow()
        window?.makeFirstResponder(nil)
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var granted: Bool {
        AXIsProcessTrusted() && !simulateUntrusted
    }

    private func refresh() {
        if forDrawing {
            let trusted = granted
            if !trusted {
                title.stringValue = "Доступ для рисования"
                subtitle.stringValue = "Разрешите PlayPointer обрабатывать нажатия мыши для рисования."
                button.title = "Открыть настройки"
            } else if tapUnavailable {
                title.stringValue = "Не удалось начать рисовать"
                subtitle.stringValue = "Доступ есть, но PlayPointer не смог перехватить нажатия мыши."
                button.title = "Повторить"
            } else {
                title.stringValue = "Можно рисовать"
                subtitle.stringValue = "Рисуйте поверх открытых окон."
                button.title = "Начать рисовать"
            }
            helpButton.isHidden = trusted
            tip.isHidden = trusted
        } else {
            title.stringValue = "Всё готово"
            subtitle.stringValue = "Нажмите \(Preferences.toggleShortcut.localizedDisplay), чтобы включить указатель."
            button.title = "Попробовать"
            helpButton.isHidden = true
            tip.isHidden = true
        }
        let height: CGFloat = tip.isHidden ? Self.cardSize.height : 436
        if let window, window.frame.height != height {
            window.setContentSize(CGSize(width: Self.cardSize.width, height: height))
        }
    }

    @objc private func buttonPressed() {
        if !forDrawing {
            close()
            onTryIt?()
            return
        }
        if granted {
            if onTryDrawing?() == true {
                close()
            } else {
                tapUnavailable = true
                refresh()
            }
            return
        }
        tapUnavailable = false
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        Self.openDrawingSettings()
    }

    static func openDrawingSettings() {
        let privacySettings = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        let destination = usesDeviceAccessSettings
            ? "\(privacySettings)?Privacy_Accessibility"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: destination), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showDrawingHelp() {
        if drawingHelp == nil {
            drawingHelp = buildDrawingHelp()
            drawingHelp?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        drawingHelp?.makeKeyAndOrderFront(nil)
    }

    var drawingHelpFrame: CGRect? {
        guard let drawingHelp, drawingHelp.isVisible else { return nil }
        return drawingHelp.frame
    }

    @objc private func openSettingsFromHelp() {
        Self.openDrawingSettings()
    }

    private func buildDrawingHelp() -> Card {
        let width: CGFloat = 428
        let inset: CGFloat = 24
        let contentWidth = width - 2 * inset
        let pane = Self.usesDeviceAccessSettings ? "Управление устройством и доступ к данным" : "Универсальный доступ"
        let steps = [
            "В Системных настройках откройте «Конфиденциальность и безопасность» → «\(pane)».",
            "Включите переключатель рядом с PlayPointer. Если приложения нет в списке, нажмите «Добавить» (+) и выберите PlayPointer в папке «Программы».",
            "Нажмите правой кнопкой на значок PlayPointer в строке меню и выберите «Режим указателя» → «Рисование». Если открылась карточка доступа, нажмите «Начать рисовать»."
        ]

        func label(_ text: String, width: CGFloat) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: 13)
            field.preferredMaxLayoutWidth = width
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
            return field
        }

        let rows = steps.enumerated().map { index, text in
            let number = NSTextField(labelWithString: "\(index + 1).")
            number.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            number.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let row = NSStackView(views: [number, label(text, width: contentWidth - 24)])
            row.alignment = .firstBaseline
            row.spacing = 6
            return row
        }

        let recoveryHeading = label("Переключатель уже включён?", width: contentWidth)
        recoveryHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        let recovery = label(Self.drawingRecovery, width: contentWidth)
        let note = label("Режим «Управление» работает без этого разрешения.", width: contentWidth)
        note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: rows)
        stack.addArrangedSubview(recoveryHeading)
        stack.addArrangedSubview(recovery)
        stack.addArrangedSubview(note)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: rows[2])
        stack.setCustomSpacing(4, after: recoveryHeading)
        stack.setCustomSpacing(16, after: recovery)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let settings = NSButton(title: "Открыть настройки", target: self, action: #selector(openSettingsFromHelp))
        settings.bezelStyle = .rounded
        settings.keyEquivalent = "\r"
        settings.translatesAutoresizingMaskIntoConstraints = false
        let size = CGSize(width: width, height: inset * 2 + stack.fittingSize.height + 18 + settings.fittingSize.height)
        let help = Card(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        help.title = "Как включить рисование"
        help.isReleasedWhenClosed = false
        help.onCancel = { [weak help] in help?.close() }
        guard let content = help.contentView else { return help }
        content.addSubview(stack)
        content.addSubview(settings)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            settings.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 18),
            settings.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
        ])
        return help
    }

    @objc private func close() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }

    private func build() {
        let size = Self.cardSize
        let messageWidth = size.width - 52
        let w = Card(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.level = .normal
        w.onCancel = { [weak self] in self?.close() }

        let card = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        card.material = .popover
        card.blendingMode = .behindWindow
        card.state = .active
        card.roundCorners(20)
        w.contentView = card

        let icon = NSImageView()
        icon.image = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 76).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 76).isActive = true

        title.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        title.alignment = .center
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.preferredMaxLayoutWidth = messageWidth
        subtitle.widthAnchor.constraint(equalToConstant: messageWidth).isActive = true

        button.target = self
        button.action = #selector(buttonPressed)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        button.widthAnchor.constraint(equalToConstant: 180).isActive = true

        helpButton.target = self
        helpButton.action = #selector(showDrawingHelp)
        helpButton.bezelStyle = .rounded
        helpButton.controlSize = .small

        tip.font = NSFont.systemFont(ofSize: 12)
        tip.alignment = .left
        tip.preferredMaxLayoutWidth = messageWidth
        tip.widthAnchor.constraint(equalToConstant: messageWidth).isActive = true

        let stack = NSStackView(views: [icon, title, subtitle, button, helpButton, tip])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(16, after: icon)
        stack.setCustomSpacing(22, after: subtitle)
        stack.setCustomSpacing(10, after: helpButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Закрыть")!,
                                   target: self, action: #selector(close))
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: 4),
            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        window = w
    }

    func snapshot() -> NSBitmapImageRep? {
        if window == nil {
            build()
        }
        if simulateUntrusted {
            forDrawing = true
        }
        refresh()
        guard let view = window?.contentView else {
            return nil
        }
        window?.appearance = NSAppearance(named: .aqua)
        view.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}

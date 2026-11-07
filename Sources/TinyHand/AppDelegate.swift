import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController()
    private let settings = SettingsWindow()
    private let updater = Updater()
    private let welcome = WelcomeWindow()
    private var permissionItem: NSMenuItem?
    private let menu = NSMenu()
    private var toggleItem: NSMenuItem?
    private var clearItem: NSMenuItem?
    private var soundItem: NSMenuItem?
    private var modeItems: [PointerMode: NSMenuItem] = [:]
    private var toggleHotKey: UInt32?
    private var clearHotKey: UInt32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = editingMenu()
        HandAsset.preloadThumbnails(PointerStyle.allCases.compactMap(\.assetName))
        Log.write("launch \(Bundle.main.bundlePath) trusted=\(AXIsProcessTrusted())")
        CursorHider.enableBackgroundHiding()
        overlay.onActiveChanged = { [weak self] in
            self?.updateIcon()
        }
        overlay.onSoundChanged = { [weak self] in
            self?.refreshMenu()
        }
        overlay.extraPassThrough = { [weak self] in
            guard let frame = self?.statusItem.button?.window?.frame else {
                return []
            }
            return [frame]
        }
        updater.start()
        setupStatusItem()
        setupSettings()
        registerHotKeys()

        overlay.onNeedsPermission = { [weak self] in
            self?.showWelcome()
        }
        welcome.onTryIt = { [weak self] in
            self?.overlay.activate()
        }
        welcome.onTryDrawing = { [weak self] in
            guard let self = self, self.overlay.setMode(.draw) else { return false }
            return self.overlay.activate()
        }
        if !UserDefaults.standard.bool(forKey: WelcomeWindow.shownKey) {
            welcome.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.deactivate()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let permission = NSMenuItem(title: "Разрешить универсальный доступ…", action: #selector(showWelcome), keyEquivalent: "")
        permissionItem = permission
        menu.addItem(permission)
        let toggle = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
        let clear = NSMenuItem(title: "", action: #selector(clearInk), keyEquivalent: "")
        let sound = NSMenuItem(title: "Звук касания", action: #selector(toggleSound), keyEquivalent: "")
        toggleItem = toggle
        clearItem = clear
        soundItem = sound
        menu.addItem(toggle)
        let modeItem = NSMenuItem(title: "Режим указателя", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for mode in PointerMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modes.addItem(item)
            modeItems[mode] = item
        }
        modeItem.submenu = modes
        menu.addItem(modeItem)
        menu.addItem(clear)
        menu.addItem(sound)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ","))
        if Updater.isAvailable {
            menu.addItem(NSMenuItem(title: "Проверить обновления…", action: #selector(checkForUpdates), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из PlayPointer", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.delegate = self
    }

    private func setupSettings() {
        settings.applyToggleShortcut = { [weak self] s in
            self?.apply(s, isToggle: true) ?? false
        }
        settings.applyClearShortcut = { [weak self] s in
            self?.apply(s, isToggle: false) ?? false
        }
        settings.applyPointerMode = { [weak self] mode in self?.overlay.requestMode(mode) }
        settings.updater = Updater.isAvailable ? updater : nil
        settings.onRecording = { [weak self] recording in
            if recording {
                self?.unregisterHotKeys()
            } else {
                self?.registerHotKeys()
            }
        }
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard wantsMenu else {
            overlay.toggle()
            return
        }
        refreshMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        overlay.suspendInput(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        overlay.suspendInput(false)
    }

    private func refreshMenu() {
        let on = overlay.isActive
        toggleItem?.title = "\(on ? "Выключить указатель" : "Включить указатель")    \(Preferences.toggleShortcut.localizedDisplay)"
        clearItem?.title = "Стереть рисунок    \(Preferences.clearShortcut.localizedDisplay)"
        soundItem?.state = overlay.soundOn ? .on : .off
        for (mode, item) in modeItems {
            item.state = Preferences.pointerMode == mode ? .on : .off
        }
        permissionItem?.isHidden = AXIsProcessTrusted()
    }

    private func apply(_ s: Shortcut, isToggle: Bool) -> Bool {
        unregisterHotKeys()
        let old = isToggle ? Preferences.toggleShortcut : Preferences.clearShortcut
        if isToggle {
            Preferences.toggleShortcut = s
        } else {
            Preferences.clearShortcut = s
        }
        let ok = registerHotKeys()
        if ok {
            return true
        }
        unregisterHotKeys()
        if isToggle {
            Preferences.toggleShortcut = old
        } else {
            Preferences.clearShortcut = old
        }
        registerHotKeys()
        return false
    }

    @discardableResult
    private func registerHotKeys() -> Bool {
        guard toggleHotKey == nil, clearHotKey == nil else {
            return true
        }
        let t = Preferences.toggleShortcut
        let c = Preferences.clearShortcut
        toggleHotKey = HotKeyCenter.shared.register(keyCode: t.keyCode, modifiers: t.modifiers) { [weak self] in
            self?.overlay.toggle()
        }
        clearHotKey = HotKeyCenter.shared.register(keyCode: c.keyCode, modifiers: c.modifiers) { [weak self] in
            self?.overlay.clearInk()
        }
        return toggleHotKey != nil && clearHotKey != nil
    }

    private func unregisterHotKeys() {
        if let id = toggleHotKey {
            HotKeyCenter.shared.unregister(id)
        }
        if let id = clearHotKey {
            HotKeyCenter.shared.unregister(id)
        }
        toggleHotKey = nil
        clearHotKey = nil
    }

    @objc private func toggle() {
        overlay.toggle()
    }

    @objc private func clearInk() {
        overlay.clearInk()
    }

    @objc private func toggleSound() {
        overlay.soundOn.toggle()
    }

    @objc private func selectMode(_ item: NSMenuItem) {
        if let rawValue = item.representedObject as? String, let mode = PointerMode(rawValue: rawValue) {
            overlay.requestMode(mode)
        }
    }

    @objc private func openSettings() {
        overlay.exit()
        settings.show()
    }

    @objc private func showWelcome() {
        if overlay.mode == .draw { overlay.exit() }
        welcome.show(forDrawing: true)
    }

    @objc private func checkForUpdates() {
        overlay.exit()
        updater.checkForUpdates()
    }

    @objc private func quit() {
        overlay.deactivate()
        NSApp.terminate(nil)
    }

    private func updateIcon() {
        let on = overlay.isActive
        let image = Bundle.main.image(forResource: on ? "menubar_on" : "menubar_off")
            ?? NSImage(systemSymbolName: on ? "hand.point.up.left.fill" : "hand.point.up.left",
                       accessibilityDescription: "PlayPointer")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = overlay.isActive
            ? "PlayPointer включён. Щелчок выключит указатель. Правый щелчок откроет меню."
            : "PlayPointer. Щелчок включит указатель. Правый щелчок откроет меню."
    }

    private func editingMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Выйти из PlayPointer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Скопировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

import AppKit
import Carbon.HIToolbox

final class OverlayController {
    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let window: OverlayWindow
    private let armView: ArmView
    private let inputTap = InputTap()
    private let tapSound = TapSound()
    private(set) var mode = Preferences.pointerMode
    private var controlMonitors: [Any] = []
    private var drawModeButtons: Set<Int64> = []
    private var interactHeld = false
    private var menuHover = false
    private var guardCursorUntil = Date.distantPast
    private var timer: Timer?
    private var currentFrame: CGRect?
    private var downPoint: CGPoint?
    private var buttonSeenDown = false

    private let toolbar = Toolbar()
    private var revealUntil = Date.distantPast
    private var normalCursor = false
    private var ownMenuOpen = false
    private var menuRects: [CGRect] = []
    private var lastMenuScan = Date.distantPast
    private var menuOpeningUntil = Date.distantPast
    private var escHotKey: UInt32?

    private static let busyInterval: TimeInterval = 1.0 / 120.0
    private static let idleInterval: TimeInterval = 1.0 / 20.0
    private static let idleAfter: TimeInterval = 0.5
    private static let menuScanFast: TimeInterval = 0.05
    private static let menuScanSlow: TimeInterval = 0.25
    private var timerInterval: TimeInterval = 0
    private var idleMonitors: [Any] = []
    private var lastMouse: CGPoint?
    private var stillSince = Date()
    private var lastButtonEvent = Date.distantPast

    private(set) var isActive = false
    private var activity: NSObjectProtocol?
    var onActiveChanged: (() -> Void)?
    var onNeedsPermission: (() -> Void)?

    init() {
        let frame = (NSScreen.main ?? NSScreen.screens.first).map { $0.frame }
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        armView = ArmView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = armView

        inputTap.onMouseDown = { [weak self] button, feedback in
            guard let self = self else {
                return
            }
            self.drawModeButtons.insert(button)
            self.armView.press()
            self.armView.held = true
            if feedback == .draw {
                self.tapSound.play()
                self.toolbar.hideHint()
                if button == 0 {
                    self.downPoint = self.localMouse()
                }
                self.showWandSparks(at: NSEvent.mouseLocation)
            }
            self.noteButtonEvent()
        }
        inputTap.onLeftDragged = { [weak self] in
            self?.drag()
            self?.wake()
        }
        inputTap.onMouseUp = { [weak self] button, feedback in
            guard let self = self else { return }
            self.drawModeButtons.remove(button)
            self.armView.held = !self.drawModeButtons.isEmpty
            if feedback == .draw && button == 0 {
                self.endStroke()
            } else if feedback == .interact {
                self.guardCursorUntil = Date().addingTimeInterval(2)
                CursorHider.reassert(urgent: true)
            }
            self.noteButtonEvent()
        }
        inputTap.onPassThroughPress = { [weak self] location in
            self?.notePassThroughPress(at: location)
        }

        toolbar.onPick = { [weak self] style in
            self?.pick(style)
        }
        toolbar.onToggleSound = { [weak self] in
            self?.soundOn.toggle()
        }
        toolbar.onSelectMode = { [weak self] in self?.requestMode($0) }
        toolbar.onExit = { [weak self] in
            self?.exit()
        }
        toolbar.select(armView.style)
        toolbar.selectMode(mode)
        tapSound.enabled = soundOn
        toolbar.setSoundOn(soundOn)
        NotificationCenter.default.addObserver(forName: Preferences.changed, object: nil, queue: .main) { [weak self] _ in
            self?.syncSound()
            self?.syncMode()
            self?.inputTap.interactKey = Preferences.interactKey.cgFlags
            self?.armView.updateInkColor()
            self?.tapSound.load(Preferences.tapSound)
            if let self = self, self.armView.style != PointerStyle.saved {
                self.pick(PointerStyle.saved)
            }
        }
    }

    var soundOn: Bool {
        get { armView.style == .laser ? Preferences.laserSound : Preferences.handSound }
        set {
            if armView.style == .laser {
                Preferences.laserSound = newValue
            } else {
                Preferences.handSound = newValue
            }
        }
    }
    var onSoundChanged: (() -> Void)?

    func pick(_ style: PointerStyle) {
        armView.setStyle(style)
        PointerStyle.saved = armView.style
        toolbar.select(armView.style)
        syncSound()
    }

    private func syncSound() {
        tapSound.enabled = soundOn
        toolbar.setSoundOn(soundOn)
        onSoundChanged?()
    }

    @discardableResult
    func setMode(_ requested: PointerMode) -> Bool {
        guard requested != .draw || (AXIsProcessTrusted() && inputTap.install()) else {
            toolbar.selectMode(mode)
            return false
        }
        if Preferences.pointerMode != requested {
            Preferences.pointerMode = requested
        }
        return true
    }

    func requestMode(_ requested: PointerMode) {
        if !setMode(requested) {
            onNeedsPermission?()
        }
    }

    private func syncMode() {
        let selected = Preferences.pointerMode
        guard mode != selected else { return }
        mode = selected
        release()
        toolbar.selectMode(selected)
        toolbar.hideHint()
        if isActive {
            if selected == .control {
                window.ignoresMouseEvents = true
                syncInput()
            }
            tick()
            if selected == .draw { syncInput() }
        }
    }

    var extraPassThrough: (() -> [CGRect])?

    func suspendInput(_ suspended: Bool) {
        guard isActive else {
            return
        }
        ownMenuOpen = suspended
        if suspended { release() }
        syncInput()
        if let screen = currentScreen() {
            updateZones(mouse: NSEvent.mouseLocation, screen: screen)
        }
    }

    func exit() {
        clearInk()
        deactivate()
    }

    private func release() {
        drawModeButtons.removeAll()
        armView.held = false
        armView.clearPointerEffects()
        endStroke()
    }

    private func endStroke() {
        buttonSeenDown = false
        downPoint = nil
        armView.ink.end()
    }

    var style: PointerStyle { armView.style }

    var tapMaxWaitMs: Double { inputTap.maxWaitMs }

    func resetTapWait() {
        inputTap.resetWait()
    }

    func toolbarButtonCenter(_ style: PointerStyle) -> CGPoint? {
        toolbar.center(of: style)
    }

    func toolbarModeCenter(_ mode: PointerMode) -> CGPoint? {
        toolbar.center(of: mode)
    }

    var inkStrokes: Int { armView.ink.layer.sublayers?.count ?? 0 }

    var debugState: String {
        "held=\(armView.held) downPoint=\(downPoint != nil) drawing=\(armView.ink.isDrawing) strokes=\(inkStrokes)"
    }

    func clearInk() {
        armView.ink.clear()
    }

    private func drag() {
        guard let start = downPoint, let p = localMouse() else {
            return
        }
        let ink = armView.ink
        if !ink.isDrawing {
            if hypot(p.x - start.x, p.y - start.y) < 4 {
                return
            }
            ink.begin(at: start, width: armView.inkWidth)
        }
        ink.extend(to: p)
    }

    private func localMouse() -> CGPoint? {
        guard let frame = currentFrame else {
            return nil
        }
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - frame.origin.x, y: mouse.y - frame.origin.y)
    }

    func toggle() {
        if isActive {
            deactivate()
            return
        }
        activate()
    }

    static let hintShownKey = "firstRunHintShown"

    @discardableResult
    func activate() -> Bool {
        guard !isActive else {
            return true
        }
        if mode == .draw && !setMode(.draw) {
            setMode(.control)
        }
        isActive = true
        currentFrame = nil
        tapSound.warm()
        inputTap.interactKey = Preferences.interactKey.cgFlags

        CursorHider.hide()
        revealUntil = Date().addingTimeInterval(3)
        tick()
        window.orderFrontRegardless()
        toolbar.show()
        syncInput()

        stillSince = Date()
        runTimer(every: OverlayController.busyInterval)

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical], reason: "PlayPointer pointer is on")
        if !UserDefaults.standard.bool(forKey: OverlayController.hintShownKey) {
            UserDefaults.standard.set(true, forKey: OverlayController.hintShownKey)
            toolbar.showHint(Toolbar.hintParts(for: mode))
            revealUntil = Date().addingTimeInterval(10)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.toolbar.hideHint()
            }
        }
        onActiveChanged?()
        return true
    }

    func deactivate() {
        guard isActive else {
            return
        }
        isActive = false

        timer?.invalidate()
        timer = nil
        timerInterval = 0
        removeIdleMonitors()
        syncInput()
        if let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
        release()
        armView.ink.clear()
        window.ignoresMouseEvents = true
        window.orderOut(nil)
        toolbar.hide()
        normalCursor = false
        armView.pointerHidden = false
        inputTap.passThroughRects = []
        setEscEnabled(false)
        ownMenuOpen = false
        CursorHider.show()
        onActiveChanged?()
    }

    private func updateZones(mouse: CGPoint, screen: NSScreen) {
        let f = toolbar.frame
        let near = f.insetBy(dx: -80, dy: 0).union(f.offsetBy(dx: 0, dy: 90)).insetBy(dx: 0, dy: -10).contains(mouse)
        let drawing = armView.ink.isDrawing
        toolbar.setRevealed(!drawing && (near || Date() < revealUntil))

        let menuLikely = !menuRects.isEmpty || ownMenuOpen || Date() < menuOpeningUntil
            || Date().timeIntervalSince(lastButtonEvent) < 2
            || OverlayController.menuBarRect(screen).insetBy(dx: 0, dy: -40).contains(mouse)
        let scanEvery = menuLikely ? OverlayController.menuScanFast : OverlayController.menuScanSlow
        if Date().timeIntervalSince(lastMenuScan) > scanEvery {
            lastMenuScan = Date()
            menuRects = OverlayController.openMenus()
        }
        let menuBar = OverlayController.menuBarRect(screen)
        let cgMouse = OverlayController.cgPoint(mouse)
        let overMenu = menuBar.contains(mouse) || menuRects.contains { $0.contains(cgMouse) }
            || Date() < menuOpeningUntil
        let key = Preferences.interactKey.cgFlags
        let interacting = mode == .draw && ((!key.isEmpty && CGEventSource.flagsState(.hidSystemState).contains(key))
            || inputTap.interactPressing)
        interactHeld = interacting
        menuHover = overMenu
        let normal = !drawing && !Preferences.interactKeepsHand && (interacting || overMenu || ownMenuOpen)
        setEscEnabled(menuRects.isEmpty && !ownMenuOpen)

        if normal != normalCursor {
            normalCursor = normal
            armView.pointerHidden = normal
            if normal {
                CursorHider.show()
            } else {
                CursorHider.hide()
            }
        }

        var rects = (extraPassThrough?() ?? []).map(OverlayController.cgRect)
        rects.append(OverlayController.cgRect(menuBar))
        rects.append(contentsOf: menuRects)
        if toolbar.revealed {
            rects.append(OverlayController.cgRect(f))
        }
        inputTap.passThroughRects = rects
    }

    private func setEscEnabled(_ enabled: Bool) {
        if enabled && isActive && escHotKey == nil {
            escHotKey = HotKeyCenter.shared.register(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] in
                self?.exit()
            }
        }
        if !enabled, let id = escHotKey {
            HotKeyCenter.shared.unregister(id)
            escHotKey = nil
        }
    }

    private static func menuBarRect(_ screen: NSScreen) -> CGRect {
        let height = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return CGRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
    }

    private static func openMenus() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == menuLevel,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
                return nil
            }
            return rect
        }
    }

    private static func cgPoint(_ p: CGPoint) -> CGPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryH - p.y)
    }

    private static func cgRect(_ r: CGRect) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
    }

    private func syncInput() {
        let acceptsInput = isActive && !ownMenuOpen
        inputTap.setActive(acceptsInput && mode == .draw)
        guard acceptsInput && mode == .control else {
            controlMonitors.forEach(NSEvent.removeMonitor)
            controlMonitors.removeAll()
            return
        }
        guard controlMonitors.isEmpty else { return }

        let presses: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: presses, handler: { [weak self] event in
            self?.showControlClick(event)
        }) {
            controlMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: presses, handler: { [weak self] event in
            self?.showControlClick(event)
            return event
        }) {
            controlMonitors.append(local)
        }
    }

    private func notePassThroughPress(at location: CGPoint) {
        if let screen = currentScreen(), OverlayController.cgRect(OverlayController.menuBarRect(screen)).contains(location) {
            menuOpeningUntil = Date().addingTimeInterval(1)
        }
        noteButtonEvent()
    }

    private func showControlClick(_ event: NSEvent) {
        guard isActive, mode == .control, !ownMenuOpen else { return }
        let location = event.cgEvent?.location ?? OverlayController.cgPoint(NSEvent.mouseLocation)
        notePassThroughPress(at: location)
        if toolbar.revealed && OverlayController.cgRect(toolbar.frame).contains(location) { return }
        armView.press()
        tapSound.play()
        showWandSparks(at: OverlayController.cgPoint(location))
    }

    private func showWandSparks(at mouse: CGPoint) {
        guard isActive, armView.isWand else { return }
        if currentFrame?.contains(mouse) != true { tick() }
        guard let frame = currentFrame, frame.contains(mouse) else { return }
        armView.showWandSparks(at: CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY))
    }

    func runClickTest() {
        func time(_ label: String, _ body: () -> Void) {
            let t = CFAbsoluteTimeGetCurrent()
            body()
            print(String(format: "%@: %.1f ms", label, (CFAbsoluteTimeGetCurrent() - t) * 1000))
        }
        func spin(_ seconds: Double) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        func simulate(_ type: CGEventType) {
            if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: .left) {
                _ = inputTap.handle(type: type, event: event)
            }
        }
        inputTap.setActive(true)
        tick()
        time("tick") { tick() }
        time("mouseDown (tap callback)") { simulate(.leftMouseDown) }
        time("mouseDown (deferred work)") { spin(0.01) }
        time("10 ticks while held") { for _ in 0..<10 { tick() } }
        time("mouseUp (tap callback)") { simulate(.leftMouseUp) }
        spin(0.01)
        spin(0.3)
        time("second click (tap callbacks)") {
            simulate(.leftMouseDown)
            simulate(.leftMouseUp)
        }
        spin(0.05)
        time("drag x50 (tap callbacks)") {
            simulate(.leftMouseDown)
            for _ in 0..<50 { simulate(.leftMouseDragged) }
            simulate(.leftMouseUp)
        }
        spin(0.05)
        time("ticks after up") { for _ in 0..<20 { tick() } }
        print("held after up:", armView.held, "drawing:", armView.ink.isDrawing)
    }

    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func runTimer(every interval: TimeInterval) {
        if timer != nil && interval == timerInterval {
            return
        }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        timerInterval = interval
    }

    private func noteButtonEvent() {
        lastButtonEvent = Date()
        wake()
    }

    private func wake() {
        stillSince = Date()
        guard isActive, timerInterval != OverlayController.busyInterval else {
            return
        }
        removeIdleMonitors()
        runTimer(every: OverlayController.busyInterval)
        tick()
    }

    private func updatePace(busy: Bool) {
        if timerInterval == OverlayController.idleInterval {
            if busy {
                wake()
            }
            return
        }
        let still = Date().timeIntervalSince(stillSince) > OverlayController.idleAfter
        guard still, !busy, !armView.held, !armView.isSettling, !armView.ink.isDrawing else {
            return
        }
        installIdleMonitors()
        runTimer(every: OverlayController.idleInterval)
    }

    private func installIdleMonitors() {
        guard idleMonitors.isEmpty else {
            return
        }
        let events: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .flagsChanged,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.wake()
        }) {
            idleMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.wake()
            return event
        }) {
            idleMonitors.append(local)
        }
    }

    private func removeIdleMonitors() {
        idleMonitors.forEach(NSEvent.removeMonitor)
        idleMonitors = []
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        guard let screen = currentScreen() else {
            return
        }

        if currentFrame != screen.frame {
            let moving = currentFrame != nil
            currentFrame = screen.frame
            if moving {
                release()
                revealUntil = Date().addingTimeInterval(1.5)
            }
            armView.ink.clear()
            window.setFrame(screen.frame, display: false)
            armView.frame = NSRect(origin: .zero, size: screen.frame.size)
            toolbar.place(on: screen)
        }

        let mouseMoved = mouse != lastMouse
        if mouseMoved {
            lastMouse = mouse
            stillSince = Date()
        }

        updateZones(mouse: mouse, screen: screen)
        let overDock = isActive && mode == .draw && DockArea.contains(OverlayController.cgPoint(mouse))
        let catchMouse = overDock && inputTap.isInstalled && !normalCursor && !interactHeld && !ownMenuOpen
        if window.ignoresMouseEvents == catchMouse {
            window.ignoresMouseEvents = !catchMouse
        }
        let urgent = interactHeld || menuHover || Date() < guardCursorUntil
        if !normalCursor {
            CursorHider.reassert(fighting: overDock, urgent: urgent)
        }
        let local = CGPoint(x: mouse.x - screen.frame.origin.x, y: mouse.y - screen.frame.origin.y)
        if isActive && mode == .control && !ownMenuOpen {
            armView.held = NSEvent.pressedMouseButtons != 0
        }
        armView.aim(cursor: local)
        guard downPoint != nil else {
            let busy = overDock || (!normalCursor && urgent) || CursorHider.isSettling || (armView.isNyanCat && mouseMoved)
            updatePace(busy: busy)
            return
        }
        let down = CGEventSource.buttonState(.hidSystemState, button: .left)
        if down {
            buttonSeenDown = true
        }
        if buttonSeenDown && !down {
            drawModeButtons.remove(0)
            armView.held = !drawModeButtons.isEmpty
            endStroke()
            return
        }
        drag()
    }
}

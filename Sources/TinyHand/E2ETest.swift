import AppKit

enum E2ETest {
    private final class CatcherView: NSView {
        var clicks = 0
        var rightClicks = 0
        var drags = 0
        var scrolls = 0
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            clicks += 1
        }
        override func rightMouseDown(with event: NSEvent) {
            rightClicks += 1
        }
        override func mouseDragged(with event: NSEvent) {
            drags += 1
        }
        override func scrollWheel(with event: NSEvent) {
            scrolls += 1
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: 0.95, alpha: 1).setFill()
            dirtyRect.fill()
        }
    }

    static func run() -> Bool {
        setlinebuf(stdout)
        guard AXIsProcessTrusted() else {
            print("The desktop test needs Accessibility to post test clicks and exercise Draw mode.")
            return false
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        guard let screen = NSScreen.screens.first else {
            print("no screen")
            return false
        }
        let size = CGSize(width: 520, height: 360)
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        let catcher = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        let catcherView = CatcherView(frame: CGRect(origin: .zero, size: size))
        catcher.contentView = catcherView
        catcher.level = .statusBar
        catcher.orderFrontRegardless()

        let saved = CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)
        let start = CGPoint(x: screen.frame.midX - 150, y: screen.frame.height - screen.frame.midY)

        func pump(_ seconds: Double) {
            let until = Date().addingTimeInterval(seconds)
            while Date() < until {
                if let e = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) {
                    app.sendEvent(e)
                }
            }
        }
        func post(_ type: CGEventType, _ p: CGPoint, flags: CGEventFlags = []) {
            let button: CGMouseButton = type == .rightMouseDown || type == .rightMouseUp ? .right : .left
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        func scroll() {
            CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: -2, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
            pump(0.1)
        }
        func clickToolbar(at point: CGPoint?) {
            guard let point = point else { return }
            let p = CGPoint(x: point.x, y: screen.frame.height - point.y)
            post(.mouseMoved, p)
            pump(0.25)
            post(.leftMouseDown, p)
            post(.leftMouseUp, p)
            pump(0.25)
        }
        func state(_ label: String, _ overlay: OverlayController) {
            let m = NSEvent.mouseLocation
            let down = CGEventSource.buttonState(.hidSystemState, button: .left)
            print(String(format: "%-14@ mouse=(%.0f,%.0f) hidDown=%@ %@", label as NSString, m.x, m.y,
                         down ? "yes" : "no", overlay.debugState))
        }

        let defaults = UserDefaults.standard
        let preferenceKeys = ["pointerMode", "pointerStyle", "interactKey", "recentStyles", OverlayController.hintShownKey]
        let savedPreferences = preferenceKeys.map { ($0, defaults.object(forKey: $0)) }
        Preferences.pointerMode = .control
        Preferences.interactKey = .option
        PointerStyle.saved = .lavender
        let overlay = OverlayController()
        defer {
            overlay.deactivate()
            for (key, value) in savedPreferences {
                defaults.set(value, forKey: key)
            }
            catcher.orderOut(nil)
            CGWarpMouseCursorPosition(saved)
            pump(0.1)
        }
        var passed = true
        func check(_ condition: Bool, _ description: String) {
            print(condition ? "PASS \(description)" : "FAIL \(description)")
            passed = passed && condition
        }
        check(overlay.activate(), "pointer activation")
        pump(0.3)

        post(.mouseMoved, start)
        pump(0.2)
        post(.leftMouseDown, start)
        pump(0.1)
        post(.leftMouseDragged, CGPoint(x: start.x + 40, y: start.y))
        pump(0.1)
        post(.leftMouseUp, CGPoint(x: start.x + 40, y: start.y))
        post(.rightMouseDown, start)
        post(.rightMouseUp, start)
        pump(0.2)
        scroll()
        check(catcherView.clicks == 1 && catcherView.rightClicks == 1 && catcherView.drags > 0 && catcherView.scrolls > 0,
              "Control delivers left click, right click, drag and scroll")
        check(overlay.inkStrokes == 0, "Control creates no ink")
        clickToolbar(at: overlay.toolbarModeCenter(.draw))
        check(overlay.mode == .draw, "toolbar switches from Control to Draw")
        guard overlay.mode == .draw else { return false }
        let originalClicks = catcherView.clicks
        let originalDrags = catcherView.drags

        post(.mouseMoved, start)
        pump(0.2)
        state("before press", overlay)

        post(.leftMouseDown, start)
        pump(0.1)
        state("pressed", overlay)

        for k in 1...40 {
            let p = CGPoint(x: start.x + CGFloat(k) * 6, y: start.y + 30 * sin(CGFloat(k) / 6))
            post(.leftMouseDragged, p)
            pump(0.016)
        }
        state("dragged", overlay)

        post(.leftMouseUp, CGPoint(x: start.x + 240, y: start.y))
        pump(0.2)
        state("released", overlay)

        check(overlay.inkStrokes > 0, "Draw creates ink")
        check(catcherView.clicks == originalClicks && catcherView.drags == originalDrags, "Draw captures clicks and drags")
        let originalScrolls = catcherView.scrolls
        scroll()
        check(catcherView.scrolls > originalScrolls, "Draw still delivers scroll")

        let before = overlay.inkStrokes
        post(.leftMouseDown, start)
        pump(0.05)
        post(.leftMouseUp, start)
        pump(0.2)
        state("plain click", overlay)
        check(overlay.inkStrokes == before, "a plain click adds no ink")

        post(.leftMouseDown, start, flags: .maskAlternate)
        post(.leftMouseUp, start, flags: .maskAlternate)
        pump(0.2)
        check(catcherView.clicks == originalClicks + 1, "Draw forwards an Option-click")

        clickToolbar(at: overlay.toolbarButtonCenter(.laser))
        check(overlay.style == .laser, "style toolbar button works in Draw")

        let clickPoint = start
        overlay.resetTapWait()
        Thread.detachNewThread {
            for _ in 0..<3 {
                usleep(400_000)
                post(.leftMouseDown, clickPoint)
                usleep(30_000)
                post(.leftMouseUp, clickPoint)
            }
        }
        Thread.sleep(forTimeInterval: 2)
        pump(0.3)
        var count: UInt32 = 0
        CGGetEventTapList(0, nil, &count)
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        CGGetEventTapList(count, &taps, &count)
        if let mine = taps.first(where: { $0.tappingProcess == getpid() && $0.enabled }) {
            print(String(format: "tap latency while the main thread was frozen: avg %.1f ms, max %.1f ms",
                         mine.avgUsecLatency / 1000, mine.maxUsecLatency / 1000))
        }
        print(String(format: "longest a click waited to reach the tap during the stall: %.1f ms", overlay.tapMaxWaitMs))
        check(catcherView.clicks == originalClicks + 1, "Draw captures clicks while the main thread is stalled")

        clickToolbar(at: overlay.toolbarModeCenter(.control))
        check(overlay.mode == .control, "toolbar switches from Draw to Control")

        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: down)?.post(tap: .cghidEventTap)
            pump(0.1)
        }
        pump(0.2)
        check(!overlay.isActive, "Esc exits Control")
        return passed
    }
}

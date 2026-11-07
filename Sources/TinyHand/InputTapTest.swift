import AppKit

enum InputTapTest {
    static func run() -> Bool {
        let tap = InputTap()
        var passed = true
        let modifiers: CGEventFlags = [.maskAlternate, .maskShift]

        func send(_ type: CGEventType, at point: CGPoint = .zero, flags: CGEventFlags = [],
                  expect expected: CGEventType?, flags expectedFlags: CGEventFlags = []) {
            let button: CGMouseButton = [.rightMouseDown, .rightMouseDragged, .rightMouseUp].contains(type) ? .right : .left
            let event = type == .scrollWheel
                ? CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)
                : CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
            guard let event = event else {
                print("FAIL could not create \(type)")
                passed = false
                return
            }
            event.flags = flags
            let result = tap.handle(type: type, event: event)?.takeUnretainedValue()
            guard result?.type == expected, result.map({ $0 === event && $0.flags == expectedFlags }) ?? true else {
                print("FAIL \(type) expected \(String(describing: expected)) / \(expectedFlags.rawValue), got \(String(describing: result?.type)) / \(String(describing: result?.flags.rawValue))")
                passed = false
                return
            }
        }

        // Control leaves the complete mouse event intact, including modifier-clicks.
        tap.interactKey = .maskAlternate
        for type: CGEventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown,
                                  .rightMouseDragged, .rightMouseUp, .scrollWheel] {
            send(type, flags: modifiers, expect: type, flags: modifiers)
        }

        // A drag started in Control still belongs to the app after entering Draw.
        send(.leftMouseDown, expect: .leftMouseDown)
        tap.setActive(true)
        send(.leftMouseDragged, expect: .leftMouseDragged)
        send(.leftMouseUp, expect: .leftMouseUp)

        // The toolbar remains interactive in Draw, even with the override key held.
        let toolbar = CGPoint(x: 100, y: 100)
        tap.passThroughRects = [CGRect(x: 80, y: 80, width: 40, height: 40)]
        send(.leftMouseDown, at: toolbar, flags: modifiers, expect: .leftMouseDown, flags: modifiers)
        send(.leftMouseDragged, flags: modifiers, expect: .leftMouseDragged, flags: modifiers)
        send(.leftMouseUp, flags: modifiers, expect: .leftMouseUp, flags: modifiers)

        // The temporary app interaction keeps using the modifier set at mouse-down.
        send(.leftMouseDown, flags: modifiers, expect: .leftMouseDown, flags: .maskShift)
        tap.interactKey = .maskCommand
        send(.leftMouseDragged, flags: modifiers, expect: .leftMouseDragged, flags: .maskShift)
        tap.setActive(false)
        send(.leftMouseUp, flags: modifiers, expect: .leftMouseUp, flags: .maskShift)

        // A drawing press never sends the app a drag or release without a down.
        tap.interactKey = []
        tap.setActive(true)
        send(.leftMouseDown, expect: nil)
        tap.setActive(false)
        send(.rightMouseDown, flags: modifiers, expect: .rightMouseDown, flags: modifiers)
        send(.leftMouseDragged, expect: .mouseMoved)
        send(.leftMouseUp, expect: nil)
        send(.rightMouseUp, flags: modifiers, expect: .rightMouseUp, flags: modifiers)
        send(.leftMouseDown, expect: .leftMouseDown)
        send(.leftMouseUp, expect: .leftMouseUp)

        if passed { print("PASS input routing for Control, Draw, toolbar, and mode changes during a press") }
        return passed
    }
}

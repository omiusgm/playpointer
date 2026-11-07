import AppKit
import SwiftUI

final class Toolbar {
    var onPick: ((PointerStyle) -> Void)?
    var onSelectMode: ((PointerMode) -> Void)?
    var onToggleSound: (() -> Void)?
    var onExit: (() -> Void)?
    var onCatalogVisibilityChanged: (() -> Void)?

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class Button: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class CatalogHost<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class ModeControl: NSSegmentedControl {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private let panel: Panel
    private let stack = NSStackView()
    private let modes = ModeControl()
    private var styleButtons: [PointerStyle: Button] = [:]
    private var shownStyles: [PointerStyle] = []
    private var current: PointerStyle?
    private var catalogButton: Button?
    private var catalog: Panel?
    private var inkButton: Button?
    private var swatches: [InkChoice: Button] = [:]
    private var inkOpen = false
    private var soundButton: Button?
    private(set) var revealed = false

    private let tray: Panel
    private let trayStack = NSStackView()
    private var hint: Panel?

    var catalogFrame: CGRect? { catalog?.frame }
    var frame: CGRect { inkOpen ? panel.frame.union(tray.frame) : panel.frame }

    init() {
        panel = Panel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 56),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = 0

        let background = NSVisualEffectView.darkGlass(radius: 16)
        panel.contentView = background

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        tray = Panel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tray.isOpaque = false
        tray.backgroundColor = .clear
        tray.hasShadow = true
        tray.hidesOnDeactivate = false
        tray.isFloatingPanel = true
        tray.becomesKeyOnlyIfNeeded = true
        tray.level = panel.level
        tray.collectionBehavior = panel.collectionBehavior
        tray.alphaValue = 0
        let trayBackground = NSVisualEffectView.darkGlass(radius: 14)
        tray.contentView = trayBackground
        trayStack.orientation = .horizontal
        trayStack.spacing = 2
        trayStack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        trayStack.translatesAutoresizingMaskIntoConstraints = false
        trayBackground.addSubview(trayStack)
        NSLayoutConstraint.activate([
            trayStack.leadingAnchor.constraint(equalTo: trayBackground.leadingAnchor),
            trayStack.trailingAnchor.constraint(equalTo: trayBackground.trailingAnchor),
            trayStack.topAnchor.constraint(equalTo: trayBackground.topAnchor),
            trayStack.bottomAnchor.constraint(equalTo: trayBackground.bottomAnchor),
        ])

        let more = makeButton(symbol: "plus", tip: "Все указатели") { [weak self] in
            self?.toggleCatalog()
        }
        catalogButton = more
        stack.addArrangedSubview(more)
        stack.addArrangedSubview(Toolbar.divider())
        modes.segmentCount = PointerMode.allCases.count
        modes.trackingMode = .selectOne
        modes.segmentStyle = .rounded
        modes.setAccessibilityLabel("Режим указателя")
        for (index, mode) in PointerMode.allCases.enumerated() {
            modes.setLabel(mode.title, forSegment: index)
            modes.setWidth(88, forSegment: index)
            modes.setToolTip(mode == .control ? "Щёлкать и перетаскивать в приложениях" : "Рисовать на экране", forSegment: index)
        }
        modes.target = self
        modes.action = #selector(changeMode(_:))
        selectMode(Preferences.pointerMode)
        stack.addArrangedSubview(modes)
        let ink = makeButton(image: nil, tip: "Цвет линий") { [weak self] in
            self?.toggleInk()
        }
        inkButton = ink
        stack.addArrangedSubview(ink)
        let sound = makeButton(symbol: "speaker.wave.2.fill", tip: "Звук касания") { [weak self] in
            self?.onToggleSound?()
        }
        soundButton = sound
        stack.addArrangedSubview(sound)
        stack.addArrangedSubview(makeButton(symbol: "xmark", tip: "Выход (Esc)") { [weak self] in
            self?.onExit?()
        })

        rebuildStyles()
        background.removeFocusRings()
        resize()
        refreshInk()
        NotificationCenter.default.addObserver(forName: Preferences.changed, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildStyles()
            self?.refreshInk()
        }
    }

    private func toggleCatalog() {
        if !closeCatalog() { showCatalog() }
    }

    private func showCatalog() {
        guard catalog == nil, let button = catalogButton,
              let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(400, visible.width - 24)
        let height = min(340, visible.maxY - panel.frame.maxY - 54)
        guard width >= 80, height >= 50 else { return }
        setInkOpen(false)
        hideHint()

        let pop = Panel(contentRect: CGRect(x: 0, y: 0, width: width, height: height + 34),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pop.isOpaque = false
        pop.backgroundColor = .clear
        pop.hasShadow = true
        pop.hidesOnDeactivate = false
        pop.isFloatingPanel = true
        pop.level = NSWindow.Level(rawValue: panel.level.rawValue + 2)
        pop.collectionBehavior = panel.collectionBehavior

        let glass = NSVisualEffectView.darkGlass(radius: 16)
        pop.contentView = glass
        let content = VStack(alignment: .leading, spacing: 0) {
            Text("Все указатели")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 34, alignment: .bottomLeading)
                .accessibilityAddTraits(.isHeader)
            PointerCatalog(selected: current, width: width, height: height) { [weak self] style in
                guard let self else { return }
                self.closeCatalog()
                self.onPick?(style)
            }
        }
        .environment(\.colorScheme, .dark)
        let host = CatalogHost(rootView: content)
        host.autoresizingMask = [.width, .height]
        host.frame = glass.bounds
        glass.addSubview(host)

        let anchor = panel.convertToScreen(button.convert(button.bounds, to: nil)).midX
        let x = min(max(anchor - width / 2, visible.minX + 12), visible.maxX - width - 12)
        pop.setFrameOrigin(CGPoint(x: x, y: panel.frame.maxY + 8))
        catalog = pop
        button.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        button.setAccessibilityLabel("Закрыть каталог указателей")
        pop.orderFrontRegardless()
        onCatalogVisibilityChanged?()
    }

    @discardableResult
    func closeCatalog() -> Bool {
        guard let pop = catalog else { return false }
        catalog = nil
        pop.orderOut(nil)
        catalogButton?.layer?.backgroundColor = NSColor.clear.cgColor
        catalogButton?.setAccessibilityLabel("Все указатели")
        onCatalogVisibilityChanged?()
        return true
    }

    func dismissCatalog(outside point: CGPoint) {
        if let catalogFrame, !catalogFrame.contains(point), !frame.contains(point) {
            closeCatalog()
        }
    }

    private func toggleInk() {
        setInkOpen(!inkOpen)
    }

    private func setInkOpen(_ open: Bool) {
        guard open != inkOpen, let ink = inkButton else {
            return
        }
        inkOpen = open
        if open {
            closeCatalog()
            if swatches.isEmpty {
                for choice in InkChoice.allCases {
                    let b = makeButton(image: nil, tip: choice.title, side: 30) { [weak self] in
                        Preferences.inkChoice = choice
                        self?.setInkOpen(false)
                    }
                    b.layer?.cornerRadius = 15
                    swatches[choice] = b
                    trayStack.addArrangedSubview(b)
                }
                tray.contentView?.removeFocusRings()
                trayStack.layoutSubtreeIfNeeded()
                tray.setContentSize(trayStack.fittingSize)
            }
            refreshInk()
            let r = panel.convertToScreen(ink.convert(ink.bounds, to: nil))
            let size = tray.frame.size
            tray.setFrameOrigin(CGPoint(x: r.midX - size.width / 2, y: panel.frame.maxY + 8))
            tray.invalidateShadow()
            tray.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                tray.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                tray.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self, !self.inkOpen else {
                    return
                }
                self.tray.orderOut(nil)
            })
        }
        refreshInk()
    }

    private func refreshInk() {
        guard let ink = inkButton else {
            return
        }
        let style = current ?? PointerStyle.saved
        ink.image = Toolbar.inkDot(Preferences.inkChoice.resolved(for: style))
        ink.layer?.backgroundColor = inkOpen ? NSColor(white: 1, alpha: 0.18).cgColor : NSColor.clear.cgColor
        let hidden = !Preferences.showInkButton
        if ink.isHidden != hidden {
            ink.isHidden = hidden
            if hidden {
                setInkOpen(false)
            }
            resizeKeepingCenter()
        }
        for (choice, b) in swatches {
            b.image = choice.color.map(Toolbar.inkDot) ?? Toolbar.rainbowDot()
            b.layer?.backgroundColor = choice == Preferences.inkChoice ? NSColor(white: 1, alpha: 0.2).cgColor : NSColor.clear.cgColor
        }
    }

    private func resizeKeepingCenter() {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY)
        resize()
        panel.setFrameOrigin(CGPoint(x: center.x - panel.frame.width / 2, y: center.y))
    }

    private func rebuildStyles() {
        var styles = Preferences.pinnedStyles
        if let c = current, !styles.contains(c) {
            styles.append(c)
        }
        if styles == shownStyles {
            return
        }
        shownStyles = styles
        for b in styleButtons.values {
            actions[b] = nil
            b.removeFromSuperview()
        }
        styleButtons = [:]
        for (i, style) in styles.enumerated() {
            let b = makeButton(image: Toolbar.icon(for: style), tip: style.title) { [weak self] in
                self?.onPick?(style)
            }
            styleButtons[style] = b
            stack.insertArrangedSubview(b, at: i)
        }
        if let c = current {
            highlight(c)
        }
        resizeKeepingCenter()
    }

    func setSoundOn(_ on: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let name = on ? "speaker.wave.2.fill" : "speaker.slash.fill"
        let tip = on ? "Выключить звук касания" : "Включить звук касания"
        soundButton?.image = NSImage(systemSymbolName: name, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        soundButton?.toolTip = tip
        soundButton?.setAccessibilityLabel(tip)
        soundButton?.contentTintColor = NSColor(white: 1, alpha: on ? 0.85 : 0.45)
    }

    func center(of style: PointerStyle) -> CGPoint? {
        guard let b = styleButtons[style], let w = b.window else {
            return nil
        }
        let r = w.convertToScreen(b.convert(b.bounds, to: nil))
        return CGPoint(x: r.midX, y: r.midY)
    }

    func center(of mode: PointerMode) -> CGPoint? {
        guard let window = modes.window, let index = PointerMode.allCases.firstIndex(of: mode) else { return nil }
        let r = window.convertToScreen(modes.convert(modes.bounds, to: nil))
        let segmentWidth = r.width / CGFloat(modes.segmentCount)
        return CGPoint(x: r.minX + (CGFloat(index) + 0.5) * segmentWidth, y: r.midY)
    }

    func snapshot() -> NSBitmapImageRep? {
        guard let view = panel.contentView else {
            return nil
        }
        view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        view.layer?.backgroundColor = nil
        return rep
    }

    func snapshotCatalog() -> NSBitmapImageRep? {
        guard let screen = NSScreen.main else { return nil }
        place(on: screen)
        showCatalog()
        defer { closeCatalog() }
        guard let view = catalog?.contentView else { return nil }
        view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func snapshotInkTray() -> NSBitmapImageRep? {
        setInkOpen(true)
        guard let view = tray.contentView else {
            return nil
        }
        view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func hintParts(for mode: PointerMode) -> [(key: String, text: String)] {
        var parts = mode == .control
            ? [(PointerMode.control.title, "приложениями"), (PointerMode.draw.title, "на экране")]
            : [("Щелчок", "— касание"), ("Перетаскивание", "— рисунок")]
        if mode == .draw && Preferences.interactKey != .off {
            parts.append(("Удерживайте \(Preferences.interactKey.symbol)", "для работы с окнами"))
        }
        parts.append(("Esc", "— выход"))
        return parts
    }

    func showHint(_ parts: [(key: String, text: String)]) {
        hideHint()
        let p = Panel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 36),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = panel.level
        p.collectionBehavior = panel.collectionBehavior
        p.alphaValue = 0
        let bg = NSVisualEffectView.darkGlass(radius: 12)
        p.contentView = bg
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        for part in parts {
            let text = NSMutableAttributedString(string: part.key, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
            text.append(NSAttributedString(string: " " + part.text, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: NSColor(white: 1, alpha: 0.7),
            ]))
            let label = NSTextField(labelWithAttributedString: text)
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byClipping
            row.addArrangedSubview(label)
        }
        bg.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            row.topAnchor.constraint(equalTo: bg.topAnchor),
            row.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        row.layoutSubtreeIfNeeded()
        p.setContentSize(row.fittingSize)
        p.setFrameOrigin(CGPoint(x: panel.frame.midX - p.frame.width / 2, y: panel.frame.maxY + 12))
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
        hint = p
    }

    func snapshotHint() -> NSBitmapImageRep? {
        guard let view = hint?.contentView else {
            return nil
        }
        view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func hideHint() {
        guard let p = hint else {
            return
        }
        hint = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }

    func select(_ style: PointerStyle) {
        closeCatalog()
        current = style
        rebuildStyles()
        highlight(style)
        refreshInk()
    }

    private func highlight(_ style: PointerStyle) {
        for (s, b) in styleButtons {
            b.layer?.backgroundColor = s == style ? NSColor(white: 1, alpha: 0.18).cgColor : NSColor.clear.cgColor
        }
    }

    func selectMode(_ mode: PointerMode) {
        if let index = PointerMode.allCases.firstIndex(of: mode) {
            modes.selectedSegment = index
        }
    }

    func place(on screen: NSScreen) {
        closeCatalog()
        setInkOpen(false)
        let f = panel.frame
        panel.setFrameOrigin(CGPoint(x: screen.frame.midX - f.width / 2, y: screen.visibleFrame.minY + 14))
    }

    func show() {
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func hide() {
        closeCatalog()
        setInkOpen(false)
        hideHint()
        revealed = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func setRevealed(_ value: Bool) {
        guard value != revealed else {
            return
        }
        revealed = value
        if !value {
            closeCatalog()
            setInkOpen(false)
        }
        panel.ignoresMouseEvents = !value
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = value ? 0.15 : 0.35
            panel.animator().alphaValue = value ? 1 : 0
        }
    }

    private func resize() {
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        panel.setContentSize(size)
        panel.invalidateShadow()
    }

    private var actions: [Button: () -> Void] = [:]

    private func makeButton(image: NSImage? = nil, symbol: String? = nil, tip: String, side: CGFloat = 40, action: @escaping () -> Void) -> Button {
        let b = Button()
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imageScaling = .scaleProportionallyUpOrDown
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        if let image = image {
            b.image = image
        }
        if let symbol = symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
            b.contentTintColor = NSColor(white: 1, alpha: 0.85)
            b.imageScaling = .scaleNone
        }
        b.widthAnchor.constraint(equalToConstant: side).isActive = true
        b.heightAnchor.constraint(equalToConstant: side).isActive = true
        b.target = self
        b.action = #selector(tapped(_:))
        actions[b] = action
        return b
    }

    @objc private func tapped(_ sender: Button) {
        actions[sender]?()
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        let options = PointerMode.allCases
        if options.indices.contains(sender.selectedSegment) {
            onSelectMode?(options[sender.selectedSegment])
        }
    }

    private static func inkDot(_ color: CGColor) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 13
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 2.5, width: 2 * r + 3, height: 2 * r + 3)).fill()
            (NSColor(cgColor: color) ?? .white).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
            NSColor(white: 1, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.15, width: r * 0.7, height: r * 0.5)).fill()
            return true
        }
    }

    private static func rainbowDot() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 13
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 2.5, width: 2 * r + 3, height: 2 * r + 3)).fill()
            let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
            for (i, color) in colors.enumerated() {
                let path = NSBezierPath()
                path.move(to: c)
                path.appendArc(withCenter: c, radius: r, startAngle: CGFloat(i) * 60 + 90, endAngle: CGFloat(i + 1) * 60 + 90)
                path.close()
                color.setFill()
                path.fill()
            }
            return true
        }
    }

    private static func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    static func icon(for style: PointerStyle) -> NSImage? {
        if let name = style.assetName {
            return HandAsset.thumbnail(name)
        }
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let red = NSColor(cgColor: Ink.red) ?? .systemRed
            let glow = NSGradient(colors: [red.withAlphaComponent(0.55), red.withAlphaComponent(0)])
            glow?.draw(in: NSBezierPath(ovalIn: rect.insetBy(dx: 14, dy: 14)), relativeCenterPosition: .zero)
            red.setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)).fill()
            NSColor(srgbRed: 1, green: 0.86, blue: 0.82, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)).fill()
            return true
        }
    }
}

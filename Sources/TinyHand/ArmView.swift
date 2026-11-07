import AppKit

final class ArmView: NSView {
    private let group = CALayer()
    private let rodLayer = CALayer()
    private let handLayer = CALayer()
    private let standaloneLayer = CALayer()
    private let catFollowerLayer = CALayer()
    private let dotLayer = CAShapeLayer()
    private let dotCore = CAShapeLayer()

    private(set) var style: PointerStyle = .lavender
    private var asset: HandAsset?
    private var pressedAsset: HandAsset?

    private var handLenFrac: CGFloat = Preferences.pointerSize
    private var showShadow = Preferences.showShadow
    private let minRodFrac: CGFloat = 0.05
    private let gripLeanFrac: CGFloat = 0.30
    private let gripDepthFrac: CGFloat = 0.12
    private let gripFollow: CGFloat = 0.08
    private let liftFrac: CGFloat = 0.06

    let ink = Ink()
    var held = false
    var inkWidth: CGFloat { max(3, bounds.height * 0.0055) }

    private var pressAmount: CGFloat = 0
    private var reactionUntil: CFTimeInterval?
    private var gripX: CGFloat?
    private var lastPose: [CGFloat] = []
    private var lastLaserRadius: CGFloat = 0
    private var gripTarget: CGFloat?
    private var displayImages: [ObjectIdentifier: (height: Int, image: CGImage)] = [:]
    private var displayImage: CGImage?
    private var catFollow: (position: CGPoint, target: CGPoint, time: CFTimeInterval, aboveLaser: Bool)?

    var isWand: Bool { style.rawValue == "funny10" }
    var isNyanCat: Bool { style.rawValue == "funny11" || style == .nyanFlight }
    private var rodHandLenFrac: CGFloat { isWand ? handLenFrac * 1.55 : handLenFrac }

    private var wandBurst: (cursor: CGPoint, endsAt: CFTimeInterval)?
    private lazy var wandSparks = (0..<10).map { index -> CAShapeLayer in
        let spark = CAShapeLayer()
        let length: CGFloat = index.isMultiple(of: 3) ? 8 : 5
        let half = length / 2
        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: -half, y: 0))
        shape.addLine(to: CGPoint(x: 0, y: 1.5))
        shape.addLine(to: CGPoint(x: half, y: 0))
        shape.addLine(to: CGPoint(x: 0, y: -1.5))
        shape.closeSubpath()

        let color = index.isMultiple(of: 3) ? Ink.hex(0xD8BBFF) : Ink.hex(0xFFF0BD)
        spark.bounds = CGRect(x: -half, y: -1.5, width: length, height: 3)
        spark.path = shape
        spark.fillColor = color
        spark.shadowPath = shape
        spark.shadowColor = color
        spark.shadowOffset = .zero
        spark.shadowRadius = 2.5
        spark.shadowOpacity = 0.9
        spark.opacity = 0
        layer?.addSublayer(spark)
        return spark
    }

    private var trailAnchor: (point: CGPoint, cursor: CGPoint, time: CFTimeInterval)?
    private var rainbowSegments: [CALayer] = []
    private var nextRainbowSegment = 0

    var isSettling: Bool {
        if pressAmount > 0.002 || reactionUntil != nil {
            return true
        }
        if style.isCatFollower {
            return catFollow.map { $0.position != $0.target } ?? false
        }
        guard !style.isStandaloneCursor, let gx = gripX, let target = gripTarget else {
            return false
        }
        return abs(target - gx) > 0.5
    }

    var pointerHidden = false {
        didSet {
            if pointerHidden { clearPointerEffects() }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updatePointerVisibility()
            CATransaction.commit()
        }
    }

    private func updatePointerVisibility() {
        let cat = style.isCatFollower
        let hideCat = pointerHidden || !cat || catFollow == nil
        group.isHidden = pointerHidden || style == .laser || cat || style.isStandaloneCursor
        standaloneLayer.isHidden = pointerHidden || !style.isStandaloneCursor
        catFollowerLayer.isHidden = hideCat
        dotLayer.isHidden = pointerHidden || (style != .laser && hideCat)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        root.addSublayer(ink.layer)
        root.addSublayer(group)
        root.addSublayer(standaloneLayer)
        standaloneLayer.magnificationFilter = .nearest
        standaloneLayer.minificationFilter = .nearest
        standaloneLayer.shadowColor = NSColor.black.cgColor
        standaloneLayer.shadowOffset = CGSize(width: 1, height: -1.5)
        standaloneLayer.shadowRadius = 2

        root.addSublayer(catFollowerLayer)
        catFollowerLayer.shadowColor = NSColor.black.cgColor
        catFollowerLayer.shadowOffset = CGSize(width: 1, height: -2)
        catFollowerLayer.shadowRadius = 3
        root.addSublayer(dotLayer)

        group.masksToBounds = false
        group.addSublayer(rodLayer)
        group.addSublayer(handLayer)
        for sub in [rodLayer, handLayer] {
            sub.contentsGravity = .resize
            sub.contentsScale = 2
            sub.anchorPoint = CGPoint(x: 0.5, y: 0)
            sub.shadowColor = NSColor.black.cgColor
            sub.shadowOpacity = 0.38
        }

        dotLayer.fillColor = Ink.red
        dotLayer.shadowColor = Ink.red
        dotLayer.shadowOpacity = 1
        dotLayer.shadowOffset = .zero
        dotCore.fillColor = CGColor(srgbRed: 1, green: 0.86, blue: 0.82, alpha: 0.95)
        dotLayer.addSublayer(dotCore)

        setStyle(PointerStyle.saved)
        NotificationCenter.default.addObserver(forName: Preferences.changed, object: nil, queue: .main) { [weak self] _ in
            self?.handLenFrac = Preferences.pointerSize
            self?.showShadow = Preferences.showShadow
        }
    }

    func updateInkColor() {
        ink.color = Preferences.inkChoice.resolved(for: style)
    }

    func setStyle(_ newStyle: PointerStyle) {
        clearPointerEffects()
        style = newStyle
        asset = newStyle.assetName.flatMap(HandAsset.load)
        pressedAsset = newStyle.pressedAssetName.flatMap(HandAsset.load)
        if newStyle.isCatFollower || pressedAsset != nil { pressAmount = 0 }
        displayImages.removeAll()
        displayImage = nil
        if newStyle != .laser && asset == nil {
            style = .laser
            pressedAsset = nil
        }
        updateInkColor()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        standaloneLayer.contents = style.isStandaloneCursor ? asset?.image : nil
        catFollowerLayer.contents = nil
        if let a = asset, style != .laser {
            if style.isCatFollower {
                catFollowerLayer.contents = a.image
                catFollowerLayer.magnificationFilter = style == .catPixel ? .nearest : .linear
                catFollowerLayer.minificationFilter = style == .catPixel ? .nearest : .linear
                displayImage = a.image
            } else if style.isStandaloneCursor {
                standaloneLayer.bounds = .zero
                standaloneLayer.anchorPoint = CGPoint(x: a.tipX, y: 1 - a.tip)
            } else {
                if let pressedAsset { _ = preparedDisplayImage(pressedAsset) }
                updateDisplayImage(a)
            }
        }
        updatePointerVisibility()
        CATransaction.commit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    func press(at now: CFTimeInterval = CACurrentMediaTime()) {
        if pointerHidden && (style.isCatFollower || pressedAsset != nil) { return }
        pressAmount = 1
        if pressedAsset != nil {
            reactionUntil = now + 0.15
        }
    }

    private func reactionAsset(at now: CFTimeInterval) -> HandAsset? {
        guard let reactionUntil, held || now < reactionUntil else {
            self.reactionUntil = nil
            return nil
        }
        return pressedAsset
    }

    func showWandSparks(at cursor: CGPoint) {
        guard isWand, !pointerHidden, let asset, let layer else { return }
        aim(cursor: cursor)
        stopWandSparks()

        let tipInset = (asset.tip - asset.handTop) / (asset.wrist - asset.handTop) * handLayer.bounds.height
        let localTip = CGPoint(x: asset.tipX * group.bounds.width, y: group.bounds.maxY - tipInset)
        let tip = group.convert(localTip, to: layer)
        let heading = atan2(tip.y - group.position.y, tip.x - group.position.x)
        let maxLifetime: CFTimeInterval = 0.34
        wandBurst = (cursor, CACurrentMediaTime() + maxLifetime)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, spark) in wandSparks.enumerated() {
            let spread = CGFloat(index) / CGFloat(wandSparks.count - 1) - 0.5
            let angle = heading + spread * 2.6 + CGFloat.random(in: -0.12...0.12)
            let distance = CGFloat.random(in: 20...57)
            let start = CGPoint(x: tip.x + cos(angle) * 3, y: tip.y + sin(angle) * 3)
            let end = CGPoint(x: tip.x + cos(angle) * distance, y: tip.y + sin(angle) * distance)
            let lifetime = Double.random(in: 0.20...maxLifetime)
            spark.setAffineTransform(CGAffineTransform(rotationAngle: angle))

            let flight = CABasicAnimation(keyPath: "position")
            flight.fromValue = start
            flight.toValue = end
            flight.duration = lifetime
            flight.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 0.85, 0]
            fade.keyTimes = [0, 0.22, 1]
            fade.duration = lifetime

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = 0.3
            shrink.duration = lifetime

            let burst = CAAnimationGroup()
            burst.animations = [flight, fade, shrink]
            burst.duration = lifetime
            spark.add(burst, forKey: "burst")
        }
        CATransaction.commit()
    }

    func clearPointerEffects() {
        stopWandSparks()
        reactionUntil = nil
        if pressedAsset != nil { pressAmount = 0 }
        if style.isCatFollower {
            catFollow = nil
            pressAmount = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updatePointerVisibility()
            CATransaction.commit()
        }
        if trailAnchor != nil {
            trailAnchor = nil
            nextRainbowSegment = 0
            rainbowSegments.forEach { $0.removeAllAnimations() }
        }
    }

    private func stopWandSparks() {
        guard wandBurst != nil else { return }
        wandBurst = nil
        wandSparks.forEach { $0.removeAllAnimations() }
    }

    private func makeRainbowSegments() -> [CALayer] {
        let colors: [UInt32] = [0xFF5261, 0xFF9D45, 0xFFDB56, 0x62E582, 0x49C7FF, 0xA87BFF]
        guard let context = CGContext(data: nil, width: 1, height: colors.count, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
        for (index, color) in colors.enumerated() {
            context.setFillColor(Ink.hex(color))
            context.fill(CGRect(x: 0, y: colors.count - index - 1, width: 1, height: 1))
        }
        guard let image = context.makeImage() else { return [] }

        return (0..<24).map { _ in
            let segment = CALayer()
            segment.contents = image
            segment.magnificationFilter = .nearest
            segment.allowsEdgeAntialiasing = true
            segment.opacity = 0
            layer?.insertSublayer(segment, below: group)
            return segment
        }
    }

    private func updateRainbowTrail(at cursor: CGPoint, emitter: CGPoint? = nil, now: CFTimeInterval = CACurrentMediaTime()) {
        let point = emitter ?? cursor
        guard let anchor = trailAnchor else {
            trailAnchor = (point, cursor, now)
            return
        }
        if cursor == anchor.cursor {
            // A press can resize the flying cat without moving the cursor.
            if point != anchor.point { trailAnchor = (point, cursor, anchor.time) }
            return
        }
        // The pointer timer can run at 120 Hz. Sample about every other tick.
        guard now - anchor.time >= 0.014 else { return }
        let dx = point.x - anchor.point.x
        let dy = point.y - anchor.point.y
        let distance = hypot(dx, dy)
        let cursorDistance = emitter == nil ? distance : hypot(cursor.x - anchor.cursor.x, cursor.y - anchor.cursor.y)
        guard distance >= 2, cursorDistance >= 2 else { return }
        trailAnchor = (point, cursor, now)
        // A cursor warp should not draw a stripe across the whole screen.
        guard distance <= 160, cursorDistance <= 160 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if rainbowSegments.isEmpty { rainbowSegments = makeRainbowSegments() }
        guard !rainbowSegments.isEmpty else { return }
        let segment = rainbowSegments[nextRainbowSegment]
        nextRainbowSegment = (nextRainbowSegment + 1) % rainbowSegments.count
        let height = max(12, min(28, handLenFrac * bounds.height * 0.19))
        segment.bounds = CGRect(x: 0, y: 0, width: distance + 1, height: height)
        segment.position = CGPoint(x: anchor.point.x + dx / 2, y: anchor.point.y + dy / 2)
        segment.setAffineTransform(CGAffineTransform(rotationAngle: atan2(dy, dx)))

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.94
        fade.toValue = 0
        fade.duration = 0.34
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        segment.add(fade, forKey: "fade")
    }

    func aim(cursor: CGPoint, at now: CFTimeInterval = CACurrentMediaTime()) {
        if let burst = wandBurst,
           now >= burst.endsAt || hypot(cursor.x - burst.cursor.x, cursor.y - burst.cursor.y) > 6 {
            stopWandSparks()
        }
        if style.rawValue == "funny11" && !pointerHidden { updateRainbowTrail(at: cursor) }
        if style.isCatFollower, let asset {
            if !pointerHidden { aimCatFollower(cursor: cursor, asset: asset, now: now) }
            return
        }
        if !held {
            pressAmount += (0 - pressAmount) * 0.18
        }
        if style.isStandaloneCursor, let asset {
            aimStandalone(cursor: cursor, asset: asset)
            if style == .nyanFlight, !pointerHidden {
                let tail = CGPoint(x: standaloneLayer.bounds.width * 0.20, y: standaloneLayer.bounds.height * 0.42)
                let emitter = standaloneLayer.convert(tail, to: layer)
                updateRainbowTrail(at: cursor, emitter: emitter, now: now)
            }
            return
        }

        let screenH = bounds.height
        let targetX = min(max(cursor.x + gripLeanFrac * bounds.width, bounds.width * 0.15), bounds.width * 1.05)
        let gx = gripX.map { $0 + (targetX - $0) * gripFollow } ?? targetX
        gripX = gx
        gripTarget = targetX
        var grip = CGPoint(x: gx, y: -gripDepthFrac * screenH)
        if style == .laser {
            aimLaser(cursor: cursor)
            return
        }
        guard let a = reactionAsset(at: now) ?? asset else {
            return
        }
        updateDisplayImage(a)

        let dx = cursor.x - grip.x
        let dy = cursor.y - grip.y
        let reach = hypot(dx, dy)
        let aimAngle = atan2(dy, dx)

        let handPts = rodHandLenFrac * screenH * (1 - 0.06 * pressAmount)
        let s = handPts / (a.wrist - a.handTop)
        let widthPts = s * a.aspect
        let handTipPts = (a.wrist - a.tip) * s
        let tipOffX = (a.tipX - a.rodX) * widthPts

        let along = sqrt(max(0, reach * reach - tipOffX * tipOffX))
        let minRodLen = minRodFrac * screenH
        let rodLen = max(minRodLen, along - handTipPts)
        let tipAngle = atan2(rodLen + handTipPts, tipOffX)
        let rotation = aimAngle - tipAngle
        let keepsExactTip = isWand || pressedAsset != nil
        if keepsExactTip && rodLen == minRodLen {
            // Keep the hotspot aligned even when the minimum rod length moves the grip back.
            let correction = reach - hypot(rodLen + handTipPts, tipOffX)
            grip.x += cos(aimAngle) * correction
            grip.y += sin(aimAngle) * correction
        }

        let lift = currentLift(screenH)
        let sx = lift * 0.6
        let sy = -lift
        let shadowOffset = CGSize(
            width: sx * cos(-rotation) - sy * sin(-rotation),
            height: sx * sin(-rotation) + sy * cos(-rotation)
        )

        let values = [rotation, rodLen, handPts, widthPts, grip.x, grip.y, lift, pressAmount, showShadow ? 1 : 0, a.aspect]
        let pose = keepsExactTip ? values : values.map { ($0 * 100).rounded() }
        guard pose != lastPose else {
            return
        }
        lastPose = pose

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for sub in [rodLayer, handLayer] {
            sub.shadowOffset = shadowOffset
            sub.shadowRadius = max(1, lift * 0.35) + 5 * pressAmount
            sub.shadowOpacity = showShadow ? Float(0.26 + 0.02 * pressAmount) : 0
        }

        rodLayer.bounds = CGRect(x: 0, y: 0, width: widthPts, height: rodLen)
        rodLayer.position = CGPoint(x: widthPts / 2, y: 0)
        handLayer.bounds = CGRect(x: 0, y: 0, width: widthPts, height: handPts)
        handLayer.position = CGPoint(x: widthPts / 2, y: rodLen)

        group.bounds = CGRect(x: 0, y: 0, width: widthPts, height: rodLen + handPts)
        group.position = grip
        group.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)

        CATransaction.commit()
    }

    private func currentLift(_ screenH: CGFloat) -> CGFloat {
        liftFrac * screenH * (1 - 0.8 * pressAmount)
    }

    private func aimStandalone(cursor: CGPoint, asset: HandAsset) {
        let sizeScale: CGFloat = style == .nyanFlight ? 1.05 : 0.8
        let height = handLenFrac * bounds.height * sizeScale * (1 - 0.06 * pressAmount)
        let spriteBounds = CGRect(x: 0, y: 0, width: height * asset.aspect, height: height)
        let shadowOpacity: Float = showShadow ? 0.26 : 0
        guard standaloneLayer.position != cursor || standaloneLayer.bounds != spriteBounds
                || standaloneLayer.shadowOpacity != shadowOpacity else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        standaloneLayer.bounds = spriteBounds
        standaloneLayer.position = cursor
        standaloneLayer.shadowOpacity = shadowOpacity
        CATransaction.commit()
    }

    private func aimCatFollower(cursor: CGPoint, asset: HandAsset, now: CFTimeInterval) {
        let previous = catFollow
        let elapsed = previous.map { max(0, now - $0.time) } ?? (1.0 / 120)
        if !held {
            pressAmount *= CGFloat(exp(-elapsed / 0.045))
        }

        let frame = reactionAsset(at: now) ?? asset
        let sizeScale: CGFloat = style == .catLaser ? 2 : 1.6
        let height = min(handLenFrac * bounds.height * 0.54 * sizeScale, bounds.width * 0.4 / frame.aspect)
            * (1 - 0.06 * pressAmount)
        let halfWidth = height * frame.aspect / 2
        let halfHeight = height / 2
        let gap = laserRadius + 5
        let centers = bounds.insetBy(dx: halfWidth, dy: halfHeight)
        let offsetY = halfHeight + gap
        let below = cursor.y - offsetY
        // Stay above until there is room to return below without flipping at the edge.
        let returnMargin = min(24, max(10, height * 0.15))
        let aboveLaser = below < centers.minY + (previous?.aboveLaser == true ? returnMargin : 0)
        let targetY = aboveLaser ? cursor.y + offsetY : below
        let target = CGPoint(
            x: min(centers.maxX, max(centers.minX, cursor.x + halfWidth * 0.38)),
            y: min(centers.maxY, max(centers.minY, targetY))
        )

        var position = target
        if let previous, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let dx = target.x - previous.position.x
            let dy = target.y - previous.position.y
            let distance = hypot(dx, dy)
            let maxSpeed = max(1200, max(bounds.width, bounds.height) * 2.3)
            let maxTravel = maxSpeed * elapsed
            let easing = CGFloat(1 - exp(-elapsed / 0.048))
            let travel = min(distance * easing, maxTravel)
            if distance - travel > 0.5 || distance > maxTravel {
                let step = travel / distance
                position.x = previous.position.x + dx * step
                position.y = previous.position.y + dy * step
            }
        }
        // Keep the actual rendered position as the starting point for the next frame.
        // The laser renders above the sprite during brief crossings.
        position.x = min(centers.maxX, max(centers.minX, position.x))
        position.y = min(centers.maxY, max(centers.minY, position.y))
        catFollow = (position, target, now, aboveLaser)

        let spriteBounds = CGRect(x: 0, y: 0, width: halfWidth * 2, height: height)
        let shadowOpacity: Float = showShadow ? 0.26 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if displayImage !== frame.image {
            displayImage = frame.image
            catFollowerLayer.contents = frame.image
        }
        if catFollowerLayer.bounds != spriteBounds { catFollowerLayer.bounds = spriteBounds }
        if catFollowerLayer.position != position { catFollowerLayer.position = position }
        if catFollowerLayer.shadowOpacity != shadowOpacity { catFollowerLayer.shadowOpacity = shadowOpacity }
        aimLaser(cursor: cursor)
        if previous == nil { updatePointerVisibility() }
        CATransaction.commit()
    }

    private var laserRadius: CGFloat {
        max(4, bounds.height * 0.0038 * handLenFrac / 0.13) * (1 + 0.2 * pressAmount)
    }

    private func aimLaser(cursor: CGPoint) {
        let r = laserRadius
        let shadowRadius = r * (2.2 + pressAmount)
        guard dotLayer.position != cursor || r != lastLaserRadius || dotLayer.shadowRadius != shadowRadius else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if r != lastLaserRadius {
            lastLaserRadius = r
            let core = r * 0.45
            let dot = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            dotLayer.path = dot
            dotLayer.shadowPath = dot
            dotCore.path = CGPath(ellipseIn: CGRect(x: -core, y: -core, width: 2 * core, height: 2 * core), transform: nil)
        }
        dotLayer.position = cursor
        dotLayer.shadowRadius = shadowRadius
        CATransaction.commit()
    }

    private func preparedDisplayImage(_ a: HandAsset) -> CGImage {
        let full = a.image
        let scale = window?.backingScaleFactor ?? 2
        let restPts = rodHandLenFrac * bounds.height / (a.wrist - a.handTop)
        let step = 64
        let needed = (Int((restPts * scale).rounded(.up)) + step - 1) / step * step
        let height = needed >= full.height * 9 / 10 ? full.height : max(step, needed)
        let key = ObjectIdentifier(full)
        if let cached = displayImages[key], cached.height == height { return cached.image }
        let image = height == full.height ? full : HandAsset.resized(full, height: height) ?? full
        displayImages[key] = (height, image)
        return image
    }

    private func updateDisplayImage(_ a: HandAsset) {
        let image = preparedDisplayImage(a)
        guard displayImage !== image else { return }
        displayImage = image
        lastPose = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        group.anchorPoint = CGPoint(x: a.rodX, y: 0)
        rodLayer.contentsRect = CGRect(x: 0, y: 1 - a.rodEnd, width: 1, height: a.rodEnd - a.wrist)
        handLayer.contentsRect = CGRect(x: 0, y: 1 - a.wrist, width: 1, height: a.wrist - a.handTop)
        rodLayer.contents = image
        handLayer.contents = image
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        applyBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyBackingScale()
    }

    private func applyBackingScale() {
        let scale = window?.backingScaleFactor ?? 2
        rodLayer.contentsScale = scale
        handLayer.contentsScale = scale
        standaloneLayer.contentsScale = scale
        catFollowerLayer.contentsScale = scale
        ink.scale = scale
    }
}

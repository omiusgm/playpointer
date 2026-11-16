import AppKit

/// A brief highlight around the position of a primary click.
final class ClickPulse {
    private let rings = (0..<3).map { _ in CAShapeLayer() }
    private var nextRing = 0
    private lazy var comicImpacts = (0..<3).map { _ -> CALayer in
        let impact = CALayer()
        for color in [NSColor.white, NSColor.black] {
            let strokes = CAShapeLayer()
            strokes.fillColor = nil
            strokes.strokeColor = color.cgColor
            strokes.lineWidth = color == .white ? 4.5 : 2
            strokes.lineCap = .round
            impact.addSublayer(strokes)
        }
        impact.opacity = 0
        return impact
    }
    private var nextImpact = 0

    func showComic(at point: CGPoint, strength: CGFloat, in layer: CALayer) {
        let impact = comicImpacts[nextImpact]
        nextImpact = (nextImpact + 1) % comicImpacts.count
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let extent: CGFloat = reduceMotion ? 18 : 21 * sqrt(strength)
        let path = CGMutablePath()
        for index in 0..<9 {
            let angle = CGFloat(index) * 2 * .pi / 9
            let inner: CGFloat = index.isMultiple(of: 2) ? 8 : 11
            let outer = extent * (index.isMultiple(of: 2) ? 1 : 0.8)
            path.move(to: CGPoint(x: cos(angle) * inner, y: sin(angle) * inner))
            path.addLine(to: CGPoint(x: cos(angle) * max(inner + 3, outer),
                                    y: sin(angle) * max(inner + 3, outer)))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        impact.removeAllAnimations()
        if impact.superlayer !== layer { layer.addSublayer(impact) }
        impact.position = point
        for strokes in impact.sublayers ?? [] {
            (strokes as? CAShapeLayer)?.path = path
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.22, 1]
        fade.duration = 0.23
        let burst = CAAnimationGroup()
        burst.duration = fade.duration
        burst.animations = [fade]
        if !reduceMotion {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.72
            grow.toValue = 1.15
            grow.duration = burst.duration
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            burst.animations?.append(grow)
        }
        impact.add(burst, forKey: "comicImpact")
        CATransaction.commit()
    }

    func show(at point: CGPoint, color: CGColor, strength: CGFloat = 1, in layer: CALayer) {
        let ring = rings[nextRing]
        nextRing = (nextRing + 1) % rings.count
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let radius: CGFloat = reduceMotion ? 12 : 12 * sqrt(strength)
        let duration: CFTimeInterval = 0.27

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.removeAllAnimations()
        if ring.superlayer !== layer { layer.addSublayer(ring) }
        ring.bounds = CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)
        ring.position = point
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 1.2, dy: 1.2), transform: nil)
        ring.fillColor = nil
        let tint = NSColor(cgColor: color)?.blended(withFraction: 0.34, of: .white)
        ring.strokeColor = tint?.cgColor ?? NSColor.white.cgColor
        ring.lineWidth = reduceMotion ? 2 : min(3, 1 + strength)
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOffset = CGSize(width: 0, height: -1)
        ring.shadowRadius = 2
        ring.shadowOpacity = 0.8
        ring.opacity = 0

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0.85, 0]
        fade.keyTimes = [0, 0.18, 1]
        fade.duration = duration
        let pulse = CAAnimationGroup()
        pulse.duration = duration
        pulse.animations = [fade]
        if !reduceMotion {
            let expand = CABasicAnimation(keyPath: "transform.scale")
            expand.fromValue = 0.68
            expand.toValue = 1.65
            expand.duration = duration
            expand.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.animations?.append(expand)
        }
        ring.add(pulse, forKey: "click")
        CATransaction.commit()
    }

    func clear() {
        for ring in rings { ring.removeAllAnimations() }
        for impact in comicImpacts { impact.removeAllAnimations() }
    }
}

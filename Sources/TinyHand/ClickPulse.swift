import AppKit

/// A brief highlight around the position of a primary click.
final class ClickPulse {
    private let rings = (0..<3).map { _ in CAShapeLayer() }
    private var nextRing = 0

    func show(at point: CGPoint, color: CGColor, in layer: CALayer) {
        let ring = rings[nextRing]
        nextRing = (nextRing + 1) % rings.count
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let radius: CGFloat = 12
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
        ring.lineWidth = 2
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
    }
}

import AppKit

enum ClickStrength: String, CaseIterable {
    case quiet, soft, normal, bright, show

    var title: String {
        switch self {
        case .quiet: return "Тихо"
        case .soft: return "Мягко"
        case .normal: return "Обычно"
        case .bright: return "Ярко"
        case .show: return "Шоу"
        }
    }

    var amplitude: CGFloat {
        switch self {
        case .quiet: return 0.35
        case .soft: return 0.65
        case .normal: return 1
        case .bright: return 1.3
        case .show: return 1.65
        }
    }
}

struct ClickCadence {
    private var lastClick: CFTimeInterval?
    private var energy: CGFloat = 0

    mutating func register(at now: CFTimeInterval, strength: ClickStrength) -> CGFloat {
        if let lastClick, now >= lastClick, now - lastClick < 0.65 {
            energy = min(1, energy * CGFloat(exp(-(now - lastClick) / 0.4)) + 0.25)
        } else {
            energy = 0
        }
        lastClick = now
        return min(2.1, strength.amplitude * (1 + energy * 0.35))
    }

    mutating func reset() {
        lastClick = nil
        energy = 0
    }
}

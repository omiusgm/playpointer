import Foundation

// This fork has no update channel. The compatibility surface keeps the settings
// UI hidden until a separately owned, signed update system is implemented.
final class Updater {
    static let isAvailable = false
    func start() {}
    func checkForUpdates() {}
    var automaticallyChecks: Bool {
        get { false }
        set {}
    }
}

import Foundation

// Pointer movement and clicks are intentionally not persisted.
enum Log {
    static func write(_ message: @autoclosure () -> String) {}
}

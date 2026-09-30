import Foundation

public enum WorkerLog {
    private enum Level: Int {
        case debug = 10
        case info = 20
        case warn = 30
        case error = 40
    }

    private static let configuredLevel: Level = {
        switch ProcessInfo.processInfo.environment["LOG_LEVEL"]?.lowercased() {
        case "debug": .debug
        case "info": .info
        case "error": .error
        default: .warn
        }
    }()

    public static func debug(_ message: String) { write(.debug, message) }
    public static func info(_ message: String) { write(.info, message) }
    public static func warn(_ message: String) { write(.warn, message) }
    public static func error(_ message: String) { write(.error, message) }

    private static func write(_ level: Level, _ message: String) {
        guard level.rawValue >= configuredLevel.rawValue else { return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

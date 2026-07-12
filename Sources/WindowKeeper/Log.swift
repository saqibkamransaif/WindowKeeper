import Foundation

/// Minimal file logger. Writes to ~/Library/Application Support/WindowKeeper/logs/system.log
/// and mirrors to stderr so `--diagnose` and dev runs show output.
final class Log {
    static let shared = Log()

    private let url: URL
    private let queue = DispatchQueue(label: "windowkeeper.log")
    private let formatter: DateFormatter

    private init() {
        let dir = LogPaths.logsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("system.log")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func info(_ message: String) { write("INFO", message) }
    func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] [\(level)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async { [url] in
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}

enum LogPaths {
    static func logsDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowKeeper/logs", isDirectory: true)
    }
}

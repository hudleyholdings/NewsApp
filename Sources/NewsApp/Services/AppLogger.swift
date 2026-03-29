import Foundation
import os

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let logger = Logger(subsystem: "NewsApp", category: "app")
    private let queue = DispatchQueue(label: "NewsAppLogger")
    private let logURL: URL
    private let dateFormatter: ISO8601DateFormatter

    private init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDirectory = libraryURL.appendingPathComponent("Logs/NewsApp", isDirectory: true)
        if !FileManager.default.fileExists(atPath: logsDirectory.path) {
            try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
        logURL = logsDirectory.appendingPathComponent("newsapp.log")
        dateFormatter = ISO8601DateFormatter()
    }

    var logFileURL: URL {
        logURL
    }

    func log(_ message: String) {
        let sanitized = sanitizeMessage(message)
        logger.info("\(sanitized, privacy: .public)")
        write(sanitized)
    }

    func error(_ message: String) {
        let sanitized = sanitizeMessage(message)
        logger.error("\(sanitized, privacy: .public)")
        write("ERROR: \(sanitized)")
    }

    /// Sanitize log messages to remove potentially sensitive URL details
    private func sanitizeMessage(_ message: String) -> String {
        // Remove full URLs, keeping just the domain for debugging
        var result = message
        // Match url=https://... patterns and truncate
        if let range = result.range(of: "url=https?://[^\\s]+", options: .regularExpression) {
            let url = String(result[range])
            if let urlObj = URL(string: String(url.dropFirst(4))), let host = urlObj.host {
                result.replaceSubrange(range, with: "url=\(host)/...")
            }
        }
        return result
    }

    func begin(_ name: String) -> AppLogTimer {
        AppLogTimer(name: name, logger: self)
    }

    private func write(_ message: String) {
        let line = "\(dateFormatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: self.logURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.logURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: self.logURL, options: [.atomic])
            }
        }
    }
}

struct AppLogTimer {
    let name: String
    private let start: DispatchTime
    private let logger: AppLogger

    init(name: String, logger: AppLogger) {
        self.name = name
        self.logger = logger
        self.start = DispatchTime.now()
    }

    func end() {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let ms = Double(elapsed) / 1_000_000
        logger.log("PERF \(name) \(String(format: "%.1f", ms))ms")
    }
}

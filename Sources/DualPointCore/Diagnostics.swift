import Foundation
import Combine
import os.log

public struct DiagnosticEntry: Identifiable, Equatable {
    public let id: UInt64
    public let date: Date
    public let category: String
    public let message: String

    public var line: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "\(formatter.string(from: date)) [\(category)] \(message)"
    }
}

/// A small in-memory activity log plus an optional on-disk log for support.
/// Only meaningful events are logged (device changes, switches, permissions),
/// never raw movement data or keystrokes.
@MainActor
public final class DiagnosticLog: ObservableObject {
    @Published public private(set) var entries: [DiagnosticEntry] = []
    @Published public private(set) var fileLoggingEnabled: Bool = true

    public let fileURL: URL
    private let maxEntries: Int
    private let queue = DispatchQueue(label: "com.dualpoint.diagnostics", qos: .utility)
    private let logger = Logger(subsystem: "com.dualpoint.DualPoint", category: "DualPoint")
    private var nextID: UInt64 = 1

    public init(maxEntries: Int = 400) {
        self.maxEntries = maxEntries
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/DualPoint", isDirectory: true)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DualPoint")
        self.fileURL = logs.appendingPathComponent("DualPoint.log")
        prepareFileLog()
    }

    private func prepareFileLog() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
               size.intValue > 512 * 1024 {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.error("Could not prepare log directory: \(error.localizedDescription)")
        }
    }

    public func info(_ category: String, _ message: String) {
        append(category, message, level: .info)
    }

    public func warning(_ category: String, _ message: String) {
        append(category, message, level: .warning)
    }

    public func error(_ category: String, _ message: String) {
        append(category, message, level: .error)
    }

    /// High-volume routing detail. Unlike the methods above this never enters
    /// the in-memory list observed by SwiftUI, so enabling a trace cannot make
    /// the panel churn. It is written to the file log and unified logging only.
    public func trace(_ category: String, _ message: String) {
        logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        guard fileLoggingEnabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) T [\(category)] \(message)\n"
        let url = fileURL
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private enum Level: String {
        case info = "I"
        case warning = "W"
        case error = "E"
    }

    private func append(_ category: String, _ message: String, level: Level) {
        let entry = DiagnosticEntry(id: nextID, date: Date(), category: category, message: message)
        nextID += 1
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        switch level {
        case .info: logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning: logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error: logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }

        guard fileLoggingEnabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: entry.date)) \(level.rawValue) [\(category)] \(message)\n"
        let url = fileURL
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func setFileLoggingEnabled(_ enabled: Bool) {
        fileLoggingEnabled = enabled
        if enabled {
            info("Diagnostics", "File logging enabled")
        }
    }

    public func clear() {
        entries.removeAll()
    }

    public func recentText(limit: Int = 200) -> String {
        entries.suffix(limit).map(\.line).joined(separator: "\n")
    }
}

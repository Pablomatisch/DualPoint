import Foundation

/// Loads and saves DualPoint's persistent device state as inspectable JSON.
///
/// All reads/writes happen on the main thread; disk writes are handed to a
/// serial queue and coalesced so cursor tracking stays cheap.
@MainActor
public final class StateStore {
    public private(set) var state: PersistedState
    public let fileURL: URL

    private let saveQueue = DispatchQueue(label: "com.dualpoint.state-store", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval

    public init(directory: URL? = nil, saveDelay: TimeInterval = 0.6) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("state.json")
        self.saveDelay = saveDelay
        self.state = PersistedState()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("DualPoint: could not create state directory: \(error)")
        }
        load()
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DualPoint", isDirectory: true)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            state = decoded
            if state.schemaVersion != PersistedState.currentSchemaVersion {
                state.schemaVersion = PersistedState.currentSchemaVersion
                scheduleSave()
            }
        } catch {
            NSLog("DualPoint: state file could not be read, starting fresh: \(error)")
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    /// Mutates state and schedules a coalesced save.
    public func update(_ body: (inout PersistedState) -> Void) {
        body(&state)
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = state
        let url = fileURL
        let queue = saveQueue
        let item = DispatchWorkItem {
            Self.write(snapshot, to: url, on: queue)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }

    /// Writes immediately. Called on quit so positions survive a restart.
    public func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = state
        let url = fileURL
        saveQueue.sync {
            Self.write(snapshot, to: url, on: nil)
        }
    }

    private nonisolated static func write(_ state: PersistedState, to url: URL, on queue: DispatchQueue?) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("DualPoint: could not save state: \(error)")
        }
    }
}

import Foundation

enum PersistedCompanionMode: String, Codable {
    case idle
    case checkIn
    case routine
    case complete
}

struct PersistedCompanionState: Codable, Equatable {
    let mode: PersistedCompanionMode
    let activeUse: ActiveUseTracker.PersistenceState
    let scheduledCheckInStartedAt: Date?
    let scheduledCheckInDueAt: Date?
    /// The next wall-clock reminder for an undecided pause offer. Optional keeps
    /// checkpoints written before repeat reminders were introduced readable.
    let pendingOfferReminderDueAt: Date?
    let routineMoveIDs: [String]
    let stepIndex: Int
    let elapsedInStep: Int
    let isPaused: Bool
    let isCheckInCollapsed: Bool
}

/// Stores only the small amount of live timer/session state needed to resume after
/// a normal relaunch. The file is deliberately in per-user Application Support,
/// never inside the replaceable app bundle.
struct CompanionStateStore {
    static let applicationDirectoryName = "2m2better"
    static let fileName = "companion-state.json"

    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() -> PersistedCompanionState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedCompanionState.self, from: data)
    }

    func save(_ state: PersistedCompanionState) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            // Losing a checkpoint must never prevent the companion from running;
            // the next state transition gets another chance to save it.
        }
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent(applicationDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

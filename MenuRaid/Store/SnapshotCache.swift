import Foundation

/// How often the snapshot is written. The panel refreshes every 5 s while open, but a snapshot at most 30 s old is
/// plenty for "what it looked like last time", and rewriting a file that often is needless disk churn.
nonisolated enum CacheWritePolicy {
    static let minimumInterval: TimeInterval = 30

    static func shouldWrite(lastWrite: Date?, now: Date = .now) -> Bool {
        guard let lastWrite else { return true }
        return now.timeIntervalSince(lastWrite) >= minimumInterval
    }
}

/// Last good snapshot, kept on disk so the panel has something to show at launch.
/// Lives in Application Support/MenuRaid/ (inside the app sandbox). Never contains the API key.
nonisolated struct SnapshotCache: Sendable {
    let url: URL

    init(serverID: UUID, directory: URL? = nil) {
        let base = directory ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))?.appending(path: "MenuRaid", directoryHint: .isDirectory)
            ?? FileManager.default.temporaryDirectory
        url = base.appending(path: "snapshot-\(serverID.uuidString).json")
    }

    func load() -> ServerSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ServerSnapshot.self, from: data)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    func save(_ snapshot: ServerSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

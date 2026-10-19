import Testing
import Foundation
@testable import MenuRaid

struct SnapshotCacheTests {
    @Test func roundTripsAndNeverContainsAnAPIKeyField() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "MenuRaidTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = UUID()
        let cache = SnapshotCache(serverID: id, directory: dir)
        #expect(cache.load() == nil)

        var overview = ServerOverview()
        overview.hostname = "Tower"
        overview.cpuPercent = 12.5
        let snapshot = ServerSnapshot(
            serverID: id, overview: overview,
            containers: [DockerContainer(id: "1", name: "web", image: nil, state: .running, statusText: nil, ports: [PortMapping(publicPort: 8080)])],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        cache.save(snapshot)
        #expect(cache.load() == snapshot)

        let text = try String(contentsOf: cache.url, encoding: .utf8).lowercased()
        #expect(!text.contains("apikey") && !text.contains("api-key"))
    }

    @Test func corruptFileLoadsAsNil() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "MenuRaidTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = SnapshotCache(serverID: UUID(), directory: dir)
        try Data("not json".utf8).write(to: cache.url)
        #expect(cache.load() == nil)
    }
}

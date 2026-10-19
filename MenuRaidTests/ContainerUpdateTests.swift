import Testing
import Foundation
@testable import MenuRaid

struct ContainerUpdateTests {
    private struct Envelope<T: Decodable>: Decodable { let data: T }

    private func decode(_ json: String) throws -> [String: Bool] {
        try JSONDecoder().decode(Envelope<DockerExtrasResponse>.self, from: Data(json.utf8)).data.updates
    }

    private func c(_ name: String) -> DockerContainer {
        DockerContainer(id: name, name: name, image: nil, state: .running, statusText: nil, ports: [])
    }

    @Test func decodesFlagsByNameWithoutTheLeadingSlash() throws {
        let json = #"{"data":{"docker":{"containers":[{"names":["/plex"],"isUpdateAvailable":true},{"names":["/sonarr"],"isUpdateAvailable":false}]}}}"#
        #expect(try decode(json) == ["plex": true, "sonarr": false])
    }

    @Test func containersWithoutAFlagAreSkippedNotTreatedAsFalse() throws {
        let json = #"{"data":{"docker":{"containers":[{"names":["/a"],"isUpdateAvailable":null},{"names":["/b"]},{"isUpdateAvailable":true},{"names":["/c"],"isUpdateAvailable":true}]}}}"#
        #expect(try decode(json) == ["c": true])
    }

    @Test func mergeSetsTheFlagByName() {
        let merged = DockerContainer.applying(DockerExtrasResponse(updates: ["plex": true, "sonarr": false]), to: [c("plex"), c("sonarr"), c("other")])
        #expect(merged.map(\.updateAvailable) == [true, false, nil])
    }

    @Test func decodesTemplatePortsByName() throws {
        let json = #"{"data":{"docker":{"containers":[{"names":["/audiobookshelf"],"isUpdateAvailable":true,"templatePorts":[{"privatePort":80,"publicPort":13378,"type":"TCP"}]},{"names":["/redis"],"templatePorts":null}]}}}"#
        let extras = try JSONDecoder().decode(Envelope<DockerExtrasResponse>.self, from: Data(json.utf8)).data
        #expect(extras.templatePorts["audiobookshelf"]?.first?.publicPort == 13378)
        #expect(extras.templatePorts["redis"] == nil)
        #expect(extras.updates == ["audiobookshelf": true])
    }

    @Test func mergeAddsTemplatePorts() {
        let extras = DockerExtrasResponse(templatePorts: ["plex": [PortMapping(privatePort: 32400, publicPort: 32400)]])
        let merged = DockerContainer.applying(extras, to: [c("plex"), c("other")])
        #expect(merged[0].templatePorts?.first?.publicPort == 32400)
        #expect(merged[1].templatePorts == nil)
    }

    @Test func noUpdateInfoLeavesContainersUntouched() {
        // The update query is best-effort: if it fails, the container list must be unchanged.
        let list = [c("plex")]
        #expect(DockerContainer.applying(nil, to: list) == list)
        #expect(DockerContainer.applying(nil, to: list).first?.updateAvailable == nil)
    }

    @Test func realServerCaptureStillDecodesWithoutTheField() throws {
        // The saved fixture predates this field: containers must still decode, with no update info.
        let json = #"{"data":{"docker":{"containers":[{"names":["/x"],"state":"RUNNING","ports":[]}]}}}"#
        let containers = try JSONDecoder().decode(Envelope<DockerResponse>.self, from: Data(json.utf8)).data.containers
        #expect(containers.first?.updateAvailable == nil)
    }

    @Test func updateFlagSurvivesTheSnapshotCache() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "MenuRaidTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        var container = c("plex"); container.updateAvailable = true
        let snapshot = ServerSnapshot(serverID: id, containers: [container], fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let cache = SnapshotCache(serverID: id, directory: dir)
        cache.save(snapshot)
        #expect(cache.load()?.containers?.first?.updateAvailable == true)
    }
}

@MainActor
struct ContainerUpdateCountTests {
    private func store(_ flags: [Bool?]) -> ServerStore {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.upd.\(UUID().uuidString)")!)
        let store = ServerStore(settings: settings, autostart: false)
        let containers = flags.enumerated().map { index, flag -> DockerContainer in
            var container = DockerContainer(id: "\(index)", name: "c\(index)", image: nil, state: .running, statusText: nil, ports: [])
            container.updateAvailable = flag
            return container
        }
        store.loadPreview(ServerSnapshot(serverID: settings.primary.id, containers: containers, fetchedAt: .now))
        return store
    }

    @Test func countsOnlyContainersWithAnUpdate() {
        #expect(store([true, false, nil, true, true]).containerUpdateCount == 3)
    }

    @Test func zeroWhenNothingIsKnownOrNothingToUpdate() {
        #expect(store([]).containerUpdateCount == 0)
        #expect(store([false, nil]).containerUpdateCount == 0)
    }

    @Test func updatesDoNotAffectHealth() {
        // A newer image is information, not a problem: the status must stay green.
        #expect(store([true, true]).health?.level != .red)
        #expect(store([true, true]).health?.reasons.isEmpty == true)
    }
}

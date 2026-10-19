#if DEBUG
import Foundation

/// Snapshots for SwiftUI previews and tests, built from real responses captured from an Unraid 7.2.3 server
/// (`Fixtures/live/*.json`). Scenario variants are derived from that data.
enum PreviewFixtures {
    private final class BundleToken {}

    private struct Envelope<T: Decodable>: Decodable { let data: T }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        for bundle in [Bundle(for: BundleToken.self), Bundle.main] {
            if let url = bundle.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let value = try? JSONDecoder().decode(Envelope<T>.self, from: data) {
                return value.data
            }
        }
        return nil
    }

    static let serverID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Your real server: array started, disk1 disabled with errors, unread alerts, 34 containers, 2 VMs.
    static var live: ServerSnapshot {
        var array: ArrayInfo?
        if let raw = load(ArrayResponse.self, "array") {
            array = ArrayInfo.make(
                array: raw,
                extras: load(DiskExtrasResponse.self, "diskExtras"),
                parity: load(ParityCheckResponse.self, "parityCheck")
            )
        }
        var overview = load(OverviewResponse.self, "overview")?.overview
        // Boot time is a fixed timestamp in the capture; keep uptime sensible.
        overview?.bootTime = Date.now.addingTimeInterval(-64 * 86_400 - 3 * 3_600)
        return ServerSnapshot(
            serverID: serverID,
            overview: overview,
            array: array,
            containers: load(DockerResponse.self, "docker")?.containers,
            vms: load(VMsResponse.self, "vms")?.vms,
            notifications: load(NotificationsResponse.self, "notifications")?.unread,
            fetchedAt: .now
        )
    }

    /// Everything fine: disk1 healthy, only informational notifications.
    static var healthy: ServerSnapshot {
        var snapshot = live
        if let index = snapshot.array?.disks.firstIndex(where: { $0.name == "disk1" }) {
            snapshot.array?.disks[index].status = "DISK_OK"
            snapshot.array?.disks[index].numErrors = 0
            snapshot.array?.disks[index].isSpinning = true
            snapshot.array?.disks[index].tempC = 28
        }
        snapshot.notifications = NotificationCounts(info: 79, warning: 0, alert: 0, total: 79)
        return snapshot
    }

    /// A few containers with a newer image available.
    static var withUpdates: ServerSnapshot {
        var snapshot = healthy
        let updating: Set<String> = ["bazarr", "binhex-radarr", "Glances"]
        snapshot.containers = snapshot.containers?.map { container in
            var copy = container
            copy.updateAvailable = updating.contains(container.name)
            return copy
        }
        return snapshot
    }

    static var parityRunning: ServerSnapshot {
        var snapshot = healthy
        snapshot.array?.parityCheck = ParityCheck(running: true, paused: false, progress: 42.5, errors: 0, status: "RUNNING")
        return snapshot
    }

    static var hotDisk: ServerSnapshot {
        var snapshot = healthy
        if let index = snapshot.array?.disks.firstIndex(where: { $0.name == "disk2" }) {
            snapshot.array?.disks[index].tempC = 57
        }
        if let index = snapshot.array?.disks.firstIndex(where: { $0.name == "disk3" }) {
            snapshot.array?.disks[index].tempC = 48
        }
        return snapshot
    }

    static var arrayStopped: ServerSnapshot {
        var snapshot = healthy
        snapshot.array?.state = "STOPPED"
        for index in snapshot.array?.disks.indices ?? 0..<0 {
            snapshot.array?.disks[index].tempC = nil
            snapshot.array?.disks[index].isSpinning = false
        }
        snapshot.containers = []
        snapshot.vms = []
        return snapshot
    }

    static var noContainers: ServerSnapshot {
        var snapshot = healthy
        snapshot.containers = nil
        return snapshot
    }

    /// Preview settings with a LAN address (so links resolve) and one override.
    @MainActor static let settings: SettingsStore = {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.preview") ?? .standard)
        store.primary.lanAddress = "192.168.1.10"
        store.primary.containerOverrides = ["binhex-delugevpn": "http://192.168.1.10:8112"]
        return store
    }()

    /// A store that has lost its connection (after earlier success), for the Disconnected view.
    @MainActor
    static func disconnectedStore(_ problem: ConnectionProblem) -> ServerStore {
        let store = ServerStore(settings: settings, autostart: false)
        var snapshot = healthy
        snapshot.fetchedAt = Date.now.addingTimeInterval(-300)
        store.loadPreview(snapshot, unreachable: true, problem: problem, failures: 3)
        return store
    }

    /// A store holding fixed data and making no network requests.
    @MainActor
    static func store(
        _ snapshot: ServerSnapshot,
        errors: [PanelSection: String] = [:],
        fromCache: Bool = false
    ) -> ServerStore {
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot, errors: errors, fromCache: fromCache)
        return store
    }
}
#endif

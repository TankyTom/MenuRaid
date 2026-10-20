import Testing
import Foundation
@testable import MenuRaid

// MARK: Item 5 - look for the LAN again while on the remote route

@MainActor
struct LANRecheckTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeManager(mode: RouteMode = .auto, lan: String = "192.168.1.10", prober: MockProber) -> RouteManager {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.lan.\(UUID().uuidString)")!)
        settings.primary = ServerConfig(
            id: settings.primary.id, lanAddress: lan, remoteAddress: "100.101.102.103", mode: mode, expectedHostname: "Tower"
        )
        return RouteManager(settings: settings, prober: prober)
    }

    @Test func movesBackToTheLANOnceItIsAvailableAgain() async {
        let prober = MockProber(["192.168.1.10": .failed(.unreachable("server still booting"))])
        let manager = makeManager(prober: prober)
        #expect(await manager.resolve(apiKey: "k", now: t0)?.kind == .remote)

        prober.set("192.168.1.10", .server(hostname: "Tower"))   // the server finishes booting
        // Within the interval nothing is re-probed. (Each LAN attempt starts with the keyless login-page check,
        // so that is what counts attempts while the LAN is down.)
        #expect(await manager.resolve(apiKey: "k", now: t0.addingTimeInterval(60))?.kind == .remote)
        #expect(prober.loginCalls.count == 1)
        // ...after it, the LAN is tried again and wins.
        #expect(await manager.resolve(apiKey: "k", now: t0.addingTimeInterval(RouteManager.lanRecheckInterval + 1))?.kind == .lan)
    }

    @Test func stillOnRemoteWhenTheLANIsStillDown() async {
        let prober = MockProber(["192.168.1.10": .failed(.unreachable("away"))])
        let manager = makeManager(prober: prober)
        _ = await manager.resolve(apiKey: "k", now: t0)
        let later = t0.addingTimeInterval(RouteManager.lanRecheckInterval + 1)
        #expect(await manager.resolve(apiKey: "k", now: later)?.kind == .remote)
        #expect(prober.loginCalls.count == 2)
        #expect(prober.calls.isEmpty)   // and the key was never sent to an address that didn't answer
        // And the next re-check is a full interval after that one, not on every refresh.
        _ = await manager.resolve(apiKey: "k", now: later.addingTimeInterval(30))
        #expect(prober.loginCalls.count == 2)
    }

    @Test func aWorkingLANIsNeverReprobedOnASchedule() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let manager = makeManager(prober: prober)
        _ = await manager.resolve(apiKey: "k", now: t0)
        _ = await manager.resolve(apiKey: "k", now: t0.addingTimeInterval(3600))
        #expect(prober.calls.count == 1)
    }

    @Test func fixedRemoteModeNeverLooksForTheLAN() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let manager = makeManager(mode: .remote, prober: prober)
        _ = await manager.resolve(apiKey: "k", now: t0)
        _ = await manager.resolve(apiKey: "k", now: t0.addingTimeInterval(3600))
        #expect(prober.calls.isEmpty)
    }

    @Test func noLANAddressMeansNothingToRecheck() async {
        let prober = MockProber()
        let manager = makeManager(lan: "", prober: prober)
        _ = await manager.resolve(apiKey: "k", now: t0)
        _ = await manager.resolve(apiKey: "k", now: t0.addingTimeInterval(3600))
        #expect(prober.calls.isEmpty)
    }
}

// MARK: Item 9 - containers that aren't running have nothing to open

@MainActor
struct StoppedContainerLinkTests {
    private func store() -> ServerStore {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.stopped.\(UUID().uuidString)")!)
        settings.primary.lanAddress = "192.168.1.10"
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(ServerSnapshot(serverID: settings.primary.id, fetchedAt: .now))   // gives it a route
        return store
    }

    private func container(_ state: ContainerState) -> DockerContainer {
        DockerContainer(
            id: "x", name: "x", image: nil, state: state, statusText: nil,
            ports: [PortMapping(privatePort: 80, publicPort: 8080)], webUITemplate: "http://[IP]:[PORT:80]"
        )
    }

    @Test func runningContainersOpen() {
        #expect(store().containerLink(for: container(.running)).url?.absoluteString == "http://192.168.1.10:8080")
    }

    @Test func stoppedPausedAndRestartingContainersDoNot() {
        for state in [ContainerState.exited, .paused, .restarting, .created, .dead, .unknown] {
            let link = store().containerLink(for: container(state))
            #expect(link == .unavailable(.notRunning), "\(state)")
            #expect(link.url == nil)
        }
        #expect(ContainerLink.unavailable(.notRunning).unavailableMessage?.contains("isn't running") == true)
    }

    @Test func aURLOverrideDoesNotMakeAStoppedContainerOpenable() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.stopped.\(UUID().uuidString)")!)
        settings.primary.lanAddress = "192.168.1.10"
        settings.primary.containerOverrides = ["x": "https://x.example.com"]
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(ServerSnapshot(serverID: settings.primary.id, fetchedAt: .now))
        #expect(store.containerLink(for: container(.running)).url?.host == "x.example.com")   // override works while running
        #expect(store.containerLink(for: container(.exited)).url == nil)                      // but not while stopped
    }

    @Test func theLinkLogicItselfStillResolvesStoppedContainersCorrectly() {
        // The Settings "Automatic link" caption uses LinkBuilder directly, so it can still show the right port.
        let link = LinkBuilder.container(container(.exited), base: URL(string: "http://192.168.1.10")!, overrides: [:])
        #expect(link.url?.port == 8080)
    }
}

// MARK: Item 6 - one rule for "failed disk"

struct DiskFailureRuleTests {
    private func disk(_ status: String?) -> DiskInfo { DiskInfo(name: "d", role: .data, status: status) }

    @Test func failedMeansDisabledMissingOrInvalid() {
        for status in ["DISK_DSBL", "DISK_INVALID", "DISK_NP_MISSING", "DISK_NP_DSBL", "DISK_NEW", "DISK_WRONG"] {
            #expect(disk(status).isFailed, "\(status)")
        }
    }

    @Test func okAnEmptySlotAndUnknownAreNotFailures() {
        #expect(!disk("DISK_OK").isFailed)
        #expect(!disk("DISK_NP").isFailed)
        #expect(disk("DISK_NP").isEmptySlot)
        #expect(!disk(nil).isFailed)
    }

    @Test func emptySlotIsDescribedAsOne() {
        #expect(disk("DISK_NP").statusDescription == "Empty slot")
        #expect(disk("DISK_NP_MISSING").statusDescription == "Missing")
    }
}

// MARK: Item 8 - Test connection uses the key you've typed

struct TestKeyChoiceTests {
    @Test func aTypedKeyWinsEvenIfOneIsSaved() {
        #expect(ServerStore.keyForTest(typed: "new-key", saved: "old-key") == "new-key")
    }

    @Test func typedKeyIsTrimmed() {
        #expect(ServerStore.keyForTest(typed: "  new-key \n", saved: nil) == "new-key")
    }

    @Test func fallsBackToTheSavedKey() {
        #expect(ServerStore.keyForTest(typed: "", saved: "old-key") == "old-key")
        #expect(ServerStore.keyForTest(typed: "   ", saved: "old-key") == "old-key")
    }

    @Test func noKeyAnywhereMeansNoTest() {
        #expect(ServerStore.keyForTest(typed: "", saved: nil) == nil)
        #expect(ServerStore.keyForTest(typed: "", saved: "") == nil)
    }
}

// MARK: Item 4 - removing the key forgets the old data

@MainActor
struct ForgetDataTests {
    @Test func removingTheKeyClearsWhatWasOnScreen() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.forget.\(UUID().uuidString)")!)
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(ServerSnapshot(serverID: settings.primary.id, fetchedAt: .now), unreachable: true, problem: .authRejected, failures: 3)
        #expect(store.snapshot != nil && store.isDisconnected)

        store.forgetServerData()

        #expect(store.snapshot == nil)
        #expect(store.health == nil)
        #expect(store.lastSuccess == nil)
        #expect(store.connectionProblem == nil)
        #expect(!store.isDisconnected && !store.isUnreachable)
        #expect(store.cpuHistory.isEmpty && store.ramHistory.isEmpty)
        #expect(store.consecutiveFailures == 0)
    }

    @Test func theSavedSnapshotFileIsDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "MenuRaidTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let cache = SnapshotCache(serverID: id, directory: dir)
        cache.save(ServerSnapshot(serverID: id, fetchedAt: .now))
        #expect(cache.load() != nil)
        cache.delete()
        #expect(cache.load() == nil)
    }
}

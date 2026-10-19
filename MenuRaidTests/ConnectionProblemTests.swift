import Testing
import Foundation
@testable import MenuRaid

struct ConnectionProblemTests {
    @Test func classifiesEveryError() {
        #expect(ConnectionProblem.classify(nil) == .unreachable)
        #expect(ConnectionProblem.classify(.unreachable("timed out")) == .unreachable)
        #expect(ConnectionProblem.classify(.unauthorized) == .authRejected)
        #expect(ConnectionProblem.classify(.insecureConnectionBlocked) == .insecureBlocked)
        #expect(ConnectionProblem.classify(.untrustedCertificate(fingerprint: "AA")) == .certificateUntrusted)
        #expect(ConnectionProblem.classify(.certificateMismatch(expected: "AA", got: "BB")) == .certificateChanged)
        #expect(ConnectionProblem.classify(.http(502)) == .unexpectedResponse("The server answered with HTTP 502."))
        #expect(ConnectionProblem.classify(.graphQL(["a", "b"])) == .unexpectedResponse("a; b"))
        if case .unexpectedResponse = ConnectionProblem.classify(.decoding("x")) {} else { Issue.record("decoding should be unexpectedResponse") }
    }

    @Test func everyProblemHasAReadableTitleAndExplanation() {
        let all: [ConnectionProblem] = [
            .unreachable, .authRejected, .insecureBlocked, .certificateUntrusted, .certificateChanged,
            .wrongServer(note: nil), .unexpectedResponse("x"),
        ]
        for problem in all {
            #expect(!problem.title.isEmpty && !problem.explanation.isEmpty && !problem.symbol.isEmpty)
        }
        // Titles are distinct so the panel says what's actually wrong.
        #expect(Set(all.map(\.title)).count == all.count)
    }

    @Test func explanationsPointToTheRightFix() {
        #expect(ConnectionProblem.authRejected.explanation.contains("Viewer"))
        #expect(ConnectionProblem.unreachable.explanation.contains("Tailscale"))
        #expect(ConnectionProblem.insecureBlocked.explanation.contains("https://"))
        #expect(ConnectionProblem.wrongServer(note: "Custom note.").explanation == "Custom note.")
    }

    @Test func onlyAPlainConnectionFailureCanBeFixedWithoutSettings() {
        #expect(!ConnectionProblem.unreachable.needsSettings)
        #expect(ConnectionProblem.authRejected.needsSettings)
        #expect(ConnectionProblem.insecureBlocked.needsSettings)
    }

    @Test func blockedByMacOSHasAClearMessageInTheConnectionReport() {
        let report = ConnectionReport.make(
            kind: .remote, address: "tower.tailnet-1234.ts.net", url: URL(string: "http://tower.tailnet-1234.ts.net"),
            outcome: .failure(.insecureConnectionBlocked), latency: nil, expectedHostname: nil, hasPin: false
        )
        #expect(!report.reachable && !report.isUsable)
        #expect(report.message?.contains("macOS blocked") == true)
        #expect(UnraidError.insecureConnectionBlocked.errorDescription?.contains("macOS blocked") == true)
    }
}

@MainActor
struct DisconnectedStateTests {
    private func makeSettings(lan: String = "192.168.1.10", remote: String = "tower.tailnet-1234.ts.net", mode: RouteMode = .auto) -> SettingsStore {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.disc.\(UUID().uuidString)")!)
        settings.primary.lanAddress = lan
        settings.primary.remoteAddress = remote
        settings.primary.mode = mode
        return settings
    }

    private func snapshot(_ settings: SettingsStore) -> ServerSnapshot {
        ServerSnapshot(serverID: settings.primary.id, fetchedAt: .now)
    }

    @Test func connectedIsNotDisconnected() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(settings))
        #expect(!store.isDisconnected)
    }

    @Test func aSingleFailedRefreshKeepsShowingTheData() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(settings), unreachable: true, problem: .unreachable, failures: 1)
        #expect(!store.isDisconnected)   // one blip shouldn't flash the Disconnected view
    }

    @Test func repeatedFailuresShowDisconnected() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(settings), unreachable: true, problem: .unreachable, failures: 2)
        #expect(store.isDisconnected)
    }

    @Test func failingWithNoDataAtAllIsDisconnectedImmediately() {
        // First launch with nothing saved, and the server can't be reached or rejects the key.
        let store = ServerStore(settings: makeSettings(), autostart: false)
        store.loadPreview(nil, unreachable: true, problem: .authRejected, failures: 0)
        #expect(store.snapshot == nil)
        #expect(store.isDisconnected)
    }

    @Test func addressesFollowTheRouteMode() {
        func kinds(_ mode: RouteMode) -> [RouteKind] {
            ServerStore(settings: makeSettings(mode: mode), autostart: false).serverAddresses.map(\.kind)
        }
        #expect(kinds(.auto) == [.lan, .remote])
        #expect(kinds(.lan) == [.lan])
        #expect(kinds(.remote) == [.remote])
    }

    @Test func headerLinksStillWorkWhenNoRouteIsActive() {
        // Disconnected, no route chosen: links fall back to the first configured address so the browser can show why.
        let store = ServerStore(settings: makeSettings(), autostart: false)
        #expect(store.activeBase == nil)
        #expect(store.linkBase?.absoluteString == "http://192.168.1.10")
        #expect(ServerStore(settings: makeSettings(lan: "", remote: ""), autostart: false).linkBase == nil)
    }

    @Test func addressesSkipEmptyOrInvalidOnes() {
        let store = ServerStore(settings: makeSettings(lan: "", remote: "tower.ts.net"), autostart: false)
        #expect(store.serverAddresses.map(\.url.absoluteString) == ["http://tower.ts.net"])
        #expect(ServerStore(settings: makeSettings(lan: "ftp://x", remote: ""), autostart: false).serverAddresses.isEmpty)
    }
}

import Testing
import Foundation
@testable import MenuRaid

/// Answers probes from a table and records what was asked.
final class MockProber: RouteProbing, @unchecked Sendable {
    struct Call: Equatable { var host: String; var timeout: TimeInterval }

    private let lock = NSLock()
    private var answers: [String: ProbeResult] = [:]
    private var loginAnswers: [String: LoginNameResult] = [:]
    private var recorded: [Call] = []
    private var recordedLogin: [Call] = []

    init(_ answers: [String: ProbeResult] = [:], loginNames: [String: LoginNameResult] = [:]) {
        self.answers = answers
        self.loginAnswers = loginNames
    }

    /// Keyed probes, i.e. requests that carry the API key.
    var calls: [Call] { lock.withLock { recorded } }
    /// Keyless login-page checks.
    var loginCalls: [Call] { lock.withLock { recordedLogin } }
    func set(_ host: String, _ result: ProbeResult) { lock.withLock { answers[host] = result } }

    /// Unless a test says otherwise, the login page names the same server the keyed probe would report.
    func loginName(base: URL, timeout: TimeInterval) async -> LoginNameResult {
        let host = base.host ?? ""
        return lock.withLock {
            recordedLogin.append(Call(host: host, timeout: timeout))
            if let explicit = loginAnswers[host] { return explicit }
            switch answers[host] {
            case .server(let name)?: return name.map(LoginNameResult.name) ?? .unreadable
            case .failed(let error)?: return .failed(error)
            case nil: return .failed(.unreachable("no answer"))
            }
        }
    }

    func probe(base: URL, apiKey: String, timeout: TimeInterval) async -> ProbeResult {
        let host = base.host ?? ""
        return lock.withLock {
            recorded.append(Call(host: host, timeout: timeout))
            return answers[host] ?? .failed(.unreachable("no answer"))
        }
    }
}

struct RouteResolverTests {
    private let lanHost = "192.168.1.10"
    private let remoteHost = "100.101.102.103"

    private func config(
        lan: String = "192.168.1.10", remote: String = "100.101.102.103",
        mode: RouteMode = .auto, expected: String? = "Tower"
    ) -> ServerConfig {
        ServerConfig(lanAddress: lan, remoteAddress: remote, mode: mode, expectedHostname: expected)
    }

    @Test func prefersLANWhenOurServerAnswersThere() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route == ActiveRoute(kind: .lan, base: URL(string: "http://192.168.1.10")!))
        #expect(result.note == nil)
        #expect(prober.calls.map(\.host) == ["192.168.1.10"])  // the remote address isn't even probed
    }

    @Test func lanProbeUsesOneSecondTimeout() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        _ = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(prober.calls.first?.timeout == 1.0)
    }

    @Test func fallsBackToRemoteWhenLANIsUnreachable() async {
        let prober = MockProber(["192.168.1.10": .failed(.unreachable("timed out"))])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
        #expect(result.route?.base.host == remoteHost)
        #expect(result.note != nil)
    }

    @Test func aDifferentServerOnTheLANAddressIsNeverUsed() async {
        // Same IP on someone else's network: must not receive the API key.
        let prober = MockProber(["192.168.1.10": .server(hostname: "Someone-Elses-NAS")])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
        #expect(result.note?.contains("Someone-Elses-NAS") == true)
    }

    @Test func aDifferentServerWithNoRemoteMeansNoRoute() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Someone-Elses-NAS")])
        let result = await RouteResolver.resolve(config(remote: ""), apiKey: "k", prober: prober)
        #expect(result.route == nil)
    }

    @Test func aServerThatGivesNoNameCannotBeVerified() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: nil)])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
    }

    @Test func hostnameMatchIgnoresCase() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "TOWER")])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .lan)
    }

    @Test func firstConnectionWithNoSavedHostnameAcceptsTheLAN() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let result = await RouteResolver.resolve(config(expected: nil), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .lan)
    }

    @Test func onlyALANAddressKeepsUsingItEvenIfTheProbeFails() async {
        let prober = MockProber(["192.168.1.10": .failed(.unreachable("timed out"))])
        let result = await RouteResolver.resolve(config(remote: ""), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .lan)
    }

    @Test func onlyARemoteAddressIsUsedWithoutProbing() async {
        let prober = MockProber()
        let result = await RouteResolver.resolve(config(lan: ""), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
        #expect(prober.calls.isEmpty)
    }

    @Test func noAddressesMeansNoRoute() async {
        let result = await RouteResolver.resolve(config(lan: "", remote: ""), apiKey: "k", prober: MockProber())
        #expect(result.route == nil)
    }

    @Test func fixedModesDoNotProbe() async {
        let prober = MockProber()
        let lan = await RouteResolver.resolve(config(mode: .lan), apiKey: "k", prober: prober)
        let remote = await RouteResolver.resolve(config(mode: .remote), apiKey: "k", prober: prober)
        #expect(lan.route?.kind == .lan)
        #expect(remote.route?.kind == .remote)
        #expect(prober.calls.isEmpty)
    }

    @Test func fixedModeWithoutThatAddressMeansNoRoute() async {
        let result = await RouteResolver.resolve(config(lan: "", mode: .lan), apiKey: "k", prober: MockProber())
        #expect(result.route == nil)
    }

    @Test func certificateProblemOnTheLANFallsBackAndIsReported() async {
        let prober = MockProber(["192.168.1.10": .failed(.certificateMismatch(expected: "AA", got: "BB"))])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
        #expect(result.certificateIssue != nil)
    }

    @Test func certificateProblemWithNoRemoteMeansNoRoute() async {
        let prober = MockProber(["192.168.1.10": .failed(.untrustedCertificate(fingerprint: "AA"))])
        let result = await RouteResolver.resolve(config(remote: ""), apiKey: "k", prober: prober)
        #expect(result.route == nil)
        #expect(result.certificateIssue != nil)
    }
}

@MainActor
struct RouteManagerTests {
    private func makeSettings() -> SettingsStore {
        let suite = "menuraid.route.\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        store.primary = ServerConfig(
            id: store.primary.id, lanAddress: "192.168.1.10", remoteAddress: "100.101.102.103",
            mode: .auto, expectedHostname: "Tower"
        )
        return store
    }

    @Test func decisionIsCachedUntilInvalidated() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let manager = RouteManager(settings: makeSettings(), prober: prober)

        #expect(await manager.resolve(apiKey: "k")?.kind == .lan)
        #expect(await manager.resolve(apiKey: "k")?.kind == .lan)
        #expect(await manager.resolve(apiKey: "k")?.kind == .lan)
        #expect(prober.calls.count == 1)  // probed once, not on every refresh

        manager.invalidate()
        _ = await manager.resolve(apiKey: "k")
        #expect(prober.calls.count == 2)
    }

    @Test func leavingHomeSwitchesToRemoteAfterInvalidation() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let manager = RouteManager(settings: makeSettings(), prober: prober)
        #expect(await manager.resolve(apiKey: "k")?.kind == .lan)

        prober.set("192.168.1.10", .failed(.unreachable("no route")))  // now on another network
        manager.invalidate()                                           // network path changed
        #expect(await manager.resolve(apiKey: "k")?.kind == .remote)
        #expect(manager.note != nil)

        prober.set("192.168.1.10", .server(hostname: "Tower"))         // back home
        manager.invalidate()
        #expect(await manager.resolve(apiKey: "k")?.kind == .lan)
        #expect(manager.note == nil)
    }

    @Test func changingSettingsForcesANewDecision() async {
        let settings = makeSettings()
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let manager = RouteManager(settings: settings, prober: prober)
        #expect(await manager.resolve(apiKey: "k")?.kind == .lan)

        settings.primary.mode = .remote
        #expect(await manager.resolve(apiKey: "k")?.kind == .remote)
    }

    @Test func nothingIsActiveBeforeTheFirstDecision() {
        let manager = RouteManager(settings: makeSettings(), prober: MockProber())
        #expect(manager.active == nil)
    }
}

struct ConnectionReportTests {
    private func report(
        _ outcome: Result<String?, UnraidError>, url: String = "http://192.168.1.10",
        expected: String? = "Tower", hasPin: Bool = false
    ) -> ConnectionReport {
        ConnectionReport.make(
            kind: .lan, address: "192.168.1.10", url: URL(string: url), outcome: outcome,
            latency: 0.05, expectedHostname: expected, hasPin: hasPin
        )
    }

    @Test func workingServer() {
        let r = report(.success("Tower"))
        #expect(r.reachable && r.apiKey == .yes && r.hostname == "Tower")
        #expect(r.identity == .matches)
        #expect(r.certificate == .notEncrypted)
        #expect(r.latency == 0.05)
        #expect(r.isUsable)
    }

    @Test func firstConnectionWillSaveTheHostname() {
        #expect(report(.success("Tower"), expected: nil).identity == .willBeSaved)
    }

    @Test func differentServerIsNotUsable() {
        let r = report(.success("Other"))
        #expect(r.identity == .differs(expected: "Tower"))
        #expect(r.isIdentityMismatch && !r.isUsable)
    }

    @Test func rejectedKeyIsReachableButNotAuthorised() {
        let r = report(.failure(.unauthorized))
        #expect(r.reachable && r.apiKey == .no && !r.isUsable)
        #expect(r.message?.contains("Viewer") == true)
    }

    @Test func unreachable() {
        let r = report(.failure(.unreachable("timed out")))
        #expect(!r.reachable && r.apiKey == .unknown && !r.isUsable)
    }

    @Test func httpsCertificateStates() {
        #expect(report(.success("Tower"), url: "https://tower.local").certificate == .trustedBySystem)
        #expect(report(.success("Tower"), url: "https://tower.local", hasPin: true).certificate == .pinned)

        let untrusted = report(.failure(.untrustedCertificate(fingerprint: "AA:BB")), url: "https://tower.local")
        #expect(untrusted.certificate == .untrusted(fingerprint: "AA:BB") && untrusted.hasCertificateProblem && !untrusted.isUsable)

        let changed = report(.failure(.certificateMismatch(expected: "AA", got: "BB")), url: "https://tower.local")
        #expect(changed.certificate == .changed(expected: "AA", got: "BB") && !changed.isUsable)
    }

    @Test func wrongAddressSaysSo() {
        #expect(report(.failure(.http(404))).message?.contains("404") == true)
        #expect(report(.failure(.decoding("x"))).message?.contains("Unraid") == true)
    }
}

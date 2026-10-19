import Foundation
import Observation
import AppKit

/// Panel sections that load independently, so one failing query shows an error in that section only.
enum PanelSection: String, CaseIterable, Identifiable {
    case overview, array, docker, vms, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "System"
        case .array: "Array"
        case .docker: "Docker"
        case .vms: "VMs"
        case .notifications: "Notifications"
        }
    }
}

/// Owns the latest snapshot and the refresh loop.
///
/// - Refreshes every `preferences.refreshInterval` seconds, or every 5 s while the panel is open.
/// - Backs off after failures (5, 15, 30, 60 s), pauses while the Mac sleeps, resumes 3 s after wake.
/// - Keeps the last good data when a section fails, and caches the snapshot for the next launch.
@MainActor
@Observable
final class ServerStore {
    private(set) var snapshot: ServerSnapshot?
    private(set) var sectionErrors: [PanelSection: String] = [:]
    private(set) var health: Health?
    private(set) var lastSuccess: Date?
    private(set) var isRefreshing = false
    /// True while the data on screen came from the on-disk cache and no live refresh has succeeded yet.
    private(set) var isShowingCache = false
    /// Set when the last refresh failed on every section.
    private(set) var isUnreachable = false
    /// Shown instead of data when there is nothing to connect with yet.
    private(set) var setupMessage: String?
    /// A certificate problem (untrusted or changed) from the last refresh, if any.
    private(set) var certificateIssue: UnraidError?
    private(set) var cpuHistory: [Double] = []
    private(set) var ramHistory: [Double] = []
    private(set) var isPanelOpen = false
    /// The server rejected the API key on the last refresh.
    private(set) var authFailed = false
    /// Why the last refresh got nothing at all (set only when every section failed).
    private(set) var connectionProblem: ConnectionProblem?
    /// The underlying error text for that failure, for the "details" line.
    private(set) var connectionDetail: String?

    /// Chooses between the LAN and remote address and remembers the choice.
    let routes: RouteManager

    static let historyLimit = 60
    static let panelOpenInterval: TimeInterval = 5
    /// Per-request timeout for section queries. Unraid's Docker and array queries can take several seconds.
    static let requestTimeout: TimeInterval = 20

    private let settings: SettingsStore
    private let client: UnraidClient
    private let keychain: KeychainStore
    private let cache: SnapshotCache

    private var loopTask: Task<Void, Never>?
    private var sleepObserver: Task<Void, Never>?
    private var wakeObserver: Task<Void, Never>?
    private var pathObserver: NetworkPathObserver?
    private var pathTask: Task<Void, Never>?
    private(set) var consecutiveFailures = 0
    private var didPromptForSetup = false

    init(
        settings: SettingsStore,
        client: UnraidClient = UnraidClient(),
        keychain: KeychainStore = KeychainStore(),
        autostart: Bool = true
    ) {
        self.settings = settings
        self.client = client
        self.keychain = keychain
        self.cache = SnapshotCache(serverID: settings.primary.id)
        self.routes = RouteManager(settings: settings, prober: client)

        if let cached = cache.load(), cached.serverID == settings.primary.id {
            snapshot = cached
            lastSuccess = cached.fetchedAt
            isShowingCache = true
            recomputeHealth()
        }
        guard autostart else { return }
        observeSleepAndWake()
        observeNetworkChanges()
        start()
    }

    // MARK: - Derived values

    var isStale: Bool {
        guard let lastSuccess else { return false }
        return Date.now.timeIntervalSince(lastSuccess) > 3 * Double(settings.preferences.refreshInterval)
    }

    /// Data on screen is old (saved from last launch, stale, or the server is unreachable), so the panel greys it.
    var isDataDimmed: Bool {
        snapshot != nil && (isShowingCache || isStale || isUnreachable)
    }

    /// Nothing is getting through, and has been that way long enough (two failed refreshes in a row, or no data
    /// at all) that the panel should say "disconnected" instead of showing the last data as if it were current.
    var isDisconnected: Bool {
        connectionProblem != nil && (snapshot == nil || consecutiveFailures >= 2)
    }

    /// The server addresses MenuRaid is configured to try, for the Disconnected view's links.
    var serverAddresses: [ServerAddress] {
        let server = settings.primary
        var result: [ServerAddress] = []
        if server.mode != .remote, let url = AddressParser.parse(server.lanAddress)?.baseURL {
            result.append(ServerAddress(kind: .lan, url: url, isInUse: routes.active?.kind == .lan))
        }
        if server.mode != .lan, let url = AddressParser.parse(server.remoteAddress)?.baseURL {
            result.append(ServerAddress(kind: .remote, url: url, isInUse: routes.active?.kind == .remote))
        }
        return result
    }

    /// The one-time notice that a plain `http://` LAN address sends the API key unencrypted.
    var showHTTPWarning: Bool {
        SecurityNotice.shouldShowHTTPWarning(config: settings.primary, dismissed: settings.preferences.httpWarningDismissed)
    }

    func dismissHTTPWarning() {
        settings.preferences.httpWarningDismissed = true
    }

    /// Short text shown beside the status symbol, per the user's choice. nil means icon only.
    var menuBarText: String? {
        switch settings.preferences.menuBarValue {
        case .cpu:
            return snapshot?.overview?.cpuPercent.map { "\(Int($0.rounded()))%" }
        case .ram:
            return snapshot?.overview?.memoryPercent.map { "\(Int($0.rounded()))%" }
        case .hottestDisk:
            return hottestDiskTemp.map { "\(Int($0.rounded()))°" }
        case .iconOnly:
            return nil
        }
    }

    var hottestDiskTemp: Double? {
        snapshot?.array?.disks.compactMap(\.tempC).max()
    }

    // MARK: - Control

    /// The address in use right now (nil until the first route decision, or if none is configured).
    var activeBase: URL? { routes.active?.base }

    /// Which address is in use, for the header icon and tooltip.
    var activeRoute: (isLAN: Bool, address: String)? {
        routes.active.map { ($0.kind == .lan, $0.base.absoluteString) }
    }

    /// Why the preferred route wasn't used, e.g. "LAN address not available, using the remote address."
    var routeNote: String? { routes.note }

    /// Tests the LAN and remote addresses separately for the Settings "Test connection" button.
    func testConnection() async -> [ConnectionReport] {
        let config = settings.primary
        guard let key = (try? keychain.get(account: config.id.uuidString)) ?? nil, !key.isEmpty else {
            return [ConnectionReport(
                kind: .lan, address: "", url: nil, reachable: false, apiKey: .no, hostname: nil,
                identity: .unknown, certificate: nil, latency: nil, message: "Save your API key first."
            )]
        }
        return await ConnectionTester(client: client).run(config: config, apiKey: key)
    }

    /// Pins a certificate the user has confirmed (trust on first use), then reconnects.
    func trustCertificate(fingerprint: String, host: String) {
        CertPinStore.shared.setPin(fingerprint, for: host)
        routes.invalidate()
        refreshNow()
    }

    /// Forgets the saved server hostname so the next successful connection records a new one.
    func resetServerIdentity() {
        settings.primary.expectedHostname = nil
        routes.invalidate()
        refreshNow()
    }

    /// How many containers have a newer image available.
    var containerUpdateCount: Int {
        snapshot?.containers?.filter { $0.updateAvailable == true }.count ?? 0
    }

    /// Containers in the order the user chose (alphabetical by default), for the panel.
    var orderedContainers: [DockerContainer] {
        ContainerOrdering.display(
            snapshot?.containers ?? [],
            custom: settings.primary.containerOrder,
            runningFirst: settings.preferences.dockerRunningFirst
        )
    }

    /// Where a click on this container should go, given the active route and the user's overrides.
    func containerLink(for container: DockerContainer) -> ContainerLink {
        LinkBuilder.container(container, base: activeBase, overrides: settings.primary.containerOverrides)
    }

    /// The VNC console URL for a running VM that has a console port set in Settings.
    func consoleURL(for vm: VirtualMachine) -> URL? {
        LinkBuilder.vmConsole(vm, base: activeBase, ports: settings.primary.vmConsolePorts)
    }

    /// Opens the VM's console if it's running with a port set; otherwise Unraid's VMs page.
    func openVM(_ vm: VirtualMachine) {
        if let url = consoleURL(for: vm) {
            NSWorkspace.shared.open(url)
        } else {
            open(.vms)
        }
    }

    /// Opens a page of the Unraid webGUI in the default browser.
    func open(_ page: LinkBuilder.Page) {
        guard let base = linkBase else { return }
        NSWorkspace.shared.open(LinkBuilder.page(page, base: base))
    }

    /// The address to open webGUI pages on: the one in use, or else the first configured one, so the links
    /// still work while MenuRaid itself can't connect (the browser may show why).
    var linkBase: URL? { activeBase ?? serverAddresses.first?.url }

    /// On first launch, with no address or API key saved, opens Settings once so setup is obvious.
    /// `open` is supplied by a view because only views can reach SwiftUI's `openSettings`.
    func promptForSetupIfNeeded(open: @MainActor () -> Void) async {
        guard !didPromptForSetup else { return }
        didPromptForSetup = true
        let hasKey = KeychainStore().hasSecret(account: settings.primary.id.uuidString)
        guard settings.needsSetup || !hasKey else { return }
        // Let the menu bar item and scenes finish appearing first.
        try? await Task.sleep(for: .milliseconds(600))
        open()
    }

    /// Starts (or restarts) the loop with an immediate refresh.
    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(self.nextDelay()))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func refreshNow() { start() }

    /// Retry from the Disconnected view: decide the route again, not just re-ask the old one.
    func retryNow() {
        consecutiveFailures = 0
        routes.invalidate()
        start()
    }

    /// Opening the panel refreshes immediately and switches to the faster rate.
    func setPanelOpen(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        if open { start() }
    }

    private func nextDelay() -> TimeInterval {
        let normal = isPanelOpen ? Self.panelOpenInterval : TimeInterval(settings.preferences.refreshInterval)
        return Backoff.delay(consecutiveFailures: consecutiveFailures, normal: normal)
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = Task { [weak self] in
            for await _ in center.notifications(named: NSWorkspace.willSleepNotification) {
                self?.stop()
            }
        }
        wakeObserver = Task { [weak self] in
            for await _ in center.notifications(named: NSWorkspace.didWakeNotification) {
                // Give the network a moment to come back before the first request.
                try? await Task.sleep(for: .seconds(3))
                self?.consecutiveFailures = 0
                self?.routes.invalidate()
                self?.start()
            }
        }
    }

    /// A change of network (home Wi-Fi to away, VPN on/off) means the best route may have changed.
    private func observeNetworkChanges() {
        let observer = NetworkPathObserver()
        pathObserver = observer
        pathTask = Task { [weak self] in
            for await _ in observer.changes {
                // Let the new network settle before probing.
                try? await Task.sleep(for: .seconds(1))
                self?.consecutiveFailures = 0
                self?.routes.invalidate()
                self?.start()
            }
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        guard let key = (try? keychain.get(account: settings.primary.id.uuidString)) ?? nil,
              !key.isEmpty, settings.primary.hasAnyAddress
        else {
            setupMessage = "Add your server address and API key in Settings."
            return
        }
        setupMessage = nil
        isRefreshing = true
        defer { isRefreshing = false }

        guard let route = await routes.resolve(apiKey: key) else {
            // No address we're willing to send the key to (e.g. the LAN address now belongs to another device).
            if Task.isCancelled { return }
            certificateIssue = routes.certificateIssue
            sectionErrors = [:]
            connectionProblem = routes.certificateIssue.map { .classify($0) } ?? .wrongServer(note: routes.note)
            connectionDetail = routes.note
            isUnreachable = true
            consecutiveFailures += 1
            recomputeHealth()
            return
        }
        let base = route.base

        let client = client
        let timeout = Self.requestTimeout
        async let overview = capture { try await client.fetchOverview(base: base, apiKey: key, timeout: timeout) }
        async let array = capture { try await client.fetchArray(base: base, apiKey: key, timeout: timeout) }
        async let docker = capture { try await client.fetchContainers(base: base, apiKey: key, timeout: timeout) }
        async let vms = capture { try await client.fetchVMs(base: base, apiKey: key, timeout: timeout) }
        async let notifications = capture { try await client.fetchNotifications(base: base, apiKey: key, timeout: timeout) }
        let results = await (overview, array, docker, vms, notifications)

        // A newer refresh (panel opened, wake) cancelled this one; its errors would be noise.
        if Task.isCancelled { return }

        var next = snapshot?.serverID == settings.primary.id
            ? snapshot ?? emptySnapshot()
            : emptySnapshot()
        var errors: [PanelSection: String] = [:]
        var issue: UnraidError?
        var rejectedKey = false
        var firstError: UnraidError?
        var successes = 0

        func record<T>(_ result: Result<T, Error>, _ section: PanelSection, _ assign: (T) -> Void) {
            switch result {
            case .success(let value):
                assign(value)
                successes += 1
            case .failure(let error):
                errors[section] = error.localizedDescription
                firstError = firstError ?? (error as? UnraidError) ?? .unreachable(error.localizedDescription)
                switch error as? UnraidError {
                case .untrustedCertificate?, .certificateMismatch?: issue = error as? UnraidError
                case .unauthorized?: rejectedKey = true
                default: break
                }
            }
        }
        record(results.0, .overview) { next.overview = $0 }
        record(results.1, .array) { next.array = $0 }
        record(results.2, .docker) { next.containers = $0 }
        record(results.3, .vms) { next.vms = $0 }
        record(results.4, .notifications) { next.notifications = $0 }

        // When nothing got through, one clear "disconnected" message replaces five copies of the same error.
        sectionErrors = successes == 0 ? [:] : errors
        connectionProblem = successes == 0 ? ConnectionProblem.classify(firstError) : nil
        connectionDetail = successes == 0 ? firstError?.localizedDescription : nil
        certificateIssue = issue ?? routes.certificateIssue
        authFailed = rejectedKey
        isUnreachable = successes == 0

        if successes > 0 {
            consecutiveFailures = 0
            isShowingCache = false
            next.fetchedAt = .now
            lastSuccess = next.fetchedAt
            snapshot = next
            cache.save(next)
            appendHistory(from: next.overview)
            rememberHostname(next.overview?.hostname)
        } else {
            consecutiveFailures += 1
            // A request on the current route failed: decide the route again next time.
            routes.invalidate()
        }
        recomputeHealth()
    }

    #if DEBUG
    /// Fills the store with fixed data for SwiftUI previews (no network).
    func loadPreview(
        _ snapshot: ServerSnapshot?,
        errors: [PanelSection: String] = [:],
        fromCache: Bool = false,
        unreachable: Bool = false,
        problem: ConnectionProblem? = nil,
        failures: Int = 0,
        refreshing: Bool = false
    ) {
        isRefreshing = refreshing
        connectionProblem = problem
        connectionDetail = problem == nil ? nil : "The request timed out."
        consecutiveFailures = failures
        self.snapshot = snapshot
        let lan = AddressParser.parse(settings.primary.lanAddress)?.baseURL
        routes.setPreviewRoute(lan.map { ActiveRoute(kind: .lan, base: $0) })
        lastSuccess = snapshot?.fetchedAt
        sectionErrors = errors
        isShowingCache = fromCache
        isUnreachable = unreachable
        var cpu: [Double] = []
        var ram: [Double] = []
        for i in 0..<Self.historyLimit {
            let x = Double(i)
            cpu.append(8 + 6 * sin(x / 5) + Double((i * 7) % 9))
            ram.append(78 + 4 * sin(x / 9) + Double((i * 3) % 4))
        }
        cpuHistory = cpu
        ramHistory = ram
        recomputeHealth()
    }
    #endif

    private func emptySnapshot() -> ServerSnapshot {
        ServerSnapshot(serverID: settings.primary.id, fetchedAt: .now)
    }

    private func appendHistory(from overview: ServerOverview?) {
        if let cpu = overview?.cpuPercent {
            cpuHistory.append(cpu)
            cpuHistory = Array(cpuHistory.suffix(Self.historyLimit))
        }
        if let ram = overview?.memoryPercent {
            ramHistory.append(ram)
            ramHistory = Array(ramHistory.suffix(Self.historyLimit))
        }
    }

    /// Remember the server's hostname on first success; route probing uses it to confirm identity.
    private func rememberHostname(_ hostname: String?) {
        guard let hostname, settings.primary.expectedHostname == nil else { return }
        settings.primary.expectedHostname = hostname
    }

    private func recomputeHealth() {
        guard snapshot != nil || isUnreachable else {
            health = nil
            return
        }
        health = HealthEvaluator.evaluate(
            snapshot: snapshot,
            thresholds: settings.preferences.thresholds,
            isStale: isStale,
            isUnreachable: isUnreachable
        )
    }
}

/// Runs an operation and captures its outcome, so `async let` siblings never cancel each other.
private func capture<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

/// A configured server address, for the Disconnected view.
struct ServerAddress: Identifiable, Equatable {
    var kind: RouteKind
    var url: URL
    /// MenuRaid is currently using (or last tried) this one.
    var isInUse: Bool

    var id: RouteKind { kind }
}

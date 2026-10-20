import Testing
import Foundation
@testable import MenuRaid

final class MockNotifier: Notifying, @unchecked Sendable {
    private let lock = NSLock()
    private var _posts: [ProblemNotification] = []
    private var _requests = 0
    private var _activations = 0
    var status: NotificationAuthorization
    var grantsPermission: Bool

    init(status: NotificationAuthorization = .allowed, grantsPermission: Bool = true) {
        self.status = status
        self.grantsPermission = grantsPermission
    }

    var posts: [ProblemNotification] { lock.withLock { _posts } }
    var permissionRequests: Int { lock.withLock { _requests } }
    var activations: Int { lock.withLock { _activations } }

    func authorizationStatus() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool {
        lock.withLock { _requests += 1 }
        return grantsPermission
    }
    func post(_ notification: ProblemNotification) async { lock.withLock { _posts.append(notification) } }
    func activate(onOpen: @escaping @MainActor @Sendable () -> Void) { lock.withLock { _activations += 1 } }
}

private func reason(_ id: String, level: HealthLevel = .red, message: String? = nil) -> HealthReason {
    HealthReason(level: level, message: message ?? id, id: id)
}

private func health(_ reasons: [HealthReason]) -> Health {
    Health(level: reasons.map(\.level).max() ?? .green, reasons: reasons)
}

struct ProblemDetectorTests {
    @Test func theFirstLookOnlyRecordsWhatIsAlreadyWrong() {
        var detector = ProblemDetector()
        #expect(detector.newProblems(in: health([reason("disk.disk1.failed")])).isEmpty)
    }

    @Test func aNewRedProblemIsReportedOnce() {
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([]))
        #expect(detector.newProblems(in: health([reason("disk.disk1.failed")])).map(\.id) == ["disk.disk1.failed"])
        #expect(detector.newProblems(in: health([reason("disk.disk1.failed")])).isEmpty)       // still there: not new
        #expect(detector.newProblems(in: health([reason("disk.disk1.failed")])).isEmpty)
    }

    @Test func aChangingMessageIsStillTheSameProblem() {
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([reason("disk.disk1.errors", message: "disk1: 5 errors")]))
        let next = detector.newProblems(in: health([reason("disk.disk1.errors", message: "disk1: 6 errors")]))
        #expect(next.isEmpty)   // the error count ticking up must not ping again
    }

    @Test func aProblemThatGoesAwayAndReturnsIsNewAgain() {
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([]))
        _ = detector.newProblems(in: health([reason("array.notStarted")]))
        _ = detector.newProblems(in: health([]))
        #expect(detector.newProblems(in: health([reason("array.notStarted")])).map(\.id) == ["array.notStarted"])
    }

    @Test func onlyTheNewOnesAreReportedWhenAnotherAlreadyExists() {
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([reason("disk.disk1.failed")]))
        let fresh = detector.newProblems(in: health([reason("disk.disk1.failed"), reason("disk.disk2.errors")]))
        #expect(fresh.map(\.id) == ["disk.disk2.errors"])
    }

    @Test func amberIsNeverNotified() {
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([]))
        let amber = [reason("array.parity", level: .amber), reason("notifications.unread", level: .amber), reason("data.stale", level: .amber)]
        #expect(detector.newProblems(in: health(amber)).isEmpty)
    }

    @Test func serverUnreachableIsNeverNotified() {
        // Can't tell a server outage from the Mac being offline, so it would cry wolf after every wake from sleep.
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([]))
        #expect(detector.newProblems(in: health([reason("server.unreachable")])).isEmpty)
    }

    @Test func severalNewProblemsAtOnceAreReportedTogether() {
        var detector = ProblemDetector()
        _ = detector.newProblems(in: health([]))
        let fresh = detector.newProblems(in: health([reason("a"), reason("b"), reason("c")]))
        #expect(fresh.count == 3)
    }
}

struct ProblemNotificationContentTests {
    @Test func singleProblem() {
        let n = ProblemNotification.make(hostname: "Tower", reasons: [reason("disk.disk1.failed", message: "disk1: disabled")])
        #expect(n.title == "Problem on Tower")
        #expect(n.body == "disk1: disabled")
    }

    @Test func severalProblemsAreCounted() {
        let n = ProblemNotification.make(hostname: "Tower", reasons: [reason("a", message: "one"), reason("b", message: "two")])
        #expect(n.title == "2 problems on Tower")
        #expect(n.body == "one\ntwo")
    }

    @Test func longListsAreCutOffWithACount() {
        let reasons = (1...6).map { reason("r\($0)", message: "problem \($0)") }
        let n = ProblemNotification.make(hostname: "Tower", reasons: reasons)
        #expect(n.body == "problem 1\nproblem 2\nproblem 3\nand 3 more")
    }

    @Test func missingHostnameFallsBack() {
        #expect(ProblemNotification.make(hostname: nil, reasons: [reason("a")]).title == "Problem on your server")
        #expect(ProblemNotification.make(hostname: "", reasons: [reason("a")]).title == "Problem on your server")
    }

    @Test func identifierIsStableForTheSameProblems() {
        let a = ProblemNotification.make(hostname: "Tower", reasons: [reason("x"), reason("y")])
        let b = ProblemNotification.make(hostname: "Tower", reasons: [reason("y"), reason("x")])
        #expect(a.identifier == b.identifier)
    }
}

struct ReasonIdentityTests {
    private func evaluate(_ disks: [DiskInfo], state: String = "STARTED") -> Health {
        let snapshot = ServerSnapshot(
            serverID: UUID(),
            array: ArrayInfo(state: state, capacity: nil, disks: disks, parityCheck: nil),
            fetchedAt: .now
        )
        return HealthEvaluator.evaluate(snapshot: snapshot, thresholds: Thresholds(), isStale: false, isUnreachable: false)
    }

    private func disk(_ name: String, status: String = "DISK_OK", errors: Int = 0, temp: Double? = 30) -> DiskInfo {
        DiskInfo(name: name, role: .data, tempC: temp, status: status, numErrors: errors, rotational: true)
    }

    @Test func theErrorCountChangingDoesNotChangeTheReasonIdentity() {
        let five = evaluate([disk("disk1", errors: 5)]).reasons.first!
        let six = evaluate([disk("disk1", errors: 6)]).reasons.first!
        #expect(five.message != six.message)
        #expect(five.id == six.id)
    }

    @Test func differentDisksAndProblemsHaveDifferentIdentities() {
        let ids = evaluate([disk("disk1", status: "DISK_DSBL", errors: 1), disk("disk2", errors: 1)]).reasons.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("disk.disk1.failed") && ids.contains("disk.disk1.errors") && ids.contains("disk.disk2.errors"))
    }

    @Test func everyKindOfReasonHasItsOwnStableId() {
        let all = evaluate([disk("d", status: "DISK_DSBL", errors: 2, temp: 60)], state: "STOPPED").reasons.map(\.id)
        #expect(Set(all) == ["array.notStarted", "disk.d.failed", "disk.d.errors", "disk.d.temp.critical"])
        #expect(HealthEvaluator.evaluate(snapshot: nil, thresholds: Thresholds(), isStale: true, isUnreachable: true).reasons.map(\.id)
                == ["server.unreachable", "data.stale"])
    }
}

@MainActor
struct StoreNotificationTests {
    private func makeStore(enabled: Bool, notifier: MockNotifier) -> (ServerStore, SettingsStore) {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.notify.\(UUID().uuidString)")!)
        settings.preferences.notifyOnProblems = enabled
        return (ServerStore(settings: settings, notifier: notifier, autostart: false), settings)
    }

    private func snapshot(_ settings: SettingsStore, disks: [DiskInfo]) -> ServerSnapshot {
        var overview = ServerOverview()
        overview.hostname = "Tower"
        return ServerSnapshot(
            serverID: settings.primary.id, overview: overview,
            array: ArrayInfo(state: "STARTED", capacity: nil, disks: disks, parityCheck: nil), fetchedAt: .now
        )
    }

    private func disk(_ name: String, status: String = "DISK_OK", errors: Int = 0) -> DiskInfo {
        DiskInfo(name: name, role: .data, tempC: 30, status: status, numErrors: errors, rotational: true)
    }

    @Test func startingWithAnExistingProblemStaysQuiet() async {
        let notifier = MockNotifier()
        let (store, settings) = makeStore(enabled: true, notifier: notifier)
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL")]))   // already wrong at launch
        await store.waitForNotifications()
        #expect(notifier.posts.isEmpty)
    }

    @Test func aNewProblemNotifiesOnceWithTheServersName() async {
        let notifier = MockNotifier()
        let (store, settings) = makeStore(enabled: true, notifier: notifier)
        store.loadPreview(snapshot(settings, disks: [disk("disk1")]))                                  // all fine
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL")]))             // disk fails
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL")]))             // refresh: unchanged
        await store.waitForNotifications()
        #expect(notifier.posts.count == 1)
        #expect(notifier.posts.first?.title == "Problem on Tower")
        #expect(notifier.posts.first?.body == "disk1: disabled")
    }

    @Test func switchedOffNeverNotifies() async {
        let notifier = MockNotifier()
        let (store, settings) = makeStore(enabled: false, notifier: notifier)
        store.loadPreview(snapshot(settings, disks: [disk("disk1")]))
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL")]))
        await store.waitForNotifications()
        #expect(notifier.posts.isEmpty)
    }

    @Test func switchingOnLaterDoesNotAnnounceOldProblems() async {
        let notifier = MockNotifier()
        let (store, settings) = makeStore(enabled: false, notifier: notifier)
        store.loadPreview(snapshot(settings, disks: [disk("disk1")]))
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL")]))   // happened while off
        settings.preferences.notifyOnProblems = true
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL")]))   // still the same problem
        await store.waitForNotifications()
        #expect(notifier.posts.isEmpty)
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL"), disk("disk2", errors: 3)]))   // genuinely new
        await store.waitForNotifications()
        #expect(notifier.posts.count == 1)
    }

    @Test func errorCountClimbingDoesNotRepeatTheNotification() async {
        let notifier = MockNotifier()
        let (store, settings) = makeStore(enabled: true, notifier: notifier)
        store.loadPreview(snapshot(settings, disks: [disk("disk1")]))
        for errors in [1, 2, 5, 40] { store.loadPreview(snapshot(settings, disks: [disk("disk1", errors: errors)])) }
        await store.waitForNotifications()
        #expect(notifier.posts.count == 1)
    }

    @Test func severalAtOnceAreOneNotification() async {
        let notifier = MockNotifier()
        let (store, settings) = makeStore(enabled: true, notifier: notifier)
        store.loadPreview(snapshot(settings, disks: [disk("disk1"), disk("disk2")]))
        store.loadPreview(snapshot(settings, disks: [disk("disk1", status: "DISK_DSBL"), disk("disk2", errors: 4)]))
        await store.waitForNotifications()
        #expect(notifier.posts.count == 1)
        #expect(notifier.posts.first?.title == "2 problems on Tower")
    }

    @Test func theTestButtonSendsATestNotification() async {
        let notifier = MockNotifier()
        let (store, _) = makeStore(enabled: true, notifier: notifier)
        store.sendTestNotification()
        await store.waitForNotifications()
        #expect(notifier.posts == [.test])
    }

    @Test func enablingAsksForPermissionOnlyWhenNeeded() async {
        let allowed = MockNotifier(status: .allowed)
        #expect(await makeStore(enabled: false, notifier: allowed).0.enableNotifications() == .allowed)
        #expect(allowed.permissionRequests == 0)

        let first = MockNotifier(status: .notDetermined, grantsPermission: true)
        #expect(await makeStore(enabled: false, notifier: first).0.enableNotifications() == .allowed)
        #expect(first.permissionRequests == 1)

        let refuses = MockNotifier(status: .notDetermined, grantsPermission: false)
        #expect(await makeStore(enabled: false, notifier: refuses).0.enableNotifications() == .denied)

        let denied = MockNotifier(status: .denied)
        #expect(await makeStore(enabled: false, notifier: denied).0.enableNotifications() == .denied)
        #expect(denied.permissionRequests == 0)   // already refused: don't re-prompt, the Settings note explains
    }

    @Test func clickHandlingIsHookedUp() {
        let notifier = MockNotifier()
        makeStore(enabled: true, notifier: notifier).0.activateNotifications()
        #expect(notifier.activations == 1)
    }

    @Test func offByDefaultAndOldSettingsStillLoad() throws {
        #expect(AppPreferences().notifyOnProblems == false)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"refreshInterval":60}"#.utf8)).notifyOnProblems == false)
    }
}

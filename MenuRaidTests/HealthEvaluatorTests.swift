import Testing
import Foundation
@testable import MenuRaid

struct HealthEvaluatorTests {
    private let thresholds = Thresholds()

    private func disk(
        _ name: String = "disk1", role: DiskRole = .data, status: String = "DISK_OK",
        temp: Double? = 30, errors: Int = 0, rotational: Bool? = true
    ) -> DiskInfo {
        DiskInfo(name: name, role: role, tempC: temp, status: status, isSpinning: temp != nil, numErrors: errors, rotational: rotational)
    }

    private func snapshot(
        state: String = "STARTED", disks: [DiskInfo] = [], parity: ParityCheck? = nil,
        notifications: NotificationCounts? = NotificationCounts(info: 5, warning: 0, alert: 0, total: 5)
    ) -> ServerSnapshot {
        ServerSnapshot(
            serverID: UUID(),
            array: ArrayInfo(state: state, capacity: nil, disks: disks, parityCheck: parity),
            notifications: notifications,
            fetchedAt: .now
        )
    }

    private func evaluate(_ snapshot: ServerSnapshot?, stale: Bool = false, unreachable: Bool = false) -> Health {
        HealthEvaluator.evaluate(snapshot: snapshot, thresholds: thresholds, isStale: stale, isUnreachable: unreachable)
    }

    @Test func healthyServerIsGreen() {
        let health = evaluate(snapshot(disks: [disk()]))
        #expect(health.level == .green)
        #expect(health.reasons.isEmpty)
    }

    @Test func arrayNotStartedIsRed() {
        #expect(evaluate(snapshot(state: "STOPPED", disks: [disk()])).level == .red)
    }

    @Test func disabledMissingAndInvalidDisksAreRed() {
        for status in ["DISK_DSBL", "DISK_INVALID", "DISK_NP_MISSING", "DISK_NP_DSBL"] {
            #expect(evaluate(snapshot(disks: [disk(status: status)])).level == .red, "\(status)")
        }
    }

    @Test func emptySlotIsNotAFailure() {
        #expect(evaluate(snapshot(disks: [disk(status: "DISK_NP", temp: nil)])).level == .green)
    }

    @Test func anyDiskErrorIsRed() {
        let health = evaluate(snapshot(disks: [disk(errors: 1)]))
        #expect(health.level == .red)
        #expect(health.reasons.first?.message == "disk1: 1 errors")
    }

    @Test func hddTemperatureThresholds() {
        #expect(evaluate(snapshot(disks: [disk(temp: 44)])).level == .green)
        #expect(evaluate(snapshot(disks: [disk(temp: 45)])).level == .amber)
        #expect(evaluate(snapshot(disks: [disk(temp: 54)])).level == .amber)
        #expect(evaluate(snapshot(disks: [disk(temp: 55)])).level == .red)
    }

    @Test func ssdUsesHigherThresholds() {
        #expect(evaluate(snapshot(disks: [disk(temp: 50, rotational: false)])).level == .green)
        #expect(evaluate(snapshot(disks: [disk(temp: 60, rotational: false)])).level == .amber)
        #expect(evaluate(snapshot(disks: [disk(temp: 70, rotational: false)])).level == .red)
    }

    @Test func unknownRotationalFallsBackToHDDLimits() {
        #expect(evaluate(snapshot(disks: [disk(temp: 50, rotational: nil)])).level == .amber)
    }

    @Test func spunDownDiskWithoutTempIsIgnored() {
        #expect(evaluate(snapshot(disks: [disk(temp: nil)])).level == .green)
    }

    @Test func customThresholdsAreHonoured() {
        let custom = Thresholds(hddWarn: 30, hddCritical: 35, ssdWarn: 60, ssdCritical: 70)
        let health = HealthEvaluator.evaluate(
            snapshot: snapshot(disks: [disk(temp: 32)]), thresholds: custom, isStale: false, isUnreachable: false
        )
        #expect(health.level == .amber)
    }

    @Test func parityCheckIsAmber() {
        let check = ParityCheck(running: true, paused: false, progress: 42, errors: nil, status: "RUNNING")
        let health = evaluate(snapshot(disks: [disk()], parity: check))
        #expect(health.level == .amber)
        #expect(health.reasons.first?.message == "Parity check running (42%)")
    }

    @Test func unreadAlertsAndWarningsAreAmberButInfoIsNot() {
        let info = NotificationCounts(info: 50, warning: 0, alert: 0, total: 50)
        #expect(evaluate(snapshot(disks: [disk()], notifications: info)).level == .green)
        let warn = NotificationCounts(info: 0, warning: 2, alert: 0, total: 2)
        #expect(evaluate(snapshot(disks: [disk()], notifications: warn)).level == .amber)
        let alert = NotificationCounts(info: 0, warning: 0, alert: 1, total: 1)
        #expect(evaluate(snapshot(disks: [disk()], notifications: alert)).level == .amber)
    }

    @Test func staleDataIsAmber() {
        #expect(evaluate(snapshot(disks: [disk()]), stale: true).level == .amber)
    }

    @Test func unreachableIsRedEvenWithoutSnapshot() {
        #expect(evaluate(nil, unreachable: true).level == .red)
    }

    @Test func worstLevelWinsAndReasonsAreSortedBySeverity() {
        let alert = NotificationCounts(info: 0, warning: 0, alert: 3, total: 3)
        let health = evaluate(snapshot(disks: [disk(status: "DISK_DSBL")], notifications: alert), stale: true)
        #expect(health.level == .red)
        #expect(health.reasons.map(\.level) == [.red, .amber, .amber])
    }

    // MARK: Where each reason leads

    @Test func diskArrayAndParityReasonsLinkToTheMainTab() {
        let check = ParityCheck(running: true, paused: false, progress: 10, errors: nil, status: "RUNNING")
        let health = evaluate(snapshot(state: "STOPPED", disks: [disk(status: "DISK_DSBL", temp: 58, errors: 3)], parity: check))
        #expect(health.reasons.count >= 4)
        #expect(health.reasons.allSatisfy { $0.link == .page(.main) })
    }

    @Test func notificationReasonLinksToNotifications() {
        let alert = NotificationCounts(info: 0, warning: 1, alert: 2, total: 3)
        let health = evaluate(snapshot(disks: [disk()], notifications: alert))
        #expect(health.reasons.first?.link == .page(.notifications))
    }

    @Test func unreachableLinksToConnectionSettingsAndStaleHasNoLink() {
        #expect(evaluate(nil, unreachable: true).reasons.first?.link == .connectionSettings)
        #expect(evaluate(snapshot(disks: [disk()]), stale: true).reasons.first?.link == nil)
    }

    @Test func theCardTitleSaysWhatIsWrong() {
        let alert = NotificationCounts(info: 0, warning: 0, alert: 1, total: 1)
        #expect(StatusCard.heading(for: evaluate(snapshot(disks: [disk(errors: 1)]))) == "Problem")
        #expect(StatusCard.heading(for: evaluate(snapshot(disks: [disk(status: "DISK_DSBL", errors: 2)]))) == "Problems")
        #expect(StatusCard.heading(for: evaluate(snapshot(disks: [disk()], notifications: alert))) == "Issue")
        let check = ParityCheck(running: true, paused: false, progress: 5, errors: nil, status: "RUNNING")
        #expect(StatusCard.heading(for: evaluate(snapshot(disks: [disk(temp: 50)], parity: check))) == "Issues")
        #expect(StatusCard.heading(for: evaluate(snapshot(disks: [disk()]))) == "All good")
        #expect(StatusCard.heading(for: nil) == "Status")
    }

    @Test func aMixOfProblemsAndIssuesIsTitledByTheWorst() {
        let alert = NotificationCounts(info: 0, warning: 0, alert: 1, total: 1)
        #expect(StatusCard.heading(for: evaluate(snapshot(disks: [disk(errors: 1)], notifications: alert))) == "Problems")
    }

    private struct FixtureEnvelope<T: Decodable>: Decodable { let data: T }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let json = try #require(FixtureJSON.named(name), "missing fixture \(name)")
        return try JSONDecoder().decode(FixtureEnvelope<T>.self, from: Data(json.utf8)).data
    }

    @Test func realServerWithDisabledDiskIsRed() throws {
        var snap = snapshot()
        snap.array = ArrayInfo.make(
            array: try load(ArrayResponse.self, "array"),
            extras: try load(DiskExtrasResponse.self, "diskExtras"),
            parity: try load(ParityCheckResponse.self, "parityCheck")
        )
        let health = evaluate(snap)
        #expect(health.level == .red)
        #expect(health.reasons.contains { $0.message.hasPrefix("disk1") })
    }
}

struct BackoffTests {
    @Test func stepsThenNormalInterval() {
        #expect(Backoff.delay(consecutiveFailures: 0, normal: 30) == 30)
        #expect([1, 2, 3, 4].map { Backoff.delay(consecutiveFailures: $0, normal: 30) } == [5, 15, 30, 60])
        #expect(Backoff.delay(consecutiveFailures: 5, normal: 30) == 30)
        #expect(Backoff.delay(consecutiveFailures: 99, normal: 120) == 120)
    }
}

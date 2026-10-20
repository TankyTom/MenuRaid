import Testing
import Foundation
@testable import MenuRaid

struct MetricHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsEmpty() {
        let history = MetricHistory()
        #expect(history.isEmpty && history.samples.isEmpty && history.values.isEmpty)
    }

    @Test func keepsSamplesInOrderWithTheirTimes() {
        var history = MetricHistory()
        history.append(10, at: at(0))
        history.append(20, at: at(30))
        history.append(30, at: at(35))
        #expect(history.values == [10, 20, 30])
        #expect(history.samples.map(\.date) == [at(0), at(30), at(35)])
    }

    @Test func mixedRefreshRatesKeepTheirRealSpacing() {
        // 30 s apart in the background, then 5 s apart with the panel open: the spacing must stay honest.
        var history = MetricHistory()
        for seconds in [0.0, 30, 60, 65, 70, 75] { history.append(1, at: at(seconds)) }
        let gaps = zip(history.samples, history.samples.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
        #expect(gaps == [30, 30, 5, 5, 5])
    }

    @Test func dropsReadingsOlderThanTheWindow() {
        var history = MetricHistory()
        history.append(1, at: at(0))
        history.append(2, at: at(60))
        history.append(3, at: at(MetricHistory.window + 30))   // the first is now older than the window
        #expect(history.values == [2, 3])
    }

    @Test func aReadingExactlyAtTheEdgeOfTheWindowIsKept() {
        var history = MetricHistory()
        history.append(1, at: at(0))
        history.append(2, at: at(MetricHistory.window))
        #expect(history.values == [1, 2])
    }

    @Test func aHardCapStopsRunawayGrowth() {
        var history = MetricHistory()
        for i in 0..<(MetricHistory.maxSamples + 50) { history.append(Double(i), at: at(Double(i) * 0.5)) }
        #expect(history.samples.count <= MetricHistory.maxSamples)
        #expect(history.values.last == Double(MetricHistory.maxSamples + 49))
    }

    @Test func aSampleFromThePastIsIgnoredSoTimeNeverGoesBackwards() {
        var history = MetricHistory()
        history.append(1, at: at(100))
        history.append(2, at: at(50))     // e.g. the clock was changed
        history.append(3, at: at(100))    // same instant is fine
        #expect(history.values == [1, 3])
    }

    @Test func removeAllEmptiesIt() {
        var history = MetricHistory()
        history.append(1, at: at(0))
        history.removeAll()
        #expect(history.isEmpty)
    }
}

struct CacheWritePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func writesTheFirstTime() {
        #expect(CacheWritePolicy.shouldWrite(lastWrite: nil, now: now))
    }

    @Test func notAgainWithinThirtySeconds() {
        #expect(!CacheWritePolicy.shouldWrite(lastWrite: now.addingTimeInterval(-5), now: now))
        #expect(!CacheWritePolicy.shouldWrite(lastWrite: now.addingTimeInterval(-29.9), now: now))
    }

    @Test func againOnceThirtySecondsHavePassed() {
        #expect(CacheWritePolicy.shouldWrite(lastWrite: now.addingTimeInterval(-30), now: now))
        #expect(CacheWritePolicy.shouldWrite(lastWrite: now.addingTimeInterval(-600), now: now))
    }
}

@MainActor
struct StoreHistoryTests {
    @Test func previewHistoryIsOrderedAndSpansTheWindow() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.hist.\(UUID().uuidString)")!)
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(ServerSnapshot(serverID: settings.primary.id, fetchedAt: .now))
        let dates = store.cpuHistory.samples.map(\.date)
        #expect(dates.count > 10)
        #expect(dates == dates.sorted())
        #expect(dates.last!.timeIntervalSince(dates.first!) <= MetricHistory.window)
    }
}

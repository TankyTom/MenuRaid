import Testing
import Foundation
@testable import MenuRaid

struct UnraidVersionTests {
    private func v(_ text: String) -> UnraidVersion { UnraidVersion(text)! }

    @Test func parsesCommonForms() {
        #expect(v("7.2.3").description == "7.2.3")
        #expect(v("7.2").description == "7.2.0")
        #expect(v("7").description == "7.0.0")
        #expect(v("v7.3.0-rc.2").description == "7.3.0-rc.2")
        #expect(v(" 7.1.4 \n").description == "7.1.4")
    }

    @Test func rejectsNonVersions() {
        for bad in ["", "abc", "7.x.1", "7.2.3.4", "-rc1", ".", "Unraid 7.2.3"] {
            #expect(UnraidVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func comparesNumbersNumericallyNotAsText() {
        #expect(v("7.2.3") < v("7.3.3"))
        #expect(v("7.9.0") < v("7.10.0"))      // the classic text-comparison trap
        #expect(v("6.12.13") < v("7.0.0"))
        #expect(v("7.2.9") < v("7.2.10"))
        #expect(!(v("7.3.3") < v("7.2.3")))
    }

    @Test func equalVersionsAreEqual() {
        #expect(v("7.2") == v("7.2.0"))
        #expect(!(v("7.2.3") < v("7.2.3")))
    }

    @Test func aPreReleaseIsOlderThanItsRelease() {
        #expect(v("7.3.0-rc.1") < v("7.3.0"))
        #expect(!(v("7.3.0") < v("7.3.0-rc.1")))
        #expect(v("7.2.3") < v("7.3.0-rc.1"))   // an RC of a later version is still later than an older release
    }

    @Test func preReleasesAreOrderedAmongThemselves() {
        #expect(v("7.3.0-rc.2") < v("7.3.0-rc.10"))
        #expect(v("7.3.0-beta.3") < v("7.3.0-rc.1"))
        #expect(v("7.3.0-rc") < v("7.3.0-rc.1"))
    }
}

struct ReleaseFeedTests {
    /// The feed's real response (fetched from releases.unraid.net).
    private let realFeed = #"""
    {
      "version": "7.3.3",
      "name": "Unraid 7.3.3",
      "date": "2026-10-06",
      "date0": "2026-05-12",
      "sha256": "673aaf477f9109913a6089e2f9515d66e1eb3d9765057a4988c439a29b6e7111",
      "changelog": "https://raw.githubusercontent.com/unraid/docs/main/docs/unraid-os/release-notes/7.3.3.md",
      "changelogPretty": "https://docs.unraid.net/unraid-os/release-notes/7.3.3/",
      "isEligible": true
    }
    """#

    @Test func decodesTheRealFeed() throws {
        let release = try LatestRelease.decode(Data(realFeed.utf8))
        #expect(release.version == "7.3.3")
        #expect(release.name == "Unraid 7.3.3")
        #expect(release.date == "2026-10-06")
        #expect(release.notesURL?.absoluteString == "https://docs.unraid.net/unraid-os/release-notes/7.3.3/")
    }

    @Test func onlyTheVersionIsRequired() throws {
        let release = try LatestRelease.decode(Data(#"{"version":"7.4.0"}"#.utf8))
        #expect(release.version == "7.4.0" && release.notesURL == nil && release.name == nil)
    }

    @Test func unreadableFeedsThrowInsteadOfInventingAVersion() {
        for bad in ["{}", #"{"version":"soon"}"#, #"{"version":null}"#, "[]", "not json", ""] {
            #expect(throws: (any Error).self, "\(bad)") { try LatestRelease.decode(Data(bad.utf8)) }
        }
    }

    @Test func releaseNotesMustBeHTTPS() throws {
        let feed = #"{"version":"7.4.0","changelogPretty":"http://example.com/notes"}"#
        #expect(try LatestRelease.decode(Data(feed.utf8)).notesURL == nil)
    }

    @Test func requestAsksForNothingAboutTheServer() {
        // Only the branch is sent: no version, hostname, key or anything else.
        let components = URLComponents(url: ReleaseChecker.endpoint, resolvingAgainstBaseURL: false)
        #expect(components?.host == "releases.unraid.net")
        #expect(components?.scheme == "https")
        #expect(components?.queryItems?.map(\.name) == ["branch"])
    }
}

struct ReleaseCheckPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    @Test func neverChecksWhenSwitchedOff() {
        #expect(!ReleaseCheckPolicy.shouldCheck(enabled: false, lastSuccess: nil, lastFailure: nil, now: now))
    }

    @Test func checksStraightAwayTheFirstTime() {
        #expect(ReleaseCheckPolicy.shouldCheck(enabled: true, lastSuccess: nil, lastFailure: nil, now: now))
    }

    @Test func waitsSixHoursAfterASuccess() {
        #expect(!ReleaseCheckPolicy.shouldCheck(enabled: true, lastSuccess: ago(5), lastFailure: nil, now: now))
        #expect(ReleaseCheckPolicy.shouldCheck(enabled: true, lastSuccess: ago(6.1), lastFailure: nil, now: now))
    }

    @Test func waitsAnHourAfterAFailure() {
        #expect(!ReleaseCheckPolicy.shouldCheck(enabled: true, lastSuccess: ago(10), lastFailure: ago(0.5), now: now))
        #expect(ReleaseCheckPolicy.shouldCheck(enabled: true, lastSuccess: ago(10), lastFailure: ago(1.5), now: now))
        #expect(!ReleaseCheckPolicy.shouldCheck(enabled: true, lastSuccess: nil, lastFailure: ago(0.2), now: now))
    }
}

struct OSUpdateComparisonTests {
    private func release(_ version: String) -> LatestRelease { LatestRelease(version: version, checkedAt: .now) }

    @Test func updateWhenStableIsNewer() {
        let update = OSUpdate.compare(current: "7.2.3", latest: release("7.3.3"))
        #expect(update?.current == "7.2.3")
        #expect(update?.latest.version == "7.3.3")
    }

    @Test func noUpdateWhenCurrentOrAhead() {
        #expect(OSUpdate.compare(current: "7.3.3", latest: release("7.3.3")) == nil)
        #expect(OSUpdate.compare(current: "7.4.0", latest: release("7.3.3")) == nil)
        // A release candidate of a version newer than stable is ahead, not behind.
        #expect(OSUpdate.compare(current: "7.4.0-rc.1", latest: release("7.3.3")) == nil)
    }

    @Test func aReleaseCandidateOfTheStableVersionCountsAsBehind() {
        #expect(OSUpdate.compare(current: "7.3.3-rc.1", latest: release("7.3.3")) != nil)
    }

    @Test func nothingWhenEitherSideIsUnknownOrUnreadable() {
        #expect(OSUpdate.compare(current: nil, latest: release("7.3.3")) == nil)
        #expect(OSUpdate.compare(current: "7.2.3", latest: nil) == nil)
        #expect(OSUpdate.compare(current: "unknown", latest: release("7.3.3")) == nil)
    }
}

final class MockReleaseFetcher: ReleaseFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var result: Result<LatestRelease, Error>

    init(_ result: Result<LatestRelease, Error>) { self.result = result }
    var calls: Int { lock.withLock { _calls } }

    func latestStable() async throws -> LatestRelease {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

@MainActor
struct OSUpdateStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(enabled: Bool, fetcher: MockReleaseFetcher, running: String? = "7.2.3") -> (ServerStore, SettingsStore) {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.os.\(UUID().uuidString)")!)
        settings.preferences.checkForOSUpdates = enabled
        let store = ServerStore(settings: settings, releaseFetcher: fetcher, autostart: false)
        var overview = ServerOverview()
        overview.unraidVersion = running
        store.loadPreview(ServerSnapshot(serverID: settings.primary.id, overview: overview, fetchedAt: .now))
        return (store, settings)
    }

    private func release(_ version: String = "7.3.3", at date: Date) -> LatestRelease {
        LatestRelease(version: version, name: "Unraid \(version)", date: "2026-10-06", notesURL: nil, checkedAt: date)
    }

    @Test func switchedOffNeverContactsAnyone() async {
        let fetcher = MockReleaseFetcher(.success(release(at: now)))
        let (store, _) = makeStore(enabled: false, fetcher: fetcher)
        await store.checkForOSUpdateIfNeeded(now: now)
        await store.checkForOSUpdateIfNeeded(force: true, now: now)
        #expect(fetcher.calls == 0)
        #expect(store.osUpdate == nil)
    }

    @Test func switchedOnFindsTheUpdate() async {
        let fetcher = MockReleaseFetcher(.success(release(at: now)))
        let (store, settings) = makeStore(enabled: true, fetcher: fetcher)
        #expect(store.osUpdate == nil)   // nothing known yet
        await store.checkForOSUpdateIfNeeded(now: now)
        #expect(fetcher.calls == 1)
        #expect(settings.latestRelease?.version == "7.3.3")
        #expect(store.osUpdate?.latest.version == "7.3.3")
        #expect(store.osUpdate?.current == "7.2.3")
    }

    @Test func notAskedAgainBeforeItsDue() async {
        let fetcher = MockReleaseFetcher(.success(release(at: now)))
        let (store, _) = makeStore(enabled: true, fetcher: fetcher)
        await store.checkForOSUpdateIfNeeded(now: now)
        await store.checkForOSUpdateIfNeeded(now: now.addingTimeInterval(3600))
        await store.checkForOSUpdateIfNeeded(now: now.addingTimeInterval(5 * 3600))
        #expect(fetcher.calls == 1)
    }

    @Test func askedAgainOnceDue() async {
        let fetcher = MockReleaseFetcher(.success(release(at: now)))
        let (store, settings) = makeStore(enabled: true, fetcher: fetcher)
        settings.recordLatestRelease(release("7.3.2", at: now.addingTimeInterval(-7 * 3600)))
        await store.checkForOSUpdateIfNeeded(now: now)
        #expect(fetcher.calls == 1)
        #expect(settings.latestRelease?.version == "7.3.3")
    }

    @Test func forceSkipsTheSchedule() async {
        let fetcher = MockReleaseFetcher(.success(release(at: now)))
        let (store, settings) = makeStore(enabled: true, fetcher: fetcher)
        settings.recordLatestRelease(release(at: now))
        await store.checkForOSUpdateIfNeeded(force: true, now: now)
        #expect(fetcher.calls == 1)
    }

    @Test func aFailureKeepsWhatWasKnownAndBacksOff() async {
        struct Offline: Error {}
        let fetcher = MockReleaseFetcher(.failure(Offline()))
        let (store, settings) = makeStore(enabled: true, fetcher: fetcher)
        settings.recordLatestRelease(release("7.3.3", at: now.addingTimeInterval(-7 * 3600)))
        await store.checkForOSUpdateIfNeeded(now: now)
        #expect(fetcher.calls == 1)
        #expect(store.osUpdate?.latest.version == "7.3.3")                 // still shows the earlier answer
        await store.checkForOSUpdateIfNeeded(now: now.addingTimeInterval(600))
        #expect(fetcher.calls == 1)                                        // not retried within the hour
        await store.checkForOSUpdateIfNeeded(now: now.addingTimeInterval(3700))
        #expect(fetcher.calls == 2)                                        // retried after
    }

    @Test func noBadgeWhenAlreadyUpToDateOrVersionUnknown() async {
        let up = makeStore(enabled: true, fetcher: MockReleaseFetcher(.success(release(at: now))), running: "7.3.3")
        await up.0.checkForOSUpdateIfNeeded(now: now)
        #expect(up.0.osUpdate == nil)

        let unknown = makeStore(enabled: true, fetcher: MockReleaseFetcher(.success(release(at: now))), running: nil)
        await unknown.0.checkForOSUpdateIfNeeded(now: now)
        #expect(unknown.0.osUpdate == nil)
    }

    @Test func switchingOffHidesTheBadgeAtOnce() async {
        let (store, settings) = makeStore(enabled: true, fetcher: MockReleaseFetcher(.success(release(at: now))))
        await store.checkForOSUpdateIfNeeded(now: now)
        #expect(store.osUpdate != nil)
        settings.preferences.checkForOSUpdates = false
        #expect(store.osUpdate == nil)
    }

    @Test func theLatestReleaseSurvivesARelaunch() {
        let suite = "menuraid.os.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStore(defaults: defaults).recordLatestRelease(release(at: now))
        #expect(SettingsStore(defaults: defaults).latestRelease?.version == "7.3.3")
    }

    @Test func offByDefaultAndOldSettingsStillLoad() throws {
        #expect(AppPreferences().checkForOSUpdates == false)
        let old = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"refreshInterval":60}"#.utf8))
        #expect(old.checkForOSUpdates == false)
    }
}

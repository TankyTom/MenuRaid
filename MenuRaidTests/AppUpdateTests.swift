import Testing
import Foundation
@testable import MenuRaid

struct AppReleaseFeedTests {
    /// The shape of GitHub's "latest release" response, trimmed to what matters.
    private let feed = #"""
    {
      "tag_name": "v1.0.1",
      "name": "MenuRaid 1.0.1",
      "html_url": "https://github.com/TankyTom/MenuRaid/releases/tag/v1.0.1",
      "draft": false,
      "prerelease": false
    }
    """#

    @Test func decodesGitHubsResponse() throws {
        let release = try AppRelease.decode(Data(feed.utf8))
        #expect(release.version == "v1.0.1")
        #expect(release.pageURL.absoluteString == "https://github.com/TankyTom/MenuRaid/releases/tag/v1.0.1")
    }

    @Test func rejectsAnUnreadableTagOrAPageThatIsntOnGitHub() {
        let badTag = #"{"tag_name":"latest","html_url":"https://github.com/TankyTom/MenuRaid/releases"}"#
        let elsewhere = #"{"tag_name":"v1.0.1","html_url":"https://example.com/MenuRaid"}"#
        let plainHTTP = #"{"tag_name":"v1.0.1","html_url":"http://github.com/TankyTom/MenuRaid"}"#
        let missing = #"{"tag_name":"v1.0.1"}"#
        for body in [badTag, elsewhere, plainHTTP, missing, "{}", "not json"] {
            #expect(throws: (any Error).self, "\(body)") { try AppRelease.decode(Data(body.utf8)) }
        }
    }

    @Test func asksOnlyGitHubAndSendsNothingAboutTheUser() {
        let components = URLComponents(url: AppUpdateChecker.endpoint, resolvingAgainstBaseURL: false)
        #expect(components?.scheme == "https")
        #expect(components?.host == "api.github.com")
        #expect(components?.queryItems == nil)
    }
}

struct AppUpdateComparisonTests {
    private func release(_ tag: String) -> AppRelease {
        AppRelease(version: tag, pageURL: URL(string: "https://github.com/TankyTom/MenuRaid/releases")!, checkedAt: .now)
    }

    @Test func updateWhenGitHubIsNewer() {
        let update = AppUpdate.compare(current: "1.0", latest: release("v1.0.1"))
        #expect(update?.current == "1.0")
        #expect(update?.latest.version == "v1.0.1")
        #expect(AppUpdate.compare(current: "1.9", latest: release("v1.10.0")) != nil)   // numeric, not text, order
    }

    @Test func noUpdateWhenCurrentOrAhead() {
        #expect(AppUpdate.compare(current: "1.0", latest: release("v1.0.0")) == nil)
        #expect(AppUpdate.compare(current: "1.1", latest: release("v1.0.9")) == nil)
    }

    @Test func nothingWhenEitherSideIsUnknownOrUnreadable() {
        #expect(AppUpdate.compare(current: nil, latest: release("v1.0.1")) == nil)
        #expect(AppUpdate.compare(current: "1.0", latest: nil) == nil)
        #expect(AppUpdate.compare(current: "dev", latest: release("v1.0.1")) == nil)
    }
}

final class MockAppReleaseFetcher: AppReleaseFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var result: Result<AppRelease, Error>

    init(_ result: Result<AppRelease, Error>) { self.result = result }
    var calls: Int { lock.withLock { _calls } }

    func latestRelease() async throws -> AppRelease {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

@MainActor
struct AppUpdateStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(enabled: Bool, fetcher: MockAppReleaseFetcher, installed: String? = "1.0") -> (ServerStore, SettingsStore) {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.app.\(UUID().uuidString)")!)
        settings.preferences.checkForAppUpdates = enabled
        let store = ServerStore(settings: settings, appReleaseFetcher: fetcher, installedVersion: installed, autostart: false)
        return (store, settings)
    }

    private func release(_ tag: String = "v1.0.1", at date: Date) -> AppRelease {
        AppRelease(version: tag, pageURL: URL(string: "https://github.com/TankyTom/MenuRaid/releases/tag/\(tag)")!, checkedAt: date)
    }

    @Test func switchedOffNeverContactsAnyone() async {
        let fetcher = MockAppReleaseFetcher(.success(release(at: now)))
        let (store, _) = makeStore(enabled: false, fetcher: fetcher)
        await store.checkForAppUpdateIfNeeded(now: now)
        await store.checkForAppUpdateIfNeeded(force: true, now: now)
        #expect(fetcher.calls == 0)
        #expect(store.appUpdate == nil)
    }

    @Test func switchedOnFindsTheUpdate() async {
        let fetcher = MockAppReleaseFetcher(.success(release(at: now)))
        let (store, settings) = makeStore(enabled: true, fetcher: fetcher)
        #expect(store.appUpdate == nil)   // nothing known yet
        await store.checkForAppUpdateIfNeeded(now: now)
        #expect(fetcher.calls == 1)
        #expect(settings.latestAppRelease?.version == "v1.0.1")
        #expect(store.appUpdate?.latest.version == "v1.0.1")
        #expect(store.appUpdate?.current == "1.0")
    }

    @Test func notAskedAgainBeforeItsDue() async {
        let fetcher = MockAppReleaseFetcher(.success(release(at: now)))
        let (store, _) = makeStore(enabled: true, fetcher: fetcher)
        await store.checkForAppUpdateIfNeeded(now: now)
        await store.checkForAppUpdateIfNeeded(now: now.addingTimeInterval(5 * 3600))
        #expect(fetcher.calls == 1)
        await store.checkForAppUpdateIfNeeded(now: now.addingTimeInterval(6.1 * 3600))
        #expect(fetcher.calls == 2)
    }

    @Test func aFailureKeepsWhatWasKnownAndBacksOff() async {
        struct Offline: Error {}
        let fetcher = MockAppReleaseFetcher(.failure(Offline()))
        let (store, settings) = makeStore(enabled: true, fetcher: fetcher)
        settings.recordLatestAppRelease(release("v1.0.1", at: now.addingTimeInterval(-7 * 3600)))
        await store.checkForAppUpdateIfNeeded(now: now)
        #expect(store.appUpdate?.latest.version == "v1.0.1")
        await store.checkForAppUpdateIfNeeded(now: now.addingTimeInterval(600))
        #expect(fetcher.calls == 1)
        await store.checkForAppUpdateIfNeeded(now: now.addingTimeInterval(3700))
        #expect(fetcher.calls == 2)
    }

    @Test func noBadgeWhenUpToDateOrInstalledVersionUnknown() async {
        let current = makeStore(enabled: true, fetcher: MockAppReleaseFetcher(.success(release("v1.0.0", at: now))))
        await current.0.checkForAppUpdateIfNeeded(now: now)
        #expect(current.0.appUpdate == nil)

        let unknown = makeStore(enabled: true, fetcher: MockAppReleaseFetcher(.success(release(at: now))), installed: nil)
        await unknown.0.checkForAppUpdateIfNeeded(now: now)
        #expect(unknown.0.appUpdate == nil)
    }

    @Test func switchingOffHidesTheBadgeAtOnce() async {
        let (store, settings) = makeStore(enabled: true, fetcher: MockAppReleaseFetcher(.success(release(at: now))))
        await store.checkForAppUpdateIfNeeded(now: now)
        #expect(store.appUpdate != nil)
        settings.preferences.checkForAppUpdates = false
        #expect(store.appUpdate == nil)
    }

    @Test func theLatestReleaseSurvivesARelaunch() {
        let suite = "menuraid.app.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStore(defaults: defaults).recordLatestAppRelease(release(at: now))
        #expect(SettingsStore(defaults: defaults).latestAppRelease?.version == "v1.0.1")
    }

    @Test func offByDefaultAndOldSettingsStillLoad() throws {
        #expect(AppPreferences().checkForAppUpdates == false)
        let old = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"refreshInterval":60}"#.utf8))
        #expect(old.checkForAppUpdates == false)
    }
}

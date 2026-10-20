import Testing
import Foundation
import ServiceManagement
@testable import MenuRaid

struct SecurityNoticeTests {
    private func config(lan: String, mode: RouteMode = .auto) -> ServerConfig {
        ServerConfig(lanAddress: lan, remoteAddress: "100.101.102.103", mode: mode)
    }

    @Test func plainHTTPLANAddressWarns() {
        #expect(SecurityNotice.shouldShowHTTPWarning(config: config(lan: "http://192.168.1.10"), dismissed: false))
        // No scheme means http:// (the default), so a bare IP warns too.
        #expect(SecurityNotice.shouldShowHTTPWarning(config: config(lan: "192.168.1.10"), dismissed: false))
    }

    @Test func httpsLANAddressDoesNotWarn() {
        #expect(!SecurityNotice.shouldShowHTTPWarning(config: config(lan: "https://tower.local"), dismissed: false))
    }

    @Test func noLANAddressOrRemoteOnlyModeDoesNotWarn() {
        #expect(!SecurityNotice.shouldShowHTTPWarning(config: config(lan: ""), dismissed: false))
        #expect(!SecurityNotice.shouldShowHTTPWarning(config: config(lan: "192.168.1.10", mode: .remote), dismissed: false))
    }

    @Test func dismissedWarningStaysHidden() {
        #expect(!SecurityNotice.shouldShowHTTPWarning(config: config(lan: "192.168.1.10"), dismissed: true))
    }

    @Test func settingsCaptionRuleIgnoresDismissal() {
        #expect(SecurityNotice.lanUsesPlainHTTP(config(lan: "192.168.1.10")))
        #expect(!SecurityNotice.lanUsesPlainHTTP(config(lan: "https://tower.local")))
        #expect(!SecurityNotice.lanUsesPlainHTTP(config(lan: "")))
    }
}

struct LaunchAtLoginStateTests {
    @Test func mapsEveryServiceStatus() {
        #expect(LaunchAtLoginState(.enabled) == .enabled)
        #expect(LaunchAtLoginState(.notRegistered) == .disabled)
        #expect(LaunchAtLoginState(.requiresApproval) == .needsApproval)
        #expect(LaunchAtLoginState(.notFound) == .unavailable)
    }

    @Test func toggleReadsOnOnceRegisteredEvenIfApprovalIsPending() {
        #expect(LaunchAtLoginState.enabled.isOn)
        #expect(LaunchAtLoginState.needsApproval.isOn)
        #expect(!LaunchAtLoginState.disabled.isOn)
        #expect(!LaunchAtLoginState.unavailable.isOn)
    }
}

@MainActor
struct StoreNoticeTests {
    private func makeSettings(lan: String = "192.168.1.10") -> SettingsStore {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.notice.\(UUID().uuidString)")!)
        settings.primary.lanAddress = lan
        return settings
    }

    private func snapshot(age: TimeInterval = 0, for settings: SettingsStore) -> ServerSnapshot {
        ServerSnapshot(serverID: settings.primary.id, fetchedAt: Date.now.addingTimeInterval(-age))
    }

    @Test func httpWarningShowsOnceThenStaysDismissed() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        #expect(store.showHTTPWarning)

        store.dismissHTTPWarning()
        #expect(!store.showHTTPWarning)
        #expect(settings.preferences.httpWarningDismissed)
    }

    @Test func noWarningForHTTPSLAN() {
        #expect(!ServerStore(settings: makeSettings(lan: "https://tower.local"), autostart: false).showHTTPWarning)
    }

    @Test func dismissalIsRememberedAfterRelaunch() {
        let suite = "menuraid.notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = SettingsStore(defaults: defaults)
        first.primary.lanAddress = "192.168.1.10"
        ServerStore(settings: first, autostart: false).dismissHTTPWarning()

        let relaunched = ServerStore(settings: SettingsStore(defaults: defaults), autostart: false)
        #expect(!relaunched.showHTTPWarning)
    }

    @Test func freshLiveDataIsNotDimmed() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(for: settings))
        #expect(!store.isDataDimmed)
    }

    @Test func savedDataFromLastLaunchIsDimmed() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(for: settings), fromCache: true)
        #expect(store.isDataDimmed)
    }

    @Test func staleDataIsDimmed() {
        let settings = makeSettings()   // refresh interval 30 s, so stale after 90 s
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(age: 600, for: settings))
        #expect(store.isStale && store.isDataDimmed)
    }

    @Test func unreachableServerDimsTheLastKnownData() {
        let settings = makeSettings()
        let store = ServerStore(settings: settings, autostart: false)
        store.loadPreview(snapshot(for: settings), unreachable: true)
        #expect(store.isDataDimmed)
    }

    @Test func nothingToDimWithoutData() {
        #expect(!ServerStore(settings: makeSettings(), autostart: false).isDataDimmed)
    }

    @Test func oldSavedPreferencesDefaultTheNoticeToNotDismissed() throws {
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"refreshInterval":60}"#.utf8))
        #expect(!prefs.httpWarningDismissed)
    }
}

@MainActor
struct StatusBadgeTests {
    @Test func onlyIssuesGetABadge() {
        #expect(StatusBadge(level: .green) == nil)
        #expect(StatusBadge(level: nil) == nil)          // no data yet: plain icon
        #expect(StatusBadge(level: .amber) == .attention)
        #expect(StatusBadge(level: .red) == .problem)
    }

    @Test func severitiesDifferInShapeAsWellAsColour() {
        #expect(StatusBadge.attention.symbol != StatusBadge.problem.symbol)
        #expect(StatusBadge.attention.color != StatusBadge.problem.color)
    }
}

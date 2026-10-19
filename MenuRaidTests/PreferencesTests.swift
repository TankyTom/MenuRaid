import Testing
import Foundation
@testable import MenuRaid

struct PreferencesTests {
    @Test func defaults() {
        let prefs = AppPreferences()
        #expect(prefs.appearance == .system)
        #expect(prefs.menuBarValue == .cpu)
        #expect(prefs.refreshInterval == 30)
    }

    @Test func oldSavedPreferencesWithoutAppearanceStillLoad() throws {
        let json = #"{"refreshInterval":60,"menuBarValue":"ram"}"#
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        #expect(prefs.refreshInterval == 60)
        #expect(prefs.menuBarValue == .ram)
        #expect(prefs.appearance == .system)
        #expect(prefs.thresholds == Thresholds())
    }

    @Test func unknownAppearanceFallsBackToSystem() throws {
        let json = #"{"appearance":"sepia"}"#
        #expect(try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8)).appearance == .system)
    }

    @Test @MainActor func sessionOverrideBeatsDefaultAndIsNotSaved() {
        let suite = "menuraid.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        settings.preferences.appearance = .light
        #expect(settings.effectiveAppearance == .light)

        settings.appearanceOverride = .dark
        #expect(settings.effectiveAppearance == .dark)

        let relaunched = SettingsStore(defaults: defaults)
        #expect(relaunched.effectiveAppearance == .light)
    }
}

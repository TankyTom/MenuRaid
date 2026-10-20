import Foundation
import Observation

/// Persisted, non-secret settings. The API key is never stored here (see `KeychainStore`).
@Observable
final class SettingsStore {
    private static let serversKey = "servers.v1"
    private static let preferencesKey = "preferences.v1"
    private static let releaseKey = "latestRelease.v1"

    /// All configured servers. Version 1 uses a single entry, but the list keeps multi-server open.
    private(set) var servers: [ServerConfig]

    var preferences: AppPreferences {
        didSet { save(preferences, key: Self.preferencesKey) }
    }

    /// The latest stable Unraid release seen at the last successful check (kept so the badge shows at launch).
    private(set) var latestRelease: LatestRelease?

    func recordLatestRelease(_ release: LatestRelease?) {
        latestRelease = release
        if let release { save(release, key: Self.releaseKey) } else { defaults.removeObject(forKey: Self.releaseKey) }
    }

    /// Set by the footer sun/moon button. Not saved, so the default from Settings applies on next launch.
    var appearanceOverride: AppearanceMode?

    /// The appearance in effect right now.
    var effectiveAppearance: AppearanceMode { appearanceOverride ?? preferences.appearance }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data),
           !decoded.isEmpty {
            servers = decoded
        } else {
            servers = [ServerConfig()]
        }
        if let data = defaults.data(forKey: Self.releaseKey) {
            let decoder = JSONDecoder()
            latestRelease = try? decoder.decode(LatestRelease.self, from: data)
        }
        if let data = defaults.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = AppPreferences()
        }
    }

    /// The server shown in the UI (the only one in version 1).
    var primary: ServerConfig {
        get { servers[0] }
        set {
            servers[0] = newValue
            save(servers, key: Self.serversKey)
        }
    }

    /// True until the user has entered at least one address.
    var needsSetup: Bool { !primary.hasAnyAddress }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

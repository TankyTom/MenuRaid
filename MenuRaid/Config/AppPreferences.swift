import Foundation

/// What to show next to the status symbol in the menu bar.
nonisolated enum MenuBarValue: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, ram, hottestDisk, iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU %"
        case .ram: "RAM %"
        case .hottestDisk: "Hottest disk temperature"
        case .iconOnly: "Icon only"
        }
    }
}

/// Light/dark appearance of the panel. `system` follows macOS.
nonisolated enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Disk temperature limits in °C. Spinning disks and SSD/NVMe have different limits.
nonisolated struct Thresholds: Codable, Equatable, Sendable {
    var hddWarn: Double = 45
    var hddCritical: Double = 55
    var ssdWarn: Double = 60
    var ssdCritical: Double = 70

    /// `rotational == false` means SSD/NVMe. Unknown (nil) falls back to the HDD limits.
    func warn(rotational: Bool?) -> Double { rotational == false ? ssdWarn : hddWarn }
    func critical(rotational: Bool?) -> Double { rotational == false ? ssdCritical : hddCritical }
}

nonisolated struct AppPreferences: Codable, Equatable, Sendable {
    static let refreshChoices = [10, 30, 60, 120]

    /// Background refresh interval in seconds. While the panel is open the app polls every 5 s.
    var refreshInterval: Int = 30
    var menuBarValue: MenuBarValue = .cpu
    /// Default panel appearance. The footer sun/moon button overrides it until the app is relaunched.
    var appearance: AppearanceMode = .system
    var thresholds = Thresholds()
    /// The one-time "your key is sent unencrypted over http://" notice has been dismissed.
    var httpWarningDismissed = false
    /// List running containers above stopped ones (within the chosen order).
    var dockerRunningFirst = true
    /// Ask Unraid's public release server which version is the latest stable. Off by default: it is the one
    /// request MenuRaid makes to anything other than your own server.
    var checkForOSUpdates = false

    init() {}

    // Lenient so adding a preference later never discards saved ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshInterval = c.lenientInt(.refreshInterval) ?? 30
        menuBarValue = c.lenient(MenuBarValue.self, .menuBarValue) ?? .cpu
        appearance = c.lenient(AppearanceMode.self, .appearance) ?? .system
        thresholds = c.lenient(Thresholds.self, .thresholds) ?? Thresholds()
        httpWarningDismissed = c.lenient(Bool.self, .httpWarningDismissed) ?? false
        dockerRunningFirst = c.lenient(Bool.self, .dockerRunningFirst) ?? true
        checkForOSUpdates = c.lenient(Bool.self, .checkForOSUpdates) ?? false
    }
}

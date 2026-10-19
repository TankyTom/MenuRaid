import Foundation
import Observation
import ServiceManagement

/// What the "Launch at login" toggle should show. Mirrors `SMAppService.Status`.
nonisolated enum LaunchAtLoginState: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but macOS wants the user to approve it in System Settings → General → Login Items.
    case needsApproval
    /// macOS can't find the app to register (e.g. running from a build folder in some setups).
    case unavailable

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .disabled
        case .requiresApproval: self = .needsApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    /// The toggle reads "on" once registered, even if approval is still pending.
    var isOn: Bool { self == .enabled || self == .needsApproval }
}

/// Registers MenuRaid as a login item with `SMAppService.mainApp`.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var state: LaunchAtLoginState
    private(set) var errorMessage: String?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        state = LaunchAtLoginState(service.status)
    }

    /// Re-reads the status; the user can change it behind our back in System Settings.
    func refresh() {
        state = LaunchAtLoginState(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

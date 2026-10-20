import Foundation
import Observation

/// Remembers the route chosen by `RouteResolver` so every refresh doesn't re-probe the LAN.
///
/// It re-probes only when told to (`invalidate()`): the network path changed, the Mac woke up,
/// or a request on the current route failed. Editing the addresses or mode also forces a fresh decision.
@MainActor
@Observable
final class RouteManager {
    private(set) var active: ActiveRoute?
    /// Why the preferred route wasn't used (shown in the panel), if applicable.
    private(set) var note: String?
    private(set) var certificateIssue: UnraidError?

    private let settings: SettingsStore
    private let prober: RouteProbing
    private var needsResolve = true
    private var resolvedFor: Signature?
    private var resolvedAt: Date?

    /// While on the remote route in Auto mode, look for the LAN again this often. Otherwise a server that wasn't
    /// ready at launch (or a first-run permission prompt) would leave you on the VPN indefinitely, even at home.
    static let lanRecheckInterval: TimeInterval = 5 * 60

    /// What the cached decision was based on.
    private struct Signature: Equatable {
        var lan: String
        var remote: String
        var mode: RouteMode
        var hostname: String?
    }

    init(settings: SettingsStore, prober: RouteProbing) {
        self.settings = settings
        self.prober = prober
    }

    private var currentSignature: Signature {
        let server = settings.primary
        return Signature(lan: server.lanAddress, remote: server.remoteAddress, mode: server.mode, hostname: server.expectedHostname)
    }

    /// Forces the next `resolve` to probe again.
    func invalidate() {
        needsResolve = true
    }

    /// The route to use now: the cached one, or a fresh decision if invalidated or the settings changed.
    func resolve(apiKey: String, now: Date = .now) async -> ActiveRoute? {
        let signature = currentSignature
        if !needsResolve, resolvedFor == signature, !shouldRecheckLAN(now: now) { return active }

        let resolution = await RouteResolver.resolve(settings.primary, apiKey: apiKey, prober: prober)
        // A cancelled refresh (panel opened, wake) makes the LAN probe fail for no real reason.
        // Don't remember that as "LAN is unavailable".
        if Task.isCancelled { return active }
        needsResolve = false
        resolvedFor = signature
        resolvedAt = now
        active = resolution.route
        note = resolution.note
        certificateIssue = resolution.certificateIssue
        return active
    }

    private func shouldRecheckLAN(now: Date) -> Bool {
        guard active?.kind == .remote, settings.primary.mode == .auto,
              AddressParser.parse(settings.primary.lanAddress) != nil,
              let resolvedAt
        else { return false }
        return now.timeIntervalSince(resolvedAt) >= Self.lanRecheckInterval
    }

    /// Clears everything, e.g. when the server config is reset.
    func reset() {
        active = nil
        note = nil
        certificateIssue = nil
        resolvedAt = nil
        needsResolve = true
    }

    #if DEBUG
    /// Fixed route for SwiftUI previews.
    func setPreviewRoute(_ route: ActiveRoute?) {
        active = route
        needsResolve = false
    }
    #endif
}

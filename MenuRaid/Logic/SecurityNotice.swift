import Foundation

/// When to warn that the API key travels unencrypted.
nonisolated enum SecurityNotice {
    /// Where an address points, as far as eavesdropping goes.
    enum HostScope: Equatable, Sendable {
        /// A private network, loopback, a local name, or a VPN (Tailscale): not open to the wider internet.
        case privateOrVPN
        /// Anything else: assumed to be reachable across the public internet.
        case publicInternet
    }

    /// Classifies a host (as stored by `AddressParser`: IPv6 without brackets, lowercase).
    static func scope(ofHost rawHost: String) -> HostScope {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard !host.isEmpty else { return .publicInternet }

        if let octets = ipv4Octets(host) {
            let (a, b) = (octets[0], octets[1])
            let isPrivate = a == 10                                   // 10.0.0.0/8
                || (a == 172 && (16...31).contains(b))                // 172.16.0.0/12
                || (a == 192 && b == 168)                             // 192.168.0.0/16
                || a == 127                                           // loopback
                || (a == 169 && b == 254)                             // link-local
                || (a == 100 && (64...127).contains(b))               // 100.64.0.0/10: CGNAT, which Tailscale uses
            return isPrivate ? .privateOrVPN : .publicInternet
        }

        if host.contains(":") {
            let zoneless = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
            if zoneless == "::1" { return .privateOrVPN }
            let first = zoneless.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if let value = UInt16(first, radix: 16) {
                if (0xfe80...0xfebf).contains(value) { return .privateOrVPN }   // link-local
                if (0xfc00...0xfdff).contains(value) { return .privateOrVPN }   // unique local (includes Tailscale's fd7a:...)
            }
            return .publicInternet
        }

        // Names: a single label ("tower") is a local name; so are the usual private suffixes and Tailscale's.
        if !host.contains(".") { return .privateOrVPN }
        let privateSuffixes = [".local", ".lan", ".home", ".home.arpa", ".internal", ".localdomain", ".ts.net"]
        return privateSuffixes.contains(where: host.hasSuffix) ? .privateOrVPN : .publicInternet
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ ($0 ?? -1) >= 0 && ($0 ?? 256) <= 255 }) else { return nil }
        return numbers.compactMap { $0 }
    }

    // MARK: LAN

    /// The LAN address is plain `http://`, so the key and data cross the home network unencrypted.
    static func lanUsesPlainHTTP(_ config: ServerConfig) -> Bool {
        guard let lan = AddressParser.parse(config.lanAddress) else { return false }
        return !lan.isHTTPS
    }

    /// Show the one-time warning when the LAN route can be used and is plain HTTP, until dismissed.
    static func shouldShowHTTPWarning(config: ServerConfig, dismissed: Bool) -> Bool {
        !dismissed && config.mode != .remote && lanUsesPlainHTTP(config)
    }

    // MARK: Remote

    /// The remote address is plain `http://` and doesn't look like a private network or VPN, so the key would cross
    /// the public internet unencrypted. A VPN address (Tailscale `100.x`, `.ts.net`) or a private one doesn't count:
    /// those are already encrypted or kept off the internet.
    static func remoteUsesUnprotectedHTTP(_ config: ServerConfig) -> Bool {
        guard let remote = AddressParser.parse(config.remoteAddress), !remote.isHTTPS else { return false }
        return scope(ofHost: remote.host) == .publicInternet
    }

    static func shouldShowRemoteHTTPWarning(config: ServerConfig, dismissed: Bool) -> Bool {
        !dismissed && config.mode != .lan && remoteUsesUnprotectedHTTP(config)
    }
}

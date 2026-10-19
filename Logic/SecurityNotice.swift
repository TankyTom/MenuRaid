import Foundation

/// When to warn that the API key travels unencrypted.
nonisolated enum SecurityNotice {
    /// The LAN address is plain `http://`, so the key and data cross the home network unencrypted.
    static func lanUsesPlainHTTP(_ config: ServerConfig) -> Bool {
        guard let lan = AddressParser.parse(config.lanAddress) else { return false }
        return !lan.isHTTPS
    }

    /// Show the one-time warning when the LAN route can be used and is plain HTTP, until dismissed.
    /// Remote addresses aren't warned about here: they're typically a VPN such as Tailscale, which encrypts the hop.
    static func shouldShowHTTPWarning(config: ServerConfig, dismissed: Bool) -> Bool {
        !dismissed && config.mode != .remote && lanUsesPlainHTTP(config)
    }
}

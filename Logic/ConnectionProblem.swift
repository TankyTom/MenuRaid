import Foundation

/// Why MenuRaid can't get data from the server, in plain language. Shown when everything fails.
nonisolated enum ConnectionProblem: Equatable, Sendable {
    /// Timed out, refused, or no route to the address.
    case unreachable
    /// The server answered but rejected the API key.
    case authRejected
    /// macOS blocked a plain http:// connection (App Transport Security).
    case insecureBlocked
    case certificateUntrusted
    case certificateChanged
    /// The LAN address now belongs to a different device and there's no remote address to fall back to.
    case wrongServer(note: String?)
    /// Something answered, but not like an Unraid API.
    case unexpectedResponse(String)

    static func classify(_ error: UnraidError?) -> ConnectionProblem {
        switch error {
        case nil, .unreachable?: .unreachable
        case .unauthorized?: .authRejected
        case .insecureConnectionBlocked?: .insecureBlocked
        case .untrustedCertificate?: .certificateUntrusted
        case .certificateMismatch?: .certificateChanged
        case .http(let status)?: .unexpectedResponse("The server answered with HTTP \(status).")
        case .graphQL(let messages)?: .unexpectedResponse(messages.joined(separator: "; "))
        case .decoding?: .unexpectedResponse("The server answered, but not like an Unraid API.")
        }
    }

    var title: String {
        switch self {
        case .unreachable: "Can't reach your server"
        case .authRejected: "API key rejected"
        case .insecureBlocked: "Blocked by macOS"
        case .certificateUntrusted: "Certificate not trusted"
        case .certificateChanged: "Certificate changed"
        case .wrongServer: "Not your server"
        case .unexpectedResponse: "Unexpected response"
        }
    }

    var symbol: String {
        switch self {
        case .unreachable: "wifi.slash"
        case .authRejected: "key.slash"
        case .insecureBlocked: "lock.open.trianglebadge.exclamationmark"
        case .certificateUntrusted, .certificateChanged: "lock.trianglebadge.exclamationmark"
        case .wrongServer: "questionmark.diamond"
        case .unexpectedResponse: "exclamationmark.bubble"
        }
    }

    /// What it means and what to try.
    var explanation: String {
        switch self {
        case .unreachable:
            "MenuRaid couldn't connect. Check that the server is on, and that you're on your home network or your VPN (such as Tailscale) is connected. It keeps retrying."
        case .authRejected:
            "The server answered but didn't accept your API key. Create a new key in Unraid (Settings → Management Access → API Keys) with at least the Viewer role and save it in MenuRaid's settings."
        case .insecureBlocked:
            "macOS refused a plain http:// connection to this address. Use https://, or make sure the app allows insecure connections (see the README)."
        case .certificateUntrusted:
            "This server's HTTPS certificate isn't trusted by macOS. In Settings → Connection, use Test connection, check the fingerprint, and trust it if it's yours."
        case .certificateChanged:
            "The server's certificate is different from the one you trusted, so the connection was blocked. If you changed it yourself, re-trust it in Settings → Connection."
        case .wrongServer(let note):
            note ?? "A different device answered at your LAN address, so MenuRaid didn't send it your API key. Add a remote address, or check the LAN address."
        case .unexpectedResponse(let detail):
            "\(detail) Check the address and port in Settings."
        }
    }

    /// The Settings window is the way forward for everything except a plain connection failure.
    var needsSettings: Bool {
        if case .unreachable = self { return false }
        return true
    }
}

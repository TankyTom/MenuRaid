import Foundation

nonisolated enum RouteKind: String, Sendable {
    case lan, remote
}

/// The address MenuRaid is currently talking to.
nonisolated struct ActiveRoute: Equatable, Sendable {
    var kind: RouteKind
    var base: URL
}

/// Result of asking an address "who are you?" with the cheapest real query.
nonisolated enum ProbeResult: Sendable {
    /// An Unraid server answered. `hostname` is its name, if it said.
    case server(hostname: String?)
    case failed(UnraidError)
}

/// Sends `{ info { os { hostname } } }` to an address. A protocol so route selection can be tested with a mock.
nonisolated protocol RouteProbing: Sendable {
    func probe(base: URL, apiKey: String, timeout: TimeInterval) async -> ProbeResult
}

extension UnraidClient: RouteProbing {
    nonisolated func probe(base: URL, apiKey: String, timeout: TimeInterval) async -> ProbeResult {
        do {
            return .server(hostname: try await fetchHostname(base: base, apiKey: apiKey, timeout: timeout))
        } catch let error as UnraidError {
            return .failed(error)
        } catch {
            return .failed(.unreachable(error.localizedDescription))
        }
    }
}

nonisolated struct RouteResolution: Sendable {
    var route: ActiveRoute?
    /// Plain-language reason when the preferred route wasn't used, shown in the panel.
    var note: String?
    /// A certificate problem (untrusted or changed) hit while probing, if any.
    var certificateIssue: UnraidError?
}

/// Decides which address to use. Pure apart from the probes it's given.
///
/// Auto mode: probe the LAN address with a 1 s timeout and confirm the answering server is ours
/// (hostname matches the one saved at first connection, and for HTTPS the pinned certificate must match).
/// If that passes, use the LAN; otherwise use the remote address. This keeps the API key from going to
/// some other device that happens to share the same IP on another network.
nonisolated enum RouteResolver {
    static let lanTimeout: TimeInterval = 1.0

    static func resolve(_ config: ServerConfig, apiKey: String, prober: RouteProbing) async -> RouteResolution {
        let lan = AddressParser.parse(config.lanAddress)?.baseURL
        let remote = AddressParser.parse(config.remoteAddress)?.baseURL

        switch config.mode {
        case .lan:
            return RouteResolution(route: lan.map { ActiveRoute(kind: .lan, base: $0) })
        case .remote:
            return RouteResolution(route: remote.map { ActiveRoute(kind: .remote, base: $0) })
        case .auto:
            break
        }

        guard let lan else {
            return RouteResolution(route: remote.map { ActiveRoute(kind: .remote, base: $0) })
        }
        let lanRoute = ActiveRoute(kind: .lan, base: lan)
        let remoteRoute = remote.map { ActiveRoute(kind: .remote, base: $0) }

        let result = await prober.probe(base: lan, apiKey: apiKey, timeout: lanTimeout)
        switch result {
        case .server(let hostname) where identityMatches(expected: config.expectedHostname, found: hostname):
            return RouteResolution(route: lanRoute)

        case .server(let hostname):
            // Something answered on the LAN address, but it isn't our server. Never send it the key.
            let found = hostname.map { "\"\($0)\"" } ?? "an unnamed server"
            let note = "The LAN address answered as \(found), not \"\(config.expectedHostname ?? "your server")\"."
            return RouteResolution(route: remoteRoute, note: remoteRoute == nil ? note + " Not using it." : note)

        case .failed(let error):
            let issue = error.isCertificateProblem ? error : nil
            if let remoteRoute {
                return RouteResolution(route: remoteRoute, note: "LAN address not available, using the remote address.", certificateIssue: issue)
            }
            // Only a LAN address exists. Keep using it; it may just be slow or briefly down.
            // A certificate problem is the exception: don't talk to a server we can't verify.
            return RouteResolution(
                route: error.isCertificateProblem ? nil : lanRoute,
                note: error.isCertificateProblem ? error.localizedDescription : nil,
                certificateIssue: issue
            )
        }
    }

    /// No saved hostname yet (first connection) accepts anything; afterwards it must match, ignoring case.
    static func identityMatches(expected: String?, found: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        guard let found else { return false }
        return expected.caseInsensitiveCompare(found) == .orderedSame
    }
}

extension UnraidError {
    nonisolated var isCertificateProblem: Bool {
        switch self {
        case .untrustedCertificate, .certificateMismatch: true
        default: false
        }
    }
}

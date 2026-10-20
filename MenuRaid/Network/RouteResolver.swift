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

/// What the keyless login page said about who is at an address.
nonisolated enum LoginNameResult: Sendable {
    case name(String)
    /// Something answered, but not with a page that names a server. Treated as "not verified".
    case unreadable
    /// Nothing answered in time.
    case failed(UnraidError)
}

/// Sends `{ info { os { hostname } } }` to an address, and can ask for the server's name WITHOUT the API key.
/// A protocol so route selection can be tested with a mock.
nonisolated protocol RouteProbing: Sendable {
    func probe(base: URL, apiKey: String, timeout: TimeInterval) async -> ProbeResult
    func loginName(base: URL, timeout: TimeInterval) async -> LoginNameResult
}

extension UnraidClient: RouteProbing {
    nonisolated func loginName(base: URL, timeout: TimeInterval) async -> LoginNameResult {
        do {
            let page = try await loginPage(base: base, timeout: timeout)
            return LoginPage.serverName(in: page).map(LoginNameResult.name) ?? .unreadable
        } catch let error as UnraidError {
            // Only "nothing answered" is a failure. An odd answer (a redirect, an error page) is unverified.
            if case .unreachable = error { return .failed(error) }
            return .unreadable
        } catch {
            return .failed(.unreachable(error.localizedDescription))
        }
    }

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
/// If that passes, use the LAN; otherwise use the remote address.
///
/// The keyed probe carries the API key, so on its own the hostname check can't stop it reaching an impostor.
/// - HTTPS: the pinned certificate is checked in the TLS handshake, before anything is sent.
/// - Plain HTTP with a saved hostname: the server's name is first read from the login page, which needs no key,
///   and the key is only sent if that name matches. A name that can't be read counts as a mismatch (fail safe).
///   A determined impostor can fake a page title, so only HTTPS fully rules that out; this stops the realistic case of
///   another network reusing the same IP.
/// - Plain HTTP on the very first connection has no saved hostname to compare with, so nothing can be checked yet.
nonisolated enum RouteResolver {
    static let lanTimeout: TimeInterval = 1.0

    /// Added to the "different server" note, because the usual cause is renaming the server in Unraid.
    static let renameHint = "If you renamed your server, use Reset next to Server identity in Settings → Connection (at home, on your own network)."

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

        func notOurs(_ found: String?) -> RouteResolution {
            let name = found.map { "\"\($0)\"" } ?? "an unnamed server"
            var note = "The LAN address answered as \(name), not \"\(config.expectedHostname ?? "your server")\"."
            if config.expectedHostname != nil { note += " " + renameHint }
            return RouteResolution(route: remoteRoute, note: remoteRoute == nil ? note + " Not using it." : note)
        }

        func unavailable(_ error: UnraidError) -> RouteResolution {
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

        // Plain HTTP can't be verified by a certificate, so check the server's name first, without the key.
        if lan.scheme == "http", let expected = config.expectedHostname, !expected.isEmpty {
            switch await prober.loginName(base: lan, timeout: lanTimeout) {
            case .name(let found) where identityMatches(expected: expected, found: found):
                break
            case .name(let found):
                return notOurs(found)
            case .unreadable:
                let note = "MenuRaid couldn't confirm the LAN address is your server, so it didn't send your API key there."
                return RouteResolution(route: remoteRoute, note: remoteRoute == nil ? note + " Not using it." : note)
            case .failed(let error):
                return unavailable(error)
            }
        }

        switch await prober.probe(base: lan, apiKey: apiKey, timeout: lanTimeout) {
        case .server(let hostname) where identityMatches(expected: config.expectedHostname, found: hostname):
            return RouteResolution(route: lanRoute)
        case .server(let hostname):
            // Something answered on the LAN address, but it isn't our server. Send it nothing further.
            return notOurs(hostname)
        case .failed(let error):
            return unavailable(error)
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

import Foundation

/// What "Test connection" learned about one address.
nonisolated struct ConnectionReport: Equatable, Identifiable, Sendable {
    enum Check: Equatable, Sendable {
        case yes, no, unknown
    }

    enum Identity: Equatable, Sendable {
        /// Hostname equals the one saved at first connection.
        case matches
        /// A different server answered.
        case differs(expected: String)
        /// Nothing saved yet; the hostname will be saved on the first successful refresh.
        case willBeSaved
        case unknown
    }

    enum Certificate: Equatable, Sendable {
        /// Plain HTTP: the key and data cross the network unencrypted.
        case notEncrypted
        case trustedBySystem
        case pinned
        /// Not trusted by the system and not pinned yet. Needs the user to confirm the fingerprint.
        case untrusted(fingerprint: String)
        /// Differs from the pinned certificate. The connection is blocked.
        case changed(expected: String, got: String)
    }

    var kind: RouteKind
    /// What was typed in Settings.
    var address: String
    var url: URL?
    var reachable: Bool
    var apiKey: Check
    var hostname: String?
    var identity: Identity
    var certificate: Certificate?
    var latency: TimeInterval?
    /// Plain-language problem, if any.
    var message: String?

    var id: RouteKind { kind }

    /// True when MenuRaid could use this address right now.
    var isUsable: Bool {
        reachable && apiKey == .yes && !isIdentityMismatch && !hasCertificateProblem
    }

    var isIdentityMismatch: Bool {
        if case .differs = identity { return true }
        return false
    }

    var hasCertificateProblem: Bool {
        switch certificate {
        case .untrusted?, .changed?: true
        default: false
        }
    }

    /// Builds a report from the outcome of one probe. Pure, so it's testable without a network.
    static func make(
        kind: RouteKind,
        address: String,
        url: URL?,
        outcome: Result<String?, UnraidError>,
        latency: TimeInterval?,
        expectedHostname: String?,
        hasPin: Bool
    ) -> ConnectionReport {
        let isHTTPS = url?.scheme == "https"
        var report = ConnectionReport(
            kind: kind, address: address, url: url, reachable: false, apiKey: .unknown,
            hostname: nil, identity: .unknown, certificate: isHTTPS ? nil : .notEncrypted,
            latency: nil, message: nil
        )

        switch outcome {
        case .success(let hostname):
            report.reachable = true
            report.apiKey = .yes
            report.hostname = hostname
            report.latency = latency
            if isHTTPS { report.certificate = hasPin ? .pinned : .trustedBySystem }
            if let expected = expectedHostname, !expected.isEmpty {
                report.identity = RouteResolver.identityMatches(expected: expected, found: hostname)
                    ? .matches : .differs(expected: expected)
                if report.isIdentityMismatch {
                    report.message = "A different server answered here. MenuRaid won't send it your API key in Auto mode."
                }
            } else {
                report.identity = hostname == nil ? .unknown : .willBeSaved
            }

        case .failure(let error):
            switch error {
            case .unauthorized:
                report.reachable = true
                report.apiKey = .no
                report.latency = latency
                report.message = "The server rejected the API key. Create a new one with at least the Viewer role."
            case .http(let status):
                report.reachable = true
                report.latency = latency
                report.message = "The server answered with HTTP \(status). Is this the Unraid webGUI address, and is the API enabled?"
            case .graphQL(let messages):
                report.reachable = true
                report.message = messages.joined(separator: "; ")
            case .decoding:
                report.reachable = true
                report.message = "The server answered, but not like an Unraid API. Check the address and port."
            case .untrustedCertificate(let fingerprint):
                report.reachable = true
                report.certificate = .untrusted(fingerprint: fingerprint)
                report.message = "This server's certificate isn't trusted by macOS. Check the fingerprint, then trust it to continue."
            case .certificateMismatch(let expected, let got):
                report.reachable = true
                report.certificate = .changed(expected: expected, got: got)
                report.message = "The server's certificate is different from the one you trusted. Connection blocked."
            case .insecureConnectionBlocked:
                report.message = "macOS blocked this plain http:// address. Use https://, or allow insecure connections in the app's App Transport Security setting."
            case .unreachable(let reason):
                report.message = "Couldn't connect (\(reason))."
            }
        }
        return report
    }
}

/// Runs "Test connection": checks the LAN and remote addresses separately.
nonisolated struct ConnectionTester: Sendable {
    let client: UnraidClient
    var timeout: TimeInterval = 8

    func run(config: ServerConfig, apiKey: String, pins: CertPinStore = .shared) async -> [ConnectionReport] {
        async let lan = test(.lan, address: config.lanAddress, config: config, apiKey: apiKey, pins: pins)
        async let remote = test(.remote, address: config.remoteAddress, config: config, apiKey: apiKey, pins: pins)
        return await [lan, remote].compactMap { $0 }
    }

    /// nil when the address field is empty (nothing to test).
    private func test(_ kind: RouteKind, address: String, config: ServerConfig, apiKey: String, pins: CertPinStore) async -> ConnectionReport? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let url = AddressParser.parse(trimmed)?.baseURL else {
            return ConnectionReport(
                kind: kind, address: trimmed, url: nil, reachable: false, apiKey: .unknown, hostname: nil,
                identity: .unknown, certificate: nil, latency: nil, message: "That isn't a valid address."
            )
        }

        let clock = ContinuousClock()
        let start = clock.now
        var outcome: Result<String?, UnraidError>
        do {
            outcome = .success(try await client.fetchHostname(base: url, apiKey: apiKey, timeout: timeout))
        } catch let error as UnraidError {
            outcome = .failure(error)
        } catch {
            outcome = .failure(.unreachable(error.localizedDescription))
        }
        let elapsed = start.duration(to: clock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        return ConnectionReport.make(
            kind: kind, address: trimmed, url: url, outcome: outcome, latency: seconds,
            expectedHostname: config.expectedHostname, hasPin: url.host.map { pins.pin(for: $0) != nil } ?? false
        )
    }
}

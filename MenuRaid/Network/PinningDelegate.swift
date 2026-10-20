import Foundation
import CryptoKit
import Security

/// Remembers why a TLS challenge was refused, so the client can throw a precise error
/// (URLSession itself only reports a generic cancellation).
nonisolated final class CertFailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String: UnraidError] = [:]

    func set(_ error: UnraidError, host: String) {
        lock.withLock { failures[host.lowercased()] = error }
    }

    func take(host: String) -> UnraidError? {
        lock.withLock { failures.removeValue(forKey: host.lowercased()) }
    }
}

/// Which redirects MenuRaid follows. Only to the same host, and never from https down to http.
/// A different host is refused outright so the `x-api-key` header can't be forwarded to it.
nonisolated enum RedirectPolicy {
    static func allows(from original: URL?, to target: URL?) -> Bool {
        guard let original, let target,
              let fromHost = original.host?.lowercased(), let toHost = target.host?.lowercased(),
              fromHost == toHost,
              let fromScheme = original.scheme?.lowercased(), let toScheme = target.scheme?.lowercased(),
              toScheme == "http" || toScheme == "https"
        else { return false }
        // http → https on the same host (a port change is fine) is an upgrade; https → http is a downgrade.
        return !(fromScheme == "https" && toScheme == "http")
    }
}

/// TOFU certificate pinning.
/// - A pinned host must present exactly the pinned certificate.
/// - An unpinned host is accepted only if the system already trusts its certificate.
/// - Otherwise the connection is refused and the fingerprint is reported for confirmation.
/// There is deliberately no "trust anything" path.
nonisolated final class PinningDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let pins: CertPinStore
    private let failures: CertFailureBox

    init(pins: CertPinStore, failures: CertFailureBox) {
        self.pins = pins
        self.failures = failures
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let fingerprint = Self.leafFingerprint(of: trust) ?? "unknown"

        if let pinned = pins.pin(for: host) {
            if fingerprint == pinned {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                failures.set(.certificateMismatch(expected: pinned, got: fingerprint), host: host)
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.performDefaultHandling, nil)
        } else {
            failures.set(.untrustedCertificate(fingerprint: fingerprint), host: host)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Every request carries the API key, so a redirect must not carry it somewhere else.
    /// A refused redirect hands back the 3xx response itself, which the client reports as an error.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let allowed = RedirectPolicy.allows(from: task.originalRequest?.url, to: request.url)
        completionHandler(allowed ? request : nil)
    }

    /// SHA-256 of the leaf certificate's DER bytes, as `AA:BB:...`.
    static func leafFingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

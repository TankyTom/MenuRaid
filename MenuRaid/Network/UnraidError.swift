import Foundation

/// Failures from talking to the Unraid GraphQL API. Messages never contain the API key.
nonisolated enum UnraidError: Error, LocalizedError, Sendable {
    case unreachable(String)
    /// macOS (App Transport Security) refused a plain http:// connection to this address.
    case insecureConnectionBlocked
    case unauthorized
    case http(Int)
    case graphQL([String])
    case decoding(String)
    /// HTTPS certificate isn't trusted by the system and no pin exists yet (trust on first use).
    case untrustedCertificate(fingerprint: String)
    /// HTTPS certificate differs from the pinned one. The connection is blocked.
    case certificateMismatch(expected: String, got: String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let reason):
            "Couldn't reach the server (\(reason))"
        case .insecureConnectionBlocked:
            "macOS blocked a plain http:// connection to this address"
        case .unauthorized:
            "The server rejected the API key"
        case .http(let status):
            "Server returned HTTP \(status)"
        case .graphQL(let messages):
            messages.joined(separator: "; ")
        case .decoding(let detail):
            "Unexpected response (\(detail))"
        case .untrustedCertificate:
            "The server's certificate isn't trusted yet"
        case .certificateMismatch:
            "The server's certificate changed. Connection blocked"
        }
    }
}

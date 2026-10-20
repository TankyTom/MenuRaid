import Foundation

/// Standard GraphQL response envelope.
nonisolated private struct GraphQLEnvelope<T: Decodable>: Decodable {
    struct Failure: Decodable { let message: String? }
    let data: T?
    let errors: [Failure]?
}

/// Talks to the Unraid GraphQL API (`POST <base>/graphql`). Owns the URLSession and its pinning delegate.
/// The API key is passed per call and only ever placed in the `x-api-key` header; it is never logged.
actor UnraidClient {
    private let session: URLSession
    private let failures = CertFailureBox()

    init(pins: CertPinStore = .shared) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(
            configuration: configuration,
            delegate: PinningDelegate(pins: pins, failures: failures),
            delegateQueue: nil
        )
    }

    /// Sends a query and returns the raw response body (used by the debug tool).
    func rawQuery(_ query: String, base: URL, apiKey: String, timeout: TimeInterval = 8) async throws -> Data {
        var request = URLRequest(url: base.appending(path: "graphql"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        return try await send(request, base: base)
    }

    /// Fetches the webGUI login page WITHOUT the API key. Its title names the server, so a plain-HTTP address can be
    /// checked before the key is ever sent to it.
    func loginPage(base: URL, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: base.appending(path: "login"), timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await send(request, base: base)
        // The title is near the top; don't hold on to a whole page.
        return String(decoding: data.prefix(LoginPage.maxBytes), as: UTF8.self)
    }

    private func send(_ request: URLRequest, base: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let host = base.host, let certError = failures.take(host: host) { throw certError }
            if (error as? URLError)?.code == .appTransportSecurityRequiresSecureConnection {
                throw UnraidError.insecureConnectionBlocked
            }
            throw UnraidError.unreachable((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw UnraidError.decoding("not an HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw UnraidError.unauthorized
        default: throw UnraidError.http(http.statusCode)
        }
    }

    /// Runs a query and decodes `data` as `T`.
    /// A response with `errors` but no `data` fails with the server's messages; partial data is returned as-is.
    func query<T: Decodable & Sendable>(
        _ query: String,
        as type: T.Type = T.self,
        base: URL,
        apiKey: String,
        timeout: TimeInterval = 8
    ) async throws -> T {
        let body = try await rawQuery(query, base: base, apiKey: apiKey, timeout: timeout)
        let envelope: GraphQLEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(GraphQLEnvelope<T>.self, from: body)
        } catch {
            throw UnraidError.decoding(String(describing: error))
        }
        if let data = envelope.data { return data }
        let messages = (envelope.errors ?? []).compactMap(\.message)
        throw messages.isEmpty ? UnraidError.decoding("empty response") : UnraidError.graphQL(messages)
    }
}

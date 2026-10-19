import Foundation

/// A normalised server address: scheme, host and optional webGUI port.
nonisolated struct ParsedAddress: Equatable, Sendable {
    var scheme: String
    var host: String
    var port: Int?

    var isHTTPS: Bool { scheme == "https" }

    /// Base URL of the webGUI, e.g. `http://192.168.1.10:8080`. IPv6 hosts are bracketed.
    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host.contains(":") ? "[\(host)]" : host
        components.port = port
        return components.url
    }
}

nonisolated enum AddressParser {
    /// Parses what a person types into a settings field.
    ///
    /// Accepts an IP or hostname, an optional `http://` / `https://` scheme (default `http://`)
    /// and an optional `:port`. Any path, query or fragment is ignored.
    /// Returns nil for empty input, unsupported schemes or a missing host.
    static func parse(_ input: String) -> ParsedAddress? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        if let port = components.port, !(1...65535).contains(port) { return nil }
        // Store IPv6 literals without brackets; `baseURL` adds them back.
        let bareHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard !bareHost.isEmpty else { return nil }
        return ParsedAddress(scheme: scheme, host: bareHost, port: components.port)
    }
}

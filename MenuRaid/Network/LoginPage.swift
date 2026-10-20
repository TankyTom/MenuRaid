import Foundation

/// Reads the server's name from the webGUI login page, which needs no API key.
/// Unraid titles it `<title>Hostname/Login</title>`. Parsing is deliberately strict: anything else is "unreadable",
/// and an unreadable name means MenuRaid won't send the API key to that address.
nonisolated enum LoginPage {
    /// How much of the page is read; the title is in the first few hundred bytes.
    static let maxBytes = 64 * 1024

    static func serverName(in html: String) -> String? {
        let head = String(html.prefix(maxBytes))
        guard let regex = try? NSRegularExpression(
            pattern: #"<title>\s*([^<>/]+?)\s*/\s*Login\s*</title>"#, options: .caseInsensitive
        ),
              let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head)
        else { return nil }
        let name = String(head[range])
        // A real hostname: letters, digits, dots, hyphens, underscores.
        guard !name.isEmpty, name.count <= 253,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") })
        else { return nil }
        return name
    }
}

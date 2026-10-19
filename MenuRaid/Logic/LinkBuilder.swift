import Foundation

/// What clicking a container should do.
nonisolated enum ContainerLink: Equatable, Sendable {
    /// A URL from the per-container override in Settings, used exactly as written.
    case override(URL)
    /// The container's own WebUI setting from its Unraid template, with `[IP]` and `[PORT:n]` filled in.
    case webUI(URL)
    /// No WebUI set: `http://<active host>:<lowest published TCP port>`.
    case published(URL)
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case noServer
        case noPublishedPort
    }

    var url: URL? {
        switch self {
        case .override(let url), .webUI(let url), .published(let url): url
        case .unavailable: nil
        }
    }

    /// Shown as the tooltip on a container that can't be opened.
    var unavailableMessage: String? {
        switch self {
        case .unavailable(.noServer): "No server address set. Add one in Settings."
        case .unavailable(.noPublishedPort): "No web UI or published port. Set a URL override in Settings."
        default: nil
        }
    }
}

/// Builds every link the panel opens. Pure functions, so they are easy to test.
nonisolated enum LinkBuilder {
    enum Page: String, Sendable {
        case dashboard = "Dashboard"
        case main = "Main"                       // array, disks, parity check
        case docker = "Docker"
        case vms = "VMs"
        case systemLog = "Tools/Syslog"
        case notifications = "Tools/NotificationsArchive"
        case terminal = "webterminal/ttyd/"
        case fileManager = "Main/Browse"

        /// Shown on buttons and tooltips.
        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .main: "Main tab"
            case .docker: "Docker page"
            case .vms: "VMs page"
            case .systemLog: "System log"
            case .notifications: "Notifications"
            case .terminal: "Terminal"
            case .fileManager: "File manager"
            }
        }

        /// Query string for pages that need one. The file manager opens at the array's mount point.
        var query: String? {
            switch self {
            case .fileManager: "dir=/mnt"
            default: nil
            }
        }
    }

    /// A page of the Unraid webGUI on the active route, e.g. `http://192.168.1.10/VMs`.
    static func page(_ page: Page, base: URL) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base.appending(path: page.rawValue)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/" + page.rawValue
        components.percentEncodedQuery = page.query   // set as-is so "?" and "/" aren't escaped
        return components.url ?? base.appending(path: page.rawValue)
    }

    /// Where a click on a container should go, in this order:
    /// 1. A per-container override, used exactly as written.
    /// 2. The container's WebUI setting from its Unraid template (what Unraid's own WebUI button uses),
    ///    with `[IP]` replaced by the active host and `[PORT:n]` by the public port mapped to container port `n`.
    /// 3. Otherwise the lowest published TCP port on the active host (a generic fallback; the webGUI's own
    ///    port is never used).
    /// 4. Otherwise nothing: bridge/host-network containers without a published port have nothing to link to.
    static func container(_ container: DockerContainer, base: URL?, overrides: [String: String]) -> ContainerLink {
        if let raw = overrideValue(for: container.name, in: overrides), let url = parseOverride(raw) {
            return .override(url)
        }
        let host = base?.host.flatMap { $0.isEmpty ? nil : $0 }

        if let template = container.webUITemplate, let url = resolveWebUI(template, host: host, container: container) {
            return .webUI(url)
        }

        guard let host else { return .unavailable(.noServer) }
        // Live ports first; while a container is stopped Docker reports none, so fall back to the template's.
        let candidates = container.ports.isEmpty ? (container.templatePorts ?? []) : container.ports
        guard let port = candidates
            .filter({ $0.isTCP && ($0.publicPort ?? 0) > 0 })
            .compactMap(\.publicPort)
            .min()
        else { return .unavailable(.noPublishedPort) }

        var components = URLComponents()
        components.scheme = "http"
        components.host = urlHost(host)
        components.port = port
        guard let url = components.url else { return .unavailable(.noPublishedPort) }
        return .published(url)
    }

    /// Fills in a template like `https://[IP]:[PORT:8080]/path`. Returns nil if it can't be resolved
    /// (no address for `[IP]`, a port that isn't published, leftover placeholders, or not an http(s) URL).
    static func resolveWebUI(_ template: String, host: String?, container: DockerContainer) -> URL? {
        var text = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.range(of: "[IP]", options: .caseInsensitive) != nil {
            guard let host else { return nil }
            text = text.replacingOccurrences(of: "[IP]", with: urlHost(host), options: .caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: #"\[PORT:(\d+)\]"#, options: .caseInsensitive) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // Replace from the end so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text),
                  let privatePort = Int(text[digits]),
                  let port = publicPort(forPrivatePort: privatePort, in: container)
            else { return nil }
            text.replaceSubrange(whole, with: String(port))
        }

        // Anything still in brackets (an unknown placeholder) makes the URL invalid, so it's rejected here.
        return parseOverride(text)
    }

    /// The port to use for a container port, in order:
    /// 1. a live published mapping (Docker's current view);
    /// 2. the template's mapping, which is still there while the container is stopped (Docker then reports no ports);
    /// 3. the container port itself, but only if neither source knows of any mapping: that's a host-network container,
    ///    where the container port is the port on the server.
    /// A container that has mappings, none of them for this port, is a bridge container that doesn't publish it.
    private static func publicPort(forPrivatePort privatePort: Int, in container: DockerContainer) -> Int? {
        func mapped(_ ports: [PortMapping]) -> Int? {
            ports.first { $0.isTCP && $0.privatePort == privatePort && ($0.publicPort ?? 0) > 0 }?.publicPort
        }
        if let live = mapped(container.ports) { return live }
        if let template = mapped(container.templatePorts ?? []) { return template }
        let knowsAnyMapping = !container.ports.isEmpty || !(container.templatePorts ?? []).isEmpty
        return knowsAnyMapping ? nil : privatePort
    }

    /// IPv6 literals need brackets in a URL; the stored host has none.
    private static func urlHost(_ host: String) -> String {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return bare.contains(":") ? "[\(bare)]" : bare
    }

    /// Container names match case-insensitively; an empty value means "no override".
    static func overrideValue(for name: String, in overrides: [String: String]) -> String? {
        let match = overrides.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        guard let trimmed = match?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Accepts a full URL (kept exactly, including path and query) or a bare `host[:port][/path]`,
    /// which gets `http://`. Returns nil if it isn't an http(s) URL with a host.
    static func parseOverride(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: full),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    // MARK: VM consoles

    /// Valid range for a VM console (web-socket proxy) port.
    static let validPorts = 1...65535

    /// The browser VNC console for a running VM, via Unraid's own noVNC page, e.g.
    /// `http://host/plugins/dynamix.vm.manager/vnc.html?resize=scale&autoconnect=true&host=host&port=&path=/wsproxy/5700/`.
    /// It goes through the webGUI, so it works on the LAN and over a remote route alike.
    /// Returns nil unless the VM is running and has a console port set.
    static func vmConsole(_ vm: VirtualMachine, base: URL?, ports: [String: Int]) -> URL? {
        guard vm.state == .running, let base, let host = base.host, !host.isEmpty,
              let port = consolePort(for: vm.name, in: ports)
        else { return nil }

        let bareHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let hostParam = bareHost.contains(":") ? "[\(bareHost)]" : bareHost
        // The page's own port (empty when the webGUI uses the scheme's default), like Unraid's own link.
        let pagePort = base.port.map(String.init) ?? ""

        var components = URLComponents()
        components.scheme = base.scheme
        components.host = hostParam
        components.port = base.port
        components.path = "/plugins/dynamix.vm.manager/vnc.html"
        components.percentEncodedQuery = "resize=scale&autoconnect=true&host=\(queryEncoded(hostParam))&port=\(pagePort)&path=/wsproxy/\(port)/"
        return components.url
    }

    /// Percent-encodes a query value. Needed for IPv6 hosts: `[` and `]` aren't legal in a query
    /// (and setting them unencoded would crash `URLComponents`).
    private static func queryEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#[]")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// VM names match case-insensitively. Out-of-range values count as "not set".
    static func consolePort(for name: String, in ports: [String: Int]) -> Int? {
        let value = ports.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        guard let value, validPorts.contains(value) else { return nil }
        return value
    }
}

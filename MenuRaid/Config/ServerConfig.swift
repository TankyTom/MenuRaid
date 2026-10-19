import Foundation

/// How MenuRaid chooses between the LAN and remote address.
nonisolated enum RouteMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case lan
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .lan: "Always LAN"
        case .remote: "Always remote"
        }
    }
}

/// One monitored server. Holds no secrets: the API key lives in the Keychain, keyed by `id`.
/// Everything is keyed by `id` so a second server can be added later without a rewrite.
nonisolated struct ServerConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var lanAddress: String
    var remoteAddress: String
    var mode: RouteMode
    /// Hostname recorded on first successful connection, used to verify a LAN host is really our server.
    var expectedHostname: String?
    /// Container name -> URL to open instead of the auto-built host:port link
    /// (reverse proxies, Cloudflare tunnels, containers whose first published port isn't the web UI).
    var containerOverrides: [String: String]
    /// VM name -> VNC web-socket port (the 5700 in `/wsproxy/5700/`). The API doesn't report it.
    var vmConsolePorts: [String: Int]

    init(
        id: UUID = UUID(),
        lanAddress: String = "",
        remoteAddress: String = "",
        mode: RouteMode = .auto,
        expectedHostname: String? = nil,
        containerOverrides: [String: String] = [:],
        vmConsolePorts: [String: Int] = [:]
    ) {
        self.id = id
        self.lanAddress = lanAddress
        self.remoteAddress = remoteAddress
        self.mode = mode
        self.expectedHostname = expectedHostname
        self.containerOverrides = containerOverrides
        self.vmConsolePorts = vmConsolePorts
    }

    private enum CodingKeys: String, CodingKey {
        case id, lanAddress, remoteAddress, mode, expectedHostname, containerOverrides, vmConsolePorts
    }

    // Lenient, so settings saved by an older version (without newer fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        lanAddress = c.lenient(String.self, .lanAddress) ?? ""
        remoteAddress = c.lenient(String.self, .remoteAddress) ?? ""
        mode = c.lenient(RouteMode.self, .mode) ?? .auto
        expectedHostname = c.lenient(String.self, .expectedHostname)
        containerOverrides = c.lenient([String: String].self, .containerOverrides) ?? [:]
        vmConsolePorts = c.lenient([String: Int].self, .vmConsolePorts) ?? [:]
    }

    var hasAnyAddress: Bool {
        !lanAddress.trimmingCharacters(in: .whitespaces).isEmpty
            || !remoteAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

import Foundation

// MARK: - Docker

nonisolated struct PortMapping: Codable, Equatable, Sendable {
    var ip: String?
    var privatePort: Int?
    var publicPort: Int?
    /// "TCP" or "UDP"
    var type: String?

    var isTCP: Bool { type?.uppercased() == "TCP" }

    init(ip: String? = nil, privatePort: Int? = nil, publicPort: Int? = nil, type: String? = "TCP") {
        self.ip = ip
        self.privatePort = privatePort
        self.publicPort = publicPort
        self.type = type
    }

    private enum CodingKeys: String, CodingKey { case ip, privatePort, publicPort, type }

    // Lenient: a null or oddly typed field never drops the container.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ip = c.lenient(String.self, .ip)
        privatePort = c.lenientInt(.privatePort)
        publicPort = c.lenientInt(.publicPort)
        type = c.lenient(String.self, .type)
    }
}

nonisolated enum ContainerState: String, Codable, Sendable {
    case running, paused, restarting, exited, created, dead, unknown

    init(api: String?) {
        self = api.flatMap { ContainerState(rawValue: $0.lowercased()) } ?? .unknown
    }

    var isRunning: Bool { self == .running }
}

nonisolated struct DockerContainer: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// Display name, without the leading `/` the API returns.
    var name: String
    var image: String?
    var state: ContainerState
    var statusText: String?
    var ports: [PortMapping]
    /// The container's WebUI setting from its Unraid template, e.g. `http://[IP]:[PORT:8112]/`.
    /// Placeholders are filled in by `LinkBuilder` using the address in use.
    var webUITemplate: String?

    /// The label Unraid writes from a container's template, and the one its own WebUI button reads.
    /// (Some images set other labels of their own, such as `com.unraid.template.webui`; Unraid ignores those.)
    static let webUILabelKeys = ["net.unraid.docker.webui"]
}

nonisolated struct DockerResponse: Decodable, Sendable {
    var containers: [DockerContainer]

    private enum Root: String, CodingKey { case docker }
    private enum Keys: String, CodingKey { case containers }

    private struct Raw: Decodable {
        var id: String?
        var names: [String]
        var image: String?
        var state: String?
        var status: String?
        var ports: [PortMapping]
        var webUITemplate: String?

        private enum Keys: String, CodingKey { case id, names, image, state, status, ports, labels }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = c.lenient(String.self, .id)
            names = c.lenient([String].self, .names) ?? []
            image = c.lenient(String.self, .image)
            state = c.lenient(String.self, .state)
            status = c.lenient(String.self, .status)
            ports = c.lenientArray(.ports)
            // Only the WebUI setting is kept; the rest of the labels aren't needed.
            let labels = c.lenient([String: String].self, .labels) ?? [:]
            webUITemplate = DockerContainer.webUILabelKeys
                .compactMap { labels[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
    }

    init(from decoder: Decoder) throws {
        let docker = try decoder.container(keyedBy: Root.self).nestedContainer(keyedBy: Keys.self, forKey: .docker)
        let raw: [Raw] = docker.lenientArray(.containers)
        containers = raw.compactMap { item in
            guard let rawName = item.names.first else { return nil }
            let name = rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName
            return DockerContainer(
                id: item.id ?? name, name: name, image: item.image,
                state: ContainerState(api: item.state), statusText: item.status, ports: item.ports,
                webUITemplate: item.webUITemplate
            )
        }
    }
}

// MARK: - VMs

nonisolated enum VMState: String, Codable, Sendable {
    case running, paused, shutoff, idle, crashed, other

    init(api: String?) {
        self = api.flatMap { VMState(rawValue: $0.lowercased()) } ?? .other
    }
}

nonisolated struct VirtualMachine: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var state: VMState
}

nonisolated struct VMsResponse: Decodable, Sendable {
    var vms: [VirtualMachine]

    private enum Root: String, CodingKey { case vms }
    private enum Keys: String, CodingKey { case domains }

    private struct Raw: Decodable {
        var id: String?
        var name: String?
        var state: String?

        private enum Keys: String, CodingKey { case id, name, state }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = c.lenient(String.self, .id)
            name = c.lenient(String.self, .name)
            state = c.lenient(String.self, .state)
        }
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Root.self).nestedContainer(keyedBy: Keys.self, forKey: .vms)
        let raw: [Raw] = box.lenientArray(.domains)
        vms = raw.compactMap { item in
            guard let name = item.name else { return nil }
            return VirtualMachine(id: item.id ?? name, name: name, state: VMState(api: item.state))
        }
    }
}

// MARK: - Notifications

nonisolated struct NotificationCounts: Codable, Equatable, Sendable {
    var info: Int
    var warning: Int
    var alert: Int
    var total: Int
}

nonisolated struct NotificationsResponse: Decodable, Sendable {
    var unread: NotificationCounts

    private enum Root: String, CodingKey { case notifications }
    private enum Keys: String, CodingKey { case overview }
    private enum Overview: String, CodingKey { case unread }
    private enum Unread: String, CodingKey { case info, warning, alert, total }

    init(from decoder: Decoder) throws {
        let notifications = try decoder.container(keyedBy: Root.self).nestedContainer(keyedBy: Keys.self, forKey: .notifications)
        let overview = try notifications.nestedContainer(keyedBy: Overview.self, forKey: .overview)
        let c = try overview.nestedContainer(keyedBy: Unread.self, forKey: .unread)
        let info = c.lenientInt(.info) ?? 0
        let warning = c.lenientInt(.warning) ?? 0
        let alert = c.lenientInt(.alert) ?? 0
        unread = NotificationCounts(info: info, warning: warning, alert: alert, total: c.lenientInt(.total) ?? info + warning + alert)
    }
}

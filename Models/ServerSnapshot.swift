import Foundation

/// Everything shown in the panel at one moment. Each section is optional so one failing query
/// leaves the rest intact. Cached to disk (never contains the API key).
nonisolated struct ServerSnapshot: Codable, Equatable, Sendable {
    var serverID: UUID
    var overview: ServerOverview?
    var array: ArrayInfo?
    var containers: [DockerContainer]?
    var vms: [VirtualMachine]?
    var notifications: NotificationCounts?
    var fetchedAt: Date
}

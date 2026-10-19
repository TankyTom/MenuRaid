import Foundation

/// One fetcher per panel section, so `ServerStore` can run them independently and concurrently.
extension UnraidClient {
    func fetchOverview(base: URL, apiKey: String, timeout: TimeInterval = 8) async throws -> ServerOverview {
        try await query(Queries.overview, as: OverviewResponse.self, base: base, apiKey: apiKey, timeout: timeout).overview
    }

    /// The array section needs three queries. The main one is required; the disk extras and
    /// parity-check queries are best-effort, so their failure doesn't blank the section.
    func fetchArray(base: URL, apiKey: String, timeout: TimeInterval = 8) async throws -> ArrayInfo {
        async let main = query(Queries.array, as: ArrayResponse.self, base: base, apiKey: apiKey, timeout: timeout)
        async let extras = try? query(Queries.diskExtras, as: DiskExtrasResponse.self, base: base, apiKey: apiKey, timeout: timeout)
        async let parity = try? query(Queries.parityCheck, as: ParityCheckResponse.self, base: base, apiKey: apiKey, timeout: timeout)
        return try await ArrayInfo.make(array: main, extras: extras, parity: parity)
    }

    func fetchContainers(base: URL, apiKey: String, timeout: TimeInterval = 8) async throws -> [DockerContainer] {
        try await query(Queries.docker, as: DockerResponse.self, base: base, apiKey: apiKey, timeout: timeout).containers
    }

    func fetchVMs(base: URL, apiKey: String, timeout: TimeInterval = 8) async throws -> [VirtualMachine] {
        try await query(Queries.vms, as: VMsResponse.self, base: base, apiKey: apiKey, timeout: timeout).vms
    }

    func fetchNotifications(base: URL, apiKey: String, timeout: TimeInterval = 8) async throws -> NotificationCounts {
        try await query(Queries.notifications, as: NotificationsResponse.self, base: base, apiKey: apiKey, timeout: timeout).unread
    }

    /// Cheapest real query; used for route probing and identity checks.
    func fetchHostname(base: URL, apiKey: String, timeout: TimeInterval) async throws -> String? {
        let response = try await query(Queries.identity, as: OverviewResponse.self, base: base, apiKey: apiKey, timeout: timeout)
        return response.overview.hostname
    }
}

import Foundation

/// Flattened server overview shown in the panel header and system section.
nonisolated struct ServerOverview: Codable, Equatable, Sendable {
    var hostname: String?
    var distro: String?
    var release: String?
    var unraidVersion: String?
    /// When the server booted. The API reports a boot timestamp, not a duration.
    var bootTime: Date?
    var cpuBrand: String?
    var cpuCores: Int?
    var cpuThreads: Int?
    var cpuPercent: Double?
    var memoryTotalBytes: Double?
    var memoryUsedBytes: Double?
    var memoryPercent: Double?

    func uptime(now: Date = .now) -> TimeInterval? {
        bootTime.map { max(0, now.timeIntervalSince($0)) }
    }
}

/// GraphQL response shape for `Queries.overview`.
nonisolated struct OverviewResponse: Decodable, Sendable {
    let overview: ServerOverview

    private enum Root: String, CodingKey { case info, metrics }
    private enum Info: String, CodingKey { case os, cpu, versions }
    private enum OS: String, CodingKey { case hostname, distro, release, uptime }
    private enum CPUInfo: String, CodingKey { case brand, cores, threads }
    private enum Versions: String, CodingKey { case core }
    private enum Core: String, CodingKey { case unraid }
    private enum Metrics: String, CodingKey { case cpu, memory }
    private enum CPUMetrics: String, CodingKey { case percentTotal }
    private enum Memory: String, CodingKey { case total, used, percentTotal }

    init(from decoder: Decoder) throws {
        var value = ServerOverview()
        let root = try decoder.container(keyedBy: Root.self)

        if let info = try? root.nestedContainer(keyedBy: Info.self, forKey: .info) {
            if let os = try? info.nestedContainer(keyedBy: OS.self, forKey: .os) {
                value.hostname = os.lenient(String.self, .hostname)
                value.distro = os.lenient(String.self, .distro)
                value.release = os.lenient(String.self, .release)
                value.bootTime = Self.bootTime(from: os)
            }
            if let cpu = try? info.nestedContainer(keyedBy: CPUInfo.self, forKey: .cpu) {
                value.cpuBrand = cpu.lenient(String.self, .brand)
                value.cpuCores = cpu.lenientInt(.cores)
                value.cpuThreads = cpu.lenientInt(.threads)
            }
            if let versions = try? info.nestedContainer(keyedBy: Versions.self, forKey: .versions),
               let core = try? versions.nestedContainer(keyedBy: Core.self, forKey: .core) {
                value.unraidVersion = core.lenient(String.self, .unraid)
            }
        }

        if let metrics = try? root.nestedContainer(keyedBy: Metrics.self, forKey: .metrics) {
            if let cpu = try? metrics.nestedContainer(keyedBy: CPUMetrics.self, forKey: .cpu) {
                value.cpuPercent = cpu.lenientDouble(.percentTotal)
            }
            if let memory = try? metrics.nestedContainer(keyedBy: Memory.self, forKey: .memory) {
                value.memoryTotalBytes = memory.lenientDouble(.total)
                value.memoryUsedBytes = memory.lenientDouble(.used)
                value.memoryPercent = memory.lenientDouble(.percentTotal)
            }
        }
        overview = value
    }

    /// `uptime` is an ISO-8601 boot timestamp on 7.2; fall back to treating a number as seconds of uptime.
    private static func bootTime(from os: KeyedDecodingContainer<OS>) -> Date? {
        if let text = os.lenient(String.self, .uptime) {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            if let date = ISO8601DateFormatter().date(from: text) { return date }
        }
        if let seconds = os.lenientDouble(.uptime) {
            return Date.now.addingTimeInterval(-seconds)
        }
        return nil
    }
}

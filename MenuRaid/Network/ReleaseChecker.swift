import Foundation

/// The latest stable Unraid OS release, from Unraid's public release feed.
nonisolated struct LatestRelease: Codable, Equatable, Sendable {
    var version: String
    var name: String?
    /// Release date as the feed gives it, e.g. "2026-10-06".
    var date: String?
    /// Human-readable release notes.
    var notesURL: URL?
    /// When MenuRaid fetched this.
    var checkedAt: Date

    /// Reads the feed's JSON leniently: only `version` is required.
    static func decode(_ data: Data, checkedAt: Date = .now) throws -> LatestRelease {
        struct Feed: Decodable {
            let version: String?
            let name: String?
            let date: String?
            let changelogPretty: String?
            let changelog: String?
        }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard let version = feed.version, UnraidVersion(version) != nil else { throw ReleaseCheckError.unreadable }
        let notes = (feed.changelogPretty ?? feed.changelog).flatMap { URL(string: $0) }.flatMap { $0.scheme == "https" ? $0 : nil }
        return LatestRelease(version: version, name: feed.name, date: feed.date, notesURL: notes, checkedAt: checkedAt)
    }
}

nonisolated enum ReleaseCheckError: Error, Sendable {
    case unreadable
    case http(Int)
}

/// Something that can fetch the latest stable release. A protocol so tests don't touch the network.
nonisolated protocol ReleaseFetching: Sendable {
    func latestStable() async throws -> LatestRelease
}

/// Asks Unraid's public release server for the latest stable version.
///
/// This is the only request MenuRaid makes to anything other than your own server, and only if you turn it on.
/// It is a plain GET with no query about your server: no version, no hostname, no API key.
nonisolated struct ReleaseChecker: ReleaseFetching {
    static let endpoint = URL(string: "https://releases.unraid.net/os?branch=stable")!

    func latestStable() async throws -> LatestRelease {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ReleaseCheckError.http(http.statusCode)
        }
        return try LatestRelease.decode(data)
    }
}

/// When to ask the release server again.
nonisolated enum ReleaseCheckPolicy {
    /// After a successful check.
    static let interval: TimeInterval = 6 * 3600
    /// After a failed one, so a flaky connection doesn't hammer the server.
    static let retryInterval: TimeInterval = 3600

    static func shouldCheck(enabled: Bool, lastSuccess: Date?, lastFailure: Date?, now: Date = .now) -> Bool {
        guard enabled else { return false }
        if let lastFailure, now.timeIntervalSince(lastFailure) < retryInterval { return false }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }
}

/// An update is available: what the server runs and what the latest stable release is.
nonisolated struct OSUpdate: Equatable, Sendable {
    var current: String
    var latest: LatestRelease

    /// nil unless the latest stable release is strictly newer than the running version.
    /// A server on a newer (or equal) version, such as a release candidate ahead of stable, gets no badge.
    static func compare(current: String?, latest: LatestRelease?) -> OSUpdate? {
        guard let current, let latest,
              let running = UnraidVersion(current), let available = UnraidVersion(latest.version),
              running < available
        else { return nil }
        return OSUpdate(current: current, latest: latest)
    }
}

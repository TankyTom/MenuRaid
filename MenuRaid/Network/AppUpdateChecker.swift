import Foundation

/// The latest MenuRaid release published on GitHub.
nonisolated struct AppRelease: Codable, Equatable, Sendable {
    /// The release tag, e.g. "v1.0.1".
    var version: String
    /// The release's page on GitHub, where the download is.
    var pageURL: URL
    /// When MenuRaid fetched this.
    var checkedAt: Date

    /// Reads GitHub's "latest release" JSON leniently: only `tag_name` and a github.com `html_url` are required.
    static func decode(_ data: Data, checkedAt: Date = .now) throws -> AppRelease {
        struct Feed: Decodable {
            let tag_name: String?
            let html_url: String?
        }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard let tag = feed.tag_name, UnraidVersion(tag) != nil,
              let page = feed.html_url.flatMap({ URL(string: $0) }),
              page.scheme == "https", page.host == "github.com"
        else { throw ReleaseCheckError.unreadable }
        return AppRelease(version: tag, pageURL: page, checkedAt: checkedAt)
    }
}

/// Something that can fetch the latest MenuRaid release. A protocol so tests don't touch the network.
nonisolated protocol AppReleaseFetching: Sendable {
    func latestRelease() async throws -> AppRelease
}

/// Asks GitHub for MenuRaid's latest published release (drafts and pre-releases are excluded by GitHub).
///
/// Only made if you turn on "Check for MenuRaid updates". A plain GET: nothing about you or your server is sent.
nonisolated struct AppUpdateChecker: AppReleaseFetching {
    static let endpoint = URL(string: "https://api.github.com/repos/TankyTom/MenuRaid/releases/latest")!

    func latestRelease() async throws -> AppRelease {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub's API rejects requests without a User-Agent.
        request.setValue("MenuRaid", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ReleaseCheckError.http(http.statusCode)
        }
        return try AppRelease.decode(data)
    }
}

/// A newer MenuRaid than the one installed.
nonisolated struct AppUpdate: Equatable, Sendable {
    var current: String
    var latest: AppRelease

    /// nil unless the latest release is strictly newer than the installed version.
    static func compare(current: String?, latest: AppRelease?) -> AppUpdate? {
        guard let current, let latest,
              let installed = UnraidVersion(current), let available = UnraidVersion(latest.version),
              installed < available
        else { return nil }
        return AppUpdate(current: current, latest: latest)
    }
}

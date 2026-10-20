import Foundation

/// Decides which health reasons are *new* problems worth a notification.
///
/// - Only red reasons count: amber is "needs attention", not "wake me up".
/// - "Server unreachable" never notifies: MenuRaid can't tell a server outage from your Mac being offline
///   (waking from sleep, a flaky Wi-Fi), so it would cry wolf.
/// - The first evaluation after launch only records what's already wrong, so starting the app doesn't announce
///   problems you already know about.
/// - A problem notifies once. It can notify again only after it has gone away and come back.
nonisolated struct ProblemDetector: Sendable {
    private var known: Set<String>?

    static func isNotifiable(_ reason: HealthReason) -> Bool {
        reason.level == .red && reason.id != "server.unreachable"
    }

    /// Returns the red reasons that weren't there at the previous evaluation. Always updates what's known,
    /// so it can be called whether or not notifications are switched on.
    mutating func newProblems(in health: Health) -> [HealthReason] {
        let current = health.reasons.filter(Self.isNotifiable)
        let previous = known
        known = Set(current.map(\.id))
        guard let previous else { return [] }
        return current.filter { !previous.contains($0.id) }
    }
}

/// What a problem notification says.
nonisolated struct ProblemNotification: Equatable, Sendable {
    var title: String
    var body: String
    var identifier: String

    /// How many reasons are spelled out before "and N more".
    static let visibleReasons = 3

    static func make(hostname: String?, reasons: [HealthReason]) -> ProblemNotification {
        let name = (hostname?.isEmpty == false ? hostname : nil) ?? "your server"
        let title = reasons.count == 1 ? "Problem on \(name)" : "\(reasons.count) problems on \(name)"
        var lines = reasons.prefix(visibleReasons).map(\.message)
        if reasons.count > visibleReasons { lines.append("and \(reasons.count - visibleReasons) more") }
        return ProblemNotification(
            title: title,
            body: lines.joined(separator: "\n"),
            identifier: "menuraid.problem." + reasons.map(\.id).sorted().joined(separator: "|")
        )
    }

    /// Sent by "Send a test notification" so you can see what they look like.
    static let test = ProblemNotification(
        title: "Problem on Tower (test)",
        body: "disk1: disabled\nThis is what a MenuRaid notification looks like.",
        identifier: "menuraid.test"
    )
}

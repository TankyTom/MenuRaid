import Foundation

nonisolated enum HealthLevel: Int, Comparable, Codable, Sendable {
    case green, amber, red

    static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where to go to look into a health reason.
nonisolated enum ReasonLink: Equatable, Sendable {
    /// A page of the Unraid webGUI.
    case page(LinkBuilder.Page)
    /// MenuRaid's own connection settings.
    case connectionSettings
}

nonisolated struct HealthReason: Equatable, Sendable {
    var level: HealthLevel
    var message: String
    var link: ReasonLink?
    /// Identifies the underlying problem, unlike `message`, which can change while the problem stays the same
    /// ("disk1: 5 errors" becomes "disk1: 6 errors"). Used to tell a new problem from a continuing one.
    var id: String

    init(level: HealthLevel, message: String, link: ReasonLink? = nil, id: String? = nil) {
        self.level = level
        self.message = message
        self.link = link
        self.id = id ?? message
    }
}

nonisolated struct Health: Equatable, Sendable {
    var level: HealthLevel
    /// Why the level isn't green, most severe first. Empty when everything is fine.
    var reasons: [HealthReason]
}

/// Turns a snapshot plus thresholds into a health level with reasons. Pure, so it's easy to test.
nonisolated enum HealthEvaluator {
    /// - Parameters:
    ///   - isStale: the data is older than 3x the refresh interval.
    ///   - isUnreachable: the last refresh failed on every section / route.
    static func evaluate(
        snapshot: ServerSnapshot?,
        thresholds: Thresholds,
        isStale: Bool,
        isUnreachable: Bool
    ) -> Health {
        var reasons: [HealthReason] = []

        if isUnreachable {
            reasons.append(HealthReason(level: .red, message: "Server unreachable", link: .connectionSettings, id: "server.unreachable"))
        }

        if let array = snapshot?.array {
            if !array.isStarted {
                reasons.append(HealthReason(level: .red, message: "Array is not started (\(array.state?.capitalized ?? "unknown"))", link: .page(.main), id: "array.notStarted"))
            }

            for disk in array.disks {
                // DISK_NP is an empty slot, not a failure. Disabled, missing and invalid disks are.
                if disk.isFailed {
                    reasons.append(HealthReason(level: .red, message: "\(disk.name): \(disk.statusDescription.lowercased())", link: .page(.main), id: "disk.\(disk.name).failed"))
                }
                if let errors = disk.numErrors, errors > 0 {
                    reasons.append(HealthReason(level: .red, message: "\(disk.name): \(errors) errors", link: .page(.main), id: "disk.\(disk.name).errors"))
                }
                // Spun-down disks report no temperature; they are skipped rather than read as 0.
                if let temp = disk.tempC {
                    let degrees = Int(temp.rounded())
                    if temp >= thresholds.critical(rotational: disk.rotational) {
                        reasons.append(HealthReason(level: .red, message: "\(disk.name): \(degrees)°C (critical)", link: .page(.main), id: "disk.\(disk.name).temp.critical"))
                    } else if temp >= thresholds.warn(rotational: disk.rotational) {
                        reasons.append(HealthReason(level: .amber, message: "\(disk.name): \(degrees)°C (warm)", link: .page(.main), id: "disk.\(disk.name).temp.warm"))
                    }
                }
            }

            if let check = array.parityCheck, check.running {
                let progress = check.progress.map { " (\(Int($0.rounded()))%)" } ?? ""
                let verb = check.paused ? "paused" : "running"
                reasons.append(HealthReason(level: .amber, message: "Parity check \(verb)\(progress)", link: .page(.main), id: "array.parity"))
            }
        }

        if let unread = snapshot?.notifications, unread.alert > 0 || unread.warning > 0 {
            var parts: [String] = []
            if unread.alert > 0 { parts.append("\(unread.alert) alert\(unread.alert == 1 ? "" : "s")") }
            if unread.warning > 0 { parts.append("\(unread.warning) warning\(unread.warning == 1 ? "" : "s")") }
            reasons.append(HealthReason(level: .amber, message: parts.joined(separator: ", ") + " unread", link: .page(.notifications), id: "notifications.unread"))
        }

        if isStale {
            reasons.append(HealthReason(level: .amber, message: "Data is out of date", id: "data.stale"))
        }

        // Stable sort: most severe first, otherwise keep discovery order.
        let sorted = reasons.enumerated()
            .sorted { ($0.element.level, $1.offset) > ($1.element.level, $0.offset) }
            .map(\.element)
        return Health(level: sorted.first?.level ?? .green, reasons: sorted)
    }
}

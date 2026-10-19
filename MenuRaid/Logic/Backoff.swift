import Foundation

/// Retry delays after consecutive failed refreshes: 5, 15, 30, 60 seconds, then the normal interval.
nonisolated enum Backoff {
    static let steps: [TimeInterval] = [5, 15, 30, 60]

    static func delay(consecutiveFailures: Int, normal: TimeInterval) -> TimeInterval {
        guard consecutiveFailures > 0, consecutiveFailures <= steps.count else { return normal }
        return steps[consecutiveFailures - 1]
    }
}

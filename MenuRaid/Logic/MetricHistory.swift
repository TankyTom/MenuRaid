import Foundation

/// One reading of CPU or RAM, with the time it was taken.
nonisolated struct MetricSample: Equatable, Sendable {
    var date: Date
    var value: Double
}

/// The recent readings behind a sparkline, kept in memory only. Samples carry their time, so the chart's horizontal
/// axis is real time even though they arrive every 5 s while the panel is open and every 30 s otherwise.
nonisolated struct MetricHistory: Equatable, Sendable {
    /// How far back the chart looks.
    static let window: TimeInterval = 10 * 60
    /// A hard cap, in case something feeds samples very quickly.
    static let maxSamples = 400

    private(set) var samples: [MetricSample] = []

    var isEmpty: Bool { samples.isEmpty }
    var values: [Double] { samples.map(\.value) }

    mutating func append(_ value: Double, at date: Date = .now) {
        // Ignore a sample that arrives out of order (a clock change): the chart needs ascending time.
        if let last = samples.last, date < last.date { return }
        samples.append(MetricSample(date: date, value: value))
        let oldestKept = date.addingTimeInterval(-Self.window)
        samples.removeAll { $0.date < oldestKept }
        if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
    }

    mutating func removeAll() { samples = [] }
}

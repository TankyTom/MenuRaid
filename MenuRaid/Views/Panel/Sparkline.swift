import SwiftUI
import Charts

/// Small filled line chart of recent readings (percent). The horizontal axis is real time, so a gap in the data
/// shows as a gap. History lives in memory only (see `MetricHistory`).
struct Sparkline: View {
    let samples: [MetricSample]
    var color: Color = .accentColor
    /// Smallest top of the scale. Low-usage series (a few % CPU) would otherwise be a flat line.
    var minimumCeiling: Double = 100

    private var ceiling: Double {
        let peak = samples.map(\.value).max() ?? 0
        return min(100, max(minimumCeiling, (peak * 1.25).rounded(.up)))
    }

    /// From the oldest to the newest sample, so the line always fills the width.
    private var timeRange: ClosedRange<Date> {
        guard let first = samples.first?.date, let last = samples.last?.date, first < last else {
            let now = Date.now
            return now.addingTimeInterval(-1)...now
        }
        return first...last
    }

    var body: some View {
        Chart {
            ForEach(samples, id: \.date) { sample in
                AreaMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...ceiling)
        .chartXScale(domain: timeRange)
        .overlay {
            if samples.count < 2 {
                Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

import SwiftUI
import Charts

/// Small filled line chart of the last ~60 samples (percent). History lives in memory only.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    /// Smallest top of the scale. Low-usage series (a few % CPU) would otherwise be a flat line.
    var minimumCeiling: Double = 100

    private var ceiling: Double {
        let peak = values.max() ?? 0
        return min(100, max(minimumCeiling, (peak * 1.25).rounded(.up)))
    }

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("Sample", index), y: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Sample", index), y: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...ceiling)
        .chartXScale(domain: 0...max(1, values.count - 1))
        .overlay {
            if values.count < 2 {
                Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// CPU and RAM as big numbers, each with a sparkline of recent samples.
struct SystemCard: View {
    @Environment(ServerStore.self) private var store

    var body: some View {
        let overview = store.snapshot?.overview
        Card("System", trailing: {
            if let uptime = Format.uptime(overview?.uptime()) {
                Text("Up \(uptime)").font(.caption).foregroundStyle(.secondary)
            }
        }) {
            if let message = store.sectionErrors[.overview] {
                SectionErrorBanner(section: .overview, message: message)
            }
            if let overview {
                metric(
                    "CPU", value: overview.cpuPercent, history: store.cpuHistory,
                    detail: cpuDetail(overview), color: Color.accentColor, minimumCeiling: 25
                )
                Divider().opacity(0.5)
                metric(
                    "RAM", value: overview.memoryPercent, history: store.ramHistory,
                    detail: overview.memoryTotalBytes.map { "\(Format.memory(bytes: $0)) installed" },
                    color: .purple
                )
            } else if store.sectionErrors[.overview] == nil {
                LoadingRow()
            }
        }
    }

    private func cpuDetail(_ overview: ServerOverview) -> String? {
        [overview.cpuBrand, overview.cpuThreads.map { "\($0) threads" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func metric(_ name: String, value: Double?, history: [Double], detail: String?, color: Color, minimumCeiling: Double = 100) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).foregroundStyle(.secondary)
                Text(Format.percent(value))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Sparkline(values: history, color: color, minimumCeiling: minimumCeiling)
                .frame(height: 52)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(Format.percent(value))")
    }
}

#if DEBUG
#Preview("System") {
    SystemCard().padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.live))
}
#endif

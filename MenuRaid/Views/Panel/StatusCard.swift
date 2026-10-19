import SwiftUI
import AppKit

/// Hero card: overall health in big type, a one-line summary, the reasons behind it (each a link to where
/// you can look into it), shortcuts to the logs, and a few status chips.
struct StatusCard: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    private static let visibleReasons = 5

    var body: some View {
        let level = store.health?.level
        Card("Status", tint: level == .green || level == nil ? nil : Palette.color(for: level), spacing: 8, trailing: {
            if let health = store.health { shortcuts(health) }
        }) {
            if let message = store.setupMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button("Open Settings") { showSettings() }
            } else if let health = store.health {
                headline(health)
                reasons(health)
                connectionNotes
                chips
            } else {
                LoadingRow()
            }
        }
    }

    // MARK: Headline

    private func headline(_ health: Health) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LevelIcon(level: health.level, size: 21)
            Text(title(for: health.level))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.color(for: health.level))
            Spacer(minLength: 4)
            // One reason explains itself, so the count is only worth showing for several.
            if health.reasons.count > 1, let summary = Self.summary(for: health) {
                // Neutral, not red: red-on-red is hard to read.
                Text(summary).font(.caption).foregroundStyle(.primary.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "2 problems · 1 to check", or nil when there's nothing to report.
    static func summary(for health: Health) -> String? {
        let problems = health.reasons.filter { $0.level == .red }.count
        let warnings = health.reasons.filter { $0.level == .amber }.count
        var parts: [String] = []
        if problems > 0 { parts.append("\(problems) problem\(problems == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) to check") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Reasons

    @ViewBuilder
    private func reasons(_ health: Health) -> some View {
        if !health.reasons.isEmpty {
            VStack(spacing: 0) {
                let shown = Array(health.reasons.prefix(Self.visibleReasons))
                ForEach(Array(shown.enumerated()), id: \.offset) { index, reason in
                    ReasonRow(reason: reason, onOpen: open)
                    if index < shown.count - 1 || health.reasons.count > Self.visibleReasons {
                        Divider().opacity(0.4)
                    }
                }
                if health.reasons.count > Self.visibleReasons {
                    Text("+ \(health.reasons.count - Self.visibleReasons) more")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                }
            }
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func open(_ link: ReasonLink) {
        switch link {
        case .page(let page): store.open(page)
        case .connectionSettings: showSettings()
        }
    }

    /// Quick links for digging in, as small icons in the card's title row. Only when there's something to look into.
    @ViewBuilder
    private func shortcuts(_ health: Health) -> some View {
        if !health.reasons.isEmpty, store.linkBase != nil {
            HStack(spacing: 10) {
                ShortcutIcon(page: .systemLog, symbol: "doc.text.magnifyingglass") { store.open(.systemLog) }
                ShortcutIcon(page: .notifications, symbol: "bell") { store.open(.notifications) }
            }
        }
    }

    // MARK: Connection problems

    private func showSettings() {
        // An agent app's windows open behind others unless we activate first.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    /// Route, key and certificate problems, in plain language.
    @ViewBuilder
    private var connectionNotes: some View {
        if store.authFailed {
            VStack(alignment: .leading, spacing: 4) {
                Label("The server rejected your API key. Check it in Settings → Connection (it needs at least the Viewer role).", systemImage: "key.slash")
                    .font(.caption).foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { showSettings() }.font(.caption)
            }
        } else if store.isUnreachable, store.routeNote == nil, store.certificateIssue == nil {
            Label("Can't reach your server. MenuRaid keeps retrying.", systemImage: "wifi.exclamationmark")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let issue = store.certificateIssue {
            Label("\(issue.localizedDescription). Open Settings → Connection to review it.", systemImage: "lock.trianglebadge.exclamationmark.fill")
                .font(.caption).foregroundStyle(Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let note = store.routeNote {
            Label(note, systemImage: "network.slash")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Only the unusual states: the Array card already shows the array's state.
    @ViewBuilder
    private var chips: some View {
        if store.isShowingCache {
            Chip(text: "Saved data", color: Palette.warn)
        } else if store.isUnreachable {
            Chip(text: "Offline", color: Palette.bad)
        }
    }

    private func title(for level: HealthLevel) -> String {
        switch level {
        case .green: "All good"
        case .amber: "Needs attention"
        case .red: "Problem"
        }
    }
}

/// One reason. With a destination it's a button (whole row) with an arrow; without, plain text.
private struct ReasonRow: View {
    let reason: HealthReason
    let onOpen: (ReasonLink) -> Void
    @State private var isHovering = false

    var body: some View {
        if let link = reason.link {
            Button { onOpen(link) } label: { content(link: link) }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help(helpText(for: link))
                .accessibilityHint(helpText(for: link))
        } else {
            content(link: nil)
        }
    }

    private func content(link: ReasonLink?) -> some View {
        HStack(spacing: 10) {
            LevelIcon(level: reason.level, size: 15)
            Text(reason.message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0.6)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(.primary.opacity(isHovering && link != nil ? 0.08 : 0))
        .contentShape(Rectangle())
    }

    private func helpText(for link: ReasonLink) -> String {
        switch link {
        case .page(let page): "Open the \(page.title) in Unraid"
        case .connectionSettings: "Open connection settings"
        }
    }
}

/// A small icon button that opens a page of the Unraid webGUI; the name is in the tooltip.
private struct ShortcutIcon: View {
    let page: LinkBuilder.Page
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open the \(page.title) in Unraid")
            .accessibilityLabel("Open the \(page.title)")
    }
}

#if DEBUG
#Preview("Problem (live data)") {
    StatusCard().padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.live))
}
#Preview("All good") {
    StatusCard().padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.healthy))
}
#Preview("Needs attention") {
    StatusCard().padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.parityRunning))
}
#endif

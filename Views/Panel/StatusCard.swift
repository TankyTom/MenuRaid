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
        Card("Status", tint: level == .green || level == nil ? nil : Palette.color(for: level)) {
            if let message = store.setupMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button("Open Settings") { showSettings() }
            } else if let health = store.health {
                headline(health)
                reasons(health)
                connectionNotes
                shortcuts(health)
                chips
            } else {
                LoadingRow()
            }
        }
    }

    // MARK: Headline

    private func headline(_ health: Health) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: StatusGlyph.symbol(for: health.level))
                    .font(.system(size: 26, weight: .semibold))
                Text(title(for: health.level))
                    .font(.system(size: 30, weight: .bold))
            }
            .foregroundStyle(Palette.color(for: health.level))

            if let summary = Self.summary(for: health) {
                Text(summary).font(.callout).foregroundStyle(.secondary)
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

    /// Quick links for digging in: only shown when there's something to look into.
    @ViewBuilder
    private func shortcuts(_ health: Health) -> some View {
        if !health.reasons.isEmpty, store.activeBase != nil {
            HStack(spacing: 8) {
                ShortcutButton(page: .systemLog, symbol: "doc.text.magnifyingglass") { store.open(.systemLog) }
                ShortcutButton(page: .notifications, symbol: "bell") { store.open(.notifications) }
                ShortcutButton(page: .main, symbol: "externaldrive") { store.open(.main) }
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

    private var chips: some View {
        HStack(spacing: 6) {
            if let array = store.snapshot?.array {
                Chip(text: "Array · \(array.state?.capitalized ?? "Unknown")", color: array.isStarted ? Palette.ok : Palette.bad)
            }
            if store.isShowingCache {
                Chip(text: "Saved data", color: Palette.warn)
            } else if store.isUnreachable {
                Chip(text: "Offline", color: Palette.bad)
            }
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
            Image(systemName: reason.level == .red ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.color(for: reason.level))
                .frame(width: 18)
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
        .padding(.vertical, 7)
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

/// A small pill button that opens a page of the Unraid webGUI.
private struct ShortcutButton: View {
    let page: LinkBuilder.Page
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(page.title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Open the \(page.title) in Unraid")
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

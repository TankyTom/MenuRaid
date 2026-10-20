import SwiftUI
import AppKit

/// The menu bar panel: header, scrolling cards, footer. 360 pt wide; up to 3/4 of the screen tall, then scrolls.
struct PanelView: View {
    @Environment(ServerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var contentHeight: CGFloat = 400
    @State private var headerHeight: CGFloat = 60
    @State private var footerHeight: CGFloat = 45

    /// The panel may grow to this share of the screen's usable height.
    private static let screenShare: CGFloat = 0.75

    private var maxScrollHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(300, screenHeight * Self.screenShare - headerHeight - footerHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            ScrollView {
                PanelCards()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(contentHeight, maxScrollHeight))

            Divider()
            PanelFooter()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .frame(width: 360)
        .background(WindowAppearance(appearance: settings.effectiveAppearance.nsAppearance))
        .preferredColorScheme(settings.effectiveAppearance.colorScheme)
        .onAppear { store.setPanelOpen(true) }
        .onDisappear { store.setPanelOpen(false) }
    }
}

/// The stack of section cards (kept separate from the scroll view so it can be rendered on its own).
struct PanelCards: View {
    @Environment(ServerStore.self) private var store
    @State private var showLastKnown = false

    var body: some View {
        VStack(spacing: 12) {
            if store.showHTTPWarning { HTTPWarningCard() }

            if store.isDisconnected {
                // Nothing is getting through: say so once, clearly, instead of five identical error cards.
                DisconnectedCard()
                if store.snapshot != nil { lastKnownData }
            } else {
                Group {
                    StatusCard()
                    dataCards
                }
                // Old data (saved from last launch, stale, or offline) is greyed so it isn't mistaken for live.
                .opacity(store.isDataDimmed ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.2), value: store.isDataDimmed)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var dataCards: some View {
        SystemCard()
        ArrayCard()
        DisksCard()
        DockerCard()
        VMsCard()
    }

    /// The last data MenuRaid got, kept out of the way (greyed) until asked for.
    @ViewBuilder
    private var lastKnownData: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showLastKnown.toggle() }
        } label: {
            HStack {
                Image(systemName: showLastKnown ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                Text(showLastKnown ? "Hide last known data" : "Show last known data")
                if let last = store.lastSuccess {
                    Text("· as of \(last.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)

        if showLastKnown {
            VStack(spacing: 12) { dataCards }
                .opacity(0.55)
        }
    }
}

/// One-time notice: a plain http:// LAN address sends the API key unencrypted. Dismissible.
struct HTTPWarningCard: View {
    @Environment(ServerStore.self) private var store

    var body: some View {
        Card("Security", tint: Palette.warn) {
            Label {
                Text("Your LAN address uses plain http://, so your API key and server data cross your network unencrypted. Consider enabling HTTPS in Unraid (Settings → Management Access).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.open.trianglebadge.exclamationmark.fill").foregroundStyle(Palette.warn)
            }
            Button("Dismiss") { store.dismissHTTPWarning() }
                .help("Hide this notice. It won't appear again.")
        }
    }
}

struct PanelHeader: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let overview = store.snapshot?.overview
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.accentIcon)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(overview?.hostname ?? "MenuRaid").font(.headline)
                HStack(spacing: 6) {
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    if let update = store.osUpdate { OSUpdateBadge(update: update) }
                }
            }

            Spacer()

            if store.linkBase != nil {
                headerButton("terminal", help: "Open the Unraid terminal") { store.open(.terminal) }
                headerButton("folder", help: "Open the Unraid file manager") { store.open(.fileManager) }
            }

            // The house (LAN) or globe (remote) shows the route in use, and opens the Unraid dashboard on it.
            if let route = store.activeRoute {
                headerButton(
                    route.isLAN ? "house.fill" : "globe",
                    help: "Open the Unraid dashboard (\(route.isLAN ? "LAN" : "remote"): \(route.address))",
                    label: route.isLAN ? "Open dashboard over LAN" : "Open dashboard over remote connection"
                ) { store.open(.dashboard) }
            }

            refreshControl
        }
    }

    /// The refresh button, which turns into the progress spinner while a refresh runs. Both share one fixed-size
    /// slot, so the header icons never shift when loading starts or stops.
    private var refreshControl: some View {
        ZStack {
            Button { store.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(store.isRefreshing ? 0 : 1)
            .disabled(store.isRefreshing)

            ProgressView()
                .controlSize(.small)
                .opacity(store.isRefreshing ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .animation(.easeInOut(duration: 0.15), value: store.isRefreshing)
        .help(store.isRefreshing ? "Refreshing…" : "Refresh now")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.isRefreshing ? "Refreshing" : "Refresh")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !store.isRefreshing { store.refreshNow() } }
    }

    private func headerButton(_ symbol: String, help: String, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(label ?? help)
    }

    private var subtitle: String? {
        guard let overview = store.snapshot?.overview else { return nil }
        let version = overview.unraidVersion.map { "Unraid \($0)" } ?? overview.release
        return version
    }
}

/// A small "↑ 7.3.3" next to the Unraid version when a newer stable release exists. Click for the update page or notes.
struct OSUpdateBadge: View {
    @Environment(ServerStore.self) private var store
    let update: OSUpdate

    var body: some View {
        Menu {
            Button("Open the Update OS page in Unraid") { store.open(.updateOS) }
            if let notes = update.latest.notesURL {
                Button("Read the release notes for \(update.latest.version)") { NSWorkspace.shared.open(notes) }
            }
        } label: {
            Label(update.latest.version, systemImage: "arrow.up.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accentIcon)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Unraid \(update.latest.version) is available (this server runs \(update.current)).")
        .accessibilityLabel("Unraid \(update.latest.version) is available")
    }
}

struct PanelFooter: View {
    @Environment(ServerStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 14) {
            freshness
            Spacer()
            notifications
            iconButton(colorScheme == .dark ? "sun.max" : "moon", help: colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode") {
                settings.appearanceOverride = colorScheme == .dark ? .light : .dark
            }
            iconButton("globe", help: "Open Unraid webGUI") { store.open(.dashboard) }
            iconButton("gearshape", help: "Settings") {
                // An agent app's windows open behind others unless we activate first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            iconButton("power", help: "Quit MenuRaid") { NSApp.terminate(nil) }
        }
        .font(.system(size: 14))
    }

    private var freshness: some View {
        HStack(spacing: 6) {
            StatusDot(color: freshnessColor)
            if let last = store.lastSuccess {
                if store.isShowingCache {
                    Text("As of \(last.formatted(date: .omitted, time: .shortened))")
                } else {
                    // Ticks every second so the age keeps counting while the panel is open.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Updated \(Format.age(of: last, now: context.date))")
                    }
                }
            } else {
                Text(store.setupMessage == nil ? "Connecting…" : "Not set up")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var freshnessColor: Color {
        if store.isUnreachable { return Palette.bad }
        if store.isShowingCache || store.isStale { return Palette.warn }
        return store.lastSuccess == nil ? Palette.idle : Palette.ok
    }

    @ViewBuilder
    private var notifications: some View {
        if let unread = store.snapshot?.notifications, unread.total > 0 {
            Button { store.open(.dashboard) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                    Text("\(unread.total)").font(.callout.weight(.medium)).monospacedDigit()
                }
                .foregroundStyle(unread.alert > 0 ? Palette.bad : unread.warning > 0 ? Palette.warn : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("\(unread.alert) alerts, \(unread.warning) warnings, \(unread.info) info unread")
            .accessibilityLabel("\(unread.total) unread notifications")
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(help)
    }
}

#if DEBUG
#Preview("Live data (disk disabled)") {
    PanelView()
        .environment(PreviewFixtures.store(PreviewFixtures.live))
        .environment(PreviewFixtures.settings)
}
#Preview("Healthy") {
    PanelView()
        .environment(PreviewFixtures.store(PreviewFixtures.healthy))
        .environment(PreviewFixtures.settings)
}
#Preview("Docker failed, rest fine") {
    PanelView()
        .environment(PreviewFixtures.store(PreviewFixtures.healthy, errors: [.docker: "Couldn't reach the server (The request timed out.)"]))
        .environment(PreviewFixtures.settings)
}
#Preview("Saved data from last launch") {
    PanelView()
        .environment(PreviewFixtures.store(PreviewFixtures.healthy, fromCache: true))
        .environment(PreviewFixtures.settings)
}
#endif

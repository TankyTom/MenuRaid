import SwiftUI
import AppKit

/// Menu bar item: the server icon, with a badge on its corner when something needs attention, plus one short value.
/// The badge's shape differs by severity (! or x), so it isn't colour alone.
struct MenuBarLabel: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            StatusGlyph.serverMenuBarImage(for: store.health?.level, dimmed: store.isShowingCache, isDark: colorScheme == .dark)
            if let text = store.menuBarText {
                Text(text).monospacedDigit()
            }
        }
        .help(tooltip)
        .task {
            await store.promptForSetupIfNeeded {
                // An agent app's windows open behind others unless we activate first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }

    private var tooltip: String {
        guard let health = store.health else { return store.setupMessage ?? "MenuRaid: waiting for data" }
        if health.reasons.isEmpty { return "All good" }
        return health.reasons.prefix(5).map(\.message).joined(separator: "\n")
    }
}

enum StatusGlyph {
    static func symbol(for level: HealthLevel?) -> String {
        switch level {
        case .green: "checkmark.circle.fill"
        case .amber: "exclamationmark.triangle.fill"
        case .red: "xmark.octagon.fill"
        case nil: "questionmark.circle"
        }
    }

    static func color(for level: HealthLevel?) -> NSColor {
        switch level {
        case .green: .systemGreen
        case .amber: .systemOrange
        case .red: .systemRed
        case nil: .systemGray
        }
    }

    /// The menu bar icon: the server (drive) icon, plain when all is well. Something wrong adds a small badge
    /// on the corner: an orange "!" for "needs attention", a red "x" for "problem".
    ///
    /// The menu bar tints plain SF Symbols to match its appearance, which would erase the badge's colour, so the
    /// icon is drawn into a non-template image. That means the base colour must be chosen to suit the bar.
    @MainActor
    static func serverMenuBarImage(for level: HealthLevel?, dimmed: Bool, isDark: Bool) -> Image {
        let badge = StatusBadge(level: level)
        let base: Color = isDark ? .white : .black
        let view = ZStack(alignment: .bottomTrailing) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(base)
                .opacity(dimmed ? 0.55 : 1)   // old data greys the icon, but a problem badge stays fully visible
                .padding(.trailing, 4)
                .padding(.bottom, 1)
            if let badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 11)
                    .background(Color(nsColor: badge.color), in: Circle())
                    .overlay(Circle().strokeBorder(isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.6), lineWidth: 0.75))
            }
        }
        // Extra room so the badge's circle isn't clipped at the image edge.
        .frame(width: 25, height: 19, alignment: .bottomTrailing)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return Image(systemName: "externaldrive.fill") }
        image.isTemplate = false
        return Image(nsImage: image)
    }
}

/// The corner mark on the menu bar icon. Nothing when all is well (or when there's no data yet).
enum StatusBadge: Equatable {
    case attention, problem

    init?(level: HealthLevel?) {
        switch level {
        case .amber?: self = .attention
        case .red?: self = .problem
        case .green?, nil: return nil
        }
    }

    var symbol: String {
        switch self {
        case .attention: "exclamationmark"
        case .problem: "xmark"
        }
    }

    var color: NSColor {
        switch self {
        case .attention: .systemOrange
        case .problem: .systemRed
        }
    }
}

#Preview {
    MenuBarLabel()
        .padding()
        .environment(ServerStore(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard)))
}

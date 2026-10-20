import SwiftUI
import AppKit

// Shared building blocks for the panel: rounded cards with letter-spaced titles, chips, bars and number formats.

/// A rounded card with an uppercase section title. `tint` colours the card (e.g. red when unhealthy).
struct Card<Trailing: View, Content: View>: View {
    let title: String
    var tint: Color?
    /// Colour of the title; the usual secondary grey when nil.
    var titleColor: Color?
    var spacing: CGFloat = 10
    let trailing: Trailing
    let content: Content

    init(
        _ title: String,
        tint: Color? = nil,
        titleColor: Color? = nil,
        spacing: CGFloat = 10,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.tint = tint
        self.titleColor = titleColor
        self.spacing = spacing
        self.trailing = trailing()
        self.content = content()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let isDark = colorScheme == .dark
        VStack(alignment: .leading, spacing: spacing) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(titleColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((tint ?? .primary).opacity(tint == nil ? 0.05 : (isDark ? 0.24 : 0.14)), in: shape)
        // A dark base under a tint keeps it a clean red/amber instead of blending into the grey material (brown).
        .background(Color.black.opacity(tint != nil && isDark ? 0.30 : 0), in: shape)
        .overlay(shape.strokeBorder((tint ?? .primary).opacity(tint == nil ? 0.10 : (isDark ? 0.55 : 0.30))))
    }
}

extension Card where Trailing == EmptyView {
    init(_ title: String, tint: Color? = nil, titleColor: Color? = nil, spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.init(title, tint: tint, titleColor: titleColor, spacing: spacing, trailing: { EmptyView() }, content: content)
    }
}

/// Inline error for one section, so the rest of the panel keeps working.
struct SectionErrorBanner: View {
    let section: PanelSection
    let message: String

    var body: some View {
        Label("\(section.title): couldn't load. \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…").font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Small pill with a dot and text, like the "ASX · Open" chip.
struct Chip: View {
    let text: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: color, size: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.primary.opacity(0.08), in: Capsule())
    }
}

/// Thin horizontal bar showing a 0...1 fraction.
struct UsageBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

extension Color {
    /// A colour that follows the appearance it's drawn in (including the panel's light/dark switch).
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum Palette {
    // The system colours are fine on light backgrounds; on dark ones they need to be brighter to stay readable.
    static let ok = Color.adaptive(light: .systemGreen, dark: NSColor(srgbRed: 0.31, green: 0.86, blue: 0.47, alpha: 1))
    static let warn = Color.adaptive(light: .systemOrange, dark: NSColor(srgbRed: 1.00, green: 0.75, blue: 0.27, alpha: 1))
    static let bad = Color.adaptive(light: .systemRed, dark: NSColor(srgbRed: 1.00, green: 0.42, blue: 0.42, alpha: 1))
    static let idle = Color(nsColor: .systemGray)
    /// The header's drive icon: readable blue on its tile in both appearances.
    static let accentIcon = Color.adaptive(light: .controlAccentColor, dark: NSColor(srgbRed: 0.55, green: 0.76, blue: 1.0, alpha: 1))

    static func color(for level: HealthLevel?) -> Color {
        switch level {
        case .green?: ok
        case .amber?: warn
        case .red?: bad
        case nil: idle
        }
    }

    /// Bars turn amber, then red as a disk fills up.
    static func fill(_ fraction: Double) -> Color {
        fraction >= 0.95 ? bad : fraction >= 0.85 ? warn : .accentColor
    }
}

/// A solid status icon: a white mark on a coloured shape. The built-in `.fill` symbols cut the mark out of the
/// shape, so it shows whatever is behind it, which is muddy on a tinted card in dark mode.
struct LevelIcon: View {
    let level: HealthLevel
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            switch level {
            case .red:
                Image(systemName: "octagon.fill").foregroundStyle(Palette.bad)
                Image(systemName: "xmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.white)
            case .amber:
                Image(systemName: "triangle.fill").foregroundStyle(Palette.warn)
                Image(systemName: "exclamationmark").font(.system(size: size * 0.46, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.78)).offset(y: size * 0.07)
            case .green:
                Image(systemName: "circle.fill").foregroundStyle(Palette.ok)
                Image(systemName: "checkmark").font(.system(size: size * 0.44, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
        }
        .font(.system(size: size))
        .frame(width: size * 1.1, height: size * 1.1)
        .accessibilityElement()
        .accessibilityLabel(level == .red ? "Problem" : level == .amber ? "Needs attention" : "OK")
    }
}

enum Format {
    /// Unraid reports sizes in KiB; show them in decimal units like the Unraid UI does.
    static func bytes(kb: Double?) -> String {
        guard let kb else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(kb * 1024), countStyle: .decimal)
    }

    static func memory(bytes: Double?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    static func fraction(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    /// "64d 3h", "5h 12m", "8m".
    static func uptime(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        let total = Int(seconds)
        let days = total / 86_400, hours = total % 86_400 / 3_600, minutes = total % 3_600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        default: return "\(seconds / 3600)h ago"
        }
    }
}

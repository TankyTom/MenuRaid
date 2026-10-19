import SwiftUI
import AppKit

/// Shown instead of the data cards when nothing is getting through: what went wrong in plain language,
/// the server address(es) being tried (each opens in your browser), and what to do about it.
struct DisconnectedCard: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let problem = store.connectionProblem ?? .unreachable
        Card("Connection", tint: Palette.bad) {
            HStack(spacing: 10) {
                Image(systemName: problem.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 30)
                Text(problem.title)
                    .font(.system(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.bad)
            .accessibilityElement(children: .combine)

            Text(problem.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !store.serverAddresses.isEmpty {
                VStack(spacing: 0) {
                    let addresses = store.serverAddresses
                    ForEach(Array(addresses.enumerated()), id: \.element.id) { index, address in
                        AddressRow(address: address)
                        if index < addresses.count - 1 { Divider().opacity(0.4) }
                    }
                }
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Button { store.retryNow() } label: {
                    Label("Retry now", systemImage: "arrow.clockwise")
                }
                Button {
                    // An agent app's windows open behind others unless we activate first.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Label(problem.needsSettings ? "Open Settings" : "Test connection…", systemImage: "gearshape")
                }
                if store.isRefreshing { ProgressView().controlSize(.small) }
            }

            if let detail = store.connectionDetail, !detail.isEmpty {
                Text("Details: \(detail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One configured address. Clicking opens it in the browser, which is the quickest way to tell whether
/// the server itself is down or only MenuRaid can't reach it.
private struct AddressRow: View {
    let address: ServerAddress
    @State private var isHovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(address.url) } label: {
            HStack(spacing: 10) {
                Image(systemName: address.kind == .lan ? "house.fill" : "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(address.url.absoluteString)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(address.kind == .lan ? "LAN" : "Remote")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if address.isInUse {
                    Text("Last tried").font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0.6)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(.primary.opacity(isHovering ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open \(address.url.absoluteString) in your browser")
        .accessibilityLabel("Open \(address.kind == .lan ? "LAN" : "remote") address \(address.url.absoluteString)")
    }
}

#if DEBUG
#Preview("Unreachable") {
    DisconnectedCard().padding().frame(width: 360)
        .environment(PreviewFixtures.disconnectedStore(.unreachable))
}
#Preview("Key rejected") {
    DisconnectedCard().padding().frame(width: 360)
        .environment(PreviewFixtures.disconnectedStore(.authRejected))
}
#Preview("Blocked by macOS") {
    DisconnectedCard().padding().frame(width: 360)
        .environment(PreviewFixtures.disconnectedStore(.insecureBlocked))
}
#endif

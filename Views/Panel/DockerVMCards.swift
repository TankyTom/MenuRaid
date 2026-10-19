import SwiftUI
import AppKit

/// Docker containers, running first, then stopped. Long lists are shortened with a "Show all" toggle.
/// Clicking a row opens the container's web UI in the default browser; the header link opens Unraid's Docker page.
struct DockerCard: View {
    @Environment(ServerStore.self) private var store
    @State private var showAll = false

    private static let collapsedCount = 8

    var body: some View {
        let containers = Self.sorted(store.snapshot?.containers ?? [])
        let running = containers.filter(\.state.isRunning).count
        Card("Docker", trailing: {
            HStack(spacing: 8) {
                if !containers.isEmpty {
                    Text("\(running) of \(containers.count) running").font(.caption).foregroundStyle(.secondary)
                }
                PageLinkButton(help: "Open the Docker page in Unraid") { store.open(.docker) }
            }
        }) {
            if let message = store.sectionErrors[.docker] {
                SectionErrorBanner(section: .docker, message: message)
            }
            if store.snapshot?.containers == nil {
                if store.sectionErrors[.docker] == nil { LoadingRow() }
            } else if containers.isEmpty {
                Text("No containers").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(showAll ? containers : Array(containers.prefix(Self.collapsedCount))) { container in
                        ContainerRow(container: container, link: store.containerLink(for: container))
                    }
                }
                if containers.count > Self.collapsedCount {
                    Button(showAll ? "Show fewer" : "Show all \(containers.count)") { showAll.toggle() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// Running containers first, each group alphabetical.
    static func sorted(_ containers: [DockerContainer]) -> [DockerContainer] {
        containers.sorted {
            let a = ($0.state.isRunning ? 0 : 1, $0.name.lowercased())
            let b = ($1.state.isRunning ? 0 : 1, $1.name.lowercased())
            return a < b
        }
    }
}

/// A container row. With a link it's one big button that opens the web UI; without one the row stays
/// readable but its "open" arrow is dimmed and a tooltip explains why.
struct ContainerRow: View {
    let container: DockerContainer
    let link: ContainerLink
    @State private var isHovering = false

    var body: some View {
        if let url = link.url {
            Button { NSWorkspace.shared.open(url) } label: { content }
                .buttonStyle(.plain)
                .help("Open \(url.absoluteString)")
                .accessibilityHint("Opens the web UI in your browser")
        } else {
            content.help(link.unavailableMessage ?? "")
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            StatusDot(color: dotColor)
            Text(container.name)
                .font(.callout)
                .foregroundStyle(container.state.isRunning ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let note {
                Text(note.text).font(.caption).foregroundStyle(note.color).lineLimit(1)
            }
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(link.url == nil ? 0.25 : (isHovering ? 1 : 0.6))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(.primary.opacity(isHovering && link.url != nil ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .padding(.horizontal, -6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(container.name), \(container.state.rawValue)")
    }

    private var dotColor: Color {
        switch container.state {
        case .running: Palette.ok
        case .paused, .restarting: Palette.warn
        default: Palette.idle
        }
    }

    /// Words as well as the dot colour: "Stopped", "Paused", or a health warning.
    private var note: (text: String, color: Color)? {
        switch container.state {
        case .running:
            if container.statusText?.contains("unhealthy") == true { return ("Unhealthy", Palette.warn) }
            return nil
        case .paused: return ("Paused", Palette.warn)
        case .restarting: return ("Restarting", Palette.warn)
        case .exited, .created, .dead: return ("Stopped", .secondary)
        case .unknown: return ("Unknown", .secondary)
        }
    }
}

struct VMsCard: View {
    @Environment(ServerStore.self) private var store

    var body: some View {
        let vms = store.snapshot?.vms
        Card("VMs", trailing: {
            PageLinkButton(help: "Open the VMs page in Unraid") { store.open(.vms) }
        }) {
            if let message = store.sectionErrors[.vms] {
                SectionErrorBanner(section: .vms, message: message)
            }
            if let vms {
                if vms.isEmpty {
                    Text("No virtual machines").font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(vms) { vm in
                            // A running VM with a console port set opens its VNC console; otherwise Unraid's VMs page.
                            let console = store.consoleURL(for: vm)
                            Button { store.openVM(vm) } label: {
                                HStack(spacing: 10) {
                                    StatusDot(color: color(for: vm.state))
                                    Text(vm.name).font(.callout)
                                    Spacer()
                                    Text(label(for: vm.state)).font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: console == nil ? "arrow.up.right" : "display")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(console == nil ? Color.secondary : Color.accentColor)
                                        .opacity(console == nil ? 0.6 : 1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(consoleHelp(for: vm, console: console))
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(console == nil ? "Opens the VMs page in your browser" : "Opens the VM console in your browser")
                        }
                    }
                }
            } else if store.sectionErrors[.vms] == nil {
                LoadingRow()
            }
        }
    }

    private func consoleHelp(for vm: VirtualMachine, console: URL?) -> String {
        if console != nil { return "Open the console for \(vm.name)" }
        if vm.state == .running { return "Open the VMs page. Set a console port in Settings → Links to open the console." }
        return "Open the VMs page in Unraid"
    }

    private func color(for state: VMState) -> Color {
        switch state {
        case .running: Palette.ok
        case .paused, .idle: Palette.warn
        case .crashed: Palette.bad
        default: Palette.idle
        }
    }

    private func label(for state: VMState) -> String {
        switch state {
        case .running: "Running"
        case .shutoff: "Stopped"
        case .paused: "Paused"
        case .idle: "Idle"
        case .crashed: "Crashed"
        case .other: "Unknown"
        }
    }
}

/// Small "open in Unraid" arrow in a card header.
struct PageLinkButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.right.square")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

#if DEBUG
#Preview("Docker + VMs (live)") {
    VStack(spacing: 12) { DockerCard(); VMsCard() }
        .padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.live))
}
#Preview("Docker failed to load") {
    VStack(spacing: 12) { DockerCard() }
        .padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.noContainers, errors: [.docker: "Couldn't reach the server (The request timed out.)"]))
}
#endif

import SwiftUI

/// Settings → Docker: choose the order containers are listed in the panel. Drag a row, or use the arrows.
/// With no custom order the list is alphabetical; "Reset" returns to that.
struct ContainerOrderView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ServerStore.self) private var store

    /// What the user is editing: the saved order (or alphabetical), ignoring the running-first grouping.
    private var containers: [DockerContainer] {
        ContainerOrdering.baseOrder(store.snapshot?.containers ?? [], custom: settings.primary.containerOrder)
    }

    private var hasCustomOrder: Bool { !settings.primary.containerOrder.isEmpty }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show running containers first", isOn: $settings.preferences.dockerRunningFirst)
                .help("Lists running containers above stopped ones, each group in the order below.")

            HStack {
                Text(hasCustomOrder ? "Custom order" : "Alphabetical (default)")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Reset to alphabetical") { settings.primary.containerOrder = [] }
                    .disabled(!hasCustomOrder)
                    .help("Forget the custom order and sort A to Z again.")
            }

            if containers.isEmpty {
                Text("Containers appear here once MenuRaid has loaded them from your server.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(containers.enumerated()), id: \.element.id) { index, container in
                        row(container, index: index, count: containers.count)
                    }
                    .onMove { source, destination in
                        save(ContainerOrdering.moved(containers.map(\.name), fromOffsets: source, toOffset: destination))
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
            }

            Text("Drag containers into the order you want, or use the arrows. New containers are added at the end, A to Z. The first eight are shown before \"Show all\" in the panel, so put your favourites at the top.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private func row(_ container: DockerContainer, index: Int, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            StatusDot(color: container.state.isRunning ? Palette.ok : Palette.idle)
            Text(container.name)
                .foregroundStyle(container.state.isRunning ? .primary : .secondary)
                .lineLimit(1)
            if !container.state.isRunning {
                Text("Stopped").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { nudge(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Move up")
                .accessibilityLabel("Move \(container.name) up")
            Button { nudge(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .help("Move down")
                .accessibilityLabel("Move \(container.name) down")
        }
        .buttonStyle(.borderless)
    }

    private func nudge(_ index: Int, by step: Int) {
        save(ContainerOrdering.nudged(containers.map(\.name), index: index, by: step))
    }

    /// Saves the edited order, keeping the place of containers that aren't in the list right now.
    private func save(_ visible: [String]) {
        settings.primary.containerOrder = ContainerOrdering.merged(edited: visible, previous: settings.primary.containerOrder)
    }
}

#if DEBUG
#Preview {
    ContainerOrderView()
        .frame(width: 540, height: 520)
        .environment(PreviewFixtures.settings)
        .environment(PreviewFixtures.store(PreviewFixtures.live))
}
#endif

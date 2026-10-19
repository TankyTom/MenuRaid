import SwiftUI

/// Where clicks go: per-container URL overrides (reverse proxies, Cloudflare tunnels, containers whose first
/// published port isn't their web UI; opened exactly as written) and per-VM console ports.
struct ContainerOverridesView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ServerStore.self) private var store

    @State private var newName = ""

    private var overrides: [String: String] { settings.primary.containerOverrides }
    private var names: [String] { overrides.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

    /// Containers seen on the server that don't have an override yet.
    private var addable: [String] {
        let taken = Set(overrides.keys.map { $0.lowercased() })
        return (store.snapshot?.containers ?? [])
            .map(\.name)
            .filter { !taken.contains($0.lowercased()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                if names.isEmpty {
                    Text("No overrides. Containers open at http://<server>:<first published port>.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(names, id: \.self) { name in row(for: name) }
                }
            } header: {
                Text("Container URLs")
            } footer: {
                Text("Use this for containers behind a reverse proxy or tunnel, or when the first published port isn't the web UI. The URL is opened exactly as written; without a scheme, http:// is assumed.")
            }

            vmSection

            Section("Add container override") {
                if !addable.isEmpty {
                    Menu("Choose a container…") {
                        ForEach(addable, id: \.self) { name in
                            Button(name) { settings.primary.containerOverrides[name] = "" }
                        }
                    }
                }
                HStack {
                    TextField("Container name", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        settings.primary.containerOverrides[name] = settings.primary.containerOverrides[name] ?? ""
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: VM consoles

    private var vmSection: some View {
        Section {
            let vms = store.snapshot?.vms ?? []
            if vms.isEmpty {
                Text("No VMs found yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(vms) { vm in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.name).font(.callout.weight(.semibold))
                        Text(portHint(for: vm)).font(.caption).foregroundStyle(portIsInvalid(vm) ? Color.orange : Color.secondary)
                    }
                    Spacer()
                    TextField("Port", text: portBinding(for: vm.name), prompt: Text("5700"))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
            }
        } header: {
            Text("VM console ports")
        } footer: {
            Text("Clicking a running VM opens its VNC console when a port is set. Unraid's API doesn't report it: open the VM's console in Unraid and copy the number from the address (…/wsproxy/5700/). It can change if VMs are started in a different order.")
        }
    }

    private func portBinding(for name: String) -> Binding<String> {
        Binding(
            get: {
                let match = settings.primary.vmConsolePorts.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
                return match.map { String($0.value) } ?? ""
            },
            set: { text in
                settings.primary.vmConsolePorts = settings.primary.vmConsolePorts.filter { $0.key.caseInsensitiveCompare(name) != .orderedSame }
                let digits = text.filter(\.isNumber)
                if let port = Int(digits) { settings.primary.vmConsolePorts[name] = port }
            }
        )
    }

    private func portIsInvalid(_ vm: VirtualMachine) -> Bool {
        let raw = settings.primary.vmConsolePorts.first { $0.key.caseInsensitiveCompare(vm.name) == .orderedSame }?.value
        return raw != nil && LinkBuilder.consolePort(for: vm.name, in: settings.primary.vmConsolePorts) == nil
    }

    private func portHint(for vm: VirtualMachine) -> String {
        if portIsInvalid(vm) { return "Port must be between 1 and 65535" }
        if LinkBuilder.consolePort(for: vm.name, in: settings.primary.vmConsolePorts) != nil {
            return vm.state == .running ? "Console opens when you click" : "Console opens while the VM is running"
        }
        return "Not set: opens the VMs page"
    }

    private func row(for name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.callout.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    settings.primary.containerOverrides[name] = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove override")
                .accessibilityLabel("Remove override for \(name)")
            }
            TextField("URL", text: binding(for: name), prompt: Text("https://app.example.com"))
                .autocorrectionDisabled()
            hint(for: name)
        }
    }

    @ViewBuilder
    private func hint(for name: String) -> some View {
        let value = overrides[name] ?? ""
        if !value.trimmingCharacters(in: .whitespaces).isEmpty, LinkBuilder.parseOverride(value) == nil {
            Label("Not a valid http(s) URL. The automatic link is used instead.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        } else if let container = store.snapshot?.containers?.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            let automatic = LinkBuilder.container(container, base: store.activeBase, overrides: [:])
            Text(automatic.url.map { "Automatic link: \($0.absoluteString)" } ?? "Automatic link: none (no published port)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { settings.primary.containerOverrides[name] ?? "" },
            set: { settings.primary.containerOverrides[name] = $0 }
        )
    }
}

#if DEBUG
#Preview {
    ContainerOverridesView()
        .frame(width: 540, height: 420)
        .environment(PreviewFixtures.settings)
        .environment(PreviewFixtures.store(PreviewFixtures.live))
}
#endif

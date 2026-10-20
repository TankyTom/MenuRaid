import SwiftUI

/// Settings window. Later milestones add refresh interval, label choice, thresholds, overrides and Test connection.
struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem { Label("Connection", systemImage: "network") }
            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "menubar.rectangle") }
            ContainerOverridesView()
                .tabItem { Label("Links", systemImage: "link") }
            ContainerOrderView()
                .tabItem { Label("Docker", systemImage: "shippingbox") }
            #if DEBUG
            TestQueryView()
                .tabItem { Label("Debug", systemImage: "ladybug") }
            #endif
        }
        .frame(width: 540, height: 520)
    }
}

/// Addresses, route mode and the API key (saved to the Keychain).
struct ConnectionSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ServerStore.self) private var store

    private let keychain = KeychainStore()

    @State private var apiKey = ""
    @State private var keyStored = false
    @State private var keyMessage: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Server") {
                TextField("LAN address", text: $settings.primary.lanAddress, prompt: Text("192.168.1.10"))
                    .autocorrectionDisabled()
                addressStatus(for: settings.primary.lanAddress)
                if SecurityNotice.lanUsesPlainHTTP(settings.primary) {
                    Label("Plain HTTP: your API key is sent unencrypted on your network. Enable HTTPS in Unraid if you can.", systemImage: "lock.open.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Remote address", text: $settings.primary.remoteAddress, prompt: Text("100.64.0.1 or tower.tailnet-xxxx.ts.net"))
                    .autocorrectionDisabled()
                addressStatus(for: settings.primary.remoteAddress)

                Picker("Mode", selection: $settings.primary.mode) {
                    ForEach(RouteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            TestConnectionSection(typedKey: apiKey)

            Section {
                SecureField("API key", text: $apiKey, prompt: Text(keyStored ? "Saved in Keychain" : "Paste your key"))
                HStack {
                    Button("Save key") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove key", role: .destructive) { removeKey() }
                        .disabled(!keyStored)
                    if let keyMessage {
                        Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("API key")
            } footer: {
                Text("Create a key with the Viewer role under Settings → Management Access → API Keys in the Unraid webGUI. MenuRaid only reads.")
            }
        }
        .formStyle(.grouped)
        .onAppear { keyStored = keychain.hasSecret(account: settings.primary.id.uuidString) }
        // Reconnect soon after the connection settings change, instead of waiting for the next scheduled refresh.
        .onChange(of: settings.primary.lanAddress) { store.settingsChanged() }
        .onChange(of: settings.primary.remoteAddress) { store.settingsChanged() }
        .onChange(of: settings.primary.mode) { store.settingsChanged() }
    }

    @ViewBuilder
    private func addressStatus(for input: String) -> some View {
        if !input.trimmingCharacters(in: .whitespaces).isEmpty {
            if let parsed = AddressParser.parse(input), let url = parsed.baseURL {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Not a valid address", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func saveKey() {
        let account = settings.primary.id.uuidString
        do {
            try keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
            apiKey = ""
            keyStored = true
            keyMessage = "Saved."
            store.settingsChanged()
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try keychain.delete(account: settings.primary.id.uuidString)
            keyStored = false
            keyMessage = "Removed."
            store.forgetServerData()
        } catch {
            keyMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}

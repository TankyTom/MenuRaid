import SwiftUI

/// Refresh interval, menu bar value and temperature thresholds.
struct DisplaySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Launch MenuRaid at login", isOn: Binding(
                    get: { launchAtLogin.state.isOn },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                switch launchAtLogin.state {
                case .needsApproval:
                    HStack {
                        Label("Approve MenuRaid in System Settings → General → Login Items.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Palette.warn)
                        Spacer()
                        Button("Open Login Items…") { launchAtLogin.openLoginItemsSettings() }
                    }
                case .unavailable:
                    Label("macOS can't register this copy of MenuRaid. Move it to the Applications folder and try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Palette.warn)
                default:
                    EmptyView()
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Palette.bad)
                }
            } header: {
                Text("Startup")
            }


            Section {
                Picker("Default appearance", selection: $settings.preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.preferences.appearance) { settings.appearanceOverride = nil }
            } header: {
                Text("Panel")
            } footer: {
                Text("The sun/moon button in the panel switches temporarily. This default applies each time MenuRaid starts.")
            }

            Section("Menu bar") {
                Picker("Show", selection: $settings.preferences.menuBarValue) {
                    ForEach(MenuBarValue.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Picker("Background refresh", selection: $settings.preferences.refreshInterval) {
                    ForEach(AppPreferences.refreshChoices, id: \.self) { Text("Every \($0) seconds").tag($0) }
                }
            } footer: {
                Text("While the panel is open, MenuRaid refreshes every 5 seconds.")
            }

            Section {
                thresholdRow("Hard disk: warm", value: $settings.preferences.thresholds.hddWarn)
                thresholdRow("Hard disk: critical", value: $settings.preferences.thresholds.hddCritical)
                thresholdRow("SSD / NVMe: warm", value: $settings.preferences.thresholds.ssdWarn)
                thresholdRow("SSD / NVMe: critical", value: $settings.preferences.thresholds.ssdCritical)
            } header: {
                Text("Disk temperature (°C)")
            } footer: {
                Text("Warm turns the status amber, critical turns it red. Disks that don't report whether they're SSDs use the hard disk limits.")
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }

    private func thresholdRow(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 20...100, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))°C").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

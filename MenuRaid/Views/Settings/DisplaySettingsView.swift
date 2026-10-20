import SwiftUI

/// Refresh interval, menu bar value and temperature thresholds.
struct DisplaySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ServerStore.self) private var store
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var notificationNote: String?

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
                Toggle("Notify me when a new problem appears", isOn: $settings.preferences.notifyOnProblems)
                    .onChange(of: settings.preferences.notifyOnProblems) { _, enabled in
                        guard enabled else { notificationNote = nil; return }
                        Task {
                            if await store.enableNotifications() == .allowed {
                                notificationNote = nil
                            } else {
                                settings.preferences.notifyOnProblems = false
                                notificationNote = "macOS isn't allowing notifications for MenuRaid. Allow them in System Settings → Notifications → MenuRaid, then switch this on again."
                            }
                        }
                    }
                if let notificationNote {
                    Label(notificationNote, systemImage: "bell.slash")
                        .font(.caption).foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Notification Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if settings.preferences.notifyOnProblems {
                    Button("Send a test notification") { store.sendTestNotification() }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Shows a macOS notification when a new red problem appears: a disabled disk, disk errors, a critical temperature, or the array stopped. It doesn't notify when the server is merely unreachable, because MenuRaid can't tell that from your Mac being offline. Notifications stay on this Mac; nothing is sent anywhere. MenuRaid must be running to notice, so this complements Unraid's own email and push alerts rather than replacing them.")
            }

            Section {
                Toggle("Check for Unraid OS updates", isOn: $settings.preferences.checkForOSUpdates)
                    .onChange(of: settings.preferences.checkForOSUpdates) { _, enabled in
                        if enabled { store.checkForOSUpdateNow() }
                    }
                if settings.preferences.checkForOSUpdates, let latest = settings.latestRelease {
                    Text("Latest stable release: Unraid \(latest.version)\(latest.date.map { " (\($0))" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Off by default. When on, MenuRaid asks Unraid's public release server (releases.unraid.net) for the latest stable version about every 6 hours and compares it with your server's. It sends nothing about your server: no version, hostname or API key. This is the only request MenuRaid makes to anything other than your own server.")
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
                .onChange(of: settings.preferences.refreshInterval) { store.settingsChanged() }
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

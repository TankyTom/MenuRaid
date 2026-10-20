import SwiftUI

@main
struct MenuRaidApp: App {
    @State private var settings: SettingsStore
    @State private var store: ServerStore

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        let store = ServerStore(settings: settings)
        store.activateNotifications()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(settings)
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(store)
        }
    }
}

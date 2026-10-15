import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let monitor: Monitor

    @AppStorage(Prefs.menuBarStyle) private var menuBarStyle = MenuBarStyle.power.rawValue
    @AppStorage(Prefs.refreshInterval) private var refreshInterval = 2.0
    @AppStorage(Prefs.notifyDevices) private var notifyDevices = false
    @AppStorage(Prefs.showInDock) private var showInDock = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Show in the menu bar", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                Toggle("Show PowerDeck in the Dock", isOn: $showInDock)
            } header: {
                Text("Appearance")
            } footer: {
                Text("With the Dock icon hidden, open the dashboard from the ⚡ in the menu bar.")
            }

            Section("Updates") {
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            }

            Section {
                Toggle("Notify me when devices or chargers connect", isOn: $notifyDevices)
            } header: {
                Text("Alerts")
            } footer: {
                Text("PowerDeck always shows alerts inside its window. This also sends them to Notification Center, including warnings like a draining battery.")
            }

            Section {
                Toggle("Open PowerDeck when I log in", isOn: $launchAtLogin)
                if let loginMessage {
                    Text(loginMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Works best once PowerDeck is in your Applications folder.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: refreshInterval) { _, seconds in
            monitor.setInterval(seconds)
        }
        .onChange(of: notifyDevices) { _, enabled in
            monitor.notificationsEnabled = enabled
            if enabled {
                Task { _ = await Notifier.requestAuthorization() }
            }
        }
        .onChange(of: showInDock) { _, show in
            NSApp.setActivationPolicy(show ? .regular : .accessory)
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginMessage = SMAppService.mainApp.status == .requiresApproval
                    ? "Approve PowerDeck in System Settings → General → Login Items."
                    : nil
            } catch {
                loginMessage = "macOS didn't allow it: \(error.localizedDescription)"
            }
        }
    }
}

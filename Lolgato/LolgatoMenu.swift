import SwiftUI

struct DeviceRow: View {
    @ObservedObject var device: ElgatoDevice

    var body: some View {
        Text(device.name)
            .font(.subheadline)
    }
}

struct LolgatoMenu: View {
    @ObservedObject var appState: AppState
    @ObservedObject var deviceManager: ElgatoDeviceManager
    let updateChecker = GitHubUpdateChecker()

    var readyDevices: [ElgatoDevice] {
        deviceManager.devices.filter { !$0.macAddress.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Devices:")
                .font(.headline)
            if readyDevices.isEmpty {
                Text("No devices found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(readyDevices, id: \.id) { device in
                    DeviceRow(device: device)
                }
            }

            Divider()

            Toggle("Lights on with Camera", isOn: $appState.lightsOnWithCamera)
            Toggle("Lights off on Sleep", isOn: $appState.lightsOffOnSleep)

            Divider()

            Button("Check for Updates...", action: checkForUpdates)

            Group {
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Text("Settings...")
                    }
                } else {
                    Button(action: {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }, label: {
                        Text("Settings...")
                    })
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .foregroundColor(.secondary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q", modifiers: .command)
        }
        .padding()
        .frame(width: 250)
    }

    func checkForUpdates() {
        updateChecker.checkForNewRelease { isNewVersionAvailable, latestVersion in
            DispatchQueue.main.async {
                if isNewVersionAvailable, let version = latestVersion {
                    updateChecker.promptForUpdate(newVersion: version)
                } else {
                    updateChecker.promptForNoUpdate()
                }
            }
        }
    }
}

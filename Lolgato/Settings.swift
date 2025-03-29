import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var deviceManager: ElgatoDeviceManager

    init(appState: AppState, deviceManager: ElgatoDeviceManager) {
        self.appState = appState
        self.deviceManager = deviceManager
    }

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            DeviceSettingsView(deviceManager: deviceManager)
                .tabItem {
                    Label("Devices", systemImage: "lightbulb")
                }

            KeyboardShortcutsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .padding(20)
        .frame(width: 600, height: 450)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            settingRow(label: "Camera:") {
                Toggle("Lights on automatically", isOn: $appState.lightsOnWithCamera)
            } caption: {
                Text("Turn on lights when camera is in use.")
            }

            settingRow(label: "Sleep:") {
                Toggle("Lights on and off automatically", isOn: $appState.lightsOffOnSleep)
            } caption: {
                Text(
                    "Turn off lights when system goes to sleep or is locked, and turn them back on when waking up."
                )
            }

            Divider()

            settingRow(label: "Launch:") {
                LaunchAtLogin.Toggle("Automatically at system startup")
            }

            Spacer()
            Divider()
            ResetButton(action: resetToDefaults)
        }
    }

    private func resetToDefaults() {
        appState.lightsOnWithCamera = false
        appState.lightsOffOnSleep = false
        LaunchAtLogin.isEnabled = false
    }
}

struct KeyboardShortcutsView: View {
    var body: some View {
        VStack(spacing: 20) {
            shortcutRow(
                label: "Toggle Lights:",
                shortcut: .toggleLights,
                caption: "Toggle lights on/off."
            )

            Divider()

            shortcutRow(
                label: "Brightness Up:",
                shortcut: .increaseBrightness,
                caption: "Increase all lights' brightness."
            )

            shortcutRow(
                label: "Brightness Down:",
                shortcut: .decreaseBrightness,
                caption: "Decrease all lights' brightness."
            )

            Divider()

            shortcutRow(
                label: "Cooler:",
                shortcut: .increaseTemperature,
                caption: "Make lights cooler (more blue)."
            )

            shortcutRow(
                label: "Warmer:",
                shortcut: .decreaseTemperature,
                caption: "Make lights warmer (more yellow)."
            )

            Spacer()
            Divider()
            ResetButton(action: resetToDefaults)
        }
    }

    private func shortcutRow(label: String, shortcut: KeyboardShortcuts.Name, caption: String) -> some View {
        settingRow(label: label) {
            KeyboardShortcuts.Recorder(for: shortcut)
                .padding(.top, -1)
        } caption: {
            Text(caption)
        }
    }

    private func resetToDefaults() {
        KeyboardShortcuts.reset(.toggleLights)
        KeyboardShortcuts.reset(.increaseBrightness)
        KeyboardShortcuts.reset(.decreaseBrightness)
        KeyboardShortcuts.reset(.increaseTemperature)
        KeyboardShortcuts.reset(.decreaseTemperature)
    }
}

func settingRow<Content: View, Caption: View>(
    label: String,
    @ViewBuilder content: () -> Content,
    @ViewBuilder caption: () -> Caption = { EmptyView() }
) -> some View {
    HStack(alignment: .top) {
        Text(label)
            .frame(width: 130, alignment: .trailing)
        VStack(alignment: .leading, spacing: 4) {
            content()
            caption()
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResetButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Restore Defaults", action: action)
        }
    }
}

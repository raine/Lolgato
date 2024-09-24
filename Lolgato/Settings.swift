import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        GeneralSettingsView(appState: appState)
            .padding(30)
            .frame(width: 500, height: 300)
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
                Toggle("Lights off automatically", isOn: $appState.lightsOffOnSleep)
            } caption: {
                Text("Turn off lights when system goes to sleep or is locked.")
            }

            shortcutRow(
                label: "Toggle Lights:",
                shortcut: .toggleLights,
                caption: "Toggle lights on/off."
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
        appState.lightsOnWithCamera = false
        appState.lightsOffOnSleep = false
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

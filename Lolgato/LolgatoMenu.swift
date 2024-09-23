import SwiftUI

struct LolgatoMenu: View {
    @ObservedObject var appState: AppState
    @ObservedObject var deviceManager: ElgatoDeviceManager

    var body: some View {
        VStack(alignment: .leading) {
            Text("Devices:")
                .font(.headline)
            if deviceManager.devices.isEmpty {
                Text("No devices found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading)
            } else {
                ForEach(deviceManager.devices, id: \.id) { device in
                    Text(device.displayName ?? device.productName)
                        .font(.subheadline)
                        .padding(.leading)
                }
            }

            Divider()

            Toggle("Lights on with Camera", isOn: $appState.lightsOnWithCamera)
            Toggle("Lights off on Sleep", isOn: $appState.lightsOffOnSleep)

            Divider()

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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q", modifiers: .command)
        }
        .padding()
        .frame(width: 250)
    }
}

import SwiftUI

@main
struct LolgatoApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Lolgato", image: "MenuBarIcon") {
            LolgatoMenu(appState: coordinator.appState, deviceManager: coordinator.deviceManager)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: coordinator.appState, deviceManager: coordinator.deviceManager)
        }
    }
}

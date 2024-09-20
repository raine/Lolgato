import Cocoa
import Combine
import SwiftUI

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []
    @ObservedObject var deviceManager: ElgatoDeviceManager

    @Published var lightsOnWithCamera: Bool {
        didSet {
            UserDefaults.standard.set(lightsOnWithCamera, forKey: "lightsOnWithCamera")
        }
    }

    @Published var lightsOffOnSleep: Bool {
        didSet {
            UserDefaults.standard.set(lightsOffOnSleep, forKey: "lightsOffOnSleep")
        }
    }

    init(deviceManager: ElgatoDeviceManager) {
        self.deviceManager = deviceManager
        lightsOnWithCamera = UserDefaults.standard.bool(forKey: "lightsOnWithCamera")
        lightsOffOnSleep = UserDefaults.standard.bool(forKey: "lightsOffOnSleep")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Elgato Devices")
        }
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()
        let titleFont = NSFont.menuBarFont(ofSize: 12)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 1.0),
        ]
        let titleItem = NSMenuItem(title: "Devices:", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(string: "Devices:", attributes: titleAttributes)
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        deviceManager.objectWillChange
            .sink { [weak self] in
                self?.updateMenu()
            }
            .store(in: &cancellables)
        updateMenu()
        statusItem.menu = menu
    }

    private func updateMenu() {
        guard let menu = statusItem.menu else { return }
        // Remove all items except the title and separator
        while menu.items.count > 1 {
            menu.removeItem(at: 1)
        }
        if deviceManager.devices.isEmpty {
            let noDevicesItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            menu.addItem(noDevicesItem)
        } else {
            for device in deviceManager.devices {
                let deviceName = device.displayName ?? device.productName
                let deviceAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 12)]
                let menuItem = NSMenuItem(title: deviceName, action: nil, keyEquivalent: "")
                menuItem.attributedTitle = NSAttributedString(
                    string: deviceName,
                    attributes: deviceAttributes
                )
                menuItem.isEnabled = false
                menuItem.indentationLevel = 1
                menu.addItem(menuItem)
            }
        }
        menu.addItem(NSMenuItem.separator())

        // Add the toggle for lights with camera
        let lightsToggleItem = NSMenuItem(
            title: "Lights on with Camera",
            action: #selector(toggleLightsWithCamera),
            keyEquivalent: ""
        )
        lightsToggleItem.target = self
        lightsToggleItem.state = lightsOnWithCamera ? .on : .off
        menu.addItem(lightsToggleItem)

        // Add the toggle for lights off on sleep
        let sleepToggleItem = NSMenuItem(
            title: "Lights off on Sleep",
            action: #selector(toggleLightsOffOnSleep),
            keyEquivalent: ""
        )
        sleepToggleItem.target = self
        sleepToggleItem.state = lightsOffOnSleep ? .on : .off
        menu.addItem(sleepToggleItem)

        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshDevices), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.shared.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    @objc private func refreshDevices() {
        Task {
            await deviceManager.performDiscovery()
        }
    }

    @objc private func toggleLightsWithCamera() {
        lightsOnWithCamera.toggle()
        updateMenu()
    }

    @objc private func toggleLightsOffOnSleep() {
        lightsOffOnSleep.toggle()
        updateMenu()
    }
}

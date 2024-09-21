import Cocoa
import Combine
import SwiftUI

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []
    @ObservedObject var deviceManager: ElgatoDeviceManager
    @ObservedObject var appDelegate: AppDelegate

    init(deviceManager: ElgatoDeviceManager, appDelegate: AppDelegate) {
        self.deviceManager = deviceManager
        self.appDelegate = appDelegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Lolgato")
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
        statusItem.menu = menu

        updateMenu()
    }

    private func updateMenu() {
        guard let menu = statusItem.menu else { return }

        // Remove all items except the title
        while menu.items.count > 1 {
            menu.removeItem(at: 1)
        }
        if deviceManager.devices.isEmpty {
            let noDevicesItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            noDevicesItem.indentationLevel = 1
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

        let lightsToggleItem = NSMenuItem(
            title: "Lights on with Camera",
            action: #selector(toggleLightsWithCamera),
            keyEquivalent: ""
        )
        lightsToggleItem.target = self
        lightsToggleItem.state = appDelegate.lightsOnWithCamera ? .on : .off
        menu.addItem(lightsToggleItem)

        let sleepToggleItem = NSMenuItem(
            title: "Lights off on Sleep",
            action: #selector(toggleLightsOffOnSleep),
            keyEquivalent: ""
        )
        sleepToggleItem.target = self
        sleepToggleItem.state = appDelegate.lightsOffOnSleep ? .on : .off
        menu.addItem(sleepToggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.shared.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    @objc private func toggleLightsWithCamera() {
        appDelegate.lightsOnWithCamera.toggle()
        updateMenu()
    }

    @objc private func toggleLightsOffOnSleep() {
        appDelegate.lightsOffOnSleep.toggle()
        updateMenu()
    }
}

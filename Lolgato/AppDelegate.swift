import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var deviceManager: ElgatoDeviceManager?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_: Notification) {
        let discovery = ElgatoDiscovery()
        deviceManager = ElgatoDeviceManager(discovery: discovery)

        if let deviceManager = deviceManager {
            statusBarController = StatusBarController(deviceManager: deviceManager)
        }
    }

    func applicationWillBecomeActive(_: Notification) {
        Task {
            await deviceManager?.performDiscovery()
        }
    }

    func applicationWillTerminate(_: Notification) {
        deviceManager?.stopDiscovery()
    }
}

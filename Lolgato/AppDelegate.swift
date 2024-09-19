import Cocoa
import Network
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private var deviceManager: ElgatoDeviceManager?

    func applicationDidFinishLaunching(_: Notification) {
        let discovery = ElgatoDiscovery()
        deviceManager = ElgatoDeviceManager(discovery: discovery)
    }

    func applicationWillBecomeActive(_: Notification) {
        deviceManager?.performDiscovery()
    }

    func applicationWillTerminate(_: Notification) {
        deviceManager?.stopDiscovery()
    }
}

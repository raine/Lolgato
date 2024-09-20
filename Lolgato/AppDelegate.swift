import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var deviceManager: ElgatoDeviceManager?
    private var statusBarController: StatusBarController?
    private var cameraDetector: CameraUsageDetector?

    func applicationDidFinishLaunching(_: Notification) {
        let discovery = ElgatoDiscovery()
        deviceManager = ElgatoDeviceManager(discovery: discovery)
        if let deviceManager = deviceManager {
            statusBarController = StatusBarController(deviceManager: deviceManager)
            deviceManager.startDiscovery()
        }

        setupCameraMonitoring()
    }

    func applicationWillTerminate(_: Notification) {
        deviceManager?.stopDiscovery()
        cameraDetector?.stopMonitoring()
    }

    private func setupCameraMonitoring() {
        cameraDetector = CameraUsageDetector()
        cameraDetector?.startMonitoring { [weak self] isActive in
            self?.handleCameraActivityChange(isActive: isActive)
        }
    }

    private func handleCameraActivityChange(isActive: Bool) {
        if isActive {
            print("Camera became active")
        } else {
            print("Camera became inactive")
        }
    }
}

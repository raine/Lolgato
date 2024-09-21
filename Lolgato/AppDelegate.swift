import Cocoa
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var deviceManager: ElgatoDeviceManager?
    private var statusBarController: StatusBarController?
    private var cameraDetector: CameraUsageDetector?
    private var lightCameraController: LightCameraController?

    @Published var lightsOnWithCamera: Bool {
        didSet {
            UserDefaults.standard.set(lightsOnWithCamera, forKey: "lightsOnWithCamera")
            updateCameraMonitoring()
        }
    }

    @Published var lightsOffOnSleep: Bool {
        didSet {
            UserDefaults.standard.set(lightsOffOnSleep, forKey: "lightsOffOnSleep")
        }
    }

    override init() {
        lightsOnWithCamera = UserDefaults.standard.bool(forKey: "lightsOnWithCamera")
        lightsOffOnSleep = UserDefaults.standard.bool(forKey: "lightsOffOnSleep")
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        let discovery = ElgatoDiscovery()
        deviceManager = ElgatoDeviceManager(discovery: discovery)
        if let deviceManager = deviceManager {
            statusBarController = StatusBarController(deviceManager: deviceManager, appDelegate: self)
            lightCameraController = LightCameraController(
                deviceManager: deviceManager,
                appDelegate: self
            )
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
        updateCameraMonitoring()
    }

    private func updateCameraMonitoring() {
        cameraDetector?.updateMonitoring(enabled: lightsOnWithCamera) { [weak self] isActive in
            self?.lightCameraController?.handleCameraActivityChange(isActive: isActive)
        }
    }
}

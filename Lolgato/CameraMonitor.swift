import AVFoundation
import Combine
import Foundation
import os

class CameraMonitor: ObservableObject {
    @Published private(set) var availableCameras: [CameraDevice] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CameraMonitor")

    init() {
        refreshCameras()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraConnectionChange),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraConnectionChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
        logger.info("CameraMonitor initialized and is listening for hardware changes.")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleCameraConnectionChange(notification: Notification) {
        let event = (notification.name == .AVCaptureDeviceWasConnected) ? "connected" : "disconnected"
        logger.info("A camera was \(event). Refreshing device list.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.refreshCameras()
        }
    }

    private func refreshCameras() {
        self.availableCameras = CameraManager.getAvailableCameras()
    }
}

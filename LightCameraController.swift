import Combine
import Foundation
import os

class LightCameraController {
    private let deviceManager: ElgatoDeviceManager
    private let appDelegate: AppDelegate
    private var cancellables: Set<AnyCancellable> = []
    private var areLightsControlledByCamera: Bool = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LightCameraController")
    private var isCameraActive: Bool = false

    init(deviceManager: ElgatoDeviceManager, appDelegate: AppDelegate) {
        self.deviceManager = deviceManager
        self.appDelegate = appDelegate
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        appDelegate.$lightsOnWithCamera
            .sink { [weak self] newValue in
                self?.handleLightsOnWithCameraChange(newValue)
            }
            .store(in: &cancellables)
    }

    private func handleLightsOnWithCameraChange(_ newValue: Bool) {
        if newValue, isCameraActive {
            turnOnAllLights()
        } else if !newValue {
            turnOffLightsIfControlled()
        }
    }

    func handleCameraActivityChange(isActive: Bool) {
        isCameraActive = isActive
        guard appDelegate.lightsOnWithCamera else { return }
        if isActive {
            turnOnAllLights()
        } else {
            turnOffLightsIfControlled()
        }
    }

    private func turnOnAllLights() {
        for device in deviceManager.devices where device.isOnline {
            Task {
                do {
                    try await device.turnOn()
                    logger.info("Turned on device: \(device.name)")
                } catch {
                    logger
                        .error(
                            "Failed to turn on device: \(device.name). Error: \(error.localizedDescription)"
                        )
                }
            }
        }
        areLightsControlledByCamera = true
        logger.info("All lights turned on due to camera activity")
    }

    private func turnOffLightsIfControlled() {
        guard areLightsControlledByCamera else { return }
        for device in deviceManager.devices where device.isOnline {
            Task {
                do {
                    try await device.turnOff()
                    logger.info("Turned off device: \(device.name)")
                } catch {
                    logger
                        .error(
                            "Failed to turn off device: \(device.name). Error: \(error.localizedDescription)"
                        )
                }
            }
        }
        areLightsControlledByCamera = false
        logger.info("All lights turned off due to camera inactivity")
    }
}

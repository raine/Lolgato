import Combine
import Foundation
import os

class LightCameraController {
    private let deviceManager: ElgatoDeviceManager
    private let appDelegate: AppDelegate
    private var cancellables: Set<AnyCancellable> = []
    private var lightsControlledByCamera: Set<ElgatoDevice> = []
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
            turnOffControlledLights()
        }
    }

    func handleCameraActivityChange(isActive: Bool) {
        isCameraActive = isActive
        guard appDelegate.lightsOnWithCamera else { return }
        if isActive {
            checkAndTurnOnLights()
        } else {
            turnOffControlledLights()
        }
    }

    private func checkAndTurnOnLights() {
        for device in deviceManager.devices where device.isOnline {
            Task {
                do {
                    try await device.fetchLightInfo()
                    if !device.isOn {
                        try await device.turnOn()
                        lightsControlledByCamera.insert(device)
                        logger.info("Turned on device: \(device.name)")
                    } else {
                        logger.info("Device already on: \(device.name)")
                    }
                } catch {
                    logger
                        .error(
                            "Failed to check or turn on device: \(device.name). Error: \(error.localizedDescription)"
                        )
                }
            }
        }
        logger.info("Checked and turned on necessary lights due to camera activity")
    }

    private func turnOffControlledLights() {
        for device in lightsControlledByCamera {
            Task {
                do {
                    try await device.turnOff()
                    logger.info("Turned off controlled device: \(device.name)")
                } catch {
                    logger
                        .error(
                            "Failed to turn off controlled device: \(device.name). Error: \(error.localizedDescription)"
                        )
                }
            }
        }

        lightsControlledByCamera.removeAll()
    }

    private func turnOnAllLights() {
        for device in deviceManager.devices where device.isOnline {
            Task {
                do {
                    try await device.turnOn()
                    lightsControlledByCamera.insert(device)
                    logger.info("Turned on device: \(device.name)")
                } catch {
                    logger
                        .error(
                            "Failed to turn on device: \(device.name). Error: \(error.localizedDescription)"
                        )
                }
            }
        }
        logger.info("All lights turned on due to lights-on-with-camera setting")
    }
}

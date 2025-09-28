import Combine
import Foundation
import os

class LightCameraController {
    private let deviceManager: ElgatoDeviceManager
    private let appState: AppState
    private let cameraStatusPublisher: AnyPublisher<Bool, Never>
    private var cancellables: Set<AnyCancellable> = []
    private var lightsControlledByCamera: Set<ElgatoDevice> = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LightCameraController")
    private var isCameraActive: Bool = false

    init(deviceManager: ElgatoDeviceManager,
         appState: AppState,
         cameraStatusPublisher: AnyPublisher<Bool, Never>)
    {
        self.deviceManager = deviceManager
        self.appState = appState
        self.cameraStatusPublisher = cameraStatusPublisher
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        appState.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleLightsOnWithCameraChange(self.appState.lightsOnWithCamera)
            }
            .store(in: &cancellables)

        cameraStatusPublisher
            .sink { [weak self] isActive in
                self?.handleCameraActivityChange(isActive: isActive)
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

    private func handleCameraActivityChange(isActive: Bool) {
        isCameraActive = isActive
        guard appState.lightsOnWithCamera else { return }
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
                        logger.info("Turned on device: \(device.name, privacy: .public)")
                    } else {
                        logger.info("Device already on: \(device.name, privacy: .public)")
                    }
                } catch {
                    logger
                        .error(
                            "Failed to check or turn on device: \(device.name, privacy: .public). Error: \(error.localizedDescription, privacy: .public)"
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
                    logger.info("Turned off controlled device: \(device.name, privacy: .public)")
                } catch {
                    logger
                        .error(
                            "Failed to turn off controlled device: \(device.name, privacy: .public). Error: \(error.localizedDescription, privacy: .public)"
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
                    logger.info("Turned on device: \(device.name, privacy: .public)")
                } catch {
                    logger
                        .error(
                            "Failed to turn on device: \(device.name, privacy: .public). Error: \(error.localizedDescription, privacy: .public)"
                        )
                }
            }
        }
        logger.info("All lights turned on due to lights-on-with-camera setting")
    }
}

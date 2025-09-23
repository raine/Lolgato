import Combine
import KeyboardShortcuts
import os
import SwiftUI

class AppState: ObservableObject {
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

    @Published var syncWithNightShift: Bool {
        didSet {
            UserDefaults.standard.set(syncWithNightShift, forKey: "syncWithNightShift")
        }
    }

    init() {
        lightsOnWithCamera = UserDefaults.standard.bool(forKey: "lightsOnWithCamera")
        lightsOffOnSleep = UserDefaults.standard.bool(forKey: "lightsOffOnSleep")
        syncWithNightShift = UserDefaults.standard.bool(forKey: "syncWithNightShift")
    }
}

class AppCoordinator: ObservableObject {
    @Published var appState: AppState
    @Published var deviceManager: ElgatoDeviceManager

    lazy var lightCameraController: LightCameraController = .init(
        deviceManager: deviceManager,
        appState: appState,
        cameraStatusPublisher: cameraDetector.cameraStatusPublisher
    )

    lazy var lightSystemStateController: LightSystemStateController = .init(
        deviceManager: deviceManager,
        appState: appState
    )

    lazy var nightShiftSyncController: NightShiftSyncController = .init(
        deviceManager: deviceManager,
        appState: appState
    )

    private var cameraDetector: CameraUsageDetector
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AppCoordinator"
    )

    init() {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        logger.info("Application started - Version: \(version)")
        let discovery = ElgatoDiscovery()
        deviceManager = ElgatoDeviceManager(discovery: discovery)
        appState = AppState()
        cameraDetector = CameraUsageDetector()

        setupControllers()
        setupBindings()
        setupShortcuts()

        Task { @MainActor in
            deviceManager.loadDevicesFromPersistentStorage()
            deviceManager.startDiscovery()
        }
    }

    private func setupControllers() {
        _ = lightCameraController
        _ = lightSystemStateController
        _ = nightShiftSyncController
    }

    private func setupBindings() {
        appState.$lightsOnWithCamera
            .sink { [weak self] enabled in
                self?.cameraDetector.updateMonitoring(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleLights) { [weak self] in
            Task { @MainActor in
                await self?.deviceManager.toggleAllLights()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .increaseBrightness) { [weak self] in
            Task { @MainActor in
                guard let deviceManager = self?.deviceManager else { return }
                let currentBrightness = deviceManager.devices
                    .filter(\.isOnline)
                    .map(\.brightness)
                    .max() ?? 0
                let newBrightness = min(currentBrightness + 10, 100)
                await deviceManager.setAllLightsBrightness(newBrightness)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .decreaseBrightness) { [weak self] in
            Task { @MainActor in
                guard let deviceManager = self?.deviceManager else { return }
                let currentBrightness = deviceManager.devices
                    .filter(\.isOnline)
                    .map(\.brightness)
                    .max() ?? 0
                let newBrightness = max(currentBrightness - 10, 0)
                await deviceManager.setAllLightsBrightness(newBrightness)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .increaseTemperature) { [weak self] in
            Task { @MainActor in
                guard let deviceManager = self?.deviceManager else { return }

                // Disable night shift sync when manually adjusting temperature
                if let self, self.appState.syncWithNightShift {
                    self.appState.syncWithNightShift = false
                }

                let currentTemp = deviceManager.devices
                    .filter(\.isOnline)
                    .map(\.temperature)
                    .max() ?? 4000
                let newTemp = min(currentTemp + 500, 7000)
                await deviceManager.setAllLightsTemperature(newTemp)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .decreaseTemperature) { [weak self] in
            Task { @MainActor in
                guard let deviceManager = self?.deviceManager else { return }

                // Disable night shift sync when manually adjusting temperature
                if let self, self.appState.syncWithNightShift {
                    self.appState.syncWithNightShift = false
                }

                let currentTemp = deviceManager.devices
                    .filter(\.isOnline)
                    .map(\.temperature)
                    .max() ?? 4000
                let newTemp = max(currentTemp - 500, 2900)
                await deviceManager.setAllLightsTemperature(newTemp)
            }
        }
    }
}

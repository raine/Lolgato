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

    init() {
        lightsOnWithCamera = UserDefaults.standard.bool(forKey: "lightsOnWithCamera")
        lightsOffOnSleep = UserDefaults.standard.bool(forKey: "lightsOffOnSleep")
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
        deviceManager.startDiscovery()
        setupControllers()
        setupBindings()
        setupShortcuts()
    }

    private func setupControllers() {
        _ = lightCameraController
        _ = lightSystemStateController
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
            Task {
                await self?.deviceManager.toggleAllLights()
            }
        }
    }
}

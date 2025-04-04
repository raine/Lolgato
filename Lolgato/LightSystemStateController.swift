import AppKit
import Combine
import Foundation
import os

class LightSystemStateController {
    private let deviceManager: ElgatoDeviceManager
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "LightSystemStateController"
    )
    private var screenLockMonitor: Any?
    private var lightsWereTurnedOff = false

    init(deviceManager: ElgatoDeviceManager, appState: AppState) {
        self.deviceManager = deviceManager
        self.appState = appState
        setupSubscriptions()
        setupNotificationObservers()
        setupScreenLockMonitor()
    }

    private func setupSubscriptions() {
        appState.$lightsOffOnSleep
            .sink { [weak self] newValue in
                self?.handleLightsOffOnSleepChange(newValue)
            }
            .store(in: &cancellables)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemStateChange),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemStateChange),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWakeUp),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWakeUp),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    private func setupScreenLockMonitor() {
        let distributed = DistributedNotificationCenter.default()
        screenLockMonitor = distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenLock()
        }

        distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWakeUp(notification: Notification(name: Notification.Name("screenUnlock")))
        }
    }

    deinit {
        if let screenLockMonitor = screenLockMonitor {
            DistributedNotificationCenter.default().removeObserver(screenLockMonitor)
        }
    }

    private func handleLightsOffOnSleepChange(_ newValue: Bool) {
        logger.info("Lights off on sleep setting changed to: \(newValue, privacy: .public)")
    }

    @objc private func handleSystemStateChange(notification: Notification) {
        guard appState.lightsOffOnSleep else { return }
        let reason: String
        switch notification.name {
        case NSWorkspace.willSleepNotification:
            reason = "computer sleep"
        case NSWorkspace.screensDidSleepNotification:
            reason = "screen sleep"
        default:
            reason = "unknown reason"
        }
        logger.info("System state changed due to \(reason, privacy: .public). Turning off lights.")
        turnOffAllLights(reason: reason)
    }

    private func handleScreenLock() {
        guard appState.lightsOffOnSleep else { return }
        logger.info("Screen locked. Turning off lights.")
        turnOffAllLights(reason: "screen lock")
    }

    private func turnOffAllLights(reason: String) {
        let onlineDevices = deviceManager.devices.filter { $0.isOnline && $0.isManaged }

        guard !onlineDevices.isEmpty else { return }

        Task {
            var anyLightWasTurnedOff = false
            for device in onlineDevices {
                do {
                    try await device.fetchLightInfo()
                    if device.isOn {
                        try await device.turnOff()
                        anyLightWasTurnedOff = true
                        logger
                            .info(
                                "Turned off device: \(device.name, privacy: .public) due to \(reason, privacy: .public)"
                            )
                    } else {
                        logger
                            .info(
                                "Device already off: \(device.name, privacy: .public)"
                            )
                    }
                } catch {
                    logger
                        .error(
                            "Failed to turn off device: \(device.name) due to \(reason). Error: \(error.localizedDescription)"
                        )
                }
            }

            lightsWereTurnedOff = anyLightWasTurnedOff
            if anyLightWasTurnedOff {
                logger.info("Successfully turned off lights that were previously on")
            } else {
                logger.info("No lights needed to be turned off")
            }
        }
    }

    @objc private func handleWakeUp(notification: Notification) {
        guard appState.lightsOffOnSleep else { return }
        guard lightsWereTurnedOff else { return }

        let reason: String
        switch notification.name {
        case NSWorkspace.didWakeNotification:
            reason = "computer wake"
        case NSWorkspace.screensDidWakeNotification:
            reason = "screen wake"
        default:
            reason = "unknown reason"
        }

        logger.info("System waking up due to \(reason, privacy: .public). Turning on lights.")

        for device in deviceManager.devices where device.isOnline && device.isManaged {
            Task {
                do {
                    try await device.turnOn()
                    logger
                        .info(
                            "Turned on device: \(device.name, privacy: .public) due to \(reason, privacy: .public)"
                        )
                } catch {
                    logger
                        .error(
                            "Failed to turn on device: \(device.name) due to \(reason). Error: \(error.localizedDescription)"
                        )
                }
            }
        }

        lightsWereTurnedOff = false
    }
}

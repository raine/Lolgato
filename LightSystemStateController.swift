import AppKit
import Combine
import Foundation
import os

class LightSystemStateController {
    private let deviceManager: ElgatoDeviceManager
    private let appDelegate: AppDelegate
    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "LightSystemStateController"
    )
    private var screenLockMonitor: Any?

    init(deviceManager: ElgatoDeviceManager, appDelegate: AppDelegate) {
        self.deviceManager = deviceManager
        self.appDelegate = appDelegate
        setupSubscriptions()
        setupNotificationObservers()
        setupScreenLockMonitor()
    }

    private func setupSubscriptions() {
        appDelegate.$lightsOffOnSleep
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
    }

    deinit {
        if let screenLockMonitor = screenLockMonitor {
            DistributedNotificationCenter.default().removeObserver(screenLockMonitor)
        }
    }

    private func handleLightsOffOnSleepChange(_ newValue: Bool) {
        logger.info("Lights off on sleep setting changed to: \(newValue)")
    }

    @objc private func handleSystemStateChange(notification: Notification) {
        guard appDelegate.lightsOffOnSleep else { return }
        let reason: String
        switch notification.name {
        case NSWorkspace.willSleepNotification:
            reason = "computer sleep"
        case NSWorkspace.screensDidSleepNotification:
            reason = "screen sleep"
        default:
            reason = "unknown reason"
        }
        logger.info("System state changed due to \(reason). Turning off lights.")
        turnOffAllLights(reason: reason)
    }

    private func handleScreenLock() {
        guard appDelegate.lightsOffOnSleep else { return }
        logger.info("Screen locked. Turning off lights.")
        turnOffAllLights(reason: "screen lock")
    }

    private func turnOffAllLights(reason: String) {
        for device in deviceManager.devices where device.isOnline {
            Task {
                do {
                    try await device.turnOff()
                    logger
                        .info(
                            "Turned off device: \(device.name) due to \(reason)"
                        )
                } catch {
                    logger
                        .error(
                            "Failed to turn off device: \(device.name) due to \(reason). Error: \(error.localizedDescription)"
                        )
                }
            }
        }
    }
}

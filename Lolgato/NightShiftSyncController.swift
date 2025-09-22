import Combine
import Foundation
import os

// MARK: - CoreBrightness Private API with Dynamic Loading

// The CBBlueLightStatus is a C struct that contains Night Shift state.
// We interact with it using raw memory pointers.

// MARK: - NightShiftSyncController

class NightShiftSyncController {
    private let deviceManager: ElgatoDeviceManager
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "NightShiftSyncController"
    )

    private var blueLightClient: AnyObject?
    private var lastSyncedTemperature: Int = 0
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var syncTimer: Timer?

    init(deviceManager: ElgatoDeviceManager, appState: AppState) {
        self.deviceManager = deviceManager
        self.appState = appState

        // Dynamically load CoreBrightness framework
        loadCoreBrightnessFramework()

        setupSubscriptions()

        // Start polling immediately if enabled
        if appState.syncWithNightShift {
            startPeriodicSync()
            updateLightTemperatureForNightShift()
        }
    }

    private func loadCoreBrightnessFramework() {
        let frameworkPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        frameworkHandle = dlopen(frameworkPath, RTLD_NOW)

        if frameworkHandle == nil {
            logger.error("Failed to load CoreBrightness framework")
            return
        }

        // Get the CBBlueLightClient class dynamically
        guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            logger.error("Failed to find CBBlueLightClient class")
            return
        }

        // Create an instance
        blueLightClient = clientClass.init()
        logger.info("Successfully loaded CoreBrightness framework and created CBBlueLightClient")
    }

    private func setupSubscriptions() {
        appState.$syncWithNightShift
            .sink { [weak self] enabled in
                self?.logger.info("Night Shift sync setting changed to: \(enabled, privacy: .public)")
                if enabled {
                    self?.startPeriodicSync()
                    self?.updateLightTemperatureForNightShift()
                } else {
                    self?.stopPeriodicSync()
                }
            }
            .store(in: &cancellables)
    }

    private func startPeriodicSync() {
        guard appState.syncWithNightShift else { return }

        // Stop existing timer if any
        stopPeriodicSync()

        // Check every second for immediate Night Shift syncing
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateLightTemperatureForNightShift()
        }

        logger.info("Started periodic Night Shift sync (every 1 second)")
    }

    private func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        logger.info("Stopped periodic Night Shift sync")
    }

    private func updateLightTemperatureForNightShift() {
        guard let client = blueLightClient else {
            logger.warning("CBBlueLightClient is not available.")
            return
        }

        // The C-struct based on the header info:
        // StatusData struct layout:
        //   - active: Bool (1 byte)
        //   - enabled: Bool (1 byte)
        //   - sunSchedulePermitted: Bool (1 byte)
        //   - 1 byte padding
        //   - mode: Int32 (4 bytes)
        //   - schedule.from: { hour: Int32, minute: Int32 } (8 bytes)
        //   - schedule.to: { hour: Int32, minute: Int32 } (8 bytes)
        //   - disableFlags: UInt64 (8 bytes)
        // Total: 32 bytes (but we'll allocate extra for safety)
        let statusSize = 48
        let statusPtr = UnsafeMutableRawPointer.allocate(byteCount: statusSize, alignment: MemoryLayout<Int>.alignment)
        defer { statusPtr.deallocate() }
        statusPtr.initializeMemory(as: UInt8.self, repeating: 0, count: statusSize)

        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else {
            logger.error("getBlueLightStatus: method not found")
            return
        }

        // To call a method that expects a C struct pointer, we must get its C-style function implementation (IMP).
        guard let methodIMP = client.method(for: selector) else {
            logger.error("Could not get IMP for getBlueLightStatus:")
            return
        }

        // Define the function signature for the IMP and cast it.
        typealias GetStatusFunc = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let getStatus = unsafeBitCast(methodIMP, to: GetStatusFunc.self)

        // Call the function with the pointer to our memory.
        guard getStatus(client, selector, statusPtr) else {
            logger.error("Failed to get Night Shift status (method returned false).")
            return
        }

        // Read the data from the pointer using the correct layout and offsets.
        let active = statusPtr.load(as: Bool.self)
        let enabled = statusPtr.load(fromByteOffset: 1, as: Bool.self)
        let _ = statusPtr.load(fromByteOffset: 2, as: Bool.self) // sunSchedulePermitted - not used
        let mode = statusPtr.load(fromByteOffset: 4, as: Int32.self)

        // For now, we'll check if it's enabled and active
        logger.info("Night Shift - Active: \(active), Enabled: \(enabled), Mode: \(mode)")

        if !enabled || !active {
            logger.info("Night Shift is not active. Reverting to default temperature.")
            // When Night Shift is disabled, revert to a neutral temperature
            let defaultTemperature = 6500 // Neutral daylight temperature
            if lastSyncedTemperature != defaultTemperature {
                lastSyncedTemperature = defaultTemperature
                Task { @MainActor in
                    await deviceManager.setAllLightsTemperature(defaultTemperature)
                }
            }
            return
        }

        // Try to get the strength value which determines warmth
        var strength: Float = 0.0 // Default value if call fails
        let getStrengthSelector = NSSelectorFromString("getStrength:")

        if client.responds(to: getStrengthSelector) {
            guard let methodIMP = client.method(for: getStrengthSelector) else {
                logger.error("Could not get IMP for getStrength:")
                return
            }

            // Define the function signature for getStrength: - (BOOL)getStrength:(float*)strength;
            typealias GetStrengthFunc = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
            let getStrength = unsafeBitCast(methodIMP, to: GetStrengthFunc.self)

            // Call the function directly with pointer to strength
            let success = getStrength(client, getStrengthSelector, &strength)

            if success {
                logger.info("Night Shift strength: \(strength)")
            } else {
                logger.warning("getStrength: returned false, using default strength")
                strength = 0.5 // Default to medium warmth
            }
        } else {
            logger.warning("getStrength: method not found, using default strength")
            strength = 0.5 // Default to medium warmth
        }

        // Map strength (0.0-1.0) to color temperature
        // 0.0 = least warm (6500K), 1.0 = most warm (2900K - Elgato's warmest)
        let minTemp = 2900  // Warmest possible on Elgato
        let maxTemp = 6500  // Cool/neutral white
        let nightShiftKelvin = Int(Float(maxTemp) - (strength * Float(maxTemp - minTemp)))

        // Clamp the temperature to the range supported by Elgato devices
        let elgatoKelvin = max(2900, min(7000, nightShiftKelvin))

        // Only update if the temperature has changed (avoid unnecessary updates)
        if lastSyncedTemperature != elgatoKelvin {
            logger.info("Night Shift temperature changed: \(nightShiftKelvin)K (strength: \(strength)) → Elgato: \(elgatoKelvin)K")
            lastSyncedTemperature = elgatoKelvin
            Task { @MainActor in
                await deviceManager.setAllLightsTemperature(elgatoKelvin)
            }
        }
    }

    deinit {
        stopPeriodicSync()

        if let handle = frameworkHandle {
            dlclose(handle)
        }
        logger.info("NightShiftSyncController deinitialized and cleaned up resources.")
    }
}
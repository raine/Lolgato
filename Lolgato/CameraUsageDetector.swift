import AVFoundation
import Combine
import CoreMediaIO
import os

class CameraUsageDetector {
    private var timer: Timer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CameraUsageDetector")
    private var lastActiveState: Bool?
    private var isMonitoringEnabled: Bool = false

    private let cameraStatusSubject = CurrentValueSubject<Bool, Never>(false)
    var cameraStatusPublisher: AnyPublisher<Bool, Never> {
        cameraStatusSubject.eraseToAnyPublisher()
    }

    enum CameraError: Error {
        case failedToGetDevices(OSStatus)
        case allDevicesFailed
        case noDevicesFound
    }

    func updateMonitoring(enabled: Bool, interval: TimeInterval = 1.0) {
        isMonitoringEnabled = enabled

        if enabled {
            logger.info("Starting camera polling")
            ensureCameraAccess { [weak self] granted in
                guard let self, granted, self.isMonitoringEnabled else {
                    self?.logger.warning("Camera access not granted, cannot monitor camera usage")
                    return
                }
                self.startMonitoring(interval: interval)
            }
        } else {
            logger.info("Stopping camera polling")
            stopMonitoring()
        }
    }

    private func ensureCameraAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { completion(true) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            DispatchQueue.main.async { completion(false) }
        }
    }
    
    private func startMonitoring(interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkCameraStatus()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        lastActiveState = nil
    }

    private func checkCameraStatus() {
        guard isMonitoringEnabled else { return }

        do {
            let isActive = try isCameraOn()
            if isActive != lastActiveState {
                lastActiveState = isActive
                cameraStatusSubject.send(isActive)
            }
        } catch {
            logger.error("Error checking camera status: \(error.localizedDescription, privacy: .public)")
            if lastActiveState != false {
                lastActiveState = false
                cameraStatusSubject.send(false)
            }
        }
    }

    private func isCameraOn() throws -> Bool {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        var dataUsed: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard result == kCMIOHardwareNoError else {
            throw CameraError.failedToGetDevices(result)
        }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        guard deviceCount > 0 else {
            throw CameraError.noDevicesFound
        }

        var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
        result = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &dataUsed,
            &devices
        )
        guard result == kCMIOHardwareNoError else {
            throw CameraError.failedToGetDevices(result)
        }

        var failedDeviceCount = 0
        for device in devices {
            if let isUsed = isDeviceInUse(device) {
                if isUsed {
                    return true
                }
            } else {
                failedDeviceCount += 1
            }
        }

        if failedDeviceCount == deviceCount {
            throw CameraError.allDevicesFailed
        }

        return false
    }

    private func isDeviceInUse(_ device: CMIODeviceID) -> Bool? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var isUsed: UInt32 = 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        var dataUsed: UInt32 = 0
        let result = CMIOObjectGetPropertyData(device, &propertyAddress, 0, nil, dataSize, &dataUsed, &isUsed)
        if result == kCMIOHardwareNoError {
            return isUsed != 0
        } else {
            logger.error("Failed to get device usage status: \(result, privacy: .public)")
            return nil
        }
    }
}

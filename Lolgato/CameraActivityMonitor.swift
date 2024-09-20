import AVFoundation
import CoreMediaIO

class CameraUsageDetector {
    private var timer: Timer?
    private var callback: ((Bool) -> Void)?

    enum CameraError: Error {
        case failedToGetDevices(OSStatus)
        case allDevicesFailed
        case noDevicesFound
    }

    func startMonitoring(interval: TimeInterval = 1.0, callback: @escaping (Bool) -> Void) {
        self.callback = callback
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkCameraStatus()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkCameraStatus() {
        do {
            let isActive = try isCameraOn()
            callback?(isActive)
        } catch {
            print("Error checking camera status: \(error)")
            callback?(false)
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
        print("Number of devices found: \(deviceCount)")

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

        for (index, device) in devices.enumerated() {
            print("Checking device \(index + 1) of \(deviceCount)")
            if let isUsed = isDeviceInUse(device) {
                if isUsed {
                    print("Device \(index + 1) is in use")
                    return true
                }
            } else {
                failedDeviceCount += 1
            }
        }

        if failedDeviceCount == deviceCount {
            throw CameraError.allDevicesFailed
        }

        print("No devices are currently in use")
        return false
    }

    private func isDeviceInUse(_ device: CMIODeviceID) -> Bool? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        var isUsed: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var dataUsed: UInt32 = 0

        let result = CMIOObjectGetPropertyData(device, &propertyAddress, 0, nil, dataSize, &dataUsed, &isUsed)

        if result == kCMIOHardwareNoError {
            return isUsed != 0
        } else {
            print("Failed to get device usage status: \(result)")
            return nil
        }
    }
}

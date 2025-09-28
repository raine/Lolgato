import AVFoundation
import CoreMediaIO
import Foundation
import os

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct StoredCameraInfo: Codable, Equatable {
    var id: String
    var name: String
}

class CameraManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CameraManager")

    static func getAvailableCameras() -> [CameraDevice] {
        // Use AVFoundation approach first as it's more reliable
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        var cameras = discoverySession.devices.map { device in
            CameraDevice(id: device.uniqueID, name: device.localizedName)
        }

        // Fallback to CoreMediaIO only if necessary
        if cameras.isEmpty {
            logger.warning("AVFoundation found no cameras, falling back to CoreMediaIO.")
            cameras = getCamerasUsingCoreMediaIO()
        }

        logger.info("Found \(cameras.count) camera(s)")
        return cameras
    }

    private static func getCamerasUsingCoreMediaIO() -> [CameraDevice] {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard result == kCMIOHardwareNoError, dataSize > 0 else {
            logger.error("CoreMediaIO: Failed to get size of device list or no devices found. Error: \(result)")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
        var dataUsed: UInt32 = 0

        result = CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &propertyAddress, 0, nil, dataSize, &dataUsed, &devices)
        guard result == kCMIOHardwareNoError else {
            logger.error("CoreMediaIO: Failed to get device list. Error: \(result)")
            return []
        }

        return devices.compactMap { deviceID in
            guard let name: String = getProperty(for: deviceID, selector: CMIOObjectPropertySelector(kCMIOObjectPropertyName)),
                  let uniqueID: String = getProperty(for: deviceID, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
            else {
                return nil
            }
            return CameraDevice(id: uniqueID, name: name)
        }
    }

    private static func getProperty<T>(for deviceID: CMIODeviceID, selector: CMIOObjectPropertySelector) -> T? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: kCMIOObjectPropertyScopeWildcard,
            mElement: kCMIOObjectPropertyElementWildcard
        )

        var dataSize: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard result == kCMIOHardwareNoError, dataSize > 0 else {
            return nil
        }

        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<UInt8>.alignment)
        defer { data.deallocate() }

        var dataUsed: UInt32 = 0
        result = CMIOObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &dataUsed, data)
        guard result == kCMIOHardwareNoError else {
            return nil
        }

        if T.self == String.self {
            return String(cString: data.assumingMemoryBound(to: CChar.self)) as? T
        } else {
            return data.load(as: T.self)
        }
    }
}

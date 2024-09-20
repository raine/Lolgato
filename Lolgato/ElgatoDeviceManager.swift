import Foundation
import Network
import os

struct WifiInfo: Codable {
    let ssid: String
    let frequencyMHz: Int
    let rssi: Int
}

class ElgatoDevice: Identifiable, Equatable {
    let endpoint: NWEndpoint
    var isOnline: Bool = true
    var lastSeen: Date = .init()

    var productName: String
    var hardwareBoardType: Int
    var hardwareRevision: Double
    var macAddress: String
    var firmwareBuildNumber: Int
    var firmwareVersion: String
    var serialNumber: String
    var displayName: String?
    var features: [String]
    var wifiInfo: WifiInfo?

    var id: NWEndpoint { endpoint }

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
        productName = ""
        hardwareBoardType = 0
        hardwareRevision = 0.0
        macAddress = ""
        firmwareBuildNumber = 0
        firmwareVersion = ""
        serialNumber = ""
        displayName = ""
        features = []
    }

    static func == (lhs: ElgatoDevice, rhs: ElgatoDevice) -> Bool {
        lhs.endpoint == rhs.endpoint
    }

    enum FetchError: Error {
        case invalidEndpoint
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case missingRequiredField(String)
    }

    func fetchAccessoryInfo() async throws {
        guard case let .hostPort(host, port) = endpoint else {
            throw FetchError.invalidEndpoint
        }

        let cleanHost = host.debugDescription.split(separator: "%").first.map(String.init) ?? host
            .debugDescription
        let urlString = "http://\(cleanHost):\(port)/elgato/accessory-info"
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

            guard let json = json else {
                throw FetchError.invalidResponse
            }

            // Use a helper function to safely extract values and throw if missing
            func extract<T>(_ key: String) throws -> T {
                guard let value = json[key] as? T else {
                    throw FetchError.missingRequiredField(key)
                }
                return value
            }

            productName = try extract("productName")
            hardwareBoardType = try extract("hardwareBoardType")
            hardwareRevision = try extract("hardwareRevision")
            macAddress = try extract("macAddress")
            firmwareBuildNumber = try extract("firmwareBuildNumber")
            firmwareVersion = try extract("firmwareVersion")
            serialNumber = try extract("serialNumber")
            if let displayNameValue: String = try? extract("displayName") {
                displayName = displayNameValue.isEmpty ? nil : displayNameValue
            } else {
                displayName = nil
            }
            features = try extract("features")

            if let wifiInfoDict: [String: Any] = try? extract("wifi-info") {
                wifiInfo = WifiInfo(
                    ssid: wifiInfoDict["ssid"] as? String ?? "",
                    frequencyMHz: wifiInfoDict["frequencyMHz"] as? Int ?? 0,
                    rssi: wifiInfoDict["rssi"] as? Int ?? 0
                )
            }
        } catch {
            throw FetchError.networkError(error)
        }
    }
}

class ElgatoDeviceManager: ObservableObject {
    @Published private(set) var devices: [ElgatoDevice] = []
    private let discovery: ElgatoDiscovery
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDeviceManager")

    init(discovery: ElgatoDiscovery) {
        self.discovery = discovery
    }

    func performDiscovery() async {
        let results = await discovery.startDiscovery()
        await updateDevices(with: results)
    }

    @MainActor
    private func updateDevices(with results: [NWEndpoint]) {
        let currentDate = Date()

        // Update existing devices and add new ones
        for endpoint in results {
            if let existingDevice = devices.first(where: { $0.endpoint == endpoint }) {
                existingDevice.isOnline = true
                existingDevice.lastSeen = currentDate
            } else {
                let newDevice = ElgatoDevice(endpoint: endpoint)
                newDevice.lastSeen = currentDate

                logger.info("New device found: \(endpoint.debugDescription)")
                devices.append(newDevice)

                // Fetch accessory info for new device
                Task {
                    do {
                        try await newDevice.fetchAccessoryInfo()
                        logger
                            .info(
                                "Accessory info fetched for device: \(newDevice.displayName ?? newDevice.productName)"
                            )
                    } catch {
                        logger
                            .error(
                                "Failed to fetch accessory info for device: \(endpoint.debugDescription), error: \(error.localizedDescription)"
                            )
                    }
                    self.objectWillChange.send()
                }
            }
        }

        // Mark devices as offline if not seen in this discovery round
        for device in devices where device.lastSeen != currentDate {
            device.isOnline = false
        }

        // Remove devices not seen for a long time (e.g., 24 hours)
        let removalThreshold = currentDate.addingTimeInterval(-24 * 60 * 60)
        devices.removeAll { $0.lastSeen < removalThreshold }

        objectWillChange.send()
    }

    func stopDiscovery() {
        discovery.stopDiscovery()
    }
}

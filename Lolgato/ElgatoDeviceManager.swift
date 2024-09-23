import Combine
import Foundation
import Network
import os

struct WifiInfo: Codable {
    let ssid: String
    let frequencyMHz: Int
    let rssi: Int
}

class ElgatoDevice: Identifiable, Equatable, Hashable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDevice")

    let endpoint: NWEndpoint
    var isOnline: Bool = true
    var lastSeen: Date = .init()
    var isOn: Bool = false

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

    var name: String { displayName ?? productName }

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

    func hash(into hasher: inout Hasher) {
        hasher.combine(endpoint)
    }

    enum FetchError: Error {
        case invalidEndpoint
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case missingRequiredField(String)
    }

    func fetchLightInfo() async throws {
        struct LightResponse: Codable {
            let numberOfLights: Int
            let lights: [LightStatus]
        }

        struct LightStatus: Codable {
            let on: Int
            let brightness: Int
            let temperature: Int
        }

        guard case let .hostPort(host, port) = endpoint else {
            throw FetchError.invalidEndpoint
        }

        let cleanHost = host.debugDescription.split(separator: "%").first.map(String.init) ?? host
            .debugDescription
        let urlString = "http://\(cleanHost):\(port)/elgato/lights"
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidURL
        }

        do {
            logger.info("GET \(url)")
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(LightResponse.self, from: data)

            guard let lightStatus = json.lights.first else {
                throw FetchError.invalidResponse
            }

            isOn = lightStatus.on == 1
        } catch _ as DecodingError {
            throw FetchError.invalidResponse
        } catch {
            throw FetchError.networkError(error)
        }
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
            logger.info("GET \(url)")
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

    enum LightControlError: Error {
        case invalidEndpoint
        case networkError(Error)
        case invalidResponse
    }

    func turnOn() async throws {
        try await setLightState(on: true)
    }

    func turnOff() async throws {
        try await setLightState(on: false)
    }

    private func setLightState(on: Bool) async throws {
        guard case let .hostPort(host, port) = endpoint else {
            throw LightControlError.invalidEndpoint
        }

        let cleanHost = host.debugDescription.split(separator: "%").first.map(String.init) ?? host
            .debugDescription
        let urlString = "http://\(cleanHost):\(port)/elgato/lights"
        guard let url = URL(string: urlString) else {
            throw LightControlError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = ["numberOfLights": 1, "lights": [["on": on ? 1 : 0]]] as [String: Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]

            guard let lights = json?["lights"] as? [[String: Any]],
                  let firstLight = lights.first,
                  let isOn = firstLight["on"] as? Int
            else {
                throw LightControlError.invalidResponse
            }

            self.isOn = (isOn == 1)
        } catch {
            throw LightControlError.networkError(error)
        }
    }
}

class ElgatoDeviceManager: ObservableObject {
    @Published private(set) var devices: [ElgatoDevice] = []
    private let discovery: ElgatoDiscovery
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDeviceManager")
    private var discoveryTask: Task<Void, Never>?
    let newDeviceDiscovered = PassthroughSubject<ElgatoDevice, Never>()

    init(discovery: ElgatoDiscovery) {
        self.discovery = discovery
    }

    func startDiscovery() {
        guard discoveryTask == nil else {
            logger.info("Discovery is already running")
            return
        }

        discoveryTask = Task {
            do {
                for try await event in discovery {
                    await handleDiscoveryEvent(event)
                }
            } catch {
                logger.error("Discovery stream ended with error: \(error.localizedDescription)")
            }
            logger.info("Discovery stream ended")
            self.discoveryTask = nil
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        discovery.stopDiscovery()
    }

    @MainActor
    private func handleDiscoveryEvent(_ event: ElgatoDiscoveryEvent) {
        logger.info("Discovery event: \(event.debugDescription)")

        switch event {
        case let .deviceFound(endpoint):
            addOrUpdateDevice(for: endpoint)
        case let .deviceLost(endpoint):
            markDeviceOffline(for: endpoint)
        case let .error(error):
            logger.error("Discovery error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func addOrUpdateDevice(for endpoint: NWEndpoint) {
        if let existingDevice = devices.first(where: { $0.endpoint == endpoint }) {
            existingDevice.isOnline = true
            existingDevice.lastSeen = Date()
        } else {
            let newDevice = ElgatoDevice(endpoint: endpoint)
            newDevice.lastSeen = Date()

            logger.info("New device found: \(endpoint.debugDescription)")
            devices.append(newDevice)

            newDeviceDiscovered.send(newDevice)

            Task {
                await fetchAccessoryInfo(for: newDevice)
            }
        }
        objectWillChange.send()
    }

    @MainActor
    private func markDeviceOffline(for endpoint: NWEndpoint) {
        if let device = devices.first(where: { $0.endpoint == endpoint }) {
            device.isOnline = false
            logger.info("Device went offline: \(endpoint.debugDescription)")
            objectWillChange.send()
        }
    }

    private func fetchAccessoryInfo(for device: ElgatoDevice) async {
        do {
            try await device.fetchAccessoryInfo()
            await MainActor.run {
                logger.info("Accessory info fetched for device: \(device.displayName ?? device.productName)")
                self.objectWillChange.send()
            }
        } catch {
            await MainActor.run {
                logger
                    .error(
                        "Failed to fetch accessory info for device: \(device.endpoint.debugDescription), error: \(error.localizedDescription)"
                    )
            }
        }
    }

    @MainActor
    func removeStaleDevices() {
        let removalThreshold = Date().addingTimeInterval(-24 * 60 * 60)
        devices.removeAll { $0.lastSeen < removalThreshold }
        objectWillChange.send()
    }

    @MainActor
    func toggleAllLights() async {
        logger.info("Toggling all lights")

        let onlineDevices = devices.filter { $0.isOnline }

        // First, update the status of all online devices
        await withTaskGroup(of: Void.self) { group in
            for device in onlineDevices {
                group.addTask {
                    do {
                        try await device.fetchLightInfo()
                        await MainActor.run {
                            self.logger
                                .info(
                                    "Updated status for device \(device.name): \(device.isOn ? "on" : "off")"
                                )
                        }
                    } catch {
                        await MainActor.run {
                            self.logger
                                .error(
                                    "Failed to update status for device \(device.name): \(error.localizedDescription)"
                                )
                        }
                    }
                }
            }
        }

        // Determine the action based on the current state of the lights
        let anyLightOn = onlineDevices.contains { $0.isOn }
        let actionIsOff = anyLightOn

        // Now toggle the lights based on the determined action
        await withTaskGroup(of: Void.self) { group in
            for device in onlineDevices {
                group.addTask {
                    do {
                        if actionIsOff {
                            if device.isOn {
                                try await device.turnOff()
                                await MainActor.run {
                                    self.logger.info("Turned off device \(device.name)")
                                }
                            }
                        } else {
                            if !device.isOn {
                                try await device.turnOn()
                                await MainActor.run {
                                    self.logger.info("Turned on device \(device.name)")
                                }
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.logger
                                .error(
                                    "Failed to toggle device \(device.name): \(error.localizedDescription)"
                                )
                        }
                    }
                }
            }
        }

        objectWillChange.send()
    }
}

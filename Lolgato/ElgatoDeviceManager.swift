import Combine
import Foundation
import Network
import os

class ElgatoDevice: ObservableObject, Identifiable, Equatable, Hashable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDevice")

    let endpoint: NWEndpoint
    var isOnline: Bool = true
    var lastSeen: Date = .init()
    var isOn: Bool = false

    @Published var productName: String
    @Published var displayName: String?
    @Published var brightness: Int = 0
    @Published var temperature: Int = 4000 // Temperature in Kelvin
    private var internalTemp: Int = 244 // Internal Elgato scale (143-344)
    var macAddress: String

    var id: NWEndpoint { endpoint }

    var name: String {
        displayName ?? productName
    }

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
        productName = ""
        macAddress = ""
        displayName = ""
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
            logger.info("GET \(url, privacy: .public)")
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(LightResponse.self, from: data)

            guard let lightStatus = json.lights.first else {
                throw FetchError.invalidResponse
            }

            await MainActor.run {
                self.isOn = lightStatus.on == 1
                self.brightness = lightStatus.brightness
                self.internalTemp = lightStatus.temperature
                self.temperature = self.kelvinFromInternal(lightStatus.temperature)
            }
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

        guard let url = URL.createFromNetworkEndpoint(host: host, port: port, path: "/elgato/accessory-info")
        else {
            throw FetchError.invalidURL
        }

        do {
            logger.info("GET \(url, privacy: .public)")
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

            guard let json = json else {
                throw FetchError.invalidResponse
            }

            func extract<T>(_ key: String) throws -> T {
                guard let value = json[key] as? T else {
                    logger.error("Missing required field '\(key, privacy: .public)' in response")
                    throw FetchError.missingRequiredField(key)
                }
                return value
            }

            productName = try extract("productName")
            macAddress = try extract("macAddress")
            if let displayNameValue: String = try? extract("displayName") {
                displayName = displayNameValue.isEmpty ? nil : displayNameValue
            } else {
                displayName = nil
            }
        } catch {
            throw FetchError.networkError(error)
        }
    }

    enum LightControlError: Error {
        case invalidEndpoint
        case invalidURL
        case networkError(Error)
        case invalidResponse
    }

    func turnOn() async throws {
        try await setLightState(on: true)
    }

    func turnOff() async throws {
        try await setLightState(on: false)
    }

    func setBrightness(_ level: Int) async throws {
        guard (0 ... 100).contains(level) else {
            logger.error("Invalid brightness level: \(level). Must be 0-100")
            return
        }

        guard case let .hostPort(host, port) = endpoint else {
            throw LightControlError.invalidEndpoint
        }

        guard let url = URL.createFromNetworkEndpoint(host: host, port: port, path: "/elgato/lights") else {
            throw LightControlError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = ["numberOfLights": 1, "lights": [["brightness": level]]] as [String: Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]

            guard let lights = json?["lights"] as? [[String: Any]],
                  let firstLight = lights.first,
                  let brightness = firstLight["brightness"] as? Int
            else {
                throw LightControlError.invalidResponse
            }

            await MainActor.run {
                self.brightness = brightness
            }
        } catch {
            throw LightControlError.networkError(error)
        }
    }

    func increaseBrightness(by amount: Int) async throws {
        try await fetchLightInfo()
        let newBrightness = min(brightness + amount, 100)
        try await setBrightness(newBrightness)
    }

    func decreaseBrightness(by amount: Int) async throws {
        try await fetchLightInfo()
        let newBrightness = max(brightness - amount, 0)
        try await setBrightness(newBrightness)
    }

    private func internalFromKelvin(_ kelvin: Int) -> Int {
        return Int(round(987_007 * pow(Double(kelvin), -0.999)))
    }

    private func kelvinFromInternal(_ internal: Int) -> Int {
        let kelvin = round(1_000_000 * pow(Double(`internal`), -1.0) / 100) * 100
        return Int(kelvin)
    }

    func setTemperature(_ kelvin: Int) async throws {
        guard (2900 ... 7000).contains(kelvin) else {
            logger.error("Invalid temperature level: \(kelvin). Must be 2900-7000")
            return
        }

        let internalValue = internalFromKelvin(kelvin)

        guard case let .hostPort(host, port) = endpoint else {
            throw LightControlError.invalidEndpoint
        }

        guard let url = URL.createFromNetworkEndpoint(host: host, port: port, path: "/elgato/lights") else {
            throw LightControlError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = ["numberOfLights": 1, "lights": [["temperature": internalValue]]] as [String: Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]

            guard let lights = json?["lights"] as? [[String: Any]],
                  let firstLight = lights.first,
                  let temperature = firstLight["temperature"] as? Int
            else {
                throw LightControlError.invalidResponse
            }

            await MainActor.run {
                self.internalTemp = temperature
                self.temperature = self.kelvinFromInternal(temperature)
            }
        } catch {
            throw LightControlError.networkError(error)
        }
    }

    func increaseTemperature(by amount: Int) async throws {
        try await fetchLightInfo()
        let newTemp = min(temperature + amount, 7000)
        try await setTemperature(newTemp)
    }

    func decreaseTemperature(by amount: Int) async throws {
        try await fetchLightInfo()
        let newTemp = max(temperature - amount, 2900)
        try await setTemperature(newTemp)
    }

    private func setLightState(on: Bool) async throws {
        guard case let .hostPort(host, port) = endpoint else {
            throw LightControlError.invalidEndpoint
        }

        guard let url = URL.createFromNetworkEndpoint(host: host, port: port, path: "/elgato/lights")
        else {
            throw LightControlError.invalidURL
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

            await MainActor.run {
                self.isOn = (isOn == 1)
            }
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
                logger
                    .error(
                        "Discovery stream ended with error: \(error.localizedDescription, privacy: .public)"
                    )
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
        logger.info("Discovery event: \(event.debugDescription, privacy: .public)")

        switch event {
        case let .deviceFound(endpoint):
            addOrUpdateDevice(for: endpoint)
        case let .deviceLost(endpoint):
            markDeviceOffline(for: endpoint)
        case let .error(error):
            logger.error("Discovery error: \(error.localizedDescription, privacy: .public)")
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

            logger.info("New device found: \(endpoint.debugDescription, privacy: .public)")
            devices.append(newDevice)

            newDeviceDiscovered.send(newDevice)

            Task {
                await fetchInitialDeviceState(for: newDevice)
            }
        }
        objectWillChange.send()
    }

    @MainActor
    private func markDeviceOffline(for endpoint: NWEndpoint) {
        if let device = devices.first(where: { $0.endpoint == endpoint }) {
            device.isOnline = false
            logger.info("Device went offline: \(endpoint.debugDescription, privacy: .public)")
            objectWillChange.send()
        }
    }

    private func fetchInitialDeviceState(for device: ElgatoDevice) async {
        do {
            try await device.fetchAccessoryInfo()
            try await device.fetchLightInfo()

            await MainActor.run {
                logger.info("Initial state fetched for device: \(device.name, privacy: .public)")
                self.objectWillChange.send()
            }
        } catch {
            await MainActor.run {
                logger
                    .error(
                        "Failed to fetch initial state for device: \(device.endpoint.debugDescription, privacy: .public), error: \(error.localizedDescription, privacy: .public)"
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
                                    "Updated status for device \(device.name, privacy: .public): \(device.isOn ? "on" : "off")"
                                )
                        }
                    } catch {
                        await MainActor.run {
                            self.logger
                                .error(
                                    "Failed to update status for device \(device.name, privacy: .public): \(error.localizedDescription)"
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
                                    self.logger.info("Turned off device \(device.name, privacy: .public)")
                                }
                            }
                        } else {
                            if !device.isOn {
                                try await device.turnOn()
                                await MainActor.run {
                                    self.logger.info("Turned on device \(device.name, privacy: .public)")
                                }
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.logger
                                .error(
                                    "Failed to toggle device \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                                )
                        }
                    }
                }
            }
        }

        objectWillChange.send()
    }

    @MainActor
    func setAllLightsBrightness(_ brightness: Int) async {
        logger.info("Setting all lights brightness to \(brightness)")

        let onlineDevices = devices.filter { $0.isOnline }

        await withTaskGroup(of: Void.self) { group in
            for device in onlineDevices {
                group.addTask {
                    do {
                        try await device.setBrightness(brightness)
                        await MainActor.run {
                            self.logger
                                .info(
                                    "Set brightness to \(brightness) for device \(device.name, privacy: .public)"
                                )
                        }
                    } catch {
                        await MainActor.run {
                            self.logger
                                .error(
                                    "Failed to set brightness for device \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                                )
                        }
                    }
                }
            }
        }

        objectWillChange.send()
    }

    @MainActor
    func setAllLightsTemperature(_ temperature: Int) async {
        logger.info("Setting all lights temperature to \(temperature)")

        let onlineDevices = devices.filter { $0.isOnline }

        await withTaskGroup(of: Void.self) { group in
            for device in onlineDevices {
                group.addTask {
                    do {
                        try await device.setTemperature(temperature)
                        await MainActor.run {
                            self.logger
                                .info(
                                    "Set temperature to \(temperature) for device \(device.name, privacy: .public)"
                                )
                        }
                    } catch {
                        await MainActor.run {
                            self.logger
                                .error(
                                    "Failed to set temperature for device \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                                )
                        }
                    }
                }
            }
        }

        objectWillChange.send()
    }

    @MainActor
    func addDeviceManually(ipAddress: String, port: UInt16 = 9123) -> Bool {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDeviceManager")
        logger.info("Attempting to add device manually with IP: \(ipAddress, privacy: .public)")

        // NWEndpoint.Host initializer doesn't return an optional
        let host = NWEndpoint.Host(ipAddress)

        // Validate the IP address format
        if !isValidIPAddress(ipAddress) {
            logger.error("Invalid IP address format: \(ipAddress, privacy: .public)")
            return false
        }

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let endpoint = NWEndpoint.hostPort(host: host, port: nwPort)

        // Check if device with this endpoint already exists
        if devices.contains(where: { $0.endpoint == endpoint }) {
            logger
                .warning(
                    "Device with endpoint \(endpoint.debugDescription, privacy: .public) already exists"
                )
            return false
        }

        // Create a new device
        let newDevice = ElgatoDevice(endpoint: endpoint)
        newDevice.lastSeen = Date()
        newDevice.isOnline = true

        devices.append(newDevice)
        newDeviceDiscovered.send(newDevice)

        // Try to fetch initial device state
        Task {
            await fetchInitialDeviceState(for: newDevice)
        }

        objectWillChange.send()
        logger.info("Manually added device with endpoint: \(endpoint.debugDescription, privacy: .public)")
        return true
    }

    // Helper method to validate IP address format
    private func isValidIPAddress(_ ipAddress: String) -> Bool {
        // Basic IPv4 validation pattern
        let ipv4Pattern =
            #"^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#

        let regex = try? NSRegularExpression(pattern: ipv4Pattern)
        let range = NSRange(location: 0, length: ipAddress.utf16.count)
        return regex?.firstMatch(in: ipAddress, range: range) != nil
    }
}

import Combine
import Foundation
import Network
import os

struct StoredDeviceInfo: Codable {
    let ipAddress: String
    let port: UInt16
    let lastSeen: Date
    let displayName: String?
    let isManaged: Bool
    let order: Int

    init(
        ipAddress: String,
        port: UInt16,
        lastSeen: Date = Date(),
        displayName: String? = nil,
        isManaged: Bool = true,
        order: Int = 0
    ) {
        self.ipAddress = ipAddress
        self.port = port
        self.lastSeen = lastSeen
        self.displayName = displayName
        self.isManaged = isManaged
        self.order = order
    }

    init?(from device: ElgatoDevice) {
        guard case let .hostPort(host, port) = device.endpoint else {
            return nil
        }

        let hostString = host.debugDescription.split(separator: "%").first.map(String.init) ?? host
            .debugDescription
        ipAddress = hostString
        self.port = port.rawValue
        lastSeen = device.lastSeen
        displayName = device.displayName
        isManaged = device.isManaged
        order = device.order
    }
}

class ElgatoDevice: ObservableObject, Identifiable, Equatable, Hashable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDevice")

    let endpoint: NWEndpoint
    var isOnline: Bool = true
    var lastSeen: Date = .init()
    var isOn: Bool = false
    var order: Int = 0

    @Published var productName: String
    @Published var displayName: String?
    @Published var brightness: Int = 0
    @Published var temperature: Int = 4000 // Temperature in Kelvin
    @Published var isManaged: Bool = true // Whether this device is controlled by the app
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

            guard let json else {
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
        Int(round(987_007 * pow(Double(kelvin), -0.999)))
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
    private static let storedDevicesKey = "com.lolgato.storedDevices"

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
        if let existingDevice = devices.first(where: { areEndpointsEquivalent($0.endpoint, endpoint) }) {
            logger.info("Existing device found, not adding: \(endpoint.debugDescription, privacy: .public)")
            existingDevice.isOnline = true
            existingDevice.lastSeen = Date()
        } else {
            let newDevice = ElgatoDevice(endpoint: endpoint)
            newDevice.lastSeen = Date()

            let maxOrder = devices.map(\.order).max() ?? -1
            newDevice.order = maxOrder + 1

            logger.info("New device found: \(endpoint.debugDescription, privacy: .public)")
            devices.append(newDevice)

            newDeviceDiscovered.send(newDevice)

            Task {
                await fetchInitialDeviceState(for: newDevice)
                // Save devices after discovering a new one
                await MainActor.run {
                    saveDevicesToPersistentStorage()
                }
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

        let onlineDevices = devices.filter { $0.isOnline && $0.isManaged }

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

        let onlineDevices = devices.filter { $0.isOnline && $0.isManaged }

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

        let onlineDevices = devices.filter { $0.isOnline && $0.isManaged }

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

    // MARK: - Device Persistence

    @MainActor
    func saveDevicesToPersistentStorage() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DevicePersistence")

        var storedDevices: [StoredDeviceInfo] = []

        for device in devices {
            if let storedInfo = StoredDeviceInfo(from: device) {
                storedDevices.append(storedInfo)
            }
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(storedDevices)
            UserDefaults.standard.set(data, forKey: Self.storedDevicesKey)
            logger.info("Saved \(storedDevices.count) devices to persistent storage")
        } catch {
            logger.error("Failed to save devices: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func loadDevicesFromPersistentStorage() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DevicePersistence")

        guard let data = UserDefaults.standard.data(forKey: Self.storedDevicesKey) else {
            logger.info("No stored devices found")
            return
        }

        do {
            let decoder = JSONDecoder()
            let storedDevices = try decoder.decode([StoredDeviceInfo].self, from: data)

            logger.info("Found \(storedDevices.count) stored devices")

            for storedDevice in storedDevices {
                // Create a new device for each stored entry
                let host = NWEndpoint.Host(storedDevice.ipAddress)
                let port = NWEndpoint.Port(rawValue: storedDevice.port)!
                let endpoint = NWEndpoint.hostPort(host: host, port: port)

                // Skip if device already exists (using new comparison function)
                if devices.contains(where: { areEndpointsEquivalent($0.endpoint, endpoint) }) {
                    logger
                        .info("Skipping already loaded device at \(storedDevice.ipAddress, privacy: .public)")
                    continue
                }

                let newDevice = ElgatoDevice(endpoint: endpoint)
                newDevice.lastSeen = storedDevice.lastSeen
                newDevice.isOnline = false
                newDevice.isManaged = storedDevice.isManaged
                newDevice.order = storedDevice.order
                if let displayName = storedDevice.displayName {
                    newDevice.displayName = displayName
                }

                devices.append(newDevice)

                // Try to fetch the device state
                Task {
                    do {
                        try await newDevice.fetchAccessoryInfo()
                        try await newDevice.fetchLightInfo()
                        await MainActor.run {
                            newDevice.isOnline = true
                            logger.info("Restored device: \(newDevice.name, privacy: .public)")
                            objectWillChange.send()
                        }
                    } catch {
                        logger
                            .warning(
                                "Failed to connect to stored device \(storedDevice.ipAddress, privacy: .public): \(error.localizedDescription, privacy: .public)"
                            )
                    }
                }
            }
        } catch {
            logger.error("Failed to load stored devices: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Manual Device Addition

    @MainActor
    func removeDevice(_ device: ElgatoDevice) {
        logger.info("Removing device: \(device.name, privacy: .public)")

        if let index = devices.firstIndex(where: { $0.endpoint == device.endpoint }) {
            devices.remove(at: index)
            saveDevicesToPersistentStorage()
            objectWillChange.send()
            logger.info("Device removed: \(device.name, privacy: .public)")
        } else {
            logger.warning("Attempted to remove device that wasn't found: \(device.name, privacy: .public)")
        }
    }

    @MainActor
    func addDeviceManually(ipAddress: String, port: UInt16 = 9123) -> Bool {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDeviceManager")
        logger.info("Attempting to add device manually with IP: \(ipAddress, privacy: .public)")

        // NWEndpoint.Host initializer doesn't return an optional
        let host = NWEndpoint.Host(ipAddress)

        if !isValidIPAddress(ipAddress) {
            logger.error("Invalid IP address format: \(ipAddress, privacy: .public)")
            return false
        }

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let endpoint = NWEndpoint.hostPort(host: host, port: nwPort)

        // Check if device with this endpoint already exists
        if devices.contains(where: { $0.endpoint == endpoint }) {
            logger
                .warning("Device with endpoint \(endpoint.debugDescription, privacy: .public) already exists")
            return false
        }

        let newDevice = ElgatoDevice(endpoint: endpoint)
        newDevice.isOnline = false
        devices.append(newDevice)

        Task {
            do {
                try await newDevice.fetchAccessoryInfo()
                try await newDevice.fetchLightInfo()

                await MainActor.run {
                    newDevice.isOnline = true
                    newDevice.lastSeen = Date()
                    logger
                        .info(
                            "Successfully connected to manually added device: \(newDevice.name, privacy: .public)"
                        )
                    newDeviceDiscovered.send(newDevice)
                    saveDevicesToPersistentStorage()
                    objectWillChange.send()
                }
            } catch {
                await MainActor.run {
                    logger
                        .error(
                            "Failed to connect to manually added device at \(ipAddress, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    objectWillChange.send()
                }
            }
        }

        logger
            .info(
                "Added device with endpoint \(endpoint.debugDescription, privacy: .public) - attempting connection"
            )
        return true
    }

    @MainActor
    func setDeviceManaged(_ device: ElgatoDevice, isManaged: Bool) {
        if let index = devices.firstIndex(where: { $0.endpoint == device.endpoint }) {
            devices[index].isManaged = isManaged
            saveDevicesToPersistentStorage()
            objectWillChange.send()

            logger
                .info(
                    "Device \(device.name, privacy: .public) management status changed to: \(isManaged ? "managed" : "unmanaged")"
                )
        }
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

    private func areEndpointsEquivalent(_ endpoint1: NWEndpoint, _ endpoint2: NWEndpoint) -> Bool {
        guard case let .hostPort(host1, port1) = endpoint1,
              case let .hostPort(host2, port2) = endpoint2
        else {
            return endpoint1 == endpoint2
        }

        guard port1.rawValue == port2.rawValue else {
            return false
        }

        // Extract raw host strings (without potential scoping info)
        let hostStr1 = "\(host1)".split(separator: "%").first.map(String.init) ?? "\(host1)"
        let hostStr2 = "\(host2)".split(separator: "%").first.map(String.init) ?? "\(host2)"

        // Compare hosts ignoring case
        return hostStr1.lowercased() == hostStr2.lowercased()
    }
}

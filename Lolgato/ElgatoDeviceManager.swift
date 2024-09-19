import Foundation
import Network
import os

class ElgatoDevice: Identifiable, Equatable {
    let endpoint: NWEndpoint
    var isOnline: Bool = true
    var lastSeen: Date = .init()

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
    }

    var id: NWEndpoint { endpoint }

    static func == (lhs: ElgatoDevice, rhs: ElgatoDevice) -> Bool {
        lhs.endpoint == rhs.endpoint
    }
}

class ElgatoDeviceManager: ObservableObject {
    @Published private(set) var devices: [ElgatoDevice] = []
    private let discovery: ElgatoDiscovery
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDeviceManager")

    init(discovery: ElgatoDiscovery) {
        self.discovery = discovery
        performDiscovery()
    }

    func performDiscovery() {
        discovery.startDiscovery { [weak self] results in
            self?.updateDevices(with: results)
        }
    }

    private func updateDevices(with results: [NWEndpoint]) {
        DispatchQueue.main.async {
            let currentDate = Date()

            // Update existing devices and add new ones
            for endpoint in results {
                if let existingDevice = self.devices.first(where: { $0.endpoint == endpoint }) {
                    existingDevice.isOnline = true
                    existingDevice.lastSeen = currentDate
                } else {
                    let newDevice = ElgatoDevice(endpoint: endpoint)
                    self.devices.append(newDevice)
                    self.logger.info("New device found: \(endpoint.debugDescription)")
                }
            }

            // Mark devices as offline if not seen in this discovery round
            for device in self.devices where device.lastSeen != currentDate {
                device.isOnline = false
            }

            // Remove devices not seen for a long time (e.g., 24 hours)
            let removalThreshold = currentDate.addingTimeInterval(-24 * 60 * 60)
            self.devices.removeAll { $0.lastSeen < removalThreshold }

            self.objectWillChange.send()
        }
    }

    func stopDiscovery() {
        discovery.stopDiscovery()
    }
}

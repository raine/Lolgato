import SwiftUI

struct DeviceSettingsView: View {
    @ObservedObject var deviceManager: ElgatoDeviceManager
    @State private var isAddingDevice = false
    @State private var newDeviceAddress = ""
    @State private var showingAddDeviceError = false
    @State private var addDeviceErrorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Detected Devices")
                    .font(.headline)

                Spacer()

                Button(action: {
                    refreshDevices()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh device list")

                Button(action: {
                    isAddingDevice = true
                }) {
                    Label("Add Device", systemImage: "plus")
                }
                .help("Add device manually")
            }

            if deviceManager.devices.isEmpty {
                Text("No devices found. Make sure your Elgato lights are connected to the network.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                deviceTable
            }

            if isAddingDevice {
                addDeviceSection
            }
        }
        .padding()
        .frame(minWidth: 500)
        .alert("Error Adding Device", isPresented: $showingAddDeviceError) {
            Button("OK") { showingAddDeviceError = false }
        } message: {
            Text(addDeviceErrorMessage)
        }
    }

    private var deviceTable: some View {
        Table(deviceManager.devices.sorted(by: { $0.name < $1.name })) {
            TableColumn("Managed") { device in
                Toggle("", isOn: Binding(
                    get: { device.isManaged },
                    set: { newValue in
                        device.isManaged = newValue
                        updateDeviceManagement(device)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(
                    "When checked, this device will be controlled by the app. When unchecked, the app will never control this device."
                )
            }
            .width(60)

            TableColumn("Name", value: \.name)
                .width(min: 120, ideal: 150)

            TableColumn("Status") { device in
                HStack {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(device.isOnline ? "Online" : "Offline")
                        .foregroundColor(device.isOnline ? .primary : .secondary)
                }
            }
            .width(min: 80, ideal: 100)
        }
    }

    private var addDeviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 8)

            Text("Add Device Manually")
                .font(.headline)

            Text("Enter the IP address of your Elgato device:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                TextField("IP Address (e.g. 192.168.1.100)", text: $newDeviceAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addDeviceManually()
                }
                .disabled(newDeviceAddress.isEmpty)

                Button("Cancel") {
                    isAddingDevice = false
                    newDeviceAddress = ""
                }
            }
        }
    }

    private func addDeviceManually() {
        guard !newDeviceAddress.isEmpty else { return }

        Task { @MainActor in
            let success = deviceManager.addDeviceManually(ipAddress: newDeviceAddress)

            if !success {
                showingAddDeviceError = true
                addDeviceErrorMessage =
                    "Failed to add device. Please check the IP address and ensure the device is powered on and connected to your network."
            }

            isAddingDevice = false
            newDeviceAddress = ""
        }
    }

    private func refreshDevices() {
        // First refresh the status of existing devices
        Task {
            for device in deviceManager.devices where device.isOnline {
                do {
                    try await device.fetchLightInfo()
                } catch {
                    print("Error updating device status: \(error)")
                }
            }
        }

        // Restart discovery to find new devices
        deviceManager.stopDiscovery()
        deviceManager.startDiscovery()

        // Remove stale devices
        deviceManager.removeStaleDevices()
    }

    private func updateDeviceManagement(_: ElgatoDevice) {
        // When changing management status, save the devices to persistent storage
        Task { @MainActor in
            deviceManager.saveDevicesToPersistentStorage()
        }
    }
}

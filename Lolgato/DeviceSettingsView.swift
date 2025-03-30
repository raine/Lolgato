import SwiftUI

struct DeviceSettingsView: View {
    @ObservedObject var deviceManager: ElgatoDeviceManager
    @State private var isAddingDevice = false
    @State private var newDeviceAddress = ""
    @State private var showingAddDeviceError = false
    @State private var addDeviceErrorMessage = ""
    @State private var isRefreshing = false
    @State private var deviceToDelete: ElgatoDevice?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Devices")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    refreshDevices()
                }) {
                    if isRefreshing {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                            Text("Refreshing...")
                        }
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
                .help(isRefreshing ? "Discovery in progress..." : "Refresh device list")

                Button(action: {
                    isAddingDevice = true
                }) {
                    Label("Add Device", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add device manually")
            }
            .padding(.bottom, 8)

            if deviceManager.devices.isEmpty {
                VStack {
                    Spacer()

                    Text("No devices found. Make sure your Elgato lights are connected to the network.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 200)

                    Spacer()
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
                .cornerRadius(8)
            } else {
                deviceTable
            }

            if isAddingDevice {
                addDeviceSection
            }
        }
        .padding()
        .alert("Error Adding Device", isPresented: $showingAddDeviceError) {
            Button("OK") { showingAddDeviceError = false }
        } message: {
            Text(addDeviceErrorMessage)
        }
        .alert("Remove Device?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                deviceToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let device = deviceToDelete {
                    Task { @MainActor in
                        deviceManager.removeDevice(device)
                    }
                }
                deviceToDelete = nil
            }
        } message: {
            if let device = deviceToDelete {
                if device.name.isEmpty {
                    // For devices that don't have a name yet
                    if case let .hostPort(host, _) = device.endpoint {
                        let ipAddress = host.debugDescription.split(separator: "%").first
                            .map(String.init) ?? host.debugDescription
                        Text(
                            "Are you sure you want to remove the device at IP address \(ipAddress) from your device list?"
                        )
                    } else {
                        Text("Are you sure you want to remove this unnamed device from your device list?")
                    }
                } else {
                    Text(
                        "Are you sure you want to remove '\(device.name)' from your device list?"
                    )
                }
            } else {
                Text("No device selected to remove.")
            }
        }
    }

    private var deviceTable: some View {
        Table(deviceManager.devices.sorted(by: { $0.order < $1.order })) {
            TableColumn("Managed") { device in
                Toggle("", isOn: Binding<Bool>(
                    get: { device.isManaged },
                    set: { newValue in
                        Task { @MainActor in
                            deviceManager.setDeviceManaged(device, isManaged: newValue)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(
                    "When checked, this device will be controlled by the app. When unchecked, the app will never control this device."
                )
            }
            .width(55)

            TableColumn("Name") { device in
                if device.name.isEmpty {
                    Text("Connecting...")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text(device.name)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("IP Address") { device in
                if case let .hostPort(host, _) = device.endpoint {
                    let ipAddress = host.debugDescription.split(separator: "%").first.map(String.init) ?? host
                        .debugDescription

                    ZStack {
                        TextEditor(text: .constant(ipAddress))
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(height: 20)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                    .help("Click to select and copy")
                } else {
                    Text("Unknown")
                }
            }
            .width(min: 100, ideal: 100)

            TableColumn("Status") { device in
                HStack(spacing: 8) {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(device.isOnline ? "Online" : "Offline")
                        .foregroundColor(device.isOnline ? .primary : .secondary)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("") { device in
                Button(action: {
                    deviceToDelete = device
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove this device")
            }
            .width(30)
        }
    }

    private var addDeviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 8)

            Text("Add Device Manually")
                .font(.headline)

            Text(
                "Devices are normally discovered automatically. If a device isn't found, you can add it manually using its IP address."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, 4)

            Text("Enter the IP address of your Elgato device:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                TextField("IP Address (e.g. 192.168.1.100)", text: $newDeviceAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        addDeviceManually()
                    }
                    .disableAutocorrection(true)

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

        Task<Void, Never> { @MainActor in
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
        guard !isRefreshing else { return }

        isRefreshing = true

        Task {
            // First refresh the status of existing devices
            await withTaskGroup(of: Void.self) { group in
                for device in deviceManager.devices where device.isOnline {
                    group.addTask {
                        do {
                            try await withTimeout(seconds: 5) {
                                try await device.fetchLightInfo()
                            }
                        } catch {
                            print("Error or timeout updating device status: \(error)")
                        }
                    }
                }
                await group.waitForAll()
            }

            // Stop discovery and wait a moment
            deviceManager.stopDiscovery()

            // Add a small delay to ensure browser state is fully reset
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

            deviceManager.startDiscovery()

            // Add a minimum delay so the spinner is visible
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func withTimeout<T>(seconds: Double,
                                operation: @escaping () async throws -> T) async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation
            group.addTask {
                try await operation()
            }

            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            // Return the first completed task result (or throw its error)
            guard let result = try await group.next() else {
                throw TimeoutError()
            }

            // Cancel any remaining tasks
            group.cancelAll()

            return result
        }
    }

    private struct TimeoutError: Error {
        let message = "Operation timed out"
    }
}

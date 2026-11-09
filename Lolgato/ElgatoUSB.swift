import Foundation
import IOKit.hid
import os

enum ElgatoUSBError: Error {
    case notConnected
    case handshakeFailed
    case timeout
    case sendFailed(IOReturn)
    case deviceError(status: UInt8)
}

/// Talks to one Elgato light in USB mode using the framing in `ElgatoHIDFraming`.
///
/// IOKit delivers input reports on the main run loop, and all state here is only touched
/// on the main actor. Replies carry no request ID, so requests run one at a time.
final class USBHIDElgatoTransport: ElgatoTransport {
    private static let replyTimeout: Duration = .seconds(2)
    private static let handshakeTimeout: Duration = .milliseconds(500)
    private static let handshakeAttempts = 10

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "USBHIDElgatoTransport")
    private var hidDevice: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var isHandshakeDone = false

    private var isBusy = false
    private var waitingRequests: [CheckedContinuation<Void, Never>] = []

    private var pendingReply: CheckedContinuation<(status: UInt8, payload: Data), Error>?
    private var pendingReplyID = 0
    private var replyPackets: [ElgatoHIDFraming.Packet] = []

    deinit {
        unregisterInputReportCallback()
    }

    @MainActor
    func attach(_ device: IOHIDDevice) {
        detach()

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: ElgatoHIDFraming.reportSize)
        hidDevice = device
        reportBuffer = buffer

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            ElgatoHIDFraming.reportSize,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let transport = Unmanaged<USBHIDElgatoTransport>.fromOpaque(context).takeUnretainedValue()
                let data = Data(bytes: report, count: length)
                MainActor.assumeIsolated {
                    transport.handleInputReport(data)
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    @MainActor
    func detach() {
        unregisterInputReportCallback()
        hidDevice = nil
        isHandshakeDone = false
        finishPendingReply(throwing: ElgatoUSBError.notConnected)
    }

    @MainActor
    func request(method: String, path: String, body: Data?) async throws -> Data {
        await acquire()
        defer { release() }

        if !isHandshakeDone {
            try await handshake()
        }

        logger.info("\(method, privacy: .public) \(path, privacy: .public) over USB")
        let reply = try await exchange(
            .request,
            payload: ElgatoHIDFraming.requestPayload(method: method, path: path, body: body),
            timeout: Self.replyTimeout
        )

        guard reply.status == ElgatoHIDFraming.Status.ok || reply.status == ElgatoHIDFraming.Status.accepted else {
            throw ElgatoUSBError.deviceError(status: reply.status)
        }
        return reply.payload
    }

    // Control Center retries the handshake up to 10 times, 200 ms apart, until the light answers OK.
    @MainActor
    private func handshake() async throws {
        for _ in 1 ... Self.handshakeAttempts {
            if let reply = try? await exchange(.handshake, payload: Data(), timeout: Self.handshakeTimeout),
               reply.status == ElgatoHIDFraming.Status.ok
            {
                isHandshakeDone = true
                return
            }
            guard hidDevice != nil else {
                throw ElgatoUSBError.notConnected
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ElgatoUSBError.handshakeFailed
    }

    @MainActor
    private func exchange(
        _ command: ElgatoHIDFraming.Command,
        payload: Data,
        timeout: Duration
    ) async throws -> (status: UInt8, payload: Data) {
        guard let hidDevice else {
            throw ElgatoUSBError.notConnected
        }

        let reports = try ElgatoHIDFraming.encode(command: command, payload: payload)
        pendingReplyID += 1
        let replyID = pendingReplyID
        replyPackets = []

        return try await withCheckedThrowingContinuation { continuation in
            pendingReply = continuation

            for report in reports {
                let result = report.withUnsafeBytes { bytes in
                    IOHIDDeviceSetReport(
                        hidDevice,
                        kIOHIDReportTypeOutput,
                        CFIndex(ElgatoHIDFraming.reportID),
                        bytes.bindMemory(to: UInt8.self).baseAddress!,
                        bytes.count
                    )
                }
                guard result == kIOReturnSuccess else {
                    finishPendingReply(throwing: ElgatoUSBError.sendFailed(result))
                    return
                }
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, pendingReplyID == replyID, pendingReply != nil else { return }
                logger.error("No reply over USB within \(timeout, privacy: .public)")
                isHandshakeDone = false
                finishPendingReply(throwing: ElgatoUSBError.timeout)
            }
        }
    }

    @MainActor
    private func handleInputReport(_ report: Data) {
        let packet: ElgatoHIDFraming.Packet
        do {
            packet = try ElgatoHIDFraming.decode(report)
        } catch {
            logger.error("Ignoring malformed USB report: \(String(describing: error), privacy: .public)")
            return
        }

        guard packet.status != ElgatoHIDFraming.Status.notification, pendingReply != nil else {
            return
        }

        if packet.index == 0 {
            replyPackets = []
        }
        replyPackets.append(packet)
        guard replyPackets.count == packet.count else { return }

        let payload = replyPackets
            .sorted { $0.index < $1.index }
            .reduce(into: Data()) { $0.append($1.payload) }
        let continuation = pendingReply
        pendingReply = nil
        replyPackets = []
        continuation?.resume(returning: (packet.status, payload))
    }

    @MainActor
    private func finishPendingReply(throwing error: Error) {
        let continuation = pendingReply
        pendingReply = nil
        replyPackets = []
        continuation?.resume(throwing: error)
    }

    @MainActor
    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waitingRequests.append($0) }
    }

    @MainActor
    private func release() {
        if waitingRequests.isEmpty {
            isBusy = false
        } else {
            waitingRequests.removeFirst().resume()
        }
    }

    private func unregisterInputReportCallback() {
        if let hidDevice, let reportBuffer {
            IOHIDDeviceRegisterInputReportCallback(hidDevice, reportBuffer, ElgatoHIDFraming.reportSize, nil, nil)
        }
        reportBuffer?.deallocate()
        reportBuffer = nil
    }
}

/// Watches for Elgato lights connected in USB mode and reports them by serial number.
final class ElgatoUSBMonitor {
    private static let vendorID = 0x0FD9
    private static let productIDs = [
        0x00A0, // Key Light Neo
        0x00BC, // Key Light Air MK.2, same protocol per github.com/dmkenney/keylight-usb
    ]

    var onAttach: (@MainActor (_ serialNumber: String, _ device: IOHIDDevice) -> Void)?
    var onDetach: (@MainActor (_ serialNumber: String) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoUSBMonitor")
    private var manager: IOHIDManager?

    @MainActor
    func start() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = Self.productIDs.map { productID in
            [
                kIOHIDVendorIDKey: Self.vendorID,
                kIOHIDProductIDKey: productID,
                kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<ElgatoUSBMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.deviceAttached(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<ElgatoUSBMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.deviceDetached(device)
            }
        }, context)

        // Common modes so lights are still picked up while the menu bar menu is open.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            logger.error("Failed to open HID manager: \(result, privacy: .public)")
        }

        self.manager = manager
        logger.info("USB monitoring started")
    }

    @MainActor
    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    @MainActor
    private func deviceAttached(_ device: IOHIDDevice) {
        let serialNumber = Self.serialNumber(of: device)
        logger.info("USB light attached: \(serialNumber, privacy: .public)")
        onAttach?(serialNumber, device)
    }

    @MainActor
    private func deviceDetached(_ device: IOHIDDevice) {
        let serialNumber = Self.serialNumber(of: device)
        logger.info("USB light detached: \(serialNumber, privacy: .public)")
        onDetach?(serialNumber)
    }

    private static func serialNumber(of device: IOHIDDevice) -> String {
        if let serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
           !serialNumber.isEmpty
        {
            return serialNumber
        }
        let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        return "usb-location-\(String(locationID, radix: 16))"
    }
}

import Foundation

/// Framing for the USB HID protocol Elgato lights speak in USB mode (Key Light Neo).
///
/// Every report, in both directions, is 512 bytes:
///
///     0x02 | index | count | command/status | length (u16 LE) | payload | 0x03 | zero padding
///
/// Request payloads are `METHOD /elgato/path <json>`, the same resources the lights
/// serve over HTTP on Wi-Fi, and replies carry the JSON response. A payload longer
/// than one report is split across reports that share `count` and count up in `index`.
enum ElgatoHIDFraming {
    static let reportID: UInt8 = 0x02
    static let reportSize = 512
    static let maxPayloadPerReport = reportSize - 7
    private static let terminator: UInt8 = 0x03

    enum Command: UInt8 {
        case request = 0x03
        case handshake = 0x04
    }

    enum Status {
        static let ok: UInt8 = 0
        static let accepted: UInt8 = 1
        /// Pushed by the light on its own, e.g. after the dial is turned. Not a reply.
        static let notification: UInt8 = 8
    }

    struct Packet: Equatable {
        let index: Int
        let count: Int
        let status: UInt8
        let payload: Data
    }

    enum FramingError: Error, Equatable {
        case payloadTooLarge(Int)
        case malformedReport(String)
    }

    static func encode(command: Command, payload: Data) throws -> [Data] {
        let count = max(1, (payload.count + maxPayloadPerReport - 1) / maxPayloadPerReport)
        guard count <= Int(UInt8.max) else {
            throw FramingError.payloadTooLarge(payload.count)
        }

        return (0 ..< count).map { index in
            let start = payload.startIndex + index * maxPayloadPerReport
            let chunk = payload[start ..< min(start + maxPayloadPerReport, payload.endIndex)]

            var report = Data(count: reportSize)
            report[0] = reportID
            report[1] = UInt8(index)
            report[2] = UInt8(count)
            report[3] = command.rawValue
            report[4] = UInt8(chunk.count & 0xFF)
            report[5] = UInt8(chunk.count >> 8)
            report.replaceSubrange(6 ..< 6 + chunk.count, with: chunk)
            report[6 + chunk.count] = terminator
            return report
        }
    }

    static func decode(_ report: Data) throws -> Packet {
        let bytes = [UInt8](report)
        guard bytes.count >= 7 else {
            throw FramingError.malformedReport("report is \(bytes.count) bytes")
        }
        guard bytes[0] == reportID else {
            throw FramingError.malformedReport("unexpected report ID \(bytes[0])")
        }

        let index = Int(bytes[1])
        let count = Int(bytes[2])
        guard count > 0, index < count else {
            throw FramingError.malformedReport("invalid packet index \(index)/\(count)")
        }

        let length = Int(bytes[4]) | Int(bytes[5]) << 8
        guard 6 + length < bytes.count, bytes[6 + length] == terminator else {
            throw FramingError.malformedReport("bad payload length \(length)")
        }

        return Packet(index: index, count: count, status: bytes[3], payload: Data(bytes[6 ..< 6 + length]))
    }

    /// The light expects a space after the path even when there is no body.
    static func requestPayload(method: String, path: String, body: Data?) -> Data {
        var payload = Data("\(method) \(path) ".utf8)
        if let body {
            payload.append(body)
        }
        return payload
    }
}

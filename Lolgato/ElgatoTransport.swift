import Foundation
import Network
import os

/// Sends a request for one of a light's `/elgato/...` resources and returns the response body.
/// Lights on Wi-Fi serve these over HTTP; lights in USB mode serve the same ones over USB HID.
protocol ElgatoTransport: AnyObject {
    func request(method: String, path: String, body: Data?) async throws -> Data
}

enum ElgatoTransportError: Error {
    case invalidEndpoint
    case invalidURL
}

final class HTTPElgatoTransport: ElgatoTransport {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HTTPElgatoTransport")
    private let endpoint: NWEndpoint

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
    }

    func request(method: String, path: String, body: Data?) async throws -> Data {
        guard case let .hostPort(host, port) = endpoint else {
            throw ElgatoTransportError.invalidEndpoint
        }

        guard let url = URL.createFromNetworkEndpoint(host: host, port: port, path: path) else {
            throw ElgatoTransportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        logger.info("\(method, privacy: .public) \(url, privacy: .public)")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}

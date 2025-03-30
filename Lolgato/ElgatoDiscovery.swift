import Foundation
import Network
import os

enum ElgatoDiscoveryEvent {
    case deviceFound(NWEndpoint)
    case deviceLost(NWEndpoint)
    case error(Error)

    var debugDescription: String {
        switch self {
        case let .deviceFound(endpoint):
            return "Device found: \(endpoint.debugDescription)"
        case let .deviceLost(endpoint):
            return "Device lost: \(endpoint.debugDescription)"
        case let .error(error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

class ElgatoDiscovery: AsyncSequence {
    typealias Element = ElgatoDiscoveryEvent
    typealias AsyncIterator = AsyncThrowingStream<Element, Error>.Iterator

    private var browser: NWBrowser?
    private var continuation: AsyncThrowingStream<Element, Error>.Continuation?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDiscovery")
    private var discoveredEndpoints: Set<NWEndpoint> = []

    func makeAsyncIterator() -> AsyncIterator {
        let stream = AsyncThrowingStream<Element, Error> { continuation in
            self.continuation = continuation
            self.startDiscovery()

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopDiscovery()
            }
        }
        return stream.makeAsyncIterator()
    }

    private func startDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_elg._tcp", domain: nil)
        browser = NWBrowser(for: browserDescriptor, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.info("Browser is ready")
            case let .failed(error):
                self.logger
                    .error("Browser failed with error: \(error.localizedDescription, privacy: .public)")
                self.continuation?.yield(.error(error))
            case .cancelled:
                self.logger.info("Browser was cancelled")
                self.continuation?.finish()
            case .setup:
                self.logger.debug("Browser is setting up")
            case .waiting:
                self.logger.debug("Browser is waiting")
            @unknown default:
                self.logger.warning("Browser entered an unknown state")
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] _, changes in
            guard let self = self else { return }

            for change in changes {
                switch change {
                case let .added(result):
                    Task {
                        if let resolvedEndpoint = await self.resolveEndpoint(result.endpoint) {
                            if !self.discoveredEndpoints.contains(resolvedEndpoint) {
                                self.discoveredEndpoints.insert(resolvedEndpoint)
                                self.continuation?.yield(.deviceFound(resolvedEndpoint))
                            }
                        }
                    }
                case let .removed(result):
                    if self.discoveredEndpoints.contains(result.endpoint) {
                        self.discoveredEndpoints.remove(result.endpoint)
                        self.continuation?.yield(.deviceLost(result.endpoint))
                    }
                case .identical:
                    // No action needed for identical results
                    break
                case let .changed(old: old, new: new, flags: _):
                    if self.discoveredEndpoints.contains(old.endpoint) {
                        self.discoveredEndpoints.remove(old.endpoint)
                        self.discoveredEndpoints.insert(new.endpoint)

                        self.continuation?.yield(.deviceLost(old.endpoint))
                        self.continuation?.yield(.deviceFound(new.endpoint))

                        self.logger
                            .info(
                                "Device changed: \(old.endpoint.debugDescription) -> \(new.endpoint.debugDescription)"
                            )
                    }
                @unknown default:
                    self.logger.warning("Unknown change type in browse results")
                }
            }
        }

        browser?.start(queue: .main)
        logger.info("Discovery started")
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint) async -> NWEndpoint? {
        await withCheckedContinuation { continuation in
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            if let tcpOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                tcpOptions.version = .v4
            }

            let connection = NWConnection(to: endpoint, using: parameters)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let resolvedEndpoint = connection.currentPath?.remoteEndpoint {
                        logEndpointType(resolvedEndpoint, logger: logger)
                        self.logger
                            .info("Resolved endpoint: \(resolvedEndpoint.debugDescription, privacy: .public)")

                        continuation.resume(returning: resolvedEndpoint)
                    } else {
                        self.logger.warning("Could not resolve endpoint")
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case let .failed(error):
                    self.logger
                        .error(
                            "Connection failed with error: \(error.localizedDescription, privacy: .public)"
                        )
                    continuation.resume(returning: nil)
                case .cancelled:
                    self.logger.info("Connection was cancelled")
                case .setup:
                    self.logger.info("Connection is in setup state")
                case .preparing:
                    self.logger.info("Connection is in preparing state")
                case .waiting:
                    self.logger.info("Connection is in waiting state")
                @unknown default:
                    self.logger.warning("Connection entered an unknown state")
                }
            }
            connection.start(queue: .main)
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        continuation?.finish()
        discoveredEndpoints.removeAll()
        logger.info("Discovery stopped")
    }
}

func logEndpointType(_ endpoint: NWEndpoint, logger: Logger) {
    switch endpoint {
    case let .hostPort(host, port):
        logger
            .info(
                "Endpoint is .hostPort - Host: \(host.debugDescription, privacy: .public), Port: \(port.debugDescription, privacy: .public)"
            )
    case let .service(name, type, domain, interface):
        logger
            .info(
                "Endpoint is .service - Name: \(name, privacy: .public), Type: \(type, privacy: .public), Domain: \(domain, privacy: .public), Interface: \(String(describing: interface))"
            )
    case let .unix(path):
        logger.info("Endpoint is .unix - Path: \(path, privacy: .public)")
    case let .url(url):
        logger.info("Endpoint is .url - URL: \(url, privacy: .public)")
    case .opaque:
        logger.info("Endpoint is .opaque")
    @unknown default:
        logger.warning("Unknown endpoint type: \(endpoint.debugDescription, privacy: .public)")
    }
}

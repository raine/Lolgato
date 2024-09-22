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
        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_elg._tcp", domain: nil)
        browser = NWBrowser(for: browserDescriptor, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.info("Browser is ready")
            case let .failed(error):
                self.logger.error("Browser failed with error: \(error.localizedDescription)")
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
            let connection = NWConnection(to: endpoint, using: .tcp)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let resolvedEndpoint = connection.currentPath?.remoteEndpoint {
                        self.logger.info("Resolved endpoint: \(resolvedEndpoint.debugDescription)")
                        continuation.resume(returning: resolvedEndpoint)
                    } else {
                        self.logger.warning("Could not resolve endpoint")
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case let .failed(error):
                    self.logger.error("Connection failed with error: \(error.localizedDescription)")
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
        logger.info("Discovery stopped")
    }
}

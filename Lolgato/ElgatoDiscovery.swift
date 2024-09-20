import Foundation
import Network
import os

class ElgatoDiscovery: NSObject {
    private var browser: NWBrowser?
    private var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ElgatoDiscovery")
    }

    func startDiscovery() async -> [NWEndpoint] {
        return await withCheckedContinuation { continuation in
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_elg._tcp", domain: nil)
            browser = NWBrowser(for: browserDescriptor, using: parameters)
            browser?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.logger.info("Browser is ready")
                case let .failed(error):
                    self.logger.error("Browser failed with error: \(error.localizedDescription)")
                case .cancelled:
                    self.logger.info("Browser was cancelled")
                case .setup:
                    self.logger.debug("Browser is setting up")
                case .waiting:
                    self.logger.debug("Browser is waiting")
                @unknown default:
                    self.logger.warning("Browser entered an unknown state")
                }
            }

            browser?.browseResultsChangedHandler = { results, _ in
                let endpoints = results.map { $0.endpoint }
                self.logger.info("Found \(endpoints.count) endpoints")
                Task {
                    let resolvedEndpoints = await self.resolveEndpoints(endpoints)
                    continuation.resume(returning: resolvedEndpoints)
                }
            }

            browser?.start(queue: .main)
            logger.info("Discovery started")
        }
    }

    private func resolveEndpoints(_ endpoints: [NWEndpoint]) async -> [NWEndpoint] {
        await withTaskGroup(of: NWEndpoint?.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await self.resolveEndpoint(endpoint)
                }
            }

            var resolvedEndpoints: [NWEndpoint] = []
            for await resolvedEndpoint in group {
                if let endpoint = resolvedEndpoint {
                    resolvedEndpoints.append(endpoint)
                }
            }
            return resolvedEndpoints
        }
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint) async -> NWEndpoint? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            connection.stateUpdateHandler = { state in
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
                case .setup, .preparing, .waiting:
                    // These states don't require any action
                    break
                @unknown default:
                    self.logger.warning("Connection entered an unknown state")
                }
            }
            connection.start(queue: .main)
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        logger.info("Discovery stopped")
    }
}

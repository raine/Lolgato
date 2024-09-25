import Foundation
import Network

extension URL {
    static func createFromNetworkEndpoint(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        path: String,
        scheme: String = "http"
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        let cleanHost = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"

        if case .ipv6 = host {
            components.host = "[\(cleanHost)]"
        } else {
            components.host = cleanHost
        }

        components.port = Int(port.rawValue)
        components.path = path
        return components.url
    }
}

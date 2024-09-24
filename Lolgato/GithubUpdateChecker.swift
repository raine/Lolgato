import AppKit
import Foundation
import os

class GitHubUpdateChecker {
    let owner = "raine"
    let repo = "lolgato"
    let currentVersion: String
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "GitHubUpdateChecker")

    init() {
        currentVersion = GitHubUpdateChecker.getCurrentAppVersion()
    }

    static func getCurrentAppVersion() -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            fatalError("Unable to retrieve app version from bundle")
        }
        return version
    }

    func checkForNewRelease(completion: @escaping (Bool, String?) -> Void) {
        let urlString = "https://github.com/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            completion(false, nil)
            return
        }
        logger.info("Checking for new release at \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        URLSession.shared.dataTask(with: request) { _, response, error in
            self.logger.info("Response: \(String(describing: response))")

            guard let httpResponse = response as? HTTPURLResponse,
                  let responseURL = httpResponse.url,
                  error == nil
            else {
                self.logger.error("Error or invalid response: \(String(describing: error))")
                completion(false, nil)
                return
            }

            self.logger.info("Final response URL: \(responseURL)")

            let versionRegex = try! NSRegularExpression(pattern: "/tag/v?([\\d.]+)")
            let urlString = responseURL.absoluteString

            if let match = versionRegex.firstMatch(
                in: urlString,
                range: NSRange(urlString.startIndex..., in: urlString)
            ) {
                let versionRange = Range(match.range(at: 1), in: urlString)!
                let latestVersion = String(urlString[versionRange])
                let isNewer = self.isVersionNewer(latestVersion, than: self.currentVersion)
                completion(isNewer, isNewer ? latestVersion : nil)
            } else {
                self.logger.warning("Unable to parse version from URL: \(urlString)")
                completion(false, nil)
            }
        }.resume()
    }

    private func isVersionNewer(_ version1: String, than version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        for (v1, v2) in zip(v1Components, v2Components) {
            if v1 > v2 {
                return true
            } else if v1 < v2 {
                return false
            }
        }
        return v1Components.count > v2Components.count
    }

    func promptForUpdate(newVersion: String) {
        let alert = NSAlert()
        alert.messageText = "New Version Available"
        alert
            .informativeText =
            "Version \(newVersion) is available. You are currently running version \(currentVersion). Would you like to view the release page?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let releaseURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
            NSWorkspace.shared.open(releaseURL)
        }
    }

    func promptForNoUpdate() {
        let alert = NSAlert()
        alert.messageText = "No Updates Available"
        alert.informativeText = "You're running the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

import Foundation
import OSLog

func writeLogsToTemp() -> URL? {
    let logStore = try? OSLogStore(scope: .currentProcessIdentifier)
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let entries = try? logStore?.getEntries(with: [])
        .compactMap { $0 as? OSLogEntryLog }
        .map { entry -> String in
            let timestamp = dateFormatter.string(from: entry.date)
            let subsystem = entry.subsystem
            let category = entry.category
            return "[\(timestamp)] subsystem=\(subsystem) category=\(category) \(entry.composedMessage)"
        }
        .joined(separator: "\n")

    guard let entries = entries else {
        return nil
    }

    let tempDirectory = FileManager.default.temporaryDirectory
    let fileURL = tempDirectory.appendingPathComponent("LolgatoLogs.txt")

    do {
        try entries.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    } catch {
        print("Failed to write logs: \(error)")
        return nil
    }
}

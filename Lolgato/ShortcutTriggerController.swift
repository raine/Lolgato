import Combine
import Foundation
import os

class ShortcutTriggerController {
    private let appState: AppState
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ShortcutTriggerController")
    private var cancellable: AnyCancellable?
    // Serial queue ensures shortcuts run one at a time, in order
    private let queue = DispatchQueue(label: "com.lolgato.shortcutRunner")

    init(appState: AppState, cameraStatusPublisher: AnyPublisher<Bool, Never>) {
        self.appState = appState

        cancellable = cameraStatusPublisher
            .dropFirst() // Skip the initial value emitted by CurrentValueSubject
            .sink { [weak self] isActive in
                guard let self else { return }
                let name = isActive ? self.appState.shortcutOnCameraOn : self.appState.shortcutOnCameraOff
                self.enqueueShortcut(named: name)
            }
    }

    private func enqueueShortcut(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        queue.async { [weak self] in
            self?.runShortcut(named: trimmed)
        }
    }

    private func runShortcut(named name: String) {
        logger.info("Running shortcut: \(name, privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Failed to run shortcut '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }
}

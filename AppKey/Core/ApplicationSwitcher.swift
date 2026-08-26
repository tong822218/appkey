import AppKit
import Foundation

struct RunningApplicationDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let bundlePath: String?
    let isFrontmost: Bool
}

enum AppSwitchDecision: Equatable, Sendable {
    case launch(path: String)
    case activate(processIdentifier: pid_t)
    case hide(processIdentifier: pid_t)
    case missing
}

struct AppSwitchResolver {
    func resolve(
        binding: AppBinding,
        runningApplications: [RunningApplicationDescriptor],
        fileExists: Bool
    ) -> AppSwitchDecision {
        let targetPath = URL(fileURLWithPath: binding.appPath).standardizedFileURL.path
        let exactMatches = runningApplications.filter {
            guard let path = $0.bundlePath else { return false }
            return URL(fileURLWithPath: path).standardizedFileURL.path == targetPath
        }

        let selected: RunningApplicationDescriptor?
        if let frontmostExact = exactMatches.first(where: \.isFrontmost) {
            selected = frontmostExact
        } else if let exact = exactMatches.first {
            selected = exact
        } else if fileExists, let bundleIdentifier = binding.bundleIdentifier {
            let bundleMatches = runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }
            selected = bundleMatches.count == 1 ? bundleMatches[0] : nil
        } else {
            selected = nil
        }

        if let selected {
            return selected.isFrontmost
                ? .hide(processIdentifier: selected.processIdentifier)
                : .activate(processIdentifier: selected.processIdentifier)
        }

        return fileExists ? .launch(path: targetPath) : .missing
    }
}

@MainActor
final class ApplicationSwitcher {
    private let resolver = AppSwitchResolver()

    func perform(_ binding: AppBinding) {
        let running = NSWorkspace.shared.runningApplications.map {
            RunningApplicationDescriptor(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier,
                bundlePath: $0.bundleURL?.path,
                isFrontmost: $0.isActive
            )
        }
        let decision = resolver.resolve(
            binding: binding,
            runningApplications: running,
            fileExists: FileManager.default.fileExists(atPath: binding.appPath)
        )

        switch decision {
        case let .launch(path):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: configuration
            ) { _, error in
                if let error {
                    NSLog("AppKey failed to launch %@: %@", path, error.localizedDescription)
                }
            }
        case let .activate(processIdentifier):
            NSRunningApplication(processIdentifier: processIdentifier)?.activate(options: [])
        case let .hide(processIdentifier):
            NSRunningApplication(processIdentifier: processIdentifier)?.hide()
        case .missing:
            NSSound.beep()
        }
    }
}

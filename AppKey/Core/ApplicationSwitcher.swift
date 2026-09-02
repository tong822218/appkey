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
    case reopen(processIdentifier: pid_t)
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
                : .reopen(processIdentifier: selected.processIdentifier)
        }

        return fileExists ? .launch(path: targetPath) : .missing
    }
}

@MainActor
final class ApplicationSwitcher {
    private let resolver = AppSwitchResolver()
    private static let launchActivationRetryDelays: [Duration] = [
        .zero,
        .milliseconds(120),
        .milliseconds(280),
        .milliseconds(600)
    ]

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
            launchAndActivate(path: path)
        case let .reopen(processIdentifier):
            guard let application = NSRunningApplication(processIdentifier: processIdentifier),
                  !application.isTerminated,
                  let applicationURL = application.bundleURL else {
                // The process may have terminated between resolving and reopening.
                launchAndActivate(path: binding.appPath)
                return
            }
            reopenAndActivate(applicationURL: applicationURL)
        case let .hide(processIdentifier):
            NSRunningApplication(processIdentifier: processIdentifier)?.hide()
        case .missing:
            NSSound.beep()
        }
    }

    private func launchAndActivate(path: String) {
        openAndActivate(
            applicationURL: URL(fileURLWithPath: path),
            appleEvent: nil
        )
    }

    private func reopenAndActivate(applicationURL: URL) {
        let standardizedURL = applicationURL.standardizedFileURL
        let reopenEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(applicationURL: standardizedURL),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        openAndActivate(applicationURL: standardizedURL, appleEvent: reopenEvent)
    }

    private func openAndActivate(
        applicationURL: URL,
        appleEvent: NSAppleEventDescriptor?
    ) {
        let standardizedURL = applicationURL.standardizedFileURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.appleEvent = appleEvent

        NSWorkspace.shared.openApplication(
            at: standardizedURL,
            configuration: configuration
        ) { application, error in
            if let error {
                NSLog("AppKey failed to open %@: %@", standardizedURL.path, error.localizedDescription)
                return
            }
            guard let application else {
                NSLog("AppKey opened %@ without receiving a running application", standardizedURL.path)
                return
            }

            Task { @MainActor in
                await Self.activateAfterLaunch(application)
            }
        }
    }

    private static func activateAfterLaunch(_ application: NSRunningApplication) async {
        // Launch Services can return before slower apps are ready to accept activation.
        // Keep retries short and bounded so a stale launch cannot steal focus later.
        for delay in launchActivationRetryDelays {
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }

            guard !application.isTerminated else { return }
            guard !application.isActive else { return }

            if application.isHidden {
                _ = application.unhide()
            }
            _ = application.activate(options: [.activateAllWindows])
        }
    }
}

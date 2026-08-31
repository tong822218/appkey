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
protocol ApplicationSwitchingRuntime: AnyObject {
    var runningApplications: [RunningApplicationDescriptor] { get }

    func fileExists(at path: String) -> Bool
    func launch(path: String, completion: @escaping @MainActor (pid_t?, String?) -> Void)
    func bringToFront(processIdentifier: pid_t)
    func hide(processIdentifier: pid_t)
    func signalMissingApplication()
}

@MainActor
final class AppKitApplicationSwitchingRuntime: ApplicationSwitchingRuntime {
    var runningApplications: [RunningApplicationDescriptor] {
        NSWorkspace.shared.runningApplications.map {
            RunningApplicationDescriptor(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier,
                bundlePath: $0.bundleURL?.path,
                isFrontmost: $0.isActive
            )
        }
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func launch(path: String, completion: @escaping @MainActor (pid_t?, String?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hides = false
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: configuration
        ) { application, error in
            let processIdentifier = application?.processIdentifier
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                completion(processIdentifier, errorMessage)
            }
        }
    }

    func bringToFront(processIdentifier: pid_t) {
        NSLog("AppKey requesting activation for pid %d", processIdentifier)
        requestActivation(processIdentifier: processIdentifier, attemptsRemaining: 8)
        requestReopen(processIdentifier: processIdentifier)
    }

    func hide(processIdentifier: pid_t) {
        NSRunningApplication(processIdentifier: processIdentifier)?.hide()
    }

    func signalMissingApplication() {
        NSSound.beep()
    }

    private func requestActivation(processIdentifier: pid_t, attemptsRemaining: Int) {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated else {
            return
        }

        application.unhide()
        let activated = application.activate(options: [.activateAllWindows])
        NSLog(
            "AppKey activation attempt pid=%d result=%@ active=%@ hidden=%@ attempts=%d",
            processIdentifier,
            activated.description,
            application.isActive.description,
            application.isHidden.description,
            attemptsRemaining
        )

        guard !application.isActive, attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.requestActivation(
                processIdentifier: processIdentifier,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    /// 重新打开已运行的 App，让目标 App 自行恢复最小化窗口或切换到窗口所在空间。
    /// 这相当于用户再次点击 Dock 图标，不依赖辅助功能权限。
    private func requestReopen(processIdentifier: pid_t) {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              let bundleURL = application.bundleURL,
              !application.isTerminated else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hides = false
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { [weak self] reopenedApplication, error in
            let reopenedProcessIdentifier = reopenedApplication?.processIdentifier
                ?? processIdentifier
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                if let errorMessage {
                    NSLog("AppKey failed to reopen %@: %@", bundleURL.path, errorMessage)
                }
                self?.requestActivation(
                    processIdentifier: reopenedProcessIdentifier,
                    attemptsRemaining: 4
                )
            }
        }
    }
}

@MainActor
final class ApplicationSwitcher {
    private let resolver = AppSwitchResolver()
    private let runtime: any ApplicationSwitchingRuntime

    init(runtime: any ApplicationSwitchingRuntime = AppKitApplicationSwitchingRuntime()) {
        self.runtime = runtime
    }

    func perform(_ binding: AppBinding) {
        let decision = resolver.resolve(
            binding: binding,
            runningApplications: runtime.runningApplications,
            fileExists: runtime.fileExists(at: binding.appPath)
        )
        NSLog("AppKey switch decision for %@: %@", binding.displayName, String(describing: decision))

        switch decision {
        case let .launch(path):
            runtime.launch(path: path) { [weak self] processIdentifier, errorMessage in
                if let errorMessage {
                    NSLog("AppKey failed to launch %@: %@", path, errorMessage)
                    return
                }
                if let processIdentifier {
                    self?.runtime.bringToFront(processIdentifier: processIdentifier)
                }
            }
        case let .activate(processIdentifier):
            runtime.bringToFront(processIdentifier: processIdentifier)
        case let .hide(processIdentifier):
            runtime.hide(processIdentifier: processIdentifier)
        case .missing:
            runtime.signalMissingApplication()
        }
    }
}

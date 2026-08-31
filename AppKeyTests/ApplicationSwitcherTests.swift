import Foundation
import XCTest
@testable import AppKey

@MainActor
final class ApplicationSwitcherTests: XCTestCase {
    private let resolver = AppSwitchResolver()

    func testLaunchWhenApplicationIsNotRunning() {
        let binding = sampleBinding(path: "/Applications/Target.app")
        XCTAssertEqual(
            resolver.resolve(binding: binding, runningApplications: [], fileExists: true),
            .launch(path: "/Applications/Target.app")
        )
    }

    func testActivateExactPath() {
        let binding = sampleBinding(path: "/Applications/Target.app")
        let running = descriptor(pid: 42, bundleID: "shared.bundle", path: "/Applications/Target.app")
        XCTAssertEqual(
            resolver.resolve(binding: binding, runningApplications: [running], fileExists: true),
            .activate(processIdentifier: 42)
        )
    }

    func testHideFrontmostExactPath() {
        let binding = sampleBinding(path: "/Applications/Target.app")
        let running = descriptor(pid: 42, bundleID: "shared.bundle", path: "/Applications/Target.app", frontmost: true)
        XCTAssertEqual(
            resolver.resolve(binding: binding, runningApplications: [running], fileExists: true),
            .hide(processIdentifier: 42)
        )
    }

    func testSameBundleIdentifierDoesNotSelectWrongPathWhenAmbiguous() {
        let binding = sampleBinding(path: "/Applications/Target.app")
        let applications = [
            descriptor(pid: 10, bundleID: "shared.bundle", path: "/Applications/Lark.app"),
            descriptor(pid: 11, bundleID: "shared.bundle", path: "/Applications/iHaier.app")
        ]
        XCTAssertEqual(
            resolver.resolve(binding: binding, runningApplications: applications, fileExists: true),
            .launch(path: "/Applications/Target.app")
        )
    }

    func testMissingApplicationDoesNotUseBundleFallback() {
        let binding = sampleBinding(path: "/Applications/Missing.app")
        let running = descriptor(pid: 10, bundleID: "shared.bundle", path: "/Applications/Lark.app")
        XCTAssertEqual(
            resolver.resolve(binding: binding, runningApplications: [running], fileExists: false),
            .missing
        )
    }

    func testLaunchCompletionExplicitlyBringsNewApplicationToFront() {
        let runtime = ApplicationSwitchingRuntimeSpy()
        runtime.launchResult = (processIdentifier: 88, errorMessage: nil)
        let switcher = ApplicationSwitcher(runtime: runtime)

        switcher.perform(sampleBinding(path: "/Applications/Target.app"))

        XCTAssertEqual(runtime.launchedPaths, ["/Applications/Target.app"])
        XCTAssertEqual(runtime.broughtToFrontProcessIdentifiers, [88])
    }

    func testLaunchFailureDoesNotAttemptActivation() {
        let runtime = ApplicationSwitchingRuntimeSpy()
        runtime.launchResult = (processIdentifier: nil, errorMessage: "launch failed")
        let switcher = ApplicationSwitcher(runtime: runtime)

        switcher.perform(sampleBinding(path: "/Applications/Target.app"))

        XCTAssertTrue(runtime.broughtToFrontProcessIdentifiers.isEmpty)
    }

    func testRunningApplicationUsesBringToFront() {
        let runtime = ApplicationSwitchingRuntimeSpy()
        runtime.runningApplications = [
            descriptor(pid: 42, bundleID: "shared.bundle", path: "/Applications/Target.app")
        ]
        let switcher = ApplicationSwitcher(runtime: runtime)

        switcher.perform(sampleBinding(path: "/Applications/Target.app"))

        XCTAssertEqual(runtime.broughtToFrontProcessIdentifiers, [42])
    }

    private func sampleBinding(path: String) -> AppBinding {
        AppBinding(displayName: "Target", bundleIdentifier: "shared.bundle", appPath: path)
    }

    private func descriptor(
        pid: pid_t,
        bundleID: String,
        path: String,
        frontmost: Bool = false
    ) -> RunningApplicationDescriptor {
        RunningApplicationDescriptor(
            processIdentifier: pid,
            bundleIdentifier: bundleID,
            bundlePath: path,
            isFrontmost: frontmost
        )
    }
}

@MainActor
private final class ApplicationSwitchingRuntimeSpy: ApplicationSwitchingRuntime {
    var runningApplications: [RunningApplicationDescriptor] = []
    var existingPaths = Set(["/Applications/Target.app"])
    var launchResult: (processIdentifier: pid_t?, errorMessage: String?) = (nil, nil)
    var launchedPaths: [String] = []
    var broughtToFrontProcessIdentifiers: [pid_t] = []
    var hiddenProcessIdentifiers: [pid_t] = []
    var missingApplicationSignalCount = 0

    func fileExists(at path: String) -> Bool {
        existingPaths.contains(path)
    }

    func launch(path: String, completion: @escaping @MainActor (pid_t?, String?) -> Void) {
        launchedPaths.append(path)
        completion(launchResult.processIdentifier, launchResult.errorMessage)
    }

    func bringToFront(processIdentifier: pid_t) {
        broughtToFrontProcessIdentifiers.append(processIdentifier)
    }

    func hide(processIdentifier: pid_t) {
        hiddenProcessIdentifiers.append(processIdentifier)
    }

    func signalMissingApplication() {
        missingApplicationSignalCount += 1
    }
}

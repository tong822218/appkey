import XCTest
@testable import AppKey

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

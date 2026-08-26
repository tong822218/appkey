import Foundation
import XCTest
@testable import AppKey

final class ModelsAndStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppKeyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testConfigurationRoundTripAndAtomicSave() throws {
        let url = temporaryDirectory.appendingPathComponent("nested/bindings.json")
        let store = BindingStore(configurationURL: url)
        let shortcut = try XCTUnwrap(Shortcut.make(keyCode: 18, modifiers: [.control]))
        let configuration = AppKeyConfiguration(bindings: [
            AppBinding(
                displayName: "Warp",
                bundleIdentifier: "dev.warp.Warp-Stable",
                appPath: "/Applications/Warp.app",
                shortcut: shortcut
            )
        ])

        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(siblings, ["bindings.json"])
    }

    func testUnsupportedSchemaIsRejected() throws {
        let url = temporaryDirectory.appendingPathComponent("bindings.json")
        let store = BindingStore(configurationURL: url)
        let data = Data("{\"schemaVersion\":99,\"bindings\":[]}".utf8)
        try data.write(to: url)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? BindingStoreError, .unsupportedSchema(99))
        }
    }

    func testShortcutValidationRequiresAllowedKeyAndPrimaryModifier() {
        XCTAssertNotNil(Shortcut.make(keyCode: 0, modifiers: [.command]))
        XCTAssertNotNil(Shortcut.make(keyCode: 111, modifiers: [.option, .shift]))
        XCTAssertNil(Shortcut.make(keyCode: 0, modifiers: [.shift]))
        XCTAssertNil(Shortcut.make(keyCode: 49, modifiers: [.command]))
    }

    func testDuplicatePathAndShortcutAreRejected() throws {
        let shortcut = try XCTUnwrap(Shortcut.make(keyCode: 12, modifiers: [.control]))
        let first = AppBinding(
            displayName: "First",
            bundleIdentifier: "one",
            appPath: "/Applications/First.app",
            shortcut: shortcut
        )
        let duplicatePath = AppBinding(
            displayName: "First copy",
            bundleIdentifier: "one.copy",
            appPath: "/Applications/../Applications/First.app"
        )
        let duplicateShortcut = AppBinding(
            displayName: "Second",
            bundleIdentifier: "two",
            appPath: "/Applications/Second.app",
            shortcut: shortcut
        )

        XCTAssertThrowsError(try BindingValidator().validate([first, duplicatePath]))
        XCTAssertThrowsError(try BindingValidator().validate([first, duplicateShortcut]))
    }
}

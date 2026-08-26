import AppKit
import Foundation
import SQLite3
import XCTest
@testable import AppKey

final class ManicoImporterTests: XCTestCase {
    func testImportsNineValidBindingsAndSkipsInvalidRows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManicoImporterTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try createFixture(at: databaseURL)

        let result = try ManicoImporter().importBindings(from: databaseURL)

        XCTAssertEqual(result.bindings.count, 9)
        XCTAssertEqual(result.bindings.map(\.shortcut?.displayText), [
            "⌃1", "⌃2", "⌃3", "⌃Q", "⌃W", "⌃E", "⌃D", "⌃F", "⌃G"
        ])
        XCTAssertEqual(result.skippedEmpty, 1)
        XCTAssertEqual(result.skippedInvalid, 1)
        XCTAssertEqual(result.skippedUpdater, 1)
    }

    private func createFixture(at url: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { return }
        defer { sqlite3_close(database) }

        try execute(database, "CREATE TABLE ZCONFIGURATION (Z_PK INTEGER PRIMARY KEY, ZMODE INTEGER)")
        try execute(database, "CREATE TABLE ZACTION (Z_PK INTEGER PRIMARY KEY, ZSORTWEIGHT INTEGER, ZCONFIGURATION INTEGER, ZBUNDLEID TEXT, ZNAME TEXT, ZTARGET TEXT, ZSHORTCUT BLOB)")
        try execute(database, "INSERT INTO ZCONFIGURATION VALUES (1, 2)")

        let entries: [(String, UInt32)] = [
            ("One", 18), ("Two", 19), ("Three", 20), ("Q", 12), ("W", 13),
            ("E", 14), ("D", 2), ("F", 3), ("G", 5)
        ]
        for (index, entry) in entries.enumerated() {
            let archive = try NSKeyedArchiver.archivedData(
                withRootObject: [
                    "keyCode": NSNumber(value: entry.1),
                    "modifierFlags": NSNumber(value: NSEvent.ModifierFlags.control.rawValue)
                ],
                requiringSecureCoding: false
            )
            try insert(
                database,
                id: index + 1,
                name: entry.0,
                path: "/Applications/\(entry.0).app",
                bundleID: "test.\(index)",
                shortcut: archive
            )
        }

        try insert(database, id: 20, name: "Empty", path: "/Applications/Empty.app", bundleID: "empty", shortcut: nil)
        let invalid = try NSKeyedArchiver.archivedData(
            withRootObject: [
                "keyCode": NSNumber(value: UInt16.max),
                "modifierFlags": NSNumber(value: 0)
            ],
            requiringSecureCoding: false
        )
        try insert(database, id: 21, name: "Invalid", path: "/Applications/Invalid.app", bundleID: "invalid", shortcut: invalid)
        try insert(
            database,
            id: 22,
            name: "Updater",
            path: "/Users/test/Library/Caches/vendor/Updater.app",
            bundleID: "org.sparkle-project.Sparkle.Updater",
            shortcut: invalid
        )
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
        }
    }

    private func insert(
        _ database: OpaquePointer,
        id: Int,
        name: String,
        path: String,
        bundleID: String,
        shortcut: Data?
    ) throws {
        let sql = "INSERT INTO ZACTION VALUES (?, ?, 1, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw NSError(domain: "SQLite", code: 2) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int(statement, 1, Int32(id))
        sqlite3_bind_int(statement, 2, Int32(id))
        sqlite3_bind_text(statement, 3, bundleID, -1, transient)
        sqlite3_bind_text(statement, 4, name, -1, transient)
        sqlite3_bind_text(statement, 5, path, -1, transient)
        if let shortcut {
            shortcut.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 6, bytes.baseAddress, Int32(shortcut.count), transient)
            }
        } else {
            sqlite3_bind_null(statement, 6)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "SQLite", code: 3, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
        }
    }
}

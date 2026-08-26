import AppKit
import Foundation
import SQLite3

#if APPKEY_MIGRATION_TESTS
@testable import AppKey
#endif

enum ManicoImportError: LocalizedError {
    case cannotOpenDatabase(String)
    case cannotReadDatabase(String)
    case invalidShortcutArchive

    var errorDescription: String? {
        switch self {
        case let .cannotOpenDatabase(message):
            return "无法只读打开 Manico 数据库：\(message)"
        case let .cannotReadDatabase(message):
            return "无法读取 Manico 数据库：\(message)"
        case .invalidShortcutArchive:
            return "快捷键归档无法解析。"
        }
    }
}

struct ManicoImportResult: Sendable {
    var bindings: [AppBinding]
    var skippedEmpty = 0
    var skippedInvalid = 0
    var skippedUpdater = 0
    var skippedDuplicate = 0
}

struct ManicoImporter {
    func importBindings(from databaseURL: URL) throws -> ManicoImportResult {
        var database: OpaquePointer?
        let openStatus = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openStatus == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let database { sqlite3_close(database) }
            throw ManicoImportError.cannotOpenDatabase(message)
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT a.ZNAME, a.ZBUNDLEID, a.ZTARGET, a.ZSHORTCUT
            FROM ZACTION a
            INNER JOIN ZCONFIGURATION c ON c.Z_PK = a.ZCONFIGURATION
            WHERE c.ZMODE = 2
            ORDER BY a.ZSORTWEIGHT, a.Z_PK
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ManicoImportError.cannotReadDatabase(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var result = ManicoImportResult(bindings: [])
        var paths = Set<String>()
        var shortcuts = Set<Shortcut>()

        while sqlite3_step(statement) == SQLITE_ROW {
            let name = string(in: statement, column: 0) ?? "未命名 App"
            let bundleIdentifier = string(in: statement, column: 1)
            guard let rawPath = string(in: statement, column: 2), !rawPath.isEmpty else {
                result.skippedInvalid += 1
                continue
            }
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path

            if bundleIdentifier == "org.sparkle-project.Sparkle.Updater"
                || path.contains("/Library/Caches/") {
                result.skippedUpdater += 1
                continue
            }

            guard sqlite3_column_type(statement, 3) != SQLITE_NULL,
                  let shortcutData = data(in: statement, column: 3) else {
                result.skippedEmpty += 1
                continue
            }

            guard let shortcut = try? decodeShortcut(shortcutData) else {
                result.skippedInvalid += 1
                continue
            }
            guard shortcut.keyCode != UInt32(UInt16.max), shortcut.isValid else {
                result.skippedInvalid += 1
                continue
            }
            guard paths.insert(path).inserted, shortcuts.insert(shortcut).inserted else {
                result.skippedDuplicate += 1
                continue
            }

            result.bindings.append(
                AppBinding(
                    displayName: name,
                    bundleIdentifier: bundleIdentifier,
                    appPath: path,
                    shortcut: shortcut,
                    isEnabled: true
                )
            )
        }

        let finalStatus = sqlite3_errcode(database)
        guard finalStatus == SQLITE_OK || finalStatus == SQLITE_DONE else {
            throw ManicoImportError.cannotReadDatabase(String(cString: sqlite3_errmsg(database)))
        }
        return result
    }

    private func decodeShortcut(_ data: Data) throws -> Shortcut {
        let allowedClasses: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self]
        let object = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
        guard let dictionary = object as? [AnyHashable: Any],
              let keyCodeNumber = dictionary["keyCode"] as? NSNumber,
              let modifierNumber = dictionary["modifierFlags"] as? NSNumber else {
            throw ManicoImportError.invalidShortcutArchive
        }

        let keyCode = keyCodeNumber.uint32Value
        let modifiers = ShortcutModifiers(manicoModifierFlags: modifierNumber.uint64Value)
        guard let shortcut = Shortcut.make(keyCode: keyCode, modifiers: modifiers) else {
            throw ManicoImportError.invalidShortcutArchive
        }
        return shortcut
    }

    private func string(in statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private func data(in statement: OpaquePointer, column: Int32) -> Data? {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: length)
    }
}

private extension ShortcutModifiers {
    init(manicoModifierFlags: UInt64) {
        var modifiers: ShortcutModifiers = []
        if manicoModifierFlags & UInt64(NSEvent.ModifierFlags.control.rawValue) != 0 {
            modifiers.insert(.control)
        }
        if manicoModifierFlags & UInt64(NSEvent.ModifierFlags.option.rawValue) != 0 {
            modifiers.insert(.option)
        }
        if manicoModifierFlags & UInt64(NSEvent.ModifierFlags.command.rawValue) != 0 {
            modifiers.insert(.command)
        }
        if manicoModifierFlags & UInt64(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            modifiers.insert(.shift)
        }
        self = modifiers
    }
}

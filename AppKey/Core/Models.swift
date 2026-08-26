import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let command = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    var hasRequiredModifier: Bool {
        !intersection([.control, .option, .command]).isEmpty
    }

    var displayPrefix: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}
struct Shortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: ShortcutModifiers
    var keyLabel: String

    var displayText: String {
        modifiers.displayPrefix + keyLabel
    }

    var isValid: Bool {
        modifiers.hasRequiredModifier && Self.allowedKeyCodes[keyCode] != nil
    }

    static func make(keyCode: UInt32, modifiers: ShortcutModifiers) -> Shortcut? {
        guard let label = allowedKeyCodes[keyCode], modifiers.hasRequiredModifier else {
            return nil
        }
        return Shortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label)
    }

    static let allowedKeyCodes: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9", 29: "0",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}

struct AppBinding: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var displayName: String
    var bundleIdentifier: String?
    var appPath: String
    var shortcut: Shortcut?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String?,
        appPath: String,
        shortcut: Shortcut? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }

    var appExists: Bool {
        FileManager.default.fileExists(atPath: appPath)
    }
}

struct AppKeyConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var bindings: [AppBinding]

    init(schemaVersion: Int = currentSchemaVersion, bindings: [AppBinding]) {
        self.schemaVersion = schemaVersion
        self.bindings = bindings
    }
}

enum BindingValidationError: LocalizedError, Equatable {
    case invalidShortcut
    case duplicateShortcut(String)
    case duplicateApplication(String)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            return "快捷键必须使用字母、数字或 F1–F12，并包含 Control、Command 或 Option。"
        case let .duplicateShortcut(shortcut):
            return "快捷键 \(shortcut) 已被其他 App 使用。"
        case let .duplicateApplication(name):
            return "\(name) 已经存在绑定。"
        }
    }
}

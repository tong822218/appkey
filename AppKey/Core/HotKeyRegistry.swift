import Carbon
import Foundation

struct HotKeyRegistrationError: LocalizedError {
    let status: OSStatus
    let shortcut: Shortcut

    var errorDescription: String? {
        if status == eventHotKeyExistsErr {
            return "快捷键 \(shortcut.displayText) 已被系统或其他应用占用。"
        }
        return "无法注册快捷键 \(shortcut.displayText)（错误 \(status)）。"
    }
}

struct HotKeyRegistrationTransaction {
    static func replace<Item>(
        previous: [Item],
        desired: [Item],
        unregisterAll: () -> Void,
        register: (Item) throws -> Void
    ) throws {
        unregisterAll()
        do {
            for item in desired {
                try register(item)
            }
        } catch {
            unregisterAll()
            for item in previous {
                try? register(item)
            }
            throw error
        }
    }

    static func registerAvailable<Item>(
        desired: [Item],
        unregisterAll: () -> Void,
        register: (Item) throws -> Void
    ) -> [Error] {
        unregisterAll()
        var errors: [Error] = []
        for item in desired {
            do {
                try register(item)
            } catch {
                errors.append(error)
            }
        }
        return errors
    }
}

@MainActor
final class HotKeyRegistry {
    typealias TriggerHandler = @MainActor (UUID) -> Void

    private struct Registration: @unchecked Sendable {
        let bindingID: UUID
        let shortcut: Shortcut
        let reference: EventHotKeyRef
        let numericID: UInt32
    }

    nonisolated(unsafe) private static weak var callbackTarget: HotKeyRegistry?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var registrations: [UUID: Registration] = [:]
    private var numericIDToBindingID: [UInt32: UUID] = [:]
    private var nextNumericID: UInt32 = 1
    private let onTrigger: TriggerHandler

    init(onTrigger: @escaping TriggerHandler) {
        self.onTrigger = onTrigger
        Self.callbackTarget = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        if status == noErr {
            NSLog("AppKey hotkey event handler installed")
        } else {
            NSLog("AppKey failed to install hotkey event handler: %d", status)
        }
    }

    deinit {
        registrations.values.forEach { UnregisterEventHotKey($0.reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func replaceAll(with bindings: [AppBinding]) throws {
        let previous = registrations.values.map { ($0.bindingID, $0.shortcut) }
        let desired = bindings.compactMap { binding in
            binding.shortcut.map { (binding.id, $0) }
        }
        try HotKeyRegistrationTransaction.replace(
            previous: previous,
            desired: desired,
            unregisterAll: unregisterAll,
            register: { try register(bindingID: $0.0, shortcut: $0.1) }
        )
    }

    /// 启动时逐个恢复可用快捷键，避免单个系统冲突导致所有绑定失效。
    func replaceAllAvailable(with bindings: [AppBinding]) -> [Error] {
        let desired = bindings.compactMap { binding in
            binding.shortcut.map { (binding.id, binding.displayName, $0) }
        }
        return HotKeyRegistrationTransaction.registerAvailable(
            desired: desired,
            unregisterAll: unregisterAll,
            register: { item in
                do {
                    try register(bindingID: item.0, shortcut: item.2)
                    NSLog("AppKey registered %@ for %@", item.2.displayText, item.1)
                } catch {
                    NSLog(
                        "AppKey failed to register %@ for %@: %@",
                        item.2.displayText,
                        item.1,
                        error.localizedDescription
                    )
                    throw error
                }
            }
        )
    }

    func suspend() -> [(UUID, Shortcut)] {
        let snapshot = registrations.values.map { ($0.bindingID, $0.shortcut) }
        unregisterAll()
        return snapshot
    }

    func resume(_ snapshot: [(UUID, Shortcut)]) {
        unregisterAll()
        for (bindingID, shortcut) in snapshot {
            try? register(bindingID: bindingID, shortcut: shortcut)
        }
    }

    private func register(bindingID: UUID, shortcut: Shortcut) throws {
        let numericID = nextNumericID
        nextNumericID &+= 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x41504B59, id: numericID) // APKY
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw HotKeyRegistrationError(status: status, shortcut: shortcut)
        }

        registrations[bindingID] = Registration(
            bindingID: bindingID,
            shortcut: shortcut,
            reference: reference,
            numericID: numericID
        )
        numericIDToBindingID[numericID] = bindingID
    }

    private func unregisterAll() {
        registrations.values.forEach { UnregisterEventHotKey($0.reference) }
        registrations.removeAll()
        numericIDToBindingID.removeAll()
    }

    private func handle(numericID: UInt32) {
        guard let bindingID = numericIDToBindingID[numericID] else {
            NSLog("AppKey received unknown hotkey id %u", numericID)
            return
        }
        NSLog("AppKey received hotkey id %u for %@", numericID, bindingID.uuidString)
        onTrigger(bindingID)
    }

    private static let eventCallback: EventHandlerUPP = { _, event, _ in
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        let numericID = hotKeyID.id
        Task { @MainActor in
            callbackTarget?.handle(numericID: numericID)
        }
        return noErr
    }
}

private extension Shortcut {
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var bindings: [AppBinding] = []
    @Published private(set) var loginItemState: LoginItemController.State = .disabled
    @Published var errorMessage: String?
    @Published private(set) var recordingBindingID: UUID?

    private let store: BindingStore
    private let validator = BindingValidator()
    private let switcher = ApplicationSwitcher()
    private let loginItemController = LoginItemController()
    private var suspendedRegistrations: [(UUID, Shortcut)] = []

    private lazy var hotKeyRegistry = HotKeyRegistry { [weak self] bindingID in
        self?.trigger(bindingID: bindingID)
    }

    init(store: BindingStore = BindingStore()) {
        self.store = store
        loadConfiguration()
        configureDefaultLoginItemIfNeeded()
    }

    func addApplication(_ application: InstalledApplication) {
        let binding = AppBinding(
            displayName: application.displayName,
            bundleIdentifier: application.bundleIdentifier,
            appPath: application.path
        )
        apply(bindings + [binding])
    }

    func removeBinding(id: UUID) {
        cancelRecording()
        apply(bindings.filter { $0.id != id })
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        updateBinding(id: id) { $0.isEnabled = enabled }
    }

    func relinkBinding(id: UUID, to application: InstalledApplication) {
        updateBinding(id: id) {
            $0.displayName = application.displayName
            $0.bundleIdentifier = application.bundleIdentifier
            $0.appPath = application.path
        }
    }

    func beginRecording(bindingID: UUID) {
        guard recordingBindingID != bindingID else { return }
        cancelRecording()
        recordingBindingID = bindingID
        suspendedRegistrations = hotKeyRegistry.suspend()
    }

    func commitShortcut(_ shortcut: Shortcut?, for bindingID: UUID) {
        restoreRegistrationsAfterRecording()
        updateBinding(id: bindingID) { $0.shortcut = shortcut }
    }

    func cancelRecording() {
        restoreRegistrationsAfterRecording()
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            refreshLoginItemState()
        } catch {
            errorMessage = "无法更新登录启动设置：\(error.localizedDescription)"
            refreshLoginItemState()
        }
    }

    func refreshLoginItemState() {
        loginItemState = loginItemController.state
    }

    func openLoginItemSettings() {
        loginItemController.openSystemSettings()
    }

    func dismissError() {
        errorMessage = nil
    }

    private func loadConfiguration() {
        do {
            let configuration = try store.load()
            try validator.validate(configuration.bindings)
            bindings = configuration.bindings
            try hotKeyRegistry.replaceAll(with: activeBindings(from: bindings))
        } catch {
            errorMessage = "无法载入配置：\(error.localizedDescription)"
        }
    }

    private func configureDefaultLoginItemIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            refreshLoginItemState()
            return
        }
        let defaultsKey = "hasAttemptedDefaultLoginRegistration"
        if !UserDefaults.standard.bool(forKey: defaultsKey) {
            do {
                try loginItemController.setEnabled(true)
            } catch {
                errorMessage = "AppKey 已启动，但需要你在系统设置中批准登录启动。"
            }
            UserDefaults.standard.set(true, forKey: defaultsKey)
        }
        refreshLoginItemState()
    }

    private func trigger(bindingID: UUID) {
        guard let binding = bindings.first(where: { $0.id == bindingID }),
              binding.isEnabled,
              binding.appExists else {
            return
        }
        switcher.perform(binding)
    }

    private func updateBinding(id: UUID, mutation: (inout AppBinding) -> Void) {
        var candidate = bindings
        guard let index = candidate.firstIndex(where: { $0.id == id }) else { return }
        mutation(&candidate[index])
        apply(candidate)
    }

    private func apply(_ candidate: [AppBinding]) {
        let previous = bindings
        do {
            try validator.validate(candidate)
            try hotKeyRegistry.replaceAll(with: activeBindings(from: candidate))
            do {
                try store.save(AppKeyConfiguration(bindings: candidate))
                bindings = candidate
                errorMessage = nil
            } catch {
                try? hotKeyRegistry.replaceAll(with: activeBindings(from: previous))
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activeBindings(from bindings: [AppBinding]) -> [AppBinding] {
        bindings.filter { $0.isEnabled && $0.shortcut != nil && $0.appExists }
    }

    private func restoreRegistrationsAfterRecording() {
        guard recordingBindingID != nil else { return }
        hotKeyRegistry.resume(suspendedRegistrations)
        suspendedRegistrations.removeAll()
        recordingBindingID = nil
    }
}

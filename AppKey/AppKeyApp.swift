import AppKit
import SwiftUI

@main
struct AppKeyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("AppKey", systemImage: "command") {
            MenuBarContent()
                .environmentObject(state)
        }

        Window("AppKey 绑定管理", id: "bindings") {
            BindingsView()
                .environmentObject(state)
        }
        .defaultSize(width: 820, height: 540)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(managementWindowLaunchBehavior)
    }

    private var managementWindowLaunchBehavior: SceneLaunchBehavior {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .suppressed
        }
        return UserDefaults.standard.bool(forKey: "hasShownManagementWindow")
            ? .suppressed
            : .presented
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button("管理绑定…") {
            openWindow(id: "bindings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Toggle(
            "登录时启动",
            isOn: Binding(
                get: { state.loginItemState == .enabled },
                set: { state.setLoginItemEnabled($0) }
            )
        )

        if state.loginItemState == .requiresApproval {
            Button("批准登录启动…") { state.openLoginItemSettings() }
        }

        if let errorMessage = state.errorMessage {
            Button {
                state.dismissError()
            } label: {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
            }
        }

        Divider()
        Button("退出 AppKey") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

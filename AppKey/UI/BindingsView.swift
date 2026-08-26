import AppKit
import SwiftUI

struct BindingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var pickerMode: PickerMode?

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.loginItemState == .requiresApproval {
                loginApprovalBanner
            }

            Divider()

            if state.bindings.isEmpty {
                ContentUnavailableView(
                    "还没有快捷键绑定",
                    systemImage: "command",
                    description: Text("添加一个 App，然后点击“录制快捷键”。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.bindings) { binding in
                        BindingRow(
                            binding: binding,
                            isRecording: state.recordingBindingID == binding.id,
                            onBeginRecording: { state.beginRecording(bindingID: binding.id) },
                            onCommitShortcut: { state.commitShortcut($0, for: binding.id) },
                            onCancelRecording: { state.cancelRecording() },
                            onSetEnabled: { state.setEnabled($0, for: binding.id) },
                            onRelink: { pickerMode = .relink(binding.id) },
                            onDelete: { state.removeBinding(id: binding.id) }
                        )
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(item: $pickerMode) { mode in
            ApplicationPickerView(title: mode.title) { application in
                switch mode {
                case .add:
                    state.addApplication(application)
                case let .relink(id):
                    state.relinkBinding(id: id, to: application)
                }
            }
        }
        .alert("操作失败", isPresented: errorPresented) {
            Button("好") { state.dismissError() }
        } message: {
            Text(state.errorMessage ?? "未知错误")
        }
        .onAppear {
            UserDefaults.standard.set(true, forKey: "hasShownManagementWindow")
            state.refreshLoginItemState()
        }
        .onDisappear { state.cancelRecording() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AppKey").font(.title.bold())
                Text("用全局快捷键启动、切换或隐藏 App")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                pickerMode = .add
            } label: {
                Label("添加 App", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding()
    }

    private var loginApprovalBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("macOS 需要你批准 AppKey 登录时启动。")
            Spacer()
            Button("打开登录项设置") { state.openLoginItemSettings() }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.dismissError() } }
        )
    }
}

private struct BindingRow: View {
    let binding: AppBinding
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onCommitShortcut: (Shortcut?) -> Void
    let onCancelRecording: () -> Void
    let onSetEnabled: (Bool) -> Void
    let onRelink: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: binding.appPath))
                .resizable()
                .frame(width: 38, height: 38)
                .opacity(binding.appExists ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 3) {
                Text(binding.displayName).font(.headline)
                if binding.appExists {
                    Text(binding.appPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 8) {
                        Label("App 不存在", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("重新选择") { onRelink() }
                            .buttonStyle(.link)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorder(
                shortcut: binding.shortcut,
                isRecording: isRecording,
                onBegin: onBeginRecording,
                onCommit: onCommitShortcut,
                onCancel: onCancelRecording
            )
            .frame(width: 132, height: 28)
            .disabled(!binding.appExists)

            Toggle("", isOn: Binding(get: { binding.isEnabled }, set: { value in onSetEnabled(value) }))
                .labelsHidden()
                .disabled(!binding.appExists || binding.shortcut == nil)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除绑定")
        }
        .padding(.vertical, 5)
    }
}

private enum PickerMode: Identifiable {
    case add
    case relink(UUID)

    var id: String {
        switch self {
        case .add: "add"
        case let .relink(id): "relink-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .add: "添加 App"
        case .relink: "重新选择 App"
        }
    }
}

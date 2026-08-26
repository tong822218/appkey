import AppKit
import SwiftUI

struct ApplicationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var applications: [InstalledApplication] = []
    @State private var searchText = ""
    @State private var isLoading = true

    let title: String
    let onSelect: (InstalledApplication) -> Void

    private var filteredApplications: [InstalledApplication] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding()

            TextField("搜索 App", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 10)

            Divider()

            if isLoading {
                ProgressView("正在扫描已安装 App…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApplications) { application in
                    Button {
                        choose(application)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: application.icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(application.displayName)
                                Text(application.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            HStack {
                Button("选择其他 App…") { selectOtherApplication() }
                Spacer()
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .task {
            let scanned = await Task.detached(priority: .userInitiated) {
                InstalledApplicationScanner().scan()
            }.value
            applications = scanned
            isLoading = false
        }
    }

    private func choose(_ application: InstalledApplication) {
        onSelect(application)
        dismiss()
    }

    private func selectOtherApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择一个 Mac App"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            choose(InstalledApplication(url: url))
        }
    }
}

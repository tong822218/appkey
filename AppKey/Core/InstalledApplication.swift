import AppKit
import Foundation

struct InstalledApplication: Identifiable, Hashable, Sendable {
    var id: String { path }
    let displayName: String
    let bundleIdentifier: String?
    let path: String

    init(url: URL) {
        let bundle = Bundle(url: url)
        displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        bundleIdentifier = bundle?.bundleIdentifier
        path = url.standardizedFileURL.path
    }
}

struct InstalledApplicationScanner: Sendable {
    func scan() -> [InstalledApplication] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var paths = Set<String>()
        var applications: [InstalledApplication] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let normalizedPath = url.standardizedFileURL.path
                guard paths.insert(normalizedPath).inserted else { continue }
                applications.append(InstalledApplication(url: url))
            }
        }

        return applications.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}

extension InstalledApplication {
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

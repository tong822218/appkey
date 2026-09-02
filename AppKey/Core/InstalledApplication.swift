import AppKit
import CoreServices
import Foundation

struct InstalledApplication: Identifiable, Hashable, Sendable {
    var id: String { path }
    let displayName: String
    let bundleIdentifier: String?
    let path: String

    init(url: URL) {
        let bundle = Bundle(url: url)
        displayName = Self.metadataDisplayName(for: url)
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        bundleIdentifier = bundle?.bundleIdentifier
        path = url.standardizedFileURL.path
    }

    func matches(searchText: String) -> Bool {
        let aliases: [String]
        switch bundleIdentifier {
        case "com.apple.finder":
            aliases = ["Finder", "访达"]
        default:
            aliases = []
        }

        return ([displayName, path, bundleIdentifier].compactMap { $0 } + aliases).contains {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private static func metadataDisplayName(for url: URL) -> String? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let displayName = MDItemCopyAttribute(item, kMDItemDisplayName) as? String,
              !displayName.isEmpty else {
            return nil
        }
        return displayName
    }
}

struct InstalledApplicationScanner: Sendable {
    private let roots: [URL]
    private let standaloneApplicationURLs: [URL]

    init() {
        let fileManager = FileManager.default
        roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        standaloneApplicationURLs = [
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
        ]
    }

    init(roots: [URL], standaloneApplicationURLs: [URL]) {
        self.roots = roots
        self.standaloneApplicationURLs = standaloneApplicationURLs
    }

    func scan() -> [InstalledApplication] {
        let fileManager = FileManager.default
        var paths = Set<String>()
        var applications: [InstalledApplication] = []

        func appendApplication(at url: URL) {
            guard url.pathExtension.lowercased() == "app",
                  fileManager.fileExists(atPath: url.path) else {
                return
            }
            let normalizedPath = url.standardizedFileURL.path
            guard paths.insert(normalizedPath).inserted else { return }
            applications.append(InstalledApplication(url: url))
        }

        standaloneApplicationURLs.forEach(appendApplication)

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                appendApplication(at: url)
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

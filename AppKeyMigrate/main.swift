import Foundation

struct MigrationArguments {
    let sourceURL: URL
    let outputURL: URL

    init(arguments: [String]) throws {
        var source: String?
        var output: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--source" where index + 1 < arguments.count:
                index += 1
                source = arguments[index]
            case "--output" where index + 1 < arguments.count:
                index += 1
                output = arguments[index]
            default:
                throw NSError(
                    domain: "AppKeyMigrate",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "用法：AppKeyMigrate --source /path/Manico.sqlite [--output /path/bindings.json]"]
                )
            }
            index += 1
        }

        guard let source else {
            throw NSError(
                domain: "AppKeyMigrate",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "必须通过 --source 指定 Manico.sqlite 的只读副本。"]
            )
        }
        sourceURL = URL(fileURLWithPath: source).standardizedFileURL
        outputURL = output.map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? BindingStore.defaultConfigurationURL
    }
}

do {
    let arguments = try MigrationArguments(arguments: CommandLine.arguments)
    let importer = ManicoImporter()
    let imported = try importer.importBindings(from: arguments.sourceURL)
    let store = BindingStore(configurationURL: arguments.outputURL)
    let existing = try store.load()

    var merged = existing.bindings
    var existingPaths = Set(merged.map { URL(fileURLWithPath: $0.appPath).standardizedFileURL.path })
    var existingShortcuts = Set(merged.compactMap(\.shortcut))
    var mergeSkipped = 0
    for binding in imported.bindings {
        let path = URL(fileURLWithPath: binding.appPath).standardizedFileURL.path
        guard existingPaths.insert(path).inserted,
              binding.shortcut.map({ existingShortcuts.insert($0).inserted }) ?? true else {
            mergeSkipped += 1
            continue
        }
        merged.append(binding)
    }

    try BindingValidator().validate(merged)

    var backupURL: URL?
    if FileManager.default.fileExists(atPath: arguments.outputURL.path) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = formatter.string(from: Date())
        let candidate = arguments.outputURL
            .deletingPathExtension()
            .appendingPathExtension("backup-\(suffix).json")
        try FileManager.default.copyItem(at: arguments.outputURL, to: candidate)
        backupURL = candidate
    }

    try store.save(AppKeyConfiguration(bindings: merged))
    print("迁移完成：导入 \(imported.bindings.count - mergeSkipped) 个绑定，配置写入 \(arguments.outputURL.path)")
    if let backupURL { print("原配置备份：\(backupURL.path)") }
    print("跳过：空快捷键 \(imported.skippedEmpty)，无效 \(imported.skippedInvalid)，Updater/缓存 \(imported.skippedUpdater)，重复 \(imported.skippedDuplicate + mergeSkipped)")
} catch {
    FileHandle.standardError.write(Data("迁移失败：\(error.localizedDescription)\n".utf8))
    exit(1)
}

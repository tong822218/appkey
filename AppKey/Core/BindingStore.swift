import Foundation

enum BindingStoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "配置版本 \(version) 暂不受支持。"
        }
    }
}

struct BindingStore: Sendable {
    let configurationURL: URL

    init(configurationURL: URL = Self.defaultConfigurationURL) {
        self.configurationURL = configurationURL
    }

    static var defaultConfigurationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppKey", isDirectory: true)
            .appendingPathComponent("bindings.json")
    }

    func load() throws -> AppKeyConfiguration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return AppKeyConfiguration(bindings: [])
        }

        let data = try Data(contentsOf: configurationURL)
        let configuration = try JSONDecoder.appKey.decode(AppKeyConfiguration.self, from: data)
        guard configuration.schemaVersion == AppKeyConfiguration.currentSchemaVersion else {
            throw BindingStoreError.unsupportedSchema(configuration.schemaVersion)
        }
        return configuration
    }

    func save(_ configuration: AppKeyConfiguration) throws {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.appKey.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var appKey: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var appKey: JSONDecoder {
        JSONDecoder()
    }
}

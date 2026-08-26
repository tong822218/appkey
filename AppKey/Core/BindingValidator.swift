import Foundation

struct BindingValidator {
    func validate(_ bindings: [AppBinding]) throws {
        var paths = Set<String>()
        var shortcuts = Set<Shortcut>()

        for binding in bindings {
            let normalizedPath = URL(fileURLWithPath: binding.appPath).standardizedFileURL.path
            guard paths.insert(normalizedPath).inserted else {
                throw BindingValidationError.duplicateApplication(binding.displayName)
            }

            guard let shortcut = binding.shortcut else { continue }
            guard shortcut.isValid else {
                throw BindingValidationError.invalidShortcut
            }
            guard shortcuts.insert(shortcut).inserted else {
                throw BindingValidationError.duplicateShortcut(shortcut.displayText)
            }
        }
    }
}

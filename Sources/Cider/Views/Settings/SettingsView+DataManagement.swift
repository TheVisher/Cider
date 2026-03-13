import SwiftUI
import AppKit

extension SettingsView {

    // MARK: - Vault Directory

    func chooseVaultDirectory() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Select a root directory for the Cider Vault"

            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }

            let oldVaultURL = StoragePaths.vaultDirectoryURL()
            let newVaultURL = url
            guard oldVaultURL.path != newVaultURL.path else { return }

            let hasData = Self.vaultHasData(at: oldVaultURL)
            if hasData {
                let result = Self.offerMigration(
                    message: "Move your Cider data to the new location?",
                    detail: "Your bookmarks, notes, and other data can be moved from:\n\(oldVaultURL.path)\n\nTo:\n\(newVaultURL.path)",
                    moveAction: {
                        Self.migrateVault(from: oldVaultURL, to: newVaultURL)
                    }
                )
                if result == .cancelled { return }
            }

            let path = newVaultURL.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.vaultDirectory = "~" + path.dropFirst(home.count)
            } else {
                viewModel.vaultDirectory = path
            }
        }
    }

    func chooseDirectoryOverride(for type: StorageType) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Select a directory for \(type.rawValue)"

            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }

            let oldDirURL = StoragePaths.directoryURL(for: type)
            let newDirURL = url
            guard oldDirURL.path != newDirURL.path else { return }

            let hasData = Self.directoryHasData(at: oldDirURL)
            if hasData {
                let result = Self.offerMigration(
                    message: "Move your \(type.rawValue) data to the new location?",
                    detail: "Your \(type.rawValue.lowercased()) data can be moved from:\n\(oldDirURL.path)\n\nTo:\n\(newDirURL.path)",
                    moveAction: {
                        Self.migrateDirectoryContents(from: oldDirURL, to: newDirURL)
                    }
                )
                if result == .cancelled { return }
            }

            let path = newDirURL.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.setDirectoryOverride(for: type, path: "~" + path.dropFirst(home.count))
            } else {
                viewModel.setDirectoryOverride(for: type, path: path)
            }
        }
    }

    // MARK: - Vault Migration

    enum MigrationResult {
        case moved, skipped, cancelled
    }

    static func offerMigration(
        message: String,
        detail: String,
        moveAction: () -> Bool
    ) -> MigrationResult {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move Data")
        alert.addButton(withTitle: "Don't Move")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            _ = moveAction()
            return .moved
        case .alertSecondButtonReturn:
            return .skipped
        default:
            return .cancelled
        }
    }

    static func vaultHasData(at vaultURL: URL) -> Bool {
        let fm = FileManager.default
        for type in StorageType.allCases {
            let typeDir = vaultURL.appendingPathComponent(type.rawValue)
            if let contents = try? fm.contentsOfDirectory(atPath: typeDir.path),
               !contents.filter({ !$0.hasPrefix(".") || $0 == ".trash" || $0 == ".attachments" }).isEmpty {
                return true
            }
        }
        return false
    }

    static func directoryHasData(at dirURL: URL) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dirURL.path) else { return false }
        return !contents.filter({ !$0.hasPrefix(".") || $0 == ".trash" || $0 == ".attachments" }).isEmpty
    }

    @discardableResult
    static func migrateVault(from oldVault: URL, to newVault: URL) -> Bool {
        let fm = FileManager.default
        var success = true

        for type in StorageType.allCases {
            let oldDir = oldVault.appendingPathComponent(type.rawValue)
            let newDir = newVault.appendingPathComponent(type.rawValue)

            guard fm.fileExists(atPath: oldDir.path) else { continue }
            if !migrateDirectoryContents(from: oldDir, to: newDir) {
                success = false
            }
        }

        // Also migrate .ai directory (embeddings)
        let oldAI = oldVault.appendingPathComponent(".ai")
        let newAI = newVault.appendingPathComponent(".ai")
        if fm.fileExists(atPath: oldAI.path) {
            if !migrateDirectoryContents(from: oldAI, to: newAI) {
                success = false
            }
        }

        return success
    }

    @discardableResult
    static func migrateDirectoryContents(from source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        StoragePaths.ensureDirectory(destination)

        guard let items = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return true // Empty source = nothing to do
        }

        var success = true
        for item in items {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: destItem.path) {
                // Skip existing files at destination to avoid data loss
                continue
            }
            do {
                try fm.moveItem(at: item, to: destItem)
            } catch {
                success = false
            }
        }
        return success
    }

    // MARK: - Import / Export

    func importBookmarks() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.canCreateDirectories = false
            panel.allowedContentTypes = [.html]
            panel.prompt = "Import"
            panel.message = "Select a bookmark HTML file to import"

            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                let count = BookmarksStorage.shared.importNetscapeHTML(from: url)
                importResult = "Imported \(count) bookmarks"
            }
        }
    }

    func exportBookmarks() {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = "CiderBookmarks.html"
            panel.prompt = "Export"
            panel.message = "Choose where to save your bookmarks"

            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try BookmarksStorage.shared.exportNetscapeHTML(to: url)
                    exportResult = "Exported successfully"
                } catch {
                    exportResult = "Export failed"
                }
            }
        }
    }
}

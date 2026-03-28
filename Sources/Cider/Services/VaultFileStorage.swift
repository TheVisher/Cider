import Foundation
import os

/// Persists metadata overlay for VaultFiles (title, notes, labels, OCR, colors).
/// VaultFileService owns file discovery (scanning); this service owns the metadata layer.
///
/// Storage file: `.cider/vault-files/_cider_vault_files_index.json`
/// Keyed by VaultFile ID (UUID). Only files with non-default metadata get entries.
@MainActor
final class VaultFileStorage: ObservableObject {
    static let shared = VaultFileStorage()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultFileStorage"
    )

    private let indexFileName = "_cider_vault_files_index.json"
    private var metadata: [UUID: VaultFileMetadata] = [:]

    private var storageDir: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("vault-files")
    }

    private var indexFileURL: URL {
        storageDir.appendingPathComponent(indexFileName)
    }

    private init() {
        ensureDirectory()
        load()
    }

    // MARK: - Load / Save

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFileURL) else { return }
        do {
            metadata = try JSONDecoder().decode([UUID: VaultFileMetadata].self, from: data)
            logger.info("Loaded vault file metadata: \(self.metadata.count) entries")
        } catch {
            logger.warning("Failed to decode vault file metadata: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(metadata)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save vault file metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Merge with Scanned Files

    /// Applies persisted metadata onto scanned VaultFiles.
    /// Called by VaultFileService after scanning.
    func applyMetadata(to files: inout [VaultFile]) {
        for i in files.indices {
            guard let meta = metadata[files[i].id] else { continue }
            files[i].title = meta.title
            files[i].notes = meta.notes
            files[i].labelIDs = meta.labelIDs
            files[i].ocrText = meta.ocrText
            files[i].dominantColors = meta.dominantColors
        }
    }

    // MARK: - Update Metadata

    func updateTitle(_ fileID: UUID, title: String?) {
        ensureEntry(fileID)
        metadata[fileID]?.title = title
        save()
    }

    func updateNotes(_ fileID: UUID, notes: String) {
        ensureEntry(fileID)
        metadata[fileID]?.notes = notes
        save()
    }

    func assignLabel(_ fileID: UUID, labelID: UUID) {
        ensureEntry(fileID)
        if metadata[fileID]?.labelIDs.contains(labelID) == false {
            metadata[fileID]?.labelIDs.append(labelID)
            save()
        }
    }

    func removeLabel(_ fileID: UUID, labelID: UUID) {
        guard metadata[fileID] != nil else { return }
        metadata[fileID]?.labelIDs.removeAll { $0 == labelID }
        save()
    }

    func applyEnrichment(fileID: UUID, ocrText: String?, dominantColors: [String]?, title: String?) {
        ensureEntry(fileID)
        var changed = false
        if let ocrText, metadata[fileID]?.ocrText != ocrText {
            metadata[fileID]?.ocrText = ocrText; changed = true
        }
        if let dominantColors, metadata[fileID]?.dominantColors != dominantColors {
            metadata[fileID]?.dominantColors = dominantColors; changed = true
        }
        if let title, !title.isEmpty, metadata[fileID]?.title != title {
            metadata[fileID]?.title = title; changed = true
        }
        if changed { save() }
    }

    /// Migrates metadata from one file ID to another (e.g., after a file move changes the path-derived ID).
    func migrateMetadata(from oldID: UUID, to newID: UUID) {
        guard let existing = metadata.removeValue(forKey: oldID) else { return }
        metadata[newID] = existing
        save()
    }

    /// Removes metadata for a file (e.g., when permanently deleted).
    func removeMetadata(for fileID: UUID) {
        guard metadata.removeValue(forKey: fileID) != nil else { return }
        save()
    }

    /// Returns metadata for a file, if any exists.
    func metadata(for fileID: UUID) -> VaultFileMetadata? {
        metadata[fileID]
    }

    /// Restores metadata from a trashed VaultFile (re-registers after restore from trash).
    func restoreMetadata(from file: VaultFile) {
        var meta = VaultFileMetadata()
        meta.title = file.title
        meta.notes = file.notes
        meta.labelIDs = file.labelIDs
        meta.ocrText = file.ocrText
        meta.dominantColors = file.dominantColors
        metadata[file.id] = meta
        save()
    }

    // MARK: - Private

    private func ensureEntry(_ fileID: UUID) {
        if metadata[fileID] == nil {
            metadata[fileID] = VaultFileMetadata()
        }
    }
}

// MARK: - Metadata Model

struct VaultFileMetadata: Codable {
    var title: String?
    var notes: String = ""
    var labelIDs: [UUID] = []
    var ocrText: String?
    var dominantColors: [String]?
}

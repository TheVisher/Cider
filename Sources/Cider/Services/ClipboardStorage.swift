import Foundation
import os

@MainActor
final class ClipboardStorage: ObservableObject {
    static let shared = ClipboardStorage()

    @Published private(set) var items: [ClipboardItem] = []

    private let fileName = "_cider_clipboard_history.json"
    private let imagesDirName = "images"
    private let logger = Logger(subsystem: "com.cider.app", category: "ClipboardStorage")

    private var fileURL: URL {
        let dir = StoragePaths.directoryURL(for: .clipboard)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    private var imagesDirectory: URL {
        let dir = StoragePaths.directoryURL(for: .clipboard)
            .appendingPathComponent(imagesDirName)
        StoragePaths.ensureDirectory(dir)
        return dir
    }

    private init() {
        load()
    }

    // MARK: - Load / Save

    private func load() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            logger.error("Failed to load clipboard history: \(error, privacy: .public)")
        }
    }

    func reload() {
        load()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist clipboard history: \(error, privacy: .public)")
        }
    }

    // MARK: - Insert

    func insert(_ item: ClipboardItem) {
        var newItem = item

        // Write image data to disk if present
        if let imageData = item.imageData, item.type == .image {
            let fileID = UUID()
            let ext = item.imageFileExtension ?? "png"
            let imageURL = imagesDirectory.appendingPathComponent("\(fileID.uuidString).\(ext)")
            do {
                try imageData.write(to: imageURL, options: .atomic)
                newItem.imageFileID = fileID
                newItem.imageFileExtension = ext
                newItem.imageData = nil  // Clear transient data
            } catch {
                logger.error("Failed to write clipboard image: \(error, privacy: .public)")
            }
        }

        // Deduplicate: remove existing item with same text content (for URLs/text)
        if let text = newItem.textContent, newItem.type != .image {
            items.removeAll { $0.textContent == text && $0.type == newItem.type }
        }

        items.insert(newItem, at: 0)
        persist()
    }

    /// Move an existing item to the top of the history (e.g. when re-copying).
    func moveToTop(_ itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }), idx != 0 else { return }
        let item = items.remove(at: idx)
        items.insert(item, at: 0)
        persist()
    }

    // MARK: - Dismiss / Delete

    func dismiss(_ item: ClipboardItem) {
        deleteImageFile(for: item)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func dismissAll(ids: Set<UUID>) {
        let toRemove = items.filter { ids.contains($0.id) }
        for item in toRemove {
            deleteImageFile(for: item)
        }
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    func clearAll() {
        for item in items {
            deleteImageFile(for: item)
        }
        items.removeAll()
        persist()
    }

    // MARK: - Save Indicator

    func markSaved(_ itemID: UUID, savedItemID: UUID? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].isSaved = true
        items[idx].savedItemID = savedItemID
        persist()
    }

    func markUnsaved(_ itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].isSaved = false
        items[idx].savedItemID = nil
        persist()
    }

    /// Reconcile saved state against current bookmarks and notes.
    /// Any clipboard item whose savedItemID no longer exists gets unmarked.
    func reconcileSavedState(bookmarkIDs: Set<UUID>, noteIDs: Set<UUID>) {
        var changed = false
        for i in items.indices where items[i].isSaved {
            guard let savedID = items[i].savedItemID else { continue }
            let stillExists: Bool
            switch items[i].type {
            case .url, .image:
                stillExists = bookmarkIDs.contains(savedID)
            case .text, .richText:
                stillExists = noteIDs.contains(savedID)
            }
            if !stillExists {
                items[i].isSaved = false
                items[i].savedItemID = nil
                changed = true
            }
        }
        if changed { persist() }
    }

    func purgeSavedItems() {
        let saved = items.filter { $0.isSaved }
        for item in saved {
            deleteImageFile(for: item)
        }
        items.removeAll { $0.isSaved }
        persist()
    }

    // MARK: - Retention / Purge

    func purgeExpired(config: CiderConfig) {
        let now = Date()
        var removed = false

        // Text retention
        if config.clipboardRetentionDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(config.clipboardRetentionDays) * 86400)
            let expired = items.filter { $0.type != .image && $0.timestamp < cutoff }
            if !expired.isEmpty {
                items.removeAll { item in expired.contains(where: { $0.id == item.id }) }
                removed = true
            }
        }

        // Image retention
        if config.clipboardImageRetentionDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(config.clipboardImageRetentionDays) * 86400)
            let expired = items.filter { $0.type == .image && $0.timestamp < cutoff }
            for item in expired {
                deleteImageFile(for: item)
            }
            if !expired.isEmpty {
                items.removeAll { item in expired.contains(where: { $0.id == item.id }) }
                removed = true
            }
        }

        if removed { persist() }

        // Enforce image storage cap
        enforceImageStorageCap(maxMB: config.clipboardMaxImageStorageMB)
    }

    func enforceImageStorageCap(maxMB: Int) {
        guard maxMB > 0 else { return }
        let maxBytes = Int64(maxMB) * 1024 * 1024
        var currentBytes = imageStorageBytes()

        guard currentBytes > maxBytes else { return }

        // Remove oldest images first
        let imageItems = items.filter { $0.type == .image }.sorted { $0.timestamp < $1.timestamp }
        var removedIDs = Set<UUID>()

        for item in imageItems {
            guard currentBytes > maxBytes else { break }
            guard let url = imageURL(for: item) else {
                removedIDs.insert(item.id)  // Orphaned metadata — clean up
                continue
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                currentBytes -= size
            }
            deleteImageFile(for: item)
            removedIDs.insert(item.id)
        }

        if !removedIDs.isEmpty {
            items.removeAll { removedIDs.contains($0.id) }
            persist()
        }
    }

    // MARK: - Image Access

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let fileID = item.imageFileID else { return nil }
        let ext = item.imageFileExtension ?? "png"
        return imagesDirectory.appendingPathComponent("\(fileID.uuidString).\(ext)")
    }

    // MARK: - Storage Size

    func totalStorageBytes() -> Int64 {
        let jsonSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            jsonSize = size
        } else {
            jsonSize = 0
        }
        return jsonSize + imageStorageBytes()
    }

    func imageStorageBytes() -> Int64 {
        let dir = imagesDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Private

    private func deleteImageFile(for item: ClipboardItem) {
        guard let url = imageURL(for: item) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

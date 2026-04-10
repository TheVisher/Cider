import AppKit
import Combine
import Foundation
import os

/// Manages contacts as individual .vcf files on disk, mirrored to SQLite.
///
/// File layout:
/// - Unfiled contacts: `Inbox/Contacts/{name}.vcf`
/// - Filed contacts: `{UserFolder}/{name}.vcf`
/// - Avatars: `.cider/contacts/.contact-avatars/{uuid}.jpg`
/// - Trash: `.cider/contacts/.trash/`
@MainActor
final class ContactStorage: ObservableObject {
    static let shared = ContactStorage()

    @Published private(set) var contacts: [ContactCard] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "ContactStorage"
    )

    private let fileExtension = "vcf"

    /// Per-contact metadata persisted in the index file.
    private struct IndexEntry: Codable, Equatable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
    }

    private var index: [UUID: IndexEntry] = [:]
    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    /// Returns the encoded folder_id TEXT if the folder exists in the target
    /// database, otherwise nil. Used to defuse items.folder_id FK violations
    /// when in-memory state has drifted from SQLite.
    private func resolveSafeFolderID(_ db: CiderDatabase, folderID: UUID?) throws -> String? {
        guard let id = folderID else { return nil }
        let encoded = DatabaseHelpers.encode(id)
        let stmt = try db.prepare("SELECT 1 FROM folders WHERE id = ? LIMIT 1;")
        stmt.bind(encoded, at: 1)
        let exists = try stmt.step()
        return exists ? encoded : nil
    }

    /// The .cider/contacts/ directory (index + avatars + trash).
    private var metadataDirectoryURL: URL {
        StoragePaths.cachedDirectoryURL(for: .contacts)
    }

    /// The Inbox/Contacts/ directory for unfiled .vcf files.
    private var inboxDirectoryURL: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .contacts)
    }

    /// The vault root directory.
    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private var inboxWatcher: FSEventsWatcher?
    private var vaultFilesystemObserver: NSObjectProtocol?
    private var isScanning = false
    private var pendingRescan = false

    private init() {
        ensureDirectories()
        loadIndex()

        // Try SQLite first (mirrors DateCardStorage/TodoCardStorage/NotesStorage pattern).
        if let db = resolvedDatabase {
            loadContactsFromDatabase(db)
            if !contacts.isEmpty {
                startWatching()
                startVaultFilesystemObservation()
                return
            }
        }

        scanAndLoad()
        startWatching()
        startVaultFilesystemObservation()

        // One-time migration: persist JSON/.vcf-sourced contacts to SQLite.
        // `persistContactToDatabaseInner` scrubs dangling folder_id references
        // at the lowest level so a single stale reference can't abort the
        // whole migration.
        if !contacts.isEmpty, let db = resolvedDatabase {
            logger.info("Migrating \(self.contacts.count) contacts from .vcf/JSON to SQLite")
            do {
                try db.withTransaction {
                    for contact in self.contacts {
                        try self.persistContactToDatabaseInner(db, contact: contact)
                    }
                }
            } catch {
                logger.error("Failed to migrate contacts to SQLite: \(error.localizedDescription)")
            }
        }
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT scan the file system — tests call loadContactsFromDatabase() directly
    /// or use the persist/delete helpers.
    init(database: CiderDatabase) {
        self.database = database
    }

    /// Testing-only: seed the in-memory index so that `persistContactToDatabase`
    /// picks up a specific filename (used to verify that uniquified filenames
    /// like "Jane Doe (2).vcf" round-trip through items.relative_path).
    func _setIndexEntryForTesting(
        contactID: UUID,
        filename: String,
        folderID: UUID? = nil
    ) {
        index[contactID] = IndexEntry(
            filename: filename,
            folderID: folderID,
            labelIDs: nil,
            createdAt: Date()
        )
    }

    /// Testing-only: read the filename currently tracked in the index for a contact.
    func _indexFilenameForTesting(contactID: UUID) -> String? {
        index[contactID]?.filename
    }

    func startWatching() {
        inboxWatcher?.stop()
        inboxWatcher = FSEventsWatcher(path: inboxDirectoryURL.path, latency: 1.0) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isScanning {
                    self.pendingRescan = true
                } else {
                    self.rescan()
                }
            }
        }
        inboxWatcher?.start()
    }

    func rescan() {
        guard !isScanning else { pendingRescan = true; return }
        isScanning = true
        let previousIDs = Set(contacts.map(\.id))
        defer {
            isScanning = false
            if pendingRescan {
                pendingRescan = false
                rescan()
            }
        }
        scanAndLoad()
        syncScanToDatabase(previousIDs: previousIDs)
    }

    // MARK: - Directory Setup

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: inboxDirectoryURL, withIntermediateDirectories: true)
    }

    private func startVaultFilesystemObservation() {
        vaultFilesystemObserver = NotificationCenter.default.addObserver(
            forName: .vaultFilesystemDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rescan()
            }
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createContact(id: UUID = UUID(), displayName: String) -> ContactCard {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Contact" : trimmed
        let contact = ContactCard(id: id, displayName: finalName)

        let filename = uniqueFilename(for: finalName, in: inboxDirectoryURL)
        guard writeVCardFile(for: contact, to: inboxDirectoryURL.appendingPathComponent(filename)) else {
            // Disk write failed — do NOT add to in-memory array or SQLite, so the UI
            // doesn't render a phantom card that isn't on disk. Return the struct so
            // the non-optional signature holds; caller will find it missing on reload.
            logger.error("createContact aborted for \(contact.id): initial .vcf write failed")
            return contact
        }

        index[contact.id] = IndexEntry(
            filename: filename,
            folderID: nil,
            labelIDs: nil,
            createdAt: contact.createdAt
        )
        saveIndex()

        contacts.append(contact)
        sortContacts()
        persistContactToDatabase(contact)
        return contact
    }

    @discardableResult
    func updateContact(_ updated: ContactCard) -> Bool {
        guard let idx = contacts.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()

        // If the display name changed, rename the file
        let oldEntry = index[updated.id]
        let oldFilename = oldEntry?.filename
        let newBaseName = sanitizedFilename(copy.displayName)
        let dirURL = resolveDirectoryURL(folderID: copy.folderID)
        var filename = oldFilename ?? uniqueFilename(for: newBaseName, in: dirURL)

        // Rename file if title changed
        if let oldFilename, sanitizedFilename(contacts[idx].displayName) != newBaseName {
            let newFilename = uniqueFilename(for: newBaseName, in: dirURL, excluding: oldFilename)
            let oldURL = dirURL.appendingPathComponent(oldFilename)
            let newURL = dirURL.appendingPathComponent(newFilename)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                filename = newFilename
            }
        }

        guard writeVCardFile(for: copy, to: dirURL.appendingPathComponent(filename)) else {
            // Disk write failed — leave in-memory state, index, and SQLite untouched.
            logger.error("updateContact aborted for \(updated.id): .vcf write failed")
            return false
        }

        contacts[idx] = copy
        index[updated.id] = IndexEntry(
            filename: filename,
            folderID: copy.folderID,
            labelIDs: copy.labelIDs.isEmpty ? nil : copy.labelIDs,
            createdAt: oldEntry?.createdAt ?? copy.createdAt
        )
        saveIndex()
        sortContacts()
        persistContactToDatabase(copy)
        return true
    }

    @discardableResult
    func deleteContact(_ id: UUID) -> TrashItem? {
        guard let contact = contacts.first(where: { $0.id == id }) else { return nil }

        // Resolve the .vcf file URL so TrashStorage can move it
        let vcfFileURL = resolveFileURL(for: id)
        let trashItem = TrashStorage.shared.trashContact(
            contact,
            contactsDir: metadataDirectoryURL,
            vcfFileURL: vcfFileURL
        )

        contacts.removeAll { $0.id == id }
        index.removeValue(forKey: id)
        saveIndex()
        deleteContactFromDatabase(id)
        return trashItem
    }

    @discardableResult
    func assignContact(_ id: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = contacts.firstIndex(where: { $0.id == id }) else { return false }
        guard contacts[idx].folderID != folderID else { return true }

        let contact = contacts[idx]
        guard let entry = index[id] else { return false }
        let filename = entry.filename

        let oldDirURL = resolveDirectoryURL(folderID: contact.folderID)
        let newDirURL = resolveDirectoryURL(folderID: folderID)
        let oldFileURL = oldDirURL.appendingPathComponent(filename)

        // Generate a collision-free filename in the destination directory
        let newFilename = uniqueFilename(for: contact.displayName, in: newDirURL)
        let newFileURL = newDirURL.appendingPathComponent(newFilename)

        if oldFileURL != newFileURL {
            let fm = FileManager.default
            try? fm.createDirectory(at: newDirURL, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: oldFileURL, to: newFileURL)
            } catch {
                logger.error("Failed to move contact file: \(error.localizedDescription)")
                return false
            }
        }

        contacts[idx].folderID = folderID
        contacts[idx].updatedAt = Date()

        var updatedEntry = entry
        updatedEntry.folderID = folderID
        updatedEntry.filename = newFilename
        index[id] = updatedEntry
        saveIndex()
        persistContactToDatabase(contacts[idx])
        return true
    }

    func contact(for id: UUID) -> ContactCard? {
        contacts.first { $0.id == id }
    }

    func removeLabelsFromAll(labelID: UUID) {
        var modifiedIDs: Set<UUID> = []
        for i in contacts.indices where contacts[i].labelIDs.contains(labelID) {
            contacts[i].labelIDs.removeAll { $0 == labelID }
            contacts[i].updatedAt = Date()
            modifiedIDs.insert(contacts[i].id)
        }
        if !modifiedIDs.isEmpty {
            let modified = contacts.filter { modifiedIDs.contains($0.id) }
            // Only persist to SQLite for contacts whose on-disk write actually happened.
            var persistable: [ContactCard] = []
            for contact in modified {
                if writeVCFAndIndex(for: contact) {
                    persistable.append(contact)
                }
            }
            saveIndex()
            // Persist all affected contacts in a single transaction.
            if !persistable.isEmpty, let db = resolvedDatabase {
                do {
                    try db.withTransaction {
                        for contact in persistable {
                            try self.persistContactToDatabaseInner(db, contact: contact)
                        }
                    }
                } catch {
                    logger.error("Failed to batch-persist contacts after label removal: \(error.localizedDescription)")
                }
            }
        }
    }

    func reload() {
        loadIndex()
        scanAndLoad()
    }

    // MARK: - Restore from Trash

    func restoreFromTrash(_ contact: ContactCard) {
        guard !contacts.contains(where: { $0.id == contact.id }) else { return }

        let dirURL = resolveDirectoryURL(folderID: contact.folderID)
        let filename = uniqueFilename(for: contact.displayName, in: dirURL)

        // Check if the .vcf file exists in trash and move it back
        let trashDir = metadataDirectoryURL.appendingPathComponent(".trash")
        let fm = FileManager.default
        let trashFiles = (try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil)) ?? []

        // Try to find the trashed .vcf by parsing each file and matching the UUID
        var restored = false
        for file in trashFiles where file.pathExtension == fileExtension {
            if let parsed = VCardSerializer.parse((try? String(contentsOf: file, encoding: .utf8)) ?? ""),
               parsed.id == contact.id {
                let destURL = dirURL.appendingPathComponent(filename)
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try? fm.moveItem(at: file, to: destURL)
                restored = true
                break
            }
        }

        // If no trashed file found, write a fresh .vcf from the payload
        if !restored {
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            guard writeVCardFile(for: contact, to: dirURL.appendingPathComponent(filename)) else {
                logger.error("restoreFromTrash aborted for contact \(contact.id): .vcf write failed")
                return
            }
        }

        index[contact.id] = IndexEntry(
            filename: filename,
            folderID: contact.folderID,
            labelIDs: contact.labelIDs.isEmpty ? nil : contact.labelIDs,
            createdAt: contact.createdAt
        )
        saveIndex()

        contacts.append(contact)
        sortContacts()
        persistContactToDatabase(contact)
    }

    // MARK: - Avatar Storage

    func avatarDirectoryURL() -> URL {
        metadataDirectoryURL.appendingPathComponent(".contact-avatars", isDirectory: true)
    }

    func avatarURL(for id: UUID) -> URL {
        avatarDirectoryURL().appendingPathComponent("\(id.uuidString).jpg")
    }

    @discardableResult
    func saveAvatar(_ image: NSImage, for id: UUID) -> Bool {
        let dir = avatarDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return false }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        let maxDim: CGFloat = 400
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return false
        }

        do {
            try jpegData.write(to: avatarURL(for: id), options: .atomic)
        } catch { return false }

        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            contacts[idx].hasAvatar = true
            contacts[idx].updatedAt = Date()
            writeAndUpdateIndex(for: contacts[idx])
        }
        return true
    }

    func deleteAvatar(for id: UUID) {
        try? FileManager.default.removeItem(at: avatarURL(for: id))
        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            contacts[idx].hasAvatar = false
            contacts[idx].updatedAt = Date()
            writeAndUpdateIndex(for: contacts[idx])
        }
    }

    // MARK: - File I/O

    /// Writes a contact to disk as a .vcf file. Returns `true` on success,
    /// `false` on failure (error is logged). Callers MUST check the result
    /// before mirroring to SQLite — a failed disk write must not be mirrored.
    @discardableResult
    func writeVCardFile(for contact: ContactCard, to url: URL) -> Bool {
        let vcardString = VCardSerializer.serialize(contact)
        do {
            try vcardString.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            logger.error("Failed to write .vcf for contact \(contact.id) at \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    /// Convenience: write file and update index for an already-in-memory contact.
    /// Only persists to SQLite when the on-disk write actually happened — otherwise
    /// DB and disk would diverge, violating "files are source of truth".
    private func writeAndUpdateIndex(for contact: ContactCard) {
        guard writeVCFAndIndex(for: contact) else { return }
        saveIndex()
        persistContactToDatabase(contact)
    }

    /// Write the .vcf file and update the in-memory index. Does NOT touch SQLite
    /// or call saveIndex — callers are responsible for batching those.
    /// Returns `true` if the write and index update happened, `false` if the index
    /// entry was missing (caller should NOT proceed to persist the DB mirror).
    @discardableResult
    private func writeVCFAndIndex(for contact: ContactCard) -> Bool {
        guard let entry = index[contact.id] else {
            logger.warning("writeVCFAndIndex skipped for contact \(contact.id): missing index entry — neither disk nor DB will be updated")
            return false
        }
        let dirURL = resolveDirectoryURL(folderID: contact.folderID)
        guard writeVCardFile(for: contact, to: dirURL.appendingPathComponent(entry.filename)) else {
            return false
        }
        var updated = entry
        updated.labelIDs = contact.labelIDs.isEmpty ? nil : contact.labelIDs
        index[contact.id] = updated
        return true
    }

    /// Resolves the absolute file URL for a contact by looking up its index entry.
    func resolveFileURL(for contactID: UUID) -> URL? {
        guard let entry = index[contactID] else { return nil }
        let dirURL = resolveDirectoryURL(folderID: entry.folderID)
        return dirURL.appendingPathComponent(entry.filename)
    }

    /// Returns the directory a contact's .vcf file should live in.
    private func resolveDirectoryURL(folderID: UUID?) -> URL {
        if let folderID, let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            return vaultRoot.appendingPathComponent(vaultFolder.relativePath)
        }
        return inboxDirectoryURL
    }

    // MARK: - Index I/O

    // Task 13: JSON index persistence removed. The in-memory `index` dict is
    // rebuilt on launch from SQLite (`loadContactsFromDatabase`) and from .vcf
    // scan (`scanAndLoad`). Stubs retained so the mutation call sites stay put.
    private func loadIndex() { /* no-op */ }
    private func saveIndex() { /* no-op */ }

    // MARK: - Scan & Load

    /// Loads contacts from .vcf files found in Inbox/Contacts/ and vault folders.
    private func scanAndLoad() {
        let fm = FileManager.default
        var loadedContacts: [ContactCard] = []
        var needsSave = false
        var adoptedContacts: [ContactCard] = []

        // Build reverse map: filename → UUID from existing index
        var filenameToUUID: [String: UUID] = [:]
        for (uuid, entry) in index {
            filenameToUUID[entry.filename] = uuid
        }

        // Scan Inbox/Contacts/ for unfiled .vcf files
        if let files = try? fm.contentsOfDirectory(at: inboxDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == fileExtension {
                let filename = file.lastPathComponent
                if let uuid = filenameToUUID[filename], let entry = index[uuid] {
                    // Known file — parse it
                    if let contact = parseVCardFile(at: file, expectedID: uuid, entry: entry) {
                        loadedContacts.append(contact)
                    }
                } else {
                    // Orphan .vcf file (not in index) — adopt it
                    if let contact = adoptOrphanVCard(at: file, folderID: nil) {
                        loadedContacts.append(contact)
                        adoptedContacts.append(contact)
                        needsSave = true
                    }
                }
            }
        }

        // Scan vault folders for filed .vcf files (from index + orphan adoption)
        let loadedIDs = Set(loadedContacts.map(\.id))
        var scannedFolderIDs: Set<UUID> = []

        for (uuid, entry) in index {
            guard let folderID = entry.folderID else { continue }
            scannedFolderIDs.insert(folderID)
            guard !loadedIDs.contains(uuid) else { continue }

            guard let vaultFolder = VaultFolderService.shared.folder(for: folderID) else { continue }
            let filePath = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                .appendingPathComponent(entry.filename)
            guard fm.fileExists(atPath: filePath.path) else { continue }

            if let contact = parseVCardFile(at: filePath, expectedID: uuid, entry: entry) {
                loadedContacts.append(contact)
            }
        }

        // Adopt orphan .vcf files in vault folders (user-dropped files)
        let allLoadedIDs = Set(loadedContacts.map(\.id))
        // Build O(1) lookup for known folder+filename pairs
        let knownFolderFiles: Set<String> = Set(index.values.compactMap { entry in
            guard let fid = entry.folderID else { return nil }
            return "\(fid.uuidString):\(entry.filename)"
        })
        for folder in VaultFolderService.shared.folders {
            let folderDir = vaultRoot.appendingPathComponent(folder.relativePath)
            guard let files = try? fm.contentsOfDirectory(at: folderDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == fileExtension {
                let filename = file.lastPathComponent
                if knownFolderFiles.contains("\(folder.id.uuidString):\(filename)") { continue }

                if let contact = adoptOrphanVCard(at: file, folderID: folder.id),
                   !allLoadedIDs.contains(contact.id) {
                    loadedContacts.append(contact)
                    adoptedContacts.append(contact)
                    needsSave = true
                }
            }
        }

        contacts = loadedContacts
        sortContacts()
        if needsSave { saveIndex() }
        logger.info("Loaded \(self.contacts.count) contacts from .vcf files")

        // Persist adopted orphan contacts to SQLite so future DB-first cold loads find them.
        if !adoptedContacts.isEmpty, let db = resolvedDatabase {
            do {
                try db.withTransaction {
                    for contact in adoptedContacts {
                        try self.persistContactToDatabaseInner(db, contact: contact)
                    }
                }
            } catch {
                logger.error("Failed to persist adopted contacts: \(error.localizedDescription)")
            }
        }
    }

    private func syncScanToDatabase(previousIDs: Set<UUID>) {
        guard let db = resolvedDatabase else { return }
        let currentIDs = Set(contacts.map(\.id))
        let removedIDs = previousIDs.subtracting(currentIDs)
        do {
            try db.withTransaction {
                for contact in self.contacts {
                    try self.persistContactToDatabaseInner(db, contact: contact)
                }
                for removedID in removedIDs {
                    let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
                    stmt.bind(DatabaseHelpers.encode(removedID), at: 1)
                    try stmt.step()
                }
            }
            logger.info("Rescan synced \(self.contacts.count) contacts to SQLite (removed \(removedIDs.count))")
        } catch {
            logger.error("Failed to sync contact rescan to SQLite: \(error.localizedDescription)")
        }
    }

    /// Parses a .vcf file, using the index entry to fill in folderID/labelIDs if not in the file.
    private func parseVCardFile(at url: URL, expectedID: UUID, entry: IndexEntry) -> ContactCard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              var contact = VCardSerializer.parse(content) else { return nil }
        // Ensure the UUID matches what the index says
        guard contact.id == expectedID else { return nil }
        // Apply index metadata (folderID may not be in the .vcf)
        contact.folderID = entry.folderID
        return contact
    }

    /// Adopts a .vcf file that exists on disk but isn't in the index.
    private func adoptOrphanVCard(at url: URL, folderID: UUID?) -> ContactCard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              var contact = VCardSerializer.parse(content) else { return nil }

        contact.folderID = folderID
        let filename = url.lastPathComponent

        index[contact.id] = IndexEntry(
            filename: filename,
            folderID: folderID,
            labelIDs: contact.labelIDs.isEmpty ? nil : contact.labelIDs,
            createdAt: contact.createdAt
        )

        logger.info("Adopted orphan .vcf: \(filename)")
        return contact
    }

    // MARK: - Filename Helpers

    private func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized.isEmpty ? "Untitled Contact" : sanitized
    }

    private func uniqueFilename(for displayName: String, in dirURL: URL, excluding: String? = nil) -> String {
        let baseName = sanitizedFilename(displayName)
        let candidate = "\(baseName).\(fileExtension)"
        if candidate != excluding && !FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(candidate).path) {
            return candidate
        }
        var counter = 2
        while true {
            let numbered = "\(baseName) (\(counter)).\(fileExtension)"
            if numbered != excluding && !FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(numbered).path) {
                return numbered
            }
            counter += 1
        }
    }

    // MARK: - Sort

    private func sortContacts() {
        contacts.sort { lhs, rhs in
            let cmp = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Database Persistence

    /// Link types that may be persisted to `item_links`. Links to non-migrated types
    /// (e.g. `session`, `externalFile`) are silently skipped — their targets don't
    /// exist as rows in `items` and would violate the foreign key.
    private static let linkableEntityTypes: Set<String> = [
        "bookmark", "note", "todo", "dateCard", "contact", "vaultFile"
    ]

    // Internal for testing
    /// SELECT all contacts from the database (items JOIN contacts), loading labelIDs from
    /// item_labels and linkedEntities from item_links. Also rehydrates `self.index`
    /// so mutation paths can find their entries after a DB-first cold launch.
    /// `ContactCard.displayName` lives in `items.title` — there is no `contacts.display_name`
    /// column.
    func loadContactsFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare("""
                SELECT i.id, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                       c.relationship_label, c.birthday, c.notes, c.email, c.phone,
                       c.address, c.has_avatar
                FROM items i
                JOIN contacts c ON c.item_id = i.id
                WHERE i.type = 'contact';
                """)
            var loaded: [ContactCard] = []
            var rebuiltIndex: [UUID: IndexEntry] = [:]
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let displayName = stmt.string(at: 1)
                let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 2))
                let updatedAt = DatabaseHelpers.decodeDate(stmt.double(at: 3))
                let folderID = DatabaseHelpers.decodeUUID(stmt.optionalString(at: 4) ?? "")
                let relativePath = stmt.optionalString(at: 5)
                let relationshipLabel = stmt.string(at: 6)
                let birthday = stmt.optionalDouble(at: 7).map(DatabaseHelpers.decodeDate)
                let notes = stmt.string(at: 8)
                let email = stmt.string(at: 9)
                let phone = stmt.string(at: 10)
                let address = stmt.string(at: 11)
                let hasAvatar = stmt.bool(at: 12)

                let labelIDs = (try? loadLabelIDs(db, itemID: id)) ?? []
                let linkedEntities = (try? loadLinkedEntities(db, sourceID: id)) ?? []

                let contact = ContactCard(
                    id: id,
                    displayName: displayName,
                    relationshipLabel: relationshipLabel,
                    birthday: birthday,
                    notes: notes,
                    email: email,
                    phone: phone,
                    address: address,
                    hasAvatar: hasAvatar,
                    labelIDs: labelIDs,
                    linkedEntities: linkedEntities,
                    folderID: folderID,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                loaded.append(contact)

                // Rehydrate the in-memory index so mutation paths work after cold load.
                // Derive the filename from `items.relative_path` (persisted on write)
                // so collision suffixes like "Jane Doe (2).vcf" are recovered exactly.
                // Fall back to a sanitized guess only if the column is missing (pre-fix
                // rows), which is still better than corrupting later writes.
                let filename: String = {
                    if let rel = relativePath, !rel.isEmpty {
                        let last = (rel as NSString).lastPathComponent
                        if !last.isEmpty { return last }
                    }
                    return "\(sanitizedFilename(displayName)).\(fileExtension)"
                }()
                rebuiltIndex[id] = IndexEntry(
                    filename: filename,
                    folderID: folderID,
                    labelIDs: labelIDs.isEmpty ? nil : labelIDs,
                    createdAt: createdAt
                )
            }
            contacts = loaded
            index = rebuiltIndex
            sortContacts()
            logger.info("Loaded \(loaded.count) contacts from database")
        } catch {
            logger.error("Failed to load contacts from database: \(error.localizedDescription)")
            contacts = []
            index = [:]
        }
    }

    /// Load label IDs from the item_labels join table for a given item.
    private func loadLabelIDs(_ db: CiderDatabase, itemID: UUID) throws -> [UUID] {
        let stmt = try db.prepare("SELECT label_id FROM item_labels WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        var ids: [UUID] = []
        while try stmt.step() {
            if let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) {
                ids.append(id)
            }
        }
        return ids
    }

    /// Load linked entities from the item_links join table (link_type = 'linked').
    /// Infers the entity type from the target item's `items.type` column.
    /// Note: `items.type == 'event'` maps to `LibraryEntityType.dateCard`.
    private func loadLinkedEntities(_ db: CiderDatabase, sourceID: UUID) throws -> [LibraryEntityRef] {
        let stmt = try db.prepare("""
            SELECT l.target_id, i.type
            FROM item_links l
            JOIN items i ON i.id = l.target_id
            WHERE l.source_id = ? AND l.link_type = 'linked';
            """)
        stmt.bind(DatabaseHelpers.encode(sourceID), at: 1)
        var refs: [LibraryEntityRef] = []
        while try stmt.step() {
            guard let targetID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
            let rawType = stmt.string(at: 1)
            // items.type uses 'event' but LibraryEntityType uses 'dateCard'.
            let resolvedRaw = (rawType == "event") ? "dateCard" : rawType
            guard let type = LibraryEntityType(rawValue: resolvedRaw) else { continue }
            refs.append(LibraryEntityRef(type: type, entityID: targetID))
        }
        return refs
    }

    // Internal for testing
    /// Persist a single contact to the database (items + contacts + item_labels + item_links)
    /// using the resolved (shared or explicit) database inside a transaction.
    func persistContactToDatabase(_ contact: ContactCard) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for contact \(contact.id)")
            return
        }
        persistContactToDatabase(db, contact: contact)
    }

    // Internal for testing
    /// Persist a single contact to the given database inside its own transaction.
    func persistContactToDatabase(_ db: CiderDatabase, contact: ContactCard) {
        do {
            try db.withTransaction {
                try persistContactToDatabaseInner(db, contact: contact)
            }
        } catch {
            logger.error("Failed to persist contact \(contact.id) to database: \(error.localizedDescription)")
        }
    }

    /// Compute the vault-relative path for a contact, preferring the real filename tracked
    /// in the in-memory index. Falls back to the sanitized display name when the index
    /// hasn't been populated yet (e.g. initial one-time JSON migration inside `init`).
    private func relativePathForPersistence(_ contact: ContactCard) -> String? {
        let filename: String
        if let entryFilename = index[contact.id]?.filename {
            filename = entryFilename
        } else {
            filename = "\(sanitizedFilename(contact.displayName)).\(fileExtension)"
        }

        if let folderID = contact.folderID,
           let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            return "\(vaultFolder.relativePath)/\(filename)"
        }
        // Inbox contacts live under `Inbox/Contacts/{filename}`.
        return "Inbox/Contacts/\(filename)"
    }

    /// Core persist logic for a single contact — must be called inside a transaction.
    /// `ContactCard.displayName` is stored in `items.title`, NOT in a separate
    /// `contacts.display_name` column (the schema has no such column).
    private func persistContactToDatabaseInner(_ db: CiderDatabase, contact: ContactCard) throws {
        // Scrub folder_id against target DB to defuse FK failures.
        let folderIDText = try resolveSafeFolderID(db, folderID: contact.folderID)

        // 1. UPSERT into items.
        // `relative_path` stores the vault-relative .vcf path so that DB-first cold
        // loads can recover the EXACT on-disk filename (including collision suffixes
        // like "Jane Doe (2).vcf"). Guessing from the display name would orphan real files.
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'contact', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
        let itemID = DatabaseHelpers.encode(contact.id)
        let relativePath: String? = relativePathForPersistence(contact)
        itemStmt.bind(itemID, at: 1)
            .bind(contact.displayName, at: 2)
            .bind(DatabaseHelpers.encode(contact.createdAt), at: 3)
            .bind(DatabaseHelpers.encode(contact.updatedAt), at: 4)
            .bind(folderIDText, at: 5)
            .bind(relativePath, at: 6)
        try itemStmt.step()

        // 2. UPSERT into contacts. Note: no display_name column — title lives in items.
        let contactStmt = try db.prepare("""
            INSERT INTO contacts (
                item_id, relationship_label, birthday, notes, email, phone, address, has_avatar
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                relationship_label = excluded.relationship_label,
                birthday = excluded.birthday,
                notes = excluded.notes,
                email = excluded.email,
                phone = excluded.phone,
                address = excluded.address,
                has_avatar = excluded.has_avatar;
            """)
        contactStmt.bind(itemID, at: 1)
            .bind(contact.relationshipLabel, at: 2)
            .bind(contact.birthday.map(DatabaseHelpers.encode), at: 3)
            .bind(contact.notes, at: 4)
            .bind(contact.email, at: 5)
            .bind(contact.phone, at: 6)
            .bind(contact.address, at: 7)
            .bind(contact.hasAvatar ? Int64(1) : Int64(0), at: 8)
        try contactStmt.step()

        // 3. Sync item_labels: delete all, re-insert current.
        let delLabels = try db.prepare("DELETE FROM item_labels WHERE item_id = ?;")
        delLabels.bind(itemID, at: 1)
        try delLabels.step()

        if !contact.labelIDs.isEmpty {
            let insLabel = try db.prepare("INSERT OR IGNORE INTO item_labels (item_id, label_id) VALUES (?, ?);")
            for labelID in contact.labelIDs {
                insLabel.reset()
                insLabel.bind(itemID, at: 1)
                    .bind(DatabaseHelpers.encode(labelID), at: 2)
                try insLabel.step()
            }
        }

        // 4. Sync item_links: delete all 'linked' rows from this source, re-insert current.
        // Non-migrated types and links whose target row doesn't exist are silently dropped.
        //
        // KNOWN LIMITATION — first-run JSON→SQLite migration:
        // When ContactStorage runs its one-time migration loop in `init`, other
        // services (bookmarks, notes, date cards, etc.) may not have migrated yet, so
        // their target rows in `items` don't exist. The `WHERE EXISTS` guard below
        // therefore silently drops any cross-type links for those not-yet-migrated
        // targets. This is acceptable because:
        //   1. `contact.linkedEntities` remains authoritative in memory and inside
        //      the .vcf file — nothing is lost on disk.
        //   2. Any subsequent user edit to the contact re-runs this persist path,
        //      by which point all services have finished migrating and the targets
        //      do exist — so the links will be correctly re-persisted.
        //   3. Task 12 (Startup Reconciliation) will add a post-migration pass that
        //      backfills any links dropped during the first run.
        let delLinks = try db.prepare("DELETE FROM item_links WHERE source_id = ? AND link_type = 'linked';")
        delLinks.bind(itemID, at: 1)
        try delLinks.step()

        let now = DatabaseHelpers.encode(Date())
        let insLink = try db.prepare("""
            INSERT OR IGNORE INTO item_links (source_id, target_id, link_type, created_at)
            SELECT ?, ?, 'linked', ?
            WHERE EXISTS (SELECT 1 FROM items WHERE id = ?);
            """)
        for ref in contact.linkedEntities where Self.linkableEntityTypes.contains(ref.type.rawValue) {
            let target = DatabaseHelpers.encode(ref.entityID)
            insLink.reset()
            insLink.bind(itemID, at: 1)
                .bind(target, at: 2)
                .bind(now, at: 3)
                .bind(target, at: 4)
            try insLink.step()
        }
    }

    /// Delete a contact from the database by ID. CASCADE handles detail + join tables.
    func deleteContactFromDatabase(_ contactID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for contact \(contactID)")
            return
        }
        deleteContactFromDatabase(db, contactID: contactID)
    }

    // Internal for testing
    /// DELETE a contact from the given database by ID.
    func deleteContactFromDatabase(_ db: CiderDatabase, contactID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(contactID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete contact \(contactID) from database: \(error.localizedDescription)")
        }
    }
}

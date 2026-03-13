import AppKit
import Combine
import Foundation
import os

/// Legacy format — kept only for migration from the old single-JSON store.
struct ContactsSnapshot: Codable {
    var contacts: [ContactCard]
}

/// Manages contacts as individual .vcf files on disk with a lightweight JSON index.
///
/// File layout:
/// - Unfiled contacts: `Inbox/Contacts/{name}.vcf`
/// - Filed contacts: `{UserFolder}/{name}.vcf`
/// - Index: `.cider/contacts/_cider_contacts_index.json`
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

    private let indexFileName = "_cider_contacts_index.json"
    private let fileExtension = "vcf"

    /// Per-contact metadata persisted in the index file.
    private struct IndexEntry: Codable, Equatable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
    }

    private var index: [UUID: IndexEntry] = [:]

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

    private var indexURL: URL {
        metadataDirectoryURL.appendingPathComponent(indexFileName)
    }

    private init() {
        ensureDirectories()
        loadIndex()
        scanAndLoad()
    }

    // MARK: - Directory Setup

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: inboxDirectoryURL, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    @discardableResult
    func createContact(id: UUID = UUID(), displayName: String) -> ContactCard {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Contact" : trimmed
        let contact = ContactCard(id: id, displayName: finalName)

        let filename = uniqueFilename(for: finalName, in: inboxDirectoryURL)
        writeVCardFile(for: contact, to: inboxDirectoryURL.appendingPathComponent(filename))

        index[contact.id] = IndexEntry(
            filename: filename,
            folderID: nil,
            labelIDs: nil,
            createdAt: contact.createdAt
        )
        saveIndex()

        contacts.append(contact)
        sortContacts()
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

        writeVCardFile(for: copy, to: dirURL.appendingPathComponent(filename))

        contacts[idx] = copy
        index[updated.id] = IndexEntry(
            filename: filename,
            folderID: copy.folderID,
            labelIDs: copy.labelIDs.isEmpty ? nil : copy.labelIDs,
            createdAt: oldEntry?.createdAt ?? copy.createdAt
        )
        saveIndex()
        sortContacts()
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
            for contact in contacts where modifiedIDs.contains(contact.id) {
                if let entry = index[contact.id] {
                    let dirURL = resolveDirectoryURL(folderID: contact.folderID)
                    writeVCardFile(for: contact, to: dirURL.appendingPathComponent(entry.filename))
                    var updated = entry
                    updated.labelIDs = contact.labelIDs.isEmpty ? nil : contact.labelIDs
                    index[contact.id] = updated
                }
            }
            saveIndex()
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
            writeVCardFile(for: contact, to: dirURL.appendingPathComponent(filename))
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
            if let entry = index[id] {
                let dirURL = resolveDirectoryURL(folderID: contacts[idx].folderID)
                writeVCardFile(for: contacts[idx], to: dirURL.appendingPathComponent(entry.filename))
            }
            saveIndex()
        }
        return true
    }

    func deleteAvatar(for id: UUID) {
        try? FileManager.default.removeItem(at: avatarURL(for: id))
        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            contacts[idx].hasAvatar = false
            contacts[idx].updatedAt = Date()
            if let entry = index[id] {
                let dirURL = resolveDirectoryURL(folderID: contacts[idx].folderID)
                writeVCardFile(for: contacts[idx], to: dirURL.appendingPathComponent(entry.filename))
            }
            saveIndex()
        }
    }

    // MARK: - File I/O

    /// Writes a contact to disk as a .vcf file.
    private func writeVCardFile(for contact: ContactCard, to url: URL) {
        let vcardString = VCardSerializer.serialize(contact)
        try? vcardString.write(to: url, atomically: true, encoding: .utf8)
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

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: IndexEntry].self, from: data) {
            index = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
            return
        }
        index = [:]
    }

    private func saveIndex() {
        let encoded = Dictionary(uniqueKeysWithValues: index.map { ($0.key.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(encoded) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Scan & Load

    /// Loads contacts from .vcf files found in Inbox/Contacts/ and vault folders.
    private func scanAndLoad() {
        let fm = FileManager.default
        var loadedContacts: [ContactCard] = []
        var needsSave = false

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
        for folder in VaultFolderService.shared.folders {
            let folderDir = vaultRoot.appendingPathComponent(folder.relativePath)
            guard let files = try? fm.contentsOfDirectory(at: folderDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == fileExtension {
                // Skip files we already loaded from the index
                let filename = file.lastPathComponent
                let knownInThisFolder = index.values.contains { $0.filename == filename && $0.folderID == folder.id }
                if knownInThisFolder { continue }

                if let contact = adoptOrphanVCard(at: file, folderID: folder.id),
                   !allLoadedIDs.contains(contact.id) {
                    loadedContacts.append(contact)
                    needsSave = true
                }
            }
        }

        contacts = loadedContacts
        sortContacts()
        if needsSave { saveIndex() }
        logger.info("Loaded \(self.contacts.count) contacts from .vcf files")
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
}

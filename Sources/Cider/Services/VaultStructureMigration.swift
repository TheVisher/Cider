import Foundation
import os

// Legacy single-file snapshot formats — retained file-privately so the one-time
// pre-SQLite migrations below can still decode old vaults if they exist. These
// used to live in the corresponding storage services (ContactsSnapshot etc.)
// but were removed as part of the Task 13 JSON index cleanup.
private struct LegacyContactsSnapshot: Codable {
    var contacts: [ContactCard]
}

private struct LegacyTodoCardsSnapshot: Codable {
    var todoCards: [TodoCard]
}

private struct LegacyDateCardsSnapshot: Codable {
    var dateCards: [DateCard]
}

/// One-time migration that moves all app-internal directories from the vault root
/// into the hidden `.cider/` subdirectory. After migration, the vault root contains
/// only user-visible folders (plus CLAUDE.md and Unsorted/).
enum VaultStructureMigration {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultStructureMigration"
    )

    /// Old directory name → new name inside `.cider/`.
    private static let directoryMappings: [(old: String, new: String)] = {
        var mappings: [(String, String)] = StorageType.allCases.map { type in
            (type.rawValue, type.ciderSubpath)
        }
        // Non-StorageType directories
        mappings.append((".cider-folders", "folders"))
        mappings.append(("AI Chat", "ai-chat"))
        mappings.append((".ai", "ai"))
        return mappings
    }()

    /// Runs the migration if it hasn't been completed yet.
    /// Call before `StoragePaths.ensureVaultStructure()` in AppDelegate.
    static func migrateIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateVaultToCiderDir else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let ciderDir = vaultRoot.appendingPathComponent(StoragePaths.ciderInternalDir)

        logger.info("Starting vault → .cider/ migration")

        // Create .cider/ parent
        do {
            try fm.createDirectory(at: ciderDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create .cider/ directory: \(error.localizedDescription)")
            return
        }

        // Move each old directory to new location
        for mapping in directoryMappings {
            let source = vaultRoot.appendingPathComponent(mapping.old)
            let dest = ciderDir.appendingPathComponent(mapping.new)

            guard fm.fileExists(atPath: source.path) else {
                logger.info("Skipping \(mapping.old) — does not exist")
                continue
            }

            if fm.fileExists(atPath: dest.path) {
                logger.info("Skipping \(mapping.old) → .cider/\(mapping.new) — destination already exists")
                continue
            }

            do {
                try fm.moveItem(at: source, to: dest)
                logger.info("Moved \(mapping.old) → .cider/\(mapping.new)")
            } catch {
                logger.error("Failed to move \(mapping.old): \(error.localizedDescription)")
            }
        }

        // Move .cider-index.json → .cider/index.json
        let oldIndex = vaultRoot.appendingPathComponent(".cider-index.json")
        let newIndex = ciderDir.appendingPathComponent("index.json")
        if fm.fileExists(atPath: oldIndex.path) && !fm.fileExists(atPath: newIndex.path) {
            do {
                try fm.moveItem(at: oldIndex, to: newIndex)
                logger.info("Moved .cider-index.json → .cider/index.json")
            } catch {
                logger.error("Failed to move index: \(error.localizedDescription)")
            }
        }

        // Invalidate cached paths so they resolve to the new locations
        StoragePaths.invalidateCachedDirectory()

        // Set flag and save
        config.didMigrateVaultToCiderDir = true
        config.save()

        logger.info("Vault → .cider/ migration complete")
    }

    // MARK: - Phase 2: Move content files from .cider/ to Inbox/

    /// Moves .webloc files from .cider/bookmarks/ to Inbox/Bookmarks/ and
    /// .md files from .cider/notes/ to Inbox/Notes/.
    /// Metadata files (_cider_bookmarks_metadata.json, _cider_notes_index.json, etc.) stay in .cider/.
    /// Call after `migrateIfNeeded()` and before storage services initialize.
    static func migrateContentToInboxIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateContentToInbox else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let ciderDir = vaultRoot.appendingPathComponent(StoragePaths.ciderInternalDir)
        let inboxDir = vaultRoot.appendingPathComponent(StoragePaths.inboxDir)

        logger.info("Starting .cider/ → Inbox/ content migration")

        // --- Bookmarks: move .webloc files + sidecar + assets ---
        let ciderBookmarksDir = ciderDir.appendingPathComponent(StorageType.bookmarks.ciderSubpath)
        let inboxBookmarksDir = inboxDir.appendingPathComponent("Bookmarks")

        do {
            try fm.createDirectory(at: inboxBookmarksDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Inbox/Bookmarks/: \(error.localizedDescription)")
        }

        // Move .webloc files and per-folder sidecar JSONs from .cider/bookmarks/ → Inbox/Bookmarks/
        // Keep: _cider_bookmarks_metadata.json (master metadata), .thumbnails/, .originals/, .trash/
        let bookmarkKeepPrefixes: Set<String> = ["_cider_bookmarks_metadata.json", ".thumbnails", ".originals", ".trash"]
        if let contents = try? fm.contentsOfDirectory(at: ciderBookmarksDir, includingPropertiesForKeys: nil) {
            for item in contents {
                let name = item.lastPathComponent
                if bookmarkKeepPrefixes.contains(name) { continue }

                let dest = inboxBookmarksDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dest.path) { continue }
                do {
                    try fm.moveItem(at: item, to: dest)
                } catch {
                    logger.error("Failed to move bookmark content \(name): \(error.localizedDescription)")
                }
            }
        }

        // Update bookmark relativePaths in the master metadata JSON
        updateBookmarkMetadataPaths(
            metadataURL: ciderBookmarksDir.appendingPathComponent("_cider_bookmarks_metadata.json"),
            oldPrefix: "\(StoragePaths.ciderInternalDir)/\(StorageType.bookmarks.ciderSubpath)",
            newPrefix: "\(StoragePaths.inboxDir)/Bookmarks"
        )

        // --- Notes: move .md files + .attachments/ + .history/ ---
        let ciderNotesDir = ciderDir.appendingPathComponent(StorageType.notes.ciderSubpath)
        let inboxNotesDir = inboxDir.appendingPathComponent("Notes")

        do {
            try fm.createDirectory(at: inboxNotesDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Inbox/Notes/: \(error.localizedDescription)")
        }

        // Move only .md files from .cider/notes/ → Inbox/Notes/
        // Keep: index file, .history/ (snapshots), .attachments/, .trash/
        let noteKeepNames: Set<String> = ["_cider_notes_index.json", ".trash", ".history", ".attachments"]
        if let contents = try? fm.contentsOfDirectory(at: ciderNotesDir, includingPropertiesForKeys: nil) {
            for item in contents {
                let name = item.lastPathComponent
                if noteKeepNames.contains(name) { continue }

                let dest = inboxNotesDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dest.path) { continue }
                do {
                    try fm.moveItem(at: item, to: dest)
                } catch {
                    logger.error("Failed to move note content \(name): \(error.localizedDescription)")
                }
            }
        }

        // Create remaining Inbox subfolders for future use
        for typeName in ["Contacts", "Todos", "Date Cards"] {
            let subdir = inboxDir.appendingPathComponent(typeName)
            try? fm.createDirectory(at: subdir, withIntermediateDirectories: true)
        }

        // Invalidate cached paths
        StoragePaths.invalidateCachedDirectory()

        config.didMigrateContentToInbox = true
        config.save()

        logger.info(".cider/ → Inbox/ content migration complete")
    }

    // MARK: - Phase 3: Migrate contacts from single JSON to per-file .vcf

    /// Reads the old _cider_contacts.json, writes individual .vcf files to Inbox/Contacts/,
    /// builds the contacts index, and renames the old JSON as a backup.
    static func migrateContactsToPerFileIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateContactsToPerFile else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let contactsDir = vaultRoot
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent(StorageType.contacts.ciderSubpath)
        let oldJSONURL = contactsDir.appendingPathComponent("_cider_contacts.json")

        // Nothing to migrate if the old file doesn't exist
        guard fm.fileExists(atPath: oldJSONURL.path) else {
            config.didMigrateContactsToPerFile = true
            config.save()
            return
        }

        logger.info("Starting contacts → per-file .vcf migration")

        // Read old snapshot
        guard let data = try? Data(contentsOf: oldJSONURL) else {
            config.didMigrateContactsToPerFile = true
            config.save()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(LegacyContactsSnapshot.self, from: data) else {
            logger.error("Failed to decode old contacts JSON")
            config.didMigrateContactsToPerFile = true
            config.save()
            return
        }

        // Ensure Inbox/Contacts/ exists
        let inboxContactsDir = vaultRoot
            .appendingPathComponent(StoragePaths.inboxDir)
            .appendingPathComponent("Contacts")
        try? fm.createDirectory(at: inboxContactsDir, withIntermediateDirectories: true)

        // Write individual .vcf files and build the index
        var indexEntries: [String: ContactPerFileIndexEntry] = [:]
        var usedFilenames: Set<String> = []

        for contact in snapshot.contacts {
            // During migration, write all .vcf files to Inbox/Contacts/.
            // The index preserves each contact's folderID, so when ContactStorage loads
            // and the user assigns a contact to a folder, the file will be moved then.
            let destDir = inboxContactsDir

            // Generate unique filename
            let baseName = sanitizeContactFilename(contact.displayName)
            var filename = "\(baseName).vcf"
            var counter = 2
            while usedFilenames.contains(filename) || fm.fileExists(atPath: destDir.appendingPathComponent(filename).path) {
                filename = "\(baseName) (\(counter)).vcf"
                counter += 1
            }
            usedFilenames.insert(filename)

            // Write the .vcf file
            let vcardString = VCardSerializer.serialize(contact)
            let destURL = destDir.appendingPathComponent(filename)
            do {
                try vcardString.write(to: destURL, atomically: true, encoding: .utf8)
                logger.info("Wrote \(filename)")
            } catch {
                logger.error("Failed to write \(filename): \(error.localizedDescription)")
                continue
            }

            indexEntries[contact.id.uuidString] = ContactPerFileIndexEntry(
                filename: filename,
                folderID: contact.folderID,
                labelIDs: contact.labelIDs.isEmpty ? nil : contact.labelIDs,
                createdAt: contact.createdAt
            )
        }

        // Write the index
        let indexURL = contactsDir.appendingPathComponent("_cider_contacts_index.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let indexData = try? encoder.encode(indexEntries) {
            try? indexData.write(to: indexURL, options: .atomic)
        }

        // Rename old JSON as backup
        let backupURL = contactsDir.appendingPathComponent("_cider_contacts_legacy.json")
        try? fm.moveItem(at: oldJSONURL, to: backupURL)

        config.didMigrateContactsToPerFile = true
        config.save()

        logger.info("Contacts → per-file .vcf migration complete: \(snapshot.contacts.count) contacts")
    }

    // MARK: - Phase 4: Migrate todos from single JSON to per-file .ics

    /// Reads the old _cider_todo_cards.json, writes individual .ics files to Inbox/Todos/,
    /// builds the todos index, and renames the old JSON as a backup.
    static func migrateTodosToPerFileIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateTodosToPerFile else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let todosDir = vaultRoot
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent(StorageType.todos.ciderSubpath)
        let oldJSONURL = todosDir.appendingPathComponent("_cider_todo_cards.json")

        // Nothing to migrate if the old file doesn't exist
        guard fm.fileExists(atPath: oldJSONURL.path) else {
            config.didMigrateTodosToPerFile = true
            config.save()
            return
        }

        logger.info("Starting todos → per-file .ics migration")

        guard let data = try? Data(contentsOf: oldJSONURL) else {
            config.didMigrateTodosToPerFile = true
            config.save()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(LegacyTodoCardsSnapshot.self, from: data) else {
            logger.error("Failed to decode old todos JSON")
            config.didMigrateTodosToPerFile = true
            config.save()
            return
        }

        // Ensure Inbox/Todos/ exists
        let inboxTodosDir = vaultRoot
            .appendingPathComponent(StoragePaths.inboxDir)
            .appendingPathComponent("Todos")
        try? fm.createDirectory(at: inboxTodosDir, withIntermediateDirectories: true)

        // Write individual .ics files and build the index
        var indexEntries: [String: TodoPerFileIndexEntry] = [:]
        var usedFilenames: Set<String> = []

        for todo in snapshot.todoCards {
            let destDir = inboxTodosDir
            let baseName = sanitizeTodoFilename(todo.title)
            var filename = "\(baseName).ics"
            var counter = 2
            while usedFilenames.contains(filename) || fm.fileExists(atPath: destDir.appendingPathComponent(filename).path) {
                filename = "\(baseName) (\(counter)).ics"
                counter += 1
            }
            usedFilenames.insert(filename)

            let icsString = ICalendarSerializer.serializeTodo(todo)
            let destURL = destDir.appendingPathComponent(filename)
            do {
                try icsString.write(to: destURL, atomically: true, encoding: .utf8)
                logger.info("Wrote \(filename)")
            } catch {
                logger.error("Failed to write \(filename): \(error.localizedDescription)")
                continue
            }

            indexEntries[todo.id.uuidString] = TodoPerFileIndexEntry(
                filename: filename,
                folderID: todo.folderID,
                labelIDs: todo.labelIDs.isEmpty ? nil : todo.labelIDs,
                createdAt: todo.createdAt,
                isCompleted: todo.isCompleted,
                dueDate: todo.dueDate,
                priority: todo.priority
            )
        }

        // Write the index
        let indexURL = todosDir.appendingPathComponent("_cider_todos_index.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let indexData = try? encoder.encode(indexEntries) {
            try? indexData.write(to: indexURL, options: .atomic)
        }

        // Rename old JSON as backup
        let backupURL = todosDir.appendingPathComponent("_cider_todo_cards_legacy.json")
        try? fm.moveItem(at: oldJSONURL, to: backupURL)

        config.didMigrateTodosToPerFile = true
        config.save()

        logger.info("Todos → per-file .ics migration complete: \(snapshot.todoCards.count) todos")
    }

    // MARK: - Phase 5: Migrate date cards from single JSON to per-file .ics

    /// Reads the old _cider_date_cards.json, writes individual .ics files to Inbox/Date Cards/,
    /// builds the date cards index, and renames the old JSON as a backup.
    static func migrateDateCardsToPerFileIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateDateCardsToPerFile else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let dateCardsDir = vaultRoot
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent(StorageType.dateCards.ciderSubpath)
        let oldJSONURL = dateCardsDir.appendingPathComponent("_cider_date_cards.json")

        guard fm.fileExists(atPath: oldJSONURL.path) else {
            config.didMigrateDateCardsToPerFile = true
            config.save()
            return
        }

        logger.info("Starting date cards → per-file .ics migration")

        guard let data = try? Data(contentsOf: oldJSONURL) else {
            config.didMigrateDateCardsToPerFile = true
            config.save()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(LegacyDateCardsSnapshot.self, from: data) else {
            logger.error("Failed to decode old date cards JSON")
            config.didMigrateDateCardsToPerFile = true
            config.save()
            return
        }

        let inboxDateCardsDir = vaultRoot
            .appendingPathComponent(StoragePaths.inboxDir)
            .appendingPathComponent("Date Cards")
        try? fm.createDirectory(at: inboxDateCardsDir, withIntermediateDirectories: true)

        var indexEntries: [String: DateCardPerFileIndexEntry] = [:]
        var usedFilenames: Set<String> = []

        for dc in snapshot.dateCards {
            let baseName = sanitizeDateCardFilename(dc.title)
            var filename = "\(baseName).ics"
            var counter = 2
            while usedFilenames.contains(filename) || fm.fileExists(atPath: inboxDateCardsDir.appendingPathComponent(filename).path) {
                filename = "\(baseName) (\(counter)).ics"
                counter += 1
            }
            usedFilenames.insert(filename)

            let icsString = ICalendarSerializer.serializeDateCard(dc)
            let destURL = inboxDateCardsDir.appendingPathComponent(filename)
            do {
                try icsString.write(to: destURL, atomically: true, encoding: .utf8)
                logger.info("Wrote \(filename)")
            } catch {
                logger.error("Failed to write \(filename): \(error.localizedDescription)")
                continue
            }

            indexEntries[dc.id.uuidString] = DateCardPerFileIndexEntry(
                filename: filename,
                folderID: dc.folderID,
                labelIDs: dc.labelIDs.isEmpty ? nil : dc.labelIDs,
                createdAt: dc.createdAt,
                isCompleted: dc.isCompleted,
                startAt: dc.startAt
            )
        }

        let indexURL = dateCardsDir.appendingPathComponent("_cider_date_cards_index.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let indexData = try? encoder.encode(indexEntries) {
            try? indexData.write(to: indexURL, options: .atomic)
        }

        let backupURL = dateCardsDir.appendingPathComponent("_cider_date_cards_legacy.json")
        try? fm.moveItem(at: oldJSONURL, to: backupURL)

        config.didMigrateDateCardsToPerFile = true
        config.save()

        logger.info("Date cards → per-file .ics migration complete: \(snapshot.dateCards.count) date cards")
    }

    private struct DateCardPerFileIndexEntry: Codable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
        var isCompleted: Bool?
        var startAt: Date?
    }

    private static func sanitizeDateCardFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized.isEmpty ? "Untitled Date Card" : sanitized
    }

    /// Minimal index entry for migration (matches TodoCardStorage.IndexEntry).
    private struct TodoPerFileIndexEntry: Codable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
        var isCompleted: Bool?
        var dueDate: Date?
        var priority: TodoPriority?
    }

    private static func sanitizeTodoFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized.isEmpty ? "Untitled Todo" : sanitized
    }

    /// Minimal index entry for migration (matches ContactStorage.IndexEntry).
    private struct ContactPerFileIndexEntry: Codable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
    }

    private static func sanitizeContactFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized.isEmpty ? "Untitled Contact" : sanitized
    }

    /// Updates bookmark relativePath entries in the master metadata JSON file.
    /// Bookmarks with paths starting with `oldPrefix` get rewritten to `newPrefix`.
    private static func updateBookmarkMetadataPaths(metadataURL: URL, oldPrefix: String, newPrefix: String) {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard var bookmarks = json["bookmarks"] as? [[String: Any]] else { return }

        var changed = false
        for i in bookmarks.indices {
            if let path = bookmarks[i]["relativePath"] as? String,
               path.hasPrefix(oldPrefix) {
                bookmarks[i]["relativePath"] = newPrefix + path.dropFirst(oldPrefix.count)
                changed = true
            }
        }

        guard changed else { return }
        json["bookmarks"] = bookmarks

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: metadataURL, options: .atomic)
            logger.info("Updated \(bookmarks.count) bookmark paths in metadata")
        }
    }
}

import Foundation

struct ItemLinkSummary: Identifiable, Equatable {
    let ref: LibraryEntityRef
    let title: String
    let subtitle: String
    let symbol: String

    var id: String { ref.id }
}

@MainActor
final class ItemLinkService {
    enum LinkError: Error, Equatable, LocalizedError {
        case unsupportedType(String)
        case itemNotFound(type: LibraryEntityType, ref: String)
        case ambiguousItem(type: LibraryEntityType, ref: String, matches: [String])

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let raw):
                return "Unsupported link type '\(raw)'. Supported types: bookmark, note, todo, dateCard, contact, vaultFile."
            case .itemNotFound(let type, let ref):
                return "No \(type.rawValue) found matching '\(ref)'."
            case .ambiguousItem(let type, let ref, let matches):
                return "Multiple \(type.rawValue) items match '\(ref)': \(matches.joined(separator: ", ")). Use an ID prefix."
            }
        }
    }

    static let shared = ItemLinkService()

    private let database: CiderDatabase
    private let bookmarks: VaultBookmarkService
    private let notes: NotesStorage
    private let dateCards: DateCardStorage
    private let contacts: ContactStorage
    private let todos: TodoCardStorage
    private let files: VaultFileService

    init(
        database: CiderDatabase = .shared,
        bookmarks: VaultBookmarkService = .shared,
        notes: NotesStorage = .shared,
        dateCards: DateCardStorage = .shared,
        contacts: ContactStorage = .shared,
        todos: TodoCardStorage = .shared,
        files: VaultFileService = .shared
    ) {
        self.database = database
        self.bookmarks = bookmarks
        self.notes = notes
        self.dateCards = dateCards
        self.contacts = contacts
        self.todos = todos
        self.files = files
    }

    static func entityType(from raw: String) throws -> LibraryEntityType {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bookmark", "bookmarks", "bm":
            return .bookmark
        case "note", "notes":
            return .note
        case "todo", "todos", "task", "tasks":
            return .todo
        case "datecard", "date-card", "date", "event", "events":
            return .dateCard
        case "contact", "contacts", "person", "people":
            return .contact
        case "vaultfile", "vault-file", "file", "files":
            return .vaultFile
        default:
            throw LinkError.unsupportedType(raw)
        }
    }

    static func databaseItemType(for type: LibraryEntityType) -> String {
        switch type {
        case .dateCard:
            return "event"
        case .bookmark, .note, .todo, .contact, .vaultFile:
            return type.rawValue
        case .externalFile, .session:
            return type.rawValue
        }
    }

    func addDirectLink(from source: LibraryEntityRef, to target: LibraryEntityRef) throws {
        guard source != target else { return }
        let stmt = try database.prepare("""
            INSERT OR IGNORE INTO item_links (source_id, target_id, link_type, created_at)
            SELECT ?, ?, 'linked', ?
            WHERE EXISTS (SELECT 1 FROM items WHERE id = ?)
              AND EXISTS (SELECT 1 FROM items WHERE id = ?);
            """)
        let sourceID = DatabaseHelpers.encode(source.entityID)
        let targetID = DatabaseHelpers.encode(target.entityID)
        stmt.bind(sourceID, at: 1)
            .bind(targetID, at: 2)
            .bind(DatabaseHelpers.encode(Date()), at: 3)
            .bind(sourceID, at: 4)
            .bind(targetID, at: 5)
        try stmt.step()
        recordLinkMutation(action: "add_link", source: source, target: target)
        rebuildLinkedItemContext(for: source)
    }

    func addLink(from source: LibraryEntityRef, to target: LibraryEntityRef) throws {
        try addDirectLink(from: source, to: target)
        try addDirectLink(from: target, to: source)
        try syncInMemoryLinkedEntities(for: source)
        try syncInMemoryLinkedEntities(for: target)
    }

    func removeDirectLink(from source: LibraryEntityRef, to target: LibraryEntityRef) throws {
        let stmt = try database.prepare("""
            DELETE FROM item_links
            WHERE source_id = ? AND target_id = ? AND link_type = 'linked';
        """)
        stmt.bind(DatabaseHelpers.encode(source.entityID), at: 1)
            .bind(DatabaseHelpers.encode(target.entityID), at: 2)
        try stmt.step()
        recordLinkMutation(action: "remove_link", source: source, target: target)
        rebuildLinkedItemContext(for: source)
    }

    func removeLink(from source: LibraryEntityRef, to target: LibraryEntityRef) throws {
        try removeDirectLink(from: source, to: target)
        try removeDirectLink(from: target, to: source)
        try syncInMemoryLinkedEntities(for: source)
        try syncInMemoryLinkedEntities(for: target)
    }

    func outgoingRefs(for ref: LibraryEntityRef) throws -> [LibraryEntityRef] {
        try linkedRefs(sql: """
            SELECT l.target_id, i.type
            FROM item_links l
            JOIN items i ON i.id = l.target_id
            WHERE l.source_id = ? AND l.link_type = 'linked'
            ORDER BY l.created_at, i.title;
            """, id: ref.entityID)
    }

    func backlinkRefs(for ref: LibraryEntityRef) throws -> [LibraryEntityRef] {
        try linkedRefs(sql: """
            SELECT l.source_id, i.type
            FROM item_links l
            JOIN items i ON i.id = l.source_id
            WHERE l.target_id = ? AND l.link_type = 'linked'
            ORDER BY l.created_at, i.title;
            """, id: ref.entityID)
    }

    func relatedRefs(for ref: LibraryEntityRef) throws -> [LibraryEntityRef] {
        try unique(outgoingRefs(for: ref) + backlinkRefs(for: ref)).filter { $0 != ref }
    }

    func summary(for ref: LibraryEntityRef) -> ItemLinkSummary? {
        switch ref.type {
        case .bookmark:
            guard let bookmark = bookmarks.bookmarks.first(where: { $0.id == ref.entityID }) else { return databaseSummary(for: ref) }
            return ItemLinkSummary(ref: ref, title: bookmark.title, subtitle: bookmark.urlString, symbol: symbol(for: ref.type))
        case .note:
            guard let note = notes.notes.first(where: { $0.id == ref.entityID }) else { return databaseSummary(for: ref) }
            let subtitle = note.relativePath.isEmpty ? "Note" : note.relativePath
            return ItemLinkSummary(ref: ref, title: note.title, subtitle: subtitle, symbol: symbol(for: ref.type))
        case .dateCard:
            guard let dateCard = dateCards.dateCard(for: ref.entityID) else { return databaseSummary(for: ref) }
            return ItemLinkSummary(ref: ref, title: dateCard.title, subtitle: "Date card", symbol: symbol(for: ref.type))
        case .contact:
            guard let contact = contacts.contact(for: ref.entityID) else { return databaseSummary(for: ref) }
            let subtitle = contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel
            return ItemLinkSummary(ref: ref, title: contact.displayName, subtitle: subtitle, symbol: symbol(for: ref.type))
        case .todo:
            guard let todo = todos.todoCard(for: ref.entityID) else { return databaseSummary(for: ref) }
            return ItemLinkSummary(ref: ref, title: todo.title, subtitle: "Todo", symbol: symbol(for: ref.type))
        case .vaultFile:
            guard let file = files.file(for: ref.entityID) else { return databaseSummary(for: ref) }
            return ItemLinkSummary(ref: ref, title: file.displayTitle, subtitle: file.relativePath, symbol: symbol(for: ref.type))
        case .externalFile, .session:
            return nil
        }
    }

    func summaries(for refs: [LibraryEntityRef]) -> [ItemLinkSummary] {
        refs.compactMap { summary(for: $0) }
    }

    private func syncInMemoryLinkedEntities(for source: LibraryEntityRef) throws {
        let refs = try outgoingRefs(for: source)
        switch source.type {
        case .dateCard:
            guard var dateCard = dateCards.dateCard(for: source.entityID) else { return }
            guard dateCard.linkedEntities != refs else { return }
            dateCard.linkedEntities = refs
            _ = dateCards.updateDateCard(dateCard)
        case .contact:
            guard var contact = contacts.contact(for: source.entityID) else { return }
            guard contact.linkedEntities != refs else { return }
            contact.linkedEntities = refs
            _ = contacts.updateContact(contact)
        case .todo:
            guard var todo = todos.todoCard(for: source.entityID) else { return }
            guard todo.linkedEntities != refs else { return }
            todo.linkedEntities = refs
            _ = todos.updateTodoCard(todo)
        case .bookmark, .note, .vaultFile, .externalFile, .session:
            return
        }
    }

    private func recordLinkMutation(action: String, source: LibraryEntityRef, target: LibraryEntityRef) {
        MutationAuditService(database: database).record(
            action: action,
            itemType: source.type.rawValue,
            itemID: source.entityID,
            metadata: [
                "targetType": target.type.rawValue,
                "targetID": target.entityID.uuidString,
            ]
        )
    }

    private func rebuildLinkedItemContext(for source: LibraryEntityRef) {
        switch source.type {
        case .bookmark, .note, .todo, .dateCard, .contact, .vaultFile:
            SecondBrainItemMutationIndexer.rebuildAfterMutation(
                database: database,
                ownerType: source.type.rawValue,
                ownerID: source.entityID
            )
        case .externalFile, .session:
            return
        }
    }

    func resolve(type: LibraryEntityType, ref rawRef: String) throws -> LibraryEntityRef {
        let normalized = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw LinkError.itemNotFound(type: type, ref: rawRef)
        }
        let lowercased = normalized.lowercased()

        let candidates = candidates(for: type)
        let idMatches = candidates.filter { $0.id.uuidString.lowercased().hasPrefix(lowercased) }
        if idMatches.count == 1 {
            return LibraryEntityRef(type: type, entityID: idMatches[0].id)
        }
        if idMatches.count > 1 {
            throw LinkError.ambiguousItem(type: type, ref: rawRef, matches: displayMatches(idMatches))
        }

        let exactMatches = candidates.filter { $0.title.localizedCaseInsensitiveCompare(normalized) == .orderedSame }
        if exactMatches.count == 1 {
            return LibraryEntityRef(type: type, entityID: exactMatches[0].id)
        }
        if exactMatches.count > 1 {
            throw LinkError.ambiguousItem(type: type, ref: rawRef, matches: displayMatches(exactMatches))
        }

        let containsMatches = candidates.filter { $0.title.localizedCaseInsensitiveContains(normalized) }
        if containsMatches.count == 1 {
            return LibraryEntityRef(type: type, entityID: containsMatches[0].id)
        }
        if containsMatches.count > 1 {
            throw LinkError.ambiguousItem(type: type, ref: rawRef, matches: displayMatches(containsMatches))
        }

        throw LinkError.itemNotFound(type: type, ref: rawRef)
    }

    private func linkedRefs(sql: String, id: UUID) throws -> [LibraryEntityRef] {
        let stmt = try database.prepare(sql)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
        var refs: [LibraryEntityRef] = []
        while try stmt.step() {
            guard let entityID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)),
                  let type = Self.entityTypeFromDatabaseItemType(stmt.string(at: 1)) else {
                continue
            }
            refs.append(LibraryEntityRef(type: type, entityID: entityID))
        }
        return unique(refs)
    }

    private struct Candidate {
        let id: UUID
        let title: String
    }

    private func candidates(for type: LibraryEntityType) -> [Candidate] {
        switch type {
        case .bookmark:
            return bookmarks.bookmarks.map { Candidate(id: $0.id, title: $0.title) }
        case .note:
            return notes.notes.map { Candidate(id: $0.id, title: $0.title) }
        case .dateCard:
            return dateCards.dateCards.map { Candidate(id: $0.id, title: $0.title) }
        case .contact:
            return contacts.contacts.map { Candidate(id: $0.id, title: $0.displayName) }
        case .todo:
            return todos.todoCards.map { Candidate(id: $0.id, title: $0.title) }
        case .vaultFile:
            return files.files.map { Candidate(id: $0.id, title: $0.displayTitle) }
        case .externalFile, .session:
            return []
        }
    }

    private func displayMatches(_ candidates: [Candidate]) -> [String] {
        candidates.map { "\($0.title) [\($0.id.uuidString.prefix(8))]" }
    }

    private static func entityTypeFromDatabaseItemType(_ raw: String) -> LibraryEntityType? {
        let resolved = raw == "event" ? "dateCard" : raw
        guard let type = LibraryEntityType(rawValue: resolved),
              LibraryEntityType.activeCases.contains(type) else {
            return nil
        }
        return type
    }

    private func databaseSummary(for ref: LibraryEntityRef) -> ItemLinkSummary? {
        let stmt: SQLStatement
        do {
            stmt = try database.prepare("SELECT title FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            guard try stmt.step() else { return nil }
        } catch {
            return nil
        }
        return ItemLinkSummary(
            ref: ref,
            title: stmt.string(at: 0),
            subtitle: displayName(for: ref.type),
            symbol: symbol(for: ref.type)
        )
    }

    private func unique(_ refs: [LibraryEntityRef]) -> [LibraryEntityRef] {
        var seen: Set<String> = []
        var result: [LibraryEntityRef] = []
        for ref in refs {
            guard !seen.contains(ref.id) else { continue }
            seen.insert(ref.id)
            result.append(ref)
        }
        return result
    }

    private func displayName(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark: return "Bookmark"
        case .note: return "Note"
        case .dateCard: return "Date card"
        case .contact: return "Contact"
        case .todo: return "Todo"
        case .vaultFile: return "File"
        case .externalFile: return "External file"
        case .session: return "Session"
        }
    }

    private func symbol(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark: return "bookmark"
        case .note: return "note.text"
        case .dateCard: return "calendar"
        case .contact: return "person.crop.circle"
        case .todo: return "checklist"
        case .vaultFile, .externalFile: return "doc"
        case .session: return "rectangle.stack"
        }
    }
}

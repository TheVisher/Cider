import Foundation

struct SecondBrainItemContentIndexResult: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var itemType: String
    var chunkCount: Int
    var sources: [String]
}

@MainActor
final class SecondBrainItemContentIndexingService {
    enum IndexingError: Error, LocalizedError {
        case unsupportedOwnerType(String)
        case itemNotFound(SecondBrainOwnerRef)

        var errorDescription: String? {
            switch self {
            case .unsupportedOwnerType(let type):
                return "Unsupported item indexing owner type '\(type)'."
            case .itemNotFound(let owner):
                return "No SQLite item found for \(owner.canonicalRef)."
            }
        }
    }

    private let database: CiderDatabase
    private let store: SecondBrainStore

    init(database: CiderDatabase = .shared, store: SecondBrainStore? = nil) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
    }

    func rebuild(owner: SecondBrainOwnerRef) throws -> SecondBrainItemContentIndexResult {
        let normalized = normalizedOwner(owner)
        guard supportedOwnerTypes.contains(normalized.ownerType) else {
            throw IndexingError.unsupportedOwnerType(owner.ownerType)
        }
        guard var item = try itemContent(for: normalized) else {
            throw IndexingError.itemNotFound(normalized)
        }
        item.fields.append(contentsOf: try captureProvenanceFields(for: normalized))

        let chunks = chunkDrafts(for: item)
        try store.replaceChunks(owner: normalized, chunks: chunks)
        return SecondBrainItemContentIndexResult(
            owner: normalized,
            title: item.title,
            itemType: item.owner.ownerType,
            chunkCount: chunks.count,
            sources: chunks.map(\.source)
        )
    }

    func rebuildAll(limit: Int? = nil) throws -> [SecondBrainItemContentIndexResult] {
        let sqlLimit = limit.map { " LIMIT \(max(1, $0))" } ?? ""
        let stmt = try database.prepare("""
            SELECT id, type
            FROM items
            WHERE type IN ('bookmark', 'note', 'todo', 'event', 'contact', 'vaultFile')
            ORDER BY updated_at DESC, title COLLATE NOCASE ASC
            \(sqlLimit);
            """)

        var results: [SecondBrainItemContentIndexResult] = []
        while try stmt.step() {
            let dbType = stmt.string(at: 1)
            let ownerType = dbType == "event" ? "dateCard" : dbType
            let owner = SecondBrainOwnerRef(ownerType: ownerType, ownerID: stmt.string(at: 0))
            results.append(try rebuild(owner: owner))
        }
        return results
    }

    private var supportedOwnerTypes: Set<String> {
        ["bookmark", "note", "todo", "dateCard", "contact", "vaultFile"]
    }

    private func normalizedOwner(_ owner: SecondBrainOwnerRef) -> SecondBrainOwnerRef {
        let normalizedType = owner.ownerType == "event" ? "dateCard" : owner.ownerType
        return SecondBrainOwnerRef(ownerType: normalizedType, ownerID: owner.ownerID)
    }

    private struct ItemContent {
        var owner: SecondBrainOwnerRef
        var itemID: String
        var title: String
        var fields: [(label: String, value: String)]
    }

    private func itemContent(for owner: SecondBrainOwnerRef) throws -> ItemContent? {
        switch owner.ownerType {
        case "note":
            return try singleDetail(
                owner: owner,
                sql: """
                SELECT i.title, n.content, n.summary, i.relative_path
                FROM items i JOIN notes n ON n.item_id = i.id
                WHERE i.id = ? AND i.type = 'note';
                """,
                fields: [
                    (1, "Content"),
                    (2, "Summary"),
                    (3, "Path"),
                ]
            )
        case "bookmark":
            return try singleDetail(
                owner: owner,
                sql: """
                SELECT i.title, b.url, b.notes, b.ai_summary, b.ocr_text, b.media_type, i.relative_path
                FROM items i JOIN bookmarks b ON b.item_id = i.id
                WHERE i.id = ? AND i.type = 'bookmark';
                """,
                fields: [
                    (1, "URL"),
                    (2, "Notes"),
                    (3, "AI summary"),
                    (4, "OCR"),
                    (5, "Media type"),
                    (6, "Path"),
                ]
            )
        case "todo":
            return try singleDetail(
                owner: owner,
                sql: """
                SELECT i.title, t.details, t.notes, t.checklist, t.priority, t.action_url, i.relative_path
                FROM items i JOIN todos t ON t.item_id = i.id
                WHERE i.id = ? AND i.type = 'todo';
                """,
                fields: [
                    (1, "Details"),
                    (2, "Notes"),
                    (3, "Checklist"),
                    (4, "Priority"),
                    (5, "Action URL"),
                    (6, "Path"),
                ]
            )
        case "dateCard":
            return try singleDetail(
                owner: owner,
                sql: """
                SELECT i.title, e.details, e.location, e.start_at, e.end_at, e.recurrence_rule, e.action_url, i.relative_path
                FROM items i JOIN events e ON e.item_id = i.id
                WHERE i.id = ? AND i.type = 'event';
                """,
                fields: [
                    (1, "Details"),
                    (2, "Location"),
                    (3, "Start"),
                    (4, "End"),
                    (5, "Recurrence"),
                    (6, "Action URL"),
                    (7, "Path"),
                ],
                dateFields: [3, 4]
            )
        case "contact":
            return try singleDetail(
                owner: owner,
                sql: """
                SELECT i.title, c.relationship_label, c.notes, c.email, c.phone, c.address, c.custom_fields, i.relative_path
                FROM items i JOIN contacts c ON c.item_id = i.id
                WHERE i.id = ? AND i.type = 'contact';
                """,
                fields: [
                    (1, "Relationship"),
                    (2, "Notes"),
                    (3, "Email"),
                    (4, "Phone"),
                    (5, "Address"),
                    (6, "Custom fields"),
                    (7, "Path"),
                ]
            )
        case "vaultFile":
            var content = try singleDetail(
                owner: owner,
                sql: """
                SELECT i.title, f.filename, f.file_type, f.file_size, f.notes, f.ocr_text, i.relative_path
                FROM items i JOIN vault_files f ON f.item_id = i.id
                WHERE i.id = ? AND i.type = 'vaultFile';
                """,
                fields: [
                    (1, "Filename"),
                    (2, "File type"),
                    (3, "File size"),
                    (4, "Notes"),
                    (5, "OCR"),
                    (6, "Path"),
                ]
            )
            if let relativePath = content?.fields.first(where: { $0.label == "Path" })?.value,
               let text = readableTextFileContent(relativePath: relativePath) {
                content?.fields.append(("Text content", text))
            }
            return content
        default:
            throw IndexingError.unsupportedOwnerType(owner.ownerType)
        }
    }

    private func singleDetail(
        owner: SecondBrainOwnerRef,
        sql: String,
        fields: [(Int, String)],
        dateFields: Set<Int> = []
    ) throws -> ItemContent? {
        let stmt = try database.prepare(sql)
        stmt.bind(owner.ownerID, at: 1)
        guard try stmt.step() else { return nil }

        let title = stmt.string(at: 0)
        let values = fields.compactMap { index, label -> (label: String, value: String)? in
            let value: String
            if dateFields.contains(index) {
                guard let raw = stmt.optionalDouble(at: Int32(index)) else { return nil }
                value = ISO8601DateFormatter().string(from: DatabaseHelpers.decodeDate(raw))
            } else if index == 3, owner.ownerType == "vaultFile" {
                value = String(stmt.int(at: Int32(index)))
            } else {
                guard let raw = stmt.optionalString(at: Int32(index)) else { return nil }
                value = raw
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return (label, trimmed)
        }

        return ItemContent(owner: owner, itemID: owner.ownerID, title: title, fields: values)
    }

    private func captureProvenanceFields(for owner: SecondBrainOwnerRef) throws -> [(label: String, value: String)] {
        let stmt = try database.prepare("""
            SELECT e.source_text, e.source_url, e.source_file, e.sender_name, e.channel
            FROM owner_relations r
            JOIN capture_events e
              ON e.id = r.source_owner_id
            WHERE r.target_owner_type = ?
              AND r.target_owner_id = ?
              AND r.source_owner_type = 'capture_event'
              AND r.relation_type = 'produced_item'
            ORDER BY e.created_at DESC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var fields: [(label: String, value: String)] = []
        var sourceTexts: [String] = []
        var sourceRefs: [String] = []
        var senders: [String] = []
        var channels: [String] = []

        while try stmt.step() {
            appendUnique(stmt.optionalString(at: 0), to: &sourceTexts)
            appendUnique(stmt.optionalString(at: 1), to: &sourceRefs)
            appendUnique(stmt.optionalString(at: 2), to: &sourceRefs)
            appendUnique(stmt.optionalString(at: 3), to: &senders)
            appendUnique(stmt.optionalString(at: 4), to: &channels)
        }

        if !sourceTexts.isEmpty {
            fields.append(("Capture source text", sourceTexts.joined(separator: "\n")))
        }
        if !sourceRefs.isEmpty {
            fields.append(("Capture source", sourceRefs.joined(separator: "\n")))
        }
        if !senders.isEmpty {
            fields.append(("Capture sender", senders.joined(separator: ", ")))
        }
        if !channels.isEmpty {
            fields.append(("Capture channel", channels.joined(separator: ", ")))
        }
        return fields
    }

    private func appendUnique(_ raw: String?, to values: inout [String]) {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !values.contains(value) else {
            return
        }
        values.append(value)
    }

    private func readableTextFileContent(relativePath: String) -> String? {
        guard isReadableTextFile(relativePath: relativePath) else { return nil }

        let fileURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath)
        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        for encoding in [String.Encoding.utf8, .utf16, .ascii, .isoLatin1] {
            guard let text = String(data: data, encoding: encoding) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private func isReadableTextFile(relativePath: String) -> Bool {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return [
            "txt",
            "text",
            "md",
            "markdown",
            "csv",
            "tsv",
            "json",
            "jsonl",
            "yaml",
            "yml",
            "xml",
            "html",
            "htm",
            "log",
        ].contains(ext)
    }

    private func chunkDrafts(for item: ItemContent) -> [SecondBrainChunkDraft] {
        let bodyLines = [("Title", item.title)] + item.fields
        let body = bodyLines
            .map { "\($0.label): \($0.value)" }
            .joined(separator: "\n")

        return [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: item.itemID,
                source: "item_index.\(item.owner.ownerType)",
                title: item.title,
                body: body,
                chunkIndex: 0,
                metadata: [
                    "indexed_owner": item.owner.canonicalRef,
                    "source": "sqlite_detail_tables",
                ]
            )
        ]
    }
}

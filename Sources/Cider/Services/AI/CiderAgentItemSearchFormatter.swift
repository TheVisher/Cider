import Foundation

@MainActor
enum CiderAgentItemSearchFormatter {
    static func searchResponse(
        query: String,
        itemType: String?,
        service: CiderItemContextService = CiderItemContextService(),
        limit: Int = 20
    ) throws -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return "No items found matching \"\(query)\"."
        }

        let typeFilter = normalizedTypeFilter(itemType)
        let results = try service.search(trimmedQuery, limit: limit)
            .filter { result in
                guard let typeFilter else { return true }
                return result.item?.type == typeFilter
            }

        guard !results.isEmpty else {
            let suffix = typeFilter.map { " in \($0.agentSearchDisplayNamePlural)" } ?? ""
            return "No items found matching \"\(query)\"\(suffix)."
        }

        let lines = results.prefix(limit).map(format)
        return "Found \(lines.count) result(s) through unified item search:\n" + lines.joined(separator: "\n")
    }

    static func searchResponseOrMessage(
        query: String,
        itemType: String?,
        service: CiderItemContextService = CiderItemContextService(),
        limit: Int = 20
    ) -> String {
        do {
            return try searchResponse(query: query, itemType: itemType, service: service, limit: limit)
        } catch {
            return "Search failed: \(error.localizedDescription)"
        }
    }

    private static func format(_ result: CiderItemSearchResult) -> String {
        let item = result.item
        let type = item?.type.rawValue ?? result.owner.ownerType
        let id = item?.id.uuidString ?? result.owner.ownerID
        let title = item?.title ?? result.title
        var parts = [
            "- \(type) \(id): \"\(title)\"",
        ]

        if let path = item?.relativePath, !path.isEmpty {
            parts.append("Path: \(path)")
        }
        if !result.snippet.isEmpty {
            parts.append("Snippet: \(result.snippet)")
        }
        if item != nil {
            parts.append("Command: cider-cli item context \(type) \(id) --json")
        }

        return parts.joined(separator: " | ")
    }

    private static func normalizedTypeFilter(_ itemType: String?) -> LibraryEntityType? {
        guard let itemType else { return nil }
        switch itemType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "all", "everything", "items":
            return nil
        case "bookmark", "bookmarks":
            return .bookmark
        case "note", "notes":
            return .note
        case "event", "events", "datecard", "datecards", "date card", "date cards":
            return .dateCard
        case "contact", "contacts":
            return .contact
        case "todo", "todos", "task", "tasks":
            return .todo
        case "file", "files", "vaultfile", "vaultfiles", "vault file", "vault files":
            return .vaultFile
        default:
            return nil
        }
    }
}

private extension LibraryEntityType {
    var agentSearchDisplayNamePlural: String {
        switch self {
        case .bookmark:
            return "bookmarks"
        case .note:
            return "notes"
        case .dateCard:
            return "events"
        case .contact:
            return "contacts"
        case .todo:
            return "todos"
        case .externalFile, .vaultFile:
            return "files"
        case .session:
            return "sessions"
        }
    }
}

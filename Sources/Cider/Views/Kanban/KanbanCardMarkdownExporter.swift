import Foundation

enum KanbanCardMarkdownExporter {
    static func markdown(
        for draft: KanbanCardDraft,
        baseCard: KanbanCard,
        boardName: String,
        columnName: String,
        linkedReferenceSummaries: [ItemLinkSummary] = []
    ) -> String {
        markdown(
            for: draft.updatedCard(from: baseCard),
            boardName: boardName,
            columnName: columnName,
            linkedReferenceSummaries: linkedReferenceSummaries
        )
    }

    static func markdown(
        for card: KanbanCard,
        boardName: String,
        columnName: String,
        linkedReferenceSummaries: [ItemLinkSummary] = []
    ) -> String {
        var lines: [String] = []
        lines.append("# \(card.title)")
        lines.append("")
        lines.append("- Card ID: \(card.id)")
        lines.append("- Board: \(boardName)")
        lines.append("- Status: \(columnName)")
        if let priority = card.priority {
            lines.append("- Priority: \(priority.rawValue)")
        }
        if let color = card.color {
            lines.append("- Color: \(color.rawValue)")
        }
        if let agent = card.agent, !agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- Agent: \(agent)")
        }
        if !card.tags.isEmpty {
            lines.append("- Tags: \(card.tags.joined(separator: ", "))")
        }
        if let parentCardID = card.parentCardID, !parentCardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- Parent Card: \(parentCardID)")
        }
        if !card.relatedCardIDs.isEmpty {
            lines.append("- Related Cards: \(card.relatedCardIDs.joined(separator: ", "))")
        }
        lines.append("- Created: \(formattedDate(card.created))")
        if let completed = card.completed {
            lines.append("- Completed: \(formattedDate(completed))")
        }
        lines.append("")
        if let summary = card.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(summary)
            lines.append("")
        }
        appendHistory(to: &lines, card: card)
        lines.append("## Notes")
        lines.append("")
        if let notes = card.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(notes)
        } else {
            lines.append("_No notes yet._")
        }
        lines.append("")
        appendLinkedReferences(
            to: &lines,
            card: card,
            linkedReferenceSummaries: linkedReferenceSummaries
        )
        return lines.joined(separator: "\n")
    }

    static func suggestedFileName(for card: KanbanCard) -> String {
        let cleaned = card.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((cleaned.isEmpty ? "Kanban Card" : cleaned)).md"
    }

    private static func appendHistory(to lines: inout [String], card: KanbanCard) {
        guard !card.historyEntries.isEmpty else { return }

        lines.append("## History")
        lines.append("")
        for entry in card.historyEntries.sorted(by: historySort) {
            let authorSuffix: String
            if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                authorSuffix = " — \(author)"
            } else {
                authorSuffix = ""
            }
            lines.append("### \(entry.type.displayName) — \(formattedDate(entry.createdAt))\(authorSuffix)")
            lines.append("")
            let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(body.isEmpty ? "_No details recorded._" : body)
            lines.append("")
        }
    }

    private static func appendLinkedReferences(
        to lines: inout [String],
        card: KanbanCard,
        linkedReferenceSummaries: [ItemLinkSummary]
    ) {
        guard !card.linkedEntities.isEmpty else { return }

        let summariesByID = Dictionary(uniqueKeysWithValues: linkedReferenceSummaries.map { ($0.ref.id, $0) })
        lines.append("## Linked References")
        lines.append("")
        for ref in card.linkedEntities {
            if let summary = summariesByID[ref.id] {
                lines.append("- \(displayName(for: ref.type)): \(summary.title) — \(summary.subtitle) [\(ref.entityID.uuidString)]")
            } else {
                lines.append("- \(displayName(for: ref.type)): \(ref.entityID.uuidString)")
            }
        }
        lines.append("")
    }

    private static func displayName(for type: LibraryEntityType) -> String {
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

    private static func historySort(_ lhs: KanbanCardHistoryEntry, _ rhs: KanbanCardHistoryEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

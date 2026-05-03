import Foundation

enum KanbanCardMarkdownExporter {
    static func markdown(
        for draft: KanbanCardDraft,
        baseCard: KanbanCard,
        boardName: String,
        columnName: String
    ) -> String {
        markdown(
            for: draft.updatedCard(from: baseCard),
            boardName: boardName,
            columnName: columnName
        )
    }

    static func markdown(for card: KanbanCard, boardName: String, columnName: String) -> String {
        var lines: [String] = []
        lines.append("# \(card.title)")
        lines.append("")
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
        lines.append("- Created: \(formattedDate(card.created))")
        if let completed = card.completed {
            lines.append("- Completed: \(formattedDate(completed))")
        }
        lines.append("")
        lines.append("## Notes")
        lines.append("")
        if let notes = card.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(notes)
        } else {
            lines.append("_No notes yet._")
        }
        lines.append("")
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

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

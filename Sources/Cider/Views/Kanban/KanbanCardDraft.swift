import Foundation

struct KanbanCardDraft: Equatable {
    var title: String
    var notes: String
    var color: KanbanCardColor?
    var priority: KanbanPriority?
    var agent: String
    var tagsText: String
    var linkedEntities: [LibraryEntityRef]

    init(card: KanbanCard) {
        title = card.title
        notes = card.notes ?? ""
        color = card.color
        priority = card.priority
        agent = card.agent ?? ""
        tagsText = card.tags.joined(separator: ", ")
        linkedEntities = card.linkedEntities
    }

    func updatedCard(from original: KanbanCard) -> KanbanCard {
        var updated = original

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? "Untitled Card" : trimmedTitle

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmedNotes.isEmpty ? nil : notes

        let trimmedAgent = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.agent = trimmedAgent.isEmpty ? nil : trimmedAgent

        updated.color = color
        updated.priority = priority
        updated.tags = tagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.linkedEntities = linkedEntities

        return updated
    }
}

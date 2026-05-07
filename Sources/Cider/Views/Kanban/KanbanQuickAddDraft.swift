import Foundation

struct KanbanQuickAddDraft: Equatable {
    var title = ""
    var notes = ""
    var priority: KanbanPriority?
    var color: KanbanCardColor?
    var tagsText = ""
    var parentCardID: String?

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var tags: [String] {
        tagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var canCreate: Bool {
        !trimmedTitle.isEmpty
    }
}

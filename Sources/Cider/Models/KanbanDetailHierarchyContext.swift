import Foundation

struct KanbanDetailHierarchyContext: Equatable {
    struct Parent: Equatable, Identifiable {
        let id: String
        let displayKey: String
        let title: String
    }

    struct Child: Equatable, Identifiable {
        let id: String
        let displayKey: String
        let title: String
        let columnID: String
        let columnName: String
        let isComplete: Bool
    }

    let parent: Parent?
    let parentProgressText: String?
    let progressText: String?
    let children: [Child]

    init(board: KanbanBoard, cardID: String) {
        let card = board.card(id: cardID)
        if let parentCardID = card?.parentCardID,
           let parentCard = board.card(id: parentCardID) {
            parent = Parent(
                id: parentCard.id,
                displayKey: board.displayKey(for: parentCard),
                title: parentCard.title
            )
            parentProgressText = KanbanBoardLayout.childSummary(for: parentCard.id, in: board)?.progressText
        } else {
            parent = nil
            parentProgressText = nil
        }

        progressText = KanbanBoardLayout.childSummary(for: cardID, in: board)?.progressText
        children = board.columns.flatMap { column in
            column.cards.compactMap { childCard -> Child? in
                guard childCard.parentCardID == cardID else { return nil }
                return Child(
                    id: childCard.id,
                    displayKey: board.displayKey(for: childCard),
                    title: childCard.title,
                    columnID: column.id,
                    columnName: column.name,
                    isComplete: column.isDoneLikeColumn || childCard.completed != nil
                )
            }
        }
    }

    var hasHierarchy: Bool {
        parent != nil || !children.isEmpty
    }
}

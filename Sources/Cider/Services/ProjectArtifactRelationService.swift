import Foundation

@MainActor
enum ProjectArtifactRelationService {
    static let source = "project_workspace"

    static func owner(for ref: LibraryEntityRef) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
    }

    static func cardOwner(boardID: String, cardID: String) -> SecondBrainOwnerRef {
        SecondBrainKanbanProjectionService.owner(boardID: boardID, cardID: cardID)
    }

    static func recordCardRelation(
        boardID: String,
        boardName: String,
        card: KanbanCard,
        relationType: String,
        target: LibraryEntityRef,
        targetTitle: String? = nil,
        evidence: String? = nil,
        database: CiderDatabase = .shared
    ) {
        let targetOwner = owner(for: target)
        var metadata = [
            "board_id": boardID,
            "board_name": boardName,
            "card_id": card.id,
            "card_title": card.title,
            "target_type": target.type.rawValue,
            "target_id": target.entityID.uuidString,
        ]
        if let targetTitle, !targetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["title"] = targetTitle
        }
        let relation = SecondBrainRelation(
            sourceOwner: cardOwner(boardID: boardID, cardID: card.id),
            targetOwner: targetOwner,
            relationType: relationType,
            evidence: evidence ?? "Kanban card \(card.title) \(relationType.replacingOccurrences(of: "_", with: " ")) \(target.type.rawValue) \(target.entityID.uuidString).",
            source: source,
            actor: "user",
            confidence: 1,
            metadata: metadata
        )
        try? SecondBrainStore(database: database).recordRelation(relation)
    }

    static func relatedModel(
        for owner: SecondBrainOwnerRef,
        boards: [KanbanBoard] = KanbanStorage.shared.boards,
        notes: [Note] = NotesStorage.shared.notes,
        database: CiderDatabase = .shared
    ) -> ProjectArtifactRelationshipPanelModel {
        let relations = (try? SecondBrainStore(database: database).relatedRelations(for: owner)) ?? []
        return ProjectArtifactRelationshipProvider.model(for: owner, relations: relations, boards: boards, notes: notes)
    }
}

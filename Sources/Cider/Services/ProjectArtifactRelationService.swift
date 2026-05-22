import Foundation

@MainActor
enum ProjectArtifactRelationService {
    static let source = "project_workspace"
    static let cliSource = "note.project-artifact"

    struct ArtifactRelationTarget: Equatable {
        let owner: SecondBrainOwnerRef
        let relationType: String
        let title: String?
        let evidence: String?

        init(
            owner: SecondBrainOwnerRef,
            relationType: String,
            title: String? = nil,
            evidence: String? = nil
        ) {
            self.owner = owner
            self.relationType = relationType
            self.title = title
            self.evidence = evidence
        }
    }

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

    static func recordArtifactRelations(
        note: Note,
        targets: [ArtifactRelationTarget],
        actor: String = "cider-cli",
        source: String = cliSource,
        database: CiderDatabase = .shared
    ) -> [SecondBrainRelation] {
        guard !targets.isEmpty else { return [] }
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
        let store = SecondBrainStore(database: database)
        var recorded: [SecondBrainRelation] = []
        for target in targets {
            var metadata = [
                "artifactType": note.artifactType ?? "note",
                "path": note.relativePath,
                "title": note.title,
                "target_type": target.owner.ownerType,
                "target_id": target.owner.ownerID,
            ]
            if let title = target.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                metadata["target_title"] = title
            }
            let relation = SecondBrainRelation(
                sourceOwner: sourceOwner,
                targetOwner: target.owner,
                relationType: target.relationType,
                evidence: target.evidence ?? defaultEvidence(note: note, target: target),
                source: source,
                actor: actor,
                confidence: 1,
                metadata: metadata
            )
            do {
                try store.recordRelation(relation)
                recorded.append(relation)
            } catch {
                assertionFailure("Failed to record project artifact relation: \(error.localizedDescription)")
            }
        }
        return recorded
    }

    private static func defaultEvidence(note: Note, target: ArtifactRelationTarget) -> String {
        let artifact = note.artifactType ?? "artifact"
        let relation = target.relationType.replacingOccurrences(of: "_", with: " ")
        let title = target.title.map { " \($0)" } ?? ""
        return "Project \(artifact) artifact \(note.title) \(relation) \(target.owner.ownerType)\(title)."
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

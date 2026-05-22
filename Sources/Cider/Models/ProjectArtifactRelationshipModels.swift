import Foundation

struct ProjectArtifactRelationshipPanelModel: Equatable {
    let owner: SecondBrainOwnerRef
    let derivedCards: [ProjectArtifactRelationshipRow]
    let sourceArtifacts: [ProjectArtifactRelationshipRow]
    let relatedDecisions: [ProjectArtifactRelationshipRow]
    let qaFindings: [ProjectArtifactRelationshipRow]
    let otherLinks: [ProjectArtifactRelationshipRow]

    var isEmpty: Bool {
        derivedCards.isEmpty
            && sourceArtifacts.isEmpty
            && relatedDecisions.isEmpty
            && qaFindings.isEmpty
            && otherLinks.isEmpty
    }
}

struct ProjectArtifactRelationshipRow: Identifiable, Equatable {
    enum Direction: String, Equatable {
        case incoming
        case outgoing
    }

    let owner: SecondBrainOwnerRef
    let title: String
    let subtitle: String
    let relationType: String
    let direction: Direction
    let evidence: String

    var id: String { "\(direction.rawValue):\(owner.canonicalRef):\(relationType)" }
}

enum ProjectArtifactRelationType {
    static let spawnedFrom = "spawned_from"
    static let derivesFrom = "derives_from"
    static let implements = "implements"
    static let validates = "validates"
    static let foundBugIn = "found_bug_in"
    static let decidedFrom = "decided_from"
    static let supersedes = "supersedes"

    static let sourceTypes: Set<String> = [spawnedFrom, derivesFrom, decidedFrom]
    static let derivedCardTypes: Set<String> = [spawnedFrom, derivesFrom, implements]
    static let qaTypes: Set<String> = [validates, foundBugIn]
    static let decisionTypes: Set<String> = [decidedFrom, "supports", "decides", "decided"]
}

enum ProjectArtifactRelationshipProvider {
    static func model(
        for owner: SecondBrainOwnerRef,
        relations: [SecondBrainRelation],
        boards: [KanbanBoard] = [],
        notes: [Note] = []
    ) -> ProjectArtifactRelationshipPanelModel {
        var derivedCards: [ProjectArtifactRelationshipRow] = []
        var sourceArtifacts: [ProjectArtifactRelationshipRow] = []
        var relatedDecisions: [ProjectArtifactRelationshipRow] = []
        var qaFindings: [ProjectArtifactRelationshipRow] = []
        var otherLinks: [ProjectArtifactRelationshipRow] = []

        for relation in relations where relation.sourceOwner == owner || relation.targetOwner == owner {
            let otherOwner = relation.sourceOwner == owner ? relation.targetOwner : relation.sourceOwner
            let direction: ProjectArtifactRelationshipRow.Direction = relation.sourceOwner == owner ? .outgoing : .incoming
            let row = ProjectArtifactRelationshipRow(
                owner: otherOwner,
                title: title(for: otherOwner, relation: relation, boards: boards, notes: notes),
                subtitle: subtitle(for: otherOwner, relation: relation, direction: direction, boards: boards),
                relationType: relation.relationType,
                direction: direction,
                evidence: relation.evidence
            )
            let relationType = relation.relationType.localizedLowercase

            if isDerivedCard(row: row, relationType: relationType, owner: owner) {
                derivedCards.append(row)
            } else if isQA(row: row, relationType: relationType, notes: notes) {
                qaFindings.append(row)
            } else if isDecision(row: row, relationType: relationType, notes: notes) {
                relatedDecisions.append(row)
            } else if isSourceArtifact(row: row, relationType: relationType, owner: owner) {
                sourceArtifacts.append(row)
            } else {
                otherLinks.append(row)
            }
        }

        return ProjectArtifactRelationshipPanelModel(
            owner: owner,
            derivedCards: sortedUnique(derivedCards),
            sourceArtifacts: sortedUnique(sourceArtifacts),
            relatedDecisions: sortedUnique(relatedDecisions),
            qaFindings: sortedUnique(qaFindings),
            otherLinks: sortedUnique(otherLinks)
        )
    }

    private static func isDerivedCard(
        row: ProjectArtifactRelationshipRow,
        relationType: String,
        owner: SecondBrainOwnerRef
    ) -> Bool {
        row.owner.ownerType == "kanban_card"
            && (row.direction == .incoming || owner.ownerType != "kanban_card")
            && ProjectArtifactRelationType.derivedCardTypes.contains(relationType)
    }

    private static func isSourceArtifact(
        row: ProjectArtifactRelationshipRow,
        relationType: String,
        owner: SecondBrainOwnerRef
    ) -> Bool {
        owner.ownerType == "kanban_card"
            && row.direction == .outgoing
            && ProjectArtifactRelationType.sourceTypes.contains(relationType)
    }

    private static func isQA(
        row: ProjectArtifactRelationshipRow,
        relationType: String,
        notes: [Note]
    ) -> Bool {
        if ProjectArtifactRelationType.qaTypes.contains(relationType) { return true }
        let artifactType = note(for: row.owner, notes: notes)?.artifactType?.localizedLowercase ?? row.owner.ownerType.localizedLowercase
        return artifactType == "qa" || artifactType == "audit" || artifactType == "bug"
    }

    private static func isDecision(
        row: ProjectArtifactRelationshipRow,
        relationType: String,
        notes: [Note]
    ) -> Bool {
        if ProjectArtifactRelationType.decisionTypes.contains(relationType) { return true }
        let artifactType = note(for: row.owner, notes: notes)?.artifactType?.localizedLowercase ?? row.owner.ownerType.localizedLowercase
        return artifactType == "decision"
    }

    private static func title(
        for owner: SecondBrainOwnerRef,
        relation: SecondBrainRelation,
        boards: [KanbanBoard],
        notes: [Note]
    ) -> String {
        for key in ["title", "card_title", "note_title", "decision_title", "qa_title", "name", "path"] {
            if let value = relation.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        if owner.ownerType == "kanban_card", let card = card(for: owner, boards: boards) {
            return card.title
        }
        if let note = note(for: owner, notes: notes) {
            return note.title
        }
        return owner.canonicalRef
    }

    private static func subtitle(
        for owner: SecondBrainOwnerRef,
        relation: SecondBrainRelation,
        direction: ProjectArtifactRelationshipRow.Direction,
        boards: [KanbanBoard]
    ) -> String {
        let arrow = direction == .outgoing ? "→" : "←"
        var parts = [relation.relationType.replacingOccurrences(of: "_", with: " ")]
        if let status = cardStatus(for: owner, boards: boards) {
            parts.append(status)
        }
        parts.append("\(arrow) \(owner.canonicalRef)")
        return parts.joined(separator: " · ")
    }

    private static func cardStatus(for owner: SecondBrainOwnerRef, boards: [KanbanBoard]) -> String? {
        guard owner.ownerType == "kanban_card" else { return nil }
        for board in boards {
            for column in board.columns {
                if let card = column.cards.first(where: { candidate in
                    owner.ownerID == "\(board.id)/\(candidate.id)" || owner.ownerID == candidate.id
                }) {
                    if card.completed != nil { return "Done · \(column.name)" }
                    return "Open · \(column.name)"
                }
            }
        }
        return nil
    }

    private static func note(for owner: SecondBrainOwnerRef, notes: [Note]) -> Note? {
        guard owner.ownerType == "note" || owner.ownerType == "decision" || owner.ownerType == "qa" || owner.ownerType == "audit" else { return nil }
        return notes.first { note in
            note.id.uuidString.caseInsensitiveCompare(owner.ownerID) == .orderedSame
                || note.relativePath.caseInsensitiveCompare(owner.ownerID) == .orderedSame
        }
    }

    private static func card(for owner: SecondBrainOwnerRef, boards: [KanbanBoard]) -> KanbanCard? {
        guard owner.ownerType == "kanban_card" else { return nil }
        let parts = owner.ownerID.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return boards.first { $0.id == parts[0] }?.card(id: parts[1])
        }
        return boards.compactMap { $0.card(id: owner.ownerID) }.first
    }

    private static func sortedUnique(_ rows: [ProjectArtifactRelationshipRow]) -> [ProjectArtifactRelationshipRow] {
        var seen = Set<String>()
        return rows
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.title.localizedCaseInsensitiveCompare(rhs.title) != .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }
}

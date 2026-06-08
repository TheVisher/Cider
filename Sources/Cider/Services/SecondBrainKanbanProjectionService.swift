import Foundation

@MainActor
final class SecondBrainKanbanProjectionService {
    private let store: SecondBrainStore

    init(store: SecondBrainStore = SecondBrainStore()) {
        self.store = store
    }

    func refreshCard(boardID: String, card: KanbanCard) throws {
        let owner = Self.owner(boardID: boardID, cardID: card.id)
        let parsedSections = normalizedSections(for: card)
        let existingByKey = Dictionary(uniqueKeysWithValues: try store.sections(for: owner).map { ($0.sectionKey, $0) })
        let displayKey = card.displayKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardIdentity = [displayKey, card.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var sections: [SecondBrainSection] = []
        var chunkDrafts: [SecondBrainChunkDraft] = []
        for (index, parsed) in parsedSections.enumerated() {
            let existing = existingByKey[parsed.key]
            let section = SecondBrainSection(
                id: existing?.id ?? UUID().uuidString,
                owner: owner,
                sectionKey: parsed.key,
                title: parsed.title,
                body: parsed.body,
                source: "kanban_notes",
                metadata: [
                    "board_id": boardID,
                    "card_id": card.id,
                    "card_title": card.title,
                ],
                sortOrder: index,
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date()
            )
            sections.append(section)

            let chunkBody = [cardIdentity, parsed.title, parsed.body]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            chunkDrafts.append(
                SecondBrainChunkDraft(
                    sectionID: section.id,
                    source: "kanban_notes",
                    title: card.title,
                    body: chunkBody,
                    chunkIndex: index,
                    metadata: [
                        "board_id": boardID,
                        "card_id": card.id,
                        "card_title": card.title,
                        "display_key": displayKey ?? "",
                        "section_key": parsed.key,
                    ]
                )
            )
        }

        try store.replaceProjection(
            owner: owner,
            sections: sections,
            keeping: Set(parsedSections.map(\.key)),
            chunks: chunkDrafts
        )
    }

    static func owner(boardID: String, cardID: String) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "\(boardID)/\(cardID)")
    }

    private func normalizedSections(for card: KanbanCard) -> [KanbanCardSection] {
        let parsed = KanbanCardSectionParser.sections(from: card.notes)
        if !parsed.isEmpty {
            return parsed
        }

        return [
            KanbanCardSection(
                key: "summary",
                title: "Summary",
                body: card.aiSummary ?? card.title,
                sortOrder: 0
            ),
        ]
    }
}

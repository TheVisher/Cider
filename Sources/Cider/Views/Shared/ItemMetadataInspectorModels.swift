import Foundation

struct ItemMetadataRow: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let value: String
    let ref: LibraryEntityRef?

    init(id: String, symbol: String, title: String, value: String = "", ref: LibraryEntityRef? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.value = value
        self.ref = ref
    }

    static func related(_ summary: ItemLinkSummary) -> ItemMetadataRow {
        ItemMetadataRow(
            id: "related-\(summary.ref.type.rawValue)-\(summary.ref.entityID.uuidString)",
            symbol: summary.symbol,
            title: summary.title,
            value: summary.subtitle,
            ref: summary.ref
        )
    }
}

struct ItemMetadataSection: Identifiable, Equatable {
    let id: String
    let title: String
    var rows: [ItemMetadataRow]
    var emptyActionTitle: String?
    var showsWhenEmpty = false

    static func visibleSections(from sections: [ItemMetadataSection]) -> [ItemMetadataSection] {
        sections.filter { !$0.rows.isEmpty || $0.emptyActionTitle != nil || $0.showsWhenEmpty }
    }
}

struct ItemMetadataLinkCandidate: Identifiable, Equatable {
    let ref: LibraryEntityRef
    let title: String
    let subtitle: String

    var id: String { ref.id }
}

struct ItemMetadataLinkCandidateGroup: Identifiable, Equatable {
    let title: String
    let candidates: [ItemMetadataLinkCandidate]

    var id: String { title }
}

enum KanbanReferenceBacklinkRows {
    static func rows(for source: LibraryEntityRef, boards: [KanbanBoard]) -> [ItemMetadataRow] {
        boards.flatMap { board in
            board.columns.flatMap { column in
                column.cards.compactMap { card -> ItemMetadataRow? in
                    guard card.linkedEntities.contains(source) else { return nil }
                    return ItemMetadataRow(
                        id: "kanban-backlink-\(board.id)-\(column.id)-\(card.id)",
                        symbol: "square.split.2x1",
                        title: card.title,
                        value: "\(board.name) · \(column.name) · \(card.id)"
                    )
                }
            }
        }
    }
}

enum ItemMetadataLinkingActions {
    static func visibleGroups(
        source: LibraryEntityRef,
        relatedRefs: [LibraryEntityRef],
        groups: [ItemMetadataLinkCandidateGroup]
    ) -> [ItemMetadataLinkCandidateGroup] {
        let blockedIDs = Set(([source] + relatedRefs).map(\.id))

        return groups.compactMap { group in
            let candidates = group.candidates.filter { !blockedIDs.contains($0.ref.id) }
            guard !candidates.isEmpty else { return nil }
            return ItemMetadataLinkCandidateGroup(title: group.title, candidates: candidates)
        }
    }
}

enum ItemMetadataInfoRows {
    static func rows(
        createdAt: Date,
        updatedAt: Date,
        typeLabel: String,
        additionalRows: [ItemMetadataRow] = [],
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [ItemMetadataRow] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return [
            ItemMetadataRow(id: "created", symbol: "calendar.badge.plus", title: "Created", value: formatter.string(from: createdAt)),
            ItemMetadataRow(id: "updated", symbol: "clock", title: "Updated", value: formatter.string(from: updatedAt)),
            ItemMetadataRow(id: "type", symbol: "info.circle", title: "Type", value: typeLabel)
        ] + additionalRows
    }
}

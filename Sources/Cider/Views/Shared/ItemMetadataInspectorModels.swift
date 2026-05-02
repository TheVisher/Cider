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

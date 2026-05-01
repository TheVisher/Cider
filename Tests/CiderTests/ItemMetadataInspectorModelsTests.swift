import Foundation
import Testing
@testable import Cider

struct ItemMetadataInspectorModelsTests {
    @Test("empty sections without actions are omitted")
    func emptySectionsWithoutActionsAreOmitted() {
        let sections = [
            ItemMetadataSection(id: "linked", title: "Linked", rows: []),
            ItemMetadataSection(id: "notes", title: "Notes", rows: [], emptyActionTitle: "Add Note"),
            ItemMetadataSection(id: "info", title: "Info", rows: [
                ItemMetadataRow(id: "type", symbol: "info.circle", title: "Type", value: "Contact")
            ])
        ]

        #expect(ItemMetadataSection.visibleSections(from: sections).map(\.id) == ["notes", "info"])
    }

    @Test("related summaries become clickable metadata rows")
    func relatedSummariesBecomeRows() {
        let ref = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let summary = ItemLinkSummary(ref: ref, title: "Gift idea", subtitle: "Bookmark", symbol: "bookmark")

        let row = ItemMetadataRow.related(summary)

        #expect(row.id == "related-\(ref.type.rawValue)-\(ref.entityID.uuidString)")
        #expect(row.symbol == "bookmark")
        #expect(row.title == "Gift idea")
        #expect(row.value == "Bookmark")
        #expect(row.ref == ref)
    }

    @Test("info rows use stable created updated type order")
    func infoRowsUseStableOrder() {
        let created = Date(timeIntervalSince1970: 100)
        let updated = Date(timeIntervalSince1970: 200)

        let rows = ItemMetadataInfoRows.rows(
            createdAt: created,
            updatedAt: updated,
            typeLabel: "Contact",
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(rows.map(\.id) == ["created", "updated", "type"])
        #expect(rows[2].value == "Contact")
    }
}

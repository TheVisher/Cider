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

    @Test("empty sections can opt into visibility")
    func emptySectionsCanOptIntoVisibility() {
        let sections = [
            ItemMetadataSection(id: "linked", title: "Linked", rows: [], showsWhenEmpty: true),
            ItemMetadataSection(id: "keywords", title: "Keywords", rows: [])
        ]

        #expect(ItemMetadataSection.visibleSections(from: sections).map(\.id) == ["linked"])
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

    @Test("info rows append type-specific details after base rows")
    func infoRowsAppendTypeSpecificDetails() {
        let rows = ItemMetadataInfoRows.rows(
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            typeLabel: "File",
            additionalRows: [
                ItemMetadataRow(id: "kind", symbol: "photo", title: "Kind", value: "Image"),
                ItemMetadataRow(id: "size", symbol: "externaldrive", title: "Size", value: "1.5 MB")
            ],
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(rows.map(\.id) == ["created", "updated", "type", "kind", "size"])
        #expect(rows[3].value == "Image")
        #expect(rows[4].value == "1.5 MB")
    }

    @Test("date card metadata rows include scheduled facts before optional facts")
    func dateCardMetadataRowsIncludeScheduledFactsBeforeOptionalFacts() {
        let dateCard = DateCard(
            title: "Dentist",
            startAt: Date(timeIntervalSince1970: 1_000),
            allDay: true,
            location: "Suite 4",
            amount: 42.5
        )

        let rows = DateCardMetadataRows.rows(for: dateCard)

        #expect(rows.map(\.id) == ["date", "time", "location", "amount"])
        #expect(rows[1].value == "All day")
        #expect(rows[2].value == "Suite 4")
    }

    @Test("todo metadata rows include status due date and priority")
    func todoMetadataRowsIncludeStatusDueDateAndPriority() {
        let todo = TodoCard(
            title: "Ship task",
            dueDate: Date(timeIntervalSince1970: 2_000),
            priority: .high,
            isCompleted: true
        )

        let rows = TodoMetadataRows.rows(for: todo)

        #expect(rows.map(\.id) == ["status", "due", "priority"])
        #expect(rows[0].value == "Completed")
        #expect(rows[2].value == "High")
    }
}

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

    @Test("link candidate groups omit source and already related refs")
    func linkCandidateGroupsOmitSourceAndRelatedRefs() {
        let source = LibraryEntityRef(type: .contact, entityID: UUID())
        let linkedBookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let addableBookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())

        let groups = [
            ItemMetadataLinkCandidateGroup(
                title: "Bookmarks",
                candidates: [
                    ItemMetadataLinkCandidate(ref: linkedBookmark, title: "Existing", subtitle: "Bookmark"),
                    ItemMetadataLinkCandidate(ref: addableBookmark, title: "Gift", subtitle: "Bookmark")
                ]
            ),
            ItemMetadataLinkCandidateGroup(
                title: "Contacts",
                candidates: [
                    ItemMetadataLinkCandidate(ref: source, title: "Current", subtitle: "Contact")
                ]
            )
        ]

        let visible = ItemMetadataLinkingActions.visibleGroups(
            source: source,
            relatedRefs: [linkedBookmark],
            groups: groups
        )

        #expect(visible.map(\.title) == ["Bookmarks"])
        #expect(visible.first?.candidates.map(\.ref) == [addableBookmark])
    }

    @Test("kanban reference backlinks expose card title board column and id")
    func kanbanReferenceBacklinksExposeCardContext() {
        let ref = LibraryEntityRef(
            type: .bookmark,
            entityID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )
        let board = KanbanBoard(
            id: "board-cider",
            name: "Cider",
            columns: [
                KanbanColumn(
                    id: "active",
                    name: "In Progress",
                    cards: [
                        KanbanCard(id: "a18f97", title: "Project references MVP", linkedEntities: [ref]),
                        KanbanCard(id: "other", title: "Unlinked")
                    ]
                )
            ]
        )

        let rows = KanbanReferenceBacklinkRows.rows(for: ref, boards: [board])

        #expect(rows.map(\.id) == ["kanban-backlink-board-cider-active-a18f97"])
        #expect(rows.first?.symbol == "square.split.2x1")
        #expect(rows.first?.title == "Project references MVP")
        #expect(rows.first?.value == "Cider · In Progress · a18f97")
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

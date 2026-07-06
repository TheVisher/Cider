import Foundation
import Testing
@testable import Cider

struct JournalLibraryReadModelTests {
    @Test("journal library projection creates one container and defaults to newest daily entry")
    func projectionCreatesContainerAndDefaultsToNewestEntry() throws {
        let older = Note(
            title: "Daily Journal 2026-06-30",
            content: "# Daily Journal 2026-06-30\n\n- 08:15 - Older reflection",
            createdAt: Self.date("2026-06-30T08:15:00Z"),
            modifiedAt: Self.date("2026-06-30T09:00:00Z"),
            relativePath: "Inbox/Notes/Daily Journal 2026-06-30.md"
        )
        let newer = Note(
            title: "Daily Journal 2026-07-02",
            content: "# Daily Journal 2026-07-02\n\n- 11:20 - Newer reflection",
            createdAt: Self.date("2026-07-02T11:20:00Z"),
            modifiedAt: Self.date("2026-07-02T12:00:00Z"),
            relativePath: "Inbox/Notes/Daily Journal 2026-07-02.md"
        )
        let ordinary = Note(
            title: "Project note",
            content: "Not a daily journal",
            modifiedAt: Self.date("2026-07-03T12:00:00Z")
        )

        let projection = JournalLibraryReadModel.build(from: [ordinary, older, newer])

        #expect(projection.container.title == "Journal")
        #expect(projection.entries.map(\.note.id) == [newer.id, older.id])
        #expect(projection.defaultSelection?.note.id == newer.id)
        #expect(projection.defaultSelection?.content.contains("Newer reflection") == true)
    }

    @Test("journal navigation tree groups entries by year month week and day")
    func navigationTreeGroupsEntriesByCalendarLevels() throws {
        let first = Note(
            title: "Daily Journal 2026-07-01",
            content: "First",
            modifiedAt: Self.date("2026-07-01T09:00:00Z"),
            relativePath: "Inbox/Notes/Daily Journal 2026-07-01.md"
        )
        let second = Note(
            title: "Daily Journal 2026-07-02",
            content: "Second",
            modifiedAt: Self.date("2026-07-02T09:00:00Z"),
            relativePath: "Inbox/Notes/Daily Journal 2026-07-02.md"
        )

        let projection = JournalLibraryReadModel.build(from: [first, second])
        let year = try #require(projection.navigation.first)
        let month = try #require(year.children.first)
        let dayNodes = month.children.flatMap(\.children)

        #expect(year.title == "2026")
        #expect(month.title == "July")
        #expect(month.children.allSatisfy { $0.title.contains("Week") })
        #expect(dayNodes.map(\.title) == ["Jul 2", "Jul 1"])
        #expect(Set(dayNodes.compactMap(\.entryID)) == Set(projection.entries.map(\.id)))
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

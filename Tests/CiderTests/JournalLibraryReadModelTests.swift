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

    @Test("journal library projection accepts canonical journal titles and keeps legacy titles readable")
    func projectionAcceptsCanonicalJournalTitlesAndLegacyTitles() throws {
        let canonical = Note(
            title: "Journal 07-04-2026",
            content: "# Journal 07-04-2026\n\n## 08:15 voice\nMorning reflection",
            createdAt: Self.date("2026-07-04T08:15:00Z"),
            modifiedAt: Self.date("2026-07-04T09:00:00Z"),
            relativePath: "Inbox/Notes/Journal 07-04-2026.md"
        )
        let legacy = Note(
            title: "Daily Journal 2026-07-03",
            content: "# Daily Journal 2026-07-03\n\n- 17:45 - Legacy reflection",
            createdAt: Self.date("2026-07-03T17:45:00Z"),
            modifiedAt: Self.date("2026-07-03T18:00:00Z"),
            relativePath: "Inbox/Notes/Daily Journal 2026-07-03.md"
        )
        let productDesign = Note(
            title: "Cider journal storage design",
            content: "This product note mentions journal but is not a personal day entry.",
            modifiedAt: Self.date("2026-07-05T12:00:00Z")
        )

        let projection = JournalLibraryReadModel.build(from: [productDesign, legacy, canonical])

        #expect(projection.entries.map(\.note.id) == [canonical.id, legacy.id])
        #expect(projection.entries.map(\.dateLabel) == ["2026-07-04", "2026-07-03"])
        #expect(projection.container.entryCount == 2)
    }

    @Test("journal navigation tree groups entries by year month week and day")
    func navigationTreeGroupsEntriesByCalendarLevels() throws {
        let first = Note(
            title: "Journal 07-01-2026",
            content: "First",
            modifiedAt: Self.date("2026-07-01T09:00:00Z"),
            relativePath: "Inbox/Notes/Journal 07-01-2026.md"
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

    @Test("journal migration preview classifies canonical legacy personal excluded and ambiguous notes")
    func migrationPreviewClassifiesKnownJournalExamples() throws {
        let notes = [
            Note(title: "Journal 05-28-2026", content: "Already canonical"),
            Note(title: "Daily Journal 2026-05-29", content: "Legacy exact"),
            Note(title: "Morning voice journal — 2026-05-28", content: "I talked through the morning."),
            Note(title: "Driving voice journal — 2026-05-29 midday", content: "Car thoughts."),
            Note(title: "Daily Journal Addendum — QA Manager path", content: "Personal review addendum."),
            Note(title: "Late-night 3D print finishing tool journal — 2026-05-31", content: "Shop reflection."),
            Note(title: "Cider journal IA — dashboard module plus Notes filter or Journal sidebar", content: "Product IA notes."),
            Note(title: "Cider journal storage design — note kind, attachments, transcript, dashboard filter", content: "Dev storage notes."),
            Note(title: "CID-wide feature validity audit loop batch 12", content: "Mentions journal in product QA.", relativePath: "Projects/Cider/QA/CID-wide feature validity audit loop batch 12.md"),
            Note(title: "Research journal taxonomy", content: "Could be personal or product."),
        ]

        let preview = JournalMigrationPreviewService().preview(notes: notes)
        let rowsByTitle = Dictionary(uniqueKeysWithValues: preview.rows.map { ($0.note.title, $0) })

        #expect(rowsByTitle["Journal 05-28-2026"]?.classification == .canonical)
        #expect(rowsByTitle["Daily Journal 2026-05-29"]?.classification == .legacyExact)
        #expect(rowsByTitle["Morning voice journal — 2026-05-28"]?.classification == .safePersonalCandidate)
        #expect(rowsByTitle["Driving voice journal — 2026-05-29 midday"]?.classification == .safePersonalCandidate)
        #expect(rowsByTitle["Daily Journal Addendum — QA Manager path"]?.classification == .safePersonalCandidate)
        #expect(rowsByTitle["Late-night 3D print finishing tool journal — 2026-05-31"]?.classification == .safePersonalCandidate)
        #expect(rowsByTitle["Cider journal IA — dashboard module plus Notes filter or Journal sidebar"]?.classification == .excludedProductOrDev)
        #expect(rowsByTitle["Cider journal storage design — note kind, attachments, transcript, dashboard filter"]?.classification == .excludedProductOrDev)
        #expect(rowsByTitle["CID-wide feature validity audit loop batch 12"]?.classification == .excludedProductOrDev)
        #expect(rowsByTitle["Research journal taxonomy"]?.classification == .ambiguous)
        #expect(rowsByTitle["Morning voice journal — 2026-05-28"]?.proposedCanonicalTitle == "Journal 05-28-2026")
        #expect(rowsByTitle["Driving voice journal — 2026-05-29 midday"]?.preservedCaptureHints.contains("driving") == true)
        #expect(preview.mutatesLiveNotes == false)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

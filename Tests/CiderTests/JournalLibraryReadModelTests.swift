import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

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

    @Test("journal entry exposes structured metadata and timestamped source-backed sections")
    func journalEntryExposesStructuredMetadataAndTimestampedSections() throws {
        let content = """
        # Journal 07-04-2026

        ## 08:15
        Source: capture.add

        Morning reflection

        ## 19:27
        Source: voice

        Evening addendum
        """
        let note = Note(
            title: "Journal 07-04-2026",
            content: content,
            createdAt: Self.date("2026-07-04T08:15:00Z"),
            modifiedAt: Self.date("2026-07-04T19:30:00Z"),
            relativePath: "Inbox/Notes/Journal 07-04-2026.md"
        )

        let entry = try #require(JournalLibraryReadModel.build(from: [note]).entries.first)

        #expect(entry.metadata.journalDate == "2026-07-04")
        #expect(entry.metadata.displayTitle == "Journal 07-04-2026")
        #expect(entry.metadata.titleKind == .canonical)
        #expect(entry.metadata.captureSource == "journal.read_model")
        #expect(entry.metadata.sections.map(\.timestamp24Hour) == ["08:15", "19:27"])
        #expect(entry.metadata.sections.map(\.captureSource) == ["capture.add", "voice"])
        #expect(entry.metadata.sections.map { $0.displayTimestamp(format: .twelveHour) } == ["8:15 AM", "7:27 PM"])
        #expect(entry.metadata.sections.allSatisfy { content.contains($0.sourceSnippet) })
        #expect(entry.displayContent(timestampFormat: .twelveHour).contains("- 7:27 PM - Captured from voice note"))
        #expect(entry.content == content)
    }

    @Test("journal rich display normalizes capture headings and hides raw source command")
    func journalRichDisplayNormalizesCaptureHeadingsAndHidesRawSourceCommand() throws {
        let content = """
        # Journal 07-08-2026

        ## Entries
        ## 15:16
        Source: capture.add

        Captured reflection from the agent path.
        """
        let note = Note(
            title: "Journal 07-08-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 07-08-2026.md"
        )

        let entry = try #require(JournalLibraryReadModel.build(from: [note]).entries.first)
        let display = entry.displayContent(timestampFormat: .twelveHour)

        #expect(display.contains("- 3:16 PM - Captured by Cider agent"))
        #expect(!display.contains("## 3:16 PM"))
        #expect(!display.contains("Source: capture.add"))
        #expect(display.contains("Captured reflection from the agent path."))
        #expect(entry.metadata.sections.map(\.captureSource) == ["capture.add"])
        #expect(entry.content == content)
    }

    @Test("journal rich display derives friendly source labels from capture marker")
    func journalRichDisplayDerivesFriendlySourceLabelsFromCaptureMarker() throws {
        let content = """
        # Journal 07-08-2026

        ## 09:05
        Source: discord voice note

        Voice-derived reflection.
        """
        let note = Note(
            title: "Journal 07-08-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 07-08-2026.md"
        )

        let entry = try #require(JournalLibraryReadModel.build(from: [note]).entries.first)
        let display = entry.displayContent(timestampFormat: .twelveHour)

        #expect(display.contains("- 9:05 AM - Captured from Discord voice note"))
        #expect(!display.contains("Source: discord voice note"))
        #expect(entry.metadata.sections.map(\.captureSource) == ["discord voice note"])
        #expect(entry.content == content)
    }

    @Test("journal capture payload exposes multi-entry structured sections without changing raw content")
    @MainActor
    func journalCapturePayloadExposesMultiEntryStructuredSectionsWithoutChangingRawContent() throws {
        let content = """
        # Journal 07-04-2026

        ## 08:15
        Source: capture.add

        Morning reflection

        ## 19:27
        Source: voice

        Evening addendum
        """
        let note = Note(
            title: "Journal 07-04-2026",
            content: content,
            createdAt: Self.date("2026-07-04T08:15:00Z"),
            modifiedAt: Self.date("2026-07-04T19:30:00Z"),
            relativePath: "Inbox/Notes/Journal 07-04-2026.md"
        )
        let result = CiderCLI.DailyNoteAppendResult(
            spec: CiderCLI.DailyNoteKindSpec(kind: "journal", titlePrefix: "Journal"),
            date: "2026-07-04",
            time: "19:27",
            created: false,
            note: note,
            content: content,
            appendedEntry: "## 19:27\nSource: voice\n\nEvening addendum",
            rawContent: "Evening addendum",
            source: "voice"
        )

        let payload = CiderCLI.journalMetadataPayload(for: result)
        let sections = try #require(payload["sections"] as? [[String: Any]])

        #expect(payload["status"] as? String == "derived")
        #expect(payload["journalDate"] as? String == "2026-07-04")
        #expect(payload["displayTitle"] as? String == "Journal 07-04-2026")
        #expect(sections.compactMap { $0["timestamp24Hour"] as? String } == ["08:15", "19:27"])
        #expect(sections.compactMap { $0["captureSource"] as? String } == ["capture.add", "voice"])
        #expect((sections.last?["sourceSnippet"] as? String)?.contains("Evening addendum") == true)
        #expect(result.content == content)
    }

    @Test("journal library projection previews old personal journal captures without importing ambiguous notes")
    func projectionPreviewsOldPersonalJournalCapturesWithoutImportingAmbiguousNotes() throws {
        let oldPersonalCapture = Note(
            title: "Driving voice journal — 2026-05-29 midday",
            content: "Drove home and talked through the day.",
            createdAt: Self.date("2026-05-29T19:30:00Z"),
            modifiedAt: Self.date("2026-05-29T20:00:00Z"),
            relativePath: "Inbox/Files/cider-driving-gas-station-desk-20260529.md"
        )
        let canonical = Note(
            title: "Journal 05-30-2026",
            content: "# Journal 05-30-2026\n\n## 08:15\nCanonical source.",
            createdAt: Self.date("2026-05-30T08:15:00Z"),
            modifiedAt: Self.date("2026-05-30T09:00:00Z"),
            relativePath: "Inbox/Notes/Journal 05-30-2026.md"
        )
        let productDesign = Note(
            title: "Cider journal IA — dashboard module plus Notes filter or Journal sidebar",
            content: "Product IA notes should not become personal Journal entries.",
            modifiedAt: Self.date("2026-05-31T09:00:00Z")
        )
        let ambiguous = Note(
            title: "Research journal taxonomy",
            content: "Could be personal or product.",
            modifiedAt: Self.date("2026-05-31T10:00:00Z")
        )

        let projection = JournalLibraryReadModel.build(from: [ambiguous, productDesign, oldPersonalCapture, canonical])

        #expect(projection.entries.map(\.note.id) == [canonical.id, oldPersonalCapture.id])
        #expect(projection.entries.map(\.dateLabel) == ["2026-05-30", "2026-05-29"])
        #expect(projection.entries.last?.content == oldPersonalCapture.content)
        #expect(projection.entries.last?.note.title == oldPersonalCapture.title)
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
        #expect(Set(dayNodes.compactMap(\.entryID)) == Set(projection.days.map(\.id)))
    }

    @Test("journal projection aggregates same-day legacy sources into one stable selectable day")
    func projectionAggregatesSameDayLegacySourcesWithoutContentLoss() throws {
        let previous = Note(
            title: "Journal 05-28-2026",
            content: "Previous day reflection",
            modifiedAt: Self.date("2026-05-28T20:00:00Z"),
            relativePath: "Inbox/Notes/Journal 05-28-2026.md"
        )
        let morning = Note(
            title: "Morning voice journal — 2026-05-29",
            content: "Morning source content",
            modifiedAt: Self.date("2026-05-29T09:00:00Z"),
            relativePath: "Inbox/Files/morning-voice-journal-20260529.md"
        )
        let midday = Note(
            title: "Driving voice journal — 2026-05-29 midday",
            content: "Midday source content",
            modifiedAt: Self.date("2026-05-29T13:00:00Z"),
            relativePath: "Inbox/Files/driving-voice-journal-20260529.md"
        )
        let evening = Note(
            title: "Journal reflection — 2026-05-29 evening",
            content: "Evening source content",
            modifiedAt: Self.date("2026-05-29T19:00:00Z"),
            relativePath: "Inbox/Files/evening-journal-20260529.md"
        )
        let next = Note(
            title: "Journal 05-31-2026",
            content: "Next day reflection",
            modifiedAt: Self.date("2026-05-31T20:00:00Z"),
            relativePath: "Inbox/Notes/Journal 05-31-2026.md"
        )

        let projection = JournalLibraryReadModel.build(from: [midday, next, morning, previous, evening])
        let dayNodes = projection.navigation
            .flatMap(\.children)
            .flatMap(\.children)
            .flatMap(\.children)
        let allNodes = projection.navigation.flatMap { year in
            [year] + year.children.flatMap { month in
                [month] + month.children.flatMap { week in [week] + week.children }
            }
        }
        let may29 = try #require(projection.days.first { $0.dateLabel == "2026-05-29" })

        #expect(projection.days.map(\.dateLabel) == ["2026-05-31", "2026-05-29", "2026-05-28"])
        #expect(dayNodes.filter { $0.kind == .day("2026-05-29") }.count == 1)
        #expect(Set(allNodes.map(\.id)).count == allNodes.count)
        #expect(dayNodes.filter { $0.entryID == may29.id }.count == 1)
        #expect(may29.sourceEntries.map(\.note.id) == [evening.id, midday.id, morning.id])
        #expect(Set(may29.sourceEntries.map(\.content)) == Set([
            "Morning source content", "Midday source content", "Evening source content"
        ]))
        #expect(may29.isAggregate)
        #expect(projection.defaultDay?.dateLabel == "2026-05-31")
    }

    @Test("single canonical note exposes deterministic source-backed capture cards without rewriting markdown")
    func singleCanonicalNoteExposesSourceBackedCaptureCards() throws {
        let content = """
        # Journal 06-04-2026

        ## 08:15
        Source: discord_voice

        Morning reflection with [Televero](https://televerohealth.com/).

        ## 17:45
        Source: capture.add

        Evening reflection preserves **Markdown** exactly.
        """
        let note = Note(
            title: "Journal 06-04-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 06-04-2026.md"
        )

        let projection = JournalLibraryReadModel.build(from: [note])
        let day = try #require(projection.days.first)

        #expect(projection.days.count == 1)
        #expect(day.captureCards.map(\.timestamp24Hour) == ["08:15", "17:45"])
        #expect(day.captureCards.map(\.captureSource) == ["discord_voice", "capture.add"])
        #expect(day.captureCards[0].sourceContent == """
        ## 08:15
        Source: discord_voice

        Morning reflection with [Televero](https://televerohealth.com/).
        """)
        #expect(day.captureCards[1].sourceContent == """
        ## 17:45
        Source: capture.add

        Evening reflection preserves **Markdown** exactly.
        """)
        #expect(day.captureCards[0].preparedMarkdown(timestampFormat: .twelveHour).contains(
            "[Televero](https://televerohealth.com/)"
        ))
        #expect(day.captureCards[0].sourceEntry.content == content)
        #expect(day.editableEntry?.note.id == note.id)
    }

    @Test("capture card exposes safe external Markdown links without changing source")
    func captureCardExposesSafeExternalMarkdownLinks() throws {
        let content = """
        # Journal 06-03-2026

        ## 08:15
        Source: capture.add

        Follow up with [Televero](https://televerohealth.com/).
        """
        let note = Note(
            title: "Journal 06-03-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 06-03-2026.md"
        )
        let card = try #require(JournalLibraryReadModel.build(from: [note]).days.first?.captureCards.first)

        #expect(card.links(isCanonicalItemResolvable: { _ in false }) == [
            JournalCaptureLink(
                label: "Televero",
                destination: try #require(URL(string: "https://televerohealth.com/")),
                target: .external(try #require(URL(string: "https://televerohealth.com/")))
            )
        ])
        #expect(card.sourceEntry.content == content)
        #expect(card.sourceContent.contains("[Televero](https://televerohealth.com/)"))
    }

    @Test("capture card exposes only explicit resolvable canonical Cider item links")
    func captureCardExposesOnlyResolvableCanonicalCiderItemLinks() throws {
        let resolvedID = UUID()
        let unresolvedID = UUID()
        let resolvedRef = LibraryEntityRef(type: .bookmark, entityID: resolvedID)
        let content = """
        # Journal 06-03-2026

        ## 09:30
        Source: capture.add

        Revisit [saved article](cider://item/bookmark/\(resolvedID.uuidString)).
        Keep Project Juniper plain text.
        Do not link [missing note](cider://item/note/\(unresolvedID.uuidString)).
        """
        let note = Note(
            title: "Journal 06-03-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 06-03-2026.md"
        )
        let card = try #require(JournalLibraryReadModel.build(from: [note]).days.first?.captureCards.first)

        let links = card.links(isCanonicalItemResolvable: { $0 == resolvedRef })

        #expect(links.count == 1)
        #expect(links.first?.label == "saved article")
        #expect(links.first?.target == .item(resolvedRef))
        #expect(!links.contains { $0.label == "missing note" })
        #expect(!links.contains { $0.label.contains("Juniper") })
        let rendered = card.preparedMarkdown(
            timestampFormat: .twentyFourHour,
            isCanonicalItemResolvable: { $0 == resolvedRef }
        )
        #expect(rendered.contains("[saved article](cider://item/bookmark/\(resolvedID.uuidString))"))
        #expect(rendered.contains("Do not link missing note."))
        #expect(!rendered.contains("cider://item/note/\(unresolvedID.uuidString)"))
        #expect(card.sourceEntry.content == content)
    }

    @Test("single source without reliable capture boundaries is not fabricated into cards")
    func sourceWithoutReliableCaptureBoundariesRemainsUnsplit() throws {
        let content = """
        # Journal 06-05-2026

        08:15-ish morning reflection.

        Another paragraph that must not become a capture merely because it is separated.
        """
        let note = Note(
            title: "Journal 06-05-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 06-05-2026.md"
        )

        let day = try #require(JournalLibraryReadModel.build(from: [note]).days.first)

        #expect(day.captureCards.isEmpty)
        #expect(day.editableEntry?.content == content)
    }

    @Test("single explicit timestamp and source remains one source-backed capture card")
    func singleExplicitCaptureUsesCardPresentationWithoutFabricatingMore() throws {
        let content = """
        # Daily Journal 2026-06-04

        ## Entries
        - 04:07 - Morning drive journal — 2026-06-04

        Source: Discord voice message while driving to work.

        Summary:
        - Exact source-backed reflection.
        """
        let note = Note(
            title: "Daily Journal 2026-06-04",
            content: content,
            relativePath: "Inbox/Notes/Daily Journal 2026-06-04.md"
        )

        let day = try #require(JournalLibraryReadModel.build(from: [note]).days.first)

        #expect(day.captureCards.count == 1)
        #expect(day.captureCards[0].timestamp24Hour == "04:07")
        #expect(day.captureCards[0].sourceContent == """
        - 04:07 - Morning drive journal — 2026-06-04

        Source: Discord voice message while driving to work.

        Summary:
        - Exact source-backed reflection.
        """)
        #expect(day.editableEntry?.content == content)
    }

    @Test("multi-note day keeps one row and one source-preserving card per physical note")
    func multiNoteDayKeepsExistingAggregateCards() throws {
        let morning = Note(
            title: "Morning voice journal — 2026-05-29",
            content: "Morning source with https://example.com/plain",
            modifiedAt: Self.date("2026-05-29T09:00:00Z"),
            relativePath: "Inbox/Files/morning-voice-journal-20260529.md"
        )
        let evening = Note(
            title: "Journal reflection — 2026-05-29 evening",
            content: "Evening [source link](https://example.com/evening)",
            modifiedAt: Self.date("2026-05-29T19:00:00Z"),
            relativePath: "Inbox/Files/evening-journal-20260529.md"
        )

        let projection = JournalLibraryReadModel.build(from: [morning, evening])
        let day = try #require(projection.days.first)
        let dayNodes = projection.navigation.flatMap(\.children).flatMap(\.children).flatMap(\.children)

        #expect(projection.days.count == 1)
        #expect(dayNodes.filter { $0.kind == .day("2026-05-29") }.count == 1)
        #expect(day.captureCards.map(\.sourceEntry.note.id) == [evening.id, morning.id])
        #expect(day.captureCards.map(\.sourceContent) == [evening.content, morning.content])
        #expect(day.captureCards[0].preparedMarkdown(timestampFormat: .twelveHour) == evening.content)
        #expect(day.captureCards[1].preparedMarkdown(timestampFormat: .twelveHour) == morning.content)
        #expect(day.editableEntry == nil)
    }

    @Test("journal display timestamps can render as twelve hour without mutating source content")
    func journalDisplayTimestampsCanRenderAsTwelveHourWithoutMutatingSourceContent() throws {
        let content = """
        # Journal 07-04-2026

        ## Entries
        - 00:05 - After midnight thought
        - 12:30 - Lunch reflection
        - 19:27 - Evening journal addendum

        ## 23:59 late heading
        Final note
        """
        let note = Note(
            title: "Journal 07-04-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 07-04-2026.md"
        )

        let entry = try #require(JournalLibraryReadModel.build(from: [note]).entries.first)
        let twelveHour = entry.displayContent(timestampFormat: .twelveHour)
        let twentyFourHour = entry.displayContent(timestampFormat: .twentyFourHour)

        #expect(twelveHour.contains("- 12:05 AM - After midnight thought"))
        #expect(twelveHour.contains("- 12:30 PM - Lunch reflection"))
        #expect(twelveHour.contains("- 7:27 PM - Evening journal addendum"))
        #expect(twelveHour.contains("## 11:59 PM late heading"))
        #expect(twentyFourHour == content)
        #expect(entry.content == content)
    }

    @Test("journal display content canonicalizes legacy heading and date metadata without mutating source")
    func journalDisplayContentCanonicalizesLegacyHeadingAndDateMetadataWithoutMutatingSource() throws {
        let content = """
        # Daily Journal 2026-07-01

        2026-07-01

        - 03:29 - Early note
        - 14:14 - Afternoon thought
        """
        let note = Note(
            title: "Daily Journal 2026-07-01",
            content: content,
            relativePath: "Inbox/Notes/Daily Journal 2026-07-01.md"
        )

        let entry = try #require(JournalLibraryReadModel.build(from: [note]).entries.first)
        let display = entry.displayContent(timestampFormat: .twelveHour)

        #expect(entry.displayTitle == "Journal 07-01-2026")
        #expect(display.contains("# Journal 07-01-2026"))
        #expect(!display.contains("# Daily Journal 2026-07-01"))
        #expect(display.contains("Journal 07-01-2026"))
        #expect(!display.contains("\n2026-07-01\n"))
        #expect(display.contains("- 3:29 AM - Early note"))
        #expect(display.contains("- 2:14 PM - Afternoon thought"))
        #expect(entry.content == content)
    }

    @Test("journal display timestamp cache keeps formatting display only")
    func journalDisplayTimestampCacheKeepsFormattingDisplayOnly() throws {
        let content = """
        # Journal 07-04-2026

        ## 19:27 evening entry
        Stored markdown stays source-backed.
        """
        let note = Note(
            title: "Journal 07-04-2026",
            content: content,
            relativePath: "Inbox/Notes/Journal 07-04-2026.md"
        )
        let entry = try #require(JournalLibraryReadModel.build(from: [note]).entries.first)

        #expect(entry.cachedDisplayContent(timestampFormat: .twelveHour) == nil)

        let formatted = entry.preparedDisplayContent(timestampFormat: .twelveHour)

        #expect(formatted.contains("## 7:27 PM evening entry"))
        #expect(entry.cachedDisplayContent(timestampFormat: .twelveHour) == formatted)
        #expect(entry.preparedDisplayContent(timestampFormat: .twentyFourHour) == content)
        #expect(entry.content == content)
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
            Note(
                title: "North Star Backend Capability Audit + Second-Brain Graph Push",
                content: """
                Created: 2026-06-14 12:45 PDT
                Operator: Cody implementation lane, Cider/Hermes verification lane
                Recent related card: CID-506 - item backfill-journals landed in Testing.

                Visher wants a long-running backend initiative that audits and improves Cider toward the North Star: a local-first second brain where journals, captures, bookmarks, files, reminders, people, places, projects, and agent conversations become reviewable, linked, provenance-preserving memory objects.
                The backend should become capable enough that app/voice/chat surfaces are thin doors into shared truth, not one-off feature piles.
                """,
                relativePath: "Inbox/Notes/North Star Backend Capability Audit + Second-Brain Graph Push.md"
            ),
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
        #expect(rowsByTitle["North Star Backend Capability Audit + Second-Brain Graph Push"]?.classification == .excludedProductOrDev)
        #expect(rowsByTitle["Research journal taxonomy"]?.classification == .ambiguous)
        #expect(rowsByTitle["Morning voice journal — 2026-05-28"]?.proposedCanonicalTitle == "Journal 05-28-2026")
        #expect(rowsByTitle["Driving voice journal — 2026-05-29 midday"]?.preservedCaptureHints.contains("driving") == true)
        #expect(preview.mutatesLiveNotes == false)
    }

    @Test("journal migration preview explains source backed date eligibility without promoting ambiguous notes")
    func migrationPreviewExplainsSourceBackedDateEligibility() throws {
        let recoverable = Note(
            title: "Driving voice journal from May 29, 2026",
            content: "Drove home and talked through the day.",
            createdAt: Self.date("2026-05-30T01:30:00Z"),
            modifiedAt: Self.date("2026-05-30T02:00:00Z"),
            relativePath: "Inbox/Files/driving-voice-journal.md"
        )
        let ambiguous = Note(
            title: "Driving voice journal after lunch",
            content: "I mentioned May 29 but did not write down a year.",
            createdAt: Self.date("2026-05-31T19:30:00Z"),
            modifiedAt: Self.date("2026-05-31T20:00:00Z"),
            relativePath: "Inbox/Files/driving-voice-journal-after-lunch.md"
        )
        let product = Note(
            title: "Cider journal IA 05/29/2026",
            content: "Product IA notes should not become personal Journal entries.",
            modifiedAt: Self.date("2026-05-31T09:00:00Z"),
            relativePath: "Projects/Cider/Plans/journal-ia.md"
        )

        let preview = JournalMigrationPreviewService().preview(notes: [recoverable, ambiguous, product])
        let rowsByTitle = Dictionary(uniqueKeysWithValues: preview.rows.map { ($0.note.title, $0) })

        let recoverableRow = try #require(rowsByTitle[recoverable.title])
        #expect(recoverableRow.classification == .safePersonalCandidate)
        #expect(recoverableRow.proposedISODate == "2026-05-29")
        #expect(recoverableRow.proposedCanonicalTitle == "Journal 05-29-2026")
        let titleEvidence = recoverableRow.dateEvidence.first
        #expect(titleEvidence?.isoDate == "2026-05-29")
        #expect(titleEvidence?.source == .title)
        #expect(titleEvidence?.kind == .monthNameDate)
        #expect(titleEvidence?.rawValue == "May 29, 2026")
        #expect(recoverableRow.dateIneligibilityReason == nil)
        #expect(recoverableRow.isJournalLibraryEligible == true)

        let ambiguousRow = try #require(rowsByTitle[ambiguous.title])
        #expect(ambiguousRow.classification == .safePersonalCandidate)
        #expect(ambiguousRow.proposedISODate == nil)
        #expect(ambiguousRow.proposedCanonicalTitle == nil)
        #expect(ambiguousRow.dateEvidence.isEmpty)
        #expect(ambiguousRow.dateIneligibilityReason == "No unambiguous source-backed date found in title or body.")
        #expect(ambiguousRow.isJournalLibraryEligible == false)

        let productRow = try #require(rowsByTitle[product.title])
        #expect(productRow.classification == .excludedProductOrDev)
        #expect(productRow.proposedISODate == nil)
        #expect(productRow.dateIneligibilityReason == "Excluded product/development journal context.")
        #expect(productRow.isJournalLibraryEligible == false)

        let projection = JournalLibraryReadModel.build(from: [recoverable, ambiguous, product])
        #expect(projection.entries.map(\.note.id) == [recoverable.id])
        #expect(projection.entries.first?.dateLabel == "2026-05-29")
        #expect(projection.entries.first?.content == recoverable.content)
        #expect(projection.entries.first?.note.createdAt == recoverable.createdAt)
        #expect(projection.entries.first?.note.modifiedAt == recoverable.modifiedAt)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

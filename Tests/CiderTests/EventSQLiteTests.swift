import Foundation
import Testing
@testable import Cider

@Suite("Event SQLite Tests")
@MainActor
struct EventSQLiteTests {

    // MARK: - Helpers

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-event-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    /// Remove a temporary database file and its WAL/SHM companions.
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    /// Create and open a fresh database for testing.
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    /// Create DateCardStorage wired to the test database.
    private func makeService(_ db: CiderDatabase) -> DateCardStorage {
        DateCardStorage(database: db)
    }

    private func makeTempVaultURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-event-vault-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Basic Round-Trip

    @Test("Date card round-trips through SQLite: persist and load")
    func dateCardRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let card = DateCard(
            title: "Meeting",
            details: "Quarterly review",
            startAt: start
        )

        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.count == 1)
        let loaded = service2.dateCards[0]
        #expect(loaded.id == card.id)
        #expect(loaded.title == "Meeting")
        #expect(loaded.details == "Quarterly review")
        #expect(abs(loaded.startAt.timeIntervalSince(start)) < 0.001)
    }

    @Test("Date card snoozedUntil round-trips through SQLite")
    func dateCardSnoozedUntilRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let snoozedUntil = Date(timeIntervalSince1970: 1_745_170_800)
        let card = DateCard(
            title: "DMV appointment",
            startAt: Date(timeIntervalSince1970: 1_745_084_400),
            snoozedUntil: snoozedUntil
        )

        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.first?.snoozedUntil == snoozedUntil)
    }

    // MARK: - All Fields

    @Test("Date card with all fields round-trips correctly")
    func dateCardAllFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "Work", colorHex: "#3B82F6")
        let label2 = labelStorage.createLabel(name: "Personal", colorHex: "#EF4444")

        let folder = VaultFolder(relativePath: "Events")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_003_600)
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        let created = Date(timeIntervalSince1970: 1_600_000_000)

        let card = DateCard(
            title: "Full Event",
            details: "Detailed description",
            startAt: start,
            endAt: end,
            allDay: false,
            location: "Conference Room A",
            amount: 123.45,
            recurrenceRule: nil,
            isCompleted: true,
            completedAt: completed,
            labelIDs: [label1.id, label2.id],
            linkedEntities: [],
            folderID: folder.id,
            rules: [],
            createdAt: created,
            updatedAt: created
        )

        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.count == 1)
        let loaded = service2.dateCards[0]
        #expect(loaded.title == "Full Event")
        #expect(loaded.details == "Detailed description")
        #expect(loaded.location == "Conference Room A")
        #expect(loaded.amount == 123.45)
        #expect(loaded.allDay == false)
        #expect(loaded.isCompleted == true)
        #expect(abs(loaded.startAt.timeIntervalSince(start)) < 0.001)
        #expect(abs((loaded.endAt ?? .distantPast).timeIntervalSince(end)) < 0.001)
        #expect(abs((loaded.completedAt ?? .distantPast).timeIntervalSince(completed)) < 0.001)
        #expect(loaded.folderID == folder.id)
        #expect(Set(loaded.labelIDs) == Set([label1.id, label2.id]))
    }

    // MARK: - All-day Event

    @Test("All-day event allDay flag round-trips")
    func allDayEvent() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let card = DateCard(title: "Birthday", startAt: Date(), allDay: true)
        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards[0].allDay == true)
    }

    @Test("All-day VALUE=DATE preserves local calendar day in Pacific time")
    func allDayValueDatePreservesPacificCalendarDay() throws {
        let originalTimeZone = NSTimeZone.default
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        NSTimeZone.default = pacific
        defer { NSTimeZone.default = originalTimeZone }

        let parsed = try #require(
            ICalendarSerializer.parseDateCard(
                """
                BEGIN:VCALENDAR
                VERSION:2.0
                PRODID:-//Cider//NONSGML v1.0//EN
                BEGIN:VEVENT
                UID:11111111-1111-1111-1111-111111111111
                SUMMARY:Rilynn Nordquist Birthday
                DTSTART;VALUE=DATE:20260630
                END:VEVENT
                END:VCALENDAR
                """
            )
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let components = calendar.dateComponents([.year, .month, .day], from: parsed.startAt)

        #expect(parsed.allDay == true)
        #expect(components.year == 2026)
        #expect(components.month == 6)
        #expect(components.day == 30)
        #expect(ICalendarSerializer.serializeDateCard(parsed).contains("DTSTART;VALUE=DATE:20260630"))
    }

    // MARK: - Nil Optionals

    @Test("Nil optional fields round-trip as nil")
    func nilOptionalsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let card = DateCard(
            title: "Minimal",
            startAt: Date(),
            endAt: nil,
            amount: nil,
            recurrenceRule: nil,
            isCompleted: false,
            completedAt: nil
        )

        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        let loaded = service2.dateCards[0]
        #expect(loaded.endAt == nil)
        #expect(loaded.amount == nil)
        #expect(loaded.recurrenceRule == nil)
        #expect(loaded.completedAt == nil)
        #expect(loaded.isCompleted == false)
        #expect(loaded.details == "")
        #expect(loaded.location == "")
        #expect(loaded.labelIDs.isEmpty)
        #expect(loaded.linkedEntities.isEmpty)
        #expect(loaded.rules.isEmpty)
    }

    // MARK: - Update

    @Test("Updating an existing date card replaces its data")
    func updateDateCard() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        var card = DateCard(title: "Original", startAt: Date(timeIntervalSince1970: 1_700_000_000))
        service.persistEventToDatabase(db, dateCard: card)

        card.title = "Updated"
        card.details = "New details"
        card.location = "Zoom"
        card.isCompleted = true
        card.completedAt = Date()
        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.count == 1)
        let loaded = service2.dateCards[0]
        #expect(loaded.title == "Updated")
        #expect(loaded.details == "New details")
        #expect(loaded.location == "Zoom")
        #expect(loaded.isCompleted == true)
    }

    @Test("Date card update and completion mutations record audit entries")
    func dateCardMetadataMutationsRecordAuditEntries() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        try fm.createDirectory(
            at: StoragePaths.cachedInboxSubdirectoryURL(for: .dateCards),
            withIntermediateDirectories: true
        )

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let card = DateCard(title: "Audit Event", startAt: start, allDay: false)
        let seed = makeService(db)
        seed.persistEventToDatabase(db, dateCard: card)

        let service = makeService(db)
        service.loadEventsFromDatabase(db)

        var updated = try #require(service.dateCards.first { $0.id == card.id })
        updated.startAt = start.addingTimeInterval(3_600)
        updated.allDay = true
        #expect(service.updateDateCard(updated) == true)
        #expect(service.markCompleted(card.id, completed: true) == true)

        let entries = MutationAuditService(database: db).loadEntries()
        let update = entries.first { $0.itemID == card.id && $0.action == "update" }
        let completed = entries.first { $0.itemID == card.id && $0.action == "set_completed" }

        #expect(update?.itemType == "dateCard")
        #expect(update?.beforeState["allDay"] == "false")
        #expect(update?.afterState["allDay"] == "true")

        #expect(completed?.itemType == "dateCard")
        #expect(completed?.beforeState["isCompleted"] == "false")
        #expect(completed?.afterState["isCompleted"] == "true")
    }

    // MARK: - Delete

    @Test("Delete date card removes items + CASCADE cleans join tables")
    func deleteDateCard() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "X")

        let service = makeService(db)

        // A second card that the first one links to.
        let target = DateCard(title: "Target", startAt: Date())
        service.persistEventToDatabase(db, dateCard: target)

        let card = DateCard(
            title: "Doomed",
            startAt: Date(),
            labelIDs: [label.id],
            linkedEntities: [LibraryEntityRef(type: .dateCard, entityID: target.id)]
        )
        service.persistEventToDatabase(db, dateCard: card)

        service.deleteEventFromDatabase(db, dateCardID: card.id)

        // Items row gone
        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)
        #expect(service2.dateCards.contains(where: { $0.id == card.id }) == false)
        #expect(service2.dateCards.contains(where: { $0.id == target.id }) == true)

        // Join tables cleaned via CASCADE
        let labelsStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        labelsStmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try labelsStmt.step()
        #expect(labelsStmt.int(at: 0) == 0)

        let linksStmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        linksStmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try linksStmt.step()
        #expect(linksStmt.int(at: 0) == 0)

        // Detail row gone
        let eventStmt = try db.prepare("SELECT count(*) FROM events WHERE item_id = ?;")
        eventStmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try eventStmt.step()
        #expect(eventStmt.int(at: 0) == 0)
    }

    // MARK: - Multiple

    @Test("Multiple date cards persist and load correctly")
    func multipleDateCards() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let c1 = DateCard(title: "One", startAt: base)
        let c2 = DateCard(title: "Two", startAt: base.addingTimeInterval(3600))
        let c3 = DateCard(title: "Three", startAt: base.addingTimeInterval(7200))

        service.persistEventToDatabase(db, dateCard: c1)
        service.persistEventToDatabase(db, dateCard: c2)
        service.persistEventToDatabase(db, dateCard: c3)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.count == 3)
        let titles = Set(service2.dateCards.map(\.title))
        #expect(titles == Set(["One", "Two", "Three"]))
    }

    // MARK: - Labels

    @Test("Label IDs round-trip through item_labels and updates replace old assignments")
    func labelIDsRoundTripAndUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let l1 = labelStorage.createLabel(name: "L1")
        let l2 = labelStorage.createLabel(name: "L2")
        let l3 = labelStorage.createLabel(name: "L3")

        let service = makeService(db)
        var card = DateCard(title: "Labeled", startAt: Date(), labelIDs: [l1.id, l2.id])
        service.persistEventToDatabase(db, dateCard: card)

        let loaded1 = makeService(db)
        loaded1.loadEventsFromDatabase(db)
        #expect(Set(loaded1.dateCards[0].labelIDs) == Set([l1.id, l2.id]))

        card.labelIDs = [l2.id, l3.id]
        service.persistEventToDatabase(db, dateCard: card)

        let loaded2 = makeService(db)
        loaded2.loadEventsFromDatabase(db)
        #expect(Set(loaded2.dateCards[0].labelIDs) == Set([l2.id, l3.id]))
    }

    // MARK: - Folder

    @Test("Date card with folder ID round-trips")
    func dateCardWithFolder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Work")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)
        let card = DateCard(title: "In Folder", startAt: Date(), folderID: folder.id)
        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards[0].folderID == folder.id)
    }

    // MARK: - Empty DB

    @Test("Empty database loads empty date cards array")
    func emptyDatabase() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadEventsFromDatabase(db)

        #expect(service.dateCards.isEmpty)
    }

    // MARK: - Date Precision

    @Test("Date fields survive round-trip with reasonable precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let now = Date()
        let card = DateCard(
            title: "Timed",
            startAt: now,
            endAt: now.addingTimeInterval(1800),
            completedAt: now,
            createdAt: now,
            updatedAt: now
        )
        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        let loaded = service2.dateCards[0]
        #expect(abs(loaded.createdAt.timeIntervalSince(now)) < 0.001)
        #expect(abs(loaded.updatedAt.timeIntervalSince(now)) < 0.001)
        #expect(abs(loaded.startAt.timeIntervalSince(now)) < 0.001)
        #expect(abs((loaded.endAt ?? .distantPast).timeIntervalSince(now.addingTimeInterval(1800))) < 0.001)
        #expect(abs((loaded.completedAt ?? .distantPast).timeIntervalSince(now)) < 0.001)
    }

    // MARK: - Recurrence Rule

    @Test("Recurrence rule round-trips through JSON blob (all frequencies)")
    func recurrenceRuleRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let endDate = Date(timeIntervalSince1970: 2_000_000_000)

        for frequency in DateCardRecurrenceFrequency.allCases {
            let card = DateCard(
                id: UUID(),
                title: "Recurring \(frequency.rawValue)",
                startAt: Date(timeIntervalSince1970: 1_700_000_000),
                recurrenceRule: DateCardRecurrenceRule(frequency: frequency, interval: 3, endDate: endDate)
            )
            service.persistEventToDatabase(db, dateCard: card)
        }

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.count == DateCardRecurrenceFrequency.allCases.count)
        for loaded in service2.dateCards {
            #expect(loaded.recurrenceRule != nil)
            #expect(loaded.recurrenceRule?.interval == 3)
            #expect(loaded.recurrenceRule?.endDate != nil)
            #expect(abs((loaded.recurrenceRule?.endDate ?? .distantPast).timeIntervalSince(endDate)) < 0.001)
        }
    }

    @Test("Nil recurrence rule stored as NULL")
    func nilRecurrenceRule() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let card = DateCard(title: "One-shot", startAt: Date(), recurrenceRule: nil)
        service.persistEventToDatabase(db, dateCard: card)

        let stmt = try db.prepare("SELECT recurrence_rule FROM events WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try stmt.step()
        #expect(stmt.optionalString(at: 0) == nil)
    }

    // MARK: - Surfacing Rules

    @Test("Surfacing rules array round-trips through JSON blob")
    func surfacingRulesRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let rules = [
            SurfacingRule(type: .pinUntilDone, integerValue: nil, isEnabled: true),
            SurfacingRule(type: .surfaceDaysBeforeDate, integerValue: 7, isEnabled: true),
            SurfacingRule(type: .remindBeforeMinutes, integerValue: 30, isEnabled: false)
        ]
        let card = DateCard(title: "With rules", startAt: Date(), rules: rules)
        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        let loaded = service2.dateCards[0]
        #expect(loaded.rules.count == 3)
        #expect(loaded.rules.first(where: { $0.type == .pinUntilDone })?.isEnabled == true)
        #expect(loaded.rules.first(where: { $0.type == .surfaceDaysBeforeDate })?.integerValue == 7)
        #expect(loaded.rules.first(where: { $0.type == .remindBeforeMinutes })?.integerValue == 30)
        #expect(loaded.rules.first(where: { $0.type == .remindBeforeMinutes })?.isEnabled == false)
    }

    @Test("Empty surfacing rules stored as NULL, not empty JSON")
    func emptyRulesStoredAsNull() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let card = DateCard(title: "No rules", startAt: Date(), rules: [])
        service.persistEventToDatabase(db, dateCard: card)

        let stmt = try db.prepare("SELECT surfacing_rules FROM events WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try stmt.step()
        #expect(stmt.optionalString(at: 0) == nil)
    }

    // MARK: - linkedEntities

    @Test("linkedEntities round-trip through item_links when target event exists")
    func linkedEntitiesRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let target = DateCard(title: "Target", startAt: Date())
        service.persistEventToDatabase(db, dateCard: target)

        let source = DateCard(
            title: "Source",
            startAt: Date(),
            linkedEntities: [LibraryEntityRef(type: .dateCard, entityID: target.id)]
        )
        service.persistEventToDatabase(db, dateCard: source)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        let loadedSource = service2.dateCards.first { $0.id == source.id }
        #expect(loadedSource != nil)
        #expect(loadedSource?.linkedEntities.count == 1)
        #expect(loadedSource?.linkedEntities.first?.entityID == target.id)
        #expect(loadedSource?.linkedEntities.first?.type == .dateCard)
    }

    @Test("linkedEntities to non-existent target silently dropped")
    func linkedEntitiesDroppedWhenMissingTarget() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let fakeTarget = UUID()
        let card = DateCard(
            title: "Has dangling link",
            startAt: Date(),
            linkedEntities: [LibraryEntityRef(type: .dateCard, entityID: fakeTarget)]
        )

        service.persistEventToDatabase(db, dateCard: card)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        let loaded = service2.dateCards[0]
        #expect(loaded.linkedEntities.isEmpty)

        let stmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        stmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    @Test("linkedEntities to non-migrated types are silently filtered")
    func linkedEntitiesNonMigratedTypesFiltered() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let card = DateCard(
            title: "Has session link",
            startAt: Date(),
            linkedEntities: [
                LibraryEntityRef(type: .session, entityID: UUID()),
                LibraryEntityRef(type: .externalFile, entityID: UUID())
            ]
        )
        service.persistEventToDatabase(db, dateCard: card)

        let stmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        stmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)
        #expect(service2.dateCards[0].linkedEntities.isEmpty)
    }

    @Test("Updating linkedEntities replaces old link rows")
    func linkedEntitiesUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let a = DateCard(title: "A", startAt: Date())
        let b = DateCard(title: "B", startAt: Date())
        service.persistEventToDatabase(db, dateCard: a)
        service.persistEventToDatabase(db, dateCard: b)

        var source = DateCard(
            title: "Source",
            startAt: Date(),
            linkedEntities: [LibraryEntityRef(type: .dateCard, entityID: a.id)]
        )
        service.persistEventToDatabase(db, dateCard: source)

        source.linkedEntities = [LibraryEntityRef(type: .dateCard, entityID: b.id)]
        service.persistEventToDatabase(db, dateCard: source)

        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        let loaded = service2.dateCards.first { $0.id == source.id }
        #expect(loaded?.linkedEntities.count == 1)
        #expect(loaded?.linkedEntities.first?.entityID == b.id)
    }

    // MARK: - Filename / relative_path round-trip

    @Test("Uniquified filename round-trips through items.relative_path")
    func uniquifiedFilenameRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        // Simulate the real creation path producing a collision-suffixed filename.
        let card = DateCard(title: "Team Meeting", startAt: Date())
        service._setIndexEntryForTesting(dateCardID: card.id, filename: "Team Meeting (2).ics")

        service.persistEventToDatabase(db, dateCard: card)

        // Verify relative_path was persisted to the items table.
        let stmt = try db.prepare("SELECT relative_path FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(card.id), at: 1)
        try stmt.step()
        let relPath = stmt.optionalString(at: 0)
        #expect(relPath == "Inbox/Date Cards/Team Meeting (2).ics")

        // Reload in a fresh service and verify the filename is recovered EXACTLY.
        let service2 = makeService(db)
        service2.loadEventsFromDatabase(db)

        #expect(service2.dateCards.count == 1)
        let recovered = service2._indexFilenameForTesting(dateCardID: card.id)
        #expect(recovered == "Team Meeting (2).ics")
    }

    // MARK: - Disk write failure gates SQLite persistence

    @Test("writeICSFile returns false when the target directory does not exist")
    func writeICSFileReturnsFalseOnDiskError() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        // Target a path whose parent directory does not exist → file write must fail.
        let bogusDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-nonexistent-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        let bogusURL = bogusDir.appendingPathComponent("event.ics")

        let card = DateCard(title: "Should not persist", startAt: Date())
        let ok = service.writeICSFile(for: card, to: bogusURL)
        #expect(ok == false)
        #expect(FileManager.default.fileExists(atPath: bogusURL.path) == false)

        // And a sanity check: writing to a real path returns true.
        let realDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-event-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: realDir) }
        let realURL = realDir.appendingPathComponent("event.ics")
        #expect(service.writeICSFile(for: card, to: realURL) == true)
        #expect(FileManager.default.fileExists(atPath: realURL.path) == true)
    }
}

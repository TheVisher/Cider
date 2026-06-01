import XCTest
@testable import Cider

final class TemporalModelsCodableTests: XCTestCase {
    func testDateCardCodableRoundTrip() throws {
        let original = DateCard(
            title: "Dentist",
            details: "Bring insurance card",
            startAt: Date(timeIntervalSince1970: 1_700_000_000),
            allDay: false,
            location: "Main St",
            amount: 129.45,
            recurrenceRule: DateCardRecurrenceRule(frequency: .monthly, interval: 1),
            labelIDs: [UUID()],
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: UUID())],
            rules: [SurfacingRule(type: .surfaceDaysBeforeDate, integerValue: 3)]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DateCard.self, from: data)

        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.location, original.location)
        XCTAssertNotNil(decoded.amount)
        XCTAssertEqual(decoded.amount ?? 0, 129.45, accuracy: 0.001)
        XCTAssertEqual(decoded.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(decoded.rules.first?.type, .surfaceDaysBeforeDate)
    }

    // MARK: - DateCardUrgency

    func testUrgencyOverdue() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let card = DateCard(title: "Past event", startAt: yesterday)
        XCTAssertEqual(card.urgency(now: now, windowDays: 7), .overdue)
    }

    func testUrgencyToday() {
        let now = Date()
        let card = DateCard(title: "Today event", startAt: now)
        XCTAssertEqual(card.urgency(now: now, windowDays: 7), .today)
    }

    func testUrgencyApproaching() {
        let now = Date()
        let threeDaysOut = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        let card = DateCard(title: "Soon event", startAt: threeDaysOut)
        XCTAssertEqual(card.urgency(now: now, windowDays: 7), .approaching(daysUntil: 3))
    }

    func testUrgencyBeyondWindow() {
        let now = Date()
        let tenDaysOut = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        let card = DateCard(title: "Far event", startAt: tenDaysOut)
        XCTAssertNil(card.urgency(now: now, windowDays: 7))
    }

    func testUrgencyCompletedReturnsNil() {
        let now = Date()
        let card = DateCard(title: "Done event", startAt: now, isCompleted: true)
        XCTAssertNil(card.urgency(now: now, windowDays: 7))
    }

    func testUrgencyOverdueCompleted() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let card = DateCard(title: "Past done", startAt: yesterday, isCompleted: true)
        XCTAssertNil(card.urgency(now: now, windowDays: 7))
    }

    func testUrgencyWindowZeroDisabled() {
        let now = Date()
        let card = DateCard(title: "Tomorrow", startAt: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        XCTAssertNil(card.urgency(now: now, windowDays: 0))
    }

    func testUrgencyExactlyAtWindowBoundary() {
        let now = Date()
        let sevenDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let card = DateCard(title: "Boundary", startAt: sevenDaysOut)
        XCTAssertEqual(card.urgency(now: now, windowDays: 7), .approaching(daysUntil: 7))
    }

    func testUrgencyOneDayPastWindow() {
        let now = Date()
        let eightDaysOut = Calendar.current.date(byAdding: .day, value: 8, to: now)!
        let card = DateCard(title: "Just outside", startAt: eightDaysOut)
        XCTAssertNil(card.urgency(now: now, windowDays: 7))
    }

    func testLegacyViewCodableRoundTrip() throws {
        var filter = LibraryFilterSpec()
        filter.entityTypes = [.bookmark, .dateCard]
        filter.includeCompleted = false
        filter.textQuery = "bills"

        let original = LegacyView(
            name: "Bills",
            filterSpec: filter,
            sortSpec: LibrarySortSpec(mode: .updatedDescending),
            layoutSpec: LegacyViewLayoutSpec(
                displayMode: .grid,
                cardSizeScale: 1.75,
                showsGhostCells: true,
                showsCalendarProjection: true
            ),
            isTabPinned: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LegacyView.self, from: data)

        XCTAssertEqual(decoded.name, "Bills")
        XCTAssertEqual(decoded.filterSpec.entityTypes, [.bookmark, .dateCard])
        XCTAssertEqual(decoded.sortSpec.mode, .updatedDescending)
        XCTAssertEqual(decoded.layoutSpec.displayMode, .grid)
        XCTAssertTrue(decoded.layoutSpec.showsCalendarProjection)
    }
}

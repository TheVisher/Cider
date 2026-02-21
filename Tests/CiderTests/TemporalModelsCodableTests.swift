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

    func testSavedViewCodableRoundTrip() throws {
        var filter = SavedViewFilterSpec()
        filter.entityTypes = [.bookmark, .dateCard]
        filter.includeCompleted = false
        filter.textQuery = "bills"

        let original = SavedView(
            name: "Bills",
            filterSpec: filter,
            sortSpec: SavedViewSortSpec(mode: .updatedDescending),
            layoutSpec: SavedViewLayoutSpec(
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
        let decoded = try decoder.decode(SavedView.self, from: data)

        XCTAssertEqual(decoded.name, "Bills")
        XCTAssertEqual(decoded.filterSpec.entityTypes, [.bookmark, .dateCard])
        XCTAssertEqual(decoded.sortSpec.mode, .updatedDescending)
        XCTAssertEqual(decoded.layoutSpec.displayMode, .grid)
        XCTAssertTrue(decoded.layoutSpec.showsCalendarProjection)
    }
}

import XCTest
@testable import Cider

final class TemporalActionURLTests: XCTestCase {
    func testTodoActionURLCodableAndICalendarRoundTrip() throws {
        let original = TodoCard(
            title: "Pay rent",
            actionURLString: "https://rent.example.com/pay"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TodoCard.self, from: data)
        XCTAssertEqual(decoded.actionURLString, "https://rent.example.com/pay")
        XCTAssertEqual(decoded.actionURL?.absoluteString, "https://rent.example.com/pay")

        let ics = ICalendarSerializer.serializeTodo(original)
        XCTAssertTrue(ics.contains("X-CIDER-ACTION-URL:https://rent.example.com/pay"))
        let parsed = try XCTUnwrap(ICalendarSerializer.parseTodo(ics))
        XCTAssertEqual(parsed.actionURLString, "https://rent.example.com/pay")
    }

    func testDateCardActionURLCodableAndICalendarRoundTrip() throws {
        let original = DateCard(
            title: "Rent due",
            startAt: Date(timeIntervalSince1970: 1_700_000_000),
            actionURLString: "rent.example.com/pay"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DateCard.self, from: data)
        XCTAssertEqual(decoded.actionURLString, "rent.example.com/pay")
        XCTAssertEqual(decoded.actionURL?.absoluteString, "https://rent.example.com/pay")

        let ics = ICalendarSerializer.serializeDateCard(original)
        XCTAssertTrue(ics.contains("X-CIDER-ACTION-URL:rent.example.com/pay"))
        let parsed = try XCTUnwrap(ICalendarSerializer.parseDateCard(ics))
        XCTAssertEqual(parsed.actionURLString, "rent.example.com/pay")
    }

    func testBlankActionURLNormalizesToNil() {
        XCTAssertNil(TodoCard(title: "Todo", actionURLString: "  ").actionURLString)
        XCTAssertNil(DateCard(title: "Event", startAt: Date(), actionURLString: "\n").actionURLString)
    }
}

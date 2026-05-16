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

    func testSnoozedUntilCodableAndICalendarRoundTrip() throws {
        let snoozedUntil = Date(timeIntervalSince1970: 1_745_170_800)
        let todo = TodoCard(
            title: "Pay rent",
            dueDate: Date(timeIntervalSince1970: 1_745_084_400),
            snoozedUntil: snoozedUntil
        )
        let event = DateCard(
            title: "DMV appointment",
            startAt: Date(timeIntervalSince1970: 1_745_084_400),
            snoozedUntil: snoozedUntil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decodedTodo = try decoder.decode(TodoCard.self, from: encoder.encode(todo))
        XCTAssertEqual(decodedTodo.snoozedUntil, snoozedUntil)
        let parsedTodo = try XCTUnwrap(ICalendarSerializer.parseTodo(ICalendarSerializer.serializeTodo(todo)))
        XCTAssertEqual(parsedTodo.snoozedUntil, snoozedUntil)

        let decodedEvent = try decoder.decode(DateCard.self, from: encoder.encode(event))
        XCTAssertEqual(decodedEvent.snoozedUntil, snoozedUntil)
        let parsedEvent = try XCTUnwrap(ICalendarSerializer.parseDateCard(ICalendarSerializer.serializeDateCard(event)))
        XCTAssertEqual(parsedEvent.snoozedUntil, snoozedUntil)
    }
}

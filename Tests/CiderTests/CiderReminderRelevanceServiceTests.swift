import XCTest
@testable import Cider

final class CiderReminderRelevanceServiceTests: XCTestCase {
    func testReminderRelevanceExplainsActionableQuietAndReviewStates() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let dueToday = TodoCard(
            title: "Pay rent",
            dueDate: now,
            priority: .high,
            actionURLString: "https://rent.example.com",
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400)
        )
        let missingReminder = TodoCard(
            title: "Schedule dentist",
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now.addingTimeInterval(-3_600)
        )
        let distantTodo = TodoCard(
            title: "Renew passport",
            dueDate: calendar.date(byAdding: .day, value: 40, to: now)!,
            createdAt: now,
            updatedAt: now
        )
        let completedTodo = TodoCard(
            title: "Already handled",
            dueDate: now,
            isCompleted: true,
            completedAt: now,
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now
        )
        let missingActionURL = DateCard(
            title: "DMV appointment",
            startAt: now,
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now
        )
        let completedDate = DateCard(
            title: "Past appointment",
            startAt: now,
            isCompleted: true,
            completedAt: now,
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now
        )

        let items = CiderReminderRelevanceService.relevance(
            todos: [dueToday, missingReminder, distantTodo, completedTodo],
            dateCards: [missingActionURL, completedDate],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.title), ["Pay rent", "DMV appointment", "Schedule dentist", "Renew passport"])
        XCTAssertEqual(items[0].surfacing.reason, "due today")
        XCTAssertEqual(items[0].surfacing.urgency, "today")
        XCTAssertEqual(items[0].surfacing.reviewState, "ok")
        XCTAssertEqual(items[0].surfacing.suggestedAction, "open action URL")
        XCTAssertEqual(items[0].surfacing.actionURLString, "https://rent.example.com")
        XCTAssertTrue(items[0].surfaceToday)

        XCTAssertEqual(items[1].surfacing.reason, "today")
        XCTAssertEqual(items[1].surfacing.reviewState, "pending")
        XCTAssertEqual(items[1].surfacing.suggestedAction, "Add action URL")
        XCTAssertTrue(items[1].surfaceToday)

        XCTAssertEqual(items[2].surfacing.reason, "Todo is missing a reminder")
        XCTAssertEqual(items[2].surfacing.urgency, "review")
        XCTAssertEqual(items[2].surfacing.reviewState, "needs_review")
        XCTAssertEqual(items[2].surfacing.suggestedAction, "Add reminder")
        XCTAssertTrue(items[2].surfaceToday)

        XCTAssertEqual(items[3].surfacing.reason, "outside reminder window")
        XCTAssertEqual(items[3].surfacing.urgency, "normal")
        XCTAssertEqual(items[3].surfacing.reviewState, "ok")
        XCTAssertFalse(items[3].surfaceToday)
    }
}

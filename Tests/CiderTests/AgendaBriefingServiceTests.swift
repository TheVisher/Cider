import XCTest
@testable import Cider

final class AgendaBriefingServiceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }

    func testCompletedSameCycleTodoSuppressesMatchingDateCard() {
        let now = date(2026, 5, 7)
        let paidRent = TodoCard(title: "Pay rent", dueDate: date(2026, 5, 1), isCompleted: true)
        let staleRentEvent = DateCard(title: "Pay Rent", startAt: date(2026, 5, 1))

        let brief = AgendaBriefingService.build(
            todos: [paidRent],
            dateCards: [staleRentEvent],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(brief.items.count, 1)
        XCTAssertEqual(brief.items[0].status, .suppressed)
        XCTAssertFalse(brief.items[0].surfaceToday)
        XCTAssertEqual(brief.items[0].reason, "suppressed by completed same-cycle todo")
    }

    func testNextMonthlyRentStaysQuietUntilLeadWindow() {
        let now = date(2026, 5, 7)
        let rent = DateCard(
            title: "Rent",
            startAt: date(2026, 6, 1),
            recurrenceRule: DateCardRecurrenceRule(frequency: .monthly)
        )

        let brief = AgendaBriefingService.build(todos: [], dateCards: [rent], now: now, calendar: calendar)

        XCTAssertEqual(brief.items[0].status, .later)
        XCTAssertFalse(brief.items[0].surfaceToday)
        XCTAssertEqual(brief.items[0].reason, "outside reminder window")
    }

    func testBirthdayOutsideLeadWindowIsNotSurfaced() {
        let now = date(2026, 5, 7)
        let birthday = DateCard(
            title: "Alex birthday",
            startAt: date(2026, 7, 1),
            recurrenceRule: DateCardRecurrenceRule(frequency: .yearly)
        )

        let brief = AgendaBriefingService.build(todos: [], dateCards: [birthday], now: now, calendar: calendar)

        XCTAssertEqual(brief.items[0].status, .later)
        XCTAssertFalse(brief.items[0].surfaceToday)
    }

    func testBirthdayWithinLeadWindowIsSurfaced() {
        let now = date(2026, 5, 7)
        let birthday = DateCard(
            title: "Alex birthday",
            startAt: date(2026, 5, 14),
            recurrenceRule: DateCardRecurrenceRule(frequency: .yearly)
        )

        let brief = AgendaBriefingService.build(todos: [], dateCards: [birthday], now: now, calendar: calendar)

        XCTAssertEqual(brief.items[0].status, .upcoming)
        XCTAssertTrue(brief.items[0].surfaceToday)
        XCTAssertEqual(brief.items[0].reason, "upcoming in 7 days")
    }

    func testTodoActionURLAndReasonAreIncluded() {
        let now = date(2026, 5, 7)
        let todo = TodoCard(
            title: "Pay rent",
            dueDate: date(2026, 5, 7),
            priority: .high,
            actionURLString: "rent.example.com"
        )

        let brief = AgendaBriefingService.build(todos: [todo], dateCards: [], now: now, calendar: calendar)

        XCTAssertEqual(brief.items[0].itemType, .todo)
        XCTAssertEqual(brief.items[0].status, .today)
        XCTAssertEqual(brief.items[0].reason, "due today")
        XCTAssertEqual(brief.items[0].priority, "high")
        XCTAssertEqual(brief.items[0].actionURLString, "rent.example.com")
        XCTAssertEqual(brief.items[0].reminderPolicy, "todo lead window: 7 days")
        XCTAssertEqual(brief.items[0].suggestedAction, "open action URL")
    }

    func testDateCardReminderPolicyIsIncluded() {
        let now = date(2026, 5, 7)
        let birthday = DateCard(
            title: "Alex birthday",
            startAt: date(2026, 5, 14),
            recurrenceRule: DateCardRecurrenceRule(frequency: .yearly),
            actionURLString: "messages://alex"
        )

        let brief = AgendaBriefingService.build(todos: [], dateCards: [birthday], now: now, calendar: calendar)

        XCTAssertEqual(brief.items[0].reminderPolicy, "birthday lead window: 14 days")
        XCTAssertEqual(brief.items[0].suggestedAction, "open action URL")
        XCTAssertEqual(brief.items[0].nextSurfaceDate, now)
    }
}

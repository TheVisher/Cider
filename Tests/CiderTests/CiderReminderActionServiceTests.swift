import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Reminder Action Service Tests")
@MainActor
struct CiderReminderActionServiceTests {
    @Test("snoozing a todo persists quiet surfacing until the requested date")
    func snoozeTodoPersistsQuietSurfacing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 7, hour: 9))!
        let snoozedUntil = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 8, hour: 9))!
        var storedTodo = TodoCard(title: "Pay rent", dueDate: now)

        let service = CiderReminderActionService(
            todoProvider: { [storedTodo] },
            dateCardProvider: { [] },
            updateTodo: { updated in storedTodo = updated; return true },
            updateDateCard: { _ in false },
            nowProvider: { now },
            calendar: calendar
        )

        let result = try service.snooze(.todo, id: storedTodo.id, until: snoozedUntil)

        #expect(storedTodo.snoozedUntil == snoozedUntil)
        #expect(storedTodo.isCompleted == false)
        #expect(result.itemType == .todo)
        #expect(result.action == .snooze)
        #expect(result.surfacing?.surfaceToday == false)
        #expect(result.surfacing?.surfacing.reason == "snoozed until 2026-05-08")
    }

    @Test("completing a date card clears snooze state and keeps it out of relevance")
    func completeDateCardClearsSnoozeState() throws {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        var storedDateCard = DateCard(
            title: "DMV appointment",
            startAt: now,
            snoozedUntil: now.addingTimeInterval(86_400)
        )

        let service = CiderReminderActionService(
            todoProvider: { [] },
            dateCardProvider: { [storedDateCard] },
            updateTodo: { _ in false },
            updateDateCard: { updated in storedDateCard = updated; return true },
            nowProvider: { now }
        )

        let result = try service.complete(.dateCard, id: storedDateCard.id)

        #expect(storedDateCard.isCompleted == true)
        #expect(storedDateCard.completedAt == now)
        #expect(storedDateCard.snoozedUntil == nil)
        #expect(result.itemType == .dateCard)
        #expect(result.action == .complete)
        #expect(result.surfacing == nil)
    }

    @Test("reminder action JSON exposes snooze result and surfacing state")
    func reminderActionJSONExposesSnoozeResult() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 7, hour: 9))!
        let snoozedUntil = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 8, hour: 9))!
        var storedTodo = TodoCard(title: "Send invoice", dueDate: now)

        let service = CiderReminderActionService(
            todoProvider: { [storedTodo] },
            dateCardProvider: { [] },
            updateTodo: { updated in storedTodo = updated; return true },
            updateDateCard: { _ in false },
            nowProvider: { now },
            calendar: calendar
        )

        let dict = reminderActionResultToDict(try service.snooze(.todo, id: storedTodo.id, until: snoozedUntil))

        #expect(dict["itemType"] as? String == "todo")
        #expect(dict["action"] as? String == "snooze")
        #expect(dict["snoozedUntil"] as? String == "2026-05-08T09:00:00Z")
        let surfacing = try #require(dict["surfacing"] as? [String: Any])
        #expect(surfacing["surfaceToday"] as? Bool == false)
        let explanation = try #require(surfacing["explanation"] as? [String: Any])
        #expect(explanation["reason"] as? String == "snoozed until 2026-05-08")
    }
}

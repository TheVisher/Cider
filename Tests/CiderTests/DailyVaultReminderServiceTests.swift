import Foundation
import Testing
@testable import Cider

struct DailyVaultReminderServiceTests {
    @Test("daily vault reminder formats the dashboard daily brief")
    func buildsCombinedReminder() {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 13
        components.hour = 10
        components.minute = 0
        components.timeZone = .current
        let now = Calendar.current.date(from: components)!
        let oldBookmark = Bookmark(
            title: "Old bookmark",
            urlString: "https://example.com/old",
            createdAt: now.addingTimeInterval(-90 * 24 * 3600),
            updatedAt: now.addingTimeInterval(-70 * 24 * 3600)
        )
        let oldNote = Note(
            title: "Old note",
            createdAt: now.addingTimeInterval(-80 * 24 * 3600),
            modifiedAt: now.addingTimeInterval(-60 * 24 * 3600)
        )
        let todo = TodoCard(
            title: "Pay rent",
            dueDate: now.addingTimeInterval(3 * 3600)
        )
        let event = DateCard(
            title: "Dentist",
            startAt: now.addingTimeInterval(5 * 3600)
        )

        let reminder = DailyVaultReminderService.buildReminder(
            now: now,
            dateCards: [event],
            todos: [todo],
            bookmarks: [oldBookmark],
            notes: [oldNote],
            resurfacedAt: [:]
        )

        let message = reminder?.message ?? ""

        #expect(reminder != nil)
        #expect(message.contains("Here's your Cider brief"))
        #expect(message.contains("Focus"))
        #expect(message.contains("Action Items"))
        #expect(message.contains("Today + Upcoming"))
        #expect(message.contains("Recent Activity"))
        #expect(message.contains("Quiet Threads"))
        #expect(message.contains("Pay rent"))
        #expect(message.contains("Dentist"))
        #expect(message.contains("Old bookmark"))
        #expect(message.contains("Old note"))
        #expect(reminder?.resurfacedItemKeys.count == 2)
    }

    @Test("resurfacing respects age threshold and cooldown history")
    func respectsResurfacingCooldown() {
        let now = Date(timeIntervalSince1970: 1_776_100_000)
        let eligibleBookmark = Bookmark(
            title: "Eligible",
            urlString: "https://example.com/eligible",
            createdAt: now.addingTimeInterval(-120 * 24 * 3600),
            updatedAt: now.addingTimeInterval(-45 * 24 * 3600)
        )
        let cooledDownNote = Note(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Recently surfaced",
            createdAt: now.addingTimeInterval(-120 * 24 * 3600),
            modifiedAt: now.addingTimeInterval(-90 * 24 * 3600)
        )
        let tooRecentBookmark = Bookmark(
            title: "Too recent",
            urlString: "https://example.com/recent",
            createdAt: now.addingTimeInterval(-20 * 24 * 3600),
            updatedAt: now.addingTimeInterval(-10 * 24 * 3600)
        )

        let reminder = DailyVaultReminderService.buildReminder(
            now: now,
            dateCards: [],
            todos: [],
            bookmarks: [eligibleBookmark, tooRecentBookmark],
            notes: [cooledDownNote],
            resurfacedAt: [
                "note:\(cooledDownNote.id.uuidString)": now.addingTimeInterval(-3 * 24 * 3600)
            ]
        )

        #expect(reminder != nil)
        #expect(reminder?.resurfacedItemKeys == ["bookmark:\(eligibleBookmark.id.uuidString)"])
        #expect(reminder?.message.contains("Eligible") == true)
        #expect(reminder?.message.contains("Quiet Threads") == true)
    }
}

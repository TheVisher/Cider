import Foundation
import Testing
@testable import Cider

@MainActor
struct ReminderReconcilerTests {
    @Test("daily digest scheduler wakes at configured hour on weekdays")
    func dailyDigestSchedulesSameWeekdayMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 17,
            hour: 4,
            minute: 30
        ))!

        let config = TelegramBridgeConfiguration(
            isEnabled: true,
            botToken: "token",
            allowedChatIDs: [12345],
            allowFirstChatToPair: false,
            sendReminders: false,
            sendDailyDigest: true,
            sendWeeklyDigest: false,
            dailyDigestHour: 6,
            dailyDigestWeekdaysOnly: true,
            dailyDigestResurfaceCount: 3,
            dailyDigestResurfaceMinAgeDays: 30,
            dailyDigestResurfaceCooldownDays: 14,
            pollingTimeoutSeconds: 30
        )

        let fireDate = ReminderReconciler.nextTelegramDigestFireDate(
            after: now,
            configuration: config,
            calendar: calendar
        )

        let expected = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 17,
            hour: 6,
            minute: 0
        ))

        #expect(fireDate == expected)
    }

    @Test("daily digest scheduler skips weekends for weekday-only delivery")
    func dailyDigestSkipsWeekend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 17,
            hour: 11,
            minute: 43
        ))!

        let config = TelegramBridgeConfiguration(
            isEnabled: true,
            botToken: "token",
            allowedChatIDs: [12345],
            allowFirstChatToPair: false,
            sendReminders: false,
            sendDailyDigest: true,
            sendWeeklyDigest: false,
            dailyDigestHour: 6,
            dailyDigestWeekdaysOnly: true,
            dailyDigestResurfaceCount: 3,
            dailyDigestResurfaceMinAgeDays: 30,
            dailyDigestResurfaceCooldownDays: 14,
            pollingTimeoutSeconds: 30
        )

        let fireDate = ReminderReconciler.nextTelegramDigestFireDate(
            after: now,
            configuration: config,
            calendar: calendar
        )

        let expected = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 20,
            hour: 6,
            minute: 0
        ))

        #expect(fireDate == expected)
    }
}

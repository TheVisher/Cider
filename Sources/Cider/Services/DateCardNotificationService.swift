import Foundation
import UserNotifications
import os

@MainActor
final class DateCardNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = DateCardNotificationService()

    private static let categoryIdentifier = "datecard-reminder"
    private static let openActionID = "OPEN_DATE_CARD"
    private static let completeActionID = "MARK_COMPLETE"
    private let logger = Logger(subsystem: "com.cider.app", category: "DateCardNotificationService")

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        configureCategories()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is running (accessory apps need this)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let idString = userInfo["dateCardID"] as? String,
              let dateCardID = UUID(uuidString: idString) else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case Self.completeActionID:
            Task { @MainActor in
                DateCardStorage.shared.markCompleted(dateCardID, completed: true)
            }
        default:
            // Open action or default tap — post notification to open the date card
            Task { @MainActor in
                if let dateCard = DateCardStorage.shared.dateCard(for: dateCardID) {
                    NotificationCenter.default.post(
                        name: .openDateCardFromNotification,
                        object: nil,
                        userInfo: ["dateCard": dateCard]
                    )
                }
            }
        }

        completionHandler()
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Notification permission request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Categories

    private func configureCategories() {
        let openAction = UNNotificationAction(
            identifier: Self.openActionID,
            title: "Open",
            options: [.foreground]
        )
        let completeAction = UNNotificationAction(
            identifier: Self.completeActionID,
            title: "Mark Complete",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [openAction, completeAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Scheduling

    func scheduleNotifications(for dateCards: [DateCard]) {
        let center = UNUserNotificationCenter.current()
        // Remove all existing date card notifications, then reschedule
        center.removeAllPendingNotificationRequests()

        let config = CiderConfig.load()
        guard config.enableDateCardNotifications else {
            logger.info("Notifications disabled in config, cleared all pending")
            return
        }

        var scheduledCount = 0
        var skippedPast = 0

        for dateCard in dateCards {
            guard !dateCard.isCompleted else { continue }

            // Use per-card rule if present, otherwise config default
            let minutesBefore: Int
            if let rule = dateCard.rules.first(where: { $0.type == .remindBeforeMinutes && $0.isEnabled }),
               let value = rule.integerValue {
                minutesBefore = value
            } else {
                minutesBefore = config.dateCardDefaultNotificationMinutes
            }

            let target = dateCard.effectiveDate()
            let fireDate = Calendar.current.date(byAdding: .minute, value: -minutesBefore, to: target) ?? target

            // Don't schedule notifications for dates already past
            guard fireDate > Date() else {
                skippedPast += 1
                logger.info("Skipped \(dateCard.title): fire date \(fireDate) already past")
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = dateCard.title
            content.body = notificationBody(for: dateCard, minutesBefore: minutesBefore)
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["dateCardID": dateCard.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "datecard-\(dateCard.id.uuidString)",
                content: content,
                trigger: trigger
            )

            center.add(request) { [logger] error in
                if let error {
                    logger.error("Failed to schedule notification for \(dateCard.title): \(error.localizedDescription)")
                }
            }
            scheduledCount += 1
            logger.info("Scheduled \(dateCard.title) for \(fireDate) (\(minutesBefore)min before)")
        }

        logger.info("Scheduled \(scheduledCount) notifications, skipped \(skippedPast) past")
    }

    func cancelNotification(for dateCardID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["datecard-\(dateCardID.uuidString)"]
        )
    }

    func rescheduleAll() {
        let dateCards = DateCardStorage.shared.dateCards
        scheduleNotifications(for: dateCards)
    }

    // MARK: - Helpers

    private func notificationBody(for dateCard: DateCard, minutesBefore: Int) -> String {
        let target = dateCard.effectiveDate()
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: target)).day ?? 0

        if days < 0 { return "Overdue" }
        if days == 0 { return "Due today" }
        if minutesBefore < 60 { return "Starting in \(minutesBefore) minutes" }
        if minutesBefore == 60 { return "Starting in 1 hour" }
        if minutesBefore < 1440 { return "Starting in \(minutesBefore / 60) hours" }
        return "Due in \(days) day\(days == 1 ? "" : "s")"
    }
}

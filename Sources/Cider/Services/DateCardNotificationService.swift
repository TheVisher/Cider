import Foundation
import UserNotifications
import os

@MainActor
final class DateCardNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = DateCardNotificationService()

    private static let categoryIdentifier = "datecard-reminder"
    private static let recurringCategoryIdentifier = "datecard-reminder-recurring"
    private static let openActionID = "OPEN_DATE_CARD"
    private static let completeActionID = "MARK_COMPLETE"
    /// Prefix for all datecard notification identifiers.
    private static let identifierPrefix = "datecard-"

    private let logger = Logger(subsystem: "com.cider.app", category: "DateCardNotificationService")

    /// Scheduling horizon — only schedule notifications within this many days.
    private static let horizonDays = 7

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
            // Only mark complete for non-recurring cards (recurring cards use a
            // category that does not include this action, but guard defensively).
            Task { @MainActor in
                if let card = DateCardStorage.shared.dateCard(for: dateCardID),
                   card.recurrenceRule == nil {
                    DateCardStorage.shared.markCompleted(dateCardID, completed: true)
                }
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

        // Non-recurring cards: Open + Mark Complete
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [openAction, completeAction],
            intentIdentifiers: []
        )

        // Recurring cards: Open only (completing a single occurrence shouldn't kill the series)
        let recurringCategory = UNNotificationCategory(
            identifier: Self.recurringCategoryIdentifier,
            actions: [openAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category, recurringCategory])
    }

    // MARK: - Scheduling

    func scheduleNotifications(for dateCards: [DateCard]) {
        let config = CiderConfig.load()
        guard config.enableDateCardNotifications else {
            // Remove only datecard notifications, leave others intact
            Task {
                let allIDs = await pendingNotificationIdentifiers()
                let datecardIDs = allIDs.filter { $0.hasPrefix(Self.identifierPrefix) }
                if !datecardIDs.isEmpty {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(datecardIDs))
                }
            }
            logger.info("Notifications disabled in config, cleared datecard-only pending")
            return
        }

        Task {
            await reconcileNotifications(for: dateCards, config: config)
        }
    }

    /// Reconcile desired notification state against currently pending requests.
    /// Adds missing notifications, removes stale ones, leaves non-datecard notifications untouched.
    private func reconcileNotifications(for dateCards: [DateCard], config: CiderConfig) async {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let calendar = Calendar.current
        guard let horizon = calendar.date(byAdding: .day, value: Self.horizonDays, to: now) else { return }

        // 1. Build the desired set of notification requests
        var desiredRequests: [String: UNNotificationRequest] = [:]

        for dateCard in dateCards {
            // Skip completed non-recurring cards. Recurring cards ignore isCompleted.
            if dateCard.isCompleted, dateCard.recurrenceRule == nil { continue }

            let isRecurring = dateCard.recurrenceRule != nil

            // Gather reminder offsets from rules
            let reminderRules = dateCard.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
            let offsets: [Int] = reminderRules.isEmpty
                ? [config.dateCardDefaultNotificationMinutes]
                : reminderRules.compactMap(\.integerValue)

            // Compute occurrences within the horizon
            let occurrences = self.occurrences(for: dateCard, from: now, to: horizon)

            for occurrence in occurrences {
                for minutesBefore in offsets {
                    let fireDate = occurrence.addingTimeInterval(-Double(minutesBefore) * 60)
                    guard fireDate > now else { continue }

                    let identifier = Self.notificationIdentifier(
                        cardID: dateCard.id,
                        occurrence: occurrence,
                        minutesBefore: minutesBefore
                    )

                    let content = UNMutableNotificationContent()
                    content.title = dateCard.title
                    content.body = notificationBody(for: dateCard, targetDate: occurrence, minutesBefore: minutesBefore)
                    content.sound = .default
                    content.categoryIdentifier = isRecurring
                        ? Self.recurringCategoryIdentifier
                        : Self.categoryIdentifier
                    content.userInfo = ["dateCardID": dateCard.id.uuidString]

                    let components = calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    desiredRequests[identifier] = request
                }
            }
        }

        // 2. Get currently pending datecard notifications
        let allPendingIDs = await pendingNotificationIdentifiers()
        let existingDatecardIDs = allPendingIDs.filter { $0.hasPrefix(Self.identifierPrefix) }
        let desiredIDs = Set(desiredRequests.keys)

        // 3. Remove stale notifications (no longer desired)
        let staleIDs = existingDatecardIDs.subtracting(desiredIDs)
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(staleIDs))
            logger.debug("Removed \(staleIDs.count) stale notifications")
        }

        // 4. Add new notifications (not already pending)
        let newIDs = desiredIDs.subtracting(existingDatecardIDs)
        var addedCount = 0
        for id in newIDs {
            guard let request = desiredRequests[id] else { continue }
            do {
                try await center.add(request)
                addedCount += 1
            } catch {
                logger.error("Failed to schedule notification \(id): \(error.localizedDescription)")
            }
        }

        let unchangedCount = desiredIDs.intersection(existingDatecardIDs).count
        logger.info("Notifications reconciled: \(addedCount) added, \(staleIDs.count) removed, \(unchangedCount) unchanged")
    }

    func cancelNotification(for dateCardID: UUID) {
        Task {
            let allIDs = await pendingNotificationIdentifiers()
            let prefix = "\(Self.identifierPrefix)\(dateCardID.uuidString)-"
            let matching = allIDs.filter { $0.hasPrefix(prefix) }
            if !matching.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(matching))
            }
        }
    }

    func rescheduleAll() {
        let dateCards = DateCardStorage.shared.dateCards
        scheduleNotifications(for: dateCards)
    }

    // MARK: - Helpers

    /// Compute all occurrences of a date card within [from, to].
    private func occurrences(for dateCard: DateCard, from: Date, to: Date) -> [Date] {
        var results: [Date] = []

        if dateCard.recurrenceRule != nil {
            // Recurring: collect occurrences within the window
            var cursor = dateCard.effectiveDate(now: from)
            while cursor <= to {
                results.append(cursor)
                guard let next = dateCard.nextOccurrence(after: cursor) else { break }
                cursor = next
            }
        } else {
            // Non-recurring: single occurrence if within the window
            let target = dateCard.startAt
            if target <= to {
                results.append(target)
            }
        }

        return results
    }

    /// Deterministic notification identifier: "datecard-{cardID}-{compactISO}-{minutes}"
    static func notificationIdentifier(cardID: UUID, occurrence: Date, minutesBefore: Int) -> String {
        let compact = compactISO(occurrence)
        return "\(identifierPrefix)\(cardID.uuidString)-\(compact)-\(minutesBefore)"
    }

    /// Compact ISO format without colons: "20260501T090000"
    private static func compactISO(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Async wrapper for UNUserNotificationCenter.getPendingNotificationRequests
    /// (the system API uses a completion handler, not async/await).
    /// Returns identifiers of all currently pending notification requests.
    /// Uses completion-handler API wrapped in continuation because
    /// UNNotificationRequest is not Sendable in strict concurrency mode.
    private func pendingNotificationIdentifiers() async -> Set<String> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Set<String>, Never>) in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let ids = Set(requests.map(\.identifier))
                continuation.resume(returning: ids)
            }
        }
    }

    private func notificationBody(for dateCard: DateCard, targetDate: Date, minutesBefore: Int) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: targetDate)
        ).day ?? 0

        if days < 0 { return "Overdue" }
        if days == 0 {
            if minutesBefore == 0 { return "Due now" }
            if minutesBefore < 60 { return "Starting in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")" }
            if minutesBefore == 60 { return "Starting in 1 hour" }
            if minutesBefore < 1440 { return "Starting in \(minutesBefore / 60) hours" }
            return "Due today"
        }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }
}

import AppKit
import Foundation
import os

/// Periodically ensures notification and outbox state matches the current vault.
/// Runs on app launch, wake-from-sleep, time zone change, day rollover, and vault changes.
@MainActor
final class ReminderReconciler {
    static let shared = ReminderReconciler()
    private nonisolated static let logger = Logger(subsystem: "com.cider.app", category: "ReminderReconciler")

    private var dayRolloverTimer: Timer?
    private var nextDueTimer: Timer?
    private var lastReconcileDate: Date?
    private var wakeObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var timeZoneObserver: NSObjectProtocol?

    /// Call on app launch, wake-from-sleep, time zone change, vault changes, and day rollover.
    func reconcile() {
        let now = Date()
        Self.logger.debug("Reconciling reminders")

        // 1. Reschedule local notifications
        DateCardNotificationService.shared.rescheduleAll()

        // 2. Check outbox for agent-delivered reminders
        ReminderOutbox.shared.processReminders()
        Task {
            await TelegramBridge.shared.processReminders()
        }
        Task {
            await AgentMemoryReviewService.shared.processScheduledReview(now: now)
        }

        lastReconcileDate = now
        scheduleNextDueTimer(from: now)
    }

    /// Start periodic reconciliation.
    func start() {
        // Day rollover: schedule a timer for midnight + 1 minute
        scheduleDayRolloverTimer()

        // Machine wake (covers lid-open, power-on)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.logger.debug("Machine wake — reconciling")
            Task { @MainActor in
                ReminderReconciler.shared.reconcile()
            }
        }

        // Screen wake (user returns to Mac)
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.logger.debug("Screen wake — reconciling")
            Task { @MainActor in
                ReminderReconciler.shared.reconcile()
            }
        }

        // Time zone change (travel, manual clock change)
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Self.logger.debug("Time zone changed — reconciling")
            Task { @MainActor in
                ReminderReconciler.shared.reconcile()
            }
        }

        // Initial reconcile
        reconcile()
    }

    func stop() {
        dayRolloverTimer?.invalidate()
        dayRolloverTimer = nil
        nextDueTimer?.invalidate()
        nextDueTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenWakeObserver)
        }
        if let timeZoneObserver {
            NotificationCenter.default.removeObserver(timeZoneObserver)
        }
        wakeObserver = nil
        screenWakeObserver = nil
        timeZoneObserver = nil
    }

    private func scheduleDayRolloverTimer() {
        dayRolloverTimer?.invalidate()

        // Fire 1 minute after midnight to advance the notification horizon
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let fireDate = tomorrow.addingTimeInterval(60)
        let interval = fireDate.timeIntervalSince(now)

        dayRolloverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Self.logger.debug("Day rollover — reconciling")
            Task { @MainActor in
                ReminderReconciler.shared.reconcile()
                ReminderReconciler.shared.scheduleDayRolloverTimer()
            }
        }

        Self.logger.debug("Day rollover timer scheduled")
    }

    private func scheduleNextDueTimer(from now: Date) {
        nextDueTimer?.invalidate()
        nextDueTimer = nil

        guard let nextFireDate = nextReminderFireDate(after: now) else {
            Self.logger.debug("No upcoming agent reminder due times found")
            return
        }

        let interval = max(1, nextFireDate.timeIntervalSince(now))
        nextDueTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                ReminderReconciler.shared.reconcile()
            }
        }

        Self.logger.debug("Next reminder timer scheduled for \(nextFireDate.formatted(), privacy: .public)")
    }

    private func nextReminderFireDate(after now: Date) -> Date? {
        let dateCards = DateCardStorage.shared.dateCards
        let todos = TodoCardStorage.shared.todoCards
        let config = CiderConfig.load()
        let telegramRemindersEnabled = telegramReminderSchedulingEnabled()
        let agentRemindersEnabled = config.enableAgentReminders
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 14, to: now) ?? now.addingTimeInterval(14 * 24 * 60 * 60)

        var earliest: Date?

        for card in dateCards {
            if card.isCompleted, card.recurrenceRule == nil { continue }

            let reminderRules = card.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
            let offsets: [Int]
            if reminderRules.isEmpty {
                offsets = (agentRemindersEnabled || telegramRemindersEnabled)
                    ? [config.dateCardDefaultNotificationMinutes]
                    : []
            } else {
                offsets = reminderRules.compactMap(\.integerValue)
            }
            guard !offsets.isEmpty else { continue }

            if card.recurrenceRule != nil {
                var cursor = card.effectiveDate(now: now)
                while cursor <= horizon {
                    for minutesBefore in offsets {
                        let fireDate = cursor.addingTimeInterval(-Double(minutesBefore) * 60)
                        if fireDate > now {
                            earliest = minOptional(earliest, fireDate)
                        }
                    }
                    guard let next = card.nextOccurrence(after: cursor) else { break }
                    cursor = next
                }
            } else {
                for minutesBefore in offsets {
                    let fireDate = card.startAt.addingTimeInterval(-Double(minutesBefore) * 60)
                    if fireDate > now {
                        earliest = minOptional(earliest, fireDate)
                    }
                }
            }
        }

        if agentRemindersEnabled || telegramRemindersEnabled {
            for todo in todos where !todo.isCompleted {
                guard let dueDate = todo.dueDate, todoHasExplicitTime(dueDate), dueDate > now else { continue }
                let reminderRules = todo.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
                let offsets = reminderRules.isEmpty ? [0] : reminderRules.compactMap { $0.integerValue ?? 0 }
                for minutesBefore in offsets {
                    let fireDate = dueDate.addingTimeInterval(-Double(minutesBefore) * 60)
                    if fireDate > now {
                        earliest = minOptional(earliest, fireDate)
                    }
                }
            }
        }

        return earliest
    }

    private func telegramReminderSchedulingEnabled() -> Bool {
        let configURL = StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("telegram")
            .appendingPathComponent("config.json")

        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(TelegramBridgeConfiguration.self, from: data)
        else {
            return false
        }

        return config.isEnabled && config.sendReminders && !config.allowedChatIDs.isEmpty
    }

    private func minOptional(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    private func todoHasExplicitTime(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }
}

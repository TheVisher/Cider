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

        lastReconcileDate = now
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
}

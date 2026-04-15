import Foundation
import os

/// Writes reminder outbox files for agent-delivered iMessage notifications.
/// Cider writes, the agent reads and sends. Filesystem as message bus.
@MainActor
final class ReminderOutbox {
    static let shared = ReminderOutbox()
    private static let logger = Logger(subsystem: "com.cider.app", category: "ReminderOutbox")

    /// Ledger file tracking all delivered reminder IDs to prevent duplicates.
    private var deliveredLedgerURL: URL {
        outboxDirectory.appendingPathComponent(".delivered")
    }

    private var outboxDirectory: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("outbox")
    }

    /// Check which reminders are due and write outbox files for agent delivery.
    func processReminders() {
        let dateCards = DateCardStorage.shared.dateCards
        let todos = TodoCardStorage.shared.todoCards
        let now = Date()
        let config = CiderConfig.load()

        guard config.enableAgentReminders else { return }

        for card in dateCards {
            processCard(card, now: now)
        }

        for todo in todos {
            processTodo(todo, now: now)
        }
    }

    private func processCard(_ card: DateCard, now: Date) {
        // Skip completed non-recurring cards. Recurring cards ignore isCompleted.
        if card.isCompleted, card.recurrenceRule == nil { return }

        let reminderRules = card.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
        guard !reminderRules.isEmpty else { return }

        // Compute occurrences in the next 24 hours
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var cursor = card.effectiveDate(now: now)

        while cursor <= horizon {
            for rule in reminderRules {
                let minutesBefore = rule.integerValue ?? 15
                let fireDate = cursor.addingTimeInterval(-Double(minutesBefore) * 60)

                // Fire if the reminder time is within the last 5 minutes (catch window)
                // and hasn't been delivered yet
                if fireDate <= now, fireDate > now.addingTimeInterval(-5 * 60) {
                    let fileID = outboxFileID(cardID: card.id, occurrence: cursor, offset: minutesBefore)
                    if !isDelivered(fileID) {
                        writeOutboxFile(card: card, occurrence: cursor, minutesBefore: minutesBefore, fileID: fileID)
                        markDelivered(fileID)
                    }
                }
            }

            guard let next = card.nextOccurrence(after: cursor) else { break }
            cursor = next
        }
    }

    private func processTodo(_ todo: TodoCard, now: Date) {
        guard !todo.isCompleted, let dueDate = todo.dueDate, todoHasExplicitTime(dueDate) else { return }

        if dueDate <= now, dueDate > now.addingTimeInterval(-5 * 60) {
            let fileID = todoOutboxFileID(todoID: todo.id, dueDate: dueDate)
            if !isDelivered(fileID) {
                writeTodoOutboxFile(todo: todo, dueDate: dueDate, fileID: fileID)
                markDelivered(fileID)
            }
        }
    }

    // MARK: - File ID

    private func outboxFileID(cardID: UUID, occurrence: Date, offset: Int) -> String {
        let formatter = ISO8601DateFormatter()
        let iso = formatter.string(from: occurrence)
        return "\(cardID.uuidString)-\(iso)-\(offset)min"
    }

    private func todoOutboxFileID(todoID: UUID, dueDate: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: dueDate)
        return "todo-\(todoID.uuidString)-\(iso)-0min"
    }

    // MARK: - Delivery Dedup (3 sources: ledger, outbox/, outbox/sent/)

    private func isDelivered(_ fileID: String) -> Bool {
        // Check 1: ledger file
        if ledgerContains(fileID) { return true }

        // Check 2: file still in outbox/ (agent hasn't picked it up yet)
        let outboxURL = outboxDirectory.appendingPathComponent("\(fileID).md")
        if FileManager.default.fileExists(atPath: outboxURL.path) { return true }

        // Check 3: file in sent/ (agent already delivered it)
        let sentURL = outboxDirectory
            .appendingPathComponent("sent")
            .appendingPathComponent("\(fileID).md")
        if FileManager.default.fileExists(atPath: sentURL.path) { return true }

        return false
    }

    private func ledgerContains(_ fileID: String) -> Bool {
        guard let data = try? String(contentsOf: deliveredLedgerURL, encoding: .utf8) else { return false }
        return data.contains(fileID)
    }

    private func markDelivered(_ fileID: String) {
        try? FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)

        let entry = "\(fileID)\n"
        if let handle = try? FileHandle(forWritingTo: deliveredLedgerURL) {
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? entry.write(to: deliveredLedgerURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Write Outbox File

    private func writeOutboxFile(card: DateCard, occurrence: Date, minutesBefore: Int, fileID: String) {
        try? FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short

        let timeDescription: String
        if minutesBefore == 0 {
            timeDescription = "now"
        } else if minutesBefore < 60 {
            timeDescription = "in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")"
        } else if minutesBefore < 1440 {
            let hours = minutesBefore / 60
            timeDescription = "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = minutesBefore / 1440
            timeDescription = "in \(days) day\(days == 1 ? "" : "s")"
        }

        let isRecurring = card.recurrenceRule != nil
        let recurringNote = isRecurring ? "\nThis is a recurring reminder (\(card.recurrenceRule!.frequency.rawValue))." : ""

        var body = "Reminder: \(card.title) is \(timeDescription).\nDate: \(formatter.string(from: occurrence))"
        if !card.location.isEmpty { body += "\nLocation: \(card.location)" }
        if !card.details.isEmpty { body += "\nDetails: \(card.details)" }
        body += recurringNote

        let content = """
        ---
        type: reminder
        cardID: \(card.id.uuidString)
        title: \(card.title)
        occurrence: \(ISO8601DateFormatter().string(from: occurrence))
        minutesBefore: \(minutesBefore)
        recurring: \(isRecurring)
        createdAt: \(ISO8601DateFormatter().string(from: Date()))
        ---

        \(body)
        """

        let url = outboxDirectory.appendingPathComponent("\(fileID).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        Self.logger.info("Wrote outbox reminder: \(fileID)")
    }

    private func writeTodoOutboxFile(todo: TodoCard, dueDate: Date, fileID: String) {
        try? FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short

        var body = "Reminder: \(todo.title) is now.\nDate: \(formatter.string(from: dueDate))"
        if !todo.details.isEmpty { body += "\nDetails: \(todo.details)" }

        let content = """
        ---
        type: reminder
        todoID: \(todo.id.uuidString)
        title: \(todo.title)
        occurrence: \(ISO8601DateFormatter().string(from: dueDate))
        minutesBefore: 0
        recurring: false
        createdAt: \(ISO8601DateFormatter().string(from: Date()))
        ---

        \(body)
        """

        let url = outboxDirectory.appendingPathComponent("\(fileID).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        Self.logger.info("Wrote outbox todo reminder: \(fileID)")
    }

    private func todoHasExplicitTime(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }
}

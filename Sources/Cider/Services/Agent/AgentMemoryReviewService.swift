import Foundation
import os

actor AgentMemoryReviewService {
    static let shared = AgentMemoryReviewService()

    private let logger = Logger(subsystem: "com.cider.app", category: "AgentMemoryReviewService")
    private let handoffStorage = AgentThreadHandoffStorage()
    private let calendar = Calendar.autoupdatingCurrent

    func processScheduledReview(now: Date = Date()) {
        guard shouldGenerateReview(now: now) else { return }

        let weekKey = Self.weekKey(for: now, calendar: calendar)
        let weekURL = reviewsDirectory.appendingPathComponent("\(weekKey).md")
        guard !FileManager.default.fileExists(atPath: weekURL.path) else { return }

        let reviewWindowStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let handoffs = handoffStorage.recentHandoffs(since: reviewWindowStart)
        let observations = loadDailyObservations(since: reviewWindowStart)
        let userMemorySnapshot = loadUserMemoryBullets(limit: 18)
        let openLoops = extractOpenLoops(from: handoffs)

        let review = buildWeeklyReview(
            weekKey: weekKey,
            now: now,
            handoffs: handoffs,
            observations: observations,
            userMemorySnapshot: userMemorySnapshot,
            openLoops: openLoops
        )

        do {
            try FileManager.default.createDirectory(at: reviewsDirectory, withIntermediateDirectories: true)
            try review.write(to: weekURL, atomically: true, encoding: .utf8)
            writeOpenLoopsFile(openLoops: openLoops, now: now)
            logger.info("Generated weekly memory review \(weekKey, privacy: .public)")
        } catch {
            logger.error("Failed to generate weekly memory review \(weekKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldGenerateReview(now: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)

        // Wait until Monday 9am local, then allow first review generation for the week
        // on any later reconcile if the app was offline earlier.
        if weekday == 2 {
            return hour >= 9
        }
        return weekday > 2
    }

    private func buildWeeklyReview(
        weekKey: String,
        now: Date,
        handoffs: [AgentThreadHandoff],
        observations: [MemoryObservation],
        userMemorySnapshot: [String],
        openLoops: [String]
    ) -> String {
        let recentAsks = Array(
            LinkedHashSet(
                handoffs.compactMap { handoff in
                    handoff.recentTurns.last(where: { $0.role == .user })?.content
                }
            ).prefix(8)
        )

        let groupedObservations = Dictionary(grouping: observations, by: \.reason)
        let focusItems = Array(
            LinkedHashSet(
                observations
                    .filter { ["project", "preference", "relationship", "routine", "explicit remember"].contains($0.reason) }
                    .map(\.text)
                    + recentAsks
            ).prefix(10)
        )

        var lines: [String] = []
        lines.append("---")
        lines.append("type: weekly-memory-review")
        lines.append("week: '\(weekKey)'")
        lines.append("generated: '\(Self.isoTimestamp(now))'")
        lines.append("---")
        lines.append("")
        lines.append("# Weekly Memory Review")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("- Conversation handoffs reviewed: \(handoffs.count)")
        lines.append("- Durable-memory observations reviewed: \(observations.count)")
        lines.append("- Open loops detected: \(openLoops.count)")
        lines.append("- User memory bullets currently tracked: \(userMemorySnapshot.count)")
        lines.append("")

        if !focusItems.isEmpty {
            lines.append("## Current Focus Signals")
            lines.append("")
            lines.append(contentsOf: focusItems.map { "- \($0)" })
            lines.append("")
        }

        if !openLoops.isEmpty {
            lines.append("## Open Loops")
            lines.append("")
            lines.append(contentsOf: openLoops.map { "- \($0)" })
            lines.append("")
        }

        if !recentAsks.isEmpty {
            lines.append("## Recent User Asks")
            lines.append("")
            lines.append(contentsOf: recentAsks.map { "- \($0)" })
            lines.append("")
        }

        if !groupedObservations.isEmpty {
            lines.append("## Captured Memory This Week")
            lines.append("")
            for reason in groupedObservations.keys.sorted() {
                let items = Array(LinkedHashSet(groupedObservations[reason, default: []].map(\.text)).prefix(8))
                guard !items.isEmpty else { continue }
                lines.append("### \(reason.capitalized)")
                lines.append("")
                lines.append(contentsOf: items.map { "- \($0)" })
                lines.append("")
            }
        }

        if !userMemorySnapshot.isEmpty {
            lines.append("## Current User Memory Snapshot")
            lines.append("")
            lines.append(contentsOf: userMemorySnapshot.map { "- \($0)" })
            lines.append("")
        }

        lines.append("## Review Notes")
        lines.append("")
        lines.append("- Confirm whether any stale preferences, projects, or relationship facts should be updated.")
        lines.append("- Turn important open loops into reminders or todos if they still matter.")
        lines.append("- Keep structured facts in contacts, events, notes, bookmarks, and todos instead of relying on memory alone.")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func loadDailyObservations(since cutoff: Date) -> [MemoryObservation] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dailyDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "md" }
            .filter { fileURL in
                guard let date = Self.dateFromDailyFileName(fileURL.deletingPathExtension().lastPathComponent, calendar: calendar) else {
                    return false
                }
                return date >= calendar.startOfDay(for: cutoff)
            }
            .flatMap { parseDailyObservations(from: $0) }
    }

    private func parseDailyObservations(from fileURL: URL) -> [MemoryObservation] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return content
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- ["),
                      let closing = trimmed.firstIndex(of: "]")
                else {
                    return nil
                }

                let reasonStart = trimmed.index(trimmed.startIndex, offsetBy: 3)
                let reason = String(trimmed[reasonStart..<closing]).trimmingCharacters(in: .whitespacesAndNewlines)
                let textStart = trimmed.index(after: closing)
                let text = String(trimmed[textStart...]).trimmingCharacters(in: CharacterSet(charactersIn: " -\t"))
                guard !reason.isEmpty, !text.isEmpty else { return nil }
                return MemoryObservation(reason: reason, text: text)
            }
    }

    private func loadUserMemoryBullets(limit: Int) -> [String] {
        let userURL = memoryDirectory.appendingPathComponent("user.md")
        guard let content = try? String(contentsOf: userURL, encoding: .utf8) else {
            return []
        }

        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    private func extractOpenLoops(from handoffs: [AgentThreadHandoff]) -> [String] {
        let loopSignals = [
            "need to", "remember to", "don't forget", "dont forget", "follow up",
            "look into", "check on", "fix", "test", "work on", "finish",
            "i want to", "i should", "later", "this week", "tomorrow"
        ]

        let candidates = handoffs
            .flatMap(\.recentTurns)
            .filter { $0.role == .user }
            .map(\.content)
            .filter { text in
                let normalized = text.lowercased()
                return loopSignals.contains(where: normalized.contains) && text.count >= 18
            }
            .map { normalizedSentence($0, maxLength: 180) }
            .filter { !$0.isEmpty }

        return Array(LinkedHashSet(candidates).prefix(12))
    }

    private func writeOpenLoopsFile(openLoops: [String], now: Date) {
        let fileURL = memoryDirectory.appendingPathComponent("open_loops.md")
        var lines: [String] = []
        lines.append("---")
        lines.append("type: open-loops")
        lines.append("updated: '\(Self.isoTimestamp(now))'")
        lines.append("---")
        lines.append("")
        lines.append("# Open Loops")
        lines.append("")

        if openLoops.isEmpty {
            lines.append("*(No obvious open loops detected this week.)*")
        } else {
            lines.append(contentsOf: openLoops.map { "- \($0)" })
        }
        lines.append("")

        do {
            try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write open loops file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func normalizedSentence(_ text: String, maxLength: Int) -> String {
        let flattened = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else { return "" }
        if flattened.count <= maxLength {
            return flattened
        }
        let cutoff = flattened.index(flattened.startIndex, offsetBy: max(1, maxLength - 3))
        return String(flattened[..<cutoff]) + "..."
    }

    private var memoryDirectory: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
    }

    private var dailyDirectory: URL {
        memoryDirectory.appendingPathComponent("daily", isDirectory: true)
    }

    private var reviewsDirectory: URL {
        memoryDirectory.appendingPathComponent("reviews", isDirectory: true)
    }

    private struct MemoryObservation {
        let reason: String
        let text: String
    }

    private struct LinkedHashSet<Element: Hashable> {
        private var ordered: [Element] = []
        private var seen: Set<Element> = []

        init(_ sequence: some Sequence<Element>) {
            for element in sequence where seen.insert(element).inserted {
                ordered.append(element)
            }
        }

        func prefix(_ maxLength: Int) -> ArraySlice<Element> {
            ordered.prefix(maxLength)
        }
    }

    private static func weekKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? calendar.component(.year, from: date)
        let week = comps.weekOfYear ?? 0
        return "\(year)-W\(String(format: "%02d", week))"
    }

    private static func dateFromDailyFileName(_ fileName: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: fileName)
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

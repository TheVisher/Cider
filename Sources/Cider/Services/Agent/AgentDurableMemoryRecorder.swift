import Foundation
import os

final class AgentDurableMemoryRecorder {
    enum MemorySection: String {
        case preferences = "Preferences"
        case projects = "Projects"
        case relationships = "Relationships"
        case routines = "Routines"
        case explicitRemember = "Explicit Remember"
    }

    struct Observation {
        let section: MemorySection
        let text: String
        let reason: String
    }

    enum Decision {
        case skipped(String)
        case recorded(Observation)
    }

    private let logger = Logger(subsystem: "com.cider.app", category: "AgentDurableMemoryRecorder")

    func recordIfNeeded(userText: String, channel: AgentChannel) {
        switch decide(userText: userText, channel: channel) {
        case .skipped(let reason):
            logger.debug("Skipped durable memory capture: \(reason, privacy: .public)")
        case .recorded(let observation):
            appendToDailyMemory(observation)
            appendToUserMemory(observation)
            logger.info("Recorded durable memory [\(observation.reason, privacy: .public)] in section \(observation.section.rawValue, privacy: .public)")
        }
    }

    private func decide(userText: String, channel: AgentChannel) -> Decision {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .skipped("empty user message")
        }

        if let observation = classify(trimmed) {
            return .recorded(observation)
        }

        guard shouldConsider(channel: channel, text: trimmed) else {
            return .skipped(skipReason(for: channel, text: trimmed))
        }

        return .skipped("no durable-memory signal matched")
    }

    private func shouldConsider(channel: AgentChannel, text: String) -> Bool {
        switch channel {
        case .system, .notification, .shareIngress:
            return false
        case .uiPanel, .iMessage, .telegram, .iosApp:
            break
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }
        guard trimmed.split(separator: " ").count >= 3 else { return false }
        guard !trimmed.contains("http://"), !trimmed.contains("https://") else { return false }
        guard !trimmed.hasPrefix("/") else { return false }
        return true
    }

    private func classify(_ text: String) -> Observation? {
        let trimmed = normalizedText(text)
        let lowercased = trimmed.lowercased()

        if let explicit = explicitRememberObservation(from: trimmed, lowercased: lowercased) {
            return explicit
        }

        if preferenceSignals.contains(where: lowercased.contains) {
            return Observation(section: .preferences, text: trimmed, reason: "preference")
        }

        if projectSignals.contains(where: lowercased.contains) {
            return Observation(section: .projects, text: trimmed, reason: "project")
        }

        if relationshipSignals.contains(where: lowercased.contains) {
            return Observation(section: .relationships, text: trimmed, reason: "relationship")
        }

        if routineSignals.contains(where: lowercased.contains) {
            return Observation(section: .routines, text: trimmed, reason: "routine")
        }

        return nil
    }

    private func explicitRememberObservation(from text: String, lowercased: String) -> Observation? {
        let phrases = [
            "remember that ",
            "remember this ",
            "can you remember that ",
            "can you remember this ",
            "for future reference, ",
            "for future reference ",
            "keep in mind that ",
            "please remember ",
            "please remember "
        ]

        for phrase in phrases {
            if let range = lowercased.range(of: phrase) {
                let suffix = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = suffix.isEmpty ? text : suffix
                return Observation(section: .explicitRemember, text: normalizedText(cleaned), reason: "explicit remember")
            }
        }

        return nil
    }

    private func skipReason(for channel: AgentChannel, text: String) -> String {
        switch channel {
        case .system, .notification, .shareIngress:
            return "channel \(channel.rawValue) is not eligible"
        case .uiPanel, .iMessage, .telegram, .iosApp:
            break
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 12 {
            return "message too short"
        }
        if trimmed.split(separator: " ").count < 3 {
            return "message too terse"
        }
        if trimmed.contains("http://") || trimmed.contains("https://") {
            return "url-heavy capture belongs elsewhere"
        }
        if trimmed.hasPrefix("/") {
            return "command-like message"
        }
        return "message did not qualify"
    }

    private func appendToDailyMemory(_ observation: Observation) {
        let dateString = Self.dateString(Date())
        let dailyURL = memoryDirectory.appendingPathComponent("daily/\(dateString).md")
        let line = "- [\(observation.reason)] \(observation.text)"

        do {
            try FileManager.default.createDirectory(at: dailyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dailyURL.path) {
                let existing = (try? String(contentsOf: dailyURL, encoding: .utf8)) ?? ""
                guard !existing.contains(line) else { return }
                if let handle = try? FileHandle(forWritingTo: dailyURL) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(("\n" + line).utf8))
                    try handle.close()
                }
            } else {
                let content = """
                ---
                date: '\(dateString)'
                ---

                ## Observations

                \(line)
                """
                try content.write(to: dailyURL, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to append daily memory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func appendToUserMemory(_ observation: Observation) {
        let userURL = memoryDirectory.appendingPathComponent("user.md")
        let bullet = "- \(observation.text)"

        do {
            try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: userURL.path) {
                let report = StoragePaths.ensureVaultStructure()
                for failure in report.failures {
                    logger.error(
                        "Durable-memory compatibility initialization incomplete: \(failure.operation.rawValue, privacy: .public) at \(failure.path, privacy: .public): \(failure.underlyingError, privacy: .public)"
                    )
                }
            }

            let existing = (try? String(contentsOf: userURL, encoding: .utf8)) ?? ""
            guard !existing.contains(bullet) else { return }

            let updated = upsertBullet(in: existing, section: observation.section.rawValue, bullet: bullet)
            try updated.write(to: userURL, atomically: true, encoding: .utf8)
            logger.info("Recorded durable memory in section \(observation.section.rawValue, privacy: .public)")
        } catch {
            logger.error("Failed to append durable memory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsertBullet(in markdown: String, section: String, bullet: String) -> String {
        let sectionHeader = "## \(section)"
        let lines = markdown.isEmpty ? [] : markdown.components(separatedBy: .newlines)

        if let index = lines.firstIndex(of: sectionHeader) {
            var insertionIndex = index + 1
            while insertionIndex < lines.count, !lines[insertionIndex].hasPrefix("## ") {
                insertionIndex += 1
            }

            var updatedLines = lines
            if insertionIndex > index + 1, updatedLines[insertionIndex - 1] != "" {
                updatedLines.insert("", at: insertionIndex)
                insertionIndex += 1
            }
            updatedLines.insert(bullet, at: insertionIndex)
            return updatedLines.joined(separator: "\n")
        }

        var base = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty {
            base += "\n\n"
        }
        base += """
        ## \(section)

        \(bullet)
        """
        return base + "\n"
    }

    private func normalizedText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsed.count <= 200 {
            return collapsed
        }
        let cutoff = collapsed.index(collapsed.startIndex, offsetBy: 197)
        return String(collapsed[..<cutoff]) + "..."
    }

    private var memoryDirectory: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private let preferenceSignals = [
        "i prefer", "i usually prefer", "i like", "i love", "i don't like", "i dislike",
        "i hate", "my favorite", "i'm into", "i am into", "i enjoy", "i don't want",
        "i do not want", "i'd rather", "i would rather"
    ]

    private let projectSignals = [
        "i'm working on", "i am working on", "i'm building", "i am building",
        "my project", "we're building", "we are building", "i'm focused on",
        "i am focused on", "my goal is", "i'm trying to", "i am trying to"
    ]

    private let relationshipSignals = [
        "my wife", "my husband", "my partner", "my girlfriend", "my boyfriend",
        "my daughter", "my son", "my kid", "my kids", "my mom", "my dad",
        "my sister", "my brother", "my friend", "my manager", "my coworker",
        "my co-worker", "my dog", "my cat"
    ]

    private let routineSignals = [
        "every morning", "every night", "every day", "every week", "usually",
        "normally", "most weekends", "on weekends", "i tend to", "i always", "i never"
    ]
}

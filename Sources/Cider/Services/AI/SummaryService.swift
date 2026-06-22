import Foundation
import FoundationModels
import os.log

/// On-device page summarization using Foundation Models (Apple Intelligence).
/// Only available when Apple Intelligence is enabled on the device.
@MainActor
final class SummaryService {
    static let shared = SummaryService()

    private let logger = Logger(subsystem: "com.cider.app", category: "SummaryService")
    private var summarizeArticleOverrideForTesting: ((String) async -> String?)?

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: """
        You are a concise bookmark summarizer. Given article or page text, \
        write a 2-sentence summary capturing the main point and key insight. \
        Be factual and direct. Never start with "This article" or "This page". \
        Return only the summary, nothing else.
        """)
    }

    private func makeKanbanPreviewSession() -> LanguageModelSession {
        LanguageModelSession(instructions: """
        You are a concise Kanban card preview summarizer. Given a card title and notes, \
        write a 1-2 sentence board-level summary that helps someone scan active work. \
        Focus on the actual work, skip section labels, and return only the summary.
        """)
    }

    // MARK: - Summarize

    /// Summarize article text into 2 sentences.
    /// - Parameter articleText: Raw article text (will be truncated if too long)
    /// - Returns: Summary string, or nil on failure
    func summarize(articleText: String) async -> String? {
        if let summarizeArticleOverrideForTesting {
            return Self.sanitizedSummary(await summarizeArticleOverrideForTesting(articleText))
        }
        guard AIAvailability.isFoundationModelsAvailable else { return nil }
        // Stay within context window — ~4000 chars is safe for the on-device model
        let truncated = String(articleText.prefix(4000))
        guard !truncated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            let response = try await makeSession().respond(to: truncated)
            return Self.sanitizedSummary(response.content)
        } catch {
            logger.error("Summary failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func sanitizedSummary(_ rawSummary: String?) -> String? {
        guard let rawSummary else { return nil }
        let summary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }

        if Self.looksLikeXPrivacyExtensionTroubleshooting(summary) { return nil }

        return summary
    }

    nonisolated static func looksLikeXPrivacyExtensionTroubleshooting(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let mentionsX = normalized.contains("x.com")
        let mentionsPrivacyExtensions = normalized.contains("privacy-related extension")
            || normalized.contains("privacy related extension")
        let mentionsTroubleshootingAction = normalized.contains("disable")
            || normalized.contains("disabling")
            || normalized.contains("try again")
        let mentionsTroubleshootingIssue = normalized.contains("may cause issues")
            || normalized.contains("might cause issues")
            || normalized.contains("cause issues")
            || normalized.contains("has been reported")
            || normalized.contains("privacy-related issue")
            || normalized.contains("does not load")
        let looksLikeAccessTroubleshooting = mentionsX
            && mentionsPrivacyExtensions
            && mentionsTroubleshootingAction
            && mentionsTroubleshootingIssue
        return looksLikeAccessTroubleshooting
    }

    func _setSummarizeArticleOverrideForTesting(_ override: @escaping (String) async -> String?) {
        summarizeArticleOverrideForTesting = override
    }

    func _resetSummarizeArticleOverrideForTesting() {
        summarizeArticleOverrideForTesting = nil
    }

    /// Summarize a Kanban card for board scanning. The full notes remain the source of truth.
    func summarizeKanbanCardPreview(title: String, notes: String?) async -> String? {
        guard AIAvailability.isFoundationModelsAvailable else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedTitle.isEmpty || !trimmedNotes.isEmpty else { return nil }

        let prompt = """
        Card title: \(trimmedTitle)

        Card notes:
        \(String(trimmedNotes.prefix(3500)))

        Write a concise Kanban board preview summary in 1-2 short sentences. \
        Focus on the actual work, not section labels like Problem, Goal, or Acceptance criteria. \
        Return only the summary.
        """

        do {
            let response = try await makeKanbanPreviewSession().respond(to: prompt)
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        } catch {
            logger.error("Kanban summary failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Suggest a cleaner title for a bookmark if the current one seems auto-generated.
    /// Returns the original title if the AI suggests no improvement.
    func suggestTitle(currentTitle: String, articleText: String) async -> String? {
        guard AIAvailability.isFoundationModelsAvailable else { return nil }
        guard looksLikeAutoGeneratedTitle(currentTitle) else { return nil }
        let excerpt = String(articleText.prefix(1200))
        let prompt = """
        Current title: \(currentTitle)
        Article excerpt: \(excerpt)

        If the current title is vague, auto-generated, or just the site name, \
        write a clearer title (max 80 characters). If it's already good, return it unchanged. \
        Return only the title, no quotes or explanation.
        """
        do {
            let response = try await makeSession().respond(to: prompt)
            let suggested = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return suggested.isEmpty ? nil : suggested
        } catch {
            return nil
        }
    }

    // MARK: - Heuristics

    private func looksLikeAutoGeneratedTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        // Patterns that suggest auto-generated: "Site | Page", "Site - Page", all-caps, just a domain
        if t.contains(" | ") || t.contains(" - ") { return true }
        if t == t.uppercased() && t.count > 4 { return true }
        if !t.contains(" ") && t.count < 30 { return true }  // single-word domain title
        return false
    }
}

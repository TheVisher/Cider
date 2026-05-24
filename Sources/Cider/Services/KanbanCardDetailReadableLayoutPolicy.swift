import Foundation

enum KanbanCardDetailReadableSection: Equatable, Sendable {
    case summary
    case comments
    case legacyNotes
    case projectedSections
    case history
    case agentContext
}

struct KanbanCardDetailReadableLayoutPolicy: Equatable, Sendable {
    let headerBadges: [String]
    let shortSummary: String
    let primarySections: [KanbanCardDetailReadableSection]
    let defaultCollapsedSections: Set<KanbanCardDetailReadableSection>

    init(card: KanbanCard, statusLabel: String?) {
        var badges: [String] = []
        if let statusLabel = statusLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !statusLabel.isEmpty {
            badges.append(statusLabel)
        }
        if let priority = card.priority {
            badges.append(priority.rawValue.capitalized)
        }
        badges.append(contentsOf: card.tags.prefix(3))

        self.headerBadges = badges
        self.shortSummary = Self.summary(for: card)
        self.primarySections = [.summary, .comments]
        self.defaultCollapsedSections = [.legacyNotes, .projectedSections, .history, .agentContext]
    }

    static func summary(for card: KanbanCard) -> String {
        if let aiSummary = card.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !aiSummary.isEmpty {
            return clipped(aiSummary)
        }

        let sections = KanbanCardSectionParser.sections(from: card.notes)
        let preferredKeys = ["current_state", "summary", "overview", "goal", "next_step"]
        for key in preferredKeys {
            if let section = sections.first(where: { $0.key == key }),
               !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return clipped(section.body)
            }
        }

        if let firstSection = sections.first(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return clipped(firstSection.body)
        }

        if let notes = card.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return clipped(notes)
        }

        return card.title
    }

    private static func clipped(_ value: String, limit: Int = 220) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

import Foundation

struct ProjectWorkspaceInboxBadge: Identifiable, Equatable, Hashable {
    enum Kind: String, Equatable, Hashable {
        case new
        case agentReport
        case needsQA
    }

    let kind: Kind
    let title: String
    let systemImage: String

    var id: Kind { kind }

    static let new = ProjectWorkspaceInboxBadge(kind: .new, title: "New", systemImage: "sparkle")
    static let agentReport = ProjectWorkspaceInboxBadge(kind: .agentReport, title: "Agent report", systemImage: "cpu")
    static let needsQA = ProjectWorkspaceInboxBadge(kind: .needsQA, title: "Needs QA", systemImage: "checklist")
}

struct ProjectWorkspaceInboxEntry: Identifiable, Equatable {
    let boardID: String
    let boardName: String
    let columnID: String
    let columnName: String
    let card: KanbanCard
    let badges: [ProjectWorkspaceInboxBadge]
    let latestActivityAt: Date

    var id: String { "\(boardID):\(card.id)" }
}

enum ProjectWorkspaceInboxProvider {
    /// Existing project boards predate the Inbox feature and do not have reviewedAt backfill.
    /// Treat pre-launch activity as already reviewed so Inbox starts as an unread lens,
    /// not a full historical activity board. New cards/activity after this point enter Inbox.
    static let inboxLaunchBaseline = Date(timeIntervalSince1970: 1_779_494_400)

    static func entries(for workspace: ProjectWorkspace, boards: [KanbanBoard]) -> [ProjectWorkspaceInboxEntry] {
        boards
            .filter { workspace.boardIDs.contains($0.id) }
            .flatMap(entries(in:))
            .filter { isUnread($0.card, latestActivityAt: $0.latestActivityAt) }
            .sorted { lhs, rhs in
                if lhs.latestActivityAt != rhs.latestActivityAt { return lhs.latestActivityAt > rhs.latestActivityAt }
                return lhs.card.title.localizedCaseInsensitiveCompare(rhs.card.title) == .orderedAscending
            }
    }

    static func unreadCount(for workspace: ProjectWorkspace, boards: [KanbanBoard]) -> Int {
        entries(for: workspace, boards: boards).count
    }

    static func badges(for card: KanbanCard, column: KanbanColumn) -> [ProjectWorkspaceInboxBadge] {
        var badges: [ProjectWorkspaceInboxBadge] = []
        if isNewSignal(card, column: column) {
            badges.append(.new)
        }
        if hasAgentReportSignal(card) {
            badges.append(.agentReport)
        }
        if needsQASignal(card, column: column) {
            badges.append(.needsQA)
        }
        return badges
    }

    static func isUnread(_ card: KanbanCard, latestActivityAt: Date? = nil) -> Bool {
        let latest = latestActivityAt ?? latestActivityDate(for: card)
        let reviewCutoff = card.reviewedAt ?? inboxLaunchBaseline
        return latest > reviewCutoff
    }

    static func latestActivityDate(for card: KanbanCard) -> Date {
        ([card.created, card.completed, card.updatedAt] + card.historyEntries.map(\.createdAt))
            .compactMap { $0 }
            .max() ?? card.created
    }

    private static func entries(in board: KanbanBoard) -> [ProjectWorkspaceInboxEntry] {
        board.columns.flatMap { column in
            column.cards.compactMap { card in
                let badges = badges(for: card, column: column)
                guard isInboxCandidate(badges) else { return nil }
                return ProjectWorkspaceInboxEntry(
                    boardID: board.id,
                    boardName: board.name,
                    columnID: column.id,
                    columnName: column.name,
                    card: card,
                    badges: badges,
                    latestActivityAt: latestActivityDate(for: card)
                )
            }
        }
    }

    private static func isInboxCandidate(_ badges: [ProjectWorkspaceInboxBadge]) -> Bool {
        badges.contains { $0.kind == .agentReport || $0.kind == .needsQA }
    }

    private static func isNewSignal(_ card: KanbanCard, column: KanbanColumn) -> Bool {
        card.reviewedAt == nil && !isBacklogOrArchiveColumn(column)
    }

    private static func hasAgentReportSignal(_ card: KanbanCard) -> Bool {
        if card.agent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        let agentEntryTypes: Set<KanbanCardHistoryEntryType> = [.implementation, .handoff, .finalSummary, .testEvidence, .commit]
        return card.historyEntries.contains { agentEntryTypes.contains($0.type) }
    }

    private static func needsQASignal(_ card: KanbanCard, column: KanbanColumn) -> Bool {
        let statusText = "\(column.id) \(column.name) \(card.lastActivityKind ?? "")".localizedLowercase
        return statusText.contains("test")
            || statusText.contains("qa")
            || statusText.contains("review")
            || statusText.contains("ready")
    }

    private static func isBacklogOrArchiveColumn(_ column: KanbanColumn) -> Bool {
        let statusText = "\(column.id) \(column.name)".localizedLowercase
        return statusText.contains("backlog")
            || statusText.contains("archive")
            || statusText.contains("done")
            || statusText.contains("fixed")
    }
}

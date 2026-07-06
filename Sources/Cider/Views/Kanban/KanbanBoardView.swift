import SwiftUI

enum KanbanBoardHeaderControl: String, CaseIterable, Identifiable {
    case filter
    case displayOptions
    case properties

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filter: "Filter"
        case .displayOptions: "Display Options"
        case .properties: "Properties"
        }
    }

    var systemImage: String {
        switch self {
        case .filter: "line.3.horizontal.decrease.circle"
        case .displayOptions: "slider.horizontal.3"
        case .properties: "sidebar.right"
        }
    }

    var helpText: String {
        switch self {
        case .filter: "Filter board"
        case .displayOptions: "Display options"
        case .properties: "Show board properties"
        }
    }

    var placeholderTitle: String {
        switch self {
        case .filter: "Filter controls are coming next."
        case .displayOptions: "Display options are coming next."
        case .properties: "Board properties are coming next."
        }
    }

    var placeholderBody: String {
        switch self {
        case .filter:
            "This shell will hold filter categories like status, labels, dates, and project milestones."
        case .displayOptions:
            "This shell will hold board layout, ordering, column visibility, and card property options."
        case .properties:
            "This inspector shell will hold board properties, milestones, progress, and activity."
        }
    }
}

enum KanbanBoardHeaderLayoutMode: Equatable {
    case regular
    case compact

    static func mode(availableWidth: CGFloat, inspectorVisible: Bool) -> KanbanBoardHeaderLayoutMode {
        inspectorVisible && availableWidth < 1_240 ? .compact : .regular
    }
}

enum KanbanBoardFilterCategory: String, CaseIterable, Identifiable {
    case aiFilter
    case advancedFilter
    case status
    case priority
    case labels
    case attachments
    case relations
    case dates
    case projectMilestone
    case content
    case links

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiFilter: "AI filter"
        case .advancedFilter: "Advanced filter"
        case .status: "Status"
        case .priority: "Priority"
        case .labels: "Labels"
        case .attachments: "Attachments"
        case .relations: "Relations"
        case .dates: "Dates"
        case .projectMilestone: "Project milestone"
        case .content: "Content"
        case .links: "Links"
        }
    }

    var systemImage: String {
        switch self {
        case .aiFilter: "sparkles"
        case .advancedFilter: "line.3.horizontal.decrease.circle"
        case .status: "circle.dashed"
        case .priority: "flag"
        case .labels: "tag"
        case .attachments: "paperclip"
        case .relations: "link"
        case .dates: "calendar"
        case .projectMilestone: "diamond"
        case .content: "doc.text.magnifyingglass"
        case .links: "link.circle"
        }
    }

    var detailText: String {
        switch self {
        case .aiFilter: "Natural language filters"
        case .advancedFilter: "Nested rule builder"
        case .status: "Column and state filters"
        case .priority: "Priority tags and markers"
        case .labels: "Card tags and domains"
        case .attachments: "Typed comment attachments"
        case .relations: "Parent, child, and related cards"
        case .dates: "Created, updated, and reviewed dates"
        case .projectMilestone: "Milestone card scope"
        case .content: "Title, notes, and summaries"
        case .links: "URLs and linked entities"
        }
    }

    var stateLabel: String {
        switch self {
        case .aiFilter, .advancedFilter:
            "Placeholder"
        case .projectMilestone:
            "Next"
        case .attachments:
            "Ready"
        case .status, .priority, .labels, .relations, .dates, .content, .links:
            "Coming later"
        }
    }

    var isNextWiringTarget: Bool {
        self == .projectMilestone || self == .attachments
    }
}

enum KanbanBoardInspectorSection: String, CaseIterable, Identifiable {
    case properties
    case milestones
    case progress
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .properties: "Properties"
        case .milestones: "Milestones"
        case .progress: "Progress"
        case .activity: "Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .properties: "list.bullet.rectangle"
        case .milestones: "diamond"
        case .progress: "chart.bar.xaxis"
        case .activity: "clock.arrow.circlepath"
        }
    }

    var placeholderText: String {
        switch self {
        case .properties:
            "Board status, priority, ownership, labels, dates, and counts will appear here."
        case .milestones:
            "Milestone rows with child counts and quick filter actions will appear here."
        case .progress:
            "Completed, active, blocked, and testing breakdowns will appear here."
        case .activity:
            "Recent board changes, card history, and test evidence will appear here."
        }
    }
}

struct KanbanBoardInspectorMilestoneRow: Identifiable, Equatable {
    let id: String
    let title: String
    let displayKey: String
    let status: String
    let progressText: String
    let completedChildCount: Int
    let childCount: Int
    let progressFraction: Double
    let isSelected: Bool

    var progressPercentText: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }

    static func rows(in board: KanbanBoard, selectedID: String?) -> [KanbanBoardInspectorMilestoneRow] {
        let candidates = board.columns.flatMap { column in
            column.cards.compactMap { card -> KanbanBoardInspectorMilestoneRow? in
                guard isMilestoneCard(card),
                      let summary = KanbanBoardLayout.childSummary(for: card.id, in: board),
                      summary.totalCount > 0 else {
                    return nil
                }

                return KanbanBoardInspectorMilestoneRow(
                    id: card.id,
                    title: normalizedMilestoneTitle(card.title),
                    displayKey: board.displayKey(for: card),
                    status: column.name,
                    progressText: summary.progressText,
                    completedChildCount: summary.doneCount,
                    childCount: summary.totalCount,
                    progressFraction: Double(summary.doneCount) / Double(summary.totalCount),
                    isSelected: card.id == selectedID
                )
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.isSelected != rhs.isSelected { return lhs.isSelected }
            if lhs.progressFraction != rhs.progressFraction { return lhs.progressFraction < rhs.progressFraction }
            return lhs.displayKey.localizedStandardCompare(rhs.displayKey) == .orderedAscending
        }
    }

    private static func isMilestoneCard(_ card: KanbanCard) -> Bool {
        card.tags.contains { tag in
            tag.localizedCaseInsensitiveCompare("milestone") == .orderedSame ||
                tag.localizedCaseInsensitiveCompare("milestone-object") == .orderedSame
        } || card.title.localizedCaseInsensitiveContains("milestone:")
    }

    private static func normalizedMilestoneTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "Milestone: ", with: "")
    }
}

struct KanbanBoardInspectorProgressSummary: Equatable {
    let total: Int
    let completed: Int
    let backlog: Int
    let inProgress: Int
    let testing: Int
    let blocked: Int

    var completedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var completedPercentText: String {
        "\(Int((completedFraction * 100).rounded()))%"
    }

    static func summary(in board: KanbanBoard) -> KanbanBoardInspectorProgressSummary {
        var total = 0
        var completed = 0
        var backlog = 0
        var inProgress = 0
        var testing = 0
        var blocked = 0

        for column in board.columns {
            let cards = column.cards
            total += cards.count
            completed += cards.filter { column.isDoneLikeColumn || $0.completed != nil }.count
            blocked += cards.filter(isBlocked).count

            switch columnKind(for: column) {
            case .backlog:
                backlog += cards.count
            case .inProgress:
                inProgress += cards.count
            case .testing:
                testing += cards.count
            case .other:
                break
            }
        }

        return KanbanBoardInspectorProgressSummary(
            total: total,
            completed: completed,
            backlog: backlog,
            inProgress: inProgress,
            testing: testing,
            blocked: blocked
        )
    }

    private enum ColumnKind {
        case backlog
        case inProgress
        case testing
        case other
    }

    private static func columnKind(for column: KanbanColumn) -> ColumnKind {
        let text = "\(column.id) \(column.name)".localizedLowercase
        if text.contains("test") || text.contains("qa") || text.contains("review") {
            return .testing
        }
        if text.contains("progress") || text.contains("doing") || text.contains("active") {
            return .inProgress
        }
        if text.contains("queued") || text.contains("backlog") || text.contains("ready") || text.contains("next") {
            return .backlog
        }
        return .other
    }

    private static func isBlocked(_ card: KanbanCard) -> Bool {
        if card.tags.contains(where: { $0.localizedCaseInsensitiveContains("blocked") }) {
            return true
        }
        let text = [card.title, card.notes ?? "", card.aiSummary ?? ""].joined(separator: " ")
        return text.localizedCaseInsensitiveContains("blocked")
            || text.localizedCaseInsensitiveContains("blocker")
    }
}

struct KanbanBoardInspectorActivityEntry: Identifiable, Equatable {
    let id: String
    let cardID: String
    let displayKey: String
    let title: String
    let kind: String
    let body: String
    let timestamp: Date
    let systemImage: String

    var timestampText: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    static func entries(in board: KanbanBoard, limit: Int = 6) -> [KanbanBoardInspectorActivityEntry] {
        let gatheredEntries = board.columns.flatMap { column in
            column.cards.flatMap { card in
                entries(for: card, in: board, column: column)
            }
        }

        return Array(
            gatheredEntries.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                return lhs.displayKey.localizedStandardCompare(rhs.displayKey) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    private static func entries(
        for card: KanbanCard,
        in board: KanbanBoard,
        column: KanbanColumn
    ) -> [KanbanBoardInspectorActivityEntry] {
        var entries: [KanbanBoardInspectorActivityEntry] = []
        let title = normalizedCardTitle(card.title)
        let displayKey = board.displayKey(for: card)

        entries.append(contentsOf: card.historyEntries.map { history in
            KanbanBoardInspectorActivityEntry(
                id: "history-\(history.id)",
                cardID: card.id,
                displayKey: displayKey,
                title: title,
                kind: history.type.displayName,
                body: summaryText(history.body),
                timestamp: history.createdAt,
                systemImage: history.type.symbolName
            )
        })

        entries.append(contentsOf: card.comments.filter { !$0.isResolved }.map { comment in
            KanbanBoardInspectorActivityEntry(
                id: "comment-\(comment.id)",
                cardID: card.id,
                displayKey: displayKey,
                title: title,
                kind: comment.kind.displayName,
                body: summaryText(comment.body),
                timestamp: comment.createdAt,
                systemImage: comment.kind.symbolName
            )
        })

        if let completed = card.completed {
            entries.append(
                KanbanBoardInspectorActivityEntry(
                    id: "completed-\(card.id)",
                    cardID: card.id,
                    displayKey: displayKey,
                    title: title,
                    kind: "Completed",
                    body: "Moved to \(column.name)",
                    timestamp: completed,
                    systemImage: "checkmark.circle.fill"
                )
            )
        }

        if let updatedAt = card.updatedAt {
            entries.append(
                KanbanBoardInspectorActivityEntry(
                    id: "updated-\(card.id)",
                    cardID: card.id,
                    displayKey: displayKey,
                    title: title,
                    kind: "Updated",
                    body: "Card updated",
                    timestamp: updatedAt,
                    systemImage: "clock.arrow.circlepath"
                )
            )
        }

        return entries
    }

    private static func normalizedCardTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "Milestone: ", with: "")
    }

    private static func summaryText(_ body: String) -> String {
        let collapsed = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 96 else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 95)
        return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct KanbanBoardMilestoneFilterOption: Identifiable, Equatable {
    let id: String
    let title: String
    let displayKey: String
    let progressText: String?
    let isSelected: Bool

    static func options(in board: KanbanBoard, selectedID: String?) -> [KanbanBoardMilestoneFilterOption] {
        board.allCards.compactMap { card in
            guard isMilestoneCard(card) else { return nil }
            return KanbanBoardMilestoneFilterOption(
                id: card.id,
                title: normalizedMilestoneTitle(card.title),
                displayKey: board.displayKey(for: card),
                progressText: KanbanBoardLayout.childSummary(for: card.id, in: board)?.progressText,
                isSelected: card.id == selectedID
            )
        }
    }

    private static func isMilestoneCard(_ card: KanbanCard) -> Bool {
        card.tags.contains { tag in
            tag.localizedCaseInsensitiveCompare("milestone") == .orderedSame ||
                tag.localizedCaseInsensitiveCompare("milestone-object") == .orderedSame
        } || card.title.localizedCaseInsensitiveContains("milestone:")
    }

    private static func normalizedMilestoneTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "Milestone: ", with: "")
    }
}

struct KanbanBoardAttachmentTypeFilterOption: Identifiable, Equatable {
    let type: KanbanCardCommentAttachmentType

    var id: String { type.rawValue }
    var title: String { type.displayName }

    static let allCases: [KanbanBoardAttachmentTypeFilterOption] = [
        KanbanBoardAttachmentTypeFilterOption(type: .research),
        KanbanBoardAttachmentTypeFilterOption(type: .inspiration),
        KanbanBoardAttachmentTypeFilterOption(type: .evidence),
        KanbanBoardAttachmentTypeFilterOption(type: .handoff),
        KanbanBoardAttachmentTypeFilterOption(type: .qa),
        KanbanBoardAttachmentTypeFilterOption(type: .reference),
    ]
}

enum KanbanBoardDisplayModeOption: String, CaseIterable, Identifiable {
    case board
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "Board"
        case .list: "List"
        }
    }

    var stateLabel: String {
        switch self {
        case .board: "Active"
        case .list: "Later"
        }
    }
}

enum KanbanBoardDisplayOrderingOption: String, CaseIterable, Identifiable {
    case manualLaneOrder
    case priority
    case created
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualLaneOrder: "Manual lane order"
        case .priority: "Priority"
        case .created: "Created"
        case .updated: "Updated"
        }
    }
}

enum KanbanBoardDisplayPropertyOption: String, CaseIterable, Identifiable, Codable {
    case id
    case status
    case priority
    case milestone
    case labels
    case links
    case created
    case updated

    var id: String { rawValue }

    static let defaultVisibleOptions: Set<KanbanBoardDisplayPropertyOption> = [.id, .labels]

    var title: String {
        switch self {
        case .id: "ID"
        case .status: "Status"
        case .priority: "Priority"
        case .milestone: "Milestone"
        case .labels: "Labels"
        case .links: "Links"
        case .created: "Created"
        case .updated: "Updated"
        }
    }
}

struct KanbanBoardViewPreferences: Codable, Equatable {
    var selectedDisplayProperties: Set<KanbanBoardDisplayPropertyOption>
    var showEmptyColumns: Bool
    var showSubIssues: Bool
    var isInspectorVisible: Bool

    static let `default` = KanbanBoardViewPreferences(
        selectedDisplayProperties: KanbanBoardDisplayPropertyOption.defaultVisibleOptions,
        showEmptyColumns: true,
        showSubIssues: true,
        isInspectorVisible: false
    )
}

final class KanbanBoardViewPreferenceStore: @unchecked Sendable {
    static let shared = KanbanBoardViewPreferenceStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preferences(for boardID: String) -> KanbanBoardViewPreferences {
        guard let data = defaults.data(forKey: key(for: boardID)),
              let preferences = try? decoder.decode(KanbanBoardViewPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    func setPreferences(_ preferences: KanbanBoardViewPreferences, for boardID: String) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: key(for: boardID))
    }

    func resetPreferences(for boardID: String) {
        defaults.removeObject(forKey: key(for: boardID))
    }

    private func key(for boardID: String) -> String {
        "cider.kanban.boardViewPreferences.\(boardID)"
    }
}

struct KanbanBoardDisplayPropertyValue: Identifiable, Equatable {
    let option: KanbanBoardDisplayPropertyOption
    let title: String
    let value: String
    let isFallback: Bool

    var id: String { option.id }

    static func values(
        for card: KanbanCard,
        in board: KanbanBoard,
        column: KanbanColumn,
        options: [KanbanBoardDisplayPropertyOption]
    ) -> [KanbanBoardDisplayPropertyValue] {
        options.map { option in
            value(for: option, card: card, board: board, column: column)
        }
    }

    private static func value(
        for option: KanbanBoardDisplayPropertyOption,
        card: KanbanCard,
        board: KanbanBoard,
        column: KanbanColumn
    ) -> KanbanBoardDisplayPropertyValue {
        switch option {
        case .id:
            return present(option, board.displayKey(for: card))
        case .status:
            return present(option, column.name)
        case .priority:
            return card.priority.map { present(option, priorityTitle($0)) } ?? fallback(option, "No priority")
        case .milestone:
            return milestoneTitle(for: card, in: board)
                .map { present(option, $0) } ?? fallback(option, "No milestone")
        case .labels:
            let labels = card.tags.map(displayTagLabel).filter { !$0.isEmpty }
            return labels.isEmpty ? fallback(option, "No labels") : present(option, labels.joined(separator: ", "))
        case .links:
            let count = card.linkedEntities.count + card.relatedCardIDs.count
            return count > 0 ? present(option, "\(count) \(count == 1 ? "link" : "links")") : fallback(option, "No links")
        case .created:
            return present(option, formattedDate(card.created))
        case .updated:
            return card.updatedAt.map { present(option, formattedDate($0)) } ?? fallback(option, "No updates")
        }
    }

    private static func present(_ option: KanbanBoardDisplayPropertyOption, _ value: String) -> KanbanBoardDisplayPropertyValue {
        KanbanBoardDisplayPropertyValue(option: option, title: option.title, value: value, isFallback: false)
    }

    private static func fallback(_ option: KanbanBoardDisplayPropertyOption, _ value: String) -> KanbanBoardDisplayPropertyValue {
        KanbanBoardDisplayPropertyValue(option: option, title: option.title, value: value, isFallback: true)
    }

    private static func priorityTitle(_ priority: KanbanPriority) -> String {
        switch priority {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    private static func milestoneTitle(for card: KanbanCard, in board: KanbanBoard) -> String? {
        var parentID = card.parentCardID
        var visited: Set<String> = []
        while let id = parentID, visited.insert(id).inserted {
            guard let parent = board.allCards.first(where: { $0.id == id }) else { return nil }
            if isMilestoneCard(parent) {
                return normalizedMilestoneTitle(parent.title)
            }
            parentID = parent.parentCardID
        }
        return nil
    }

    private static func isMilestoneCard(_ card: KanbanCard) -> Bool {
        card.tags.contains { tag in
            tag.localizedCaseInsensitiveCompare("milestone") == .orderedSame ||
                tag.localizedCaseInsensitiveCompare("milestone-object") == .orderedSame
        } || card.title.localizedCaseInsensitiveContains("milestone:")
    }

    private static func normalizedMilestoneTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "Milestone: ", with: "")
    }

    private static func displayTagLabel(_ tag: String) -> String {
        KanbanCardTagTaxonomy.normalized(tag)
            .split(separator: "-")
            .map { part in
                let lower = part.lowercased()
                if lower == "ios" { return "iOS" }
                if lower == "qa" { return "QA" }
                guard let first = part.first else { return "" }
                return first.uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter.string(from: date)
    }
}

struct KanbanBoardScanStripColumnCount: Identifiable, Equatable {
    let id: String
    let label: String
    let visibleCount: Int
    let totalCount: Int

    var countText: String {
        "\(visibleCount)/\(totalCount)"
    }
}

struct KanbanBoardScanStripState: Equatable {
    let totalCardCount: Int
    let visibleCardCount: Int
    let activeFilterCount: Int
    let columnCounts: [KanbanBoardScanStripColumnCount]

    var resultText: String {
        "\(visibleCardCount) of \(totalCardCount) \(totalCardCount == 1 ? "card" : "cards")"
    }

    var activeFilterSummary: String {
        activeFilterCount == 1 ? "1 filter" : "\(activeFilterCount) filters"
    }

    static func state(
        in board: KanbanBoard,
        searchText: String,
        attachmentType: KanbanCardCommentAttachmentType?,
        featureDomainFilter: String?,
        projectBoardViewID: String,
        milestoneFilterCardID: String?
    ) -> KanbanBoardScanStripState {
        let counts = board.columns.map { column in
            let visible = KanbanBoardVisibleCardFilter.filteredCards(
                column.cards,
                in: column,
                board: board,
                searchText: searchText,
                attachmentType: attachmentType,
                featureDomainFilter: featureDomainFilter,
                projectBoardViewID: projectBoardViewID,
                milestoneFilterCardID: milestoneFilterCardID
            ).count
            return KanbanBoardScanStripColumnCount(
                id: column.id,
                label: column.name,
                visibleCount: visible,
                totalCount: column.cards.count
            )
        }

        return KanbanBoardScanStripState(
            totalCardCount: board.allCards.count,
            visibleCardCount: counts.reduce(0) { $0 + $1.visibleCount },
            activeFilterCount: KanbanBoardScanStripFilterRow.rows(
                in: board,
                searchText: searchText,
                attachmentType: attachmentType,
                featureDomainFilter: featureDomainFilter,
                projectBoardViewID: projectBoardViewID,
                milestoneFilterCardID: milestoneFilterCardID
            ).filter(\.isActive).count,
            columnCounts: counts
        )
    }
}

struct KanbanBoardScanStripFilterRow: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case projectView
        case domain
        case attachment
        case milestone
        case search
    }

    let kind: Kind
    let title: String
    let value: String
    let systemImage: String
    let isActive: Bool

    var id: String { kind.rawValue }

    static func rows(
        in board: KanbanBoard,
        searchText: String,
        attachmentType: KanbanCardCommentAttachmentType?,
        featureDomainFilter: String?,
        projectBoardViewID: String,
        milestoneFilterCardID: String?
    ) -> [KanbanBoardScanStripFilterRow] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectView = KanbanBoardLayout.projectBoardViewFilters(for: board)
            .first { $0.id == projectBoardViewID }

        return [
            KanbanBoardScanStripFilterRow(
                kind: .projectView,
                title: "View",
                value: projectView?.label ?? "All",
                systemImage: "rectangle.3.group",
                isActive: projectBoardViewID != "all"
            ),
            KanbanBoardScanStripFilterRow(
                kind: .domain,
                title: "Domain",
                value: featureDomainLabel(featureDomainFilter) ?? "All domains",
                systemImage: "cube.transparent",
                isActive: featureDomainFilter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ),
            KanbanBoardScanStripFilterRow(
                kind: .attachment,
                title: "Attachment",
                value: attachmentType?.displayName ?? "All refs",
                systemImage: "paperclip",
                isActive: attachmentType != nil
            ),
            KanbanBoardScanStripFilterRow(
                kind: .milestone,
                title: "Milestone",
                value: milestoneFilterCardID.flatMap { board.card(id: $0) }.map { board.displayKey(for: $0) } ?? "All milestones",
                systemImage: "diamond",
                isActive: milestoneFilterCardID != nil
            ),
            KanbanBoardScanStripFilterRow(
                kind: .search,
                title: "Search",
                value: trimmedSearch.isEmpty ? "Any text" : trimmedSearch,
                systemImage: "magnifyingglass",
                isActive: !trimmedSearch.isEmpty
            ),
        ]
    }

    private static func featureDomainLabel(_ id: String?) -> String? {
        let normalized = KanbanCardTagTaxonomy.normalized(id ?? "")
        guard !normalized.isEmpty else { return nil }
        return KanbanBoardLayout.featureDomainCatalog.first { $0.id == normalized }?.label
            ?? displayLabel(for: normalized)
    }

    private static func displayLabel(for value: String) -> String {
        value.split(separator: "-")
            .map { part in
                let lowercased = part.lowercased()
                if lowercased == "ios" { return "iOS" }
                if lowercased == "qa" { return "QA" }
                guard let first = part.first else { return "" }
                return first.uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct KanbanCardScanMetadata: Equatable {
    let displayKey: String
    let title: String
    let status: String
    let readiness: String?
    let attachmentText: String?
    let chips: [KanbanCardFaceChip]

    static func metadata(
        for card: KanbanCard,
        in board: KanbanBoard,
        column: KanbanColumn
    ) -> KanbanCardScanMetadata {
        let attachmentCount = card.attachmentSummary.totalCount
        return KanbanCardScanMetadata(
            displayKey: board.displayKey(for: card),
            title: card.title,
            status: column.name,
            readiness: KanbanBoardLayout.testingOwnerBadge(for: card)?.text,
            attachmentText: attachmentCount > 0 ? "\(attachmentCount) \(attachmentCount == 1 ? "ref" : "refs")" : nil,
            chips: KanbanBoardLayout.cardFaceOverflowTags(for: card, limit: 3)
        )
    }
}

enum KanbanBoardVisibleCardFilter {
    static func filteredCards(
        _ cards: [KanbanCard],
        in column: KanbanColumn,
        board: KanbanBoard,
        searchText: String,
        attachmentType: KanbanCardCommentAttachmentType?,
        featureDomainFilter: String?,
        projectBoardViewID: String,
        milestoneFilterCardID: String?
    ) -> [KanbanCard] {
        let viewFilteredCards = KanbanBoardLayout.cards(
            cards,
            in: column,
            board: board,
            matchingProjectBoardViewID: projectBoardViewID
        )
        let featureFilteredCards = KanbanBoardLayout.cards(
            viewFilteredCards,
            matchingFeatureDomainFilter: featureDomainFilter
        )
        let milestoneFilteredCards = Self.milestoneFilteredCards(
            featureFilteredCards,
            board: board,
            milestoneFilterCardID: milestoneFilterCardID
        )

        let discoveryFilter = KanbanBoardDiscoveryFilter(
            query: searchText,
            attachmentTypes: attachmentType.map { [$0] } ?? []
        )
        guard !discoveryFilter.isEmpty else { return milestoneFilteredCards }

        let filteredColumn = KanbanColumn(
            id: column.id,
            name: column.name,
            isDoneColumn: column.isDoneColumn,
            cards: milestoneFilteredCards
        )
        let scopedBoard = KanbanBoard(
            id: board.id,
            name: board.name,
            columns: [filteredColumn]
        )

        guard let result = try? scopedBoard.filteredForDiscovery(discoveryFilter) else {
            return milestoneFilteredCards
        }

        if !discoveryFilter.query.isEmpty {
            let discoveryIDs = Set(result.board.columns.first?.cards.map { $0.id } ?? [String]())
            return milestoneFilteredCards.filter { card in
                discoveryIDs.contains(card.id) || (
                    matchesBoardSearchFallback(card, board: board, query: discoveryFilter.query) &&
                    matchesAttachmentType(card, attachmentType)
                )
            }
        }

        return result.board.columns.first?.cards ?? []
    }

    private static func milestoneFilteredCards(
        _ cards: [KanbanCard],
        board: KanbanBoard,
        milestoneFilterCardID: String?
    ) -> [KanbanCard] {
        guard let milestoneID = milestoneFilterCardID,
              board.allCards.contains(where: { $0.id == milestoneID }) else {
            return cards
        }
        let cardsByParentID = Dictionary(grouping: board.allCards) { $0.parentCardID ?? "" }
        var includedCardIDs: Set<String> = [milestoneID]
        var pendingCardIDs = [milestoneID]
        while let parentID = pendingCardIDs.popLast() {
            for child in cardsByParentID[parentID, default: []] where !includedCardIDs.contains(child.id) {
                includedCardIDs.insert(child.id)
                pendingCardIDs.append(child.id)
            }
        }
        return cards.filter { card in
            includedCardIDs.contains(card.id)
        }
    }

    private static func matchesBoardSearchFallback(_ card: KanbanCard, board: KanbanBoard, query: String) -> Bool {
        card.id.localizedStandardContains(query) ||
            board.displayKey(for: card).localizedStandardContains(query) ||
            (card.agent ?? "").localizedStandardContains(query)
    }

    private static func matchesAttachmentType(_ card: KanbanCard, _ attachmentType: KanbanCardCommentAttachmentType?) -> Bool {
        guard let attachmentType else { return true }
        return card.comments.contains { comment in
            comment.attachments.contains { $0.type == attachmentType }
        }
    }
}

/// Renders a Kanban board as horizontal scrolling columns with draggable cards.
struct KanbanBoardView: View {
    let boardID: String
    var milestoneFilterCardID: String?
    var onOpenCard: (String, String) -> Void = { _, _ in }

    @ObservedObject private var storage = KanbanStorage.shared
    @State private var editingBoardName = false
    @State private var boardNameDraft = ""
    @State private var addingCardToColumn: String?
    @State private var newCardTitle = ""
    @State private var quickAddColumnID: String?
    @State private var quickAddDraft = KanbanQuickAddDraft()
    @State private var renamingColumnID: String?
    @State private var columnNameDraft = ""
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""
    @State private var compactCards = false
    @State private var projectLaneScrollIndexByID: [String: Int] = [:]
    @State private var tagEditorCardID: String?
    @State private var tagEditorDraft = ""
    @State private var selectedFeatureDomainFilter: String?
    @State private var selectedAttachmentTypeFilter: KanbanCardCommentAttachmentType?
    @State private var selectedProjectBoardViewID = "all"
    @State private var selectedMilestoneFilterCardID: String?
    @State private var activeHeaderPopover: KanbanBoardHeaderControl?
    @State private var expandedFilterCategory: KanbanBoardFilterCategory?
    @State private var isBoardInspectorVisible = false
    @State private var selectedDisplayProperties = KanbanBoardDisplayPropertyOption.defaultVisibleOptions
    @State private var showEmptyColumns = true
    @State private var showSubIssues = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardFaceSuggestedTags = [
        "sidebar",
        "cider-web",
        "cider-ios",
        "bug",
        "idea",
        "testing",
        "qa",
        "performance",
        "blocked",
    ]

    private var board: KanbanBoard? {
        storage.boards.first { $0.id == boardID }
    }

    /// Filter cards by board view, search text, milestone, domain, and typed attachments.
    private func filteredCards(_ cards: [KanbanCard], in column: KanbanColumn, board: KanbanBoard) -> [KanbanCard] {
        KanbanBoardVisibleCardFilter.filteredCards(
            cards,
            in: column,
            board: board,
            searchText: searchText,
            attachmentType: selectedAttachmentTypeFilter,
            featureDomainFilter: selectedFeatureDomainFilter,
            projectBoardViewID: selectedProjectBoardViewID,
            milestoneFilterCardID: selectedMilestoneFilterCardID
        )
    }

    var body: some View {
        if let board {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    boardHeader(board)
                    Divider().background(CiderColors.separator)
                    columnsArea(board)
                }

                if isBoardInspectorVisible {
                    boardInspectorShell(board)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: isBoardInspectorVisible)
            .onChange(of: boardID) { _, _ in
                projectLaneScrollIndexByID.removeAll()
                selectedFeatureDomainFilter = nil
                selectedAttachmentTypeFilter = nil
                selectedProjectBoardViewID = "all"
                selectedMilestoneFilterCardID = milestoneFilterCardID
                activeHeaderPopover = nil
                expandedFilterCategory = nil
                loadBoardViewPreferences()
            }
            .onAppear {
                loadBoardViewPreferences()
                selectedMilestoneFilterCardID = milestoneFilterCardID
                expandedFilterCategory = selectedMilestoneFilterCardID == nil ? nil : .projectMilestone
            }
            .onChange(of: milestoneFilterCardID) { _, newValue in
                selectedMilestoneFilterCardID = newValue
                expandedFilterCategory = newValue == nil ? expandedFilterCategory : .projectMilestone
            }
        } else {
            emptyState
        }
    }

    private func loadBoardViewPreferences() {
        let preferences = KanbanBoardViewPreferenceStore.shared.preferences(for: boardID)
        selectedDisplayProperties = preferences.selectedDisplayProperties
        showEmptyColumns = preferences.showEmptyColumns
        showSubIssues = preferences.showSubIssues
        isBoardInspectorVisible = preferences.isInspectorVisible
    }

    private func persistBoardViewPreferences() {
        KanbanBoardViewPreferenceStore.shared.setPreferences(
            KanbanBoardViewPreferences(
                selectedDisplayProperties: selectedDisplayProperties,
                showEmptyColumns: showEmptyColumns,
                showSubIssues: showSubIssues,
                isInspectorVisible: isBoardInspectorVisible
            ),
            for: boardID
        )
    }

    private func resetBoardViewPreferences() {
        KanbanBoardViewPreferenceStore.shared.resetPreferences(for: boardID)
        loadBoardViewPreferences()
    }

    // MARK: - Board Header

    private func boardHeader(_ board: KanbanBoard) -> some View {
        let featureFilters = KanbanBoardLayout.featureDomainFilters(for: board)

        return GeometryReader { proxy in
            VStack(alignment: .leading, spacing: Spacing.xs) {
                boardHeaderRow(
                    board,
                    featureFilters: featureFilters,
                    mode: KanbanBoardHeaderLayoutMode.mode(
                        availableWidth: proxy.size.width,
                        inspectorVisible: isBoardInspectorVisible
                    )
                )
                boardScanStrip(board)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private func boardHeaderRow(
        _ board: KanbanBoard,
        featureFilters: [KanbanFeatureDomainFilter],
        mode: KanbanBoardHeaderLayoutMode
    ) -> some View {
        let isCompact = mode == .compact

        return HStack(spacing: Spacing.sm) {
            boardTitleView(board, mode: mode)

            Spacer(minLength: Spacing.md)

            boardSearchField(width: isCompact ? 82 : 100)

            if !featureFilters.isEmpty {
                domainFilterMenu(featureFilters, mode: mode)
            }

            attachmentTypeFilterMenu(mode: mode)

            HStack(spacing: Spacing.xxs) {
                ForEach(KanbanBoardHeaderControl.allCases) { control in
                    boardHeaderControlButton(control)
                }
            }

            // Compact toggle
            Button {
                withAnimation(reduceMotion ? .none : .spring) {
                    compactCards.toggle()
                }
            } label: {
                Image(systemName: compactCards ? "list.bullet" : "rectangle.grid.1x2")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .help(compactCards ? "Expanded view" : "Compact view")

            addColumnButton(compact: isCompact)

            Menu {
                Button {
                    boardNameDraft = board.name
                    editingBoardName = true
                } label: {
                    Label("Rename Board", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Board", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Delete \"\(board.name)\"?", isPresented: $showDeleteConfirmation) {
                Button("Delete Board", role: .destructive) {
                    if let trashItem = storage.deleteBoard(id: boardID) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .kanbanBoard, trashItem: trashItem))
                    }
                }
            } message: {
                Text("This will permanently delete the board and all its cards. This can't be undone.")
            }
        }
    }

    private func boardSearchField(width: CGFloat) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            TextField("Filter cards...", text: $searchText)
                .textFieldStyle(.plain)
                .font(CiderFont.caption)
                .frame(width: width)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func addColumnButton(compact: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring) {
                let name = "New Column"
                storage.addColumn(boardID: boardID, name: name)
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "plus")
                if !compact {
                    Text("Column")
                }
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(CiderColors.controlAccent)
            .frame(minWidth: compact ? 24 : 0, minHeight: 24)
        }
        .buttonStyle(.plain)
        .help("Add column")
        .accessibilityLabel("Add column")
    }

    private func boardTitleView(_ board: KanbanBoard, mode: KanbanBoardHeaderLayoutMode = .regular) -> some View {
        let isCompact = mode == .compact

        return HStack(spacing: Spacing.sm) {
            if editingBoardName {
                TextField("Board name", text: $boardNameDraft)
                    .textFieldStyle(.plain)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onSubmit {
                        storage.renameBoard(id: boardID, name: boardNameDraft)
                        editingBoardName = false
                    }
            } else {
                Text(board.name)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) {
                        boardNameDraft = board.name
                        editingBoardName = true
                    }
            }

            if !isCompact {
                Text("\(filteredCardCount(for: board)) cards")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if KanbanBoardLayout.usesProjectLayout(for: board) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "rectangle.split.3x1")
                    if !isCompact {
                        Text("Project board")
                    }
                }
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule(style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.12))
                )
                .help("Project board")
                .accessibilityLabel("Project board")
            }
        }
        .frame(minWidth: 0, maxWidth: isCompact ? 210 : nil, alignment: .leading)
        .layoutPriority(isCompact ? 0 : 1)
    }

    private func boardScanStrip(_ board: KanbanBoard) -> some View {
        let state = KanbanBoardScanStripState.state(
            in: board,
            searchText: searchText,
            attachmentType: selectedAttachmentTypeFilter,
            featureDomainFilter: selectedFeatureDomainFilter,
            projectBoardViewID: selectedProjectBoardViewID,
            milestoneFilterCardID: selectedMilestoneFilterCardID
        )
        let activeRows = KanbanBoardScanStripFilterRow.rows(
            in: board,
            searchText: searchText,
            attachmentType: selectedAttachmentTypeFilter,
            featureDomainFilter: selectedFeatureDomainFilter,
            projectBoardViewID: selectedProjectBoardViewID,
            milestoneFilterCardID: selectedMilestoneFilterCardID
        ).filter(\.isActive)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                scanStripResultChip(state)

                if activeRows.isEmpty {
                    scanStripPassiveChip(title: "Filters", value: "All cards", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    ForEach(activeRows) { row in
                        scanStripFilterChip(row)
                    }
                }

                Divider()
                    .frame(height: 16)
                    .background(CiderColors.separator)

                ForEach(state.columnCounts) { count in
                    scanStripPassiveChip(
                        title: count.label,
                        value: count.countText,
                        systemImage: "rectangle.split.3x1"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Kanban scan controls, \(state.resultText), \(state.activeFilterSummary)")
    }

    private func scanStripResultChip(_ state: KanbanBoardScanStripState) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "number")
                .font(CiderFont.micro)
            Text(state.resultText)
                .lineLimit(1)
            if state.activeFilterCount > 0 {
                Text(state.activeFilterSummary)
                    .foregroundColor(CiderColors.controlAccent)
            }
        }
        .font(CiderFont.micro)
        .foregroundColor(CiderColors.secondary)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func scanStripFilterChip(_ row: KanbanBoardScanStripFilterRow) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: row.systemImage)
                .font(CiderFont.micro)
            Text(row.title)
                .foregroundColor(CiderColors.tertiary)
            Text(row.value)
                .foregroundColor(CiderColors.controlAccent)
                .lineLimit(1)
        }
        .font(CiderFont.micro)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.controlAccent.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CiderColors.controlAccent.opacity(0.18), lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .accessibilityLabel("\(row.title): \(row.value)")
    }

    private func scanStripPassiveChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: systemImage)
                .font(CiderFont.micro)
            Text(title)
                .foregroundColor(CiderColors.tertiary)
            Text(value)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
        }
        .font(CiderFont.micro)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput.opacity(0.76))
        )
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Columns

    private func domainFilterMenu(
        _ filters: [KanbanFeatureDomainFilter],
        mode: KanbanBoardHeaderLayoutMode = .regular
    ) -> some View {
        let selected = selectedFeatureDomainFilter.flatMap { selectedID in
            filters.first { $0.id == selectedID }
        }
        let isCompact = mode == .compact

        return Menu {
            Button {
                selectedFeatureDomainFilter = nil
            } label: {
                Label("All Domains", systemImage: selected == nil ? "checkmark" : "cube.transparent")
            }

            Divider()

            ForEach(filters) { filter in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                        selectedFeatureDomainFilter = filter.id
                    }
                } label: {
                    Label(
                        "\(filter.label) (\(filter.cardCount))",
                        systemImage: selectedFeatureDomainFilter == filter.id ? "checkmark" : "cube.transparent"
                    )
                }
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "cube.transparent")
                    .font(CiderFont.caption)
                if !isCompact {
                    Text(selected?.label ?? "Domains")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(selected == nil ? CiderColors.tertiary : CiderColors.controlAccent)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .frame(minWidth: isCompact ? 24 : 0, minHeight: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(selected == nil ? CiderColors.surfaceInput : CiderColors.controlAccent.opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help(selected.map { "Domain filter: \($0.label)" } ?? "Domain filter")
        .accessibilityLabel(selected.map { "Domain filter: \($0.label)" } ?? "Domain filter")
    }

    private func attachmentTypeFilterMenu(mode: KanbanBoardHeaderLayoutMode = .regular) -> some View {
        let isCompact = mode == .compact
        let selected = selectedAttachmentTypeFilter

        return Menu {
            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                    selectedAttachmentTypeFilter = nil
                }
            } label: {
                Label("All Attachments", systemImage: selected == nil ? "checkmark" : "paperclip")
            }

            Divider()

            ForEach(KanbanBoardAttachmentTypeFilterOption.allCases) { option in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                        selectedAttachmentTypeFilter = option.type
                    }
                } label: {
                    Label(
                        option.title,
                        systemImage: selected == option.type ? "checkmark" : "paperclip"
                    )
                }
            }
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "paperclip")
                        .font(CiderFont.caption)
                    if !isCompact {
                        Text(selected?.displayName ?? "Attachments")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(CiderFont.micro)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                .padding(.trailing, selected == nil || isCompact ? 0 : Spacing.xxs)
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(selected == nil ? CiderColors.tertiary : CiderColors.controlAccent)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .frame(minWidth: isCompact ? 24 : 0, minHeight: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(selected == nil ? CiderColors.surfaceInput : CiderColors.controlAccent.opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help(selected.map { "Attachment filter: \($0.displayName)" } ?? "Attachment filter")
        .accessibilityLabel(selected.map { "Attachment filter: \($0.displayName)" } ?? "Attachment filter")
        .overlay(alignment: .trailing) {
            if selected != nil, !isCompact {
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                        selectedAttachmentTypeFilter = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.controlAccent)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Spacing.xs)
                .help("Clear attachment filter")
                .accessibilityLabel("Clear attachment filter")
            }
        }
    }

    private func boardHeaderControlButton(_ control: KanbanBoardHeaderControl) -> some View {
        let isActive = activeHeaderPopover == control || (control == .properties && isBoardInspectorVisible)

        return Button {
            switch control {
            case .filter, .displayOptions:
                activeHeaderPopover = activeHeaderPopover == control ? nil : control
            case .properties:
                withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88)) {
                    isBoardInspectorVisible.toggle()
                    persistBoardViewPreferences()
                }
                activeHeaderPopover = nil
            }
        } label: {
            Image(systemName: control.systemImage)
                .font(CiderFont.caption)
                .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.tertiary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isActive ? CiderColors.controlAccent.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(isActive ? CiderColors.controlAccent.opacity(0.26) : Color.clear, lineWidth: CiderBorder.hairlineStrokeWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(control.helpText)
        .accessibilityLabel(control.title)
        .popover(
            isPresented: Binding(
                get: { activeHeaderPopover == control },
                set: { isPresented in
                    if !isPresented, activeHeaderPopover == control {
                        activeHeaderPopover = nil
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            boardHeaderControlPopover(control)
        }
    }

    private func boardHeaderControlPopover(_ control: KanbanBoardHeaderControl) -> some View {
        Group {
            if control == .filter {
                filterCategoriesPopover
            } else if control == .displayOptions {
                displayOptionsPopover
            } else {
                genericBoardHeaderControlPopover(control)
            }
        }
    }

    private var filterCategoriesPopover: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(KanbanBoardHeaderControl.filter.title, systemImage: KanbanBoardHeaderControl.filter.systemImage)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)

            Text("Filter categories")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)

            VStack(spacing: Spacing.xxs) {
                ForEach(KanbanBoardFilterCategory.allCases) { category in
                    filterCategoryRow(category)
                    if category == .projectMilestone,
                       expandedFilterCategory == .projectMilestone,
                       let board {
                        milestoneFilterOptionsList(board)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: 340, alignment: .leading)
    }

    private func filterCategoryRow(_ category: KanbanBoardFilterCategory) -> some View {
        Button {
            guard category == .projectMilestone else { return }
            withAnimation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.86)) {
                expandedFilterCategory = expandedFilterCategory == category ? nil : category
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.systemImage)
                    .font(CiderFont.caption)
                    .foregroundColor(category.isNextWiringTarget ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(category.detailText)
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.xs)

                if category == .projectMilestone {
                    Image(systemName: expandedFilterCategory == category ? "chevron.down" : "chevron.right")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.controlAccent)
                } else {
                    Text(category.stateLabel)
                        .font(CiderFont.micro)
                        .foregroundColor(category.isNextWiringTarget ? CiderColors.controlAccent : CiderColors.tertiary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(category.isNextWiringTarget ? CiderColors.controlAccent.opacity(0.12) : CiderColors.surfaceSubtle.opacity(0.72))
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(category != .projectMilestone)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(category.isNextWiringTarget ? CiderColors.controlAccent.opacity(0.07) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(category.isNextWiringTarget ? CiderColors.controlAccent.opacity(0.18) : Color.clear, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.title), \(category.detailText), \(category.stateLabel)")
    }

    private func milestoneFilterOptionsList(_ board: KanbanBoard) -> some View {
        let options = KanbanBoardMilestoneFilterOption.options(in: board, selectedID: selectedMilestoneFilterCardID)

        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                    selectedMilestoneFilterCardID = nil
                    projectLaneScrollIndexByID.removeAll()
                    activeHeaderPopover = nil
                }
            } label: {
                milestoneFilterOptionRow(
                    title: "All milestones",
                    detail: "Clear milestone filter",
                    systemImage: selectedMilestoneFilterCardID == nil ? "checkmark.circle.fill" : "circle",
                    isSelected: selectedMilestoneFilterCardID == nil
                )
            }
            .buttonStyle(.plain)

            if options.isEmpty {
                Text("No milestone cards on this board.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
            } else {
                ForEach(options) { option in
                    Button {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                            selectedMilestoneFilterCardID = option.id
                            projectLaneScrollIndexByID.removeAll()
                            activeHeaderPopover = nil
                        }
                    } label: {
                        milestoneFilterOptionRow(
                            title: option.title,
                            detail: option.progressText.map { "\(option.displayKey) · \($0)" } ?? option.displayKey,
                            systemImage: option.isSelected ? "checkmark.circle.fill" : "circle",
                            isSelected: option.isSelected
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 26)
        .padding(.vertical, Spacing.xxs)
    }

    private func milestoneFilterOptionRow(
        title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(CiderFont.caption)
                .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.controlAccent.opacity(0.08) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var displayOptionsPopover: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(KanbanBoardHeaderControl.displayOptions.title, systemImage: KanbanBoardHeaderControl.displayOptions.systemImage)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)

            displayOptionsSection("Layout") {
                HStack(spacing: Spacing.xs) {
                    ForEach(KanbanBoardDisplayModeOption.allCases) { option in
                        displayModeSegment(option)
                    }
                }
            }

            displayOptionsSection("Grouping") {
                displayDisabledOptionRow(title: "No grouping", detail: "Grouping controls come later.")
            }

            displayOptionsSection("Ordering") {
                VStack(spacing: Spacing.xxs) {
                    ForEach(KanbanBoardDisplayOrderingOption.allCases) { option in
                        displayDisabledOptionRow(
                            title: option.title,
                            detail: option == .manualLaneOrder ? "Current order" : "Candidate"
                        )
                    }
                }
            }

            displayOptionsSection("Visibility") {
                VStack(spacing: Spacing.xxs) {
                    displayToggleRow(title: "Show empty columns", isOn: showEmptyColumns) {
                        showEmptyColumns.toggle()
                        projectLaneScrollIndexByID.removeAll()
                        persistBoardViewPreferences()
                    }
                    displayToggleRow(title: "Show sub-issues", isOn: showSubIssues) {
                        showSubIssues.toggle()
                        persistBoardViewPreferences()
                    }
                }
            }

            displayOptionsSection("Display properties") {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 72), spacing: Spacing.xs)
                ], alignment: .leading, spacing: Spacing.xs) {
                    ForEach(KanbanBoardDisplayPropertyOption.allCases) { option in
                        displayPropertyChip(option, isSelected: selectedDisplayProperties.contains(option))
                    }
                }
            }

            Divider().background(CiderColors.separator)

            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.86)) {
                    resetBoardViewPreferences()
                    projectLaneScrollIndexByID.removeAll()
                }
            } label: {
                Label("Reset view preferences", systemImage: "arrow.counterclockwise")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset Kanban board view preferences")
        }
        .padding(Spacing.md)
        .frame(width: 320, alignment: .leading)
    }

    private func displayOptionsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)
            content()
        }
    }

    private func displayModeSegment(_ option: KanbanBoardDisplayModeOption) -> some View {
        let isActive = option == .board
        return HStack(spacing: Spacing.xxs) {
            Text(option.title)
            Text(option.stateLabel)
                .font(CiderFont.micro)
                .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.tertiary)
        }
        .font(CiderFont.captionMedium)
        .foregroundColor(isActive ? CiderColors.primary : CiderColors.secondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isActive ? CiderColors.controlAccent.opacity(0.10) : CiderColors.surfaceSubtle.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(isActive ? CiderColors.controlAccent.opacity(0.22) : CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func displayDisabledOptionRow(title: String, detail: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "circle")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 14)
            Text(title)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.secondary)
            Spacer(minLength: Spacing.xs)
            Text(detail)
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }

    private func displayToggleRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.88)) {
                action()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(CiderFont.caption)
                    .foregroundColor(isOn ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: 16)
                Text(title)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                Spacer(minLength: 0)
                Text(isOn ? "Shown" : "Hidden")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
    }

    private func displayPropertyChip(_ option: KanbanBoardDisplayPropertyOption, isSelected: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.88)) {
                toggleDisplayProperty(option)
            }
        } label: {
            HStack(spacing: 3) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(CiderFont.micro)
                }
                Text(option.title)
                    .lineLimit(1)
            }
            .font(CiderFont.micro)
            .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? CiderColors.controlAccent.opacity(0.12) : CiderColors.surfaceSubtle.opacity(0.72))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.controlAccent.opacity(0.24) : CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) display property")
        .accessibilityValue(isSelected ? "Shown" : "Hidden")
    }

    private func toggleDisplayProperty(_ option: KanbanBoardDisplayPropertyOption) {
        if selectedDisplayProperties.contains(option) {
            selectedDisplayProperties.remove(option)
        } else {
            selectedDisplayProperties.insert(option)
        }
        persistBoardViewPreferences()
    }

    private func genericBoardHeaderControlPopover(_ control: KanbanBoardHeaderControl) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(control.title, systemImage: control.systemImage)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)

            Text(control.placeholderTitle)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)

            Text(control.placeholderBody)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(width: 260, alignment: .leading)
    }

    private func boardInspectorShell(_ board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Label(KanbanBoardHeaderControl.properties.title, systemImage: KanbanBoardHeaderControl.properties.systemImage)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: 0)

                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88)) {
                        isBoardInspectorVisible = false
                        persistBoardViewPreferences()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Hide board properties")
                .accessibilityLabel("Close properties inspector")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider().background(CiderColors.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(board.name)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(2)

                        Text("\(board.allCards.count) cards")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(CiderColors.surfaceSubtle.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                    )

                    ForEach(KanbanBoardInspectorSection.allCases) { section in
                        boardInspectorSectionView(section, board: board)
                    }
                }
                .padding(Spacing.md)
            }
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
    }

    private func boardInspectorSectionView(_ section: KanbanBoardInspectorSection, board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Label(section.title, systemImage: section.systemImage)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: 0)

                Text(section == .properties ? "Shell" : "Live")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
            }

            switch section {
            case .milestones:
                boardInspectorMilestonesView(board)
            case .progress:
                boardInspectorProgressView(board)
            case .activity:
                boardInspectorActivityView(board)
            case .properties:
                Text(section.placeholderText)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func boardInspectorMilestonesView(_ board: KanbanBoard) -> some View {
        let rows = KanbanBoardInspectorMilestoneRow.rows(in: board, selectedID: selectedMilestoneFilterCardID)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if rows.isEmpty {
                Text("No milestone cards with child progress yet.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows.prefix(6)) { row in
                    Button {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.88)) {
                            selectedMilestoneFilterCardID = row.id
                            expandedFilterCategory = .projectMilestone
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                                Text(row.displayKey)
                                    .font(CiderFont.microMonospaced)
                                    .foregroundColor(row.isSelected ? CiderColors.controlAccent : CiderColors.tertiary)

                                Text(row.title)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Text(row.progressPercentText)
                                    .font(CiderFont.micro)
                                    .foregroundColor(CiderColors.secondary)
                            }

                            HStack(spacing: Spacing.xs) {
                                ProgressView(value: row.progressFraction)
                                    .progressViewStyle(.linear)
                                Text("\(row.progressText) · \(row.status)")
                                    .font(CiderFont.micro)
                                    .foregroundColor(CiderColors.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.title), \(row.progressText), \(row.progressPercentText), filter milestone")
                }
            }
        }
    }

    private func boardInspectorProgressView(_ board: KanbanBoard) -> some View {
        let summary = KanbanBoardInspectorProgressSummary.summary(in: board)
        let metrics: [(String, Int)] = [
            ("Total", summary.total),
            ("Completed", summary.completed),
            ("Backlog", summary.backlog),
            ("In Progress", summary.inProgress),
            ("Testing", summary.testing),
            ("Blocked", summary.blocked),
        ]

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(summary.completedPercentText)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Text("complete")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Text("\(summary.completed)/\(summary.total)")
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.secondary)
            }

            ProgressView(value: summary.completedFraction)
                .progressViewStyle(.linear)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.xs),
                GridItem(.flexible(), spacing: Spacing.xs),
            ], alignment: .leading, spacing: Spacing.xs) {
                ForEach(metrics, id: \.0) { label, value in
                    HStack(spacing: Spacing.xs) {
                        Text("\(value)")
                            .font(CiderFont.microMonospaced)
                            .foregroundColor(CiderColors.primary)
                        Text(label)
                            .font(CiderFont.micro)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func boardInspectorActivityView(_ board: KanbanBoard) -> some View {
        let entries = KanbanBoardInspectorActivityEntry.entries(in: board)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if entries.isEmpty {
                Text("No recent board activity yet.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entries) { entry in
                    Button {
                        onOpenCard(board.id, entry.cardID)
                    } label: {
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Image(systemName: entry.systemImage)
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.controlAccent)
                                .frame(width: 14, alignment: .center)

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                                    Text(entry.displayKey)
                                        .font(CiderFont.microMonospaced)
                                        .foregroundColor(CiderColors.tertiary)

                                    Text(entry.kind)
                                        .font(CiderFont.micro)
                                        .foregroundColor(CiderColors.secondary)

                                    Spacer(minLength: 0)

                                    Text(entry.timestampText)
                                        .font(CiderFont.micro)
                                        .foregroundColor(CiderColors.tertiary)
                                        .lineLimit(1)
                                }

                                Text(entry.title)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.primary)
                                    .lineLimit(1)

                                Text(entry.body)
                                    .font(CiderFont.micro)
                                    .foregroundColor(CiderColors.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(entry.kind) on \(entry.displayKey), \(entry.title), \(entry.body)")
                }
            }
        }
    }

    private func filteredCardCount(for board: KanbanBoard) -> Int {
        board.columns.reduce(0) { partial, column in
            partial + filteredCards(column.cards, in: column, board: board).count
        }
    }

    @ViewBuilder
    private func columnsArea(_ board: KanbanBoard) -> some View {
        if KanbanBoardLayout.usesProjectLayout(for: board) {
            projectRowsArea(board)
        } else {
            standardColumnsArea(board)
        }
    }

    private func displayColumns(_ columns: [KanbanColumn], board: KanbanBoard) -> [KanbanColumn] {
        guard !showEmptyColumns else { return columns }
        return columns.filter { column in
            let cards = filteredCards(column.cards, in: column, board: board)
            let displayCards = showSubIssues ? cards : cards.filter { $0.parentCardID == nil }
            return !displayCards.isEmpty
        }
    }

    private func standardColumnsArea(_ board: KanbanBoard) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(displayColumns(KanbanBoardLayout.visibleColumns(in: board), board: board)) { column in
                    columnView(column, board: board, width: KanbanDesign.columnWidth)
                }
            }
            .padding(Spacing.lg)
            .background(horizontalPanSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectRowsArea(_ board: KanbanBoard) -> some View {
        GeometryReader { geometry in
            if let lane = KanbanBoardLayout.lanes(for: board).first {
                projectLaneView(
                    lane,
                    board: board,
                    availableBoardHeight: geometry.size.height
                )
                .padding(Spacing.lg)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            } else {
                VStack {
                    Spacer()
                    Text("No columns")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectLaneView(
        _ lane: KanbanBoardLane,
        board: KanbanBoard,
        availableBoardHeight: CGFloat
    ) -> some View {
        let laneColumns = displayColumns(lane.columns, board: board)
        let hiddenColumns = KanbanBoardLayout.hiddenColumns(in: board)
        let viewFilters = KanbanBoardLayout.projectBoardViewFilters(for: board)
        let milestoneFilterCard = selectedMilestoneFilterCardID.flatMap { milestoneID in
            board.allCards.first { $0.id == milestoneID }
        }

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            if let milestoneFilterCard {
                milestoneFilterBanner(milestoneFilterCard, board: board)
            }
            projectBoardViewPills(viewFilters, hiddenColumnCount: hiddenColumns.count)

            GeometryReader { geometry in
                let scrollItemCount = KanbanBoardLayout.projectScrollableItemCount(
                    activeColumnCount: laneColumns.count,
                    hiddenColumnCount: hiddenColumns.count
                )
                let visibleColumnCount = projectLaneVisibleColumnCount(availableWidth: geometry.size.width)
                let maxScrollIndex = max(scrollItemCount - visibleColumnCount, 0)
                let columnHeight = KanbanBoardLayout.projectColumnHeight(
                    availableBoardHeight: availableBoardHeight,
                    showsScrollControls: maxScrollIndex > 0
                )

                ScrollViewReader { scrollProxy in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(alignment: .top, spacing: Spacing.md) {
                                ForEach(laneColumns) { column in
                                    columnView(
                                        column,
                                        board: board,
                                        width: KanbanDesign.projectColumnWidth,
                                        height: columnHeight
                                    )
                                    .id(projectColumnScrollID(laneID: lane.id, columnID: column.id))
                                }

                                if !hiddenColumns.isEmpty {
                                    hiddenColumnsRail(
                                        columns: hiddenColumns,
                                        board: board,
                                        height: columnHeight
                                    )
                                    .id(projectHiddenRailScrollID(laneID: lane.id))
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                            }
                            .padding(.bottom, Spacing.xs)
                            .background(horizontalPanSurface)
                        }
                        .frame(maxWidth: .infinity)
                        .defaultScrollAnchor(.leading)
                        .id(projectLaneScrollIdentity(for: lane))

                        if maxScrollIndex > 0 {
                            projectLaneScrollControls(
                                lane: lane,
                                visibleColumnCount: visibleColumnCount,
                                scrollItemCount: scrollItemCount,
                                maxScrollIndex: maxScrollIndex,
                                scrollProxy: scrollProxy
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.86), value: hiddenColumns.map(\.id))
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func projectBoardViewPills(
        _ filters: [KanbanProjectBoardViewFilter],
        hiddenColumnCount: Int
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(filters) { filter in
                        projectBoardViewPill(filter)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hiddenColumnCount > 0 {
                Text("\(hiddenColumnCount) hidden")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func projectBoardViewPill(_ filter: KanbanProjectBoardViewFilter) -> some View {
        let isSelected = selectedProjectBoardViewID == filter.id
        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                selectedProjectBoardViewID = filter.id
                projectLaneScrollIndexByID.removeAll()
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text(filter.label)
                    .lineLimit(1)

                Text("\(filter.cardCount)")
                    .font(CiderFont.micro)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? CiderColors.surfaceInput.opacity(0.94) : CiderColors.surfaceSubtle.opacity(0.48))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.borderSubtle : CiderColors.borderSubtle.opacity(0.58), lineWidth: CiderBorder.hairlineStrokeWidth)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.label) board view, \(filter.cardCount) cards")
    }

    private func projectLaneVisibleColumnCount(availableWidth: CGFloat) -> Int {
        let columnStride = KanbanDesign.projectColumnWidth + Spacing.md
        return max(1, Int(floor((availableWidth + Spacing.md) / columnStride)))
    }

    private func projectLaneScrollIdentity(for lane: KanbanBoardLane) -> String {
        return "\(lane.id)-active"
    }

    private func projectColumnScrollID(laneID: String, columnID: String) -> String {
        "\(laneID)-column-\(columnID)"
    }

    private func projectHiddenRailScrollID(laneID: String) -> String {
        "\(laneID)-hidden-rail"
    }

    private func projectLaneScrollIndex(for lane: KanbanBoardLane, maxScrollIndex: Int) -> Int {
        min(max(projectLaneScrollIndexByID[lane.id] ?? 0, 0), maxScrollIndex)
    }

    private func scrollProjectLane(
        _ lane: KanbanBoardLane,
        to index: Int,
        scrollItemCount: Int,
        maxScrollIndex: Int,
        scrollProxy: ScrollViewProxy
    ) {
        let nextIndex = min(max(index, 0), maxScrollIndex)
        projectLaneScrollIndexByID[lane.id] = nextIndex

        guard nextIndex < scrollItemCount else { return }

        let targetID = lane.columns.indices.contains(nextIndex)
            ? projectColumnScrollID(laneID: lane.id, columnID: lane.columns[nextIndex].id)
            : projectHiddenRailScrollID(laneID: lane.id)
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
            scrollProxy.scrollTo(
                targetID,
                anchor: .leading
            )
        }
    }

    private func milestoneFilterBanner(_ milestone: KanbanCard, board: KanbanBoard) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "diamond")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.controlAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(milestone.title.replacingOccurrences(of: "Milestone: ", with: ""))
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if let summary = KanbanBoardLayout.childSummary(for: milestone.id, in: board) {
                    Text("\(summary.progressText) · milestone filter")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                selectedMilestoneFilterCardID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Clear milestone filter")
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(CiderColors.surfaceSubtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline))
    }

    private func projectLaneScrollControls(
        lane: KanbanBoardLane,
        visibleColumnCount: Int,
        scrollItemCount: Int,
        maxScrollIndex: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let currentIndex = projectLaneScrollIndex(for: lane, maxScrollIndex: maxScrollIndex)
        let visibleRange = currentIndex..<(min(currentIndex + visibleColumnCount, scrollItemCount))

        return HStack(spacing: Spacing.xs) {
            Button {
                scrollProjectLane(
                    lane,
                    to: currentIndex - 1,
                    scrollItemCount: scrollItemCount,
                    maxScrollIndex: maxScrollIndex,
                    scrollProxy: scrollProxy
                )
            } label: {
                Image(systemName: "chevron.left")
                    .font(CiderFont.micro)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)
            .opacity(currentIndex == 0 ? 0.35 : 0.85)
            .help("Scroll columns left")

            HStack(spacing: Spacing.xxs) {
                ForEach(0..<scrollItemCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(visibleRange.contains(index) ? CiderColors.controlAccent.opacity(0.78) : CiderColors.borderSubtle.opacity(0.65))
                        .frame(width: visibleRange.contains(index) ? 18 : 10, height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Horizontal column position")

            Button {
                scrollProjectLane(
                    lane,
                    to: currentIndex + 1,
                    scrollItemCount: scrollItemCount,
                    maxScrollIndex: maxScrollIndex,
                    scrollProxy: scrollProxy
                )
            } label: {
                Image(systemName: "chevron.right")
                    .font(CiderFont.micro)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= maxScrollIndex)
            .opacity(currentIndex >= maxScrollIndex ? 0.35 : 0.85)
            .help("Scroll columns right")
        }
        .foregroundColor(CiderColors.tertiary)
        .padding(.horizontal, Spacing.xs)
        .frame(height: KanbanDesign.projectHorizontalScrollControlHeight)
    }

    private func hiddenColumnsRail(
        columns hiddenColumns: [KanbanColumn],
        board: KanbanBoard,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chevron.down")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)

                Text("Hidden columns")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: Spacing.xs)

                Text("\(hiddenColumns.count)")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(hiddenColumns) { column in
                    hiddenColumnRow(column, board: board)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(width: KanbanDesign.hiddenColumnsRailWidth, height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func hiddenColumnRow(_ column: KanbanColumn, board: KanbanBoard) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                storage.setColumnHidden(boardID: board.id, columnID: column.id, isHidden: false)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: column.isDoneColumn ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 18, alignment: .center)

                Text(column.name)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.xs)

                Text("\(filteredCards(column.cards, in: column, board: board).count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput.opacity(0.86))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show \(column.name)")
        .contextMenu {
            Button("Show Column") {
                storage.setColumnHidden(boardID: board.id, columnID: column.id, isHidden: false)
            }
        }
    }

    private func columnView(
        _ column: KanbanColumn,
        board: KanbanBoard,
        width: CGFloat,
        height: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            columnHeader(column, board: board)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Spacing.sm) {
                    let cards = filteredCards(column.cards, in: column, board: board)
                    let displayCards = showSubIssues ? cards : cards.filter { $0.parentCardID == nil }
                    let nodes = KanbanBoardLayout.cardNodes(
                        for: column,
                        in: board,
                        visibleCards: displayCards
                    )
                    ForEach(nodes) { node in
                        interactiveCard(
                            node.card,
                            column: column,
                            board: board,
                            toIndex: node.visualIndex,
                            childSummary: KanbanBoardLayout.childSummary(for: node.card.id, in: board)
                        )
                        .id(node.id)
                    }

                    // Add card button or inline field — also a drop target for appending
                    if addingCardToColumn == column.id {
                        addCardField(columnID: column.id)
                    } else {
                        addCardButton(columnID: column.id)
                            .dropDestination(for: String.self) { cardIDs, _ in
                                guard let cardID = cardIDs.first else { return false }
                                withAnimation(reduceMotion ? .none : .spring) {
                                    storage.moveCard(
                                        boardID: boardID,
                                        cardID: cardID,
                                        toColumnID: column.id,
                                        toIndex: column.cards.count,
                                        includeDescendants: shouldMoveDescendants(
                                            cardID: cardID,
                                            to: column,
                                            board: board
                                        )
                                    )
                                }
                                return true
                            }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .frame(width: width)
        .frame(height: height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
                horizontalPanSurface
            }
        )
        .dropDestination(for: String.self) { cardIDs, _ in
            guard let cardID = cardIDs.first else { return false }
            withAnimation(reduceMotion ? .none : .spring) {
                storage.moveCard(
                    boardID: boardID,
                    cardID: cardID,
                    toColumnID: column.id,
                    toIndex: column.cards.count,
                    includeDescendants: shouldMoveDescendants(
                        cardID: cardID,
                        to: column,
                        board: board
                    )
                )
            }
            return true
        }
    }

    private var horizontalPanSurface: some View {
        GeometryReader { _ in
            KanbanHorizontalPanScrollSurface()
        }
    }

    private func columnHeader(_ column: KanbanColumn, board: KanbanBoard) -> some View {
        HStack(spacing: Spacing.xs) {
            if renamingColumnID == column.id {
                TextField("Column name", text: $columnNameDraft)
                    .textFieldStyle(.plain)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onSubmit {
                        let trimmed = columnNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            storage.renameColumn(boardID: boardID, columnID: column.id, name: trimmed)
                        }
                        renamingColumnID = nil
                    }
            } else {
                Text(column.name)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onTapGesture(count: 2) {
                        columnNameDraft = column.name
                        renamingColumnID = column.id
                    }
            }

            Text("\(filteredCards(column.cards, in: column, board: board).count)")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.xs)
                .background(
                    Capsule(style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

            Spacer()

            Button {
                quickAddDraft = KanbanQuickAddDraft()
                quickAddColumnID = column.id
            } label: {
                Image(systemName: "plus")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick add card")
            .popover(
                isPresented: Binding(
                    get: { quickAddColumnID == column.id },
                    set: { isPresented in
                        if !isPresented {
                            quickAddColumnID = nil
                            quickAddDraft = KanbanQuickAddDraft()
                        }
                    }
                ),
                arrowEdge: .bottom
            ) {
                quickAddPopover(column: column, board: board)
            }

            Menu {
                Button("Rename") {
                    columnNameDraft = column.name
                    renamingColumnID = column.id
                }
                if !column.isDoneColumn {
                    Button("Mark as Done column") {
                        storage.setColumnDone(boardID: boardID, columnID: column.id, isDone: true)
                    }
                } else {
                    Button("Unmark as Done column") {
                        storage.setColumnDone(boardID: boardID, columnID: column.id, isDone: false)
                    }
                }
                Button("Hide Column") {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                        storage.setColumnHidden(boardID: boardID, columnID: column.id, isHidden: true)
                    }
                }
                Divider()
                Button("Delete Column", role: .destructive) {
                    withAnimation(reduceMotion ? .none : .spring) {
                        storage.deleteColumn(boardID: boardID, columnID: column.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Cards

    private func interactiveCard(
        _ card: KanbanCard,
        column: KanbanColumn,
        board: KanbanBoard,
        toIndex: Int,
        childSummary: KanbanParentChildSummary? = nil
    ) -> some View {
        let context = KanbanBoardLayout.boardCardContext(for: card, in: column, board: board)

        return cardView(
            card,
            column: column,
            board: board,
            compact: compactCards,
            childSummary: childSummary,
            parentBadge: context.parentBadge,
            planIndicator: context.planIndicator,
            accentColor: KanbanBoardLayout.cardAccentColor(for: card, in: board),
            inboxBadges: inboxBadges(for: card, in: column)
        )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                onOpenCard(boardID, card.id)
            }
            .draggable(card.id) {
                cardDragPreview(card)
            }
            .dropDestination(for: String.self) { cardIDs, _ in
                guard let cardID = cardIDs.first, cardID != card.id else { return false }
                withAnimation(reduceMotion ? .none : .spring) {
                    storage.moveCard(
                        boardID: boardID,
                        cardID: cardID,
                        toColumnID: column.id,
                        toIndex: toIndex,
                        includeDescendants: shouldMoveDescendants(
                            cardID: cardID,
                            to: column,
                            board: board
                        )
                    )
                }
                return true
            }
    }

    private func shouldMoveDescendants(cardID: String, to column: KanbanColumn, board: KanbanBoard) -> Bool {
        isQueuedColumn(column) && !board.childCards(of: cardID).isEmpty
    }

    private func isQueuedColumn(_ column: KanbanColumn) -> Bool {
        let normalized = "\(column.id) \(column.name)".lowercased()
        return normalized.contains("queue")
    }

    private func cardView(
        _ card: KanbanCard,
        column: KanbanColumn,
        board: KanbanBoard,
        compact: Bool = false,
        childSummary: KanbanParentChildSummary? = nil,
        parentBadge: KanbanParentBadge? = nil,
        planIndicator: KanbanPlanIndicator? = nil,
        accentColor: KanbanCardColor? = nil,
        inboxBadges: [ProjectWorkspaceInboxBadge] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : 0) {
            if let color = accentColor {
                RoundedRectangle(cornerRadius: KanbanDesign.accentBarRadius, style: .continuous)
                    .fill(kanbanColor(color))
                    .frame(height: KanbanDesign.accentBarHeight)
                    .padding(.bottom, compact ? Spacing.xxs : Spacing.xs)
            }

            cardHeaderView(
                card,
                compact: compact,
                childSummary: childSummary,
                showsDisplayKey: selectedDisplayProperties.contains(.id)
            )

            let displayValues = selectedCardDisplayPropertyValues(for: card, in: board, column: column)
            if !displayValues.isEmpty {
                cardDisplayPropertiesView(displayValues)
                    .padding(.top, compact ? Spacing.xxs : KanbanDesign.cardPreviewSectionSpacing)
            }

            if !inboxBadges.isEmpty {
                cardInboxBadgesView(inboxBadges)
                    .padding(.top, compact ? Spacing.xxs : KanbanDesign.cardPreviewSectionSpacing)
            }

            if compact {
                compactCardScanMetadataView(
                    KanbanCardScanMetadata.metadata(
                        for: card,
                        in: board,
                        column: column
                    ),
                    for: card
                )
                .padding(.top, Spacing.xxs)
            }

            if compact, hasCardContext(parentBadge: parentBadge, planIndicator: planIndicator) {
                cardContextView(parentBadge: parentBadge, planIndicator: planIndicator)
                    .padding(.top, Spacing.xxs)
            }

            if !compact {
                if hasCardContext(parentBadge: parentBadge, planIndicator: planIndicator) {
                    cardContextView(parentBadge: parentBadge, planIndicator: planIndicator)
                        .padding(.top, KanbanDesign.cardPreviewContextFooterSpacing)
                }

                if hasCardFooter(card) {
                    cardFooterView(card)
                        .padding(.top, KanbanDesign.cardPreviewFooterTopSpacing)
                }
            }
        }
        .padding(.horizontal, compact ? Spacing.sm : Spacing.md)
        .padding(.vertical, compact ? Spacing.sm : Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .contextMenu {
            Button("Delete Card", role: .destructive) {
                withAnimation(reduceMotion ? .none : .spring) {
                    storage.deleteCard(boardID: boardID, cardID: card.id)
                }
            }
        }
    }

    private func inboxBadges(for card: KanbanCard, in column: KanbanColumn) -> [ProjectWorkspaceInboxBadge] {
        guard ProjectWorkspaceInboxProvider.isUnread(card) else { return [] }
        return ProjectWorkspaceInboxProvider.badges(for: card, column: column)
    }

    private func cardInboxBadgesView(_ badges: [ProjectWorkspaceInboxBadge]) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(badges.prefix(3)) { badge in
                Label(badge.title, systemImage: badge.systemImage)
                    .font(CiderFont.micro)
                    .foregroundColor(inboxBadgeColor(for: badge.kind))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(inboxBadgeColor(for: badge.kind).opacity(0.12))
                    )
            }
        }
    }

    private func inboxBadgeColor(for kind: ProjectWorkspaceInboxBadge.Kind) -> Color {
        switch kind {
        case .new: return CiderColors.controlAccent
        case .agentReport: return CiderColors.secondary
        case .needsQA: return CiderColors.warning
        }
    }

    private func cardHeaderView(
        _ card: KanbanCard,
        compact: Bool,
        childSummary: KanbanParentChildSummary?,
        showsDisplayKey: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.xs) {
                if showsDisplayKey {
                    Text(displayKey(for: card))
                        .font(CiderFont.microMonospaced)
                        .foregroundColor(CiderColors.controlAccent)
                        .lineLimit(1)
                }

                if let childSummary {
                    childProgressChip(childSummary)
                }

                Spacer(minLength: Spacing.xs)

                cardAvatarPlaceholder(card)
            }

            Text(card.title)
                .font(compact ? CiderFont.captionSemibold : CiderFont.labelSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(compact ? 2 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectedCardDisplayPropertyValues(
        for card: KanbanCard,
        in board: KanbanBoard,
        column: KanbanColumn
    ) -> [KanbanBoardDisplayPropertyValue] {
        let options = KanbanBoardDisplayPropertyOption.allCases.filter { option in
            guard selectedDisplayProperties.contains(option) else { return false }
            if option == .id { return false }
            if option == .labels, !card.tags.isEmpty { return false }
            return true
        }
        return KanbanBoardDisplayPropertyValue.values(for: card, in: board, column: column, options: options)
    }

    private func cardDisplayPropertiesView(_ values: [KanbanBoardDisplayPropertyValue]) -> some View {
        TagFlowLayout(spacing: Spacing.xs) {
            ForEach(values) { value in
                HStack(spacing: 3) {
                    Text(value.title)
                        .foregroundColor(CiderColors.tertiary)
                    Text(value.value)
                        .foregroundColor(value.isFallback ? CiderColors.tertiary : CiderColors.secondary)
                }
                .font(CiderFont.micro)
                .lineLimit(1)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(value.isFallback ? CiderColors.surfaceInput.opacity(0.62) : CiderColors.surfaceInput)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                )
                .accessibilityLabel("\(value.title): \(value.value)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactCardScanMetadataView(_ metadata: KanbanCardScanMetadata, for card: KanbanCard) -> some View {
        TagFlowLayout(spacing: Spacing.xs) {
            HStack(spacing: 3) {
                Text("Status")
                    .foregroundColor(CiderColors.tertiary)
                Text(metadata.status)
                    .foregroundColor(CiderColors.secondary)
            }
            .font(CiderFont.micro)
            .lineLimit(1)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(CiderColors.surfaceInput.opacity(0.78)))

            if let readiness = metadata.readiness {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal")
                        .font(CiderFont.micro)
                    Text(readiness)
                }
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.controlAccent)
                .lineLimit(1)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(CiderColors.controlAccent.opacity(0.10)))
            }

            ForEach(metadata.chips, id: \.label) { chip in
                cardFaceChipView(chip, card: card)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func childProgressChip(_ summary: KanbanParentChildSummary) -> some View {
        HStack(spacing: Spacing.xxs) {
            ZStack {
                Circle()
                    .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
                    .frame(width: 12, height: 12)

                Circle()
                    .trim(from: 0, to: summary.totalCount == 0 ? 0 : CGFloat(summary.doneCount) / CGFloat(summary.totalCount))
                    .stroke(CiderColors.controlAccent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 12, height: 12)
            }

            Text(summary.progressText)
                .font(CiderFont.microMonospaced)
                .foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput.opacity(0.82))
        )
        .help(summary.compactText)
        .accessibilityLabel("Sub-issues \(summary.progressText), \(summary.compactText)")
    }

    private func displayKey(for card: KanbanCard) -> String {
        board?.displayKey(for: card) ?? card.displayKey ?? String(card.id.prefix(8)).uppercased()
    }

    private func cardAvatarPlaceholder(_ card: KanbanCard) -> some View {
        let label = card.agent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initials = label?.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return ZStack {
            Circle()
                .fill(label == nil ? CiderColors.surfaceInput : CiderColors.controlAccent.opacity(0.16))
                .frame(width: 18, height: 18)
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.controlAccent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .accessibilityLabel(label.map { "Assignee \($0)" } ?? "Unassigned")
    }

    private func hasCardFooter(_ card: KanbanCard) -> Bool {
        KanbanBoardLayout.testingOwnerBadge(for: card) != nil
            || (selectedDisplayProperties.contains(.labels) && !KanbanBoardLayout.cardFaceChips(for: card).isEmpty)
    }

    private func hasCardContext(parentBadge: KanbanParentBadge?, planIndicator: KanbanPlanIndicator?) -> Bool {
        parentBadge != nil || planIndicator != nil
    }

    @ViewBuilder
    private func cardContextView(
        parentBadge: KanbanParentBadge?,
        planIndicator: KanbanPlanIndicator?
    ) -> some View {
        if let parentBadge {
            parentBadgeView(parentBadge)
        } else if let planIndicator {
            planIndicatorView(planIndicator)
        }
    }

    private func cardFooterView(_ card: KanbanCard) -> some View {
        TagFlowLayout(spacing: Spacing.xs) {
            if let badge = KanbanBoardLayout.testingOwnerBadge(for: card) {
                testingOwnerBadgeView(badge)
            }
            if selectedDisplayProperties.contains(.labels) {
                ForEach(KanbanBoardLayout.cardFaceChips(for: card), id: \.label) { chip in
                    cardFaceChipView(chip, card: card)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cardFaceChipView(_ chip: KanbanCardFaceChip, card: KanbanCard) -> some View {
        switch chip.role {
        case .tagEdit:
            Button {
                beginTagEditing(card)
            } label: {
                cardFaceChipLabel(chip, color: CiderColors.tertiary, indicatorColor: CiderColors.controlAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add or change tags for \(card.title)")
            .popover(
                isPresented: Binding(
                    get: { tagEditorCardID == card.id },
                    set: { isPresented in
                        if !isPresented {
                            tagEditorCardID = nil
                            tagEditorDraft = ""
                        }
                    }
                ),
                arrowEdge: .bottom
            ) {
                cardFaceTagEditorPopover(card)
            }
        case .featureDomain:
            let filterID = KanbanCardTagTaxonomy.normalized(chip.label)
            let isSelected = selectedFeatureDomainFilter == filterID
            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                    selectedFeatureDomainFilter = isSelected ? nil : filterID
                }
            } label: {
                cardFaceChipLabel(
                    chip,
                    color: isSelected ? CiderColors.controlAccent : CiderColors.secondary,
                    indicatorColor: CiderColors.controlAccent
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter board by \(chip.label)")
        case .typeStatus:
            let color = cardFaceChipColor(for: chip)
            cardFaceChipLabel(chip, color: CiderColors.secondary, indicatorColor: color)
        case .attachment:
            cardFaceChipLabel(chip, color: CiderColors.secondary, indicatorColor: CiderColors.tertiary)
        }
    }

    private func beginTagEditing(_ card: KanbanCard) {
        tagEditorDraft = card.tags.joined(separator: ", ")
        tagEditorCardID = card.id
    }

    private func cardFaceTagEditorPopover(_ card: KanbanCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tag")
                    .foregroundColor(CiderColors.tertiary)
                Text("Edit tags")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer()
            }

            TextField("Tags, comma separated", text: $tagEditorDraft)
                .textFieldStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                )
                .onSubmit {
                    saveTagEditor(for: card)
                }

            TagFlowLayout(spacing: Spacing.xs) {
                ForEach(cardFaceSuggestedTags, id: \.self) { tag in
                    Button {
                        toggleTagEditorTag(tag)
                    } label: {
                        Text(KanbanCardTagTaxonomy.normalized(tag).split(separator: "-")
                            .map { part in
                                let lower = part.lowercased()
                                if lower == "ios" { return "iOS" }
                                if lower == "qa" { return "QA" }
                                guard let first = part.first else { return "" }
                                return first.uppercased() + part.dropFirst()
                            }
                            .joined(separator: " "))
                            .font(CiderFont.microSemibold)
                            .foregroundColor(tagEditorTags.contains(KanbanCardTagTaxonomy.normalized(tag)) ? CiderColors.controlAccent : CiderColors.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tagEditorTags.contains(KanbanCardTagTaxonomy.normalized(tag)) ? CiderColors.controlAccent.opacity(0.14) : CiderColors.surfaceInput)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Spacing.sm) {
                Button("Save") {
                    saveTagEditor(for: card)
                }
                .buttonStyle(CiderAccentButtonStyle())

                Button("Cancel") {
                    tagEditorCardID = nil
                    tagEditorDraft = ""
                }
                .buttonStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(width: 300)
    }

    private var tagEditorTags: Set<String> {
        Set(parsedTagEditorTags())
    }

    private func parsedTagEditorTags() -> [String] {
        tagEditorDraft
            .components(separatedBy: ",")
            .map { KanbanCardTagTaxonomy.normalized($0) }
            .filter { !$0.isEmpty }
    }

    private func toggleTagEditorTag(_ tag: String) {
        let normalized = KanbanCardTagTaxonomy.normalized(tag)
        guard !normalized.isEmpty else { return }
        var tags = parsedTagEditorTags()
        if tags.contains(normalized) {
            tags.removeAll { $0 == normalized }
        } else {
            tags.append(normalized)
        }
        tagEditorDraft = tags.joined(separator: ", ")
    }

    private func saveTagEditor(for card: KanbanCard) {
        storage.updateCardTags(boardID: boardID, cardID: card.id, tags: parsedTagEditorTags())
        tagEditorCardID = nil
        tagEditorDraft = ""
    }

    private func cardFaceChipLabel(_ chip: KanbanCardFaceChip, color: Color, indicatorColor: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            switch chip.accessory {
            case .none:
                EmptyView()
            case .featureIcon:
                Image(systemName: chip.iconSystemName ?? "cube.transparent")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(indicatorColor.opacity(0.85))
            case .colorDot:
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 5, height: 5)
            }

            Text(chip.label)
                .font(CiderFont.microSemibold)
                .foregroundColor(color)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func cardFaceChipColor(for chip: KanbanCardFaceChip) -> Color {
        switch chip.role {
        case .tagEdit:
            CiderColors.tertiary
        case .featureDomain:
            CiderColors.controlAccent
        case .typeStatus:
            cardFaceTypeIndicatorColor(for: chip.label)
        case .attachment:
            CiderColors.tertiary
        }
    }

    private func cardFaceTypeIndicatorColor(for label: String) -> Color {
        switch label.lowercased() {
        case "bug", "blocked":
            CiderColors.destructive
        case "performance":
            CiderColors.success
        case "test", "testing", "qa", "review", "needs qa":
            CiderColors.warning
        case "idea", "new", "inbox":
            CiderColors.controlAccent
        default:
            CiderColors.tertiary
        }
    }

    private func testingOwnerBadgeView(_ badge: KanbanTestingOwnerBadge) -> some View {
        let color = testingOwnerBadgeColor(for: badge.kind)
        return Text(badge.text)
            .font(CiderFont.micro)
            .foregroundColor(color)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: CiderBorder.hairlineStrokeWidth)
            )
    }

    private func testingOwnerBadgeColor(for kind: KanbanTestingOwnerBadge.Kind) -> Color {
        switch kind {
        case .needsErik: CiderColors.warning
        case .agentCanVerify: CiderColors.success
        }
    }

    private func parentBadgeView(_ badge: KanbanParentBadge) -> some View {
        Button {
            onOpenCard(boardID, badge.parentID)
        } label: {
            HStack(spacing: Spacing.xxs) {
                if let accentColor = badge.accentColor {
                    Circle()
                        .fill(kanbanColor(accentColor))
                        .frame(width: 5, height: 5)
                }

                Text(badge.displayKey)
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.tertiary)

                Text("›")
                    .foregroundColor(CiderColors.quaternary)

                Text(badge.title)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }
            .font(CiderFont.micro)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput.opacity(0.85))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open parent card \(badge.title)")
    }

    private func planIndicatorView(_ indicator: KanbanPlanIndicator) -> some View {
        Button {
            onOpenCard(boardID, indicator.parentID)
        } label: {
            HStack(spacing: Spacing.xxs) {
                if let accentColor = indicator.accentColor {
                    Circle()
                        .fill(kanbanColor(accentColor))
                        .frame(width: 5, height: 5)
                }

                Text(indicator.compactText)
                    .foregroundColor(indicator.isNextUp ? CiderColors.controlAccent : CiderColors.tertiary)

                Text(indicator.title)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }
            .font(CiderFont.micro)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(indicator.isNextUp ? CiderColors.accentSubtle : CiderColors.surfaceInput.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(indicator.isNextUp ? CiderColors.controlAccent.opacity(0.28) : Color.clear, lineWidth: CiderBorder.hairlineStrokeWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open plan \(indicator.title), \(indicator.compactText)")
    }

    private func cardDragPreview(_ card: KanbanCard) -> some View {
        Text(card.title)
            .font(CiderFont.label)
            .foregroundColor(CiderColors.primary)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceElevated)
            )
    }

    // MARK: - Header Quick Add

    private func quickAddPopover(column: KanbanColumn, board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Add to \(column.name)")
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.primary)

            TextField("Title", text: $quickAddDraft.title)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .onSubmit {
                    createQuickAddCard(columnID: column.id, openAfterCreate: false)
                }

            TextEditor(text: $quickAddDraft.notes)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.primary)
                .scrollContentBackground(.hidden)
                .frame(height: 76)
                .padding(Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                )

            HStack(spacing: Spacing.xs) {
                quickAddPriorityMenu
                quickAddColorMenu
            }

            TextField("Tags, comma separated", text: $quickAddDraft.tagsText)
                .textFieldStyle(.plain)
                .font(CiderFont.caption)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

            quickAddParentMenu(board: board)

            HStack(spacing: Spacing.sm) {
                Button("Create") {
                    createQuickAddCard(columnID: column.id, openAfterCreate: false)
                }
                .buttonStyle(CiderAccentButtonStyle())
                .disabled(!quickAddDraft.canCreate)

                Button("Create & Open") {
                    createQuickAddCard(columnID: column.id, openAfterCreate: true)
                }
                .buttonStyle(.plain)
                .font(CiderFont.captionSemibold)
                .foregroundColor(quickAddDraft.canCreate ? CiderColors.controlAccent : CiderColors.tertiary)
                .disabled(!quickAddDraft.canCreate)
                .keyboardShortcut(.return, modifiers: [.command])

                Spacer()

                Button("Cancel") {
                    quickAddColumnID = nil
                    quickAddDraft = KanbanQuickAddDraft()
                }
                .buttonStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.md)
        .frame(width: 300)
    }

    private var quickAddPriorityMenu: some View {
        Menu {
            Button("None") { quickAddDraft.priority = nil }
            Divider()
            ForEach(KanbanPriority.allCases, id: \.self) { priority in
                Button(priorityLabel(for: priority).0) {
                    quickAddDraft.priority = priority
                }
            }
        } label: {
            quickAddMenuLabel(
                title: quickAddDraft.priority.map { priorityLabel(for: $0).0 } ?? "Priority",
                systemImage: "flag"
            )
        }
        .buttonStyle(.plain)
    }

    private var quickAddColorMenu: some View {
        Menu {
            Button("None") { quickAddDraft.color = nil }
            Divider()
            ForEach(KanbanCardColor.allCases, id: \.self) { color in
                Button(color.rawValue.capitalized) {
                    quickAddDraft.color = color
                }
            }
        } label: {
            quickAddMenuLabel(
                title: quickAddDraft.color?.rawValue.capitalized ?? "Color",
                systemImage: "circle.fill",
                tint: quickAddDraft.color.map { kanbanColor($0) }
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAddParentMenu(board: KanbanBoard) -> some View {
        Menu {
            Button("No parent") { quickAddDraft.parentCardID = nil }
            Divider()
            ForEach(board.allCards, id: \.id) { card in
                Button {
                    quickAddDraft.parentCardID = card.id
                } label: {
                    Text(card.title)
                }
            }
        } label: {
            let parentTitle = quickAddDraft.parentCardID.flatMap { parentID in
                board.card(id: parentID)?.title
            }
            quickAddMenuLabel(
                title: parentTitle ?? "No parent",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAddMenuLabel(title: String, systemImage: String, tint: Color? = nil) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: systemImage)
                .foregroundColor(tint ?? CiderColors.tertiary)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
        }
        .font(CiderFont.caption)
        .foregroundColor(CiderColors.secondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func createQuickAddCard(columnID: String, openAfterCreate: Bool) {
        guard quickAddDraft.canCreate else { return }

        let created = storage.addCard(
            boardID: boardID,
            columnID: columnID,
            title: quickAddDraft.trimmedTitle,
            notes: quickAddDraft.trimmedNotes,
            priority: quickAddDraft.priority,
            color: quickAddDraft.color,
            tags: quickAddDraft.tags,
            parentCardID: quickAddDraft.parentCardID
        )

        let createdID = created?.id
        quickAddColumnID = nil
        quickAddDraft = KanbanQuickAddDraft()

        if openAfterCreate, let createdID {
            onOpenCard(boardID, createdID)
        }
    }

    // MARK: - Add Card

    private func addCardButton(columnID: String) -> some View {
        Button {
            addingCardToColumn = columnID
            newCardTitle = ""
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "plus")
                Text("Add card")
            }
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private func addCardField(columnID: String) -> some View {
        VStack(spacing: Spacing.xs) {
            TextField("Card title...", text: $newCardTitle)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceElevated)
                )
                .onSubmit {
                    let trimmed = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = withAnimation(reduceMotion ? .none : .spring) {
                            storage.addCard(boardID: boardID, columnID: columnID, title: trimmed)
                        }
                    }
                    newCardTitle = ""
                    addingCardToColumn = nil
                }

            HStack {
                Button("Add") {
                    let trimmed = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = withAnimation(reduceMotion ? .none : .spring) {
                            storage.addCard(boardID: boardID, columnID: columnID, title: trimmed)
                        }
                    }
                    newCardTitle = ""
                    addingCardToColumn = nil
                }
                .buttonStyle(.plain)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.controlAccent)

                Spacer()

                Button("Cancel") {
                    addingCardToColumn = nil
                    newCardTitle = ""
                }
                .buttonStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.xs)
        }
    }

    // MARK: - Helpers

    private func kanbanColor(_ color: KanbanCardColor) -> Color {
        switch color {
        case .blue:
            Color(
                hue: KanbanDesign.kanbanBlueAccentHueDegrees / 360,
                saturation: KanbanDesign.kanbanAccentSaturation,
                brightness: KanbanDesign.kanbanAccentBrightness
            )
        case .green: CiderColors.success
        case .orange: CiderColors.warning
        case .red: CiderColors.destructive
        case .purple:
            Color(
                hue: KanbanDesign.kanbanPurpleAccentHueDegrees / 360,
                saturation: KanbanDesign.kanbanAccentSaturation,
                brightness: KanbanDesign.kanbanAccentBrightness
            )
        }
    }

    private func priorityBadge(_ priority: KanbanPriority) -> some View {
        let (text, color) = priorityLabel(for: priority)
        return Text(text)
            .font(CiderFont.micro)
            .foregroundColor(color)
    }

    private func priorityLabel(for priority: KanbanPriority) -> (String, Color) {
        switch priority {
        case .high: ("High", CiderColors.destructive)
        case .medium: ("Med", CiderColors.warning)
        case .low: ("Low", CiderColors.tertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "square.split.2x1")
                .font(CiderFont.settingsEmptyIcon)
                .foregroundColor(CiderColors.quaternary)
            Text("Board not found")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

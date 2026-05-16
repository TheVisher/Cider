import Foundation

enum HomeTelemetryMetricKind: String, CaseIterable, Equatable {
    case bookmarks
    case notes
    case todos
    case events
    case unfiled
    case urgent

    var title: String {
        switch self {
        case .bookmarks: "Bookmarks"
        case .notes: "Notes"
        case .todos: "Todos"
        case .events: "Events"
        case .unfiled: "Unfiled"
        case .urgent: "Urgent"
        }
    }
}

enum HomeOverviewActionTarget: Equatable {
    case inbox
    case savedView(name: String, filterSpec: SavedViewFilterSpec, sortMode: LibrarySortMode)
}

struct HomeTelemetryMetric: Equatable, Identifiable {
    let kind: HomeTelemetryMetricKind
    let value: Int
    let target: HomeOverviewActionTarget

    var id: HomeTelemetryMetricKind { kind }
}

struct HomeOverviewChip: Equatable, Identifiable {
    let id: String
    let title: String
    let value: Int
    let target: HomeOverviewActionTarget
}

struct HomeAttentionMetric: Equatable, Identifiable {
    let id: String
    let title: String
    let value: Int
    let target: HomeOverviewActionTarget
}

enum HomeDailyBriefGreetingBucket: Equatable {
    case morning
    case afternoon
    case evening
    case lateNight
}

enum HomeDailyBriefTarget: Equatable {
    case item(LibraryItemV2)
    case action(HomeOverviewActionTarget)
}

struct HomeDailyBriefItem: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let target: HomeDailyBriefTarget
    var surfacingExplanation: CiderSurfacingExplanation? = nil

    var visibleWhyLine: String? {
        surfacingExplanation.map { "Why: \(Self.sentenceCased($0.reason))" }
    }

    var visibleNextActionLine: String? {
        surfacingExplanation.map { "Next: \($0.suggestedAction)" }
    }

    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

struct HomeDailyBriefSummaryChip: Equatable, Identifiable {
    let id: String
    let label: String
    let target: HomeOverviewActionTarget
}

struct HomeDailyBriefSummaryPart: Equatable, Identifiable {
    let id: String
    let text: String
    let chip: HomeDailyBriefSummaryChip?
}

struct HomeDailyBrief: Equatable {
    let dateLabel: String
    let greetingBucket: HomeDailyBriefGreetingBucket
    let summary: String
    let summaryParts: [HomeDailyBriefSummaryPart]
    let focusItems: [HomeDailyBriefItem]
}

struct HomeOverviewClosedTabSummary: Equatable, Identifiable {
    let id: UUID
    let name: String
    let kind: SavedViewKind
    let updatedAt: Date
}

struct HomeTriageItem: Equatable, Identifiable {
    let id: String
    let item: LibraryItemV2
    let reason: String
    let suggestedAction: String
    let confidenceLabel: String
}

struct HomeRecentCaptureItem: Equatable, Identifiable {
    let id: String
    let item: LibraryItemV2
    let title: String
    let typeLabel: String
    let sourceTypeLabel: String
    let itemTypeLabel: String
    let locationLabel: String
    let destinationLabel: String
    let reviewState: String
    let reviewNeeded: Bool
    let suggestedAction: String
    let safeFollowUpActions: [String]
    let surfacingExplanation: CiderSurfacingExplanation

    var reviewStateLabel: String {
        reviewState
            .split(separator: "_")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }

    var visibleWhyLine: String {
        "Why: \(surfacingExplanation.reason)"
    }

    var visibleNextActionLine: String {
        "Next: \(surfacingExplanation.suggestedAction)"
    }

    var visibleSafeFollowUpLine: String {
        "Safe: \(safeFollowUpActions.prefix(3).joined(separator: ", "))"
    }
}

struct HomeReviewCockpitDateSuggestionApproval: Equatable {
    let bookmarkID: UUID
    let suggestionIndex: Int
    let suggestionKey: String
    let destination: LibraryEntityType
}

struct HomeReviewCockpitItem: Equatable, Identifiable {
    let id: String
    let sourceReviewID: String
    let itemID: UUID
    let itemType: String
    let item: LibraryItemV2?
    let title: String
    let kindLabel: String
    let reason: String
    let suggestedAction: String
    let reviewStateLabel: String
    let confidenceLabel: String?
    let targetLabel: String?
    let sourceLabel: String
    let canApprove: Bool
    let canCorrect: Bool
    let canDefer: Bool
    let safeActions: [String]
    let dateSuggestionApproval: HomeReviewCockpitDateSuggestionApproval?
}

struct HomeReviewCockpitBadge: Equatable, Identifiable {
    let id: String
    let label: String
    let value: Int
}

struct HomeReviewCockpitGroup: Equatable, Identifiable {
    let id: String
    let label: String
    let reviewState: String
    let requiredSafeAction: String
    let itemType: String
    let count: Int
    let sampleTitles: [String]
}

struct HomeReviewCockpitLane: Equatable, Identifiable {
    let id: String
    let title: String
    let count: Int
    let actionLabel: String
    let sampleTitles: [String]
    let keepsRoutingSeparate: Bool
}

struct HomeReviewCockpitBatchEnrichmentPreview: Equatable {
    let action: String
    let isMutating: Bool
    let candidateCount: Int
    let candidateSampleLimit: Int
    let candidateSampleTitles: [String]
    let excludedCount: Int
    let exclusionsByReason: [String: Int]
}

struct HomeReviewCockpitBatchEnrichmentControlPresentation: Equatable {
    let accessibilityLabel: String
    let help: String
    let statusLine: String
    let systemImage: String
    let isEnabled: Bool
}

struct HomeReviewCockpitSummary: Equatable {
    let totalCount: Int
    let badges: [HomeReviewCockpitBadge]
    let itemTypeCounts: [String: Int]
    let reviewStateCounts: [String: Int]
    let safeActionCounts: [String: Int]
    let groups: [HomeReviewCockpitGroup]
    let batchEnrichmentPreview: HomeReviewCockpitBatchEnrichmentPreview
    let generatedAt: Date
}

extension HomeReviewCockpitSummary {
    var visibleLanes: [HomeReviewCockpitLane] {
        groups.map { group in
            HomeReviewCockpitLane(
                id: group.id,
                title: group.label,
                count: group.count,
                actionLabel: HomeReviewCockpitSummary.actionLabel(for: group.requiredSafeAction),
                sampleTitles: group.sampleTitles,
                keepsRoutingSeparate: group.requiredSafeAction == "enrich"
            )
        }
    }

    private static func actionLabel(for action: String) -> String {
        switch action {
        case "approve": return "Approve"
        case "correct": return "Correct"
        case "defer": return "Defer"
        case "enrich": return "Enrich"
        case "open": return "Open"
        default:
            return action
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

extension HomeReviewCockpitBatchEnrichmentPreview {
    var canRunExplicitBatchAction: Bool {
        action == "review.enrich" && candidateCount > 0
    }

    var primaryActionTitle: String {
        "Enrich \(candidateCount) \(candidateCount == 1 ? "bookmark" : "bookmarks")"
    }

    var previewDetailLine: String {
        guard candidateSampleTitles.isEmpty == false else {
            return "No preview samples"
        }
        return "Preview sample: \(candidateSampleTitles.prefix(3).joined(separator: ", "))"
    }

    var exclusionDetailLine: String? {
        guard excludedCount > 0 else { return nil }
        if exclusionsByReason.count == 1,
           let reason = exclusionsByReason.first {
            return "\(reason.value) \(exclusionLabel(for: reason.key, count: reason.value))"
        }

        let reasonLabels = exclusionsByReason
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \(exclusionLabel(for: $0.key, count: $0.value))" }
            .joined(separator: ", ")
        return "\(excludedCount) excluded: \(reasonLabels)"
    }

    private func exclusionLabel(for reason: String, count: Int) -> String {
        switch reason {
        case "routing_requires_explicit_approval":
            return count == 1 ? "routing item requires explicit approval" : "routing items require explicit approval"
        case "manual_routing_required":
            return count == 1 ? "item needs manual routing" : "items need manual routing"
        case "unsupported_item_type":
            return count == 1 ? "item has unsupported type" : "items have unsupported types"
        case "not_enrichment_candidate":
            return count == 1 ? "item is not an enrichment candidate" : "items are not enrichment candidates"
        default:
            return reason
        }
    }

    func controlPresentation(
        isConfirming: Bool,
        scheduledCount: Int?
    ) -> HomeReviewCockpitBatchEnrichmentControlPresentation {
        if let scheduledCount {
            let scheduledTitle = "Scheduled enrichment for \(scheduledCount) \(scheduledCount == 1 ? "bookmark" : "bookmarks")"
            return HomeReviewCockpitBatchEnrichmentControlPresentation(
                accessibilityLabel: scheduledTitle,
                help: scheduledTitle,
                statusLine: "\(scheduledTitle). Routing items were not changed.",
                systemImage: "checkmark.circle.fill",
                isEnabled: false
            )
        }

        if isConfirming {
            let confirmTitle = "Confirm enrichment for \(candidateCount) \(candidateCount == 1 ? "bookmark" : "bookmarks")"
            return HomeReviewCockpitBatchEnrichmentControlPresentation(
                accessibilityLabel: confirmTitle,
                help: "\(confirmTitle). Routing items are excluded.",
                statusLine: exclusionDetailLine ?? previewDetailLine,
                systemImage: "checkmark.circle",
                isEnabled: canRunExplicitBatchAction
            )
        }

        let reviewTitle = "Review \(candidateCount) bookmark \(candidateCount == 1 ? "enrichment" : "enrichments")"
        return HomeReviewCockpitBatchEnrichmentControlPresentation(
            accessibilityLabel: reviewTitle,
            help: "\(reviewTitle) before scheduling",
            statusLine: previewDetailLine,
            systemImage: "sparkles",
            isEnabled: canRunExplicitBatchAction
        )
    }
}

struct HomeKanbanPulseItem: Equatable, Identifiable {
    let id: String
    let boardID: String
    let boardName: String
    let cardID: String
    let title: String
    let statusLabel: String
    let parentTitle: String?
    let suggestedAction: String
    let priority: Int
}

struct HomeOverviewSnapshot: Equatable {
    let telemetry: [HomeTelemetryMetric]
    let dailyBrief: HomeDailyBrief
    let pulse: String
    let overviewSummary: String
    let overviewChips: [HomeOverviewChip]
    let attentionMetrics: [HomeAttentionMetric]
    let recentItems: [LibraryItemV2]
    let recentCaptureItems: [HomeRecentCaptureItem]
    let upcomingItems: [LibraryItemV2]
    let todoItems: [TodoCard]
    let completedTodoItems: [TodoCard]
    let resurfacedItems: [LibraryItemV2]
    let reviewCockpitItems: [HomeReviewCockpitItem]
    let reviewCockpitSummary: HomeReviewCockpitSummary
    let triageItems: [HomeTriageItem]
    let kanbanPulseItems: [HomeKanbanPulseItem]
    let closedTabs: [HomeOverviewClosedTabSummary]
}

enum HomeOverviewPanelID {
    case dailyBrief
    case pulse
    case overview
    case profile
    case activityTimeline
    case recentActivity
    case upcoming
    case kanbanPulse
    case todos
    case triage
    case resurface
    case closedTabs
}

struct HomeOverviewLayoutMetrics {
    let snapshot: HomeOverviewSnapshot

    func requiredHeight(for panel: HomeOverviewPanelID) -> CGFloat {
        switch panel {
        case .dailyBrief:
            return HomeOverviewDesign.fullLayoutTopRowHeight
        case .pulse:
            return HomeOverviewDesign.topRowMinHeight
        case .overview:
            return HomeOverviewDesign.overviewPanelFixedHeight
        case .profile:
            return HomeOverviewDesign.profilePanelFixedHeight
        case .activityTimeline:
            return HomeOverviewDesign.activityTimelinePanelHeight
        case .recentActivity:
            return max(
                HomeOverviewDesign.recentActivityBaseHeight,
                88 + (CGFloat(max(snapshot.recentCaptureItems.count, 1)) * HomeOverviewDesign.recentActivityRowHeightEstimate)
            )
        case .upcoming:
            return HomeOverviewDesign.upcomingPanelFixedHeight
        case .kanbanPulse:
            return HomeOverviewDesign.resurfacePanelMinHeight
        case .todos:
            return HomeOverviewDesign.resurfacePanelMinHeight
        case .triage:
            return HomeOverviewDesign.resurfacePanelMinHeight
        case .resurface:
            let visibleCardCount = min(snapshot.resurfacedItems.count, 2)
            let rowCount = CGFloat(max((visibleCardCount + 1) / 2, 1))
            return max(
                HomeOverviewDesign.resurfacePanelMinHeight,
                96 + (rowCount * HomeOverviewDesign.resurfacePanelRowHeightEstimate)
            )
        case .closedTabs:
            return snapshot.closedTabs.isEmpty
                ? HomeOverviewDesign.closedTabsBaseMinHeight
                : HomeOverviewDesign.closedTabsPanelMinHeight
        }
    }

    var topRowHeight: CGFloat {
        max(
            requiredHeight(for: .pulse),
            requiredHeight(for: .overview),
            requiredHeight(for: .profile)
        )
    }

    var activityRowHeight: CGFloat {
        max(
            requiredHeight(for: .recentActivity),
            requiredHeight(for: .upcoming)
        )
    }

    var bottomRowHeight: CGFloat {
        max(
            requiredHeight(for: .resurface),
            requiredHeight(for: .closedTabs)
        )
    }
}

struct HomeOverviewFullLayoutTracks {
    let first: CGFloat
    let second: CGFloat
    let third: CGFloat
    let fourth: CGFloat
    let gap: CGFloat

    init(availableWidth: CGFloat, gap: CGFloat = HomeOverviewDesign.columnSpacing) {
        let usableWidth = max(0, availableWidth - (gap * 3))
        let totalWeight = HomeOverviewDesign.fullLayoutTrackWeights.reduce(0, +)
        let widths = HomeOverviewDesign.fullLayoutTrackWeights.map { weight in
            usableWidth * (weight / totalWeight)
        }

        self.first = widths[safe: 0] ?? 0
        self.second = widths[safe: 1] ?? 0
        self.third = widths[safe: 2] ?? 0
        self.fourth = widths[safe: 3] ?? 0
        self.gap = gap
    }

    var pulseWidth: CGFloat { first }
    var overviewWidth: CGFloat { second + gap + third }
    var attentionWidth: CGFloat { fourth }
    var recentWidth: CGFloat { first + gap + second }
    var upcomingWidth: CGFloat { third + gap + fourth }
    var captureTimelineWidth: CGFloat { first + gap + second + gap + third }
    var continueWidth: CGFloat { fourth }
    var resurfaceWidth: CGFloat { first }
    var pinnedWidth: CGFloat { second + gap + third + gap + fourth }
}

private extension Array where Element == CGFloat {
    subscript(safe index: Int) -> CGFloat? {
        indices.contains(index) ? self[index] : nil
    }
}

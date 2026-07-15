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
    case review
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
    let expectedUpdatedAt: Date
    let exactEvidence: CiderBookmarkDateSuggestion
}

enum HomeReviewCockpitAction: String, Equatable, Identifiable {
    case accept
    case reject
    case deferReview = "defer"
    case openSource
    case correctRoute
    case createDateCard
    case createTodo

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .accept: return "checkmark.circle"
        case .reject: return "xmark.circle"
        case .deferReview: return "clock"
        case .openSource: return "arrow.up.right.square"
        case .correctRoute: return "folder.badge.gearshape"
        case .createDateCard: return "calendar.badge.plus"
        case .createTodo: return "checklist"
        }
    }

    func buttonTitle(for item: HomeReviewCockpitItem) -> String {
        switch self {
        case .accept:
            return item.kindLabel == "Graph Candidate" ? "Accept relation" : "Accept"
        case .reject:
            return "Reject"
        case .deferReview:
            return "Defer"
        case .openSource:
            if item.kindLabel == "Graph Candidate", item.canApprove == false {
                return "Resolve target"
            }
            return "Open source"
        case .correctRoute:
            return "Correct destination"
        case .createDateCard:
            return "Create Date Card"
        case .createTodo:
            return "Create Todo"
        }
    }

    func helpLabel(for item: HomeReviewCockpitItem) -> String {
        switch self {
        case .accept:
            if item.kindLabel == "Memory Candidate" { return "Accept memory" }
            if item.kindLabel == "Graph Candidate" { return "Accept graph candidate" }
            return "Approve review"
        case .reject:
            return "Reject suggestion"
        case .deferReview:
            return "Defer for later"
        case .openSource:
            if item.kindLabel == "Memory Candidate" || item.kindLabel == "Graph Candidate" {
                return "Open source evidence"
            }
            return item.dateSuggestionApproval == nil ? "Open source item" : "Open bookmark details"
        case .correctRoute:
            return "Choose an exact existing destination"
        case .createDateCard:
            return "Approve to the explicit Date Card destination"
        case .createTodo:
            return "Approve to the explicit Todo destination"
        }
    }

    var coordinatorAction: CiderReviewAction? {
        switch self {
        case .accept, .createDateCard, .createTodo: .approve
        case .reject: .reject
        case .deferReview: .defer
        case .openSource: nil
        case .correctRoute: .correct
        }
    }
}

enum HomeReviewActionResult: Equatable {
    case succeeded
    case failed(message: String)

    var succeeded: Bool {
        if case .succeeded = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

struct HomeReviewActionState: Equatable {
    private(set) var resolvedReviewIDs: Set<String> = []
    private(set) var pendingReviewIDs: Set<String> = []
    private(set) var actionErrors: [String: String] = [:]

    mutating func begin(rowID: String) {
        pendingReviewIDs.insert(rowID)
        actionErrors[rowID] = nil
    }

    mutating func reconcile(rowID: String, result: HomeReviewActionResult) {
        pendingReviewIDs.remove(rowID)
        if result.succeeded {
            resolvedReviewIDs.insert(rowID)
            actionErrors[rowID] = nil
        } else {
            resolvedReviewIDs.remove(rowID)
            actionErrors[rowID] = result.errorMessage
        }
    }

    func errorMessage(for rowID: String) -> String? {
        actionErrors[rowID]
    }
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
    let reviewActions: [HomeReviewCockpitAction]
    let candidateID: String?
    let candidateRef: String?
    let candidateExpectedReviewState: String?
    let candidateUpdatedAt: Date?
    let routingDestination: CiderRoutingDecisionTarget?
    let sourceQuote: String?
    let sourceProvenanceLabel: String?
    let memoryKind: String?
    let linkedOwnerRefs: [String]
    let possibleTypeLabels: [String]
    let possibleRelationLabels: [String]
    let candidateActionLabels: [String]
    let confidenceReason: String?
    let truthState: String?
    let extractionReason: String?
    let proposedChangeLabel: String?
    let storageLabel: String?
    let candidateQualityLevel: String?
    let candidateQualityFlags: [String]
    let candidateQualityExplanation: String?

    init(
        id: String,
        sourceReviewID: String,
        itemID: UUID,
        itemType: String,
        item: LibraryItemV2?,
        title: String,
        kindLabel: String,
        reason: String,
        suggestedAction: String,
        reviewStateLabel: String,
        confidenceLabel: String?,
        targetLabel: String?,
        sourceLabel: String,
        canApprove: Bool,
        canCorrect: Bool,
        canDefer: Bool,
        safeActions: [String],
        dateSuggestionApproval: HomeReviewCockpitDateSuggestionApproval?,
        reviewActions: [HomeReviewCockpitAction] = [],
        candidateID: String? = nil,
        candidateRef: String? = nil,
        candidateExpectedReviewState: String? = nil,
        candidateUpdatedAt: Date? = nil,
        routingDestination: CiderRoutingDecisionTarget? = nil,
        sourceQuote: String? = nil,
        sourceProvenanceLabel: String? = nil,
        memoryKind: String? = nil,
        linkedOwnerRefs: [String] = [],
        possibleTypeLabels: [String] = [],
        possibleRelationLabels: [String] = [],
        candidateActionLabels: [String] = [],
        confidenceReason: String? = nil,
        truthState: String? = nil,
        extractionReason: String? = nil,
        proposedChangeLabel: String? = nil,
        storageLabel: String? = nil,
        candidateQualityLevel: String? = nil,
        candidateQualityFlags: [String] = [],
        candidateQualityExplanation: String? = nil
    ) {
        self.id = id
        self.sourceReviewID = sourceReviewID
        self.itemID = itemID
        self.itemType = itemType
        self.item = item
        self.title = title
        self.kindLabel = kindLabel
        self.reason = reason
        self.suggestedAction = suggestedAction
        self.reviewStateLabel = reviewStateLabel
        self.confidenceLabel = confidenceLabel
        self.targetLabel = targetLabel
        self.sourceLabel = sourceLabel
        self.canApprove = canApprove
        self.canCorrect = canCorrect
        self.canDefer = canDefer
        self.safeActions = safeActions
        self.dateSuggestionApproval = dateSuggestionApproval
        self.reviewActions = reviewActions
        self.candidateID = candidateID
        self.candidateRef = candidateRef
        self.candidateExpectedReviewState = candidateExpectedReviewState
        self.candidateUpdatedAt = candidateUpdatedAt
        self.routingDestination = routingDestination
        self.sourceQuote = sourceQuote
        self.sourceProvenanceLabel = sourceProvenanceLabel
        self.memoryKind = memoryKind
        self.linkedOwnerRefs = linkedOwnerRefs
        self.possibleTypeLabels = possibleTypeLabels
        self.possibleRelationLabels = possibleRelationLabels
        self.candidateActionLabels = candidateActionLabels
        self.confidenceReason = confidenceReason
        self.truthState = truthState
        self.extractionReason = extractionReason
        self.proposedChangeLabel = proposedChangeLabel
        self.storageLabel = storageLabel
        self.candidateQualityLevel = candidateQualityLevel
        self.candidateQualityFlags = candidateQualityFlags
        self.candidateQualityExplanation = candidateQualityExplanation
    }
}

extension HomeReviewCockpitItem {
    var sourceEvidenceFindQuery: String? {
        sourceEvidenceFindQueries.first
    }

    var sourceEvidenceFindQueries: [String] {
        guard let sourceQuote else { return [] }
        var normalized = sourceQuote
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let evidencePreambles = [
            #"(?i)^daily\s+journal\s+source\s+says\s+"#,
            #"(?i)^journal\s+source\s+says\s+"#,
            #"(?i)^journal\s+note\s+says\s+"#,
            #"(?i)^source\s+says\s+"#,
        ]
        for preamble in evidencePreambles {
            normalized = normalized.replacingOccurrences(
                of: preamble,
                with: "",
                options: .regularExpression
            )
        }
        normalized = Self.stripMarkdownLinePrefix(from: normalized)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        var queries: [String] = []
        Self.appendUnique(normalized, to: &queries)

        let quotedPhrasePattern = #"[“”"]([^“”"]{3,})[“”"]"#
        if let regex = try? NSRegularExpression(pattern: quotedPhrasePattern) {
            let nsNormalized = normalized as NSString
            let range = NSRange(location: 0, length: nsNormalized.length)
            for match in regex.matches(in: normalized, range: range) {
                guard match.numberOfRanges > 1 else { continue }
                let phrase = nsNormalized.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                Self.appendUnique(phrase, to: &queries)
            }
        }

        let titleCandidate = Self.stripMarkdownLinePrefix(from: title)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        if titleCandidate.count >= 4 {
            Self.appendUnique(titleCandidate, to: &queries)
        }

        return queries
    }

    func bestSourceEvidenceFindQuery(in sourceText: String) -> String? {
        let normalizedSource = Self.normalizedComparableText(sourceText)
        return sourceEvidenceFindQueries.first { query in
            normalizedSource.localizedCaseInsensitiveContains(Self.normalizedComparableText(query))
        } ?? sourceEvidenceFindQuery
    }

    private static func stripMarkdownLinePrefix(from value: String) -> String {
        value.replacingOccurrences(
            of: #"^\s*(?:[-+*]|\d+[.)])\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func normalizedComparableText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendUnique(_ value: String, to queries: inout [String]) {
        let normalized = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        guard queries.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) == false else { return }
        queries.append(normalized)
    }

    var detailExtractedValueLabel: String {
        if let proposedChangeLabel { return proposedChangeLabel }
        if kindLabel == "Graph Candidate" {
            let relation = possibleRelationLabels.first ?? "mentions"
            let typeSuffix = possibleTypeLabels.isEmpty ? "" : " (\(possibleTypeLabels.joined(separator: ", ")))"
            return "Proposes \(relation) → \(title)\(typeSuffix)"
        }
        return targetLabel ?? reason
    }

    var acceptanceEffectLabel: String? {
        switch kindLabel {
        case "Graph Candidate":
            let relation = possibleRelationLabels.first ?? "mentions"
            if canApprove {
                return "Accepting will add a \(relation) relation from this source note to the resolved graph target."
            }
            return "Resolve or create the target object before accepting; then Cider will add a \(relation) relation from this source note to that object."
        case "Memory Candidate":
            return "Accepting will mark this source-backed memory candidate as approved for promotion."
        default:
            return nil
        }
    }

    var detailOwnerRefsLabel: String? {
        guard linkedOwnerRefs.isEmpty == false else { return nil }
        return linkedOwnerRefs.joined(separator: ", ")
    }

    var detailCorrectionActionLabel: String? {
        switch kindLabel {
        case "Memory Candidate":
            return "Edit value"
        case "Graph Candidate":
            return canApprove ? "Inspect relation" : "Resolve / correct target"
        default:
            return canCorrect ? "Correct source" : nil
        }
    }

    var detailCorrectionHelp: String? {
        guard let actionLabel = detailCorrectionActionLabel else { return nil }
        switch kindLabel {
        case "Memory Candidate":
            return "\(actionLabel) from the source evidence"
        case "Graph Candidate":
            return "\(actionLabel) before accepting this graph relation"
        default:
            return "\(actionLabel) for this review item"
        }
    }
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
        requiredHeight(for: .resurface)
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
    var resurfaceWidth: CGFloat { first }
    var pinnedWidth: CGFloat { second + gap + third + gap + fourth }
}

private extension Array where Element == CGFloat {
    subscript(safe index: Int) -> CGFloat? {
        indices.contains(index) ? self[index] : nil
    }
}

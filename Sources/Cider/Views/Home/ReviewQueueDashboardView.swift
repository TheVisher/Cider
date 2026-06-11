import SwiftUI

struct ReviewQueueDashboardView: View {
    let items: [HomeReviewCockpitItem]
    let summary: HomeReviewCockpitSummary
    let onOpenItem: (LibraryItemV2) -> Void
    let onPerformReviewAction: (HomeReviewCockpitItem, HomeReviewCockpitAction) -> Bool
    let onEnrichReviewBatch: () -> Bool

    @State private var resolvedReviewIDs: Set<String> = []
    @State private var batchEnrichmentIsConfirming = false
    @State private var scheduledBatchEnrichmentCount: Int?
    @State private var selectedLaneLabel: String?
    @State private var selectedDetailItemID: String?

    private var visibleItems: [HomeReviewCockpitItem] {
        items.filter { item in
            guard resolvedReviewIDs.contains(item.id) == false else { return false }
            guard let selectedLaneLabel else { return true }
            return item.kindLabel == selectedLaneLabel
        }
    }

    private var selectedDetailItem: HomeReviewCockpitItem? {
        guard let selectedDetailItemID else { return nil }
        return visibleItems.first { $0.id == selectedDetailItemID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                summaryBand
                lanesBand
                batchControlBand
                itemsBand
            }
            .frame(maxWidth: HomeOverviewDesign.maxContentWidth, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, HomeOverviewDesign.telemetryTopPadding)
            .padding(.bottom, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var summaryBand: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Review Queue")
                    .font(CiderFont.displayBold)
                    .foregroundColor(CiderColors.primary)
                Spacer()
                Text("\(summary.totalCount)")
                    .font(CiderFont.monospacedBody)
                    .foregroundColor(CiderColors.secondary)
            }

            Text("Routing, enrichment, duplicate, inbox, date-suggestion, and source-backed memory/graph candidates that need explicit review.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)

            if summary.badges.isEmpty {
                Text("No review work is waiting.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                TagFlowLayout(spacing: Spacing.sm) {
                    ForEach(summary.badges) { badge in
                        HStack(spacing: Spacing.xs) {
                            Text("\(badge.value)")
                                .font(CiderFont.labelSemibold)
                            Text(badge.label)
                                .font(CiderFont.captionMedium)
                        }
                        .foregroundColor(CiderColors.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.surfaceInput)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
    }

    private var lanesBand: some View {
        HomeOverviewPanel(title: "Reason Families") {
            let lanes = summary.visibleLanes
            if lanes.isEmpty {
                Text("No grouped review reasons yet.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm)],
                    spacing: Spacing.sm
                ) {
                    ForEach(lanes) { lane in
                        laneCard(lane)
                    }
                }
            }
        }
    }

    private func laneCard(_ lane: HomeReviewCockpitLane) -> some View {
        let isSelected = selectedLaneLabel == lane.title
        return Button {
            selectedLaneLabel = isSelected ? nil : lane.title
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(lane.title)
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)
                    Spacer()
                    Text("\(lane.count)")
                        .font(CiderFont.monospacedBody)
                        .foregroundColor(CiderColors.secondary)
                }
                Text(lane.actionLabel)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                ForEach(lane.sampleTitles.prefix(3), id: \.self) { title in
                    Text(title)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.surfaceElevated : CiderColors.surfaceInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(isSelected ? CiderColors.controlAccent : CiderColors.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Show all review items" : "Show \(lane.title) items")
        .accessibilityLabel(isSelected ? "Show all review items" : "Show \(lane.title) items")
    }

    @ViewBuilder
    private var batchControlBand: some View {
        let preview = summary.batchEnrichmentPreview
        if preview.candidateCount > 0 || preview.excludedCount > 0 {
            HomeOverviewPanel(title: "Batch Enrichment") {
                let presentation = preview.controlPresentation(
                    isConfirming: batchEnrichmentIsConfirming,
                    scheduledCount: scheduledBatchEnrichmentCount
                )
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Button {
                        if batchEnrichmentIsConfirming {
                            if onEnrichReviewBatch() {
                                scheduledBatchEnrichmentCount = preview.candidateCount
                            }
                        } else {
                            batchEnrichmentIsConfirming = true
                        }
                    } label: {
                        Image(systemName: presentation.systemImage)
                            .frame(width: Spacing.xl, height: Spacing.xl)
                    }
                    .buttonStyle(.plain)
                    .disabled(!presentation.isEnabled)
                    .help(presentation.help)
                    .accessibilityLabel(presentation.accessibilityLabel)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(preview.primaryActionTitle)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                        Text(presentation.statusLine)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
            }
        }
    }

    private var itemsBand: some View {
        HomeOverviewPanel(title: selectedLaneLabel.map { "Items: \($0)" } ?? "Items") {
            if visibleItems.isEmpty {
                Text("Nothing is waiting in the visible review queue.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let selectedDetailItem {
                        candidateDetailPanel(selectedDetailItem)
                        Divider()
                            .background(CiderColors.separator)
                    }
                    ForEach(visibleItems) { item in
                        reviewRow(item)
                        if item.id != visibleItems.last?.id {
                            Divider()
                                .background(CiderColors.separator)
                        }
                    }
                }
            }
        }
    }

    private func candidateDetailPanel(_ reviewItem: HomeReviewCockpitItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Candidate Detail")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)
                    Text("\(reviewItem.kindLabel) • \(reviewItem.sourceLabel)")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                }
                Spacer()
                Button {
                    selectedDetailItemID = nil
                } label: {
                    Image(systemName: "xmark.circle")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Close candidate detail")
                .accessibilityLabel("Close candidate detail")
            }

            detailLine(title: "Extracted value / relation", value: reviewItem.detailExtractedValueLabel)
            if let sourceQuote = reviewItem.sourceQuote, sourceQuote.isEmpty == false {
                detailLine(title: "Source quote", value: sourceQuote)
            }
            if let ownerRefs = reviewItem.detailOwnerRefsLabel {
                detailLine(title: "Linked owner refs", value: ownerRefs)
            }
            if let confidenceLabel = reviewItem.confidenceLabel {
                detailLine(title: "Confidence", value: confidenceLabel)
            }
            if let candidateRef = reviewItem.candidateRef {
                detailLine(title: "Candidate ref", value: candidateRef)
            }

            HStack(spacing: Spacing.xs) {
                ForEach(reviewItem.reviewActions) { action in
                    reviewActionButton(action, for: reviewItem)
                }
                if let correctionLabel = reviewItem.detailCorrectionActionLabel,
                   let item = reviewItem.item {
                    Button(correctionLabel) {
                        onOpenItem(item)
                    }
                    .buttonStyle(.borderless)
                    .help(reviewItem.detailCorrectionHelp ?? correctionLabel)
                    .accessibilityLabel(correctionLabel)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(CiderColors.controlAccent.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func detailLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)
            Text(value)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewRow(_ reviewItem: HomeReviewCockpitItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Button {
                if let item = reviewItem.item {
                    onOpenItem(item)
                }
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(reviewItem.title)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                    Text(reviewItem.reason)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                    if let sourceQuote = reviewItem.sourceQuote, !sourceQuote.isEmpty {
                        Text(sourceQuote)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(2)
                    }
                    Text("\(reviewItem.suggestedAction) • \(reviewItem.sourceLabel) • \(reviewItem.targetLabel ?? reviewItem.reviewStateLabel)")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(reviewItem.item == nil)

            HStack(spacing: Spacing.xxs) {
                Button {
                    selectedDetailItemID = reviewItem.id
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Show candidate detail")
                .accessibilityLabel("Show candidate detail")

                ForEach(reviewItem.reviewActions) { action in
                    reviewActionButton(action, for: reviewItem)
                }
            }
            .font(CiderFont.captionSemibold)
            .foregroundColor(CiderColors.secondary)
        }
    }

    @ViewBuilder
    private func reviewActionButton(
        _ action: HomeReviewCockpitAction,
        for reviewItem: HomeReviewCockpitItem
    ) -> some View {
        switch action {
        case .openSource:
            if let item = reviewItem.item {
                Button {
                    onOpenItem(item)
                } label: {
                    Image(systemName: action.systemImage)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(reviewActionHelp(action, for: reviewItem))
                .accessibilityLabel(reviewActionHelp(action, for: reviewItem))
            }
        case .accept, .reject, .deferReview:
            Button {
                if onPerformReviewAction(reviewItem, action) {
                    resolvedReviewIDs.insert(reviewItem.id)
                }
            } label: {
                Image(systemName: action.systemImage)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(reviewActionHelp(action, for: reviewItem))
            .accessibilityLabel(reviewActionHelp(action, for: reviewItem))
        }
    }

    private func reviewActionHelp(
        _ action: HomeReviewCockpitAction,
        for item: HomeReviewCockpitItem
    ) -> String {
        switch action {
        case .accept:
            if item.kindLabel == "Memory Candidate" { return "Accept memory" }
            if item.kindLabel == "Graph Candidate" { return "Accept graph candidate" }
            return item.dateSuggestionApproval == nil ? "Approve review" : "Approve suggestion"
        case .reject:
            return "Reject suggestion"
        case .deferReview:
            return "Defer for later"
        case .openSource:
            return "Open source item"
        }
    }
}

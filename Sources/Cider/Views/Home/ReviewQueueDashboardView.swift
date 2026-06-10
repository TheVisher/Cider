import SwiftUI

struct ReviewQueueDashboardView: View {
    let items: [HomeReviewCockpitItem]
    let summary: HomeReviewCockpitSummary
    let onOpenItem: (LibraryItemV2) -> Void
    let onApproveReview: (HomeReviewCockpitItem) -> Bool
    let onDeferReview: (HomeReviewCockpitItem) -> Bool
    let onEnrichReviewBatch: () -> Bool

    @State private var resolvedReviewIDs: Set<String> = []
    @State private var batchEnrichmentIsConfirming = false
    @State private var scheduledBatchEnrichmentCount: Int?

    private var visibleItems: [HomeReviewCockpitItem] {
        items.filter { !resolvedReviewIDs.contains($0.id) }
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
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(CiderColors.surfaceInput)
                        )
                    }
                }
            }
        }
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
        HomeOverviewPanel(title: "Items") {
            if visibleItems.isEmpty {
                Text("Nothing is waiting in the visible review queue.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
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
                if reviewItem.canCorrect, let item = reviewItem.item {
                    Button {
                        onOpenItem(item)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Open item")
                    .accessibilityLabel("Open item")
                }

                if reviewItem.canApprove {
                    Button {
                        if onApproveReview(reviewItem) {
                            resolvedReviewIDs.insert(reviewItem.id)
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Approve review")
                    .accessibilityLabel("Approve review")
                }

                if reviewItem.canDefer {
                    Button {
                        if onDeferReview(reviewItem) {
                            resolvedReviewIDs.insert(reviewItem.id)
                        }
                    } label: {
                        Image(systemName: "clock")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Defer review")
                    .accessibilityLabel("Defer review")
                }
            }
            .font(CiderFont.captionSemibold)
            .foregroundColor(CiderColors.secondary)
        }
    }
}

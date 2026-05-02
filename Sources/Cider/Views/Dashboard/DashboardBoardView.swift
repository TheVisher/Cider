import SwiftUI

@MainActor
struct DashboardBoardView: View {
    let topic: DashboardTopic
    @ObservedObject var storage: DashboardStorage
    let onOpenSourceURL: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if visibleCards.isEmpty {
                    DashboardEmptyStateView(
                        icon: topic.icon ?? "rectangle.stack",
                        title: "Nothing in \(topic.title)",
                        message: "Cards curated for this topic will show up here. For now, the quiet is almost suspiciously tidy."
                    )
                    .frame(maxWidth: .infinity, minHeight: DashboardBoardDesign.emptyStateHeight)
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(visibleCards) { card in
                            DashboardCardView(
                                card: card,
                                onMarkSeen: {
                                    _ = storage.markSeen(card.ciderSyncId)
                                },
                                onDismiss: {
                                    _ = storage.dismissCard(card.ciderSyncId)
                                },
                                onRate: { rating in
                                    _ = storage.rateCard(card.ciderSyncId, rating: rating)
                                },
                                onMoreLikeThis: {
                                    let isActive = card.feedback?.moreLikeThis == true
                                    _ = storage.setCardPreference(
                                        card.ciderSyncId,
                                        moreLikeThis: !isActive,
                                        lessLikeThis: false
                                    )
                                },
                                onLessLikeThis: {
                                    let isActive = card.feedback?.lessLikeThis == true
                                    _ = storage.setCardPreference(
                                        card.ciderSyncId,
                                        moreLikeThis: false,
                                        lessLikeThis: !isActive
                                    )
                                },
                                onOpenSourceURL: onOpenSourceURL
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: DashboardBoardDesign.maxContentWidth, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: topic.icon ?? "rectangle.stack")
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: DashboardBoardDesign.headerIconSize, height: DashboardBoardDesign.headerIconSize)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.accentSubtle)
                )

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(topic.title)
                    .font(CiderFont.displaySemibold)
                    .foregroundColor(CiderColors.primary)

                Text(cardSummary)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private var visibleCards: [DashboardCard] {
        storage.cards
            .filter { card in
                card.topicSyncIds.contains(topic.ciderSyncId)
                    && card.deleted != true
                    && card.status != .dismissed
                    && card.status != .archived
            }
            .sorted { lhs, rhs in
                let lhsRank = DashboardBoardDesign.priorityRank(lhs.priority)
                let rhsRank = DashboardBoardDesign.priorityRank(rhs.priority)
                if lhs.status == .new, rhs.status != .new { return true }
                if lhs.status != .new, rhs.status == .new { return false }
                if lhsRank != rhsRank { return lhsRank > rhsRank }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var cardSummary: String {
        let count = visibleCards.count
        if count == 1 {
            return "1 active card"
        }
        return "\(count) active cards"
    }
}

private enum DashboardBoardDesign {
    static let maxContentWidth: CGFloat = 920
    static let emptyStateHeight: CGFloat = 260
    static let headerIconSize: CGFloat = 34

    static func priorityRank(_ priority: DashboardCardPriority) -> Int {
        switch priority {
        case .urgent: 4
        case .high: 3
        case .normal: 2
        case .low: 1
        case .unknown: 0
        }
    }
}

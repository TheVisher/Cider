import SwiftUI

struct DashboardCardView: View {
    let card: DashboardCard
    let onMarkSeen: () -> Void
    let onDismiss: () -> Void
    let onRate: (Int) -> Void
    let onMoreLikeThis: () -> Void
    let onLessLikeThis: () -> Void
    let onOpenSourceURL: (URL) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            Text(card.summary)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let whyItMatters = card.whyItMatters, !whyItMatters.isEmpty {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "sparkle")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.controlAccent)
                    Text(whyItMatters)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceSubtle)
                )
            }

            Divider()
                .background(CiderColors.separator)

            footer
        }
        .padding(Spacing.md)
        .cardContainer(isHovered: isHovered, cornerRadius: Radius.md)
        .onHover { isHovered = $0 }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    statusPill
                    priorityPill
                    sourcePill
                }

                Text(card.title)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = card.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                }
            }

            Spacer(minLength: Spacing.md)

            HStack(spacing: Spacing.xs) {
                if card.status == .new {
                    iconButton(
                        systemName: "checkmark.circle",
                        accessibilityLabel: "Mark seen",
                        action: onMarkSeen
                    )
                }

                if let sourceURL {
                    iconButton(
                        systemName: "arrow.up.forward.square",
                        accessibilityLabel: "Open source",
                        action: { onOpenSourceURL(sourceURL) }
                    )
                }

                iconButton(
                    systemName: "xmark.circle",
                    accessibilityLabel: "Dismiss",
                    action: onDismiss
                )
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            HStack(spacing: Spacing.xxs) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        onRate(rating)
                    } label: {
                        Image(systemName: rating <= selectedRating ? "star.fill" : "star")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(rating <= selectedRating ? CiderColors.warning : CiderColors.quaternary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rate \(rating)")
                }
            }

            Spacer(minLength: Spacing.sm)

            feedbackButton(
                title: "More like this",
                systemName: card.feedback?.moreLikeThis == true ? "hand.thumbsup.fill" : "hand.thumbsup",
                isActive: card.feedback?.moreLikeThis == true,
                action: onMoreLikeThis
            )

            feedbackButton(
                title: "Less like this",
                systemName: card.feedback?.lessLikeThis == true ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                isActive: card.feedback?.lessLikeThis == true,
                action: onLessLikeThis
            )
        }
    }

    private var statusPill: some View {
        Text(card.status.dashboardTitle)
            .font(CiderFont.microSemibold)
            .foregroundColor(card.status == .new ? CiderColors.controlAccent : CiderColors.tertiary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(card.status == .new ? CiderColors.accentLight : CiderColors.surfaceInput)
            )
    }

    private var priorityPill: some View {
        Text(card.priority.dashboardTitle)
            .font(CiderFont.microSemibold)
            .foregroundColor(card.priority == .high || card.priority == .urgent ? CiderColors.warning : CiderColors.quaternary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
    }

    private var sourcePill: some View {
        Text(card.sourceKind.dashboardTitle)
            .font(CiderFont.microSemibold)
            .foregroundColor(CiderColors.quaternary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
    }

    private var selectedRating: Int {
        card.feedback?.rating ?? 0
    }

    private var sourceURL: URL? {
        guard let sourceURL = card.sourceURL else { return nil }
        return URL(string: sourceURL)
    }

    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: DashboardCardDesign.iconButtonSize, height: DashboardCardDesign.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func feedbackButton(
        title: String,
        systemName: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemName)
                    .font(CiderFont.captionMedium)
                Text(title)
                    .font(CiderFont.captionMedium)
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.tertiary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isActive ? CiderColors.accentLight : CiderColors.surfaceInput)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum DashboardCardDesign {
    static let iconButtonSize: CGFloat = 26
}

private extension DashboardCardStatus {
    var dashboardTitle: String {
        switch self {
        case .new: "New"
        case .seen: "Seen"
        case .saved: "Saved"
        case .dismissed: "Dismissed"
        case .reminded: "Reminded"
        case .archived: "Archived"
        case .unknown(let value): value.capitalized
        }
    }
}

private extension DashboardCardPriority {
    var dashboardTitle: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        case .unknown(let value): value.capitalized
        }
    }
}

private extension DashboardCardSourceKind {
    var dashboardTitle: String {
        switch self {
        case .url: "URL"
        case .bookmark: "Bookmark"
        case .note: "Note"
        case .todo: "Todo"
        case .event: "Event"
        case .project: "Project"
        case .board: "Board"
        case .repo: "Repo"
        case .manual: "Manual"
        case .unknown(let value): value.capitalized
        }
    }
}

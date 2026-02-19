import SwiftUI

struct StackCardView: View {
    let surface: StackSurfaceResult
    var onOpen: (() -> Void)? = nil
    var onTogglePinned: ((CardStack) -> Void)? = nil
    var onManage: ((CardStack) -> Void)? = nil

    @State private var isHovered = false

    private var ruleBadges: [String] {
        var badges: [String] = []

        if surface.stack.isPinned {
            badges.append("Pinned")
        }

        if !surface.stack.manualItemRefs.isEmpty {
            badges.append("Manual \(surface.stack.manualItemRefs.count)")
        }

        for rule in surface.stack.matchRules {
            switch rule.condition {
            case .hasDate:
                badges.append("Has Date")
            case .isIncomplete:
                badges.append("Incomplete")
            case .entityType:
                if let value = rule.value {
                    badges.append(value.capitalized)
                }
            case .hasLabel:
                badges.append("Label")
            }
        }

        for rule in surface.stack.surfaceRules where rule.isEnabled {
            switch rule.type {
            case .pinUntilDone:
                badges.append("Pin Until Done")
            case .surfaceDaysBeforeDate:
                let days = rule.integerValue ?? 0
                badges.append("Surf \(days)d")
            case .remindBeforeMinutes:
                let minutes = rule.integerValue ?? 0
                badges.append("Remind \(minutes)m")
            }
        }

        // Avoid noisy cards.
        return Array(badges.prefix(4))
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "square.stack.3d.up")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    Text(surface.stack.name)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(surface.items.count)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.hairline)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.separatorLight)
                        )

                    Menu {
                        Button(surface.stack.isPinned ? "Unpin" : "Pin") {
                            onTogglePinned?(surface.stack)
                        }
                        Button("Manage Stack") {
                            onManage?(surface.stack)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                ForEach(Array(surface.items.prefix(3).enumerated()), id: \.offset) { _, item in
                    Text(item.title)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                }

                if !ruleBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xxs) {
                            ForEach(ruleBadges, id: \.self) { badge in
                                Text(badge)
                                    .font(CiderFont.captionMedium)
                                    .foregroundColor(CiderColors.tertiary)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, Spacing.hairline)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(CiderColors.separatorLight)
                                    )
                            }
                        }
                    }
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
    }
}

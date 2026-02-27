import SwiftUI

struct DateCardCardView: View {
    let dateCard: DateCard
    var onOpen: (() -> Void)? = nil
    var onToggleComplete: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: dateCard.startAt)
    }

    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: dateCard.startAt).uppercased()
    }

    private var timeString: String {
        if dateCard.allDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let endAt = dateCard.endAt {
            return "\(formatter.string(from: dateCard.startAt)) - \(formatter.string(from: endAt))"
        }
        return formatter.string(from: dateCard.startAt)
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header: large date block on left, vertical divider, title on right
                HStack(alignment: .top, spacing: 0) {
                    // Date block — the hero visual
                    VStack(alignment: .leading, spacing: 0) {
                        Text(monthString)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                        Text(dayString)
                            .font(CiderFont.heroFallback)
                            .foregroundColor(CiderColors.primary)
                            .monospacedDigit()
                    }
                    .frame(width: 48, alignment: .leading)

                    Rectangle()
                        .fill(CiderColors.borderSubtle)
                        .frame(width: 1)
                        .padding(.vertical, Spacing.xxs)
                        .padding(.horizontal, Spacing.sm)

                    // Title + completion toggle
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Text(dateCard.title)
                            .font(CiderFont.subheadingSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            onToggleComplete?()
                        } label: {
                            Image(systemName: dateCard.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(CiderFont.bodyMedium)
                                .foregroundColor(dateCard.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, Spacing.xs)
                }

                // Detail rows — time first, then location, amount, details
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    detailRow(icon: "clock", text: timeString)

                    if !dateCard.location.isEmpty {
                        detailRow(icon: "mappin.and.ellipse", text: dateCard.location)
                    }

                    if let amount = dateCard.amount {
                        detailRow(
                            icon: "dollarsign.circle",
                            text: Self.currencyFormatter.string(from: NSNumber(value: amount))
                                ?? String(format: "%.2f", amount)
                        )
                    }

                    if !dateCard.details.isEmpty {
                        Text(dateCard.details)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(3)
                    }
                }

                if !dateCard.labelIDs.isEmpty {
                    TagPillRow(
                        labelIDs: dateCard.labelIDs,
                        labels: CardLabelStorage.shared.labels
                    )
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
        .dateCardContextMenu(
            onOpen: { onOpen?() },
            onToggleComplete: { onToggleComplete?() },
            isCompleted: dateCard.isCompleted,
            labelIDs: dateCard.labelIDs,
            folders: folders,
            onMoveToFolder: { onMoveToFolder?($0) },
            onDelete: { onDelete?() },
            onToggleLabel: { labelID in
                var updated = dateCard
                if updated.labelIDs.contains(labelID) {
                    updated.labelIDs.removeAll { $0 == labelID }
                } else {
                    updated.labelIDs.append(labelID)
                }
                _ = DateCardStorage.shared.updateDateCard(updated)
            }
        )
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 12)
            Text(text)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

struct DateCardListRow: View {
    let dateCard: DateCard
    var onOpen: (() -> Void)? = nil
    var onToggleComplete: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(dateCard.startAt.formatted(.dateTime.month(.abbreviated)))
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Text(dateCard.startAt.formatted(.dateTime.day()))
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                }
                .frame(width: 42, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(dateCard.title)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(dateCard.allDay ? "All Day" : dateCard.startAt.formatted(.dateTime.hour().minute()))
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                        if !dateCard.location.isEmpty {
                            Text("\u{00B7}")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.quaternary)
                            Text(dateCard.location)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if let amount = dateCard.amount {
                        Text(Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Spacer(minLength: Spacing.sm)

                Button {
                    onToggleComplete?()
                } label: {
                    Image(systemName: dateCard.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(dateCard.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
        .dateCardContextMenu(
            onOpen: { onOpen?() },
            onToggleComplete: { onToggleComplete?() },
            isCompleted: dateCard.isCompleted,
            labelIDs: dateCard.labelIDs,
            folders: folders,
            onMoveToFolder: { onMoveToFolder?($0) },
            onDelete: { onDelete?() },
            onToggleLabel: { labelID in
                var updated = dateCard
                if updated.labelIDs.contains(labelID) {
                    updated.labelIDs.removeAll { $0 == labelID }
                } else {
                    updated.labelIDs.append(labelID)
                }
                _ = DateCardStorage.shared.updateDateCard(updated)
            }
        )
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

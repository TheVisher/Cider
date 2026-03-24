import SwiftUI

struct DateCardCardView: View {
    let dateCard: DateCard
    var urgency: DateCardUrgency? = nil
    var onOpen: (() -> Void)? = nil
    var onToggleComplete: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @State private var isHovered = false

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

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

    private var dateBlockMonthColor: Color {
        switch urgency {
        case .overdue: return CiderColors.destructive
        case .today: return CiderColors.warning
        case .approaching: return CiderColors.controlAccent
        case nil: return CiderColors.tertiary
        }
    }

    private var dateBlockDayColor: Color {
        switch urgency {
        case .overdue: return CiderColors.destructive
        case .today: return CiderColors.warning
        case .approaching: return CiderColors.controlAccent
        case nil: return CiderColors.primary
        }
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
            handleClick { onOpen?() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header: large date block on left, vertical divider, title on right
                HStack(alignment: .top, spacing: 0) {
                    // Date block — the hero visual
                    VStack(alignment: .leading, spacing: 0) {
                        Text(monthString)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(dateBlockMonthColor)
                        Text(dayString)
                            .font(CiderFont.heroFallback)
                            .foregroundColor(dateBlockDayColor)
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

                if let urgency {
                    urgencyBadge(urgency)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
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
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
    }

    private func urgencyBadge(_ urgency: DateCardUrgency) -> some View {
        let (text, fgColor, bgColor): (String, Color, Color) = {
            switch urgency {
            case .overdue:
                return ("Overdue", CiderColors.destructive, CiderColors.destructiveSubtle)
            case .today:
                return ("Today", CiderColors.warning, CiderColors.warningSubtle)
            case .approaching(let d):
                return ("In \(d) day\(d == 1 ? "" : "s")", CiderColors.controlAccent, CiderColors.accentSubtle)
            }
        }()

        return Text(text)
            .font(CiderFont.captionSemibold)
            .foregroundColor(fgColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(bgColor)
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
    var urgency: DateCardUrgency? = nil
    var onOpen: (() -> Void)? = nil
    var onToggleComplete: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

    private var listMonthColor: Color {
        switch urgency {
        case .overdue: return CiderColors.destructive
        case .today: return CiderColors.warning
        case .approaching: return CiderColors.controlAccent
        case nil: return CiderColors.tertiary
        }
    }

    private var listDayColor: Color {
        switch urgency {
        case .overdue: return CiderColors.destructive
        case .today: return CiderColors.warning
        case .approaching: return CiderColors.controlAccent
        case nil: return CiderColors.primary
        }
    }

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isSelected {
                    SelectionCheckmark()
                }

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(dateCard.startAt.formatted(.dateTime.month(.abbreviated)))
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(listMonthColor)
                    Text(dateCard.startAt.formatted(.dateTime.day()))
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(listDayColor)
                }
                .frame(width: 42, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
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

                if let urgency {
                    listUrgencyBadge(urgency)
                }

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
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(
                        isFocused ? CiderColors.controlAccent : (isSelected ? CiderColors.controlAccent : Color.clear),
                        lineWidth: isFocused ? 1.5 : (isSelected ? CiderBorder.innerStrokeWidth : 0)
                    )
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
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
    }

    private func listUrgencyBadge(_ urgency: DateCardUrgency) -> some View {
        let (text, fgColor, bgColor): (String, Color, Color) = {
            switch urgency {
            case .overdue:
                return ("Overdue", CiderColors.destructive, CiderColors.destructiveSubtle)
            case .today:
                return ("Today", CiderColors.warning, CiderColors.warningSubtle)
            case .approaching(let d):
                return ("In \(d) day\(d == 1 ? "" : "s")", CiderColors.controlAccent, CiderColors.accentSubtle)
            }
        }()

        return Text(text)
            .font(CiderFont.micro)
            .foregroundColor(fgColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(bgColor)
            )
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

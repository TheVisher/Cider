import SwiftUI

struct TodoCardCardView: View {
    let todoCard: TodoCard
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

    private var priorityColor: Color {
        switch todoCard.priority {
        case .high: CiderColors.destructive
        case .medium: CiderColors.warning
        case .low: CiderColors.controlAccent
        case nil: CiderColors.tertiary
        }
    }

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header: completion toggle (single todos only) + title + priority
                HStack(alignment: .top, spacing: Spacing.xs) {
                    if todoCard.checklist.isEmpty {
                        Button {
                            onToggleComplete?()
                        } label: {
                            Image(systemName: todoCard.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(CiderFont.bodyMedium)
                                .foregroundColor(todoCard.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(todoCard.title)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(todoCard.isCompleted ? CiderColors.tertiary : CiderColors.primary)
                        .strikethrough(todoCard.isCompleted && todoCard.checklist.isEmpty)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let priority = todoCard.priority {
                        Image(systemName: priority.icon)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(priorityColor)
                    }
                }

                // Details
                if !todoCard.details.isEmpty {
                    Text(todoCard.details)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(3)
                }

                // Todo items
                if !todoCard.checklist.isEmpty {
                    let preview = todoCard.checklist.prefix(4)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(Array(preview)) { item in
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                // Main item row — full todo
                                HStack(spacing: Spacing.xs) {
                                    Button {
                                        TodoCardStorage.shared.toggleChecklistItem(todoCard.id, checklistItemID: item.id)
                                    } label: {
                                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(CiderFont.bodyMedium)
                                            .foregroundColor(item.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                                    }
                                    .buttonStyle(.plain)

                                    Text(item.title)
                                        .font(CiderFont.bodyMedium)
                                        .foregroundColor(item.isCompleted ? CiderColors.tertiary : CiderColors.primary)
                                        .strikethrough(item.isCompleted)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if let amount = item.amount {
                                        Text(Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
                                            .font(CiderFont.body)
                                            .foregroundColor(item.isCompleted ? CiderColors.tertiary : CiderColors.secondary)
                                    }
                                    if let itemDue = item.dueDate, !item.isCompleted {
                                        Text(itemDue.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(CiderFont.caption)
                                            .foregroundColor(itemDueDateColor(itemDue))
                                    }
                                }

                                // Subtasks — indented, square checkboxes
                                if !item.subtasks.isEmpty {
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        ForEach(item.subtasks) { subtask in
                                            HStack(spacing: Spacing.xs) {
                                                Image(systemName: subtask.isCompleted ? "checkmark.square.fill" : "square")
                                                    .font(CiderFont.captionMedium)
                                                    .foregroundColor(subtask.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                                                Text(subtask.title)
                                                    .font(CiderFont.caption)
                                                    .foregroundColor(subtask.isCompleted ? CiderColors.tertiary : CiderColors.secondary)
                                                    .strikethrough(subtask.isCompleted)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.leading, Spacing.lg + Spacing.xs)
                                }
                            }
                        }
                        if todoCard.checklist.count > 4 {
                            Text("+\(todoCard.checklist.count - 4) more")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }

                // Bottom row: due date + progress + total amount
                HStack(spacing: Spacing.sm) {
                    if let dueDate = todoCard.dueDate {
                        dueDateBadge(dueDate)
                    }

                    if !todoCard.checklist.isEmpty {
                        Text("\(todoCard.completedCount)/\(todoCard.totalCount)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Spacer(minLength: 0)

                    if let total = todoCard.totalAmount {
                        let unpaid = todoCard.unpaidAmount ?? 0
                        let unpaidStr = Self.currencyFormatter.string(from: NSNumber(value: unpaid)) ?? String(format: "%.2f", unpaid)
                        let totalStr = Self.currencyFormatter.string(from: NSNumber(value: total)) ?? String(format: "%.2f", total)
                        Text("\(unpaidStr) / \(totalStr)")
                            .font(CiderFont.caption)
                            .foregroundColor(unpaid > 0 ? CiderColors.primary : CiderColors.tertiary)
                    }
                }

                if !todoCard.labelIDs.isEmpty {
                    TagPillRow(
                        labelIDs: todoCard.labelIDs,
                        labels: CardLabelStorage.shared.labels
                    )
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
        .todoCardContextMenu(
            onOpen: { onOpen?() },
            onToggleComplete: { onToggleComplete?() },
            isCompleted: todoCard.isCompleted,
            labelIDs: todoCard.labelIDs,
            folders: folders,
            onMoveToFolder: { onMoveToFolder?($0) },
            onDelete: { onDelete?() },
            onToggleLabel: { labelID in
                var updated = todoCard
                if updated.labelIDs.contains(labelID) {
                    updated.labelIDs.removeAll { $0 == labelID }
                } else {
                    updated.labelIDs.append(labelID)
                }
                _ = TodoCardStorage.shared.updateTodoCard(updated)
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
    }

    @ViewBuilder
    private func dueDateBadge(_ date: Date) -> some View {
        let (text, fgColor, bgColor) = dueDateStyle(date)
        Text(text)
            .font(CiderFont.captionSemibold)
            .foregroundColor(fgColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(bgColor)
            )
    }

    private func dueDateStyle(_ date: Date) -> (String, Color, Color) {
        if todoCard.isCompleted {
            return (date.formatted(.dateTime.month(.abbreviated).day()), CiderColors.tertiary, CiderColors.surfaceInput)
        }
        if todoCard.isOverdue {
            return ("Overdue", CiderColors.destructive, CiderColors.destructiveSubtle)
        }
        if todoCard.isDueToday {
            return ("Today", CiderColors.warning, CiderColors.warning.opacity(0.08))
        }
        return (date.formatted(.dateTime.month(.abbreviated).day()), CiderColors.tertiary, CiderColors.surfaceInput)
    }

    private func itemDueDateColor(_ date: Date) -> Color {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return CiderColors.destructive }
        if days == 0 { return CiderColors.warning }
        return CiderColors.tertiary
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

// MARK: - TodoListRow

struct TodoListRow: View {
    let todoCard: TodoCard
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

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isSelected {
                    SelectionCheckmark()
                }

                if todoCard.checklist.isEmpty {
                    Button {
                        onToggleComplete?()
                    } label: {
                        Image(systemName: todoCard.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(todoCard.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(todoCard.title)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(todoCard.isCompleted ? CiderColors.tertiary : CiderColors.primary)
                        .strikethrough(todoCard.isCompleted && todoCard.checklist.isEmpty)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        if !todoCard.checklist.isEmpty {
                            Text("\(todoCard.completedCount)/\(todoCard.totalCount)")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                        }

                        if let priority = todoCard.priority {
                            if !todoCard.checklist.isEmpty {
                                Text("\u{00B7}")
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.quaternary)
                            }
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: priority.icon)
                                    .font(CiderFont.captionMedium)
                                Text(priority.displayName)
                                    .font(CiderFont.body)
                            }
                            .foregroundColor(priorityColor)
                        }

                        if !todoCard.details.isEmpty {
                            if !todoCard.checklist.isEmpty || todoCard.priority != nil {
                                Text("\u{00B7}")
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.quaternary)
                            }
                            Text(todoCard.details)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: Spacing.sm)

                if let dueDate = todoCard.dueDate {
                    listDueDateBadge(dueDate)
                }
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
        .todoCardContextMenu(
            onOpen: { onOpen?() },
            onToggleComplete: { onToggleComplete?() },
            isCompleted: todoCard.isCompleted,
            labelIDs: todoCard.labelIDs,
            folders: folders,
            onMoveToFolder: { onMoveToFolder?($0) },
            onDelete: { onDelete?() },
            onToggleLabel: { labelID in
                var updated = todoCard
                if updated.labelIDs.contains(labelID) {
                    updated.labelIDs.removeAll { $0 == labelID }
                } else {
                    updated.labelIDs.append(labelID)
                }
                _ = TodoCardStorage.shared.updateTodoCard(updated)
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
    }

    private var priorityColor: Color {
        switch todoCard.priority {
        case .high: CiderColors.destructive
        case .medium: CiderColors.warning
        case .low: CiderColors.controlAccent
        case nil: CiderColors.tertiary
        }
    }

    @ViewBuilder
    private func listDueDateBadge(_ date: Date) -> some View {
        if todoCard.isCompleted {
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        } else if todoCard.isOverdue {
            Text("Overdue")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.destructive)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(CiderColors.destructiveSubtle))
        } else if todoCard.isDueToday {
            Text("Today")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.warning)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(CiderColors.warning.opacity(0.08)))
        } else {
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
    }
}

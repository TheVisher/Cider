import SwiftUI

struct TodoDetailView: View {
    let todoCard: TodoCard
    var onEdit: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var todoStorage = TodoCardStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var liveTodo: TodoCard {
        todoStorage.todoCard(for: todoCard.id) ?? todoCard
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f
    }()

    var body: some View {
        let todo = liveTodo
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(todo.title)
                    .font(CiderFont.subheading)
                    .foregroundColor(CiderColors.primary)

                if !todo.details.isEmpty {
                    Text(todo.details)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Spacing.sm) {
                    if let priority = todo.priority {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: priority.icon)
                                .font(CiderFont.captionMedium)
                            Text(priority.displayName)
                                .font(CiderFont.caption)
                        }
                        .foregroundColor(priorityColor(priority))
                    }

                    if let dueDate = todo.dueDate {
                        dueDateBadge(dueDate, isCompleted: todo.isCompleted, isOverdue: todo.isOverdue, isDueToday: todo.isDueToday)
                    }

                    if !todo.checklist.isEmpty {
                        Text("\(todo.completedCount)/\(todo.totalCount)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
            }

            // Summary bar for lists with amounts
            if let total = todo.totalAmount {
                summaryBar(todo: todo, total: total)
            }

            if !todo.checklist.isEmpty {
                Divider()
                checklistSection(todo: todo)
            }

            // Single todo — completion toggle
            if todo.checklist.isEmpty {
                Divider()
                Button {
                    _ = todoStorage.markCompleted(todo.id, completed: !todo.isCompleted)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(todo.isCompleted ? CiderColors.controlAccent : CiderColors.tertiary)
                        Text(todo.isCompleted ? "Completed" : "Mark as completed")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            // Notes / History
            notesSection(todo: todo)

            // Labels
            let labels = labelStorage.labels.filter { todo.labelIDs.contains($0.id) }
            if !labels.isEmpty {
                TagPillRow(labelIDs: todo.labelIDs, labels: labelStorage.labels)
            }

            Divider()

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)

                Button("Edit") {
                    onEdit?()
                }
                .buttonStyle(.borderless)
                .foregroundColor(CiderColors.secondary)

                Button("Done") {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Summary Bar

    private func summaryBar(todo: TodoCard, total: Double) -> some View {
        let unpaid = todo.unpaidAmount ?? 0
        let paid = total - unpaid
        let totalStr = Self.currencyFormatter.string(from: NSNumber(value: total)) ?? String(format: "%.2f", total)
        let paidStr = Self.currencyFormatter.string(from: NSNumber(value: paid)) ?? String(format: "%.2f", paid)
        let remainingStr = Self.currencyFormatter.string(from: NSNumber(value: unpaid)) ?? String(format: "%.2f", unpaid)

        return HStack(spacing: Spacing.md) {
            summaryMetric(title: "Total", value: totalStr)
            summaryMetric(title: "Paid", value: paidStr)
            summaryMetric(title: "Remaining", value: remainingStr, highlight: unpaid > 0)
            summaryMetric(title: "Progress", value: "\(todo.completedCount)/\(todo.totalCount)")
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func summaryMetric(title: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(title)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
            Text(value)
                .font(CiderFont.bodySemibold)
                .foregroundColor(highlight ? CiderColors.primary : CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Checklist

    private func checklistSection(todo: TodoCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(todo.checklist) { item in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Main item row
                    HStack(spacing: Spacing.xs) {
                        Button {
                            todoStorage.toggleChecklistItem(todo.id, checklistItemID: item.id)
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

                        Spacer(minLength: 0)

                        if let amount = item.amount {
                            Text(Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
                                .font(CiderFont.body)
                                .foregroundColor(item.isCompleted ? CiderColors.tertiary : CiderColors.secondary)
                        }

                        if let itemDue = item.dueDate, !item.isCompleted {
                            Text(itemDue.formatted(.dateTime.month(.abbreviated).day()))
                                .font(CiderFont.caption)
                                .foregroundColor(itemDueDateColor(itemDue, isCompleted: item.isCompleted))
                        }

                        if item.isCompleted, let completedAt = item.completedAt {
                            Text("Done \(completedAt.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.controlAccent)
                        }
                    }

                    // Item metadata row (URL)
                    if let urlString = item.urlString, !urlString.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "link")
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.controlAccent)
                            if let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://\(urlString)") {
                                Link(destination: url) {
                                    Text(urlString)
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.controlAccent)
                                        .lineLimit(1)
                                        .underline()
                                }
                            } else {
                                Text(urlString)
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, Spacing.lg + Spacing.xs)
                    }

                    // Subtasks
                    if !item.subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            ForEach(item.subtasks) { subtask in
                                HStack(spacing: Spacing.xs) {
                                    Button {
                                        todoStorage.toggleSubtask(todo.id, checklistItemID: item.id, subtaskID: subtask.id)
                                    } label: {
                                        Image(systemName: subtask.isCompleted ? "checkmark.square.fill" : "square")
                                            .font(CiderFont.captionMedium)
                                            .foregroundColor(subtask.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                                    }
                                    .buttonStyle(.plain)

                                    Text(subtask.title)
                                        .font(CiderFont.caption)
                                        .foregroundColor(subtask.isCompleted ? CiderColors.tertiary : CiderColors.secondary)
                                        .strikethrough(subtask.isCompleted)
                                }
                            }
                        }
                        .padding(.leading, Spacing.lg + Spacing.xs)
                    }
                }
            }
        }
    }

    // MARK: - Notes

    @State private var isNotesExpanded = false
    @State private var draftNotes: String = ""
    @State private var notesInitialized = false

    private func notesSection(todo: TodoCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                withAnimation(reduceMotion ? .none : .snappy) { isNotesExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "note.text")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                    Text("Notes & History")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    if !todo.notes.isEmpty && !isNotesExpanded {
                        Circle()
                            .fill(CiderColors.controlAccent)
                            .frame(width: 6, height: 6)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isNotesExpanded {
                TextEditor(text: $draftNotes)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 160)
                    .padding(Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceSubtle)
                    )
                    .onChange(of: draftNotes) {
                        saveNotes(todoID: todo.id)
                    }
            }
        }
        .onAppear {
            if !notesInitialized {
                draftNotes = todo.notes
                notesInitialized = true
            }
        }
        .onChange(of: todo.notes) {
            // Sync from storage when auto-log entries are added
            if todo.notes != draftNotes {
                draftNotes = todo.notes
            }
        }
    }

    private func saveNotes(todoID: UUID) {
        guard var card = todoStorage.todoCard(for: todoID) else { return }
        guard card.notes != draftNotes else { return }
        card.notes = draftNotes
        _ = todoStorage.updateTodoCard(card)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func dueDateBadge(_ date: Date, isCompleted: Bool, isOverdue: Bool, isDueToday: Bool) -> some View {
        let (text, fgColor, bgColor): (String, Color, Color) = {
            if isCompleted {
                return (date.formatted(.dateTime.month(.abbreviated).day()), CiderColors.tertiary, CiderColors.surfaceInput)
            }
            if isOverdue {
                return ("Overdue", CiderColors.destructive, CiderColors.destructiveSubtle)
            }
            if isDueToday {
                return ("Today", CiderColors.warning, CiderColors.warningSubtle)
            }
            return (date.formatted(.dateTime.month(.abbreviated).day()), CiderColors.tertiary, CiderColors.surfaceInput)
        }()
        Text(text)
            .font(CiderFont.captionSemibold)
            .foregroundColor(fgColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(bgColor))
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high:   CiderColors.destructive
        case .medium: CiderColors.warning
        case .low:    CiderColors.controlAccent
        }
    }

    private func dueDateColor(_ date: Date, isCompleted: Bool) -> Color {
        if isCompleted { return CiderColors.tertiary }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return CiderColors.destructive }
        if days == 0 { return CiderColors.warning }
        return CiderColors.tertiary
    }

    private func itemDueDateColor(_ date: Date, isCompleted: Bool) -> Color {
        if isCompleted { return CiderColors.tertiary }
        return dueDateColor(date, isCompleted: false)
    }
}

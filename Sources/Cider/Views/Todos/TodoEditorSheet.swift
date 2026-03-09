import SwiftUI

struct TodoEditorSheet: View {
    let existingCard: TodoCard?
    let onSave: (TodoCard) -> Void
    let onDelete: ((TodoCard) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var title: String
    @State private var details: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TodoPriority?
    @State private var checklist: [TodoChecklistItem]
    @State private var selectedLabelIDs: Set<UUID>
    @State private var draftLabelName = ""
    @State private var draftItemTitle = ""

    init(
        existingCard: TodoCard?,
        onSave: @escaping (TodoCard) -> Void,
        onDelete: ((TodoCard) -> Void)? = nil
    ) {
        self.existingCard = existingCard
        self.onSave = onSave
        self.onDelete = onDelete

        _title = State(initialValue: existingCard?.title ?? "")
        _details = State(initialValue: existingCard?.details ?? "")
        _hasDueDate = State(initialValue: existingCard?.dueDate != nil)
        _dueDate = State(initialValue: existingCard?.dueDate ?? Date())
        _priority = State(initialValue: existingCard?.priority)
        _checklist = State(initialValue: existingCard?.checklist ?? [])
        _selectedLabelIDs = State(initialValue: Set(existingCard?.labelIDs ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(existingCard == nil ? "New Todo" : "Edit Todo")
                .font(CiderFont.headingMedium)
                .foregroundColor(CiderColors.primary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Title
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    // Details
                    TextField("Details", text: $details, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    // Priority
                    HStack(spacing: Spacing.sm) {
                        Text("Priority")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                        Spacer()
                        Picker("", selection: $priority) {
                            Text("None").tag(nil as TodoPriority?)
                            ForEach(TodoPriority.allCases, id: \.self) { p in
                                Label(p.displayName, systemImage: p.icon).tag(p as TodoPriority?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    // Due Date
                    Toggle("Due Date", isOn: $hasDueDate)
                        .toggleStyle(.switch)

                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: $dueDate,
                            displayedComponents: [.date]
                        )
                    }

                    Divider().background(CiderColors.separator)

                    // Checklist
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Checklist")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)

                        ForEach(Array(checklist.enumerated()), id: \.element.id) { index, item in
                            checklistItemRow(index: index, item: item)
                        }

                        // Add item row
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "plus.circle")
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.quaternary)
                            TextField("Add item", text: $draftItemTitle)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addChecklistItem() }
                            Button("Add") { addChecklistItem() }
                                .buttonStyle(.borderless)
                                .disabled(draftItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Divider().background(CiderColors.separator)

                    // Labels
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Labels")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)

                        if !labelStorage.labels.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.xs) {
                                    ForEach(labelStorage.labels) { label in
                                        labelChip(label)
                                    }
                                }
                            }
                        }

                        HStack(spacing: Spacing.xs) {
                            TextField("New label", text: $draftLabelName)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let trimmed = draftLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                let created = labelStorage.createLabel(name: trimmed)
                                selectedLabelIDs.insert(created.id)
                                draftLabelName = ""
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)

            // Buttons
            HStack(spacing: Spacing.sm) {
                if let existingCard {
                    Button("Delete") {
                        onDelete?(existingCard)
                        dismiss()
                    }
                    .buttonStyle(CiderDestructiveButtonStyle())
                }

                Spacer(minLength: 0)

                Button("Cancel") { dismiss() }
                    .buttonStyle(CiderSecondaryButtonStyle())

                Button("Save") { save() }
                    .buttonStyle(CiderAccentButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: 420, maxWidth: 560)
    }

    // MARK: - Checklist Item Row

    @ViewBuilder
    private func checklistItemRow(index: Int, item: TodoChecklistItem) -> some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                // Reorder controls
                VStack(spacing: 0) {
                    Button {
                        guard index > 0 else { return }
                        checklist.swapAt(index, index - 1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(CiderFont.microBold)
                            .foregroundColor(index > 0 ? CiderColors.tertiary : CiderColors.quaternary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    .help("Move up")

                    Button {
                        guard index < checklist.count - 1 else { return }
                        checklist.swapAt(index, index + 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(CiderFont.microBold)
                            .foregroundColor(index < checklist.count - 1 ? CiderColors.tertiary : CiderColors.quaternary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= checklist.count - 1)
                    .help("Move down")
                }
                .frame(width: 12)

                Button {
                    checklist[index].isCompleted.toggle()
                    checklist[index].completedAt = checklist[index].isCompleted ? Date() : nil
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(item.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                }
                .buttonStyle(.plain)
                .help(item.isCompleted ? "Mark incomplete" : "Mark complete")

                TextField("Item", text: binding(for: index, keyPath: \.title))
                    .textFieldStyle(.roundedBorder)
                    .font(CiderFont.body)

                Button {
                    checklist.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                }
                .buttonStyle(.plain)
                .help("Remove item")
            }

            // Optional fields row: due date + amount
            HStack(spacing: Spacing.sm) {
                // Due date
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "calendar")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                    if checklist[index].dueDate != nil {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { checklist[index].dueDate ?? Date() },
                                set: { checklist[index].dueDate = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .controlSize(.small)
                        Button {
                            checklist[index].dueDate = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.quaternary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove due date")
                    } else {
                        Button("Add date") {
                            checklist[index].dueDate = Date()
                        }
                        .font(CiderFont.caption)
                        .buttonStyle(.borderless)
                    }
                }

                Spacer(minLength: 0)

                // Amount
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "dollarsign.circle")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                    TextField("$", value: binding(for: index, keyPath: \.amount), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .controlSize(.small)
                }

                // URL
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "link")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                    TextField("URL", text: binding(for: index, keyPath: \.urlString, default: ""))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .controlSize(.small)
                }
            }
            .padding(.leading, Spacing.lg + Spacing.xs)

            // Subtasks
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(Array(checklist[index].subtasks.enumerated()), id: \.element.id) { subIdx, subtask in
                    HStack(spacing: Spacing.xs) {
                        Button {
                            checklist[index].subtasks[subIdx].isCompleted.toggle()
                            checklist[index].subtasks[subIdx].completedAt = checklist[index].subtasks[subIdx].isCompleted ? Date() : nil
                        } label: {
                            Image(systemName: subtask.isCompleted ? "checkmark.square.fill" : "square")
                                .font(CiderFont.captionMedium)
                                .foregroundColor(subtask.isCompleted ? CiderColors.controlAccent : CiderColors.quaternary)
                        }
                        .buttonStyle(.plain)
                        .help(subtask.isCompleted ? "Mark sub-task incomplete" : "Mark sub-task complete")

                        TextField("Sub-task", text: Binding(
                            get: { checklist[index].subtasks[subIdx].title },
                            set: { checklist[index].subtasks[subIdx].title = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(CiderFont.caption)
                        .controlSize(.small)

                        Button {
                            checklist[index].subtasks.remove(at: subIdx)
                        } label: {
                            Image(systemName: "xmark")
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.quaternary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove sub-task")
                    }
                }

                Button {
                    checklist[index].subtasks.append(TodoSubtask(title: ""))
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionMedium)
                        Text("Add sub-task")
                            .font(CiderFont.caption)
                    }
                    .foregroundColor(CiderColors.quaternary)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, Spacing.lg + Spacing.xs)
        }
    }

    // MARK: - Helpers

    private func binding(for index: Int, keyPath: WritableKeyPath<TodoChecklistItem, String>) -> Binding<String> {
        Binding(
            get: { checklist[index][keyPath: keyPath] },
            set: { checklist[index][keyPath: keyPath] = $0 }
        )
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<TodoChecklistItem, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { checklist[index][keyPath: keyPath] ?? defaultValue },
            set: { checklist[index][keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<TodoChecklistItem, Double?>) -> Binding<Double?> {
        Binding(
            get: { checklist[index][keyPath: keyPath] },
            set: { checklist[index][keyPath: keyPath] = $0 }
        )
    }

    private func addChecklistItem() {
        let trimmed = draftItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TodoChecklistItem(title: trimmed, sortOrder: checklist.count)
        checklist.append(item)
        draftItemTitle = ""
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        var card = existingCard ?? TodoCard(title: trimmedTitle)
        card.title = trimmedTitle
        card.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        card.dueDate = hasDueDate ? dueDate : nil
        card.priority = priority
        // Update sortOrder to match current array position
        for i in checklist.indices {
            checklist[i].sortOrder = i
        }
        card.checklist = checklist
        card.labelIDs = Array(selectedLabelIDs)

        onSave(card)
        dismiss()
    }

    private func labelChip(_ label: CardLabel) -> some View {
        let isOn = selectedLabelIDs.contains(label.id)
        return Button {
            if isOn {
                selectedLabelIDs.remove(label.id)
            } else {
                selectedLabelIDs.insert(label.id)
            }
        } label: {
            Text(label.name)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove \(label.name) label" : "Add \(label.name) label")
    }
}

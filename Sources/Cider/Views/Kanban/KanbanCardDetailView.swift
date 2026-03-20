import SwiftUI

/// Detail editor for a Kanban card. Shown as a sheet when clicking a card.
struct KanbanCardDetailView: View {
    @State var card: KanbanCard
    let boardID: String
    let storage: KanbanStorage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Edit Card")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            Divider().background(CiderColors.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Title
                    fieldSection("Title") {
                        TextField("Card title", text: $card.title)
                            .textFieldStyle(.plain)
                            .font(CiderFont.label)
                    }

                    // Notes
                    fieldSection("Notes") {
                        TextField("Add notes...", text: Binding(
                            get: { card.notes ?? "" },
                            set: { card.notes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(CiderFont.body)
                            .lineLimit(1...8)
                    }

                    // Color
                    fieldSection("Color") {
                        HStack(spacing: Spacing.sm) {
                            colorButton(nil, label: "None")
                            ForEach(KanbanCardColor.allCases, id: \.self) { color in
                                colorButton(color, label: color.rawValue.capitalized)
                            }
                        }
                    }

                    // Priority
                    fieldSection("Priority") {
                        HStack(spacing: Spacing.sm) {
                            priorityButton(nil, label: "None")
                            ForEach(KanbanPriority.allCases, id: \.self) { priority in
                                priorityButton(priority, label: priority.rawValue.capitalized)
                            }
                        }
                    }

                    // Agent
                    fieldSection("Agent") {
                        TextField("Assigned agent...", text: Binding(
                            get: { card.agent ?? "" },
                            set: { card.agent = $0.isEmpty ? nil : $0 }
                        ))
                            .textFieldStyle(.plain)
                            .font(CiderFont.body)
                    }

                    // Tags
                    fieldSection("Tags") {
                        TextField("Comma-separated tags...", text: Binding(
                            get: { card.tags.joined(separator: ", ") },
                            set: { card.tags = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                        ))
                            .textFieldStyle(.plain)
                            .font(CiderFont.body)
                    }

                    // Created date
                    HStack {
                        Text("Created")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                        Spacer()
                        Text(card.created, style: .date)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    if let completed = card.completed {
                        HStack {
                            Text("Completed")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.success)
                            Spacer()
                            Text(completed, style: .date)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.success)
                        }
                    }
                }
                .padding(Spacing.lg)
            }

            Divider().background(CiderColors.separator)

            // Footer with save
            HStack {
                Button("Delete Card", role: .destructive) {
                    storage.deleteCard(boardID: boardID, cardID: card.id)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.destructive)

                Spacer()

                Button("Save") {
                    storage.updateCard(boardID: boardID, card: card)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.controlAccent)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: 400, height: 500)
        .background(CiderColors.opaqueBackground)
    }

    // MARK: - Field Section

    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            content()
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
        }
    }

    // MARK: - Color Buttons

    private func colorButton(_ color: KanbanCardColor?, label: String) -> some View {
        Button {
            card.color = color
        } label: {
            if let color {
                Circle()
                    .fill(kanbanColor(color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(card.color == color ? CiderColors.primary : Color.clear, lineWidth: 2)
                    )
            } else {
                Circle()
                    .strokeBorder(CiderColors.borderDefault, lineWidth: 1)
                    .frame(width: 24, height: 24)
                    .overlay(
                        card.color == nil
                            ? AnyView(Image(systemName: "checkmark")
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.primary))
                            : AnyView(EmptyView())
                    )
            }
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Priority Buttons

    private func priorityButton(_ priority: KanbanPriority?, label: String) -> some View {
        let isSelected = card.priority == priority
        return Button {
            card.priority = priority
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(isSelected ? CiderColors.surfaceHover : CiderColors.surfaceInput)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color Helper

    private func kanbanColor(_ color: KanbanCardColor) -> Color {
        switch color {
        case .blue: CiderColors.controlAccent
        case .green: CiderColors.success
        case .orange: CiderColors.warning
        case .red: CiderColors.destructive
        case .purple: CiderColors.controlAccent.opacity(0.7)
        }
    }
}

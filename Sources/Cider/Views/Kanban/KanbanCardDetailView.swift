import SwiftUI

/// Detail editor for a Kanban card. Shown as a sheet when clicking a card.
struct KanbanCardDetailView: View {
    @State var card: KanbanCard
    let boardID: String
    let storage: KanbanStorage
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var notesExpanded = true
    @State private var appearanceExpanded = true
    @State private var assignmentExpanded = false
    @State private var metadataExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(CiderColors.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    titleSection
                    collapsibleSection("Notes", isExpanded: $notesExpanded) {
                        TextEditor(text: notesBinding)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.primary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: notesEditorHeight)
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                    }

                    collapsibleSection("Appearance", isExpanded: $appearanceExpanded) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            fieldLabel("Color")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    colorButton(nil, label: "None")
                                    ForEach(KanbanCardColor.allCases, id: \.self) { color in
                                        colorButton(color, label: color.rawValue.capitalized)
                                    }
                                }
                            }

                            fieldLabel("Priority")
                            HStack(spacing: Spacing.sm) {
                                priorityButton(nil, label: "None")
                                ForEach(KanbanPriority.allCases, id: \.self) { priority in
                                    priorityButton(priority, label: priority.rawValue.capitalized)
                                }
                            }
                        }
                    }

                    collapsibleSection("Assignment", isExpanded: $assignmentExpanded) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            fieldSection("Agent") {
                                TextField("Assigned agent...", text: agentBinding)
                                    .textFieldStyle(.plain)
                                    .font(CiderFont.body)
                            }

                            fieldSection("Tags") {
                                TextField("Comma-separated tags...", text: tagsBinding)
                                    .textFieldStyle(.plain)
                                    .font(CiderFont.body)
                            }
                        }
                    }

                    collapsibleSection("Metadata", isExpanded: $metadataExpanded) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            metadataRow("Created", value: formattedDate(card.created), valueColor: CiderColors.tertiary)
                            if let completed = card.completed {
                                metadataRow("Completed", value: formattedDate(completed), valueColor: CiderColors.success)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }

            Divider().background(CiderColors.separator)

            footer
        }
        .frame(width: 600, height: 700)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CiderColors.opaqueBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(CiderColors.separator.opacity(0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text("Edit Card")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
            Spacer()
            Button {
                close()
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
    }

    private var titleSection: some View {
        fieldSection("Title") {
            TextField("Card title", text: $card.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .lineLimit(1...4)
        }
    }

    private var footer: some View {
        HStack {
            Button("Delete Card", role: .destructive) {
                storage.deleteCard(boardID: boardID, cardID: card.id)
                close()
            }
            .buttonStyle(.plain)
            .font(CiderFont.captionMedium)
            .foregroundColor(CiderColors.destructive)

            Spacer()

            Button("Save") {
                storage.updateCard(boardID: boardID, card: normalizedCard)
                close()
            }
            .buttonStyle(.plain)
            .font(CiderFont.labelSemibold)
            .foregroundColor(CiderColors.controlAccent)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { card.notes ?? "" },
            set: { card.notes = $0 }
        )
    }

    private var agentBinding: Binding<String> {
        Binding(
            get: { card.agent ?? "" },
            set: { card.agent = $0 }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { card.tags.joined(separator: ", ") },
            set: {
                card.tags = $0
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var notesEditorHeight: CGFloat {
        let text = card.notes ?? ""
        let lineEstimate = max(6, min(18, text.split(separator: "\n", omittingEmptySubsequences: false).count + 2))
        return CGFloat(lineEstimate * 22)
    }

    private var normalizedCard: KanbanCard {
        var updated = card
        let title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = title.isEmpty ? "Untitled Card" : title

        if let notes = updated.notes?.trimmingCharacters(in: .whitespacesAndNewlines), notes.isEmpty {
            updated.notes = nil
        } else {
            updated.notes = updated.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let agent = updated.agent?.trimmingCharacters(in: .whitespacesAndNewlines), agent.isEmpty {
            updated.agent = nil
        } else {
            updated.agent = updated.agent?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        updated.tags = updated.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return updated
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(CiderFont.captionSemibold)
            .foregroundColor(CiderColors.tertiary)
    }

    private func metadataRow(_ label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            Spacer()
            Text(value)
                .font(CiderFont.caption)
                .foregroundColor(valueColor)
        }
    }

    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            fieldLabel(label)
            content()
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
        }
    }

    private func collapsibleSection<Content: View>(
        _ label: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Text(label)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

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
                            .strokeBorder(card.color == color ? CiderColors.primary : Color.clear, lineWidth: CiderBorder.colorPickerRingWidth)
                    )
            } else {
                Circle()
                    .strokeBorder(CiderColors.borderDefault, lineWidth: CiderBorder.thinStrokeWidth)
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

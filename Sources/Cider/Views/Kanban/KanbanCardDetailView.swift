import SwiftUI

/// Long-form editor for a Kanban card inside the shared Cider detail panel.
struct KanbanCardDetailView: View {
    let boardName: String
    let cardID: String
    @Binding var draft: KanbanCardDraft
    var onSave: () -> Void

    @FocusState private var notesFocused: Bool

    init(boardName: String, cardID: String, draft: Binding<KanbanCardDraft>, onSave: @escaping () -> Void) {
        self.boardName = boardName
        self.cardID = cardID
        _draft = draft
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                KanbanCardDashboardView(boardName: boardName, cardID: cardID, title: draft.title, notes: draft.notes)
                    .frame(minWidth: 340, idealWidth: 430, maxWidth: 520, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Source Notes")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    TextEditor(text: $draft.notes)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.primary)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($notesFocused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .center, spacing: Spacing.md) {
                Spacer(minLength: Spacing.sm)

                Button("Save") {
                    onSave()
                }
                .buttonStyle(CiderAccentButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }
}

private struct KanbanCardDashboardView: View {
    let boardName: String
    let cardID: String
    let title: String
    let notes: String

    private var model: KanbanCardDashboardModel {
        KanbanCardDashboardModel(title: title, notes: notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CiderColors.controlAccent)

                Text("Second-Brain Dashboard")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Spacer(minLength: Spacing.sm)

                KanbanDashboardBadge(text: model.hasStructuredContent ? "\(model.sections.count) sections" : "unstructured")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    KanbanDashboardCurrentStateView(model: model)

                    if !model.testingGuidanceEntries.isEmpty {
                        KanbanDashboardTestingGuidanceView(entries: model.testingGuidanceEntries)
                    }

                    KanbanDashboardTripleSection(model: model)

                    KanbanDashboardEntryGroup(
                        icon: "checklist",
                        title: "Open Loops / Next Actions",
                        entries: model.openLoops,
                        emptyText: model.nextStep ?? "No open loops or next actions recorded."
                    )

                    KanbanDashboardEntryGroup(
                        icon: "seal",
                        title: "Decisions",
                        entries: model.decisions,
                        emptyText: "No decisions recorded yet."
                    )

                    KanbanDashboardEntryGroup(
                        icon: "clock.badge.checkmark",
                        title: "Evidence & Test History",
                        entries: model.evidenceEntries,
                        emptyText: "No test or QA evidence recorded."
                    )

                    KanbanDashboardEntryGroup(
                        icon: "link",
                        title: "Related Links / Cards / Items",
                        entries: model.relatedItems,
                        emptyText: "No related cards, docs backlinks, or linked items recorded."
                    )

                    KanbanDashboardAgentHandoffView(boardName: boardName, cardID: cardID, context: model.agentContext)

                    if !model.missingCoreSections.isEmpty {
                        KanbanDashboardMissingSectionsView(sections: model.missingCoreSections)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct KanbanDashboardTestingGuidanceView: View {
    let entries: [KanbanCardDashboardEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.seal")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.warning)
                Text("What To Test")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer(minLength: Spacing.sm)
                KanbanDashboardBadge(text: "\(entries.count)")
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(entries.prefix(6)) { entry in
                    KanbanDashboardEntryRow(entry: entry)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.warning.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct KanbanDashboardCurrentStateView: View {
    let model: KanbanCardDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(model.currentState ?? model.fallbackSummary)
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.xs) {
                KanbanDashboardBadge(text: model.hasStructuredContent ? "structured" : "needs structure")
                if let nextStep = model.nextStep {
                    KanbanDashboardBadge(text: "next: \(nextStep)")
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.controlAccent.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct KanbanDashboardTripleSection: View {
    let model: KanbanCardDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KanbanDashboardTextBlock(title: "Problem", text: model.problem, emptyText: "No problem statement yet.")
            KanbanDashboardTextBlock(title: "Goal", text: model.goal, emptyText: "No goal statement yet.")
            KanbanDashboardTextBlock(title: "Scope", text: model.scope, emptyText: "No scope or acceptance criteria recorded.")
        }
    }
}

private struct KanbanDashboardTextBlock: View {
    let title: String
    let text: String?
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text(text ?? emptyText)
                .font(CiderFont.caption)
                .foregroundColor(text == nil ? CiderColors.tertiary : CiderColors.secondary)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.separator.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct KanbanDashboardEntryGroup: View {
    let icon: String
    let title: String
    let entries: [KanbanCardDashboardEntry]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                Text(title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer(minLength: Spacing.sm)
                KanbanDashboardBadge(text: "\(entries.count)")
            }

            if entries.isEmpty {
                Text(emptyText)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(entries.prefix(6)) { entry in
                        KanbanDashboardEntryRow(entry: entry)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.separator.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct KanbanDashboardEntryRow: View {
    let entry: KanbanCardDashboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(CiderColors.controlAccent.opacity(0.75))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                if entry.dateLabel != nil || entry.source != nil {
                    HStack(spacing: Spacing.xs) {
                        if let dateLabel = entry.dateLabel {
                            Text(dateLabel)
                        }
                        if let source = entry.source {
                            Text(source)
                        }
                    }
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
                }

                Text(entry.body)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct KanbanDashboardAgentHandoffView: View {
    let boardName: String
    let cardID: String
    let context: KanbanCardAgentContext

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "terminal")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                Text("Agent Handoff")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
            }

            Text(context.notes)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(7)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(context.commands(board: boardName, cardID: cardID).prefix(3), id: \.self) { command in
                    Text(command)
                        .font(CiderFont.microMonospaced)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.separator.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct KanbanDashboardMissingSectionsView: View {
    let sections: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Structure Hints")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text("Missing: \(sections.joined(separator: ", "))")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KanbanDashboardBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CiderFont.microMedium)
            .foregroundColor(CiderColors.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(CiderColors.surfaceInput))
    }
}

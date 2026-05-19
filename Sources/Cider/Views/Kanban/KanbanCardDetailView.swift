import SwiftUI

private enum KanbanCardDetailMode: String, CaseIterable, Identifiable {
    case overview
    case agentContext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .agentContext: "Agent Context"
        }
    }
}

/// Long-form editor for a Kanban card inside the shared Cider detail panel.
struct KanbanCardDetailView: View {
    let boardID: String
    let boardName: String
    let cardID: String
    @Binding var draft: KanbanCardDraft
    @Binding var sourceNotesVisible: Bool
    var onSave: () -> Void

    @FocusState private var notesFocused: Bool
    @State private var newHistoryType: KanbanCardHistoryEntryType = .note
    @State private var newHistoryBody = ""
    @State private var mode: KanbanCardDetailMode = .overview

    init(
        boardID: String,
        boardName: String,
        cardID: String,
        draft: Binding<KanbanCardDraft>,
        sourceNotesVisible: Binding<Bool>,
        onSave: @escaping () -> Void
    ) {
        self.boardID = boardID
        self.boardName = boardName
        self.cardID = cardID
        _draft = draft
        _sourceNotesVisible = sourceNotesVisible
        self.onSave = onSave
    }

    private var qualityReport: KanbanCardQualityReport {
        KanbanCardQualityReport(notes: draft.notes)
    }

    private var notesOutline: KanbanCardNotesOutline {
        KanbanCardNotesOutline(notes: draft.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Picker("Card detail view", selection: $mode) {
                ForEach(KanbanCardDetailMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)

            HStack(alignment: .top, spacing: Spacing.xl) {
                Group {
                    switch mode {
                    case .overview:
                        KanbanCardDashboardView(
                            boardID: boardID,
                            boardName: boardName,
                            cardID: cardID,
                            title: draft.title,
                            notes: draft.notes,
                            historyEntries: $draft.historyEntries,
                            newHistoryType: $newHistoryType,
                            newHistoryBody: $newHistoryBody
                        )
                    case .agentContext:
                        KanbanCardAgentContextView(
                            notes: $draft.notes,
                            historyEntries: $draft.historyEntries,
                            newHistoryType: $newHistoryType,
                            newHistoryBody: $newHistoryBody,
                            qualityReport: qualityReport,
                            notesOutline: notesOutline,
                            notesFocused: $notesFocused
                        )
                    }
                }
                .frame(
                    minWidth: KanbanDetailSlideOutLayoutPolicy.dashboardMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

                if sourceNotesVisible && mode == .overview {
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
                    .frame(
                        minWidth: KanbanDetailSlideOutLayoutPolicy.sourceNotesMinimumWidth,
                        idealWidth: 520,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
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
        .onChange(of: sourceNotesVisible) { _, isVisible in
            if !isVisible {
                notesFocused = false
            }
        }
    }
}

private struct KanbanCardAgentContextView: View {
    @Binding var notes: String
    @Binding var historyEntries: [KanbanCardHistoryEntry]
    @Binding var newHistoryType: KanbanCardHistoryEntryType
    @Binding var newHistoryBody: String
    let qualityReport: KanbanCardQualityReport
    let notesOutline: KanbanCardNotesOutline
    var notesFocused: FocusState<Bool>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                KanbanCardQualityChecklistView(report: qualityReport)

                KanbanCardHistorySectionView(
                    entries: $historyEntries,
                    newEntryType: $newHistoryType,
                    newEntryBody: $newHistoryBody
                )

                if notesOutline.hasStructuredSections {
                    KanbanCardNotesOutlineView(outline: notesOutline)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Spec / Notes")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    TextEditor(text: $notes)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.primary)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused(notesFocused)
                        .frame(minHeight: 280)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct KanbanSourceNotesToggleButton: View {
    @Binding var isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isVisible.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: isVisible ? "doc.text.fill" : "doc.text")
                        .font(CiderFont.toolbarIcon)
                        .foregroundColor(isVisible ? CiderColors.controlAccent : CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .help(isVisible ? "Hide Source Notes" : "Show Source Notes")
    }
}

private struct KanbanCardDashboardView: View {
    let boardID: String
    let boardName: String
    let cardID: String
    let title: String
    let notes: String
    @Binding var historyEntries: [KanbanCardHistoryEntry]
    @Binding var newHistoryType: KanbanCardHistoryEntryType
    @Binding var newHistoryBody: String

    @ObservedObject private var storage = KanbanStorage.shared

    private var model: KanbanCardDashboardModel {
        KanbanCardDashboardModel(title: title, notes: notes)
    }

    private var childRollup: KanbanParentChildRollup? {
        guard let board = storage.boards.first(where: { $0.id == boardID || $0.name == boardName }) else {
            return nil
        }
        return KanbanParentChildRollup(board: board, parentID: cardID)
    }

    private var roadmapNextUp: KanbanRoadmapNextUpProjection? {
        guard let board = storage.boards.first(where: { $0.id == boardID || $0.name == boardName }) else {
            return nil
        }
        return KanbanRoadmapNextUpProjection(board: board, parentID: cardID)
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

                    if let childRollup {
                        KanbanDashboardChildRollupView(
                            rollup: childRollup,
                            roadmapNextUp: roadmapNextUp
                        )
                    }

                    if !model.testingGuidanceEntries.isEmpty {
                        KanbanDashboardTestingGuidanceView(
                            boardID: boardID,
                            boardName: boardName,
                            cardID: cardID,
                            cardTitle: title,
                            entries: model.testingGuidanceEntries
                        )
                    }

                    KanbanCardHistorySectionView(
                        entries: $historyEntries,
                        newEntryType: $newHistoryType,
                        newEntryBody: $newHistoryBody
                    )

                    KanbanDashboardTripleSection(model: model)

                    if !model.qaFindingsEntries.isEmpty {
                        KanbanDashboardEntryGroup(
                            icon: "exclamationmark.triangle",
                            title: "QA Findings",
                            entries: model.qaFindingsEntries,
                            emptyText: "No failed QA findings recorded."
                        )
                    }

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

private struct KanbanDashboardChildRollupView: View {
    let rollup: KanbanParentChildRollup
    let roadmapNextUp: KanbanRoadmapNextUpProjection?

    private var visibleChildren: ArraySlice<KanbanParentChildRollup.Child> {
        rollup.children.prefix(5)
    }

    private var countBadges: [String] {
        [
            rollup.counts.backlog > 0 ? "\(rollup.counts.backlog) backlog" : nil,
            rollup.counts.queued > 0 ? "\(rollup.counts.queued) queued" : nil,
            rollup.counts.inProgress > 0 ? "\(rollup.counts.inProgress) active" : nil,
            rollup.counts.testing > 0 ? "\(rollup.counts.testing) testing" : nil,
            rollup.counts.needsFix > 0 ? "\(rollup.counts.needsFix) needs fix" : nil,
            rollup.counts.done > 0 ? "\(rollup.counts.done) done" : nil,
            rollup.counts.other > 0 ? "\(rollup.counts.other) other" : nil,
        ].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "list.bullet.indent")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                Text("Child Rollup")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer(minLength: Spacing.sm)
                KanbanDashboardBadge(text: "\(rollup.totalChildCount) children")
                if rollup.isComplete {
                    KanbanDashboardBadge(text: "complete")
                }
            }

            Text(rollup.statusLine)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(rollup.nextActionLine)
                .font(CiderFont.captionSemibold)
                .foregroundColor(rollup.failedQAChild == nil ? CiderColors.primary : CiderColors.warning)
                .fixedSize(horizontal: false, vertical: true)

            if !countBadges.isEmpty {
                TagFlowLayout(spacing: Spacing.xs) {
                    ForEach(countBadges, id: \.self) { badge in
                        KanbanDashboardBadge(text: badge)
                    }
                }
            }

            if roadmapNextUp == nil, let currentGate = rollup.currentGate {
                KanbanDashboardChildRollupRow(label: "Current Gate", child: currentGate)
            }

            if let roadmapNextUp {
                KanbanDashboardRoadmapGroupsView(nextUp: roadmapNextUp)
            } else if !visibleChildren.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Array(visibleChildren)) { child in
                        KanbanDashboardChildRollupRow(label: nil, child: child)
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
                .stroke(CiderColors.controlAccent.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct KanbanDashboardRoadmapGroupsView: View {
    let nextUp: KanbanRoadmapNextUpProjection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(nextUp.groups) { group in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(group.label)
                        .font(CiderFont.microMedium)
                        .foregroundColor(CiderColors.tertiary)

                    ForEach(group.items) { item in
                        KanbanDashboardRoadmapStepRow(item: item)
                    }
                }
            }
        }
    }
}

private struct KanbanDashboardRoadmapStepRow: View {
    let item: KanbanRoadmapNextUpProjection.SequenceItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: iconName)
                .font(CiderFont.microMedium)
                .foregroundColor(item.hasFailedQA ? CiderColors.warning : CiderColors.tertiary)
                .frame(width: 14)

            Text("Step \(item.stepNumber)/\(item.stepCount)")
                .font(CiderFont.microMedium)
                .foregroundColor(item.isCurrentGate ? CiderColors.controlAccent : CiderColors.tertiary)

            Text(item.title)
                .font(item.isNextActionable ? CiderFont.captionSemibold : CiderFont.caption)
                .foregroundColor(item.isNextActionable ? CiderColors.primary : CiderColors.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Spacing.xs)

            Text(item.columnName)
                .font(CiderFont.microMedium)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var iconName: String {
        if item.hasFailedQA {
            return "exclamationmark.triangle.fill"
        }

        switch item.role {
        case .backlog:
            return "tray"
        case .queued:
            return "line.3.horizontal.decrease.circle"
        case .inProgress:
            return "play.circle"
        case .testing:
            return "checkmark.seal"
        case .needsFix:
            return "wrench.adjustable"
        case .done:
            return "checkmark.circle"
        case .other:
            return "circle"
        }
    }
}

private struct KanbanDashboardChildRollupRow: View {
    let label: String?
    let child: KanbanParentChildRollup.Child

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: iconName)
                .font(CiderFont.microMedium)
                .foregroundColor(child.hasFailedQA ? CiderColors.warning : CiderColors.tertiary)
                .frame(width: 14)

            if let label {
                Text(label)
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
            }

            Text(child.title)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Spacing.xs)

            Text(child.columnName)
                .font(CiderFont.microMedium)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var iconName: String {
        if child.hasFailedQA {
            return "exclamationmark.triangle.fill"
        }

        switch child.role {
        case .backlog:
            return "tray"
        case .queued:
            return "line.3.horizontal.decrease.circle"
        case .inProgress:
            return "play.circle"
        case .testing:
            return "checkmark.seal"
        case .needsFix:
            return "wrench.adjustable"
        case .done:
            return "checkmark.circle"
        case .other:
            return "circle"
        }
    }
}

private struct KanbanDashboardTestingGuidanceView: View {
    let boardID: String
    let boardName: String
    let cardID: String
    let cardTitle: String
    let entries: [KanbanCardDashboardEntry]

    @ObservedObject private var progressStore = KanbanTestingGuideProgressStore.shared

    private var companionPayload: KanbanTestingGuidePanelPayload {
        KanbanTestingGuidePanelModel(
            boardID: boardID,
            boardName: boardName,
            cardID: cardID,
            cardTitle: cardTitle,
            entries: entries
        ).payload
    }

    private var visibleSteps: [KanbanTestingGuideStep] {
        Array(companionPayload.steps.prefix(6))
    }

    private var completedStepCount: Int {
        progressStore.completedCount(guideID: companionPayload.id, steps: companionPayload.steps)
    }

    private var failedStepCount: Int {
        progressStore.failedCount(guideID: companionPayload.id, steps: companionPayload.steps)
    }

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
                if completedStepCount > 0 {
                    KanbanDashboardBadge(text: "\(completedStepCount) passed")
                }
                if failedStepCount > 0 {
                    KanbanDashboardBadge(text: "\(failedStepCount) failed")
                }
                Button {
                    let surface = CiderFloatableSurface.kanbanTestingGuide(companionPayload)
                    NotificationCenter.default.post(
                        name: .floatCiderSurface,
                        object: surface,
                        userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
                    )
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Pop out What To Test")
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(visibleSteps.enumerated()), id: \.element.id) { index, step in
                    KanbanTestingGuideStepRow(
                        guideID: companionPayload.id,
                        payload: companionPayload,
                        step: step,
                        stepIndex: index,
                        label: "Step \(index + 1)",
                        textFont: CiderFont.caption
                    )
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

private struct KanbanCardNotesOutlineView: View {
    var outline: KanbanCardNotesOutline

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("Readable Sections")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("\(outline.sections.count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CiderColors.surfaceInput))

                Spacer(minLength: Spacing.sm)

                Text("Preview only — raw notes stay editable below")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            if !outline.leadingText.isEmpty {
                Text(outline.leadingText)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm, alignment: .top)], alignment: .leading, spacing: Spacing.sm) {
                ForEach(outline.sections) { section in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(section.title)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.primary)

                        if section.bulletItems.isEmpty {
                            Text(section.body.isEmpty ? "No details yet." : section.body)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                                .lineSpacing(3)
                                .lineLimit(5)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(section.bulletItems.prefix(4), id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                                        Text("•")
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.tertiary)
                                        Text(item)
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.secondary)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CiderColors.surfaceInput.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                    )
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

private struct KanbanCardHistorySectionView: View {
    @Binding var entries: [KanbanCardHistoryEntry]
    @Binding var newEntryType: KanbanCardHistoryEntryType
    @Binding var newEntryBody: String

    private var sortedEntries: [KanbanCardHistoryEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    private var canAddEntry: Bool {
        !newEntryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("History")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("\(entries.count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CiderColors.surfaceInput))

                Spacer(minLength: Spacing.sm)

                Text("Typed card memory")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            if entries.isEmpty {
                Text("No structured history yet. Add implementation notes, failed attempts, test evidence, summaries, or commits without replacing the main notes field.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(sortedEntries) { entry in
                        KanbanCardHistoryEntryRow(entry: entry)
                    }
                }
            }

            Divider()
                .overlay(CiderColors.borderSubtle)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Picker("Type", selection: $newEntryType) {
                        ForEach(KanbanCardHistoryEntryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    Spacer(minLength: Spacing.sm)

                    Button("Add History") {
                        addEntry()
                    }
                    .buttonStyle(CiderAccentButtonStyle())
                    .disabled(!canAddEntry)
                }

                TextEditor(text: $newEntryBody)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.primary)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                    .frame(minHeight: 58, maxHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CiderColors.surfaceInput.opacity(0.6))
                    )
                    .overlay(alignment: .topLeading) {
                        if newEntryBody.isEmpty {
                            Text("Add a focused history entry…")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.sm)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CiderColors.borderDefault, lineWidth: 1)
                )
        )
    }

    private func addEntry() {
        let trimmedBody = newEntryBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        entries.append(
            KanbanCardHistoryEntry(
                type: newEntryType,
                body: trimmedBody,
                createdAt: Date()
            )
        )
        newEntryBody = ""
        newEntryType = .note
    }
}

private struct KanbanCardHistoryEntryRow: View {
    var entry: KanbanCardHistoryEntry

    private var timestamp: String {
        entry.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: entry.type.symbolName)
                .font(.caption)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(entry.type.displayName)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)

                    Text(timestamp)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    if let author = entry.author, !author.isEmpty {
                        Text("• \(author)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Text(entry.body)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }
}

private struct KanbanCardQualityChecklistView: View {
    var report: KanbanCardQualityReport

    private var statusColor: Color {
        switch report.status {
        case .ready:
            CiderColors.success
        case .needsContext:
            CiderColors.warning
        }
    }

    private var statusIcon: String {
        switch report.status {
        case .ready:
            "checkmark.seal.fill"
        case .needsContext:
            "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)

                Text(report.summary)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: Spacing.sm)

                Text("Agent checklist")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: Spacing.xs)],
                alignment: .leading,
                spacing: Spacing.xs
            ) {
                ForEach(report.items) { item in
                    KanbanCardQualityChecklistChip(item: item)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusColor.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

private struct KanbanCardQualityChecklistChip: View {
    var item: KanbanCardQualityReport.Item

    private var color: Color {
        item.isPresent ? CiderColors.success : CiderColors.tertiary
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isPresent ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(color)

            Text(item.section.displayName)
                .font(CiderFont.caption)
                .foregroundColor(item.isPresent ? CiderColors.secondary : CiderColors.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(item.isPresent ? 0.10 : 0.06))
        )
        .help(item.isPresent ? "Section detected" : "Missing optional/essential context")
    }
}

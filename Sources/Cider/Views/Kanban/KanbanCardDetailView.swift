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
    @State private var newCommentKind: KanbanCardCommentKind = .note
    @State private var newCommentBody = ""
    @State private var replyingToCommentID: String?
    @State private var replyCommentBody = ""
    @State private var collapsedThreadIDs: Set<String> = []
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

    private var currentCommentAuthorName: String {
        KanbanCardCommentThreadPolicy.defaultAuthorName(
            accountEmail: AuthService.shared.accountEmail,
            fullUserName: NSFullUserName(),
            userName: NSUserName()
        )
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
                            aiSummary: draft.aiSummary,
                            priority: draft.priority,
                            tagsText: draft.tagsText,
                            comments: $draft.comments,
                            newCommentKind: $newCommentKind,
                            newCommentBody: $newCommentBody,
                            replyingToCommentID: $replyingToCommentID,
                            replyCommentBody: $replyCommentBody,
                            collapsedThreadIDs: $collapsedThreadIDs,
                            currentAuthorName: currentCommentAuthorName,
                            onCommentChanged: onSave,
                            historyEntries: $draft.historyEntries,
                            newHistoryType: $newHistoryType,
                            newHistoryBody: $newHistoryBody
                        )
                    case .agentContext:
                        KanbanCardAgentContextView(
                            notes: $draft.notes,
                            comments: $draft.comments,
                            newCommentKind: $newCommentKind,
                            newCommentBody: $newCommentBody,
                            replyingToCommentID: $replyingToCommentID,
                            replyCommentBody: $replyCommentBody,
                            collapsedThreadIDs: $collapsedThreadIDs,
                            currentAuthorName: currentCommentAuthorName,
                            onCommentChanged: onSave,
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
    @Binding var comments: [KanbanCardComment]
    @Binding var newCommentKind: KanbanCardCommentKind
    @Binding var newCommentBody: String
    @Binding var replyingToCommentID: String?
    @Binding var replyCommentBody: String
    @Binding var collapsedThreadIDs: Set<String>
    var currentAuthorName: String
    var onCommentChanged: () -> Void
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

                KanbanCardCommentsSectionView(
                    comments: $comments,
                    newCommentKind: $newCommentKind,
                    newCommentBody: $newCommentBody,
                    replyingToCommentID: $replyingToCommentID,
                    replyCommentBody: $replyCommentBody,
                    collapsedThreadIDs: $collapsedThreadIDs,
                    currentAuthorName: currentAuthorName,
                    onCommentChanged: onCommentChanged
                )

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
    let aiSummary: String?
    let priority: KanbanPriority?
    let tagsText: String
    @Binding var comments: [KanbanCardComment]
    @Binding var newCommentKind: KanbanCardCommentKind
    @Binding var newCommentBody: String
    @Binding var replyingToCommentID: String?
    @Binding var replyCommentBody: String
    @Binding var collapsedThreadIDs: Set<String>
    var currentAuthorName: String
    var onCommentChanged: () -> Void
    @Binding var historyEntries: [KanbanCardHistoryEntry]
    @Binding var newHistoryType: KanbanCardHistoryEntryType
    @Binding var newHistoryBody: String

    @ObservedObject private var storage = KanbanStorage.shared
    @State private var legacyContextExpanded = false

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

    private var displayKey: String {
        guard let board = storage.boards.first(where: { $0.id == boardID || $0.name == boardName }),
              let card = board.card(id: cardID) else {
            return String(cardID.prefix(8)).uppercased()
        }
        return board.displayKey(for: card)
    }

    private var tagList: [String] {
        tagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var currentStatusLabel: String? {
        guard let board = storage.boards.first(where: { $0.id == boardID || $0.name == boardName }) else {
            return nil
        }
        return board.columns.first(where: { column in
            column.cards.contains { $0.id == cardID }
        })?.name
    }

    private var readablePolicy: KanbanCardDetailReadableLayoutPolicy {
        KanbanCardDetailReadableLayoutPolicy(
            card: KanbanCard(
                id: cardID,
                title: title,
                notes: notes,
                aiSummary: aiSummary,
                priority: priority,
                tags: tagList,
                historyEntries: historyEntries,
                comments: comments
            ),
            statusLabel: currentStatusLabel
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CiderColors.controlAccent)

                Text("Command Thread")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Spacer(minLength: Spacing.sm)

                KanbanDashboardBadge(text: displayKey)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !readablePolicy.headerBadges.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ForEach(readablePolicy.headerBadges.prefix(4), id: \.self) { badge in
                            KanbanDashboardBadge(text: badge)
                        }
                    }
                }

                if !readablePolicy.shortSummary.isEmpty {
                    Text(readablePolicy.shortSummary)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .lineSpacing(3)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    KanbanCardCommentsSectionView(
                        comments: $comments,
                        newCommentKind: $newCommentKind,
                        newCommentBody: $newCommentBody,
                        replyingToCommentID: $replyingToCommentID,
                        replyCommentBody: $replyCommentBody,
                        collapsedThreadIDs: $collapsedThreadIDs,
                        currentAuthorName: currentAuthorName,
                        onCommentChanged: onCommentChanged
                    )

                    DisclosureGroup(isExpanded: $legacyContextExpanded) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
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
                        .padding(.top, Spacing.sm)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "archivebox")
                            Text("Legacy notes, projected sections, history, and agent context")
                            Spacer(minLength: Spacing.sm)
                            Text("Collapsed by default")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CiderColors.surfaceElevated.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(CiderColors.borderSubtle, lineWidth: 1)
                            )
                    )
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

private struct KanbanCardCommentsSectionView: View {
    @Binding var comments: [KanbanCardComment]
    @Binding var newCommentKind: KanbanCardCommentKind
    @Binding var newCommentBody: String
    @Binding var replyingToCommentID: String?
    @Binding var replyCommentBody: String
    @Binding var collapsedThreadIDs: Set<String>
    var currentAuthorName: String
    var onCommentChanged: () -> Void

    private var threads: [KanbanCardCommentThreadPolicy.Thread] {
        KanbanCardCommentThreadPolicy.displayThreads(from: comments)
    }

    private var threadCounts: (active: Int, resolved: Int) {
        KanbanCardCommentThreadPolicy.threadCounts(from: comments)
    }

    private var canAddComment: Bool {
        !newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddReply: Bool {
        !replyCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("Comments")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("\(threadCounts.active) active")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.controlAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CiderColors.controlAccent.opacity(0.12)))

                if threadCounts.resolved > 0 {
                    Text("\(threadCounts.resolved) resolved")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CiderColors.surfaceInput))
                }

                Spacer(minLength: Spacing.sm)

                Text("Handoffs, notes, decisions, QA")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            if comments.isEmpty {
                Text("No comments yet. Add human notes, agent handoffs, decisions, evidence, QA, or final reports without growing the source notes wall.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(threads, id: \.root.id) { thread in
                        KanbanCardCommentThreadRow(
                            thread: thread,
                            isCollapsed: collapsedThreadIDs.contains(thread.root.id),
                            isReplying: replyingToCommentID == thread.root.id,
                            replyBody: $replyCommentBody,
                            canAddReply: canAddReply,
                            onToggleCollapse: { toggleCollapse(for: thread.root) },
                            onToggleResolved: { toggleResolved(thread.root) },
                            onReply: { startReply(to: thread.root) },
                            onCancelReply: { cancelReply() },
                            onAddReply: { addReply(to: thread.root) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(CiderColors.borderSubtle)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Picker("Kind", selection: $newCommentKind) {
                        ForEach(KanbanCardCommentKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    Spacer(minLength: Spacing.sm)

                    Button("Add Comment") {
                        addComment()
                    }
                    .buttonStyle(CiderAccentButtonStyle())
                    .disabled(!canAddComment)
                }

                TextEditor(text: $newCommentBody)
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
                        if newCommentBody.isEmpty {
                            Text("Add a focused comment…")
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
        .onAppear(perform: applyResolvedThreadDefaults)
        .onChange(of: comments.map { "\($0.id):\($0.resolvedAt?.timeIntervalSince1970 ?? 0)" }) { _, _ in
            applyResolvedThreadDefaults()
        }
    }

    private func applyResolvedThreadDefaults() {
        collapsedThreadIDs.formUnion(KanbanCardCommentThreadPolicy.defaultCollapsedThreadIDs(from: comments))
    }

    private func addComment() {
        let trimmedBody = newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        comments.append(
            KanbanCardComment(
                kind: newCommentKind,
                body: trimmedBody,
                author: currentAuthorName,
                source: "cider-ui",
                createdAt: Date()
            )
        )
        newCommentBody = ""
        newCommentKind = .note
        persistCommentChange()
    }

    private func startReply(to comment: KanbanCardComment) {
        replyingToCommentID = comment.id
        replyCommentBody = ""
        collapsedThreadIDs.remove(comment.id)
    }

    private func cancelReply() {
        replyingToCommentID = nil
        replyCommentBody = ""
    }

    private func addReply(to comment: KanbanCardComment) {
        let trimmedBody = replyCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        comments.append(
            KanbanCardComment(
                kind: .note,
                body: trimmedBody,
                author: currentAuthorName,
                source: "cider-ui",
                createdAt: Date(),
                parentCommentID: comment.id
            )
        )
        cancelReply()
        persistCommentChange()
    }

    private func toggleResolved(_ comment: KanbanCardComment) {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        if comments[index].isResolved {
            comments[index].resolvedAt = nil
            comments[index].resolvedBy = nil
            collapsedThreadIDs.remove(comment.id)
        } else {
            comments[index].resolvedAt = Date()
            comments[index].resolvedBy = currentAuthorName
            collapsedThreadIDs.insert(comment.id)
        }
        persistCommentChange()
    }

    private func toggleCollapse(for comment: KanbanCardComment) {
        if collapsedThreadIDs.contains(comment.id) {
            collapsedThreadIDs.remove(comment.id)
        } else {
            collapsedThreadIDs.insert(comment.id)
        }
    }

    private func persistCommentChange() {
        DispatchQueue.main.async {
            onCommentChanged()
        }
    }
}

private struct KanbanCardCommentThreadRow: View {
    var thread: KanbanCardCommentThreadPolicy.Thread
    var isCollapsed: Bool
    var isReplying: Bool
    @Binding var replyBody: String
    var canAddReply: Bool
    var onToggleCollapse: () -> Void
    var onToggleResolved: () -> Void
    var onReply: () -> Void
    var onCancelReply: () -> Void
    var onAddReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if thread.isResolved && isCollapsed {
                KanbanCardResolvedThreadSummaryRow(
                    comment: thread.root,
                    onExpand: onToggleCollapse
                )
            } else {
                KanbanCardCommentRow(
                    comment: thread.root,
                    indent: 0,
                    replyCount: thread.replies.count,
                    isThreadCollapsed: isCollapsed,
                    onToggleResolved: onToggleResolved,
                    onToggleCollapse: onToggleCollapse,
                    onReply: onReply
                )
            }

            if !isCollapsed {
                if thread.isResolved {
                    KanbanCardThreadEventRow(
                        comment: thread.root,
                        actionLabel: "Collapse",
                        systemImage: "chevron.up",
                        onAction: onToggleCollapse
                    )
                }

                if !thread.replies.isEmpty || isReplying {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(thread.replies) { reply in
                            KanbanCardCommentRow(comment: reply, indent: 0)
                        }
                        if isReplying {
                            KanbanCardReplyComposer(
                                text: $replyBody,
                                canSubmit: canAddReply,
                                onCancel: onCancelReply,
                                onSubmit: onAddReply
                            )
                        }
                    }
                    .padding(.leading, 28)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(CiderColors.borderSubtle)
                            .frame(width: 2)
                            .padding(.leading, 10)
                    }
                }
            }
        }
    }
}

private struct KanbanCardResolvedThreadSummaryRow: View {
    var comment: KanbanCardComment
    var onExpand: () -> Void

    var body: some View {
        KanbanCardThreadEventRow(
            comment: comment,
            actionLabel: "Expand",
            systemImage: "chevron.down",
            onAction: onExpand
        )
    }
}

private struct KanbanCardThreadEventRow: View {
    var comment: KanbanCardComment
    var actionLabel: String
    var systemImage: String
    var onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundColor(CiderColors.success)
                .frame(width: 18, height: 18)

            Text(KanbanCardCommentThreadPolicy.resolvedSummaryText(for: comment))
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Button(action: onAction) {
                HStack(spacing: 4) {
                    Text(actionLabel)
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.tertiary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CiderColors.surfaceInput.opacity(0.25)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onAction)
    }
}

private struct KanbanCardCommentRow: View {
    var comment: KanbanCardComment
    var indent: CGFloat
    var replyCount: Int = 0
    var isThreadCollapsed: Bool = false
    var onToggleResolved: (() -> Void)? = nil
    var onToggleCollapse: (() -> Void)? = nil
    var onReply: (() -> Void)? = nil

    private var timestamp: String {
        comment.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var hasThreadActions: Bool {
        onReply != nil || onToggleResolved != nil || (replyCount > 0 && onToggleCollapse != nil)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: comment.kind.symbolName)
                .font(.caption)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(comment.kind.displayName)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)

                    Text(timestamp)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    if let author = comment.author, !author.isEmpty {
                        Text("• \(author)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Spacer(minLength: Spacing.sm)

                    if hasThreadActions {
                        Menu {
                            if let onReply {
                                Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
                            }
                            if let onToggleResolved {
                                Button(comment.isResolved ? "Reopen thread" : "Resolve thread", systemImage: comment.isResolved ? "arrow.uturn.backward" : "checkmark", action: onToggleResolved)
                            }
                            if replyCount > 0, let onToggleCollapse {
                                Button(isThreadCollapsed ? "Expand replies" : "Collapse replies", systemImage: isThreadCollapsed ? "chevron.down" : "chevron.up", action: onToggleCollapse)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(CiderColors.tertiary)
                                .frame(width: 22, height: 18)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                }

                if let source = comment.source, !source.isEmpty {
                    Text("#\(comment.permalinkID) • \(source)")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    Text("#\(comment.permalinkID)")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }

                KanbanCommentBodyView(content: comment.body)

            }
        }
        .padding(Spacing.sm)
        .padding(.leading, indent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(indent > 0 ? CiderColors.surfaceInput.opacity(0.45) : CiderColors.surfaceSubtle)
        )
    }
}

private struct KanbanCardReplyComposer: View {
    @Binding var text: String
    var canSubmit: Bool
    var onCancel: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextEditor(text: $text)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.primary)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(Spacing.xs)
                .frame(minHeight: 46, maxHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CiderColors.surfaceInput.opacity(0.55))
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Reply to this thread…")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.sm)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: Spacing.sm) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                Button("Reply", action: onSubmit)
                    .buttonStyle(CiderAccentButtonStyle())
                    .disabled(!canSubmit)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

private struct KanbanCommentBodyView: View {
    let content: String

    var bodyViewLines: [String] {
        KanbanCardCommentThreadPolicy.displayBodyLines(for: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if bodyViewLines.isEmpty {
                Text("No comment text captured.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .italic()
            }
            ForEach(Array(bodyViewLines.enumerated()), id: \.offset) { _, line in
                if let checklist = KanbanMarkdownChecklistLine(line: line) {
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Image(systemName: checklist.isChecked ? "checkmark.square.fill" : "square")
                            .font(CiderFont.caption)
                            .foregroundColor(checklist.isChecked ? CiderColors.controlAccent : CiderColors.tertiary)
                            .padding(.top, 1)
                        Text(checklist.text)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .strikethrough(checklist.isChecked, color: CiderColors.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(line)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .lineSpacing(3)
    }
}

private struct KanbanMarkdownChecklistLine {
    let isChecked: Bool
    let text: String

    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") else {
            return nil
        }
        isChecked = trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")
        text = String(trimmed.dropFirst(6))
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

import SwiftUI

/// Renders a Kanban board as horizontal scrolling columns with draggable cards.
struct KanbanBoardView: View {
    let boardID: String
    var onOpenCard: (String, String) -> Void = { _, _ in }

    @ObservedObject private var storage = KanbanStorage.shared
    @State private var editingBoardName = false
    @State private var boardNameDraft = ""
    @State private var addingCardToColumn: String?
    @State private var newCardTitle = ""
    @State private var renamingColumnID: String?
    @State private var columnNameDraft = ""
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""
    @State private var compactCards = false
    @State private var archiveExpanded = false
    @State private var archiveOpenGeneration = 0
    @State private var collapsedParentCardIDs: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var board: KanbanBoard? {
        storage.boards.first { $0.id == boardID }
    }

    /// Filter cards by search text across title, notes, agent, and tags.
    private func filteredCards(_ cards: [KanbanCard]) -> [KanbanCard] {
        guard !searchText.isEmpty else { return cards }
        let query = searchText.lowercased()
        return cards.filter { card in
            card.title.localizedStandardContains(query) ||
            (card.notes ?? "").localizedStandardContains(query) ||
            (card.agent ?? "").localizedStandardContains(query) ||
            card.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        if let board {
            VStack(spacing: 0) {
                boardHeader(board)
                Divider().background(CiderColors.separator)
                columnsArea(board)
            }
            .onChange(of: boardID) { _, _ in
                collapsedParentCardIDs.removeAll()
            }
        } else {
            emptyState
        }
    }

    // MARK: - Board Header

    private func boardHeader(_ board: KanbanBoard) -> some View {
        HStack(spacing: Spacing.sm) {
            if editingBoardName {
                TextField("Board name", text: $boardNameDraft)
                    .textFieldStyle(.plain)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onSubmit {
                        storage.renameBoard(id: boardID, name: boardNameDraft)
                        editingBoardName = false
                    }
            } else {
                Text(board.name)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onTapGesture(count: 2) {
                        boardNameDraft = board.name
                        editingBoardName = true
                    }
            }

            Text("\(board.columns.reduce(0) { $0 + $1.cards.count }) cards")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)

            if KanbanBoardLayout.usesProjectLayout(for: board) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "rectangle.split.3x1")
                    Text("Project board")
                }
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule(style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.12))
                )
            }

            Spacer()

            // Search field
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "magnifyingglass")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                TextField("Filter cards...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(CiderFont.caption)
                    .frame(width: 100)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )

            // Compact toggle
            Button {
                withAnimation(reduceMotion ? .none : .spring) {
                    compactCards.toggle()
                }
            } label: {
                Image(systemName: compactCards ? "list.bullet" : "rectangle.grid.1x2")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .help(compactCards ? "Expanded view" : "Compact view")

            if KanbanBoardLayout.usesProjectLayout(for: board),
               KanbanBoardLayout.hasArchiveColumns(in: board) {
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.86)) {
                        if !archiveExpanded {
                            archiveOpenGeneration += 1
                        }
                        archiveExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: archiveExpanded ? "archivebox.fill" : "archivebox")
                        Text("Archive")
                    }
                    .font(CiderFont.captionMedium)
                    .foregroundColor(archiveExpanded ? CiderColors.controlAccent : CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(archiveExpanded ? CiderColors.controlAccent.opacity(0.12) : CiderColors.surfaceInput)
                    )
                }
                .buttonStyle(.plain)
                .help(archiveExpanded ? "Hide archive columns" : "Reveal archive columns")
            }

            Button {
                withAnimation(reduceMotion ? .none : .spring) {
                    let name = "New Column"
                    storage.addColumn(boardID: boardID, name: name)
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "plus")
                    Text("Column")
                }
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.controlAccent)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    boardNameDraft = board.name
                    editingBoardName = true
                } label: {
                    Label("Rename Board", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Board", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Delete \"\(board.name)\"?", isPresented: $showDeleteConfirmation) {
                Button("Delete Board", role: .destructive) {
                    if let trashItem = storage.deleteBoard(id: boardID) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .kanbanBoard, trashItem: trashItem))
                    }
                }
            } message: {
                Text("This will permanently delete the board and all its cards. This can't be undone.")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Columns

    @ViewBuilder
    private func columnsArea(_ board: KanbanBoard) -> some View {
        if KanbanBoardLayout.usesProjectLayout(for: board) {
            projectRowsArea(board)
        } else {
            standardColumnsArea(board)
        }
    }

    private func standardColumnsArea(_ board: KanbanBoard) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(board.columns) { column in
                    columnView(column, board: board, width: KanbanDesign.columnWidth)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectRowsArea(_ board: KanbanBoard) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(KanbanBoardLayout.lanes(for: board)) { lane in
                    projectLaneView(lane, board: board)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectLaneView(_ lane: KanbanBoardLane, board: KanbanBoard) -> some View {
        let archiveColumns = archiveExpanded ? KanbanBoardLayout.archiveColumns(for: lane.role, in: board) : []

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(lane.title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("\(lane.columns.count) columns")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)

                Text("\(lane.cardCount) cards")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)

                Spacer()
            }
            .padding(.horizontal, Spacing.xs)

            GeometryReader { geometry in
                let shouldPushArchive = projectLaneNeedsArchivePush(
                    lane: lane,
                    archiveColumns: archiveColumns,
                    availableWidth: geometry.size.width
                )

                HStack(alignment: .top, spacing: Spacing.md) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            ForEach(lane.columns) { column in
                                columnView(
                                    column,
                                    board: board,
                                    width: KanbanDesign.projectColumnWidth,
                                    height: KanbanDesign.projectColumnHeight
                                )
                            }
                        }
                        .padding(.bottom, Spacing.xs)
                    }
                    .frame(maxWidth: .infinity)
                    .defaultScrollAnchor(shouldPushArchive ? .trailing : .leading)
                    .id(projectLaneScrollIdentity(for: lane, shouldPushArchive: shouldPushArchive))

                    if !archiveColumns.isEmpty {
                        projectArchiveReveal(columns: archiveColumns, board: board)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .frame(height: KanbanDesign.projectColumnHeight + Spacing.xs)
            .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.86), value: archiveExpanded)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func projectLaneNeedsArchivePush(
        lane: KanbanBoardLane,
        archiveColumns: [KanbanColumn],
        availableWidth: CGFloat
    ) -> Bool {
        KanbanBoardLayout.shouldPushArchive(
            activeColumnCount: lane.columns.count,
            archiveColumnCount: archiveColumns.count,
            availableWidth: availableWidth,
            columnWidth: KanbanDesign.projectColumnWidth,
            spacing: Spacing.md,
            archiveExpanded: archiveExpanded
        )
    }

    private func projectLaneScrollIdentity(for lane: KanbanBoardLane, shouldPushArchive: Bool) -> String {
        if archiveExpanded {
            return "\(lane.id)-archive-\(archiveOpenGeneration)-push-\(shouldPushArchive)"
        }

        return "\(lane.id)-active"
    }

    private func projectArchiveReveal(columns archiveColumns: [KanbanColumn], board: KanbanBoard) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            archiveRevealDivider

            ForEach(archiveColumns) { column in
                columnView(
                    column,
                    board: board,
                    width: KanbanDesign.projectColumnWidth,
                    height: KanbanDesign.projectColumnHeight
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(CiderColors.controlAccent.opacity(0.35), lineWidth: CiderBorder.hairlineStrokeWidth)
                )
            }
        }
    }

    private var archiveRevealDivider: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "chevron.right")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.controlAccent)

            Text("Archive")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
                .rotationEffect(.degrees(-90))
                .fixedSize()

            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.lg)
        .frame(width: 28, height: KanbanDesign.projectColumnHeight, alignment: .top)
    }

    private func columnView(
        _ column: KanbanColumn,
        board: KanbanBoard,
        width: CGFloat,
        height: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            columnHeader(column)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Spacing.sm) {
                    let cards = filteredCards(column.cards)
                    let groups = KanbanBoardLayout.cardGroups(
                        for: column,
                        in: board,
                        visibleCards: cards,
                        collapsedParentIDs: collapsedParentCardIDs
                    )
                    ForEach(groups) { group in
                        cardGroupView(group, column: column, board: board)
                            .id(group.renderID)
                    }

                    // Add card button or inline field — also a drop target for appending
                    if addingCardToColumn == column.id {
                        addCardField(columnID: column.id)
                    } else {
                        addCardButton(columnID: column.id)
                            .dropDestination(for: String.self) { cardIDs, _ in
                                guard let cardID = cardIDs.first else { return false }
                                withAnimation(reduceMotion ? .none : .spring) {
                                    storage.moveCard(
                                        boardID: boardID,
                                        cardID: cardID,
                                        toColumnID: column.id,
                                        toIndex: column.cards.count,
                                        includeDescendants: shouldMoveDescendants(
                                            cardID: cardID,
                                            to: column,
                                            board: board
                                        )
                                    )
                                }
                                return true
                            }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .frame(width: width)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
        .dropDestination(for: String.self) { cardIDs, _ in
            guard let cardID = cardIDs.first else { return false }
            withAnimation(reduceMotion ? .none : .spring) {
                storage.moveCard(
                    boardID: boardID,
                    cardID: cardID,
                    toColumnID: column.id,
                    toIndex: column.cards.count,
                    includeDescendants: shouldMoveDescendants(
                        cardID: cardID,
                        to: column,
                        board: board
                    )
                )
            }
            return true
        }
    }

    private func columnHeader(_ column: KanbanColumn) -> some View {
        HStack(spacing: Spacing.xs) {
            if renamingColumnID == column.id {
                TextField("Column name", text: $columnNameDraft)
                    .textFieldStyle(.plain)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onSubmit {
                        let trimmed = columnNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            storage.renameColumn(boardID: boardID, columnID: column.id, name: trimmed)
                        }
                        renamingColumnID = nil
                    }
            } else {
                Text(column.name)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .onTapGesture(count: 2) {
                        columnNameDraft = column.name
                        renamingColumnID = column.id
                    }
            }

            Text("\(filteredCards(column.cards).count)")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.xs)
                .background(
                    Capsule(style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

            Spacer()

            Menu {
                Button("Rename") {
                    columnNameDraft = column.name
                    renamingColumnID = column.id
                }
                if !column.isDoneColumn {
                    Button("Mark as Done column") {
                        storage.setColumnDone(boardID: boardID, columnID: column.id, isDone: true)
                    }
                } else {
                    Button("Unmark as Done column") {
                        storage.setColumnDone(boardID: boardID, columnID: column.id, isDone: false)
                    }
                }
                Divider()
                Button("Delete Column", role: .destructive) {
                    withAnimation(reduceMotion ? .none : .spring) {
                        storage.deleteColumn(boardID: boardID, columnID: column.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Cards

    private func cardGroupView(
        _ group: KanbanColumnCardGroup,
        column: KanbanColumn,
        board: KanbanBoard
    ) -> some View {
        let summary = KanbanBoardLayout.childSummary(for: group.parent.card.id, in: board)
        let isCollapsed = collapsedParentCardIDs.contains(group.parent.card.id)
        let canCollapse = group.sameColumnChildCount > 0

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            interactiveCard(
                group.parent.card,
                column: column,
                board: board,
                toIndex: group.parent.visualIndex,
                childSummary: summary,
                canCollapse: canCollapse,
                isCollapsed: isCollapsed
            )

            if !group.children.isEmpty {
                childRailView(group: group, column: column, board: board)
            }
        }
    }

    private func childRailView(
        group: KanbanColumnCardGroup,
        column: KanbanColumn,
        board: KanbanBoard
    ) -> some View {
        let lineColor = hierarchyLineColor(for: group.parent.card)
        let children = group.children

        return VStack(spacing: Spacing.sm) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                childBranchRow(
                    child,
                    column: column,
                    board: board,
                    lineColor: lineColor,
                    isFirst: index == 0,
                    isLast: index == children.count - 1
                )
            }
        }
    }

    private func childBranchRow(
        _ node: KanbanColumnCardNode,
        column: KanbanColumn,
        board: KanbanBoard,
        lineColor: Color,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            KanbanChildConnector(
                lineColor: lineColor,
                isFirst: isFirst,
                isLast: isLast
            )

            interactiveCard(node.card, column: column, board: board, toIndex: node.visualIndex)
        }
        .padding(.leading, KanbanDesign.childIndent)
    }

    private func interactiveCard(
        _ card: KanbanCard,
        column: KanbanColumn,
        board: KanbanBoard,
        toIndex: Int,
        childSummary: KanbanParentChildSummary? = nil,
        canCollapse: Bool = false,
        isCollapsed: Bool = false
    ) -> some View {
        cardView(
            card,
            compact: compactCards,
            childSummary: childSummary,
            parentBadge: KanbanBoardLayout.parentBadge(for: card, in: column, board: board),
            accentColor: KanbanBoardLayout.cardAccentColor(for: card, in: board),
            canCollapse: canCollapse,
            isCollapsed: isCollapsed
        )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                onOpenCard(boardID, card.id)
            }
            .draggable(card.id) {
                cardDragPreview(card)
            }
            .dropDestination(for: String.self) { cardIDs, _ in
                guard let cardID = cardIDs.first, cardID != card.id else { return false }
                withAnimation(reduceMotion ? .none : .spring) {
                    storage.moveCard(
                        boardID: boardID,
                        cardID: cardID,
                        toColumnID: column.id,
                        toIndex: toIndex,
                        includeDescendants: shouldMoveDescendants(
                            cardID: cardID,
                            to: column,
                            board: board
                        )
                    )
                }
                return true
            }
    }

    private func toggleCollapse(cardID: String) {
        withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
            if collapsedParentCardIDs.contains(cardID) {
                collapsedParentCardIDs.remove(cardID)
            } else {
                collapsedParentCardIDs.insert(cardID)
            }
        }
    }

    private func hierarchyLineColor(for parent: KanbanCard) -> Color {
        if let color = parent.color {
            return kanbanColor(color).opacity(0.82)
        }

        return CiderColors.borderSubtle.opacity(0.95)
    }

    private func shouldMoveDescendants(cardID: String, to column: KanbanColumn, board: KanbanBoard) -> Bool {
        isQueuedColumn(column) && !board.childCards(of: cardID).isEmpty
    }

    private func isQueuedColumn(_ column: KanbanColumn) -> Bool {
        let normalized = "\(column.id) \(column.name)".lowercased()
        return normalized.contains("queue")
    }

    private func cardView(
        _ card: KanbanCard,
        compact: Bool = false,
        childSummary: KanbanParentChildSummary? = nil,
        parentBadge: KanbanParentBadge? = nil,
        accentColor: KanbanCardColor? = nil,
        canCollapse: Bool = false,
        isCollapsed: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : Spacing.xs) {
            if let color = accentColor {
                RoundedRectangle(cornerRadius: KanbanDesign.accentBarRadius, style: .continuous)
                    .fill(kanbanColor(color))
                    .frame(height: KanbanDesign.accentBarHeight)
            }

            HStack(spacing: Spacing.xs) {
                if canCollapse {
                    Button {
                        toggleCollapse(cardID: card.id)
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(CiderFont.micro)
                            .foregroundColor(CiderColors.tertiary)
                            .frame(width: 12, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed ? "Expand child cards" : "Collapse child cards")
                    .accessibilityHint("Toggles visible child cards in this column.")
                }

                Text(card.title)
                    .font(compact ? CiderFont.caption : CiderFont.label)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(compact ? 1 : 2)

                if compact {
                    Spacer()
                    if let priority = card.priority {
                        priorityBadge(priority)
                    }
                }
            }

            if let childSummary {
                Text(childSummary.compactText)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            if let parentBadge {
                parentBadgeView(parentBadge)
            }

            if !compact {
                if let notes = card.notes, !notes.isEmpty {
                    Text(notes)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(3)
                }

                HStack(spacing: Spacing.xs) {
                    if let priority = card.priority {
                        priorityBadge(priority)
                    }
                    if let agent = card.agent {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "cpu")
                            Text(agent)
                        }
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.controlAccent)
                    }
                    if !card.tags.isEmpty {
                        ForEach(card.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.tertiary)
                                .padding(.horizontal, Spacing.xxs)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CiderColors.surfaceInput)
                                )
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .contextMenu {
            Button("Delete Card", role: .destructive) {
                withAnimation(reduceMotion ? .none : .spring) {
                    storage.deleteCard(boardID: boardID, cardID: card.id)
                }
            }
        }
    }

    private func parentBadgeView(_ badge: KanbanParentBadge) -> some View {
        Button {
            onOpenCard(boardID, badge.parentID)
        } label: {
            HStack(spacing: Spacing.xxs) {
                if let accentColor = badge.accentColor {
                    Circle()
                        .fill(kanbanColor(accentColor))
                        .frame(width: 5, height: 5)
                }

                Text("Parent")
                    .foregroundColor(CiderColors.tertiary)

                Text(badge.title)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }
            .font(CiderFont.micro)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput.opacity(0.85))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open parent card \(badge.title)")
    }

    private func cardDragPreview(_ card: KanbanCard) -> some View {
        Text(card.title)
            .font(CiderFont.label)
            .foregroundColor(CiderColors.primary)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceElevated)
            )
    }

    // MARK: - Add Card

    private func addCardButton(columnID: String) -> some View {
        Button {
            addingCardToColumn = columnID
            newCardTitle = ""
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "plus")
                Text("Add card")
            }
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private func addCardField(columnID: String) -> some View {
        VStack(spacing: Spacing.xs) {
            TextField("Card title...", text: $newCardTitle)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceElevated)
                )
                .onSubmit {
                    let trimmed = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = withAnimation(reduceMotion ? .none : .spring) {
                            storage.addCard(boardID: boardID, columnID: columnID, title: trimmed)
                        }
                    }
                    newCardTitle = ""
                    addingCardToColumn = nil
                }

            HStack {
                Button("Add") {
                    let trimmed = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = withAnimation(reduceMotion ? .none : .spring) {
                            storage.addCard(boardID: boardID, columnID: columnID, title: trimmed)
                        }
                    }
                    newCardTitle = ""
                    addingCardToColumn = nil
                }
                .buttonStyle(.plain)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.controlAccent)

                Spacer()

                Button("Cancel") {
                    addingCardToColumn = nil
                    newCardTitle = ""
                }
                .buttonStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.xs)
        }
    }

    // MARK: - Helpers

    private func kanbanColor(_ color: KanbanCardColor) -> Color {
        switch color {
        case .blue: CiderColors.controlAccent
        case .green: CiderColors.success
        case .orange: CiderColors.warning
        case .red: CiderColors.destructive
        case .purple: CiderColors.controlAccent.opacity(0.7)
        }
    }

    private func priorityBadge(_ priority: KanbanPriority) -> some View {
        let (text, color): (String, Color) = switch priority {
        case .high: ("High", CiderColors.destructive)
        case .medium: ("Med", CiderColors.warning)
        case .low: ("Low", CiderColors.tertiary)
        }
        return Text(text)
            .font(CiderFont.micro)
            .foregroundColor(color)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "square.split.2x1")
                .font(CiderFont.settingsEmptyIcon)
                .foregroundColor(CiderColors.quaternary)
            Text("Board not found")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KanbanChildConnector: View {
    let lineColor: Color
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let startY = isFirst ? -Spacing.xs : -Spacing.sm
                let endY = isLast
                    ? KanbanDesign.childConnectorTopInset
                    : proxy.size.height + Spacing.sm

                path.move(to: CGPoint(x: 0, y: startY))
                path.addLine(to: CGPoint(x: 0, y: endY))
                path.move(to: CGPoint(x: 0, y: KanbanDesign.childConnectorTopInset))
                path.addLine(to: CGPoint(
                    x: KanbanDesign.childConnectorWidth,
                    y: KanbanDesign.childConnectorTopInset
                ))
            }
            .stroke(lineColor, lineWidth: CiderBorder.hairlineStrokeWidth)
        }
        .frame(width: KanbanDesign.childConnectorWidth)
    }
}

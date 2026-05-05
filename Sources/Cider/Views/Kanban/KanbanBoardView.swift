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

                if !archiveColumns.isEmpty {
                    projectArchiveReveal(columns: archiveColumns, board: board)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
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

    private func projectArchiveReveal(columns: [KanbanColumn], board: KanbanBoard) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            archiveRevealDivider

            ForEach(columns) { column in
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
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        cardView(card, compact: compactCards)
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
                                        toIndex: index
                                    )
                                }
                                return true
                            }
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
                                        toIndex: column.cards.count
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
                    toIndex: column.cards.count
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

    private func cardView(_ card: KanbanCard, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : Spacing.xs) {
            // Color accent bar
            if let color = card.color {
                RoundedRectangle(cornerRadius: KanbanDesign.accentBarRadius, style: .continuous)
                    .fill(kanbanColor(color))
                    .frame(height: KanbanDesign.accentBarHeight)
            }

            HStack(spacing: Spacing.xs) {
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

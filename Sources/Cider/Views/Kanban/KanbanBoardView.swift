import SwiftUI

/// Renders a Kanban board as horizontal scrolling columns with draggable cards.
struct KanbanBoardView: View {
    let boardID: String
    var projectHeaderTabs: [ProjectWorkspaceLocalTab] = []
    var onSelectProjectHeaderTab: (ProjectWorkspaceLocalTabKind) -> Void = { _ in }
    var onOpenCard: (String, String) -> Void = { _, _ in }

    @ObservedObject private var storage = KanbanStorage.shared
    @State private var editingBoardName = false
    @State private var boardNameDraft = ""
    @State private var addingCardToColumn: String?
    @State private var newCardTitle = ""
    @State private var quickAddColumnID: String?
    @State private var quickAddDraft = KanbanQuickAddDraft()
    @State private var renamingColumnID: String?
    @State private var columnNameDraft = ""
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""
    @State private var compactCards = false
    @State private var archiveExpanded = false
    @State private var archiveOpenGeneration = 0
    @State private var collapsedParentCardIDs: Set<String> = []
    @State private var projectLaneScrollIndexByID: [String: Int] = [:]
    @State private var tagEditorCardID: String?
    @State private var tagEditorDraft = ""
    @State private var selectedFeatureDomainFilter: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardFaceSuggestedTags = [
        "sidebar",
        "cider-web",
        "cider-ios",
        "bug",
        "idea",
        "testing",
        "qa",
        "performance",
        "blocked",
    ]

    private var board: KanbanBoard? {
        storage.boards.first { $0.id == boardID }
    }

    /// Filter cards by search text across title, notes, agent, and tags.
    private func filteredCards(_ cards: [KanbanCard]) -> [KanbanCard] {
        let featureFilteredCards = KanbanBoardLayout.cards(
            cards,
            matchingFeatureDomainFilter: selectedFeatureDomainFilter
        )
        guard !searchText.isEmpty else { return featureFilteredCards }
        let query = searchText.lowercased()
        return featureFilteredCards.filter { card in
            card.title.localizedStandardContains(query) ||
            (board?.displayKey(for: card) ?? card.displayKey ?? "").localizedStandardContains(query) ||
            card.id.localizedStandardContains(query) ||
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
                projectLaneScrollIndexByID.removeAll()
                selectedFeatureDomainFilter = nil
            }
        } else {
            emptyState
        }
    }

    // MARK: - Board Header

    private func boardHeader(_ board: KanbanBoard) -> some View {
        let featureFilters = KanbanBoardLayout.featureDomainFilters(for: board)

        return HStack(spacing: Spacing.sm) {
            if KanbanBoardLayout.usesProjectLayout(for: board), !projectHeaderTabs.isEmpty {
                projectHeaderTabsView
            } else {
                boardTitleView(board)
            }

            Spacer(minLength: Spacing.md)

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

            if !featureFilters.isEmpty {
                domainFilterMenu(featureFilters)
            }

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

    private func boardTitleView(_ board: KanbanBoard) -> some View {
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

            Text("\(filteredCardCount(for: board)) cards")
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
        }
    }

    private var projectHeaderTabsView: some View {
        ProjectWorkspaceLocalTabStrip(
            tabs: projectHeaderTabs,
            onSelect: onSelectProjectHeaderTab
        )
    }

    // MARK: - Columns

    private func domainFilterMenu(_ filters: [KanbanFeatureDomainFilter]) -> some View {
        let selected = selectedFeatureDomainFilter.flatMap { selectedID in
            filters.first { $0.id == selectedID }
        }

        return Menu {
            Button {
                selectedFeatureDomainFilter = nil
            } label: {
                Label("All Domains", systemImage: selected == nil ? "checkmark" : "cube.transparent")
            }

            Divider()

            ForEach(filters) { filter in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                        selectedFeatureDomainFilter = filter.id
                    }
                } label: {
                    Label(
                        "\(filter.label) (\(filter.cardCount))",
                        systemImage: selectedFeatureDomainFilter == filter.id ? "checkmark" : "cube.transparent"
                    )
                }
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "cube.transparent")
                    .font(CiderFont.caption)
                Text(selected?.label ?? "Domains")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(selected == nil ? CiderColors.tertiary : CiderColors.controlAccent)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(selected == nil ? CiderColors.surfaceInput : CiderColors.controlAccent.opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(selected.map { "Domain filter: \($0.label)" } ?? "Domain filter")
    }

    private func filteredCardCount(for board: KanbanBoard) -> Int {
        board.columns.reduce(0) { partial, column in
            partial + filteredCards(column.cards).count
        }
    }

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
            .background(horizontalPanSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectRowsArea(_ board: KanbanBoard) -> some View {
        GeometryReader { geometry in
            if let lane = KanbanBoardLayout.lanes(for: board).first {
                projectLaneView(
                    lane,
                    board: board,
                    availableBoardHeight: geometry.size.height
                )
                .padding(Spacing.lg)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            } else {
                VStack {
                    Spacer()
                    Text("No columns")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectLaneView(
        _ lane: KanbanBoardLane,
        board: KanbanBoard,
        availableBoardHeight: CGFloat
    ) -> some View {
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
                let visibleColumnCount = projectLaneVisibleColumnCount(availableWidth: geometry.size.width)
                let maxScrollIndex = max(lane.columns.count - visibleColumnCount, 0)
                let columnHeight = KanbanBoardLayout.projectColumnHeight(
                    availableBoardHeight: availableBoardHeight,
                    showsScrollControls: maxScrollIndex > 0
                )

                ScrollViewReader { scrollProxy in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .top, spacing: Spacing.md) {
                                    ForEach(lane.columns) { column in
                                        columnView(
                                            column,
                                            board: board,
                                            width: KanbanDesign.projectColumnWidth,
                                            height: columnHeight
                                        )
                                        .id(projectColumnScrollID(laneID: lane.id, columnID: column.id))
                                    }
                                }
                                .padding(.bottom, Spacing.xs)
                                .background(horizontalPanSurface)
                            }
                            .frame(maxWidth: .infinity)
                            .defaultScrollAnchor(shouldPushArchive ? .trailing : .leading)
                            .id(projectLaneScrollIdentity(for: lane, shouldPushArchive: shouldPushArchive))

                            if !archiveColumns.isEmpty {
                                projectArchiveReveal(
                                    columns: archiveColumns,
                                    board: board,
                                    columnHeight: columnHeight
                                )
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }

                        if maxScrollIndex > 0 {
                            projectLaneScrollControls(
                                lane: lane,
                                visibleColumnCount: visibleColumnCount,
                                maxScrollIndex: maxScrollIndex,
                                scrollProxy: scrollProxy
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.86), value: archiveExpanded)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func projectLaneVisibleColumnCount(availableWidth: CGFloat) -> Int {
        let columnStride = KanbanDesign.projectColumnWidth + Spacing.md
        return max(1, Int(floor((availableWidth + Spacing.md) / columnStride)))
    }

    private func projectLaneScrollIdentity(for lane: KanbanBoardLane, shouldPushArchive: Bool) -> String {
        if archiveExpanded {
            return "\(lane.id)-archive-\(archiveOpenGeneration)-push-\(shouldPushArchive)"
        }

        return "\(lane.id)-active"
    }

    private func projectColumnScrollID(laneID: String, columnID: String) -> String {
        "\(laneID)-column-\(columnID)"
    }

    private func projectLaneScrollIndex(for lane: KanbanBoardLane, maxScrollIndex: Int) -> Int {
        min(max(projectLaneScrollIndexByID[lane.id] ?? 0, 0), maxScrollIndex)
    }

    private func scrollProjectLane(
        _ lane: KanbanBoardLane,
        to index: Int,
        maxScrollIndex: Int,
        scrollProxy: ScrollViewProxy
    ) {
        let nextIndex = min(max(index, 0), maxScrollIndex)
        projectLaneScrollIndexByID[lane.id] = nextIndex

        guard lane.columns.indices.contains(nextIndex) else { return }

        let targetColumn = lane.columns[nextIndex]
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
            scrollProxy.scrollTo(
                projectColumnScrollID(laneID: lane.id, columnID: targetColumn.id),
                anchor: .leading
            )
        }
    }

    private func projectLaneScrollControls(
        lane: KanbanBoardLane,
        visibleColumnCount: Int,
        maxScrollIndex: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let currentIndex = projectLaneScrollIndex(for: lane, maxScrollIndex: maxScrollIndex)
        let visibleRange = currentIndex..<(min(currentIndex + visibleColumnCount, lane.columns.count))

        return HStack(spacing: Spacing.xs) {
            Button {
                scrollProjectLane(
                    lane,
                    to: currentIndex - 1,
                    maxScrollIndex: maxScrollIndex,
                    scrollProxy: scrollProxy
                )
            } label: {
                Image(systemName: "chevron.left")
                    .font(CiderFont.micro)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)
            .opacity(currentIndex == 0 ? 0.35 : 0.85)
            .help("Scroll columns left")

            HStack(spacing: Spacing.xxs) {
                ForEach(lane.columns.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(visibleRange.contains(index) ? CiderColors.controlAccent.opacity(0.78) : CiderColors.borderSubtle.opacity(0.65))
                        .frame(width: visibleRange.contains(index) ? 18 : 10, height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Horizontal column position")

            Button {
                scrollProjectLane(
                    lane,
                    to: currentIndex + 1,
                    maxScrollIndex: maxScrollIndex,
                    scrollProxy: scrollProxy
                )
            } label: {
                Image(systemName: "chevron.right")
                    .font(CiderFont.micro)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= maxScrollIndex)
            .opacity(currentIndex >= maxScrollIndex ? 0.35 : 0.85)
            .help("Scroll columns right")
        }
        .foregroundColor(CiderColors.tertiary)
        .padding(.horizontal, Spacing.xs)
        .frame(height: KanbanDesign.projectHorizontalScrollControlHeight)
    }

    private func projectArchiveReveal(
        columns archiveColumns: [KanbanColumn],
        board: KanbanBoard,
        columnHeight: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            archiveRevealDivider(height: columnHeight)

            ForEach(archiveColumns) { column in
                columnView(
                    column,
                    board: board,
                    width: KanbanDesign.projectColumnWidth,
                    height: columnHeight
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(CiderColors.controlAccent.opacity(0.35), lineWidth: CiderBorder.hairlineStrokeWidth)
                )
            }
        }
    }

    private func archiveRevealDivider(height: CGFloat) -> some View {
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
        .frame(width: 28, height: height, alignment: .top)
    }

    private func columnView(
        _ column: KanbanColumn,
        board: KanbanBoard,
        width: CGFloat,
        height: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            columnHeader(column, board: board)

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
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
                horizontalPanSurface
            }
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

    private var horizontalPanSurface: some View {
        GeometryReader { _ in
            KanbanHorizontalPanScrollSurface()
        }
    }

    private func columnHeader(_ column: KanbanColumn, board: KanbanBoard) -> some View {
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

            Button {
                quickAddDraft = KanbanQuickAddDraft()
                quickAddColumnID = column.id
            } label: {
                Image(systemName: "plus")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick add card")
            .popover(
                isPresented: Binding(
                    get: { quickAddColumnID == column.id },
                    set: { isPresented in
                        if !isPresented {
                            quickAddColumnID = nil
                            quickAddDraft = KanbanQuickAddDraft()
                        }
                    }
                ),
                arrowEdge: .bottom
            ) {
                quickAddPopover(column: column, board: board)
            }

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
        let lineColor = hierarchyLineColor(for: group.parent.card, in: board)
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
                .padding(.leading, nestedChildIndent(for: node))
        }
        .padding(.leading, KanbanDesign.childIndent)
    }

    private func nestedChildIndent(for node: KanbanColumnCardNode) -> CGFloat {
        CGFloat(max(0, min(node.depth, 3) - 1)) * (KanbanDesign.childIndent * 0.72)
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
            planIndicator: KanbanBoardLayout.planIndicator(for: card, in: board),
            accentColor: KanbanBoardLayout.cardAccentColor(for: card, in: board),
            inboxBadges: inboxBadges(for: card, in: column),
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

    private func hierarchyLineColor(for parent: KanbanCard, in board: KanbanBoard) -> Color {
        if let color = KanbanBoardLayout.hierarchyConnectorAccentColor(for: parent, in: board) {
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
        planIndicator: KanbanPlanIndicator? = nil,
        accentColor: KanbanCardColor? = nil,
        inboxBadges: [ProjectWorkspaceInboxBadge] = [],
        canCollapse: Bool = false,
        isCollapsed: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : 0) {
            if let color = accentColor {
                RoundedRectangle(cornerRadius: KanbanDesign.accentBarRadius, style: .continuous)
                    .fill(kanbanColor(color))
                    .frame(height: KanbanDesign.accentBarHeight)
                    .padding(.bottom, compact ? Spacing.xxs : Spacing.xs)
            }

            cardHeaderView(
                card,
                compact: compact,
                canCollapse: canCollapse,
                isCollapsed: isCollapsed
            )

            if !inboxBadges.isEmpty {
                cardInboxBadgesView(inboxBadges)
                    .padding(.top, compact ? Spacing.xxs : KanbanDesign.cardPreviewSectionSpacing)
            }

            if let childSummary {
                Text(childSummary.compactText)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
                    .padding(.top, compact ? Spacing.xxs : KanbanDesign.cardPreviewSectionSpacing)
            }

            if compact, hasCardContext(parentBadge: parentBadge, planIndicator: planIndicator) {
                cardContextView(parentBadge: parentBadge, planIndicator: planIndicator)
                    .padding(.top, Spacing.xxs)
            }

            if !compact {
                if hasCardContext(parentBadge: parentBadge, planIndicator: planIndicator) {
                    cardContextView(parentBadge: parentBadge, planIndicator: planIndicator)
                        .padding(.top, KanbanDesign.cardPreviewContextFooterSpacing)
                }

                if hasCardFooter(card) {
                    cardFooterView(card)
                        .padding(.top, KanbanDesign.cardPreviewFooterTopSpacing)
                }
            }
        }
        .padding(.horizontal, compact ? Spacing.sm : Spacing.md)
        .padding(.vertical, compact ? Spacing.sm : Spacing.md)
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

    private func inboxBadges(for card: KanbanCard, in column: KanbanColumn) -> [ProjectWorkspaceInboxBadge] {
        guard ProjectWorkspaceInboxProvider.isUnread(card) else { return [] }
        return ProjectWorkspaceInboxProvider.badges(for: card, column: column)
    }

    private func cardInboxBadgesView(_ badges: [ProjectWorkspaceInboxBadge]) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(badges.prefix(3)) { badge in
                Label(badge.title, systemImage: badge.systemImage)
                    .font(CiderFont.micro)
                    .foregroundColor(inboxBadgeColor(for: badge.kind))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(inboxBadgeColor(for: badge.kind).opacity(0.12))
                    )
            }
        }
    }

    private func inboxBadgeColor(for kind: ProjectWorkspaceInboxBadge.Kind) -> Color {
        switch kind {
        case .new: return CiderColors.controlAccent
        case .agentReport: return CiderColors.secondary
        case .needsQA: return CiderColors.warning
        }
    }

    private func cardHeaderView(
        _ card: KanbanCard,
        compact: Bool,
        canCollapse: Bool,
        isCollapsed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.xs) {
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

                Text(displayKey(for: card))
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.controlAccent)
                    .lineLimit(1)

                Spacer(minLength: Spacing.xs)

                cardAvatarPlaceholder(card)
            }

            Text(card.title)
                .font(compact ? CiderFont.captionSemibold : CiderFont.labelSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(compact ? 2 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func displayKey(for card: KanbanCard) -> String {
        board?.displayKey(for: card) ?? card.displayKey ?? String(card.id.prefix(8)).uppercased()
    }

    private func cardAvatarPlaceholder(_ card: KanbanCard) -> some View {
        let label = card.agent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initials = label?.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return ZStack {
            Circle()
                .fill(label == nil ? CiderColors.surfaceInput : CiderColors.controlAccent.opacity(0.16))
                .frame(width: 18, height: 18)
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.controlAccent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .accessibilityLabel(label.map { "Assignee \($0)" } ?? "Unassigned")
    }

    private func hasCardFooter(_ card: KanbanCard) -> Bool {
        KanbanBoardLayout.testingOwnerBadge(for: card) != nil
            || !KanbanBoardLayout.cardFaceChips(for: card).isEmpty
    }

    private func hasCardContext(parentBadge: KanbanParentBadge?, planIndicator: KanbanPlanIndicator?) -> Bool {
        parentBadge != nil || planIndicator != nil
    }

    @ViewBuilder
    private func cardContextView(
        parentBadge: KanbanParentBadge?,
        planIndicator: KanbanPlanIndicator?
    ) -> some View {
        if let parentBadge {
            if let planIndicator {
                planIndicatorView(planIndicator)
            } else {
                parentBadgeView(parentBadge)
            }
        } else if let planIndicator {
            planIndicatorView(planIndicator)
        }
    }

    private func cardFooterView(_ card: KanbanCard) -> some View {
        TagFlowLayout(spacing: Spacing.xs) {
            if let badge = KanbanBoardLayout.testingOwnerBadge(for: card) {
                testingOwnerBadgeView(badge)
            }
            ForEach(KanbanBoardLayout.cardFaceChips(for: card), id: \.label) { chip in
                cardFaceChipView(chip, card: card)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cardFaceChipView(_ chip: KanbanCardFaceChip, card: KanbanCard) -> some View {
        switch chip.role {
        case .tagEdit:
            Button {
                beginTagEditing(card)
            } label: {
                cardFaceChipLabel(chip, color: CiderColors.tertiary, indicatorColor: CiderColors.controlAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add or change tags for \(card.title)")
            .popover(
                isPresented: Binding(
                    get: { tagEditorCardID == card.id },
                    set: { isPresented in
                        if !isPresented {
                            tagEditorCardID = nil
                            tagEditorDraft = ""
                        }
                    }
                ),
                arrowEdge: .bottom
            ) {
                cardFaceTagEditorPopover(card)
            }
        case .featureDomain:
            let filterID = KanbanCardTagTaxonomy.normalized(chip.label)
            let isSelected = selectedFeatureDomainFilter == filterID
            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                    selectedFeatureDomainFilter = isSelected ? nil : filterID
                }
            } label: {
                cardFaceChipLabel(
                    chip,
                    color: isSelected ? CiderColors.controlAccent : CiderColors.secondary,
                    indicatorColor: CiderColors.controlAccent
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter board by \(chip.label)")
        case .typeStatus:
            let color = cardFaceChipColor(for: chip)
            cardFaceChipLabel(chip, color: CiderColors.secondary, indicatorColor: color)
        }
    }

    private func beginTagEditing(_ card: KanbanCard) {
        tagEditorDraft = card.tags.joined(separator: ", ")
        tagEditorCardID = card.id
    }

    private func cardFaceTagEditorPopover(_ card: KanbanCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tag")
                    .foregroundColor(CiderColors.tertiary)
                Text("Edit tags")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer()
            }

            TextField("Tags, comma separated", text: $tagEditorDraft)
                .textFieldStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                )
                .onSubmit {
                    saveTagEditor(for: card)
                }

            TagFlowLayout(spacing: Spacing.xs) {
                ForEach(cardFaceSuggestedTags, id: \.self) { tag in
                    Button {
                        toggleTagEditorTag(tag)
                    } label: {
                        Text(KanbanCardTagTaxonomy.normalized(tag).split(separator: "-")
                            .map { part in
                                let lower = part.lowercased()
                                if lower == "ios" { return "iOS" }
                                if lower == "qa" { return "QA" }
                                guard let first = part.first else { return "" }
                                return first.uppercased() + part.dropFirst()
                            }
                            .joined(separator: " "))
                            .font(CiderFont.microSemibold)
                            .foregroundColor(tagEditorTags.contains(KanbanCardTagTaxonomy.normalized(tag)) ? CiderColors.controlAccent : CiderColors.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tagEditorTags.contains(KanbanCardTagTaxonomy.normalized(tag)) ? CiderColors.controlAccent.opacity(0.14) : CiderColors.surfaceInput)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Spacing.sm) {
                Button("Save") {
                    saveTagEditor(for: card)
                }
                .buttonStyle(CiderAccentButtonStyle())

                Button("Cancel") {
                    tagEditorCardID = nil
                    tagEditorDraft = ""
                }
                .buttonStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(width: 300)
    }

    private var tagEditorTags: Set<String> {
        Set(parsedTagEditorTags())
    }

    private func parsedTagEditorTags() -> [String] {
        tagEditorDraft
            .components(separatedBy: ",")
            .map { KanbanCardTagTaxonomy.normalized($0) }
            .filter { !$0.isEmpty }
    }

    private func toggleTagEditorTag(_ tag: String) {
        let normalized = KanbanCardTagTaxonomy.normalized(tag)
        guard !normalized.isEmpty else { return }
        var tags = parsedTagEditorTags()
        if tags.contains(normalized) {
            tags.removeAll { $0 == normalized }
        } else {
            tags.append(normalized)
        }
        tagEditorDraft = tags.joined(separator: ", ")
    }

    private func saveTagEditor(for card: KanbanCard) {
        storage.updateCardTags(boardID: boardID, cardID: card.id, tags: parsedTagEditorTags())
        tagEditorCardID = nil
        tagEditorDraft = ""
    }

    private func cardFaceChipLabel(_ chip: KanbanCardFaceChip, color: Color, indicatorColor: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            switch chip.accessory {
            case .none:
                EmptyView()
            case .featureIcon:
                Image(systemName: chip.iconSystemName ?? "cube.transparent")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(indicatorColor.opacity(0.85))
            case .colorDot:
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 5, height: 5)
            }

            Text(chip.label)
                .font(CiderFont.microSemibold)
                .foregroundColor(color)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func cardFaceChipColor(for chip: KanbanCardFaceChip) -> Color {
        switch chip.role {
        case .tagEdit:
            CiderColors.tertiary
        case .featureDomain:
            CiderColors.controlAccent
        case .typeStatus:
            cardFaceTypeIndicatorColor(for: chip.label)
        }
    }

    private func cardFaceTypeIndicatorColor(for label: String) -> Color {
        switch label.lowercased() {
        case "bug", "blocked":
            CiderColors.destructive
        case "performance":
            CiderColors.success
        case "test", "testing", "qa", "review", "needs qa":
            CiderColors.warning
        case "idea", "new", "inbox":
            CiderColors.controlAccent
        default:
            CiderColors.tertiary
        }
    }

    private func testingOwnerBadgeView(_ badge: KanbanTestingOwnerBadge) -> some View {
        let color = testingOwnerBadgeColor(for: badge.kind)
        return Text(badge.text)
            .font(CiderFont.micro)
            .foregroundColor(color)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: CiderBorder.hairlineStrokeWidth)
            )
    }

    private func testingOwnerBadgeColor(for kind: KanbanTestingOwnerBadge.Kind) -> Color {
        switch kind {
        case .needsErik: CiderColors.warning
        case .agentCanVerify: CiderColors.success
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

    private func planIndicatorView(_ indicator: KanbanPlanIndicator) -> some View {
        Button {
            onOpenCard(boardID, indicator.parentID)
        } label: {
            HStack(spacing: Spacing.xxs) {
                if let accentColor = indicator.accentColor {
                    Circle()
                        .fill(kanbanColor(accentColor))
                        .frame(width: 5, height: 5)
                }

                Text(indicator.compactText)
                    .foregroundColor(indicator.isNextUp ? CiderColors.controlAccent : CiderColors.tertiary)

                Text(indicator.title)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }
            .font(CiderFont.micro)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(indicator.isNextUp ? CiderColors.accentSubtle : CiderColors.surfaceInput.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(indicator.isNextUp ? CiderColors.controlAccent.opacity(0.28) : Color.clear, lineWidth: CiderBorder.hairlineStrokeWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open plan \(indicator.title), \(indicator.compactText)")
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

    // MARK: - Header Quick Add

    private func quickAddPopover(column: KanbanColumn, board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Add to \(column.name)")
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.primary)

            TextField("Title", text: $quickAddDraft.title)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .onSubmit {
                    createQuickAddCard(columnID: column.id, openAfterCreate: false)
                }

            TextEditor(text: $quickAddDraft.notes)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.primary)
                .scrollContentBackground(.hidden)
                .frame(height: 76)
                .padding(Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                )

            HStack(spacing: Spacing.xs) {
                quickAddPriorityMenu
                quickAddColorMenu
            }

            TextField("Tags, comma separated", text: $quickAddDraft.tagsText)
                .textFieldStyle(.plain)
                .font(CiderFont.caption)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

            quickAddParentMenu(board: board)

            HStack(spacing: Spacing.sm) {
                Button("Create") {
                    createQuickAddCard(columnID: column.id, openAfterCreate: false)
                }
                .buttonStyle(CiderAccentButtonStyle())
                .disabled(!quickAddDraft.canCreate)

                Button("Create & Open") {
                    createQuickAddCard(columnID: column.id, openAfterCreate: true)
                }
                .buttonStyle(.plain)
                .font(CiderFont.captionSemibold)
                .foregroundColor(quickAddDraft.canCreate ? CiderColors.controlAccent : CiderColors.tertiary)
                .disabled(!quickAddDraft.canCreate)
                .keyboardShortcut(.return, modifiers: [.command])

                Spacer()

                Button("Cancel") {
                    quickAddColumnID = nil
                    quickAddDraft = KanbanQuickAddDraft()
                }
                .buttonStyle(.plain)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.md)
        .frame(width: 300)
    }

    private var quickAddPriorityMenu: some View {
        Menu {
            Button("None") { quickAddDraft.priority = nil }
            Divider()
            ForEach(KanbanPriority.allCases, id: \.self) { priority in
                Button(priorityLabel(for: priority).0) {
                    quickAddDraft.priority = priority
                }
            }
        } label: {
            quickAddMenuLabel(
                title: quickAddDraft.priority.map { priorityLabel(for: $0).0 } ?? "Priority",
                systemImage: "flag"
            )
        }
        .buttonStyle(.plain)
    }

    private var quickAddColorMenu: some View {
        Menu {
            Button("None") { quickAddDraft.color = nil }
            Divider()
            ForEach(KanbanCardColor.allCases, id: \.self) { color in
                Button(color.rawValue.capitalized) {
                    quickAddDraft.color = color
                }
            }
        } label: {
            quickAddMenuLabel(
                title: quickAddDraft.color?.rawValue.capitalized ?? "Color",
                systemImage: "circle.fill",
                tint: quickAddDraft.color.map { kanbanColor($0) }
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAddParentMenu(board: KanbanBoard) -> some View {
        Menu {
            Button("No parent") { quickAddDraft.parentCardID = nil }
            Divider()
            ForEach(board.allCards, id: \.id) { card in
                Button {
                    quickAddDraft.parentCardID = card.id
                } label: {
                    Text(card.title)
                }
            }
        } label: {
            let parentTitle = quickAddDraft.parentCardID.flatMap { parentID in
                board.card(id: parentID)?.title
            }
            quickAddMenuLabel(
                title: parentTitle ?? "No parent",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAddMenuLabel(title: String, systemImage: String, tint: Color? = nil) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: systemImage)
                .foregroundColor(tint ?? CiderColors.tertiary)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
        }
        .font(CiderFont.caption)
        .foregroundColor(CiderColors.secondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func createQuickAddCard(columnID: String, openAfterCreate: Bool) {
        guard quickAddDraft.canCreate else { return }

        let created = storage.addCard(
            boardID: boardID,
            columnID: columnID,
            title: quickAddDraft.trimmedTitle,
            notes: quickAddDraft.trimmedNotes,
            priority: quickAddDraft.priority,
            color: quickAddDraft.color,
            tags: quickAddDraft.tags,
            parentCardID: quickAddDraft.parentCardID
        )

        let createdID = created?.id
        quickAddColumnID = nil
        quickAddDraft = KanbanQuickAddDraft()

        if openAfterCreate, let createdID {
            onOpenCard(boardID, createdID)
        }
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
        case .blue:
            Color(
                hue: KanbanDesign.kanbanBlueAccentHueDegrees / 360,
                saturation: KanbanDesign.kanbanAccentSaturation,
                brightness: KanbanDesign.kanbanAccentBrightness
            )
        case .green: CiderColors.success
        case .orange: CiderColors.warning
        case .red: CiderColors.destructive
        case .purple:
            Color(
                hue: KanbanDesign.kanbanPurpleAccentHueDegrees / 360,
                saturation: KanbanDesign.kanbanAccentSaturation,
                brightness: KanbanDesign.kanbanAccentBrightness
            )
        }
    }

    private func priorityBadge(_ priority: KanbanPriority) -> some View {
        let (text, color) = priorityLabel(for: priority)
        return Text(text)
            .font(CiderFont.micro)
            .foregroundColor(color)
    }

    private func priorityLabel(for priority: KanbanPriority) -> (String, Color) {
        switch priority {
        case .high: ("High", CiderColors.destructive)
        case .medium: ("Med", CiderColors.warning)
        case .low: ("Low", CiderColors.tertiary)
        }
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

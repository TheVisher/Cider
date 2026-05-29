import SwiftUI

enum KanbanBoardHeaderControl: String, CaseIterable, Identifiable {
    case filter
    case displayOptions
    case properties

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filter: "Filter"
        case .displayOptions: "Display Options"
        case .properties: "Properties"
        }
    }

    var systemImage: String {
        switch self {
        case .filter: "line.3.horizontal.decrease.circle"
        case .displayOptions: "slider.horizontal.3"
        case .properties: "sidebar.right"
        }
    }

    var helpText: String {
        switch self {
        case .filter: "Filter board"
        case .displayOptions: "Display options"
        case .properties: "Show board properties"
        }
    }

    var placeholderTitle: String {
        switch self {
        case .filter: "Filter controls are coming next."
        case .displayOptions: "Display options are coming next."
        case .properties: "Board properties are coming next."
        }
    }

    var placeholderBody: String {
        switch self {
        case .filter:
            "This shell will hold filter categories like status, labels, dates, and project milestones."
        case .displayOptions:
            "This shell will hold board layout, ordering, column visibility, and card property options."
        case .properties:
            "This inspector shell will hold board properties, milestones, progress, and activity."
        }
    }
}

/// Renders a Kanban board as horizontal scrolling columns with draggable cards.
struct KanbanBoardView: View {
    let boardID: String
    var milestoneFilterCardID: String?
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
    @State private var projectLaneScrollIndexByID: [String: Int] = [:]
    @State private var tagEditorCardID: String?
    @State private var tagEditorDraft = ""
    @State private var selectedFeatureDomainFilter: String?
    @State private var selectedProjectBoardViewID = "all"
    @State private var selectedMilestoneFilterCardID: String?
    @State private var activeHeaderPopover: KanbanBoardHeaderControl?
    @State private var isBoardInspectorVisible = false
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
    private func filteredCards(_ cards: [KanbanCard], in column: KanbanColumn, board: KanbanBoard) -> [KanbanCard] {
        let viewFilteredCards = KanbanBoardLayout.cards(
            cards,
            in: column,
            board: board,
            matchingProjectBoardViewID: selectedProjectBoardViewID
        )
        let featureFilteredCards = KanbanBoardLayout.cards(
            viewFilteredCards,
            matchingFeatureDomainFilter: selectedFeatureDomainFilter
        )
        let milestoneFilteredCards = milestoneFilteredCards(featureFilteredCards, board: board)
        guard !searchText.isEmpty else { return milestoneFilteredCards }
        let query = searchText.lowercased()
        return milestoneFilteredCards.filter { card in
            card.title.localizedStandardContains(query) ||
            board.displayKey(for: card).localizedStandardContains(query) ||
            card.id.localizedStandardContains(query) ||
            (card.notes ?? "").localizedStandardContains(query) ||
            (card.agent ?? "").localizedStandardContains(query) ||
            card.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        if let board {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    boardHeader(board)
                    Divider().background(CiderColors.separator)
                    columnsArea(board)
                }

                if isBoardInspectorVisible {
                    boardInspectorShell(board)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: isBoardInspectorVisible)
            .onChange(of: boardID) { _, _ in
                projectLaneScrollIndexByID.removeAll()
                selectedFeatureDomainFilter = nil
                selectedProjectBoardViewID = "all"
                selectedMilestoneFilterCardID = milestoneFilterCardID
                activeHeaderPopover = nil
                isBoardInspectorVisible = false
            }
            .onAppear {
                selectedMilestoneFilterCardID = milestoneFilterCardID
            }
            .onChange(of: milestoneFilterCardID) { _, newValue in
                selectedMilestoneFilterCardID = newValue
            }
        } else {
            emptyState
        }
    }

    private func milestoneFilteredCards(_ cards: [KanbanCard], board: KanbanBoard) -> [KanbanCard] {
        guard let milestoneID = selectedMilestoneFilterCardID,
              board.allCards.contains(where: { $0.id == milestoneID }) else {
            return cards
        }
        let cardsByParentID = Dictionary(grouping: board.allCards) { $0.parentCardID ?? "" }
        var includedCardIDs: Set<String> = [milestoneID]
        var pendingCardIDs = [milestoneID]
        while let parentID = pendingCardIDs.popLast() {
            for child in cardsByParentID[parentID, default: []] where !includedCardIDs.contains(child.id) {
                includedCardIDs.insert(child.id)
                pendingCardIDs.append(child.id)
            }
        }
        return cards.filter { card in
            includedCardIDs.contains(card.id)
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

            HStack(spacing: Spacing.xxs) {
                ForEach(KanbanBoardHeaderControl.allCases) { control in
                    boardHeaderControlButton(control)
                }
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

    private func boardHeaderControlButton(_ control: KanbanBoardHeaderControl) -> some View {
        let isActive = activeHeaderPopover == control || (control == .properties && isBoardInspectorVisible)

        return Button {
            switch control {
            case .filter, .displayOptions:
                activeHeaderPopover = activeHeaderPopover == control ? nil : control
            case .properties:
                withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88)) {
                    isBoardInspectorVisible.toggle()
                }
                activeHeaderPopover = nil
            }
        } label: {
            Image(systemName: control.systemImage)
                .font(CiderFont.caption)
                .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.tertiary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isActive ? CiderColors.controlAccent.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(isActive ? CiderColors.controlAccent.opacity(0.26) : Color.clear, lineWidth: CiderBorder.hairlineStrokeWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(control.helpText)
        .accessibilityLabel(control.title)
        .popover(
            isPresented: Binding(
                get: { activeHeaderPopover == control },
                set: { isPresented in
                    if !isPresented, activeHeaderPopover == control {
                        activeHeaderPopover = nil
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            boardHeaderControlPopover(control)
        }
    }

    private func boardHeaderControlPopover(_ control: KanbanBoardHeaderControl) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(control.title, systemImage: control.systemImage)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)

            Text(control.placeholderTitle)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)

            Text(control.placeholderBody)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(width: 260, alignment: .leading)
    }

    private func boardInspectorShell(_ board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Label(KanbanBoardHeaderControl.properties.title, systemImage: KanbanBoardHeaderControl.properties.systemImage)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: 0)

                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88)) {
                        isBoardInspectorVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Hide board properties")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider().background(CiderColors.separator)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(board.name)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                Text(KanbanBoardHeaderControl.properties.placeholderTitle)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)

                Text(KanbanBoardHeaderControl.properties.placeholderBody)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)

            Spacer(minLength: 0)
        }
        .frame(width: 280)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
    }

    private func filteredCardCount(for board: KanbanBoard) -> Int {
        board.columns.reduce(0) { partial, column in
            partial + filteredCards(column.cards, in: column, board: board).count
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
                ForEach(KanbanBoardLayout.visibleColumns(in: board)) { column in
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
        let hiddenColumns = KanbanBoardLayout.hiddenColumns(in: board)
        let viewFilters = KanbanBoardLayout.projectBoardViewFilters(for: board)
        let milestoneFilterCard = selectedMilestoneFilterCardID.flatMap { milestoneID in
            board.allCards.first { $0.id == milestoneID }
        }

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            if let milestoneFilterCard {
                milestoneFilterBanner(milestoneFilterCard, board: board)
            }
            projectBoardViewPills(viewFilters, hiddenColumnCount: hiddenColumns.count)

            GeometryReader { geometry in
                let scrollItemCount = KanbanBoardLayout.projectScrollableItemCount(
                    activeColumnCount: lane.columns.count,
                    hiddenColumnCount: hiddenColumns.count
                )
                let visibleColumnCount = projectLaneVisibleColumnCount(availableWidth: geometry.size.width)
                let maxScrollIndex = max(scrollItemCount - visibleColumnCount, 0)
                let columnHeight = KanbanBoardLayout.projectColumnHeight(
                    availableBoardHeight: availableBoardHeight,
                    showsScrollControls: maxScrollIndex > 0
                )

                ScrollViewReader { scrollProxy in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
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

                                if !hiddenColumns.isEmpty {
                                    hiddenColumnsRail(
                                        columns: hiddenColumns,
                                        board: board,
                                        height: columnHeight
                                    )
                                    .id(projectHiddenRailScrollID(laneID: lane.id))
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                            }
                            .padding(.bottom, Spacing.xs)
                            .background(horizontalPanSurface)
                        }
                        .frame(maxWidth: .infinity)
                        .defaultScrollAnchor(.leading)
                        .id(projectLaneScrollIdentity(for: lane))

                        if maxScrollIndex > 0 {
                            projectLaneScrollControls(
                                lane: lane,
                                visibleColumnCount: visibleColumnCount,
                                scrollItemCount: scrollItemCount,
                                maxScrollIndex: maxScrollIndex,
                                scrollProxy: scrollProxy
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.86), value: hiddenColumns.map(\.id))
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

    private func projectBoardViewPills(
        _ filters: [KanbanProjectBoardViewFilter],
        hiddenColumnCount: Int
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(filters) { filter in
                        projectBoardViewPill(filter)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hiddenColumnCount > 0 {
                Text("\(hiddenColumnCount) hidden")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func projectBoardViewPill(_ filter: KanbanProjectBoardViewFilter) -> some View {
        let isSelected = selectedProjectBoardViewID == filter.id
        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                selectedProjectBoardViewID = filter.id
                projectLaneScrollIndexByID.removeAll()
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text(filter.label)
                    .lineLimit(1)

                Text("\(filter.cardCount)")
                    .font(CiderFont.micro)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? CiderColors.surfaceInput.opacity(0.94) : CiderColors.surfaceSubtle.opacity(0.48))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.borderSubtle : CiderColors.borderSubtle.opacity(0.58), lineWidth: CiderBorder.hairlineStrokeWidth)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.label) board view, \(filter.cardCount) cards")
    }

    private func projectLaneVisibleColumnCount(availableWidth: CGFloat) -> Int {
        let columnStride = KanbanDesign.projectColumnWidth + Spacing.md
        return max(1, Int(floor((availableWidth + Spacing.md) / columnStride)))
    }

    private func projectLaneScrollIdentity(for lane: KanbanBoardLane) -> String {
        return "\(lane.id)-active"
    }

    private func projectColumnScrollID(laneID: String, columnID: String) -> String {
        "\(laneID)-column-\(columnID)"
    }

    private func projectHiddenRailScrollID(laneID: String) -> String {
        "\(laneID)-hidden-rail"
    }

    private func projectLaneScrollIndex(for lane: KanbanBoardLane, maxScrollIndex: Int) -> Int {
        min(max(projectLaneScrollIndexByID[lane.id] ?? 0, 0), maxScrollIndex)
    }

    private func scrollProjectLane(
        _ lane: KanbanBoardLane,
        to index: Int,
        scrollItemCount: Int,
        maxScrollIndex: Int,
        scrollProxy: ScrollViewProxy
    ) {
        let nextIndex = min(max(index, 0), maxScrollIndex)
        projectLaneScrollIndexByID[lane.id] = nextIndex

        guard nextIndex < scrollItemCount else { return }

        let targetID = lane.columns.indices.contains(nextIndex)
            ? projectColumnScrollID(laneID: lane.id, columnID: lane.columns[nextIndex].id)
            : projectHiddenRailScrollID(laneID: lane.id)
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
            scrollProxy.scrollTo(
                targetID,
                anchor: .leading
            )
        }
    }

    private func milestoneFilterBanner(_ milestone: KanbanCard, board: KanbanBoard) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "diamond")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.controlAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(milestone.title.replacingOccurrences(of: "Milestone: ", with: ""))
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if let summary = KanbanBoardLayout.childSummary(for: milestone.id, in: board) {
                    Text("\(summary.progressText) · milestone filter")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                selectedMilestoneFilterCardID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Clear milestone filter")
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 8).fill(CiderColors.surfaceSubtle))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline))
    }

    private func projectLaneScrollControls(
        lane: KanbanBoardLane,
        visibleColumnCount: Int,
        scrollItemCount: Int,
        maxScrollIndex: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let currentIndex = projectLaneScrollIndex(for: lane, maxScrollIndex: maxScrollIndex)
        let visibleRange = currentIndex..<(min(currentIndex + visibleColumnCount, scrollItemCount))

        return HStack(spacing: Spacing.xs) {
            Button {
                scrollProjectLane(
                    lane,
                    to: currentIndex - 1,
                    scrollItemCount: scrollItemCount,
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
                ForEach(0..<scrollItemCount, id: \.self) { index in
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
                    scrollItemCount: scrollItemCount,
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

    private func hiddenColumnsRail(
        columns hiddenColumns: [KanbanColumn],
        board: KanbanBoard,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chevron.down")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)

                Text("Hidden columns")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: Spacing.xs)

                Text("\(hiddenColumns.count)")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(hiddenColumns) { column in
                    hiddenColumnRow(column, board: board)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(width: KanbanDesign.hiddenColumnsRailWidth, height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    private func hiddenColumnRow(_ column: KanbanColumn, board: KanbanBoard) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                storage.setColumnHidden(boardID: board.id, columnID: column.id, isHidden: false)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: column.isDoneColumn ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 18, alignment: .center)

                Text(column.name)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.xs)

                Text("\(filteredCards(column.cards, in: column, board: board).count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput.opacity(0.86))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show \(column.name)")
        .contextMenu {
            Button("Show Column") {
                storage.setColumnHidden(boardID: board.id, columnID: column.id, isHidden: false)
            }
        }
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
                    let cards = filteredCards(column.cards, in: column, board: board)
                    let nodes = KanbanBoardLayout.cardNodes(
                        for: column,
                        in: board,
                        visibleCards: cards
                    )
                    ForEach(nodes) { node in
                        interactiveCard(
                            node.card,
                            column: column,
                            board: board,
                            toIndex: node.visualIndex,
                            childSummary: KanbanBoardLayout.childSummary(for: node.card.id, in: board)
                        )
                        .id(node.id)
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

            Text("\(filteredCards(column.cards, in: column, board: board).count)")
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
                Button("Hide Column") {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86)) {
                        storage.setColumnHidden(boardID: boardID, columnID: column.id, isHidden: true)
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

    private func interactiveCard(
        _ card: KanbanCard,
        column: KanbanColumn,
        board: KanbanBoard,
        toIndex: Int,
        childSummary: KanbanParentChildSummary? = nil
    ) -> some View {
        let context = KanbanBoardLayout.boardCardContext(for: card, in: column, board: board)

        return cardView(
            card,
            compact: compactCards,
            childSummary: childSummary,
            parentBadge: context.parentBadge,
            planIndicator: context.planIndicator,
            accentColor: KanbanBoardLayout.cardAccentColor(for: card, in: board),
            inboxBadges: inboxBadges(for: card, in: column)
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
        inboxBadges: [ProjectWorkspaceInboxBadge] = []
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
                childSummary: childSummary
            )

            if !inboxBadges.isEmpty {
                cardInboxBadgesView(inboxBadges)
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
        childSummary: KanbanParentChildSummary?
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.xxs : Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.xs) {
                Text(displayKey(for: card))
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.controlAccent)
                    .lineLimit(1)

                if let childSummary {
                    childProgressChip(childSummary)
                }

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

    private func childProgressChip(_ summary: KanbanParentChildSummary) -> some View {
        HStack(spacing: Spacing.xxs) {
            ZStack {
                Circle()
                    .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
                    .frame(width: 12, height: 12)

                Circle()
                    .trim(from: 0, to: summary.totalCount == 0 ? 0 : CGFloat(summary.doneCount) / CGFloat(summary.totalCount))
                    .stroke(CiderColors.controlAccent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 12, height: 12)
            }

            Text(summary.progressText)
                .font(CiderFont.microMonospaced)
                .foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceInput.opacity(0.82))
        )
        .help(summary.compactText)
        .accessibilityLabel("Sub-issues \(summary.progressText), \(summary.compactText)")
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
            parentBadgeView(parentBadge)
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

                Text(badge.displayKey)
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.tertiary)

                Text("›")
                    .foregroundColor(CiderColors.quaternary)

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

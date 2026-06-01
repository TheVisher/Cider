import SwiftUI

struct CiderTabBar: View {
    @Binding var selectedTab: CiderTab?
    let tabs: [CiderTab]
    @Binding var selectedFolderID: UUID?
    var onCloseTab: ((CiderTab) -> Void)?
    var onDeleteTab: ((CiderTab) -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var projectBoardActionTitle: ((CiderTab) -> String?)?
    var onRemoveBoardFromProject: ((CiderTab) -> Void)?
    var onAddTab: (() -> Void)?
    var onOpenBoard: ((KanbanBoard) -> Void)?
    var projectAddableBoards: [KanbanBoard]?
    var onAddBoardToProject: ((KanbanBoard) -> Void)?
    var onOpenAIAssistantTab: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var kanbanStorage = KanbanStorage.shared

    @State private var draggingTabID: String?
    @State private var showAddTabPopover = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CiderPanelDesign.tabSpacing) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    tabButton(for: tab, at: index)
                }

                if let onAddTab {
                    addTabButton(action: onAddTab)
                }
            }
            .padding(.horizontal, CiderPanelDesign.tabHorizontalPadding)
        }
        .frame(height: CiderPanelDesign.tabBarHeight)
    }

    @ViewBuilder
    private func tabButton(for tab: CiderTab, at index: Int) -> some View {
        let isSelected = selectedTab == tab && selectedFolderID == nil
        let count = badgeCount(for: tab)
        let isDragging = draggingTabID == tab.id

        Button {
            withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
                selectedFolderID = nil
                selectedTab = tab
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: iconForTab(tab))
                    .font(CiderFont.bodyMedium)

                Text(tab.displayName)
                    .font(isSelected ? CiderFont.labelSemibold : CiderFont.label)
                    .lineLimit(1)

                if count > 0 {
                    Text("\(count)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                        .padding(.horizontal, CiderPanelDesign.tabBadgePadding)
                        .padding(.vertical, Spacing.hairline)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? CiderColors.separatorFirm : CiderColors.separatorLight)
                        )
                }
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.separatorMedium : Color.clear)
            )
            .contentShape(Rectangle())
            .opacity(isDragging ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .background(CiderWindowDragExclusionReporter(id: "tab-\(tab.id)"))
        .contextMenu {
            if let title = projectBoardActionTitle?(tab) {
                Button(title) {
                    onRemoveBoardFromProject?(tab)
                }
            } else if tab != .aiAssistant && !isPersistentContextTab(tab) {
                Button("Close Tab") {
                    onCloseTab?(tab)
                }
            }
        }
        .conditionalDraggable(
            tab: tab,
            index: index,
            tabs: tabs,
            draggingTabID: $draggingTabID,
            onReorder: onReorderTab
        )
    }

    private func addTabButton(action: @escaping () -> Void) -> some View {
        Button {
            showAddTabPopover.toggle()
        } label: {
            Image(systemName: "plus")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(CiderWindowDragExclusionReporter(id: "tab-add"))
        .help("New tab")
        .popover(isPresented: $showAddTabPopover, arrowEdge: .bottom) {
            addTabPopoverContent(action: action)
        }
    }

    @ViewBuilder
    private func addTabPopoverContent(action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let projectAddableBoards {
                if projectAddableBoards.isEmpty {
                    Text("All boards are already in this project")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                } else {
                    Text("Add Board to Project")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.xs)
                        .padding(.bottom, Spacing.xxs)

                    ForEach(projectAddableBoards) { board in
                        Button {
                            onAddBoardToProject?(board)
                            showAddTabPopover = false
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "square.split.2x1")
                                    .font(CiderFont.bodyMedium)
                                    .frame(width: Spacing.lg, alignment: .center)
                                Text(board.name)
                                    .font(CiderFont.body)
                                    .lineLimit(1)
                            }
                            .foregroundColor(CiderColors.secondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button {
                    action()
                    showAddTabPopover = false
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "plus")
                            .font(CiderFont.bodyMedium)
                            .frame(width: Spacing.lg, alignment: .center)
                        Text("New Tab")
                            .font(CiderFont.body)
                    }
                    .foregroundColor(CiderColors.primary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !tabs.contains(.aiAssistant), let onOpenAIAssistantTab {
                    Divider()
                        .padding(.vertical, Spacing.xxs)

                    Button {
                        onOpenAIAssistantTab()
                        showAddTabPopover = false
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(CiderFont.bodyMedium)
                                .frame(width: Spacing.lg, alignment: .center)
                            Text("AI Assistant")
                                .font(CiderFont.body)
                        }
                        .foregroundColor(CiderColors.secondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                let openBoardIDs = Set(tabs.compactMap { tab -> String? in
                    if case .projectBoard(_, let boardID, _) = tab { return boardID }
                    return nil
                })
                let unopenedBoards = kanbanStorage.boards.filter { !openBoardIDs.contains($0.id) }
                if !unopenedBoards.isEmpty {
                    Divider()
                        .padding(.vertical, Spacing.xxs)

                    Text("Boards")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.xs)
                        .padding(.bottom, Spacing.xxs)

                    ForEach(unopenedBoards) { board in
                        Button {
                            onOpenBoard?(board)
                            showAddTabPopover = false
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "square.split.2x1")
                                    .font(CiderFont.bodyMedium)
                                    .frame(width: Spacing.lg, alignment: .center)
                                Text(board.name)
                                    .font(CiderFont.body)
                                    .lineLimit(1)
                            }
                            .foregroundColor(CiderColors.secondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(minWidth: CiderTabDesign.addTabPopoverMinWidth)
    }

    private func iconForTab(_ tab: CiderTab) -> String {
        return tab.systemImage
    }

    private func isPersistentContextTab(_ tab: CiderTab) -> Bool {
        if case .domainDashboard = tab { return true }
        if case .projectOverview = tab { return true }
        if case .projectInbox = tab { return true }
        if case .projectBoard = tab { return true }
        if case .projectSurface = tab { return true }
        if case .projectReferences = tab { return true }
        return false
    }

    private func badgeCount(for tab: CiderTab) -> Int {
        switch tab {
        case .search: return 0
        case .tag: return 0
        case .domainDashboard: return 0
        case .projectOverview: return 0
        case .projectInbox: return 0
        case .projectBoard: return 0
        case .projectSurface: return 0
        case .projectReferences: return 0
        case .spaceOverview: return 0
        case .spacesManager: return 0
        case .aiAssistant: return 0
        }
    }
}

// MARK: - Conditional Tab Dragging

private extension View {
    @ViewBuilder
    func conditionalDraggable(
        tab: CiderTab,
        index: Int,
        tabs: [CiderTab],
        draggingTabID: Binding<String?>,
        onReorder: ((Int, Int) -> Void)?
    ) -> some View {
        self
    }
}

// MARK: - Drop Delegate for Reordering

private struct TabReorderDropDelegate: DropDelegate {
    let tabID: String
    let tabIndex: Int
    let tabs: [CiderTab]
    @Binding var draggingTabID: String?
    var onReorder: ((Int, Int) -> Void)?

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingTabID,
              draggingID != tabID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == draggingID }) else { return }
        onReorder?(sourceIndex, tabIndex)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTabID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingTabID != nil
    }
}

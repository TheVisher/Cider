import SwiftUI
import AppKit

struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject private var projectStorage = ProjectStorage.shared
    @State private var selectedTab: CiderTab = .home
    @State private var isCollapsed = false
    @State private var isFolderSidebarVisible = true
    @State private var selectedFolderID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var isSearchPaletteVisible = false
    @State private var dynamicTabs: [CiderTab] = []
    @State private var isCompactMode = false
    @State private var sidebarAutoCollapsed = false
    @State private var isViewOptionsVisible = false

    private var allTabs: [CiderTab] {
        CiderTab.fixedTabs + dynamicTabs
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AcrylicPanelBackground(
                cornerRadius: CiderPanelDesign.cornerRadius,
                shadowStyle: isCollapsed ? .compact : .full
            )

            VStack(spacing: 0) {
                titleBar

                if !isCollapsed {
                    Divider()
                        .background(CiderColors.separator)

                    tabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isSearchPaletteVisible {
                SearchPaletteView(
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmark in
                        bookmarksViewModel.open(bookmark)
                    },
                    onOpenNote: { note in
                        notesViewModel.selectNote(note)
                        selectedTab = .notes
                    },
                    onSpawnSearchTab: spawnSearchTab,
                    onDismiss: { isSearchPaletteVisible = false }
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isCollapsed {
                CiderPanelResizeIcon()
            }
        }
        .padding(.horizontal, CiderPanelDesign.shadowPadding)
        .padding(.top, CiderPanelDesign.topPadding)
        .padding(
            .bottom,
            isCollapsed
                ? CiderPanelDesign.collapsedBottomPadding
                : CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
        )
        .overlay {
            if !isCollapsed {
                PanelEdgeResizeView()
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .onChange(of: selectedTab) { _, _ in
            selectedFolderID = nil
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: CiderPanelDesign.trafficLightSpacing) {
                CiderTrafficLightButton(color: .systemRed, symbol: "xmark", help: "Close panel") {
                    NotificationCenter.default.post(name: .dismissCiderPanel, object: nil)
                }
                CiderTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: isCollapsed ? "Expand panel" : "Collapse to header"
                ) {
                    NotificationCenter.default.post(name: .toggleCiderPanelCollapse, object: nil)
                }
                CiderTrafficLightButton(
                    color: .systemGreen,
                    symbol: "arrow.up.left.and.arrow.down.right",
                    help: "Maximize panel"
                ) {
                    NotificationCenter.default.post(name: .maximizeCiderPanel, object: nil)
                }
            }

            Button(action: toggleFolderSidebar) {
                Image(systemName: isFolderSidebarVisible ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundColor(isFolderSidebarVisible ? CiderColors.controlAccent : CiderColors.secondary)
            .help(isFolderSidebarVisible ? "Hide folder sidebar" : "Show folder sidebar")

            CiderTabBar(
                selectedTab: $selectedTab,
                tabs: allTabs,
                bookmarkCount: bookmarksViewModel.bookmarks.count,
                noteCount: notesViewModel.notes.count,
                onCloseTab: closeTab
            )
            .frame(maxWidth: .infinity)

            if selectedTab == .bookmarks {
                Image(systemName: "safari")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
                    }
                    .help("Capture active browser tab")

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { isViewOptionsVisible.toggle() }
                    .help("View options")
                    .popover(isPresented: $isViewOptionsVisible) {
                        ViewOptionsDropdown(
                            displayMode: Binding(
                                get: { bookmarksViewModel.displayMode },
                                set: { bookmarksViewModel.setDisplayMode($0) }
                            ),
                            cardSizeScale: Binding(
                                get: { bookmarksViewModel.cardSizeScale },
                                set: { bookmarksViewModel.setCardSizeScale($0) }
                            )
                        )
                    }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: CiderPanelDesign.titleBarHeight)
        .background {
            Button("") { isSearchPaletteVisible = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ZStack(alignment: .leading) {
            // Main content — always fills full width
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Side-by-side sidebar (non-compact)
            // Handled inside mainContentArea via HStack when !isCompactMode

            // Overlay sidebar (compact mode)
            if isCompactMode && isFolderSidebarVisible {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) {
                            isFolderSidebarVisible = false
                        }
                    }

                folderSidebar
                    .padding(.leading, Spacing.md)
                    .padding(.vertical, Spacing.md)
                    .background(
                        ZStack {
                            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                            Color.black.opacity(0.45)
                        }
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: Radius.md,
                                topTrailingRadius: Radius.md,
                                style: .continuous
                            )
                        )
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width) { _, newWidth in
                        let compact = newWidth < CiderPanelDesign.sidebarCompactThreshold
                        if compact != isCompactMode {
                            isCompactMode = compact
                            if compact && isFolderSidebarVisible {
                                sidebarAutoCollapsed = true
                                isFolderSidebarVisible = false
                            } else if !compact && sidebarAutoCollapsed {
                                sidebarAutoCollapsed = false
                                isFolderSidebarVisible = true
                            }
                        }
                    }
                    .onAppear {
                        isCompactMode = proxy.size.width < CiderPanelDesign.sidebarCompactThreshold
                    }
            }
        )
        .animation(.snappy, value: isFolderSidebarVisible)
    }

    @ViewBuilder
    private var mainContentArea: some View {
        HStack(spacing: 0) {
            if !isCompactMode && isFolderSidebarVisible {
                folderSidebar
                    .padding(.leading, Spacing.md)
                    .padding(.vertical, Spacing.md)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            tabContentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var folderSidebar: some View {
        FolderSidebarView(
            folders: bookmarksViewModel.folders,
            bookmarks: bookmarksViewModel.bookmarks,
            notes: notesViewModel.notes,
            projects: projectStorage.activeProjects(),
            selectedFolderID: $selectedFolderID,
            expandedFolderIDs: $expandedFolderIDs,
            onCreateFolder: { bookmarksViewModel.createFolder(name: $0, parentID: $1) },
            onAssignBookmarkToFolder: { bookmarksViewModel.assign($0, toFolder: $1) },
            onAssignNoteToFolder: { notesViewModel.assignNote($0, toFolder: $1) },
            onOpenProject: openProjectTab,
            onCreateProject: createProject,
            onDeleteProject: deleteProject,
            onRenameProject: renameProject,
            onDeleteFolder: deleteFolder,
            onTriggerSearch: { isSearchPaletteVisible = true },
            onCreateBookmark: {
                selectedTab = .bookmarks
                selectedFolderID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .showBookmarkAddForm, object: nil)
                }
            },
            onCreateNote: {
                selectedTab = .notes
                selectedFolderID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .triggerNewNoteInTab, object: nil)
                }
            },
            onCaptureBrowserTab: {
                _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
            },
            onPasteFromClipboard: {
                _ = bookmarksViewModel.addBookmarkFromPasteboard()
            }
        )
    }

    @ViewBuilder
    private var tabContentBody: some View {
        if let folderID = selectedFolderID, selectedTab.isFixed {
            if isRootFolder(folderID) {
                RootFolderOverviewView(
                    folderID: folderID,
                    folders: bookmarksViewModel.folders,
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmarksViewModel.open($0) },
                    onOpenNote: { note in
                        notesViewModel.selectNote(note)
                        NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                    },
                    onSelectSubFolder: { subFolderID in
                        selectedFolderID = subFolderID
                        expandPathToFolder(subFolderID)
                    }
                )
            } else {
                FolderContentView(
                    folderID: folderID,
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmarksViewModel.open($0) },
                    onOpenNote: { note in
                        notesViewModel.selectNote(note)
                        NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                    }
                )
            }
        } else {
            switch selectedTab {
            case .home:
                HomeDashboardView(
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel
                )
            case .bookmarks:
                BookmarksTabContent(
                    viewModel: bookmarksViewModel,
                    selectedFolderID: nil
                )
            case .notes:
                NotesTabContent(
                    viewModel: notesViewModel,
                    searchText: "",
                    selectedFolderID: nil
                )
            case .search(_, let query):
                SearchTabContent(
                    query: query,
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmarksViewModel.open($0) },
                    onOpenNote: { note in
                        notesViewModel.selectNote(note)
                        selectedTab = .notes
                    },
                    onSaveAsProject: { name, results in
                        saveSearchAsProject(name: name, results: results)
                    }
                )
            case .project(let id, _):
                ProjectTabContent(
                    projectID: id,
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmarksViewModel.open($0) },
                    onOpenNote: { note in
                        notesViewModel.selectNote(note)
                        selectedTab = .notes
                    }
                )
            }
        }
    }

    private func toggleFolderSidebar() {
        withAnimation(.snappy) {
            isFolderSidebarVisible.toggle()
            sidebarAutoCollapsed = false
        }
    }

    // MARK: - Search Tab Management

    private func spawnSearchTab(_ query: String) {
        let tab = CiderTab.search(id: UUID(), query: query)
        dynamicTabs.append(tab)
        selectedTab = tab
    }

    private func closeTab(_ tab: CiderTab) {
        guard tab.isCloseable else { return }
        dynamicTabs.removeAll { $0 == tab }
        if selectedTab == tab {
            selectedTab = .home
        }
    }

    // MARK: - Project Management

    private func openProjectTab(_ projectID: UUID) {
        let projectName = ProjectStorage.shared.project(for: projectID)?.name ?? "Project"
        let tab = CiderTab.project(id: projectID, name: projectName)
        if !dynamicTabs.contains(where: { $0.projectID == projectID }) {
            dynamicTabs.append(tab)
        }
        selectedTab = dynamicTabs.first(where: { $0.projectID == projectID }) ?? tab
    }

    private func createProject() {
        let project = ProjectStorage.shared.createProject(name: "New Project")
        openProjectTab(project.id)
    }

    private func renameProject(_ projectID: UUID, _ newName: String) {
        ProjectStorage.shared.renameProject(projectID, to: newName)
        if let idx = dynamicTabs.firstIndex(where: { $0.projectID == projectID }) {
            dynamicTabs[idx] = .project(id: projectID, name: newName)
            if case .project(let id, _) = selectedTab, id == projectID {
                selectedTab = dynamicTabs[idx]
            }
        }
    }

    private func expandPathToFolder(_ folderID: UUID) {
        let folderByID = Dictionary(uniqueKeysWithValues: bookmarksViewModel.folders.map { ($0.id, $0) })
        var cursorID: UUID? = folderID
        var visited = Set<UUID>()

        while let currentID = cursorID,
              !visited.contains(currentID),
              let folder = folderByID[currentID] {
            visited.insert(currentID)
            cursorID = folder.parentID
        }

        for id in visited {
            expandedFolderIDs.insert(id)
        }
    }

    private func isRootFolder(_ folderID: UUID) -> Bool {
        bookmarksViewModel.folders.first(where: { $0.id == folderID })?.parentID == nil
    }

    private func deleteFolder(_ folderID: UUID) {
        if selectedFolderID == folderID {
            selectedFolderID = nil
        }
        bookmarksViewModel.deleteFolder(folderID)
    }

    private func deleteProject(_ projectID: UUID) {
        dynamicTabs.removeAll { $0.projectID == projectID }
        if case .project(let id, _) = selectedTab, id == projectID {
            selectedTab = .home
        }
        ProjectStorage.shared.deleteProject(projectID)
    }

    private func saveSearchAsProject(name: String, results: [SearchResult]) {
        let project = ProjectStorage.shared.createProject(name: name)
        ProjectStorage.shared.addSearchResults(results, toProject: project.id)
        dynamicTabs.removeAll { $0 == selectedTab }
        openProjectTab(project.id)
    }

    // MARK: - Collapse State Sync

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }
}

// MARK: - Traffic Light Button

private struct CiderTrafficLightButton: View {
    let color: NSColor
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: CiderPanelDesign.trafficLightDiameter, height: CiderPanelDesign.trafficLightDiameter)
                .overlay {
                    if isHovered {
                        Image(systemName: symbol)
                            .font(.system(size: CiderPanelDesign.trafficLightSymbolSize, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.65))
                    }
                }
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
        .help(help)
    }
}

// MARK: - Resize Icon (decoration only)

private struct CiderPanelResizeIcon: View {
    var body: some View {
        Image(systemName: "arrow.down.backward.and.arrow.up.forward")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(CiderColors.quaternary)
            .frame(width: 16, height: 16)
            .allowsHitTesting(false)
    }
}

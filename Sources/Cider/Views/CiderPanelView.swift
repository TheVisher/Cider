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
    @State private var isNoteViewOptionsVisible = false

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

            HStack(spacing: 0) {
                // Left: full-height sidebar column
                if !isCollapsed && !isCompactMode && isFolderSidebarVisible {
                    sidebarColumn
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Right: title bar + content
                VStack(spacing: 0) {
                    titleBar

                    if !isCollapsed {
                        Divider()
                            .background(CiderColors.separator)
                            .padding(.horizontal, Spacing.md)

                        contentArea
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // Compact overlay sidebar
            if !isCollapsed && isCompactMode && isFolderSidebarVisible {
                compactOverlaySidebar
            }

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
        .animation(reduceMotion ? .none : .snappy, value: isFolderSidebarVisible)
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .onChange(of: selectedTab) { _, _ in
            selectedFolderID = nil
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
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
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: CiderPanelDesign.titleBarHeight)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Close") {
                NotificationCenter.default.post(name: .dismissCiderPanel, object: nil)
            }
            Button(isCollapsed ? "Expand" : "Minimize") {
                NotificationCenter.default.post(name: .toggleCiderPanelCollapse, object: nil)
            }
            Button("Maximize") {
                NotificationCenter.default.post(name: .maximizeCiderPanel, object: nil)
            }
        }
        .background {
            Button("") { isSearchPaletteVisible = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Sidebar Column

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            // Traffic lights inside the rounded sidebar
            sidebarHeader

            // Folder content (no background — wrapper handles it)
            folderSidebar
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: CiderBorder.innerStrokeWidth)
        )
        .padding(.leading, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    private var sidebarHeader: some View {
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

            Spacer(minLength: 0)

            if selectedTab == .bookmarks {
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
            } else if selectedTab == .notes {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isNoteViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { isNoteViewOptionsVisible.toggle() }
                    .help("View options")
                    .popover(isPresented: $isNoteViewOptionsVisible) {
                        ViewOptionsDropdown(
                            displayMode: Binding(
                                get: { notesViewModel.displayMode },
                                set: { notesViewModel.setDisplayMode($0) }
                            ),
                            cardSizeScale: Binding(
                                get: { notesViewModel.cardSizeScale },
                                set: { notesViewModel.setCardSizeScale($0) }
                            )
                        )
                    }
            }
        }
        .frame(height: BookmarksDesign.buttonTapTarget)
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .frame(maxWidth: BookmarksDesign.folderSidebarWidth, alignment: .leading)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        tabContentBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    // MARK: - Compact Overlay Sidebar

    private var compactOverlaySidebar: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) {
                        isFolderSidebarVisible = false
                    }
                }

            VStack(spacing: 0) {
                sidebarHeader

                folderSidebar
            }
            .background(
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    Color.black.opacity(0.45)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: CiderPanelDesign.cornerRadius,
                        bottomLeadingRadius: CiderPanelDesign.cornerRadius,
                        bottomTrailingRadius: Radius.md,
                        topTrailingRadius: Radius.md,
                        style: .continuous
                    )
                )
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
        .animation(.snappy, value: isFolderSidebarVisible)
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
            },
            showBackground: false
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
                    folders: bookmarksViewModel.folders,
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

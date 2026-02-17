import SwiftUI
import AppKit

struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject private var projectStorage = ProjectStorage.shared
    @State private var selectedTab: CiderTab = .home
    @State private var isCollapsed = false
    @State private var selectedFolderID: UUID?
    @State private var selectedItemIDs: Set<String> = []
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var isSearchPaletteVisible = false
    @State private var dynamicTabs: [CiderTab] = []
    @State private var isViewOptionsVisible = false
    @State private var isNoteViewOptionsVisible = false
    @State private var isHomeViewOptionsVisible = false
    @State private var homeDisplayMode: LibraryDisplayMode = CiderConfig.load().homeDisplayMode
    @State private var homeCardSizeScale: Double = CiderConfig.load().homeCardSizeScale ?? 1.0
    @State private var continueSectionCollapsed: Bool = CiderConfig.load().continueSectionCollapsed
    @State private var showContinueSection: Bool = CiderConfig.load().showContinueSection
    @State private var subFoldersCollapsed: Bool = CiderConfig.load().subFoldersCollapsed

    private var allTabs: [CiderTab] {
        CiderTab.fixedTabs + dynamicTabs
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CiderPanelShell(
            isCollapsed: isCollapsed,
            onClose: { NotificationCenter.default.post(name: .dismissCiderPanel, object: nil) },
            onCollapse: { NotificationCenter.default.post(name: .toggleCiderPanelCollapse, object: nil) },
            onMaximize: { NotificationCenter.default.post(name: .maximizeCiderPanel, object: nil) }
        ) {
            folderSidebar
        } sidebarFooter: {
            sidebarFooterView
        } titleBar: {
            titleBarContent
        } content: {
            contentArea
        } overlay: {
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
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .onChange(of: selectedTab) { _, _ in
            selectedFolderID = nil
            selectedItemIDs.removeAll()
        }
        .onChange(of: selectedFolderID) { _, _ in
            selectedItemIDs.removeAll()
        }
        .onChange(of: homeDisplayMode) { _, newValue in
            var config = CiderConfig.load()
            config.homeDisplayMode = newValue
            config.save()
        }
        .onChange(of: homeCardSizeScale) { _, newValue in
            var config = CiderConfig.load()
            config.homeCardSizeScale = newValue
            config.save()
        }
        .onChange(of: continueSectionCollapsed) { _, newValue in
            var config = CiderConfig.load()
            config.continueSectionCollapsed = newValue
            config.save()
        }
        .onChange(of: subFoldersCollapsed) { _, newValue in
            var config = CiderConfig.load()
            config.subFoldersCollapsed = newValue
            config.save()
        }
        .background {
            Button("") { isSearchPaletteVisible = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()

            Button("") { selectAllVisibleItems() }
                .keyboardShortcut("a", modifiers: .command)
                .hidden()

            Button("") {
                if !selectedItemIDs.isEmpty {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        selectedItemIDs.removeAll()
                    }
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .hidden()
        }
    }

    // MARK: - Title Bar Content

    @ViewBuilder
    private var titleBarContent: some View {
        if !selectedItemIDs.isEmpty {
            selectionTitleBar
        } else {
            normalTitleBar
        }
    }

    @ViewBuilder
    private var normalTitleBar: some View {
        CiderTabBar(
            selectedTab: $selectedTab,
            tabs: allTabs,
            bookmarkCount: bookmarksViewModel.bookmarks.count,
            noteCount: notesViewModel.notes.count,
            selectedFolderID: $selectedFolderID,
            onCloseTab: closeTab
        )
        .frame(maxWidth: .infinity)

        if selectedTab == .bookmarks {
            Image(systemName: "safari")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .onTapGesture {
                    _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
                }
                .help("Capture active browser tab")
        }

        if selectedTab == .home && selectedFolderID == nil && showContinueSection {
            SectionCollapseToggle(
                label: "Recents",
                isCollapsed: $continueSectionCollapsed,
                collapsedHelp: "Show recent items",
                expandedHelp: "Hide recent items"
            )
        } else if selectedFolderID != nil && folderHasSubFolders {
            SectionCollapseToggle(
                label: "Folders",
                isCollapsed: $subFoldersCollapsed,
                collapsedHelp: "Show sub-folders",
                expandedHelp: "Hide sub-folders"
            )
        }
    }

    @ViewBuilder
    private var selectionTitleBar: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                selectedItemIDs.removeAll()
            }
        } label: {
            Image(systemName: "xmark")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear selection")

        Text("\(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s") selected")
            .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.primary)
            .lineLimit(1)

        Spacer(minLength: Spacing.sm)

        Menu {
            ForEach(bookmarksViewModel.folders) { folder in
                Button(folder.name) {
                    moveSelectedToFolder(folder.id)
                }
            }
            if !bookmarksViewModel.folders.isEmpty {
                Divider()
            }
            Button("Remove from Folder") {
                moveSelectedToFolder(nil)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(CiderFont.captionSemibold)
                Text("Move")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move selected items to folder")

        Button {
            deleteSelectedItems()
        } label: {
            Image(systemName: "trash")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.destructive)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete selected items")
    }

    // MARK: - Section Toggles

    private var folderHasSubFolders: Bool {
        guard let folderID = selectedFolderID else { return false }
        return bookmarksViewModel.folders.contains(where: { $0.parentID == folderID })
    }


    // MARK: - Sidebar Content

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
            onRenameFolder: { bookmarksViewModel.renameFolder($0, to: $1) },
            onDeleteFolder: deleteFolder,
            onTriggerSearch: { isSearchPaletteVisible = true },
            showBackground: false
        )
    }

    // MARK: - Sidebar Footer

    private var sidebarFooterView: some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .background(CiderColors.separator)
                .padding(.bottom, Spacing.xs)

            HStack(spacing: Spacing.sm) {
                // Settings gear
                Button {
                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer(minLength: 0)

                // + pill menu
                Menu {
                    Button {
                        NotificationCenter.default.post(name: .showFolderCreationField, object: nil)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button(action: createProject) {
                        Label("New Project", systemImage: "tray.full")
                    }
                    Button {
                        selectedTab = .bookmarks
                        selectedFolderID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NotificationCenter.default.post(name: .showBookmarkAddForm, object: nil)
                        }
                    } label: {
                        Label("New Bookmark", systemImage: "bookmark")
                    }
                    Button {
                        selectedTab = .notes
                        selectedFolderID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NotificationCenter.default.post(name: .triggerNewNoteInTab, object: nil)
                        }
                    } label: {
                        Label("New Note", systemImage: "note.text")
                    }
                    Divider()
                    Button {
                        _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
                    } label: {
                        Label("Capture Browser Tab", systemImage: "safari")
                    }
                    Button {
                        _ = bookmarksViewModel.addBookmarkFromPasteboard()
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                        Text("New")
                            .font(CiderFont.bodyMedium)
                    }
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: CiderPanelDesign.trafficLightTapTarget)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Create new item")

                Spacer(minLength: 0)

                // View options
                viewOptionsButton
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
    }

    private var showFolderViewOptions: Bool {
        selectedFolderID != nil && selectedTab.isFixed
    }

    @ViewBuilder
    private var viewOptionsButton: some View {
        if showFolderViewOptions {
            // Folder view uses home display mode
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isHomeViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
                .onTapGesture { isHomeViewOptionsVisible.toggle() }
                .help("View options")
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale
                    )
                }
        } else if selectedTab == .bookmarks {
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
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
                .font(CiderFont.bodySemibold)
                .foregroundColor(isNoteViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
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
        } else if selectedTab == .home {
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isHomeViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
                .onTapGesture { isHomeViewOptionsVisible.toggle() }
                .help("View options")
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale
                    )
                }
        } else {
            // Invisible spacer to keep layout stable
            Color.clear
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        tabContentBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabContentBody: some View {
        if let folderID = selectedFolderID, selectedTab.isFixed {
            FolderDetailView(
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                folderID: folderID,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale,
                selectedItemIDs: $selectedItemIDs,
                subFoldersCollapsed: $subFoldersCollapsed,
                onSelectSubFolder: { subFolderID in
                    selectedFolderID = subFolderID
                    expandPathToFolder(subFolderID)
                }
            )
        } else {
            switch selectedTab {
            case .home:
                HomeDashboardView(
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    selectedFolderID: selectedFolderID,
                    displayMode: $homeDisplayMode,
                    cardSizeScale: $homeCardSizeScale,
                    continueSectionCollapsed: $continueSectionCollapsed,
                    selectedItemIDs: $selectedItemIDs
                )
            case .bookmarks:
                BookmarksTabContent(
                    viewModel: bookmarksViewModel,
                    selectedFolderID: nil,
                    selectedItemIDs: $selectedItemIDs
                )
            case .notes:
                NotesTabContent(
                    viewModel: notesViewModel,
                    searchText: "",
                    folders: bookmarksViewModel.folders,
                    selectedFolderID: nil,
                    selectedItemIDs: $selectedItemIDs
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

    // MARK: - Select All

    private func selectAllVisibleItems() {
        if let folderID = selectedFolderID, selectedTab.isFixed {
            let bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
            let notes = notesViewModel.notes.filter { $0.folderID == folderID }
            for b in bookmarks { selectedItemIDs.insert("bookmark-\(b.id.uuidString)") }
            for n in notes { selectedItemIDs.insert("note-\(n.id.uuidString)") }
        } else {
            switch selectedTab {
            case .home:
                for b in bookmarksViewModel.bookmarks { selectedItemIDs.insert("bookmark-\(b.id.uuidString)") }
                for n in notesViewModel.notes { selectedItemIDs.insert("note-\(n.id.uuidString)") }
            case .bookmarks:
                for b in bookmarksViewModel.filteredBookmarks { selectedItemIDs.insert("bookmark-\(b.id.uuidString)") }
            case .notes:
                for n in notesViewModel.notes { selectedItemIDs.insert("note-\(n.id.uuidString)") }
            default:
                break
            }
        }
    }

    // MARK: - Bulk Selection Actions

    private func deleteSelectedItems() {
        var bookmarksToDelete: [Bookmark] = []
        var notesToDelete: [Note] = []

        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    bookmarksToDelete.append(bookmark)
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    notesToDelete.append(note)
                }
            }
        }

        if !bookmarksToDelete.isEmpty {
            bookmarksViewModel.deleteBookmarks(bookmarksToDelete)
        }
        if !notesToDelete.isEmpty {
            notesViewModel.deleteNotes(notesToDelete)
        }

        selectedItemIDs.removeAll()
    }

    private func moveSelectedToFolder(_ folderID: UUID?) {
        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    _ = notesViewModel.assignNote(note, toFolder: folderID)
                }
            }
        }

        selectedItemIDs.removeAll()
    }

    // MARK: - Collapse State Sync

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }
}

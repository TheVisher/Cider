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
                CiderPanelResizeHandle()
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
            }

            CiderTabBar(
                selectedTab: $selectedTab,
                tabs: allTabs,
                bookmarkCount: bookmarksViewModel.bookmarks.count,
                noteCount: notesViewModel.notes.count,
                onCloseTab: closeTab
            )

            Spacer(minLength: Spacing.sm)

            Button(action: { isSearchPaletteVisible = true }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CiderColors.tertiary)

                    Text("Search")
                        .font(.system(size: 12))
                        .foregroundColor(CiderColors.tertiary)

                    Spacer(minLength: 0)

                    Text("\u{2318}K")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CiderColors.quaternary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: 180)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.separator.opacity(0.25))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)

            Button(action: toggleFolderSidebar) {
                Image(systemName: isFolderSidebarVisible ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundColor(isFolderSidebarVisible ? CiderColors.controlAccent : CiderColors.secondary)
            .help(isFolderSidebarVisible ? "Hide folder sidebar" : "Show folder sidebar")

            Button {
                NotificationCenter.default.post(name: .openCiderSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24)
            .help("Settings")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: CiderPanelDesign.titleBarHeight)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        HStack(spacing: 0) {
            if isFolderSidebarVisible {
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
                    onDeleteFolder: deleteFolder
                )
                .padding(.leading, Spacing.md)
                .padding(.vertical, Spacing.md)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy, value: isFolderSidebarVisible)
    }

    private func toggleFolderSidebar() {
        withAnimation(.snappy) {
            isFolderSidebarVisible.toggle()
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

// MARK: - Resize Handle

private struct CiderPanelResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> CiderPanelResizeHandleNSView {
        let view = CiderPanelResizeHandleNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: CiderPanelResizeHandleNSView, context: Context) {}
}

private final class CiderPanelResizeHandleNSView: NSView {
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 16, height: 16)
    }

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(
            systemSymbolName: "arrow.down.backward.and.arrow.up.forward",
            accessibilityDescription: "Resize"
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        if let symbol {
            let size = symbol.size
            let origin = NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            )
            symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.35)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.frameResize(position: .bottomRight, directions: [.inward, .outward]).push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let initialFrame = window.frame
        let initialMouse = NSEvent.mouseLocation

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                let w = max(CiderPanelDesign.panelMinWidth, initialFrame.width + dx)
                let h = max(CiderPanelDesign.panelMinHeight, initialFrame.height - dy)
                let y = initialFrame.origin.y + (initialFrame.height - h)

                window.setFrame(
                    NSRect(x: initialFrame.origin.x, y: y, width: w, height: h),
                    display: true
                )

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }
    }
}

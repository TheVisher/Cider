import SwiftUI
import AppKit
import Combine

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var pinnedApps: [AppInfo] = []
    @Published var folders: [AppFolder] = []
    @Published var windowGroups: [WindowAppGroup] = []
    @Published var activeTab: PaletteTab = .windows
    @Published var isVisible = false
    @Published var monitors: [MonitorInfo] = []
    @Published var focusState: PaletteFocusState = .initial
    @Published var searchText: String = ""
    @Published var expandedFolderID: UUID?
    /// The screen ID where the palette is currently shown
    var paletteScreenID: UInt32?
    @Published var focusedFolderAppIndex: Int? = nil
    @Published var isDraggingWindow = false
    /// The window ID currently being dragged from the palette (for split zone targeting).
    @Published var currentDraggedWindowID: CGWindowID?
    /// The PID of the window being dragged — stored at drag start so we don't need to look it up later.
    var currentDraggedWindowPID: pid_t = 0
    @Published var savedLayouts: [SavedTileLayout] = []

    private let windowListViewModel: WindowListViewModel
    private let pinnedAppsViewModel: PinnedAppsViewModel
    private let appLauncher = AppLauncher()
    private var cancellables = Set<AnyCancellable>()

    struct NoteSearchResult: Identifiable, Hashable {
        var id: UUID { note.id }
        let note: Note
        let snippet: String?
        let score: Int
    }

    private static let noteSearchSnippetContextLength = 52
    private static let noteSearchSnippetMaxLength = 132

    init(windowListViewModel: WindowListViewModel, pinnedAppsViewModel: PinnedAppsViewModel) {
        self.windowListViewModel = windowListViewModel
        self.pinnedAppsViewModel = pinnedAppsViewModel

        // Sync pinned apps
        pinnedAppsViewModel.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.pinnedApps = apps
            }
            .store(in: &cancellables)

        // Sync window groups
        windowListViewModel.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] groups in
                self?.windowGroups = groups
            }
            .store(in: &cancellables)

        // Re-render when notes change (e.g. after deletion)
        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Sync monitors
        windowListViewModel.$monitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] monitors in
                self?.monitors = monitors
            }
            .store(in: &cancellables)

        // Sync saved tile layouts
        SavedTileLayoutManager.shared.$layouts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layouts in
                self?.savedLayouts = layouts
            }
            .store(in: &cancellables)

        // Load folders from config (placeholder for now)
        loadFolders()
    }

    // MARK: - App Actions

    func launchApp(_ app: AppInfo) {
        let config = CiderConfig.load()
        let shouldStage = config.autoHideApps
        let targetScreenID = paletteScreenID
        let isAlreadyRunning = !app.bundleIdentifier.isEmpty &&
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first != nil

        appLauncher.launchOrFocus(app)
        dismiss()

        guard let targetScreenID else { return }
        let bundleID = app.bundleIdentifier
        guard !bundleID.isEmpty else { return }

        Task.detached { [weak self] in
            // Poll for app launch off the main actor
            if isAlreadyRunning {
                try? await Task.sleep(nanoseconds: 150_000_000)
            } else {
                for _ in 0..<25 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }) != nil {
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }

            // Back to main actor for UI updates
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
                let pid = running.processIdentifier

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var moved = false
                    for attempt in 0..<5 {
                        if attempt > 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
                        moved = self.windowListViewModel.moveAppToScreen(pid: pid, screenID: targetScreenID)
                        if moved { break }
                    }

                    if shouldStage {
                        if !moved { try? await Task.sleep(nanoseconds: 200_000_000) }
                        self.windowListViewModel.stageOtherApps(exceptPID: pid, onScreenID: targetScreenID)
                    }
                }
            }
        }
    }

    func isRunning(_ app: AppInfo) -> Bool {
        pinnedAppsViewModel.isRunning(app)
    }

    func quitApp(_ app: AppInfo) {
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first {
            runningApp.terminate()
        }
    }

    func reorderApps(_ newOrder: [AppInfo]) {
        pinnedAppsViewModel.reorder(newOrder)
    }

    /// Look up the PID for a window ID from the current window list.
    func findPID(for windowID: CGWindowID) -> pid_t {
        for monitorGroup in windowListViewModel.monitorGroups {
            for group in monitorGroup.windowGroups {
                if let window = group.windows.first(where: { $0.id == windowID }) {
                    return window.ownerPID
                }
            }
        }
        return 0
    }

    // MARK: - Window Actions

    func focusWindow(_ window: WindowInfo) {
        windowListViewModel.focus(window: window)
        dismiss()
    }

    func closeWindow(_ window: WindowInfo) {
        windowListViewModel.close(window: window)
    }

    func minimizeWindow(_ window: WindowInfo) {
        windowListViewModel.minimize(window: window)
    }

    func quitWindowApp(_ window: WindowInfo) {
        windowListViewModel.quitApp(for: window)
    }

    func moveWindow(_ window: WindowInfo, to monitor: MonitorInfo) {
        windowListViewModel.moveWindow(window, to: monitor)
    }

    /// Find a window by its ID across all monitor groups.
    private func findWindow(byID windowID: CGWindowID) -> WindowInfo? {
        for monitorGroup in windowListViewModel.monitorGroups {
            for group in monitorGroup.windowGroups {
                if let window = group.windows.first(where: { $0.id == windowID }) {
                    return window
                }
            }
        }
        return nil
    }

    func moveWindowByID(_ windowID: CGWindowID, to monitor: MonitorInfo) {
        guard let window = findWindow(byID: windowID) else { return }
        // Don't move if already on the target monitor
        if window.screenID != monitor.id {
            windowListViewModel.moveWindow(window, to: monitor)
        }
    }

    func tileWindow(_ window: WindowInfo, position: TilePosition) {
        dismiss()
        windowListViewModel.tileWindow(window, position: position)
    }

    func tileWindowByID(_ windowID: CGWindowID, position: TilePosition, on monitor: MonitorInfo) {
        guard let window = findWindow(byID: windowID) else { return }
        let wlvm = windowListViewModel
        windowListViewModel.windowManager.tileWindow(window, position: position, on: monitor) { [weak self] success in
            if success {
                self?.dismiss()
                NotificationCenter.default.post(name: .ciderTileActionCompleted, object: nil)
            }
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { wlvm.refresh() }
            }
        }
    }

    // MARK: - Tile Group Actions

    /// Build tile group displays for each monitor from the active DynamicTileManager groups.
    func tileGroupDisplays(for screenID: UInt32) -> [TileGroupDisplay] {
        let activeGroups = DynamicTileManager.shared.activeTileGroups()
        var displays: [TileGroupDisplay] = []

        for group in activeGroups where group.screenID == screenID {
            let windows: [WindowInfo] = group.windowIDs.compactMap { findWindow(byID: $0) }
            guard !windows.isEmpty else { continue }
            // Deduplicate app names while preserving order
            var seen = Set<String>()
            let uniqueNames = windows.compactMap { w -> String? in
                if seen.insert(w.ownerName).inserted { return w.ownerName }
                return nil
            }
            let name = uniqueNames.joined(separator: " + ")
            displays.append(TileGroupDisplay(
                id: group.groupID,
                windows: windows,
                groupID: group.groupID,
                screenID: screenID,
                displayName: name
            ))
        }

        return displays
    }

    /// Set of all window IDs that belong to active tile groups (for filtering from app groups).
    var tiledWindowIDs: Set<CGWindowID> {
        let activeGroups = DynamicTileManager.shared.activeTileGroups()
        var ids = Set<CGWindowID>()
        for group in activeGroups {
            for wid in group.windowIDs {
                ids.insert(wid)
            }
        }
        return ids
    }

    /// Saved layouts for a specific monitor index.
    func savedLayouts(for screenIndex: Int) -> [SavedTileLayout] {
        savedLayouts.filter { $0.targetScreenIndex == screenIndex }
    }

    func pinTileGroup(groupID: UUID) {
        SavedTileLayoutManager.shared.saveCurrentGroup(groupID: groupID)
    }

    func breakApartTileGroup(groupID: UUID) {
        guard let group = DynamicTileManager.shared.group(for: groupID) else { return }
        let windowIDs = group.root.allWindowIDs().map(\.0)
        for wid in windowIDs {
            DynamicTileManager.shared.removeWindow(wid)
        }
    }

    func focusTileGroup(_ display: TileGroupDisplay) {
        for window in display.windows {
            windowListViewModel.focus(window: window)
        }
        dismiss()
    }

    func restoreSavedLayout(_ layout: SavedTileLayout) {
        SavedTileLayoutManager.shared.restoreLayout(layout)
        dismiss()
    }

    func deleteSavedLayout(_ layout: SavedTileLayout) {
        SavedTileLayoutManager.shared.deleteLayout(layout)
    }

    // MARK: - Notes Integration

    var notes: [Note] {
        NotesStorage.shared.notes
    }

    var noteSearchResults: [NoteSearchResult] {
        guard isSearching else {
            return notes.map { NoteSearchResult(note: $0, snippet: nil, score: 0) }
        }

        let query = searchQuery
        guard !query.isEmpty else {
            return notes.map { NoteSearchResult(note: $0, snippet: nil, score: 0) }
        }

        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        return notes
            .compactMap { buildNoteSearchResult(for: $0, query: query, terms: terms) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.note.modifiedAt > rhs.note.modifiedAt
                }
                return lhs.score > rhs.score
            }
    }

    var filteredNotes: [Note] {
        noteSearchResults.map(\.note)
    }

    var noteSearchSnippetsByID: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: noteSearchResults.compactMap { result in
                guard let snippet = result.snippet, !snippet.isEmpty else { return nil }
                return (result.note.id, snippet)
            }
        )
    }

    func openNote(_ note: Note) {
        NotificationCenter.default.post(name: .openNoteInPanel, object: note)
        dismiss()
    }

    func createNewNoteFromPalette() {
        let note = NotesStorage.shared.createNew()
        NotificationCenter.default.post(name: .openNoteInPanel, object: note)
        dismiss()
    }

    func deleteNotes(_ notes: [Note]) {
        guard !notes.isEmpty else { return }
        for note in notes {
            NotesStorage.shared.delete(note: note)
        }
    }

    private func buildNoteSearchResult(for note: Note, query: String, terms: [String]) -> NoteSearchResult? {
        let title = note.title
        let titleMatch = phraseRange(in: title, query: query)
        let titleTermMatches = terms.reduce(into: 0) { count, term in
            if phraseRange(in: title, query: term) != nil {
                count += 1
            }
        }

        let rawContent = NotesStorage.shared.loadContent(for: note)
        let searchableContent = normalizedSearchSnippetContent(rawContent)
        let contentMatch = phraseRange(in: searchableContent, query: query)
        let contentTermMatches = terms.reduce(into: 0) { count, term in
            if phraseRange(in: searchableContent, query: term) != nil {
                count += 1
            }
        }

        let hasPhraseMatch = titleMatch != nil || contentMatch != nil
        let hasTokenMatch = titleTermMatches > 0 || contentTermMatches > 0
        guard hasPhraseMatch || hasTokenMatch else { return nil }

        var score = 0

        if let match = titleMatch {
            score += 1200
            score += max(0, 100 - match.location)
        }

        if let match = contentMatch {
            score += 850
            score += max(0, 100 - (match.location / 2))
        }

        score += titleTermMatches * 140
        score += contentTermMatches * 45

        let snippet: String?
        if let contentMatch {
            snippet = snippetForContent(searchableContent, matchRange: contentMatch)
        } else {
            var fallbackSnippet: String?
            for term in terms {
                guard let range = phraseRange(in: searchableContent, query: term) else { continue }
                fallbackSnippet = snippetForContent(searchableContent, matchRange: range)
                break
            }
            snippet = fallbackSnippet
        }

        return NoteSearchResult(note: note, snippet: snippet, score: score)
    }

    private func phraseRange(in text: String, query: String) -> NSRange? {
        guard !text.isEmpty, !query.isEmpty else { return nil }
        let range = (text as NSString).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        return range.location == NSNotFound ? nil : range
    }

    private func normalizedSearchSnippetContent(_ content: String) -> String {
        var normalized = content
        normalized = normalized.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\!\[[^\]]*\]\([^)]+\)"#,
            with: " [image] ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snippetForContent(_ content: String, matchRange: NSRange) -> String {
        let nsContent = content as NSString
        let context = Self.noteSearchSnippetContextLength
        let start = max(0, matchRange.location - context)
        let end = min(nsContent.length, matchRange.location + matchRange.length + context)
        let snippetRange = NSRange(location: start, length: max(0, end - start))

        var snippet = nsContent.substring(with: snippetRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if start > 0 {
            snippet = "…\(snippet)"
        }
        if end < nsContent.length {
            snippet += "…"
        }

        if snippet.count > Self.noteSearchSnippetMaxLength {
            let limit = max(0, Self.noteSearchSnippetMaxLength - 1)
            snippet = String(snippet.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
            snippet += "…"
        }

        return snippet
    }

    /// Filter search results for saved layouts.
    var filteredSavedLayouts: [SavedTileLayout] {
        guard isSearching else { return savedLayouts }
        return savedLayouts.filter { layout in
            layout.name.lowercased().contains(searchQuery) ||
            layout.root.apps.contains(where: { $0.appName.lowercased().contains(searchQuery) })
        }
    }

    // MARK: - Folder Actions

    func toggleFolder(_ folder: AppFolder) {
        if expandedFolderID == folder.id {
            expandedFolderID = nil
        } else {
            expandedFolderID = folder.id
        }
        focusedFolderAppIndex = nil
    }

    func reorderFolders(_ newOrder: [AppFolder]) {
        guard newOrder.map(\.id) != folders.map(\.id) else { return }
        folders = newOrder
        saveFolders()
    }

    // MARK: - Navigation

    func dismiss() {
        isVisible = false
        windowListViewModel.pauseTimer()
        NotificationCenter.default.post(name: .dismissCommandPalette, object: nil)
    }

    func openSettings() {
        NotificationCenter.default.post(name: .openCiderSettings, object: nil)
    }

    func show() {
        isVisible = true
        // Clear any previous search
        searchText = ""

        let config = CiderConfig.load()
        if !config.rememberPaletteState {
            expandedFolderID = nil
        }
        focusedFolderAppIndex = nil

        // Track which screen the palette is on (mouse location at show time)
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }),
           let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            paletteScreenID = screenNumber.uint32Value
        }

        // Resume timer and refresh data when shown
        windowListViewModel.resumeTimer()
        windowListViewModel.refresh()
        // Reset focus to search
        resetFocus()
    }

    // MARK: - Search Filtering

    /// Whether search is active (has text)
    var isSearching: Bool {
        !searchText.isEmpty
    }

    /// Normalized search query (lowercase, trimmed)
    private var searchQuery: String {
        searchText.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Filtered pinned apps based on search text (preserving unified order)
    var filteredApps: [AppInfo] {
        let apps = pinnedItems.compactMap { $0.appInfo }
        guard isSearching else { return apps }
        return apps.filter { $0.name.lowercased().contains(searchQuery) }
    }

    /// Filtered folders based on search text (preserving unified order)
    var filteredFolders: [AppFolder] {
        let flds = pinnedItems.compactMap { $0.appFolder }
        guard isSearching else { return flds }
        return flds.filter { $0.name.lowercased().contains(searchQuery) }
    }

    /// Filtered window groups - keeps groups that have matching windows
    var filteredWindowGroups: [WindowAppGroup] {
        guard isSearching else { return windowGroups }

        return windowGroups.compactMap { group -> WindowAppGroup? in
            // Filter windows by title or app name
            let matchingWindows = group.windows.filter { window in
                window.title.lowercased().contains(searchQuery) ||
                window.ownerName.lowercased().contains(searchQuery)
            }

            // Also include if app name matches (show all windows)
            if group.appName.lowercased().contains(searchQuery) {
                return group
            }

            // Return group with filtered windows, or nil if no matches
            guard !matchingWindows.isEmpty else { return nil }
            return WindowAppGroup(
                id: group.id,
                appName: group.appName,
                bundleIdentifier: group.bundleIdentifier,
                windows: matchingWindows
            )
        }
    }

    /// Filtered monitor groups - keeps monitors that have matching windows.
    /// Tiled windows are pulled out of their app groups.
    var filteredMonitorGroups: [MonitorWindowGroup] {
        let monitorGroups = windowListViewModel.monitorGroups
        let tiledIDs = tiledWindowIDs

        // Filter out tiled windows from app groups
        let filtered = monitorGroups.map { monitorGroup -> MonitorWindowGroup in
            let filteredAppGroups = monitorGroup.windowGroups.compactMap { group -> WindowAppGroup? in
                let untimedWindows = group.windows.filter { !tiledIDs.contains($0.id) }
                guard !untimedWindows.isEmpty else { return nil }
                return WindowAppGroup(
                    id: group.id,
                    appName: group.appName,
                    bundleIdentifier: group.bundleIdentifier,
                    windows: untimedWindows
                )
            }
            return MonitorWindowGroup(monitor: monitorGroup.monitor, windowGroups: filteredAppGroups)
        }

        guard isSearching else { return filtered }

        return filtered.compactMap { monitorGroup -> MonitorWindowGroup? in
            let searchedGroups = monitorGroup.windowGroups.compactMap { group -> WindowAppGroup? in
                let matchingWindows = group.windows.filter { window in
                    window.title.lowercased().contains(searchQuery) ||
                    window.ownerName.lowercased().contains(searchQuery)
                }

                if group.appName.lowercased().contains(searchQuery) {
                    return group
                }

                guard !matchingWindows.isEmpty else { return nil }
                return WindowAppGroup(
                    id: group.id,
                    appName: group.appName,
                    bundleIdentifier: group.bundleIdentifier,
                    windows: matchingWindows
                )
            }

            guard !searchedGroups.isEmpty else { return nil }
            return MonitorWindowGroup(monitor: monitorGroup.monitor, windowGroups: searchedGroups)
        }
    }

    /// Clear search text
    func clearSearch() {
        searchText = ""
        // Reset all focus state when clearing search
        focusState = .initial
        // Preserve active tab selection
        if let idx = PaletteTab.allCases.firstIndex(of: activeTab) {
            focusState.tabsIndex = idx
        }
    }

    /// Check if search has results
    var hasSearchResults: Bool {
        !filteredPinnedItems.isEmpty || !searchableContentResults.isEmpty
    }

    // MARK: - Keyboard Navigation

    /// All windows flattened across filtered monitor groups for sequential navigation
    var flattenedWindows: [WindowInfo] {
        filteredMonitorGroups.flatMap { monitorGroup in
            monitorGroup.windowGroups.flatMap { $0.windows }
        }
    }

    private enum SearchContentResult {
        case window(WindowInfo)
        case note(Note)
    }

    /// Ordered content results used by keyboard navigation while searching.
    /// Windows are listed first to preserve existing behavior, followed by notes.
    private var searchableContentResults: [SearchContentResult] {
        var results: [SearchContentResult] = flattenedWindows.map { .window($0) }
        if isSearching {
            results.append(contentsOf: noteSearchResults.map { .note($0.note) })
        }
        return results
    }

    private func activateSearchContentResult(_ result: SearchContentResult) {
        switch result {
        case .window(let window):
            focusWindow(window)
        case .note(let note):
            openNote(note)
        }
    }

    /// Total count of navigable pinned items (apps + folders)
    var totalAppsCount: Int {
        filteredPinnedItems.count
    }

    /// Number of tabs
    var tabsCount: Int {
        PaletteTab.allCases.count
    }

    func resetFocus() {
        focusState = .initial
        // Sync tabsIndex with activeTab
        if let idx = PaletteTab.allCases.firstIndex(of: activeTab) {
            focusState.tabsIndex = idx
        }
    }

    /// Handle Escape key - returns true if handled (folder closed or search cleared), false if should dismiss
    func handleEscape() -> Bool {
        // First: close folder popup if open
        if expandedFolderID != nil {
            expandedFolderID = nil
            focusedFolderAppIndex = nil
            return true
        }
        // Second: clear search if active
        if isSearching {
            clearSearch()
            return true
        }
        return false  // Nothing to clear, should dismiss
    }

    // MARK: - Folder Popup Navigation

    /// Apps in the currently expanded folder
    private var expandedFolderApps: [AppInfo] {
        guard let id = expandedFolderID,
              let folder = folders.first(where: { $0.id == id }) else { return [] }
        return folder.apps
    }

    func moveFolderFocusLeft() {
        guard let index = focusedFolderAppIndex else {
            focusedFolderAppIndex = 0
            return
        }
        if index > 0 {
            focusedFolderAppIndex = index - 1
        }
    }

    func moveFolderFocusRight() {
        guard let index = focusedFolderAppIndex else {
            focusedFolderAppIndex = 0
            return
        }
        let maxIndex = expandedFolderApps.count - 1
        if maxIndex >= 0 && index < maxIndex {
            focusedFolderAppIndex = index + 1
        }
    }

    func activateFocusedFolderApp() {
        let apps = expandedFolderApps
        // If no keyboard focus yet, activate first app
        let index = focusedFolderAppIndex ?? 0
        guard index < apps.count else { return }
        launchApp(apps[index])
    }

    // MARK: - Arrow Key Navigation (fine movement)

    func moveFocusDown() {
        switch focusState.section {
        case .search:
            // Search → Apps (if any) or Tabs or Content
            if totalAppsCount > 0 {
                focusState.section = .apps
                focusState.appsIndex = 0
            } else if !searchableContentResults.isEmpty {
                // Skip tabs when searching - go directly to results
                focusState.section = .content
                focusState.contentIndex = 0
            } else {
                focusState.section = .tabs
            }
        case .apps:
            // Apps → Tabs or Content (skip tabs when searching with results)
            if isSearching && !searchableContentResults.isEmpty {
                focusState.section = .content
                focusState.contentIndex = 0
            } else {
                focusState.section = .tabs
            }
        case .tabs:
            // Tabs → Content (first item)
            if !searchableContentResults.isEmpty {
                focusState.section = .content
                focusState.contentIndex = 0
            }
        case .content:
            // Move down within window list
            let maxIndex = searchableContentResults.count - 1
            if maxIndex >= 0 && focusState.contentIndex < maxIndex {
                focusState.contentIndex += 1
            }
        }
    }

    func moveFocusUp() {
        switch focusState.section {
        case .search:
            // Already at top
            break
        case .apps:
            // Apps → Search
            focusState.section = .search
        case .tabs:
            // Tabs → Apps (if any) or Search
            if totalAppsCount > 0 {
                focusState.section = .apps
                focusState.appsIndex = min(focusState.appsIndex, max(0, totalAppsCount - 1))
            } else {
                focusState.section = .search
            }
        case .content:
            // Move up within window list, or go to Apps/Tabs/Search
            if focusState.contentIndex > 0 {
                focusState.contentIndex -= 1
            } else if isSearching && totalAppsCount > 0 {
                // When searching, go back to apps (skip tabs)
                focusState.section = .apps
                focusState.appsIndex = min(focusState.appsIndex, max(0, totalAppsCount - 1))
            } else if totalAppsCount > 0 {
                focusState.section = .apps
                focusState.appsIndex = min(focusState.appsIndex, max(0, totalAppsCount - 1))
            } else if !isSearching {
                focusState.section = .tabs
            } else {
                focusState.section = .search
            }
        }
    }

    func moveFocusLeft() {
        switch focusState.section {
        case .search:
            break
        case .apps:
            if focusState.appsIndex > 0 {
                focusState.appsIndex -= 1
            }
        case .tabs:
            if focusState.tabsIndex > 0 {
                focusState.tabsIndex -= 1
                // Sync activeTab with focus
                activeTab = PaletteTab.allCases[focusState.tabsIndex]
            }
        case .content:
            break
        }
    }

    func moveFocusRight() {
        switch focusState.section {
        case .search:
            break
        case .apps:
            let maxIndex = totalAppsCount - 1
            if maxIndex >= 0 && focusState.appsIndex < maxIndex {
                focusState.appsIndex += 1
            }
        case .tabs:
            let maxIndex = tabsCount - 1
            if focusState.tabsIndex < maxIndex {
                focusState.tabsIndex += 1
                // Sync activeTab with focus
                activeTab = PaletteTab.allCases[focusState.tabsIndex]
            }
        case .content:
            break
        }
    }

    // MARK: - Tab Key Navigation (jump between groups)

    func cycleSection(forward: Bool) {
        // When searching, only cycle between sections that have content
        let availableSections: [PaletteSection]
        if isSearching {
            var sections: [PaletteSection] = [.search]
            if totalAppsCount > 0 { sections.append(.apps) }
            if !searchableContentResults.isEmpty { sections.append(.content) }
            availableSections = sections
        } else {
            availableSections = PaletteSection.allCases
        }

        guard availableSections.count > 1,
              let currentIndex = availableSections.firstIndex(of: focusState.section) else {
            return
        }

        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % availableSections.count
        } else {
            nextIndex = (currentIndex - 1 + availableSections.count) % availableSections.count
        }

        focusState.section = availableSections[nextIndex]

        // Clamp indices for new section
        switch focusState.section {
        case .search:
            break
        case .apps:
            focusState.appsIndex = min(focusState.appsIndex, max(0, totalAppsCount - 1))
        case .tabs:
            focusState.tabsIndex = min(focusState.tabsIndex, max(0, tabsCount - 1))
        case .content:
            focusState.contentIndex = min(focusState.contentIndex, max(0, searchableContentResults.count - 1))
        }
    }

    // MARK: - Activation

    func activateFocusedItem() {
        switch focusState.section {
        case .search:
            // If searching and there are results, activate first result
            if isSearching && hasSearchResults {
                if let firstItem = filteredPinnedItems.first {
                    if case .app(let app) = firstItem { launchApp(app) }
                } else if let firstResult = searchableContentResults.first {
                    activateSearchContentResult(firstResult)
                }
            }
        case .apps:
            // Launch the focused app or open folder (use filtered data)
            let items = filteredPinnedItems
            if focusState.appsIndex < items.count {
                switch items[focusState.appsIndex] {
                case .app(let app): launchApp(app)
                case .folder(let folder): toggleFolder(folder)
                }
            }
        case .tabs:
            // Tab is already selected via left/right, Enter could confirm or do nothing
            // The tab is already active, so this is a no-op
            break
        case .content:
            // Activate the selected search result (window or note).
            if focusState.contentIndex < searchableContentResults.count {
                activateSearchContentResult(searchableContentResults[focusState.contentIndex])
            }
        }
    }

    // MARK: - Cap Enforcement

    static let maxPinnedItems = 10
    private let foldersStorageKey = "AppFolders"
    private let itemOrderStorageKey = "PinnedItemOrder"

    /// Total top-level items (pinned apps + folders)
    var totalPinnedItemCount: Int {
        pinnedApps.count + folders.count
    }

    /// Whether more items can be added to the palette row
    var canAddMoreItems: Bool {
        totalPinnedItemCount < Self.maxPinnedItems
    }

    /// Unified ordered list of pinned items (apps + folders) for display
    var pinnedItems: [PinnedItem] {
        let order = loadItemOrder()
        var result: [PinnedItem] = []
        var usedAppIDs = Set<UUID>()
        var usedFolderIDs = Set<UUID>()

        // First, add items in stored order
        for id in order {
            if let app = pinnedApps.first(where: { $0.id == id }) {
                result.append(.app(app))
                usedAppIDs.insert(id)
            } else if let folder = folders.first(where: { $0.id == id }) {
                result.append(.folder(folder))
                usedFolderIDs.insert(id)
            }
        }

        // Then append any items not in the order (newly added)
        for app in pinnedApps where !usedAppIDs.contains(app.id) {
            result.append(.app(app))
        }
        for folder in folders where !usedFolderIDs.contains(folder.id) {
            result.append(.folder(folder))
        }

        return result
    }

    /// Filtered pinned items for search — also surfaces matching apps from inside folders
    var filteredPinnedItems: [PinnedItem] {
        guard isSearching else { return pinnedItems }
        var results: [PinnedItem] = []
        for item in pinnedItems {
            switch item {
            case .app(let app):
                if app.name.lowercased().contains(searchQuery) {
                    results.append(item)
                }
            case .folder(let folder):
                if folder.name.lowercased().contains(searchQuery) {
                    // Folder name matches — show the whole folder
                    results.append(item)
                } else {
                    // Show individual matching apps from inside the folder
                    for app in folder.apps where app.name.lowercased().contains(searchQuery) {
                        results.append(.app(app))
                    }
                }
            }
        }
        return results
    }

    /// Reorder all pinned items (apps + folders mixed)
    func reorderPinnedItems(_ newOrder: [PinnedItem]) {
        // Extract apps and folders in new order
        let newApps = newOrder.compactMap { $0.appInfo }
        let newFolders = newOrder.compactMap { $0.appFolder }

        // Persist app order
        pinnedAppsViewModel.reorder(newApps)
        // Persist folder order
        if newFolders.map(\.id) != folders.map(\.id) {
            folders = newFolders
            saveFolders()
        }
        // Persist unified order
        saveItemOrder(newOrder.map { $0.id })
    }

    private func loadItemOrder() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: itemOrderStorageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([UUID].self, from: data)
        } catch {
            NSLog("[Cider] Failed to decode item order: \(error)")
            return []
        }
    }

    private func saveItemOrder(_ ids: [UUID]) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: itemOrderStorageKey)
        }
    }

    /// Save current item order after mutations
    private func persistCurrentOrder() {
        saveItemOrder(pinnedItems.map { $0.id })
    }

    /// Remove an app from a folder and move it back to pinned (if room) or remove from Cider
    func removeAppFromFolderToPinned(app: AppInfo, folder: AppFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].apps.removeAll { $0.id == app.id }
        // Add back to pinned if under cap
        if canAddMoreItems {
            pinnedAppsViewModel.addExistingApp(app)
        }
        // Dissolve folder if <= 1 app
        if folders[idx].apps.count <= 1 {
            let remaining = folders[idx].apps
            folders.remove(at: idx)
            for remainingApp in remaining where canAddMoreItems {
                pinnedAppsViewModel.addExistingApp(remainingApp)
            }
        }
        saveFolders()
        persistCurrentOrder()
    }

    /// Remove an app from a folder and from Cider entirely
    func removeAppFromFolderAndCider(app: AppInfo, folder: AppFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].apps.removeAll { $0.id == app.id }
        // Dissolve folder if <= 1 app
        if folders[idx].apps.count <= 1 {
            let remaining = folders[idx].apps
            folders.remove(at: idx)
            for remainingApp in remaining where canAddMoreItems {
                pinnedAppsViewModel.addExistingApp(remainingApp)
            }
        }
        saveFolders()
        persistCurrentOrder()
    }

    /// Move an app from one folder to another
    func moveAppBetweenFolders(app: AppInfo, from sourceFolder: AppFolder, to destFolder: AppFolder) {
        guard let srcIdx = folders.firstIndex(where: { $0.id == sourceFolder.id }),
              let dstIdx = folders.firstIndex(where: { $0.id == destFolder.id }) else { return }
        guard !folders[dstIdx].apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        folders[srcIdx].apps.removeAll { $0.id == app.id }
        folders[dstIdx].apps.append(app)
        // Dissolve source folder if <= 1 app
        if folders[srcIdx].apps.count <= 1 {
            let remaining = folders[srcIdx].apps
            folders.remove(at: srcIdx)
            for remainingApp in remaining where canAddMoreItems {
                pinnedAppsViewModel.addExistingApp(remainingApp)
            }
        }
        saveFolders()
        persistCurrentOrder()
    }

    // MARK: - Folders

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: foldersStorageKey) else {
            folders = []
            return
        }
        do {
            folders = try JSONDecoder().decode([AppFolder].self, from: data)
        } catch {
            NSLog("[Cider] Failed to decode folders: \(error)")
            folders = []
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: foldersStorageKey)
        }
    }

    /// Create a folder by dropping one app onto another in the palette
    func createFolderFromDrop(app1: AppInfo, app2: AppInfo) {
        // Remember position of app2 in the order
        let currentOrder = pinnedItems.map { $0.id }
        let insertIndex = currentOrder.firstIndex(of: app2.id)

        // Remove both apps from pinned list
        pinnedAppsViewModel.removeApps([app1, app2])
        // Create folder with both apps
        let folder = AppFolder(name: "Folder", apps: [app1, app2])
        folders.append(folder)
        saveFolders()

        // Insert folder at the position where app2 was
        var newOrder = currentOrder.filter { $0 != app1.id && $0 != app2.id }
        if let idx = insertIndex {
            // Find where to insert relative to the filtered order
            let clampedIdx = min(idx, newOrder.count)
            newOrder.insert(folder.id, at: clampedIdx)
        } else {
            newOrder.append(folder.id)
        }
        saveItemOrder(newOrder)
    }

    /// Add a pinned app to an existing folder (drag app onto folder)
    func addAppToFolder(app: AppInfo, folder: AppFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        // Don't add duplicates
        guard !folders[idx].apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        // Remove from pinned list
        pinnedAppsViewModel.remove(app)
        folders[idx].apps.append(app)
        saveFolders()
        persistCurrentOrder()
    }

    /// Add an app to a folder via file picker (from inside folder popup)
    func addAppToFolderFromURL(_ url: URL, folder: AppFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        guard let info = appInfoFromURL(url) else { return }
        // Don't add duplicates
        guard !folders[idx].apps.contains(where: { $0.bundleIdentifier == info.bundleIdentifier }) else { return }
        folders[idx].apps.append(info)
        saveFolders()
    }

    /// Remove an app from a folder
    func removeAppFromFolder(app: AppInfo, folder: AppFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].apps.removeAll { $0.id == app.id }
        // If folder has 0 or 1 apps left, dissolve it
        if folders[idx].apps.count <= 1 {
            let remaining = folders[idx].apps
            folders.remove(at: idx)
            for app in remaining where canAddMoreItems {
                pinnedAppsViewModel.addExistingApp(app)
            }
        }
        saveFolders()
        persistCurrentOrder()
    }

    /// Delete a folder, moving its apps back to pinned list if under cap
    func deleteFolder(_ folder: AppFolder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        let appsToRestore = folders[idx].apps
        folders.remove(at: idx)
        saveFolders()
        for app in appsToRestore where canAddMoreItems {
            pinnedAppsViewModel.addExistingApp(app)
        }
        persistCurrentOrder()
    }

    /// Rename a folder
    func renameFolder(_ folder: AppFolder, to newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].name = newName
        saveFolders()
    }

    /// Add a new pinned app (checks cap)
    func addPinnedApp(from url: URL) {
        guard canAddMoreItems else { return }
        pinnedAppsViewModel.addApp(from: url)
    }

    /// Helper to create AppInfo from a URL
    private func appInfoFromURL(_ url: URL) -> AppInfo? {
        let path = url.path
        guard path.hasSuffix(".app") else { return nil }
        guard let bundle = Bundle(path: path) else { return nil }
        let bundleId = bundle.bundleIdentifier ?? ""
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(name: name, bundleIdentifier: bundleId, path: path)
    }
}

// MARK: - App Folder Model

struct AppFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apps: [AppInfo]

    init(id: UUID = UUID(), name: String, apps: [AppInfo]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

// MARK: - Pinned Item (unified app/folder for ordering)

enum PinnedItem: Identifiable {
    case app(AppInfo)
    case folder(AppFolder)

    var id: UUID {
        switch self {
        case .app(let app): return app.id
        case .folder(let folder): return folder.id
        }
    }

    var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var appInfo: AppInfo? {
        if case .app(let app) = self { return app }
        return nil
    }

    var appFolder: AppFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

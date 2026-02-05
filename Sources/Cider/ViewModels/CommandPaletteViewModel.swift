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

    private let windowListViewModel: WindowListViewModel
    private let pinnedAppsViewModel: PinnedAppsViewModel
    private let appLauncher = AppLauncher()
    private var cancellables = Set<AnyCancellable>()

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

        // Sync monitors
        windowListViewModel.$monitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] monitors in
                self?.monitors = monitors
            }
            .store(in: &cancellables)

        // Load folders from config (placeholder for now)
        loadFolders()
    }

    // MARK: - App Actions

    func launchApp(_ app: AppInfo) {
        appLauncher.launchOrFocus(app)
        dismiss()
    }

    func isRunning(_ app: AppInfo) -> Bool {
        pinnedAppsViewModel.isRunning(app)
    }

    func quitApp(_ app: AppInfo) {
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first {
            runningApp.terminate()
        }
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

    // MARK: - Folder Actions

    func toggleFolder(_ folder: AppFolder) {
        // Handled in the view for now
    }

    // MARK: - Navigation

    func dismiss() {
        isVisible = false
        NotificationCenter.default.post(name: .dismissCommandPalette, object: nil)
    }

    func openSettings() {
        NotificationCenter.default.post(name: .openCiderSettings, object: nil)
    }

    func show() {
        isVisible = true
        // Clear any previous search
        searchText = ""
        // Refresh data when shown
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

    /// Filtered pinned apps based on search text
    var filteredApps: [AppInfo] {
        guard isSearching else { return pinnedApps }
        return pinnedApps.filter { app in
            app.name.lowercased().contains(searchQuery)
        }
    }

    /// Filtered folders based on search text
    var filteredFolders: [AppFolder] {
        guard isSearching else { return folders }
        return folders.filter { folder in
            folder.name.lowercased().contains(searchQuery)
        }
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

    /// Clear search text
    func clearSearch() {
        searchText = ""
        // Reset focus to search when clearing
        focusState.section = .search
    }

    /// Check if search has results
    var hasSearchResults: Bool {
        !filteredApps.isEmpty || !filteredFolders.isEmpty || !filteredWindowGroups.isEmpty
    }

    // MARK: - Keyboard Navigation

    /// All windows flattened across filtered groups for sequential navigation
    var flattenedWindows: [WindowInfo] {
        filteredWindowGroups.flatMap { $0.windows }
    }

    /// Total count of navigable apps (filtered pinned apps + filtered folders)
    var totalAppsCount: Int {
        filteredApps.count + filteredFolders.count
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

    /// Handle Escape key - returns true if search was cleared, false if should dismiss
    func handleEscape() -> Bool {
        if isSearching {
            clearSearch()
            return true  // Search was cleared, don't dismiss
        }
        return false  // No search to clear, should dismiss
    }

    // MARK: - Arrow Key Navigation (fine movement)

    func moveFocusDown() {
        switch focusState.section {
        case .search:
            // Search → Apps (if any) or Tabs or Content
            if totalAppsCount > 0 {
                focusState.section = .apps
                focusState.appsIndex = 0
            } else if !flattenedWindows.isEmpty {
                // Skip tabs when searching - go directly to results
                focusState.section = .content
                focusState.contentIndex = 0
            } else {
                focusState.section = .tabs
            }
        case .apps:
            // Apps → Tabs or Content (skip tabs when searching with results)
            if isSearching && !flattenedWindows.isEmpty {
                focusState.section = .content
                focusState.contentIndex = 0
            } else {
                focusState.section = .tabs
            }
        case .tabs:
            // Tabs → Content (first item)
            if !flattenedWindows.isEmpty {
                focusState.section = .content
                focusState.contentIndex = 0
            }
        case .content:
            // Move down within window list
            let maxIndex = flattenedWindows.count - 1
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
            if !flattenedWindows.isEmpty { sections.append(.content) }
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
            focusState.contentIndex = min(focusState.contentIndex, max(0, flattenedWindows.count - 1))
        }
    }

    // MARK: - Activation

    func activateFocusedItem() {
        switch focusState.section {
        case .search:
            // If searching and there are results, activate first result
            if isSearching && hasSearchResults {
                if !filteredApps.isEmpty {
                    launchApp(filteredApps[0])
                } else if !flattenedWindows.isEmpty {
                    focusWindow(flattenedWindows[0])
                }
            }
        case .apps:
            // Launch the focused app or open folder (use filtered data)
            if focusState.appsIndex < filteredApps.count {
                launchApp(filteredApps[focusState.appsIndex])
            } else {
                let folderIndex = focusState.appsIndex - filteredApps.count
                if folderIndex < filteredFolders.count {
                    toggleFolder(filteredFolders[folderIndex])
                }
            }
        case .tabs:
            // Tab is already selected via left/right, Enter could confirm or do nothing
            // The tab is already active, so this is a no-op
            break
        case .content:
            // Focus the selected window (use filtered data)
            if focusState.contentIndex < flattenedWindows.count {
                focusWindow(flattenedWindows[focusState.contentIndex])
            }
        }
    }

    // MARK: - Folders

    private func loadFolders() {
        // TODO: Load folders from persistent storage
        // For now, empty - user will create folders through UI
        folders = []
    }

    func createFolder(name: String, apps: [AppInfo]) {
        let folder = AppFolder(id: UUID(), name: name, apps: apps)
        folders.append(folder)
        saveFolders()
    }

    private func saveFolders() {
        // TODO: Persist folders to storage
    }
}

// MARK: - App Folder Model

struct AppFolder: Identifiable {
    let id: UUID
    var name: String
    var apps: [AppInfo]
}

// MARK: - Notifications

extension Notification.Name {
    static let dismissCommandPalette = Notification.Name("dismissCommandPalette")
    static let toggleCommandPalette = Notification.Name("toggleCommandPalette")
    static let openCiderSettings = Notification.Name("openCiderSettings")
}

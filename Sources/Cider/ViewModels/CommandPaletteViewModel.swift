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
        // Refresh data when shown
        windowListViewModel.refresh()
        // Reset focus to search
        resetFocus()
    }

    // MARK: - Keyboard Navigation

    /// All windows flattened across groups for sequential navigation
    var flattenedWindows: [WindowInfo] {
        windowGroups.flatMap { $0.windows }
    }

    /// Total count of navigable apps (pinned apps + folders)
    var totalAppsCount: Int {
        pinnedApps.count + folders.count
    }

    func resetFocus() {
        focusState = .initial
    }

    func moveFocusDown() {
        switch focusState.section {
        case .search:
            // From search, jump directly to first window in content
            if !flattenedWindows.isEmpty {
                focusState.section = .content
                focusState.contentIndex = 0
            } else if totalAppsCount > 0 {
                // Fallback to apps if no windows
                focusState.section = .apps
                focusState.appsIndex = 0
            }
        case .apps:
            // From apps, move to content
            if !flattenedWindows.isEmpty {
                focusState.section = .content
                focusState.contentIndex = 0
            }
        case .content:
            // Move down in window list
            let maxIndex = flattenedWindows.count - 1
            if focusState.contentIndex < maxIndex {
                focusState.contentIndex += 1
            }
        }
    }

    func moveFocusUp() {
        switch focusState.section {
        case .search:
            // Already at top, do nothing
            break
        case .apps:
            // From apps, go back to search
            focusState.section = .search
        case .content:
            // Move up in window list, or go to apps/search
            if focusState.contentIndex > 0 {
                focusState.contentIndex -= 1
            } else if totalAppsCount > 0 {
                // Go to apps section
                focusState.section = .apps
            } else {
                // Go to search
                focusState.section = .search
            }
        }
    }

    func moveFocusLeft() {
        guard focusState.section == .apps else { return }
        if focusState.appsIndex > 0 {
            focusState.appsIndex -= 1
        }
    }

    func moveFocusRight() {
        guard focusState.section == .apps else { return }
        let maxIndex = totalAppsCount - 1
        if focusState.appsIndex < maxIndex {
            focusState.appsIndex += 1
        }
    }

    func cycleSection(forward: Bool) {
        let sections = PaletteSection.allCases
        guard let currentIndex = sections.firstIndex(of: focusState.section) else { return }

        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % sections.count
        } else {
            nextIndex = (currentIndex - 1 + sections.count) % sections.count
        }

        focusState.section = sections[nextIndex]

        // Reset index for the new section
        switch focusState.section {
        case .search:
            break
        case .apps:
            focusState.appsIndex = min(focusState.appsIndex, max(0, totalAppsCount - 1))
        case .content:
            focusState.contentIndex = min(focusState.contentIndex, max(0, flattenedWindows.count - 1))
        }
    }

    func activateFocusedItem() {
        switch focusState.section {
        case .search:
            // Nothing to activate in search
            break
        case .apps:
            // Activate the focused app or folder
            if focusState.appsIndex < pinnedApps.count {
                launchApp(pinnedApps[focusState.appsIndex])
            } else {
                let folderIndex = focusState.appsIndex - pinnedApps.count
                if folderIndex < folders.count {
                    toggleFolder(folders[folderIndex])
                }
            }
        case .content:
            // Focus the selected window
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

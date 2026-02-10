import SwiftUI
import AppKit

enum PaletteTab: String, CaseIterable {
    case windows = "Windows"
    case notes = "Notes"
    case bookmarks = "Bookmarks"

    var icon: String {
        switch self {
        case .windows: return "macwindow.on.rectangle"
        case .notes: return "note.text"
        case .bookmarks: return "bookmark"
        }
    }
}

struct PaletteContentArea: View {
    let activeTab: PaletteTab
    let monitorGroups: [MonitorWindowGroup]
    let monitors: [MonitorInfo]
    var searchText: String = ""
    var isSearching: Bool = false
    let focusedTabIndex: Int?
    let focusedContentIndex: Int?
    let onWindowClick: (WindowInfo) -> Void
    let onCloseWindow: (WindowInfo) -> Void
    let onMinimizeWindow: (WindowInfo) -> Void
    let onQuitApp: (WindowInfo) -> Void
    let onMoveWindow: (WindowInfo, MonitorInfo) -> Void
    let onMoveWindowByID: (CGWindowID, MonitorInfo) -> Void
    let onTileWindow: (WindowInfo, TilePosition) -> Void
    var onDragStarted: ((CGWindowID?) -> Void)? = nil
    let onTabChange: (PaletteTab) -> Void
    var isDragging: Bool = false  // Tracks whether a drag is in progress (from ViewModel)
    // Tile group support
    var tileGroupDisplaysForScreen: ((UInt32) -> [TileGroupDisplay])? = nil
    var savedLayoutsForScreen: ((Int) -> [SavedTileLayout])? = nil
    var filteredSavedLayouts: [SavedTileLayout] = []
    // Notes
    var notes: [Note] = []
    var onNoteClick: ((Note) -> Void)? = nil
    var onNewNote: (() -> Void)? = nil
    var onDeleteNotes: (([Note]) -> Void)? = nil
    var onFocusTileGroup: ((TileGroupDisplay) -> Void)? = nil
    var onPinTileGroup: ((UUID) -> Void)? = nil
    var onBreakApartTileGroup: ((UUID) -> Void)? = nil
    var onRestoreLayout: ((SavedTileLayout) -> Void)? = nil
    var onDeleteLayout: ((SavedTileLayout) -> Void)? = nil
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shared drag state across monitor sections
    @State private var draggedWindow: WindowInfo?  // For phantom insertion (single window drag only)
    @State private var allDraggedIDs: Set<CGWindowID> = []  // All dragged window IDs (single or group)

    /// Collapse state for sections
    @State private var collapsedMonitorIDs: Set<UInt32> = []
    @State private var collapsedAppGroupIDs: Set<String> = []
    @State private var isNoteSelectionMode = false
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var showDeleteNotesConfirmation = false

    /// Flattened window groups for single-monitor or search view
    private var flatWindowGroups: [WindowAppGroup] {
        monitorGroups.flatMap { $0.windowGroups }
    }

    /// Whether to show multi-monitor view
    private var showMultiMonitorView: Bool {
        monitors.count > 1 && !isSearching
    }

    private var hasMatchingWindowResults: Bool {
        let allWindows = monitorGroups.flatMap { $0.windowGroups.flatMap { $0.windows } }
        let hasTileContent = monitors.contains(where: { !(tileGroupDisplaysForScreen?($0.id) ?? []).isEmpty })
        let hasSavedContent = !filteredSavedLayouts.isEmpty
        return !allWindows.isEmpty || hasTileContent || hasSavedContent
    }

    private var windowResultCount: Int {
        monitorGroups.flatMap { $0.windowGroups.flatMap { $0.windows } }.count
    }

    private func searchResultIndex(for note: Note) -> Int? {
        guard let noteIndex = notes.firstIndex(where: { $0.id == note.id }) else { return nil }
        return windowResultCount + noteIndex
    }

    private var selectedNotes: [Note] {
        notes.filter { selectedNoteIDs.contains($0.id) }
    }

    private var allVisibleNotesSelected: Bool {
        !notes.isEmpty && notes.allSatisfy { selectedNoteIDs.contains($0.id) }
    }

    /// Calculate the flat index for a window across all monitor groups
    private func flatIndex(for window: WindowInfo) -> Int? {
        var index = 0
        for monitorGroup in monitorGroups {
            for group in monitorGroup.windowGroups {
                for w in group.windows {
                    if w.id == window.id {
                        return index
                    }
                    index += 1
                }
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Tab bar - hide when searching
            if !isSearching {
                HStack(spacing: Spacing.md) {
                    ForEach(Array(PaletteTab.allCases.enumerated()), id: \.element) { index, tab in
                        TabButton(
                            tab: tab,
                            isActive: activeTab == tab,
                            isKeyboardFocused: focusedTabIndex == index,
                            onTap: { onTabChange(tab) }
                        )
                    }
                    Spacer()
                }
            }

            // Content
            ScrollView(showsIndicators: false) {
                if isSearching {
                    // Search is global across result types.
                    searchResultsContent
                } else {
                    switch activeTab {
                    case .windows:
                        windowsContent
                    case .notes:
                        notesContent
                    case .bookmarks:
                        comingSoonContent("Bookmarks")
                    }
                }
            }
        }
        .onChange(of: isDragging) { _, newValue in
            if !newValue {
                draggedWindow = nil
                allDraggedIDs = []
            }
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab != .notes {
                exitNoteSelectionMode()
            }
        }
        .onChange(of: notes.map(\.id)) { _, noteIDs in
            let visibleIDs = Set(noteIDs)
            selectedNoteIDs = selectedNoteIDs.intersection(visibleIDs)
            if visibleIDs.isEmpty {
                exitNoteSelectionMode()
            }
        }
        .alert(
            "Delete \(selectedNoteIDs.count) note\(selectedNoteIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteNotesConfirmation
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedNotes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        let hasNoteResults = !notes.isEmpty

        if !hasMatchingWindowResults && !hasNoteResults {
            emptyState("No matching results", icon: "magnifyingglass")
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                if hasMatchingWindowResults {
                    searchSectionHeader(title: "Windows", icon: "macwindow")
                    windowsContent
                }

                if hasNoteResults {
                    if hasMatchingWindowResults {
                        Divider()
                            .padding(.horizontal, Spacing.sm)
                            .opacity(0.3)
                    }

                    searchSectionHeader(title: "Notes", icon: "note.text")
                    searchNotesContent
                }
            }
        }
    }

    @ViewBuilder
    private var searchNotesContent: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(notes) { note in
                let noteFlatIndex = searchResultIndex(for: note)
                PaletteNoteRow(
                    note: note,
                    searchText: searchText,
                    isKeyboardFocused: focusedContentIndex != nil && noteFlatIndex == focusedContentIndex,
                    onTap: { onNoteClick?(note) }
                )
            }
        }
    }

    @ViewBuilder
    private func searchSectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10 * textScale, weight: .semibold))
                .foregroundColor(CiderColors.tertiary)

            Text(title)
                .font(.system(size: 11 * textScale, weight: .semibold))
                .foregroundColor(CiderColors.secondary)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private var windowsContent: some View {
        if !hasMatchingWindowResults {
            if isSearching {
                emptyState("No matching windows", icon: "magnifyingglass")
            } else {
                emptyState("No windows open", icon: "macwindow")
            }
        } else if showMultiMonitorView {
            // Multi-monitor view with sections
            multiMonitorContent
        } else {
            // Flat view (single monitor or searching)
            flatWindowsContent
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        if notes.isEmpty {
            VStack(spacing: Spacing.md) {
                Image(systemName: "note.text")
                    .font(.system(size: 32 * textScale))
                    .foregroundColor(CiderColors.tertiary)
                Text("No notes yet")
                    .font(.system(size: 13 * textScale))
                    .foregroundColor(CiderColors.secondary)
                Button(action: { onNewNote?() }) {
                    Text("Create your first note")
                        .font(.system(size: 12 * textScale, weight: .medium))
                        .foregroundColor(CiderColors.controlAccent)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xxl)
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    if isNoteSelectionMode {
                        Button(action: toggleSelectAllNotes) {
                            Text(allVisibleNotesSelected ? "Clear All" : "Select All")
                                .font(.system(size: 12 * textScale, weight: .medium))
                                .foregroundColor(CiderColors.controlAccent)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: exitNoteSelectionMode) {
                            Text("Done")
                                .font(.system(size: 12 * textScale, weight: .medium))
                                .foregroundColor(CiderColors.controlAccent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { onNewNote?() }) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12 * textScale))
                                    .foregroundColor(CiderColors.controlAccent)
                                Text("New Note")
                                    .font(.system(size: 12 * textScale, weight: .medium))
                                    .foregroundColor(CiderColors.controlAccent)
                            }
                            .padding(.vertical, Spacing.xs)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: enterNoteSelectionMode) {
                            Text("Select")
                                .font(.system(size: 12 * textScale, weight: .medium))
                                .foregroundColor(CiderColors.controlAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(notes) { note in
                    let isSelected = selectedNoteIDs.contains(note.id)
                    PaletteNoteRow(
                        note: note,
                        searchText: searchText,
                        isSelectionMode: isNoteSelectionMode,
                        isSelected: isSelected,
                        onTap: {
                            if isNoteSelectionMode {
                                toggleNoteSelection(note.id)
                            } else {
                                onNoteClick?(note)
                            }
                        }
                    )
                }

                if isNoteSelectionMode && !selectedNoteIDs.isEmpty {
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showDeleteNotesConfirmation = true
                        } label: {
                            Label("Delete (\(selectedNoteIDs.count))", systemImage: "trash")
                                .font(.system(size: 12 * textScale, weight: .semibold))
                                .foregroundColor(CiderColors.destructive)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(CiderColors.destructive.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private func enterNoteSelectionMode() {
        withAnimation(reduceMotion ? .none : .snappy) {
            isNoteSelectionMode = true
            selectedNoteIDs.removeAll()
        }
    }

    private func exitNoteSelectionMode() {
        withAnimation(reduceMotion ? .none : .snappy) {
            isNoteSelectionMode = false
            selectedNoteIDs.removeAll()
            showDeleteNotesConfirmation = false
        }
    }

    private func toggleSelectAllNotes() {
        withAnimation(reduceMotion ? .none : .snappy) {
            if allVisibleNotesSelected {
                selectedNoteIDs.removeAll()
            } else {
                selectedNoteIDs = Set(notes.map(\.id))
            }
        }
    }

    private func toggleNoteSelection(_ noteID: UUID) {
        withAnimation(reduceMotion ? .none : .snappy) {
            if selectedNoteIDs.contains(noteID) {
                selectedNoteIDs.remove(noteID)
            } else {
                selectedNoteIDs.insert(noteID)
            }
        }
    }

    private func deleteSelectedNotes() {
        let notesToDelete = selectedNotes
        guard !notesToDelete.isEmpty else { return }
        onDeleteNotes?(notesToDelete)
        exitNoteSelectionMode()
    }

    @ViewBuilder
    private var multiMonitorContent: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(monitorGroups) { monitorGroup in
                monitorSection(for: monitorGroup)
            }
        }
    }

    @ViewBuilder
    private func monitorSection(for monitorGroup: MonitorWindowGroup) -> some View {
        let displayID = monitorGroup.monitor.id
        let screenIndex = monitors.firstIndex(where: { $0.id == displayID }) ?? 0
        PaletteMonitorSection(
            monitorGroup: monitorGroup,
            monitors: monitors,
            searchText: searchText,
            reduceMotion: reduceMotion,
            isMonitorCollapsed: collapsedMonitorIDs.contains(displayID),
            collapsedAppGroupIDs: collapsedAppGroupIDs,
            focusedContentIndex: focusedContentIndex,
            flatIndexForWindow: flatIndex,
            appIconProvider: appIcon,
            tileGroupDisplays: tileGroupDisplaysForScreen?(displayID) ?? [],
            savedLayouts: savedLayoutsForScreen?(screenIndex) ?? [],
            draggedWindow: $draggedWindow,
            allDraggedIDs: $allDraggedIDs,
            onWindowClick: onWindowClick,
            onCloseWindow: onCloseWindow,
            onMinimizeWindow: onMinimizeWindow,
            onQuitApp: onQuitApp,
            onMoveWindow: onMoveWindow,
            onMoveWindowByID: onMoveWindowByID,
            onTileWindow: onTileWindow,
            onDragStartedCallback: onDragStarted,
            onFocusTileGroup: onFocusTileGroup,
            onPinTileGroup: onPinTileGroup,
            onBreakApartTileGroup: onBreakApartTileGroup,
            onRestoreLayout: onRestoreLayout,
            onDeleteLayout: onDeleteLayout,
            onToggleMonitor: {
                withAnimation(reduceMotion ? .none : .snappy) {
                    if collapsedMonitorIDs.contains(displayID) {
                        collapsedMonitorIDs.remove(displayID)
                    } else {
                        collapsedMonitorIDs.insert(displayID)
                    }
                }
            },
            onToggleAppGroup: { groupID in
                withAnimation(reduceMotion ? .none : .snappy) {
                    if collapsedAppGroupIDs.contains(groupID) {
                        collapsedAppGroupIDs.remove(groupID)
                    } else {
                        collapsedAppGroupIDs.insert(groupID)
                    }
                }
            }
        )
    }

    /// All tile group displays across all monitors (for flat view).
    private var allTileGroupDisplays: [TileGroupDisplay] {
        monitors.flatMap { tileGroupDisplaysForScreen?($0.id) ?? [] }
    }

    @ViewBuilder
    private var flatWindowsContent: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.md) {
            // Active tile groups
            ForEach(allTileGroupDisplays) { display in
                TileGroupRow(
                    display: display,
                    monitors: monitors,
                    searchText: searchText,
                    onFocusAll: { onFocusTileGroup?(display) },
                    onPinLayout: { onPinTileGroup?(display.groupID) },
                    onBreakApart: { onBreakApartTileGroup?(display.groupID) }
                )
            }

            // Saved layouts
            ForEach(filteredSavedLayouts) { layout in
                SavedLayoutRow(
                    layout: layout,
                    monitors: monitors,
                    searchText: searchText,
                    onRestore: { onRestoreLayout?(layout) },
                    onDelete: { onDeleteLayout?(layout) }
                )
            }

            // Regular app groups
            ForEach(flatWindowGroups) { group in
                let isAppCollapsed = !isSearching && group.windows.count >= 2 && collapsedAppGroupIDs.contains(group.id)
                let canCollapse = !isSearching && group.windows.count >= 2

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // App header with quit button
                    HStack(spacing: Spacing.sm) {
                        if canCollapse {
                            Image(systemName: isAppCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10 * textScale, weight: .semibold))
                                .foregroundColor(CiderColors.tertiary)
                                .frame(width: 10 * textScale)
                        }

                        Image(nsImage: appIcon(for: group))
                            .resizable()
                            .frame(width: 20 * textScale, height: 20 * textScale)
                        HighlightedText(group.appName, highlight: searchText)
                            .font(.system(size: 13 * textScale, weight: .medium))
                            .foregroundColor(CiderColors.primary)

                        if isAppCollapsed {
                            Text("\(group.windows.count)")
                                .font(.system(size: 11 * textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }

                        Spacer()

                        // Quit app button
                        if let firstWindow = group.windows.first {
                            Button(action: { onQuitApp(firstWindow) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14 * textScale))
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Quit \(group.appName)")
                            .accessibilityLabel("Quit \(group.appName)")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canCollapse else { return }
                        withAnimation(reduceMotion ? .none : .snappy) {
                            if collapsedAppGroupIDs.contains(group.id) {
                                collapsedAppGroupIDs.remove(group.id)
                            } else {
                                collapsedAppGroupIDs.insert(group.id)
                            }
                        }
                    }

                    // Windows (hidden when collapsed)
                    if !isAppCollapsed {
                        ForEach(group.windows) { window in
                            let windowFlatIndex = flatIndex(for: window)
                            PaletteWindowRow(
                                window: window,
                                monitors: monitors,
                                windowCount: group.windows.count,
                                searchText: searchText,
                                isKeyboardFocused: focusedContentIndex != nil && windowFlatIndex == focusedContentIndex,
                                onTap: { onWindowClick(window) },
                                onClose: { onCloseWindow(window) },
                                onMinimize: { onMinimizeWindow(window) },
                                onMoveToMonitor: { monitor in onMoveWindow(window, monitor) },
                                onTileWindow: { position in onTileWindow(window, position) },
                                onDragStarted: { windowID in onDragStarted?(windowID) }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comingSoonContent(_ feature: String) -> some View {
        emptyState("\(feature) coming soon", icon: "clock")
    }

    @ViewBuilder
    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32 * textScale))
                .foregroundColor(CiderColors.tertiary)
            Text(message)
                .font(.system(size: 13 * textScale))
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    private func appIcon(for group: WindowAppGroup) -> NSImage {
        let iconSize = NSSize(width: 20, height: 20)
        let bundleID = group.bundleIdentifier

        // 1. Ask Launch Services — but if the resolved app is embedded inside another .app
        //    (e.g., Steam Helper.app inside Steam.app/Contents/Frameworks/), prefer the parent.
        if !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let path = appURL.path
            // Check if this app lives inside another .app bundle (helper/framework process)
            if let outerAppRange = path.range(of: ".app/", options: []),
               path[outerAppRange.upperBound...].contains(".app") {
                // Embedded helper — try parent bundle ID first
                let parentID = bundleID.components(separatedBy: ".").dropLast().joined(separator: ".")
                if let parentURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parentID) {
                    let icon = NSWorkspace.shared.icon(forFile: parentURL.path)
                    icon.size = iconSize
                    return icon
                }
            }
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = iconSize
            return icon
        }

        // 2. Try parent bundle ID (e.g., com.valvesoftware.steam.helper → com.valvesoftware.steam)
        if !bundleID.isEmpty {
            let parentID = bundleID.components(separatedBy: ".").dropLast().joined(separator: ".")
            if parentID.contains("."),
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parentID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = iconSize
                return icon
            }
        }

        // 3. Try running process's bundle URL directly
        if !bundleID.isEmpty,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let bundleURL = running.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = iconSize
            return icon
        }

        // 4. Try process icon directly via PID
        if let pid = group.windows.first?.ownerPID,
           let running = NSRunningApplication(processIdentifier: pid),
           let icon = running.icon {
            icon.size = iconSize
            return icon
        }

        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let tab: PaletteTab
    let isActive: Bool
    var isKeyboardFocused: Bool = false
    let onTap: () -> Void
    @Environment(\.textScale) private var textScale

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11 * textScale))
                Text(tab.rawValue)
                    .font(.system(size: 11 * textScale, weight: isActive ? .semibold : .regular))
            }
            .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.1) : Color.clear)
            )
            .overlay(
                Group {
                    if isKeyboardFocused {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(CiderColors.controlAccent.opacity(0.8), lineWidth: 1.5)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Row

struct PaletteWindowRow: View {
    let window: WindowInfo
    let monitors: [MonitorInfo]
    let windowCount: Int  // Number of windows in parent group
    var searchText: String = ""
    var isKeyboardFocused: Bool = false
    var isDraggedItem: Bool = false  // Set by parent when this item is being dragged
    var isDragActive: Bool = false  // True when any drag is in progress (suppress hover)
    let onTap: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onMoveToMonitor: (MonitorInfo) -> Void
    var onTileWindow: ((TilePosition) -> Void)? = nil
    var onDragStarted: ((CGWindowID?) -> Void)? = nil  // Callback when drag begins (passes window ID)
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false

    private var isFocused: Bool {
        (isHovering && !isDragActive) || isKeyboardFocused
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "macwindow")
                    .font(.system(size: 11 * textScale))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 16 * textScale)

                HighlightedText(window.displayTitle, highlight: searchText)
                    .font(.system(size: 13 * textScale))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer()

                if isFocused && !isDraggedItem {
                    HStack(spacing: Spacing.xs) {
                        // Minimize button
                        Button(action: onMinimize) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14 * textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Minimize")
                        .accessibilityLabel("Minimize window")

                        // Close button - only show if app has multiple windows
                        if windowCount > 1 {
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14 * textScale))
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Close window")
                            .accessibilityLabel("Close window")
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                Group {
                    if isKeyboardFocused {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(CiderColors.controlAccent.opacity(0.6), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .opacity(isDraggedItem ? 0.0 : 1.0)
        .scaleEffect(isDraggedItem ? 0.8 : 1.0)
        .animation(reduceMotion ? .none : .smooth, value: isDraggedItem)
        .onDrag {
            onDragStarted?(window.id)
            return NSItemProvider(object: String(window.id) as NSString)
        }
        .onHover { hovering in
            // Don't show hover highlight during drag operations
            if isDragActive {
                if isHovering { isHovering = false }
                return
            }
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Focus Window") { onTap() }

            Divider()

            Button("Minimize") { onMinimize() }
            if windowCount > 1 {
                Button("Close Window") { onClose() }
            }

            if monitors.count > 1 {
                Divider()
                Menu("Move to Monitor") {
                    ForEach(monitors) { monitor in
                        Button(monitor.displayName) {
                            onMoveToMonitor(monitor)
                        }
                    }
                }
            }

            if let onTileWindow {
                Divider()
                Menu("Tile Window") {
                    ForEach(TilePosition.halves, id: \.self) { position in
                        Button(action: { onTileWindow(position) }) {
                            Label("\(position.displayName)  \(position.shortcutLabel)", systemImage: position.icon)
                        }
                    }
                    Divider()
                    ForEach(TilePosition.quarters, id: \.self) { position in
                        Button(action: { onTileWindow(position) }) {
                            Label("\(position.displayName)  \(position.shortcutLabel)", systemImage: position.icon)
                        }
                    }
                    Divider()
                    ForEach(TilePosition.thirds, id: \.self) { position in
                        Button(action: { onTileWindow(position) }) {
                            Label("\(position.displayName)  \(position.shortcutLabel)", systemImage: position.icon)
                        }
                    }
                    Divider()
                    ForEach(TilePosition.twoThirds, id: \.self) { position in
                        Button(action: { onTileWindow(position) }) {
                            Label("\(position.displayName)  \(position.shortcutLabel)", systemImage: position.icon)
                        }
                    }
                    Divider()
                    ForEach(TilePosition.other, id: \.self) { position in
                        Button(action: { onTileWindow(position) }) {
                            Label("\(position.displayName)  \(position.shortcutLabel)", systemImage: position.icon)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Note Row

struct PaletteNoteRow: View {
    let note: Note
    var searchText: String = ""
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var isKeyboardFocused: Bool = false
    let onTap: () -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var isFocused: Bool {
        isHovering || isKeyboardFocused
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Group {
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
                    } else {
                        Image(systemName: "note.text")
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                .font(.system(size: 11 * textScale))
                .frame(width: 16 * textScale)

                VStack(alignment: .leading, spacing: 1) {
                    HighlightedText(note.title, highlight: searchText)
                        .font(.system(size: 13 * textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(Self.dateFormatter.string(from: note.modifiedAt))
                        .font(.system(size: 10 * textScale))
                        .foregroundColor(CiderColors.tertiary)
                }

                Spacer()

                if !isSelectionMode && isHovering {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10 * textScale))
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(
                        isSelectionMode
                        ? (isSelected ? CiderColors.controlAccent.opacity(0.14) : Color.clear)
                        : (isFocused ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
            .overlay(
                Group {
                    if isKeyboardFocused {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(CiderColors.controlAccent.opacity(0.6), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if isSelectionMode {
                isHovering = false
                return
            }
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Monitor Section

struct PaletteMonitorSection: View {
    let monitorGroup: MonitorWindowGroup
    let monitors: [MonitorInfo]
    var searchText: String = ""
    let reduceMotion: Bool
    var isMonitorCollapsed: Bool = false
    var collapsedAppGroupIDs: Set<String> = []
    let focusedContentIndex: Int?
    let flatIndexForWindow: (WindowInfo) -> Int?
    let appIconProvider: (WindowAppGroup) -> NSImage
    var tileGroupDisplays: [TileGroupDisplay] = []
    var savedLayouts: [SavedTileLayout] = []
    @Binding var draggedWindow: WindowInfo?
    @Binding var allDraggedIDs: Set<CGWindowID>
    let onWindowClick: (WindowInfo) -> Void
    let onCloseWindow: (WindowInfo) -> Void
    let onMinimizeWindow: (WindowInfo) -> Void
    let onQuitApp: (WindowInfo) -> Void
    let onMoveWindow: (WindowInfo, MonitorInfo) -> Void
    let onMoveWindowByID: (CGWindowID, MonitorInfo) -> Void
    let onTileWindow: (WindowInfo, TilePosition) -> Void
    var onDragStartedCallback: ((CGWindowID?) -> Void)? = nil
    var onFocusTileGroup: ((TileGroupDisplay) -> Void)? = nil
    var onPinTileGroup: ((UUID) -> Void)? = nil
    var onBreakApartTileGroup: ((UUID) -> Void)? = nil
    var onRestoreLayout: ((SavedTileLayout) -> Void)? = nil
    var onDeleteLayout: ((SavedTileLayout) -> Void)? = nil
    var onToggleMonitor: (() -> Void)? = nil
    var onToggleAppGroup: ((String) -> Void)? = nil
    @Environment(\.textScale) private var textScale

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Monitor header (clickable to collapse)
            HStack(spacing: Spacing.sm) {
                Image(systemName: isMonitorCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10 * textScale, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 10 * textScale)

                Image(systemName: monitorGroup.monitor.isPrimary ? "display" : monitorGroup.monitor.relativePosition.icon)
                    .font(.system(size: 12 * textScale))
                    .foregroundColor(isDropTargeted ? CiderColors.controlAccent : CiderColors.secondary)

                Text(monitorGroup.monitor.displayName)
                    .font(.system(size: 12 * textScale, weight: .medium))
                    .foregroundColor(isDropTargeted ? CiderColors.controlAccent : CiderColors.primary)

                Text("(\(monitorGroup.windowCount))")
                    .font(.system(size: 11 * textScale))
                    .foregroundColor(CiderColors.tertiary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isDropTargeted ? CiderColors.controlAccent.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isDropTargeted ? CiderColors.controlAccent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleMonitor?()
            }

            // Window rows grouped by app (hidden when monitor is collapsed)
            if !isMonitorCollapsed {
                // Active tile groups (above app groups)
                ForEach(tileGroupDisplays) { display in
                    TileGroupRow(
                        display: display,
                        monitors: monitors,
                        searchText: searchText,
                        onFocusAll: { onFocusTileGroup?(display) },
                        onPinLayout: { onPinTileGroup?(display.groupID) },
                        onBreakApart: { onBreakApartTileGroup?(display.groupID) }
                    )
                    .padding(.leading, Spacing.sm)
                }

                // Saved layouts
                ForEach(savedLayouts) { layout in
                    SavedLayoutRow(
                        layout: layout,
                        monitors: monitors,
                        searchText: searchText,
                        onRestore: { onRestoreLayout?(layout) },
                        onDelete: { onDeleteLayout?(layout) }
                    )
                    .padding(.leading, Spacing.sm)
                }

                // Regular app groups
                ForEach(monitorGroup.windowGroups) { group in
                    let isGroupDragged = !group.windows.isEmpty && group.windows.allSatisfy { allDraggedIDs.contains($0.id) }
                    let canCollapseApp = group.windows.count >= 2
                    let isAppCollapsed = canCollapseApp && collapsedAppGroupIDs.contains(group.id)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // App group header
                        HStack(spacing: Spacing.sm) {
                            if canCollapseApp {
                                Image(systemName: isAppCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 10 * textScale, weight: .semibold))
                                    .foregroundColor(CiderColors.tertiary)
                                    .frame(width: 10 * textScale)
                            }

                            Image(nsImage: appIconProvider(group))
                                .resizable()
                                .frame(width: 18 * textScale, height: 18 * textScale)
                            Text(group.appName)
                                .font(.system(size: 12 * textScale, weight: .medium))
                                .foregroundColor(CiderColors.primary)

                            if isAppCollapsed {
                                Text("\(group.windows.count)")
                                    .font(.system(size: 11 * textScale))
                                    .foregroundColor(CiderColors.tertiary)
                            }

                            Spacer()

                            Button(action: { onQuitApp(group.windows[0]) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13 * textScale))
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Quit \(group.appName)")
                            .accessibilityLabel("Quit \(group.appName)")
                        }
                        .padding(.leading, Spacing.sm)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard canCollapseApp else { return }
                            onToggleAppGroup?(group.id)
                        }
                        .opacity(isGroupDragged ? 0.0 : 1.0)
                        .scaleEffect(isGroupDragged ? 0.8 : 1.0)
                        .animation(reduceMotion ? .none : .smooth, value: isGroupDragged)
                        .onDrag {
                            let ids = group.windows.map { String($0.id) }.joined(separator: ",")
                            allDraggedIDs = Set(group.windows.map(\.id))
                            draggedWindow = nil
                            onDragStartedCallback?(group.windows.first?.id)
                            return NSItemProvider(object: ids as NSString)
                        }

                        // Individual window rows (hidden when app group is collapsed)
                        if !isAppCollapsed {
                            ForEach(group.windows) { window in
                                let isDraggedItem = allDraggedIDs.contains(window.id)
                                let windowFlatIndex = flatIndexForWindow(window)

                                PaletteWindowRow(
                                    window: window,
                                    monitors: monitors,
                                    windowCount: group.windows.count,
                                    searchText: searchText,
                                    isKeyboardFocused: focusedContentIndex != nil && windowFlatIndex == focusedContentIndex,
                                    isDraggedItem: isDraggedItem,
                                    isDragActive: !allDraggedIDs.isEmpty,
                                    onTap: { onWindowClick(window) },
                                    onClose: { onCloseWindow(window) },
                                    onMinimize: { onMinimizeWindow(window) },
                                    onMoveToMonitor: { monitor in onMoveWindow(window, monitor) },
                                    onTileWindow: { position in onTileWindow(window, position) },
                                    onDragStarted: { windowID in
                                        draggedWindow = window
                                        allDraggedIDs = [window.id]
                                        onDragStartedCallback?(windowID)
                                    }
                                )
                                .padding(.leading, Spacing.sm)
                            }
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.text, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(reduceMotion ? .none : .smooth, value: isDropTargeted)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let idString = item as? String else { return }
            let windowIDs = idString.split(separator: ",").compactMap { CGWindowID($0) }
            guard !windowIDs.isEmpty else { return }

            DispatchQueue.main.async {
                for windowID in windowIDs {
                    onMoveWindowByID(windowID, monitorGroup.monitor)
                }
                draggedWindow = nil
                allDraggedIDs = []
            }
        }
        return true
    }
}

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
    let onTabChange: (PaletteTab) -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shared drag state across monitor sections
    @State private var draggedWindow: WindowInfo?  // For phantom insertion (single window drag only)
    @State private var allDraggedIDs: Set<CGWindowID> = []  // All dragged window IDs (single or group)

    /// Flattened window groups for single-monitor or search view
    private var flatWindowGroups: [WindowAppGroup] {
        monitorGroups.flatMap { $0.windowGroups }
    }

    /// Whether to show multi-monitor view
    private var showMultiMonitorView: Bool {
        monitors.count > 1 && !isSearching
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
            ScrollView {
                if isSearching {
                    // When searching, show filtered windows directly (no tabs)
                    windowsContent
                } else {
                    switch activeTab {
                    case .windows:
                        windowsContent
                    case .notes:
                        comingSoonContent("Notes")
                    case .bookmarks:
                        comingSoonContent("Bookmarks")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var windowsContent: some View {
        let allWindows = monitorGroups.flatMap { $0.windowGroups.flatMap { $0.windows } }

        if allWindows.isEmpty {
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
    private var multiMonitorContent: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(monitorGroups) { monitorGroup in
                PaletteMonitorSection(
                    monitorGroup: monitorGroup,
                    monitors: monitors,
                    searchText: searchText,
                    reduceMotion: reduceMotion,
                    focusedContentIndex: focusedContentIndex,
                    flatIndexForWindow: flatIndex,
                    appIconProvider: appIcon,
                    draggedWindow: $draggedWindow,
                    allDraggedIDs: $allDraggedIDs,
                    onWindowClick: onWindowClick,
                    onCloseWindow: onCloseWindow,
                    onMinimizeWindow: onMinimizeWindow,
                    onQuitApp: onQuitApp,
                    onMoveWindow: onMoveWindow,
                    onMoveWindowByID: onMoveWindowByID
                )
            }
        }
    }

    @ViewBuilder
    private var flatWindowsContent: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(flatWindowGroups) { group in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // App header with quit button
                    HStack(spacing: Spacing.sm) {
                        Image(nsImage: appIcon(for: group))
                            .resizable()
                            .frame(width: 20 * textScale, height: 20 * textScale)
                        HighlightedText(group.appName, highlight: searchText)
                            .font(.system(size: 13 * textScale, weight: .medium))
                            .foregroundColor(CiderColors.primary)

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
                        }
                    }

                    // Windows
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
                            onMoveToMonitor: { monitor in onMoveWindow(window, monitor) }
                        )
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
        if !group.bundleIdentifier.isEmpty,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: group.bundleIdentifier).first,
           let bundleURL = running.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = NSSize(width: 20, height: 20)
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
    var onDragStarted: (() -> Void)? = nil  // Callback when drag begins
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

                        // Close button - only show if app has multiple windows
                        if windowCount > 1 {
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14 * textScale))
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Close window")
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
            onDragStarted?()
            return NSItemProvider(object: String(window.id) as NSString)
        }
        .onHover { hovering in
            // Don't show hover highlight during drag operations
            if isDragActive {
                if isHovering { isHovering = false }
                return
            }
            withAnimation(.snappy) {
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
        }
    }
}

// MARK: - Monitor Section

struct PaletteMonitorSection: View {
    let monitorGroup: MonitorWindowGroup
    let monitors: [MonitorInfo]
    var searchText: String = ""
    let reduceMotion: Bool
    let focusedContentIndex: Int?
    let flatIndexForWindow: (WindowInfo) -> Int?
    let appIconProvider: (WindowAppGroup) -> NSImage
    @Binding var draggedWindow: WindowInfo?
    @Binding var allDraggedIDs: Set<CGWindowID>
    let onWindowClick: (WindowInfo) -> Void
    let onCloseWindow: (WindowInfo) -> Void
    let onMinimizeWindow: (WindowInfo) -> Void
    let onQuitApp: (WindowInfo) -> Void
    let onMoveWindow: (WindowInfo, MonitorInfo) -> Void
    let onMoveWindowByID: (CGWindowID, MonitorInfo) -> Void
    @Environment(\.textScale) private var textScale

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Monitor header
            HStack(spacing: Spacing.sm) {
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

            // Window rows grouped by app — renders directly from ViewModel data
            ForEach(monitorGroup.windowGroups) { group in
                let isGroupDragged = !group.windows.isEmpty && group.windows.allSatisfy { allDraggedIDs.contains($0.id) }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // App group header
                    HStack(spacing: Spacing.sm) {
                        Image(nsImage: appIconProvider(group))
                            .resizable()
                            .frame(width: 18 * textScale, height: 18 * textScale)
                        Text(group.appName)
                            .font(.system(size: 12 * textScale, weight: .medium))
                            .foregroundColor(CiderColors.primary)

                        Spacer()

                        Button(action: { onQuitApp(group.windows[0]) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13 * textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Quit \(group.appName)")
                    }
                    .padding(.leading, Spacing.sm)
                    .opacity(isGroupDragged ? 0.0 : 1.0)
                    .scaleEffect(isGroupDragged ? 0.8 : 1.0)
                    .animation(reduceMotion ? .none : .smooth, value: isGroupDragged)
                    .onDrag {
                        let ids = group.windows.map { String($0.id) }.joined(separator: ",")
                        allDraggedIDs = Set(group.windows.map(\.id))
                        draggedWindow = nil
                        return NSItemProvider(object: ids as NSString)
                    }

                    // Individual window rows
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
                            onDragStarted: {
                                draggedWindow = window
                                allDraggedIDs = [window.id]
                            }
                        )
                        .padding(.leading, Spacing.sm)
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

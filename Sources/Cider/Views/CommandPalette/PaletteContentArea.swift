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
    let windowGroups: [WindowAppGroup]
    let monitors: [MonitorInfo]
    let focusedTabIndex: Int?
    let focusedContentIndex: Int?
    let onWindowClick: (WindowInfo) -> Void
    let onCloseWindow: (WindowInfo) -> Void
    let onMinimizeWindow: (WindowInfo) -> Void
    let onQuitApp: (WindowInfo) -> Void
    let onMoveWindow: (WindowInfo, MonitorInfo) -> Void
    let onTabChange: (PaletteTab) -> Void
    @Environment(\.textScale) private var textScale

    /// Calculate the flat index for a window within all groups
    private func flatIndex(for window: WindowInfo, in groups: [WindowAppGroup]) -> Int? {
        var index = 0
        for group in groups {
            for w in group.windows {
                if w.id == window.id {
                    return index
                }
                index += 1
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Tab bar
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

            // Content
            ScrollView {
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

    @ViewBuilder
    private var windowsContent: some View {
        if windowGroups.isEmpty {
            emptyState("No windows open", icon: "macwindow")
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(windowGroups) { group in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // App header with quit button
                        HStack(spacing: Spacing.sm) {
                            Image(nsImage: appIcon(for: group))
                                .resizable()
                                .frame(width: 20 * textScale, height: 20 * textScale)
                            Text(group.appName)
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
                            let windowFlatIndex = flatIndex(for: window, in: windowGroups)
                            PaletteWindowRow(
                                window: window,
                                monitors: monitors,
                                windowCount: group.windows.count,
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
    var isKeyboardFocused: Bool = false
    let onTap: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onMoveToMonitor: (MonitorInfo) -> Void
    @Environment(\.textScale) private var textScale

    @State private var isHovering = false

    private var isFocused: Bool {
        isHovering || isKeyboardFocused
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "macwindow")
                    .font(.system(size: 11 * textScale))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 16 * textScale)

                Text(window.displayTitle)
                    .font(.system(size: 13 * textScale))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer()

                if isFocused {
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
        .onHover { hovering in
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

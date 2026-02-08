import SwiftUI
import AppKit

/// Row view for displaying an active tile group in the palette.
struct TileGroupRow: View {
    let display: TileGroupDisplay
    let monitors: [MonitorInfo]
    var searchText: String = ""
    var isKeyboardFocused: Bool = false
    let onFocusAll: () -> Void
    let onPinLayout: () -> Void
    let onBreakApart: () -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false

    private var isFocused: Bool {
        isHovering || isKeyboardFocused
    }

    var body: some View {
        Button(action: onFocusAll) {
            HStack(spacing: Spacing.sm) {
                // Overlapping app icons
                appIconsStack

                HighlightedText(display.displayName, highlight: searchText)
                    .font(.system(size: 13 * textScale, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer()

                if isFocused {
                    HStack(spacing: Spacing.xs) {
                        Button(action: onPinLayout) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12 * textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Pin Layout")

                        Button(action: onBreakApart) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 12 * textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Break Apart")
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
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
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Focus All") { onFocusAll() }
            Divider()
            Button("Pin Layout") { onPinLayout() }
            Button("Break Apart") { onBreakApart() }
        }
    }

    @ViewBuilder
    private var appIconsStack: some View {
        let icons = display.windows.prefix(4).map { window -> NSImage in
            appIcon(for: window)
        }
        let iconSize: CGFloat = 16 * textScale
        let overlap: CGFloat = -4 * textScale

        HStack(spacing: overlap) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .zIndex(Double(icons.count - index))
            }
        }
    }

    private func appIcon(for window: WindowInfo) -> NSImage {
        let iconSize = NSSize(width: 16, height: 16)
        let bundleID = window.bundleIdentifier

        if !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = iconSize
            return icon
        }

        if let running = NSRunningApplication(processIdentifier: window.ownerPID),
           let icon = running.icon {
            icon.size = iconSize
            return icon
        }

        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

/// Row view for displaying a saved (pinned) tile layout in the palette.
struct SavedLayoutRow: View {
    let layout: SavedTileLayout
    let monitors: [MonitorInfo]
    var searchText: String = ""
    var isKeyboardFocused: Bool = false
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false

    private var isFocused: Bool {
        isHovering || isKeyboardFocused
    }

    var body: some View {
        Button(action: onRestore) {
            HStack(spacing: Spacing.sm) {
                // Overlapping app icons from saved layout
                savedIconsStack

                HighlightedText(layout.name, highlight: searchText)
                    .font(.system(size: 13 * textScale, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Image(systemName: "pin.fill")
                    .font(.system(size: 9 * textScale))
                    .foregroundColor(CiderColors.tertiary)

                Spacer()

                if isFocused {
                    HStack(spacing: Spacing.xs) {
                        Button(action: onRestore) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12 * textScale))
                                .foregroundColor(CiderColors.controlAccent)
                        }
                        .buttonStyle(.plain)
                        .help("Restore Layout")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12 * textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Layout")
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
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
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Restore Layout") { onRestore() }
            Divider()
            if monitors.count > 1 {
                Menu("Move to Monitor") {
                    ForEach(Array(monitors.enumerated()), id: \.element.id) { index, monitor in
                        Button(monitor.displayName) {
                            SavedTileLayoutManager.shared.moveLayoutToMonitor(layout, screenIndex: index)
                        }
                    }
                }
            }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var savedIconsStack: some View {
        let apps = layout.root.apps
        let iconSize: CGFloat = 16 * textScale
        let overlap: CGFloat = -4 * textScale

        HStack(spacing: overlap) {
            ForEach(Array(apps.prefix(4).enumerated()), id: \.offset) { index, app in
                Image(nsImage: savedAppIcon(bundleID: app.bundleIdentifier, path: app.appPath))
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .zIndex(Double(apps.count - index))
            }
        }
    }

    private func savedAppIcon(bundleID: String, path: String) -> NSImage {
        let iconSize = NSSize(width: 16, height: 16)

        if !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = iconSize
            return icon
        }

        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = iconSize
            return icon
        }

        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WindowListView: View {
    @ObservedObject var viewModel: WindowListViewModel
    @ObservedObject var previewService = WindowPreviewService.shared
    @State private var autoHideApps: Bool = CiderConfig.load().autoHideApps
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !isCompact {
                HStack {
                    Text("Windows")
                        .font(.caption)
                        .foregroundColor(CiderColors.secondary)
                    Spacer()

                    // Auto-hide toggle (Stage Manager-like behavior)
                    Button(action: {
                        autoHideApps.toggle()
                        var config = CiderConfig.load()
                        config.autoHideApps = autoHideApps
                        config.save()
                    }) {
                        Image(systemName: autoHideApps ? "square.on.square.fill" : "square.on.square")
                            .font(.caption)
                            .foregroundColor(autoHideApps ? CiderColors.controlAccent : CiderColors.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(autoHideApps ? "Auto-hide: ON (click to disable)" : "Auto-hide: OFF (click to enable)")
                    .accessibilityLabel(autoHideApps ? "Disable auto-hide" : "Enable auto-hide")

                    if !previewService.hasPermission {
                        Button("Enable Previews") {
                            previewService.requestPermission()
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundColor(CiderColors.controlAccent)
                        .accessibilityLabel("Enable window previews")
                        .accessibilityHint("Opens accessibility permissions")
                    }
                }
            }

            if !viewModel.isAccessibilityTrusted && !isCompact {
                PermissionBannerView()
            }

            // Always show expanded view - panel is always full width
            expandedView
        }
        .padding(Spacing.sm)
    }

    private var compactView: some View {
        VStack(alignment: .center, spacing: Spacing.md) {
            ForEach(viewModel.groups) { group in
                Button(action: {
                    if let first = group.windows.first {
                        viewModel.focus(window: first)
                    }
                }) {
                    Image(nsImage: appIcon(for: group))
                        .resizable()
                        .frame(width: CiderDesign.compactIconSize, height: CiderDesign.compactIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if viewModel.monitors.count > 1 {
                // Multi-monitor view with sections
                ForEach(viewModel.monitorGroups) { monitorGroup in
                    MonitorSection(
                        monitorGroup: monitorGroup,
                        isExpanded: viewModel.isMonitorExpanded(monitorGroup.monitor),
                        previewService: previewService,
                        viewModel: viewModel,
                        appIconProvider: appIcon(for:)
                    )
                }
            } else {
                // Single monitor - show flat list
                ForEach(viewModel.groups) { group in
                    ForEach(group.windows) { window in
                        WindowPreviewCard(
                            window: window,
                            preview: previewService.previews[window.id],
                            appIcon: appIcon(for: group),
                            monitors: viewModel.monitors,
                            onFocus: { viewModel.focus(window: window) },
                            onClose: { viewModel.close(window: window) },
                            onMinimize: { viewModel.minimize(window: window) },
                            onQuit: { viewModel.quitApp(for: window) },
                            onTile: { position in viewModel.tileWindow(window, position: position) },
                            onMoveToMonitor: { monitor in viewModel.moveWindow(window, to: monitor) },
                            onSplitWith: { targetWindow, leftRight in
                                viewModel.splitWindows(window, targetWindow, leftRight: leftRight)
                            }
                        )
                        .help(window.displayTitle)
                    }
                }
            }
        }
    }

    func appIcon(for group: WindowAppGroup) -> NSImage {
        if !group.bundleIdentifier.isEmpty,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: group.bundleIdentifier).first,
           let bundleURL = running.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Monitor Section

private struct MonitorSection: View {
    let monitorGroup: MonitorWindowGroup
    let isExpanded: Bool
    let previewService: WindowPreviewService
    @ObservedObject var viewModel: WindowListViewModel
    let appIconProvider: (WindowAppGroup) -> NSImage

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header
            Button(action: { viewModel.toggleMonitor(monitorGroup.monitor) }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: Spacing.md)

                    Image(systemName: monitorGroup.monitor.isPrimary ? "display" : monitorGroup.monitor.relativePosition.icon)
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    Text(monitorGroup.monitor.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(CiderColors.primary)

                    Text("(\(monitorGroup.windowCount))")
                        .font(.caption2)
                        .foregroundColor(CiderColors.secondary)

                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
                .padding(.horizontal, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(monitorGroup.monitor.displayName)")

            // Windows
            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(monitorGroup.windowGroups) { group in
                        ForEach(group.windows) { window in
                            WindowPreviewCard(
                                window: window,
                                preview: previewService.previews[window.id],
                                appIcon: appIconProvider(group),
                                monitors: viewModel.monitors,
                                onFocus: { viewModel.focus(window: window) },
                                onClose: { viewModel.close(window: window) },
                                onMinimize: { viewModel.minimize(window: window) },
                                onQuit: { viewModel.quitApp(for: window) },
                                onTile: { position in viewModel.tileWindow(window, position: position) },
                                onMoveToMonitor: { monitor in viewModel.moveWindow(window, to: monitor) },
                                onSplitWith: { targetWindow, leftRight in
                                    viewModel.splitWindows(window, targetWindow, leftRight: leftRight)
                                }
                            )
                            .help(window.displayTitle)
                        }
                    }
                }
                .padding(.leading, Spacing.lg + Spacing.xxs)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.text, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let windowIDString = item as? String,
                  let windowID = CGWindowID(windowIDString) else { return }

            DispatchQueue.main.async {
                // Find the window and move it
                for group in viewModel.groups {
                    if let window = group.windows.first(where: { $0.id == windowID }) {
                        viewModel.moveWindow(window, to: monitorGroup.monitor)
                        break
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Window Preview Card

private struct WindowPreviewCard: View {
    let window: WindowInfo
    let preview: NSImage?
    let appIcon: NSImage?
    let monitors: [MonitorInfo]
    let onFocus: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onQuit: () -> Void
    let onTile: (TilePosition) -> Void
    let onMoveToMonitor: (MonitorInfo) -> Void
    let onSplitWith: (WindowInfo, Bool) -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var dropSide: DropSide = .none

    enum DropSide {
        case none, left, right
    }

    var body: some View {
        Button(action: onFocus) {
            ZStack(alignment: .bottomLeading) {
                // Preview image - preserves native aspect ratio
                Group {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        // Placeholder with default 16:9 aspect
                        Rectangle()
                            .fill(Color(.underPageBackgroundColor))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                Image(systemName: "macwindow")
                                    .font(.title)
                                    .foregroundColor(CiderColors.tertiary.opacity(0.6))
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(isDropTargeted ? Color.accentColor : CiderColors.separator.opacity(0.4), lineWidth: isDropTargeted ? 2 : 0.5)
                )

                // Drop side indicator
                if isDropTargeted && dropSide != .none {
                    HStack(spacing: 0) {
                        if dropSide == .left {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(maxWidth: .infinity)
                        }
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                        if dropSide == .right {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }

                // App icon badge (bottom left, like Stage Manager)
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .offset(x: Spacing.sm, y: -Spacing.sm)
                }

                // Window control buttons on hover (top right)
                if isHovering {
                    VStack {
                        HStack(spacing: Spacing.xs) {
                            Spacer()
                            // Minimize button
                            Button(action: onMinimize) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(CiderColors.primary, CiderColors.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Minimize window")
                            .accessibilityLabel("Minimize \(window.displayTitle)")

                            // Quit button (X now quits the app)
                            Button(action: onQuit) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(CiderColors.primary, CiderColors.destructive)
                            }
                            .buttonStyle(.plain)
                            .help("Quit app")
                            .accessibilityLabel("Quit \(window.ownerName)")
                        }
                        .offset(x: CiderDesign.runningIndicatorOffset, y: -CiderDesign.runningIndicatorOffset)
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(hoverAnimation) {
                isHovering = hovering
            }
        }
        .draggable(String(window.id))
        .contextMenu { contextMenuContent }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hoverAnimation: Animation {
        reduceMotion ? CiderAnimation.reduceMotion : CiderAnimation.snappy
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        // Tile submenu
        Menu {
            ForEach(TilePosition.halves, id: \.self) { position in
                Button {
                    onTile(position)
                } label: {
                    Label(position.displayName, systemImage: position.icon)
                }
            }

            Divider()

            ForEach(TilePosition.quarters, id: \.self) { position in
                Button {
                    onTile(position)
                } label: {
                    Label(position.displayName, systemImage: position.icon)
                }
            }

            Divider()

            ForEach(TilePosition.other, id: \.self) { position in
                Button {
                    onTile(position)
                } label: {
                    Label(position.displayName, systemImage: position.icon)
                }
            }
        } label: {
            Label("Tile", systemImage: "rectangle.split.2x2")
        }

        // Move to Monitor submenu (only show if multiple monitors)
        if monitors.count > 1 {
            Menu {
                ForEach(monitors) { monitor in
                    Button {
                        onMoveToMonitor(monitor)
                    } label: {
                        Label(monitor.displayName, systemImage: monitor.isPrimary ? "display" : monitor.relativePosition.icon)
                    }
                    .disabled(window.screenID == monitor.id)
                }
            } label: {
                Label("Move to Monitor", systemImage: "display.2")
            }
        }

        Divider()

        Button {
            onMinimize()
        } label: {
            Label("Minimize Window", systemImage: "minus")
        }

        Button {
            onClose()
        } label: {
            Label("Close Window", systemImage: "xmark")
        }

        Button(role: .destructive) {
            onQuit()
        } label: {
            Label("Quit App", systemImage: "power")
        }
    }
}

// MARK: - Permission Banner

private struct PermissionBannerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Accessibility Required")
                .font(.caption)
                .foregroundColor(CiderColors.primary)
            Text("Enable Cider in System Settings > Privacy & Security > Accessibility.")
                .font(.caption2)
                .foregroundColor(CiderColors.secondary)
        }
        .padding(Spacing.sm)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

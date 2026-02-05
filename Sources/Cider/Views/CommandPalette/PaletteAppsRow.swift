import SwiftUI
import AppKit

struct PaletteAppsRow: View {
    let apps: [AppInfo]
    let folders: [AppFolder]
    let focusedIndex: Int?
    let onAppClick: (AppInfo) -> Void
    let onFolderClick: (AppFolder) -> Void
    let isRunning: (AppInfo) -> Bool
    let onQuitApp: (AppInfo) -> Void
    @Environment(\.textScale) private var textScale

    @State private var expandedFolder: AppFolder?
    @State private var folderAnchor: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Pinned")
                .font(.system(size: 11 * textScale, weight: .medium))
                .foregroundColor(CiderColors.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CommandPaletteDesign.appGridSpacing) {
                    // Regular pinned apps
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        PaletteAppIcon(
                            app: app,
                            isRunning: isRunning(app),
                            isKeyboardFocused: focusedIndex == index,
                            onTap: { onAppClick(app) },
                            onQuit: { onQuitApp(app) }
                        )
                    }

                    // Folders
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        let folderFocusIndex = apps.count + index
                        PaletteFolderIcon(
                            folder: folder,
                            isKeyboardFocused: focusedIndex == folderFocusIndex
                        ) { anchor in
                            folderAnchor = anchor
                            if expandedFolder?.id == folder.id {
                                expandedFolder = nil
                            } else {
                                expandedFolder = folder
                            }
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .overlay(
            // Folder popup overlay
            Group {
                if let folder = expandedFolder {
                    FolderPopupView(
                        folder: folder,
                        anchor: folderAnchor,
                        isRunning: isRunning,
                        onAppClick: { app in
                            onAppClick(app)
                            expandedFolder = nil
                        },
                        onQuitApp: onQuitApp,
                        onDismiss: { expandedFolder = nil }
                    )
                }
            }
        )
    }
}

// MARK: - App Icon

struct PaletteAppIcon: View {
    let app: AppInfo
    let isRunning: Bool
    var isKeyboardFocused: Bool = false
    let onTap: () -> Void
    let onQuit: () -> Void
    @Environment(\.textScale) private var textScale

    @State private var isHovering = false
    @State private var accentColor: Color = .white

    private var isFocused: Bool {
        isHovering || isKeyboardFocused
    }

    private var iconSize: CGFloat {
        CommandPaletteDesign.appIconSize * textScale
    }

    private var appIcon: NSImage {
        if !app.path.isEmpty {
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 48, height: 48)
            return icon
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Spacing.xs) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(
                        Group {
                            if isKeyboardFocused {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(CiderColors.controlAccent.opacity(0.8), lineWidth: 2)
                            }
                        }
                    )
                    .scaleEffect(isFocused ? 1.1 : 1.0)

                // App name with running indicator bar underneath
                VStack(spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 10 * textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    // Running indicator - thin colored bar
                    if isRunning {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(accentColor)
                            .frame(width: iconSize * 0.5, height: 2)
                            .opacity(0.9)
                    }
                }
                .frame(width: iconSize + 8)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            // Extract accent color from app icon
            accentColor = ColorExtractor.vibrantColor(from: appIcon)
        }
        .onHover { hovering in
            withAnimation(.snappy) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Open") { onTap() }

            if isRunning {
                Divider()
                Button("Quit \(app.name)", role: .destructive) { onQuit() }
            }

            Divider()
            Button("Show in Finder") {
                if let url = URL(string: "file://\(app.path)") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}

// MARK: - Folder Icon

struct PaletteFolderIcon: View {
    let folder: AppFolder
    var isKeyboardFocused: Bool = false
    let onTap: (CGRect) -> Void
    @Environment(\.textScale) private var textScale

    @State private var isHovering = false
    @State private var iconFrame: CGRect = .zero

    private var isFocused: Bool {
        isHovering || isKeyboardFocused
    }

    private var iconSize: CGFloat {
        CommandPaletteDesign.folderIconSize * textScale
    }

    var body: some View {
        Button(action: {
            onTap(iconFrame)
        }) {
            VStack(spacing: Spacing.xs) {
                // Folder icon with mini app icons inside
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: iconSize, height: iconSize)

                    // Mini grid of app icons (2x2)
                    let gridApps = Array(folder.apps.prefix(4))
                    let miniSize = 16 * textScale
                    LazyVGrid(columns: [GridItem(.fixed(18 * textScale)), GridItem(.fixed(18 * textScale))], spacing: 2) {
                        ForEach(gridApps) { app in
                            Image(nsImage: iconFor(app))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: miniSize, height: miniSize)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                }
                .overlay(
                    Group {
                        if isKeyboardFocused {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(CiderColors.controlAccent.opacity(0.8), lineWidth: 2)
                        }
                    }
                )
                .scaleEffect(isFocused ? 1.1 : 1.0)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            iconFrame = geo.frame(in: .global)
                        }
                    }
                )

                Text(folder.name)
                    .font(.system(size: 10 * textScale))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                    .frame(width: iconSize + 8)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy) {
                isHovering = hovering
            }
        }
    }

    private func iconFor(_ app: AppInfo) -> NSImage {
        if !app.path.isEmpty {
            return NSWorkspace.shared.icon(forFile: app.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Folder Popup

struct FolderPopupView: View {
    let folder: AppFolder
    let anchor: CGRect
    let isRunning: (AppInfo) -> Bool
    let onAppClick: (AppInfo) -> Void
    let onQuitApp: (AppInfo) -> Void
    let onDismiss: () -> Void
    @Environment(\.textScale) private var textScale

    var body: some View {
        ZStack {
            // Dismiss background
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Popup content
            VStack(spacing: Spacing.sm) {
                Text(folder.name)
                    .font(.system(size: 11 * textScale, weight: .medium))
                    .foregroundColor(CiderColors.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50 * textScale))], spacing: Spacing.sm) {
                    ForEach(folder.apps) { app in
                        PaletteAppIcon(
                            app: app,
                            isRunning: isRunning(app),
                            onTap: { onAppClick(app) },
                            onQuit: { onQuitApp(app) }
                        )
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color(.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

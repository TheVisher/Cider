import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PaletteAppsRow: View {
    let items: [PinnedItem]
    let allFolders: [AppFolder]  // For "Move to folder" context menu
    var searchText: String = ""
    let focusedIndex: Int?
    let canAddMore: Bool
    var focusedFolderAppIndex: Int? = nil
    @Binding var expandedFolderID: UUID?
    let onAppClick: (AppInfo) -> Void
    let onFolderClick: (AppFolder) -> Void
    let isRunning: (AppInfo) -> Bool
    let onQuitApp: (AppInfo) -> Void
    let onReorderItems: ([PinnedItem]) -> Void
    let onCreateFolder: (AppInfo, AppInfo) -> Void
    let onAddToFolder: (AppInfo, AppFolder) -> Void
    let onAddAppToFolderFromPicker: (URL, AppFolder) -> Void
    let onRemoveFromFolderToPinned: (AppInfo, AppFolder) -> Void
    let onRemoveFromFolderAndCider: (AppInfo, AppFolder) -> Void
    let onMoveAppBetweenFolders: (AppInfo, AppFolder, AppFolder) -> Void
    let onRenameFolder: (AppFolder, String) -> Void
    let onAddApp: () -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var folderAnchor: CGRect = .zero

    private var expandedFolder: AppFolder? {
        guard let id = expandedFolderID else { return nil }
        return allFolders.first { $0.id == id }
    }

    @State private var draggedItem: PinnedItem?
    @State private var orderedItems: [PinnedItem] = []
    @State private var dropTargetAppID: UUID?
    @State private var folderDwellTimer: Timer?
    @State private var dwellTargetID: UUID?

    /// Fingerprint that changes when IDs, order, or folder names change
    private var itemsFingerprint: String {
        items.map { item in
            switch item {
            case .app(let app): return app.id.uuidString
            case .folder(let folder): return "\(folder.id):\(folder.name):\(folder.apps.count)"
            }
        }.joined(separator: ",")
    }

    private func syncItems() {
        // Always sync from source of truth when not actively dragging.
        // During drag, keep the local reorder state intact.
        guard draggedItem == nil else { return }
        orderedItems = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Pinned")
                .font(.system(size: 11 * textScale, weight: .medium))
                .foregroundColor(CiderColors.secondary)

            HStack(spacing: CommandPaletteDesign.appGridSpacing) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                    let isDragging = draggedItem?.id == item.id
                    let isDropTarget = dropTargetAppID == item.id

                    pinnedItemView(item: item, index: index)
                        .opacity(isDragging ? 0.0 : 1.0)
                        .scaleEffect(isDragging ? 0.8 : isDropTarget ? 1.15 : 1.0)
                        .overlay(
                            Group {
                                if isDropTarget && item.isApp {
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(CiderColors.controlAccent.opacity(0.6), lineWidth: 2)
                                }
                            }
                        )
                        .animation(reduceMotion ? .none : .smooth, value: isDragging)
                        .animation(reduceMotion ? .none : .snappy, value: isDropTarget)
                        .onDrag {
                            draggedItem = item
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: UnifiedDropDelegate(
                            targetItem: item,
                            items: $orderedItems,
                            draggedItem: $draggedItem,
                            dropTargetID: $dropTargetAppID,
                            dwellTargetID: $dwellTargetID,
                            dwellTimer: $folderDwellTimer,
                            reduceMotion: reduceMotion,
                            onReorder: { onReorderItems(orderedItems) },
                            onCreateFolder: onCreateFolder,
                            onAddToFolder: onAddToFolder
                        ))
                }

                // "+" add button
                if canAddMore && searchText.isEmpty {
                    AddAppButton(iconSize: CommandPaletteDesign.appIconSize * textScale) {
                        onAddApp()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
        }
        .overlay(
            Group {
                if let folder = expandedFolder {
                    FolderPopupView(
                        folder: folder,
                        anchor: folderAnchor,
                        allFolders: allFolders,
                        canAddMore: canAddMore,
                        focusedAppIndex: focusedFolderAppIndex,
                        isRunning: isRunning,
                        onAppClick: { app in
                            onAppClick(app)
                            expandedFolderID = nil
                        },
                        onQuitApp: onQuitApp,
                        onRemoveFromFolderToPinned: { app in
                            onRemoveFromFolderToPinned(app, folder)
                            if folder.apps.count <= 2 { expandedFolderID = nil }
                        },
                        onRemoveFromFolderAndCider: { app in
                            onRemoveFromFolderAndCider(app, folder)
                            if folder.apps.count <= 2 { expandedFolderID = nil }
                        },
                        onMoveToFolder: { app, destFolder in
                            onMoveAppBetweenFolders(app, folder, destFolder)
                            if folder.apps.count <= 2 { expandedFolderID = nil }
                        },
                        onRenameFolder: { newName in
                            onRenameFolder(folder, newName)
                        },
                        onAddApp: {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            panel.allowedContentTypes = [UTType.application]
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            panel.level = .floating
                            let response = panel.runModal()
                            guard response == .OK, let url = panel.url else { return }
                            onAddAppToFolderFromPicker(url, folder)
                        },
                        onDismiss: { expandedFolderID = nil }
                    )
                }
            }
        )
        .onAppear { syncItems() }
        .onChange(of: itemsFingerprint) { _, _ in syncItems() }
    }

    @ViewBuilder
    private func pinnedItemView(item: PinnedItem, index: Int) -> some View {
        switch item {
        case .app(let app):
            PaletteAppIcon(
                app: app,
                searchText: searchText,
                isRunning: isRunning(app),
                isKeyboardFocused: focusedIndex == index,
                onTap: { onAppClick(app) },
                onQuit: { onQuitApp(app) }
            )
        case .folder(let folder):
            PaletteFolderIcon(
                folder: folder,
                isKeyboardFocused: focusedIndex == index,
                isDropTargeted: dropTargetAppID == folder.id,
                onTap: { anchor in
                    folderAnchor = anchor
                    if expandedFolderID == folder.id {
                        expandedFolderID = nil
                    } else {
                        expandedFolderID = folder.id
                    }
                }
            )
        }
    }
}

// MARK: - Add App Button

private struct AddAppButton: View {
    let iconSize: CGFloat
    let onTap: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.12 : 0.06))
                        .frame(width: iconSize, height: iconSize)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(CiderColors.secondary)
                }
                Text("Add")
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: iconSize + 8)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) { isHovering = hovering }
        }
    }
}

// MARK: - App Icon

struct PaletteAppIcon: View {
    let app: AppInfo
    var searchText: String = ""
    let isRunning: Bool
    var isKeyboardFocused: Bool = false
    var showContextMenu: Bool = true
    let onTap: () -> Void
    let onQuit: () -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false
    @State private var accentColor: Color = .white

    private var isFocused: Bool { isHovering || isKeyboardFocused }
    private var iconSize: CGFloat { CommandPaletteDesign.appIconSize * textScale }

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

                VStack(spacing: 2) {
                    HighlightedText(app.name, highlight: searchText)
                        .font(.system(size: 10 * textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
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
        .onAppear { accentColor = ColorExtractor.vibrantColor(from: appIcon) }
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) { isHovering = hovering }
        }
        .modifier(OptionalContextMenu(enabled: showContextMenu) {
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
        })
    }
}

// MARK: - Folder Icon

struct PaletteFolderIcon: View {
    let folder: AppFolder
    var isKeyboardFocused: Bool = false
    var isDropTargeted: Bool = false
    let onTap: (CGRect) -> Void
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false
    @State private var iconFrame: CGRect = .zero

    private var isFocused: Bool { isHovering || isKeyboardFocused }
    private var iconSize: CGFloat { CommandPaletteDesign.folderIconSize * textScale }
    private var miniIconSize: CGFloat { (iconSize - 6) / 2 }

    var body: some View {
        Button(action: { onTap(iconFrame) }) {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.white.opacity(isDropTargeted ? 0.2 : 0.1))
                        .frame(width: iconSize, height: iconSize)

                    let gridApps = Array(folder.apps.prefix(4))
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            ForEach(gridApps.prefix(2)) { app in
                                Image(nsImage: iconFor(app))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: miniIconSize, height: miniIconSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                        }
                        if gridApps.count > 2 {
                            HStack(spacing: 2) {
                                ForEach(gridApps.dropFirst(2).prefix(2)) { app in
                                    Image(nsImage: iconFor(app))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: miniIconSize, height: miniIconSize)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    Group {
                        if isKeyboardFocused || isDropTargeted {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(CiderColors.controlAccent.opacity(0.8), lineWidth: 2)
                        }
                    }
                )
                .scaleEffect(isFocused || isDropTargeted ? 1.1 : 1.0)
                .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { iconFrame = geo.frame(in: .global) }
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
            withAnimation(reduceMotion ? .none : .snappy) { isHovering = hovering }
        }
    }

    private func iconFor(_ app: AppInfo) -> NSImage {
        if !app.path.isEmpty { return NSWorkspace.shared.icon(forFile: app.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Folder Popup

struct FolderPopupView: View {
    let folder: AppFolder
    let anchor: CGRect
    let allFolders: [AppFolder]
    let canAddMore: Bool
    var focusedAppIndex: Int? = nil
    let isRunning: (AppInfo) -> Bool
    let onAppClick: (AppInfo) -> Void
    let onQuitApp: (AppInfo) -> Void
    let onRemoveFromFolderToPinned: (AppInfo) -> Void
    let onRemoveFromFolderAndCider: (AppInfo) -> Void
    let onMoveToFolder: (AppInfo, AppFolder) -> Void
    let onRenameFolder: (String) -> Void
    let onAddApp: () -> Void
    let onDismiss: () -> Void
    @Environment(\.textScale) private var textScale

    @State private var isEditingName = false
    @State private var editedName = ""

    private var otherFolders: [AppFolder] {
        allFolders.filter { $0.id != folder.id }
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Spacing.sm) {
                // Editable folder name
                if isEditingName {
                    TextField("Folder name", text: $editedName, onCommit: {
                        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onRenameFolder(trimmed)
                        }
                        isEditingName = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11 * textScale, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                } else {
                    Text(folder.name)
                        .font(.system(size: 11 * textScale, weight: .medium))
                        .foregroundColor(CiderColors.secondary)
                        .onTapGesture {
                            editedName = folder.name
                            isEditingName = true
                        }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50 * textScale))], spacing: Spacing.sm) {
                    ForEach(Array(folder.apps.enumerated()), id: \.element.id) { index, app in
                        PaletteAppIcon(
                            app: app,
                            isRunning: isRunning(app),
                            isKeyboardFocused: focusedAppIndex == index,
                            showContextMenu: false,
                            onTap: { onAppClick(app) },
                            onQuit: { onQuitApp(app) }
                        )
                        .contextMenu {
                            Button("Open") { onAppClick(app) }

                            Divider()

                            if canAddMore {
                                Button("Move to Pinned") {
                                    onRemoveFromFolderToPinned(app)
                                }
                            }

                            if !otherFolders.isEmpty {
                                Menu("Move to Folder") {
                                    ForEach(otherFolders) { destFolder in
                                        Button(destFolder.name) {
                                            onMoveToFolder(app, destFolder)
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button("Remove from Cider", role: .destructive) {
                                onRemoveFromFolderAndCider(app)
                            }
                        }
                    }

                    AddAppButton(iconSize: CommandPaletteDesign.appIconSize * textScale) {
                        onAddApp()
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

// MARK: - Unified Drop Delegate

/// Single drop delegate for the unified pinned items list.
/// Handles reorder for all items, dwell-to-create-folder (app on app),
/// and drop-app-on-folder.
private struct UnifiedDropDelegate: DropDelegate {
    let targetItem: PinnedItem
    @Binding var items: [PinnedItem]
    @Binding var draggedItem: PinnedItem?
    @Binding var dropTargetID: UUID?
    @Binding var dwellTargetID: UUID?
    @Binding var dwellTimer: Timer?
    let reduceMotion: Bool
    let onReorder: () -> Void
    let onCreateFolder: (AppInfo, AppInfo) -> Void
    let onAddToFolder: (AppInfo, AppFolder) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != targetItem.id else { return }

        dwellTimer?.invalidate()

        // Clear folder highlight if it was on a different target
        if dropTargetID != nil && dropTargetID != targetItem.id {
            dropTargetID = nil
        }

        // If dragging an app onto another app, start dwell timer for folder creation
        if case .app = dragged, case .app = targetItem {
            dwellTargetID = targetItem.id
            let targetID = targetItem.id
            dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
                DispatchQueue.main.async {
                    if dwellTargetID == targetID {
                        dropTargetID = targetID
                    }
                }
            }
        }

        // If dragging an app onto a folder, highlight the folder
        if case .app = dragged, case .folder = targetItem {
            dropTargetID = targetItem.id
            // Don't reorder — the folder is a drop target
            return
        }

        // Reorder (only if not in folder-creation mode)
        guard dropTargetID == nil else { return }
        guard let fromIndex = items.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = items.firstIndex(where: { $0.id == targetItem.id }) else { return }

        withAnimation(reduceMotion ? .none : .smooth) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dwellTimer?.invalidate()
        dwellTimer = nil
        dwellTargetID = nil

        guard let dragged = draggedItem else { return false }

        // App dropped on folder → add to folder
        if case .app(let app) = dragged, case .folder(let folder) = targetItem,
           dropTargetID == targetItem.id {
            onAddToFolder(app, folder)
            dropTargetID = nil
            draggedItem = nil
            return true
        }

        // App dropped on app with dwell → create folder
        if case .app(let draggedApp) = dragged, case .app(let targetApp) = targetItem,
           dropTargetID == targetItem.id {
            onCreateFolder(draggedApp, targetApp)
            dropTargetID = nil
            draggedItem = nil
            return true
        }

        // Normal reorder
        onReorder()
        dropTargetID = nil
        draggedItem = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if dwellTargetID == targetItem.id {
            dwellTimer?.invalidate()
            dwellTimer = nil
            dwellTargetID = nil
        }
        if dropTargetID == targetItem.id {
            dropTargetID = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedItem != nil
    }
}

// MARK: - Optional Context Menu

/// A ViewModifier that conditionally applies a context menu.
private struct OptionalContextMenu<MenuContent: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let menuContent: () -> MenuContent

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { menuContent() }
        } else {
            content
        }
    }
}

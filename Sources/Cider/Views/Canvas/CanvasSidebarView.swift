import SwiftUI

/// Simplified folder sidebar for the canvas window.
/// Shows folder tree with item counts. Click a folder to pan the canvas to it.
struct CanvasSidebarView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    let onSelectFolder: (UUID) -> Void
    let onSelectAll: () -> Void

    @State private var selectedFolderID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var hoveredFolderID: UUID?

    @Environment(\.textScale) private var textScale

    private var topLevelFolders: [Folder] {
        bookmarksViewModel.folders
            .filter { $0.parentID == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func childFolders(of parentID: UUID) -> [Folder] {
        bookmarksViewModel.folders
            .filter { $0.parentID == parentID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func itemCount(for folderID: UUID) -> Int {
        let bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }.count
        let notes = NotesStorage.shared.notes.filter { $0.folderID == folderID }.count
        let todos = TodoCardStorage.shared.todoCards.filter { $0.folderID == folderID }.count
        return bookmarks + notes + todos
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Folders")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // "All Items" row
                    sidebarRow(
                        icon: "square.grid.2x2",
                        name: "All Items",
                        count: bookmarksViewModel.bookmarks.count
                            + NotesStorage.shared.notes.count
                            + TodoCardStorage.shared.todoCards.count,
                        isSelected: selectedFolderID == nil,
                        isHovered: hoveredFolderID == nil
                    )
                    .onTapGesture {
                        selectedFolderID = nil
                        onSelectAll()
                    }
                    .onHover { hoveredFolderID = $0 ? nil : hoveredFolderID }

                    // Folder tree (flattened to avoid recursive view issues)
                    ForEach(flattenedFolders, id: \.folder.id) { entry in
                        folderRowView(folder: entry.folder, depth: entry.depth)
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
        }
        .frame(width: 200)
        .background(CiderColors.surfaceInput.opacity(0.5))
    }

    private struct FolderEntry: Identifiable {
        var id: UUID { folder.id }
        let folder: Folder
        let depth: Int
    }

    private var flattenedFolders: [FolderEntry] {
        var result: [FolderEntry] = []
        func walk(_ parentID: UUID?, depth: Int) {
            let children = bookmarksViewModel.folders
                .filter { $0.parentID == parentID }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for child in children {
                result.append(FolderEntry(folder: child, depth: depth))
                if expandedFolderIDs.contains(child.id) {
                    walk(child.id, depth: depth + 1)
                }
            }
        }
        walk(nil, depth: 0)
        return result
    }

    private func folderRowView(folder: Folder, depth: Int) -> some View {
        let children = childFolders(of: folder.id)
        let hasChildren = !children.isEmpty
        let isExpanded = expandedFolderIDs.contains(folder.id)
        let count = itemCount(for: folder.id)

        return sidebarRow(
            icon: folder.icon ?? "folder",
            name: folder.name,
            count: count,
            isSelected: selectedFolderID == folder.id,
            isHovered: hoveredFolderID == folder.id,
            depth: depth,
            hasChildren: hasChildren,
            isExpanded: isExpanded
        )
        .onTapGesture {
            selectedFolderID = folder.id
            onSelectFolder(folder.id)
        }
        .onHover { isHovered in
            hoveredFolderID = isHovered ? folder.id : nil
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if hasChildren {
                    if isExpanded {
                        expandedFolderIDs.remove(folder.id)
                    } else {
                        expandedFolderIDs.insert(folder.id)
                    }
                }
            }
        )
    }

    private func sidebarRow(
        icon: String,
        name: String,
        count: Int,
        isSelected: Bool,
        isHovered: Bool,
        depth: Int = 0,
        hasChildren: Bool = false,
        isExpanded: Bool = false
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            // Folder icon — SF Symbol or emoji
            if icon.count <= 2 && icon.unicodeScalars.allSatisfy({ $0.value > 127 }) {
                // Emoji
                Text(icon)
                    .font(.system(size: 12))
            } else {
                // SF Symbol
                Image(systemName: icon)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
            }

            Text(name)
                .font(CiderFont.label)
                .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.primary)
                .lineLimit(1)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
        .padding(.leading, CGFloat(depth) * 16)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.selectedFill : (isHovered ? CiderColors.surfaceHover : Color.clear))
        )
        .contentShape(Rectangle())
    }
}

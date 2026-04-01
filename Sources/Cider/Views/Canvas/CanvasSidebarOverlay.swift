import SwiftUI
import os

/// Frosted glass sidebar that overlays the canvas from the left edge.
/// Shows folder tree, saved views, and tags. Clicking a folder pans the canvas to it.
struct CanvasSidebarOverlay: View {
    @Binding var isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var bookmarkService = VaultBookmarkService.shared
    @ObservedObject private var notesStorage = NotesStorage.shared
    @ObservedObject private var todoStorage = TodoCardStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var selectedFolderID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var folders: [VaultFolder] = []

    // Section collapse state
    @State private var foldersExpanded = true
    @State private var viewsExpanded = false
    @State private var tagsExpanded = false

    private static let sidebarWidth: CGFloat = 240
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "CanvasSidebarOverlay"
    )

    var body: some View {
        HStack(spacing: 0) {
            if isVisible {
                sidebarContent
                    .frame(width: Self.sidebarWidth)
                    .background {
                        VisualEffectView(
                            material: .underWindowBackground,
                            blendingMode: .withinWindow
                        )
                    }
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: Radius.lg,
                            topTrailingRadius: Radius.lg,
                            style: .continuous
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(CiderColors.borderSubtle)
                            .frame(width: 0.5)
                    }
                    .transition(.move(edge: .leading))
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: isVisible)
        .onAppear { refreshFolders() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultFoldersChanged)) { _ in
            refreshFolders()
        }
    }

    private func refreshFolders() {
        folders = VaultFolderService.shared.folders
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Folders section
                sectionHeader("Folders", icon: "folder", isExpanded: $foldersExpanded)
                if foldersExpanded {
                    foldersSection
                }

                Divider()
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)

                // Views section
                sectionHeader("Views", icon: "eye", isExpanded: $viewsExpanded)
                if viewsExpanded {
                    viewsSection
                }

                Divider()
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)

                // Tags section
                sectionHeader("Tags", icon: "tag", isExpanded: $tagsExpanded)
                if tagsExpanded {
                    tagsSection
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(
        _ title: String,
        icon: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 12)

                Image(systemName: icon)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)

                Text(title)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Folders Section

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            allItemsRow
            folderTreeRows
        }
        .padding(.horizontal, Spacing.xs)
    }

    private var allItemsRow: some View {
        folderRow(
            icon: "square.grid.2x2",
            name: "All Items",
            count: totalItemCount,
            isSelected: selectedFolderID == nil,
            depth: 0,
            hasChildren: false,
            isExpanded: false
        )
        .onTapGesture {
            selectedFolderID = nil
        }
    }

    private var folderTreeRows: some View {
        ForEach(flattenedFolders, id: \.folder.id) { entry in
            folderEntryRow(entry)
        }
    }

    private func folderEntryRow(_ entry: FolderEntry) -> some View {
        let folderID = entry.folder.id
        let hasChildren = !childFolders(of: folderID).isEmpty
        let isExpanded = expandedFolderIDs.contains(folderID)

        return folderRow(
            icon: entry.folder.icon ?? "folder",
            name: entry.folder.name,
            count: itemCount(for: folderID),
            isSelected: selectedFolderID == folderID,
            depth: entry.depth,
            hasChildren: hasChildren,
            isExpanded: isExpanded
        )
        .onTapGesture {
            selectedFolderID = folderID
            NotificationCenter.default.post(
                name: .panelFolderSelected,
                object: nil,
                userInfo: ["folderID": folderID]
            )
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard hasChildren else { return }
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.2)) {
                    if expandedFolderIDs.contains(folderID) {
                        expandedFolderIDs.remove(folderID)
                    } else {
                        expandedFolderIDs.insert(folderID)
                    }
                }
            }
        )
    }

    // MARK: - Views Section

    private var viewsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            staticRow(icon: "square.grid.2x2", name: "All Items")
            staticRow(icon: "tray", name: "Inbox")
        }
        .padding(.horizontal, Spacing.xs)
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if labelStorage.labels.isEmpty {
                Text("No tags yet")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
            } else {
                ForEach(labelStorage.labels) { label in
                    tagRow(label)
                }
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func tagRow(_ label: CardLabel) -> some View {
        let fillColor = Color(hex: label.colorHex) ?? CiderColors.controlAccent
        return HStack(spacing: Spacing.xs) {
            Circle()
                .fill(fillColor)
                .frame(width: 8, height: 8)
            Text(label.name)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: - Row Views

    private func folderRow(
        icon: String,
        name: String,
        count: Int,
        isSelected: Bool,
        depth: Int,
        hasChildren: Bool,
        isExpanded: Bool
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

            folderIcon(icon)

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
        .padding(.leading, CGFloat(depth) * Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.selectedFill : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func folderIcon(_ icon: String) -> some View {
        let isEmoji = icon.count <= 2 && icon.unicodeScalars.allSatisfy({ $0.value > 127 })
        if isEmoji {
            Text(icon)
                .font(.system(size: 12))
        } else {
            Image(systemName: icon)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
        }
    }

    private func staticRow(icon: String, name: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Spacer().frame(width: 12)
            Image(systemName: icon)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
            Text(name)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: - Data Helpers

    private var totalItemCount: Int {
        bookmarkService.bookmarks.count
            + notesStorage.notes.count
            + todoStorage.todoCards.count
    }

    private func itemCount(for folderID: UUID) -> Int {
        let bookmarks = bookmarkService.bookmarks.filter { $0.folderID == folderID }.count
        let notes = notesStorage.notes.filter { $0.folderID == folderID }.count
        let todos = todoStorage.todoCards.filter { $0.folderID == folderID }.count
        return bookmarks + notes + todos
    }

    private func childFolders(of parentID: UUID) -> [VaultFolder] {
        VaultFolderService.shared.children(of: parentID)
    }

    // MARK: - Folder Tree Flattening

    private struct FolderEntry: Identifiable {
        var id: UUID { folder.id }
        let folder: VaultFolder
        let depth: Int
    }

    private var flattenedFolders: [FolderEntry] {
        var result: [FolderEntry] = []
        func walk(parentID: UUID?, depth: Int) {
            let children = VaultFolderService.shared.children(of: parentID)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for child in children {
                result.append(FolderEntry(folder: child, depth: depth))
                if expandedFolderIDs.contains(child.id) {
                    walk(parentID: child.id, depth: depth + 1)
                }
            }
        }
        walk(parentID: nil, depth: 0)
        return result
    }
}

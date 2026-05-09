import SwiftUI

struct FolderBrowserView: View {
    let folders: [Folder]
    let bookmarks: [Bookmark]
    let notes: [Note]
    let navigationDomain: WorkspaceNavigationDomain
    var searchText: String = ""
    var onSelectFolder: (UUID) -> Void

    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared
    @ObservedObject private var todoCardStorage = TodoCardStorage.shared
    @ObservedObject private var vaultFileService = VaultFileService.shared

    private var visibleFolders: [Folder] {
        FolderBrowserModel.visibleFolders(
            folders: folders,
            directItemCounts: folderItemCounts,
            navigationDomain: navigationDomain,
            searchText: searchText
        )
    }

    private var itemEntityTypes: Set<LibraryEntityType> {
        WorkspaceDomainContentScope.defaultScope(for: navigationDomain).entityTypes(for: navigationDomain)
    }

    private var allItems: [LibraryItemV2] {
        let libraryItems =
            bookmarks.map { LibraryItemV2.bookmark($0) }
            + notes.map { LibraryItemV2.note($0) }
            + dateCardStorage.dateCards.map { LibraryItemV2.dateCard($0) }
            + contactStorage.contacts.map { LibraryItemV2.contact($0) }
            + todoCardStorage.todoCards.map { LibraryItemV2.todo($0) }
            + vaultFileService.files.map { LibraryItemV2.vaultFile($0) }
        return libraryItems.filter { itemEntityTypes.contains($0.entityType) }
    }

    private var folderItemCounts: [UUID: Int] {
        Dictionary(grouping: allItems.compactMap(\.folderID), by: { $0 })
            .mapValues(\.count)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    header

                    if visibleFolders.isEmpty {
                        EmptyStateView(
                            icon: "folder",
                            title: "No folders found",
                            subtitle: "Try a different sidebar search or create a folder from the add menu."
                        )
                        .frame(minHeight: 260)
                    } else {
                        let columns = [
                            GridItem(.adaptive(minimum: min(max(proxy.size.width * 0.22, 180), 240)), spacing: Spacing.sm)
                        ]
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.sm) {
                            ForEach(visibleFolders) { folder in
                                folderCard(folder)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
                .frame(width: proxy.size.width, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(navigationDomain.title) Folders")
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.primary)

            Text(navigationDomain == .browse
                 ? "All universal folders in the vault."
                 : "Folders available from the \(navigationDomain.title) domain.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
        }
    }

    private func folderCard(_ folder: Folder) -> some View {
        Button {
            onSelectFolder(folder.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    folderIcon(folder)

                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(folder.name)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)

                        Text(folderPath(folder))
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Text(folderCountText(folder))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separatorLight.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(CiderColors.separatorLight, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func folderIcon(_ folder: Folder) -> some View {
        if let icon = folder.icon, folder.iconIsEmoji {
            Text(icon)
                .font(CiderFont.bodySemibold)
                .frame(width: Spacing.xl, height: Spacing.xl)
        } else {
            Image(systemName: folder.icon ?? "folder")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
                .frame(width: Spacing.xl, height: Spacing.xl)
        }
    }

    private func folderCountText(_ folder: Folder) -> String {
        let directItems = folderItemCounts[folder.id] ?? 0
        let visibleFolderIDs = Set(visibleFolders.map(\.id))
        let childCount = folders.filter { $0.parentID == folder.id && visibleFolderIDs.contains($0.id) }.count
        let itemLabel = "\(directItems) item\(directItems == 1 ? "" : "s")"
        guard childCount > 0 else { return itemLabel }
        return "\(itemLabel) · \(childCount) folder\(childCount == 1 ? "" : "s")"
    }

    private func folderPath(_ folder: Folder) -> String {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var names = [folder.name]
        var parentID = folder.parentID
        var visited = Set<UUID>([folder.id])

        while let id = parentID, let parent = foldersByID[id], visited.insert(id).inserted {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }

        return names.joined(separator: " / ")
    }
}

enum FolderBrowserModel {
    static func visibleFolders(
        folders: [Folder],
        directItemCounts: [UUID: Int],
        navigationDomain: WorkspaceNavigationDomain,
        searchText: String = ""
    ) -> [Folder] {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var source = folders

        if navigationDomain != .browse {
            let directFolders = Set(
                directItemCounts.compactMap { folderID, count in
                    count > 0 ? folderID : nil
                }
            )
            let relevantIDs = directFolders.reduce(into: directFolders) { result, folderID in
                var parentID = foldersByID[folderID]?.parentID
                var visited = Set<UUID>([folderID])

                while let id = parentID, let parent = foldersByID[id], visited.insert(id).inserted {
                    result.insert(id)
                    parentID = parent.parentID
                }
            }
            source = source.filter { relevantIDs.contains($0.id) }
        }

        let sorted = source.sorted { lhs, rhs in
            folderPath(lhs, foldersByID: foldersByID)
                .localizedCaseInsensitiveCompare(folderPath(rhs, foldersByID: foldersByID)) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return sorted }
        return sorted.filter { folder in
            folder.name.localizedCaseInsensitiveContains(query)
                || folderPath(folder, foldersByID: foldersByID).localizedCaseInsensitiveContains(query)
        }
    }

    private static func folderPath(_ folder: Folder, foldersByID: [UUID: Folder]) -> String {
        var names = [folder.name]
        var parentID = folder.parentID
        var visited = Set<UUID>([folder.id])

        while let id = parentID, let parent = foldersByID[id], visited.insert(id).inserted {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }

        return names.joined(separator: " / ")
    }
}

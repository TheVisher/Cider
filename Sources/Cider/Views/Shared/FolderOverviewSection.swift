import CoreGraphics
import Foundation

struct FolderCardSummary: Equatable {
    struct Metric: Equatable {
        let count: Int
        let systemImage: String
    }

    let directItemCount: Int
    let childFolderCount: Int
    let badgeCount: Int?
    let metrics: [Metric]
    let isEmpty: Bool

    var totalCount: Int {
        directItemCount + childFolderCount
    }

    static func build(
        directItemCount: Int,
        childFolderCount: Int
    ) -> FolderCardSummary {
        var metrics: [Metric] = []
        if directItemCount > 0 {
            metrics.append(Metric(count: directItemCount, systemImage: "square.stack"))
        }
        if childFolderCount > 0 {
            metrics.append(Metric(count: childFolderCount, systemImage: "folder"))
        }

        let badgeCount: Int?
        if directItemCount > 0 {
            badgeCount = directItemCount
        } else if childFolderCount > 0 {
            badgeCount = childFolderCount
        } else {
            badgeCount = nil
        }

        return FolderCardSummary(
            directItemCount: directItemCount,
            childFolderCount: childFolderCount,
            badgeCount: badgeCount,
            metrics: metrics,
            isEmpty: directItemCount == 0 && childFolderCount == 0
        )
    }

    static func build(
        folderID: UUID,
        folders: [Folder],
        items: [LibraryItemV2]
    ) -> FolderCardSummary {
        let directItemCount = items.reduce(into: 0) { count, item in
            if item.folderID == folderID {
                count += 1
            }
        }
        let childFolderCount = folders.reduce(into: 0) { count, folder in
            if folder.parentID == folderID {
                count += 1
            }
        }

        return build(
            directItemCount: directItemCount,
            childFolderCount: childFolderCount
        )
    }

    var contentDescription: String {
        switch (directItemCount, childFolderCount) {
        case (0, 0):
            return "empty"
        case (let directItemCount, 0):
            return "\(directItemCount) direct item\(directItemCount == 1 ? "" : "s")"
        case (0, let childFolderCount):
            return "\(childFolderCount) subfolder\(childFolderCount == 1 ? "" : "s")"
        case (let directItemCount, let childFolderCount):
            return "\(directItemCount) direct item\(directItemCount == 1 ? "" : "s") and \(childFolderCount) subfolder\(childFolderCount == 1 ? "" : "s")"
        }
    }
}

struct FolderOverviewSection: Identifiable, Hashable {
    struct PreviewLayout: Equatable {
        let visibleItemCount: Int
        let remainingItemCount: Int
        let showsMoreCard: Bool
    }

    let folder: Folder
    let items: [LibraryItemV2]

    var id: UUID { folder.id }
    var itemCount: Int { items.count }

    static func buildSections(
        parentFolderID: UUID,
        folders: [Folder],
        items: [LibraryItemV2]
    ) -> [FolderOverviewSection] {
        let immediateChildren = folders
            .filter { $0.parentID == parentFolderID }
            .sorted { lhs, rhs in
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let itemsByFolderID = Dictionary(grouping: items.compactMap { item -> (UUID, LibraryItemV2)? in
            guard let folderID = item.folderID else { return nil }
            return (folderID, item)
        }, by: \.0)

        return immediateChildren.map { child in
            let directItems = (itemsByFolderID[child.id] ?? [])
                .map(\.1)
                .sorted { lhs, rhs in
                    if lhs.createdDate != rhs.createdDate {
                        return lhs.createdDate > rhs.createdDate
                    }
                    return lhs.id < rhs.id
                }
            return FolderOverviewSection(folder: child, items: directItems)
        }
    }

    static func previewLayout(
        items: [LibraryItemV2],
        availableWidth: CGFloat,
        preferredCardWidth: CGFloat,
        itemSpacing: CGFloat
    ) -> PreviewLayout {
        guard !items.isEmpty else {
            return PreviewLayout(visibleItemCount: 0, remainingItemCount: 0, showsMoreCard: false)
        }

        let slotWidth = max(preferredCardWidth, 1) + max(itemSpacing, 0)
        let slotCount = max(Int((max(availableWidth, 0) + max(itemSpacing, 0)) / slotWidth), 1)

        if items.count <= slotCount {
            return PreviewLayout(
                visibleItemCount: items.count,
                remainingItemCount: 0,
                showsMoreCard: false
            )
        }

        if slotCount >= 2 {
            let visibleItemCount = slotCount - 1
            return PreviewLayout(
                visibleItemCount: visibleItemCount,
                remainingItemCount: max(items.count - visibleItemCount, 0),
                showsMoreCard: true
            )
        }

        return PreviewLayout(
            visibleItemCount: 1,
            remainingItemCount: max(items.count - 1, 0),
            showsMoreCard: false
        )
    }
}

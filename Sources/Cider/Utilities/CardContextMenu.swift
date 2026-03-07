import AppKit
import SwiftUI

// MARK: - Menu Item Model

/// Describes a single item in a card context menu.
enum CardMenuItem {
    case action(title: String, image: NSImage? = nil, callback: () -> Void)
    case submenu(title: String, children: [CardMenuItem])
    case separator
    case destructive(title: String, callback: () -> Void)
}

// MARK: - View Modifier

/// Builds a fresh NSMenu on every right-click, avoiding SwiftUI's
/// .contextMenu caching bug where menu content goes stale after data changes.
struct CardContextMenuModifier: ViewModifier {
    let items: () -> [CardMenuItem]

    func body(content: Content) -> some View {
        content.overlay {
            CardContextMenuHelper(items: items)
        }
    }
}

// MARK: - NSViewRepresentable

private struct CardContextMenuHelper: NSViewRepresentable {
    let items: () -> [CardMenuItem]

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.menuBuilder = { buildMenu(from: items()) }
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.menuBuilder = { buildMenu(from: items()) }
    }

    private func buildMenu(from items: [CardMenuItem]) -> NSMenu {
        let menu = NSMenu()
        for item in items {
            menu.addItem(menuItem(from: item))
        }
        return menu
    }

    private func menuItem(from item: CardMenuItem) -> NSMenuItem {
        switch item {
        case .action(let title, let image, let callback):
            let mi = NSMenuItem(title: title, action: #selector(MenuActionTarget.runAction), keyEquivalent: "")
            mi.representedObject = callback
            mi.target = MenuActionTarget.shared
            mi.image = image
            return mi

        case .submenu(let title, let children):
            let sub = NSMenu()
            for child in children {
                sub.addItem(menuItem(from: child))
            }
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.submenu = sub
            return mi

        case .separator:
            return NSMenuItem.separator()

        case .destructive(let title, let callback):
            let mi = NSMenuItem(title: title, action: #selector(MenuActionTarget.runAction), keyEquivalent: "")
            mi.representedObject = callback
            mi.target = MenuActionTarget.shared
            return mi
        }
    }
}

// MARK: - Right-Click NSView

/// Invisible NSView that intercepts right-click to show a custom NSMenu.
/// Returns nil from hitTest for all events except right-clicks so that
/// left clicks, hovers, and drags pass through to SwiftUI content beneath.
final class RightClickView: NSView {
    var menuBuilder: (() -> NSMenu)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuBuilder?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - Action Target

@MainActor
private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    @objc func runAction(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}

// MARK: - Tag Submenu Helper

/// Builds a "Tags" submenu with all labels, toggling assignment.
/// When `isSelected` is true and `onToggleLabelBulk` is provided, tag actions apply to all selected items.
@MainActor
private func tagMenuItems(
    itemLabelIDs: [UUID],
    onToggleLabel: @escaping (UUID) -> Void,
    isSelected: Bool = false,
    onToggleLabelBulk: ((UUID) -> Void)? = nil,
    onCreateTag: (() -> Void)? = nil
) -> [CardMenuItem] {
    let allLabels = CardLabelStorage.shared.labels
    var children: [CardMenuItem] = []
    let handler = (isSelected && onToggleLabelBulk != nil) ? onToggleLabelBulk! : onToggleLabel

    for label in allLabels {
        let isAssigned = itemLabelIDs.contains(label.id)
        let title = isAssigned ? "\u{2713} \(label.name)" : "    \(label.name)"
        let labelID = label.id
        children.append(.action(title: title) { handler(labelID) })
    }

    if !children.isEmpty, onCreateTag != nil {
        children.append(.separator)
    }
    if let onCreateTag {
        children.append(.action(title: "New Tag\u{2026}", callback: onCreateTag))
    }

    guard !children.isEmpty else { return [] }
    return [.submenu(title: "Tags", children: children)]
}

// MARK: - Folder Submenu Helper

/// Builds standard "Move to Folder" menu items from a folder list.
private func folderMenuItems(
    folders: [Folder],
    onMoveToFolder: @escaping (UUID?) -> Void
) -> [CardMenuItem] {
    guard !folders.isEmpty else { return [] }
    var children: [CardMenuItem] = [
        .action(title: "No Folder") { onMoveToFolder(nil) },
        .separator
    ]
    for folder in folders {
        let id = folder.id
        children.append(.action(title: folder.name) { onMoveToFolder(id) })
    }
    return [.submenu(title: "Move to Folder", children: children)]
}

// MARK: - View Extensions

extension View {
    /// Context menu for note cards — Open, Rename, Tags, Move to Folder, Delete.
    func noteContextMenu(
        note: Note,
        folders: [Folder],
        onOpen: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onMoveToFolder: @escaping (UUID?) -> Void,
        onDelete: @escaping () -> Void,
        onToggleLabel: ((UUID) -> Void)? = nil,
        isSelected: Bool = false,
        onToggleLabelBulk: ((UUID) -> Void)? = nil
    ) -> some View {
        modifier(CardContextMenuModifier {
            var items: [CardMenuItem] = [
                .action(title: "Open", callback: onOpen),
                .action(title: "Rename", callback: onRename),
                .action(title: note.isPinned ? "Unpin Note" : "Pin Note", callback: onTogglePin)
            ]
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: note.labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += folderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
            items += [.separator, .destructive(title: "Delete", callback: onDelete)]
            return items
        })
    }

    /// Context menu for date card (event) cards — Open, Mark Complete, Tags, Move to Folder, Delete.
    func dateCardContextMenu(
        onOpen: @escaping () -> Void,
        onToggleComplete: @escaping () -> Void,
        isCompleted: Bool,
        labelIDs: [UUID] = [],
        folders: [Folder],
        onMoveToFolder: @escaping (UUID?) -> Void,
        onDelete: @escaping () -> Void,
        onToggleLabel: ((UUID) -> Void)? = nil,
        isSelected: Bool = false,
        onToggleLabelBulk: ((UUID) -> Void)? = nil
    ) -> some View {
        modifier(CardContextMenuModifier {
            var items: [CardMenuItem] = [
                .action(title: "Open", callback: onOpen),
                .action(title: isCompleted ? "Mark Incomplete" : "Mark Complete", callback: onToggleComplete)
            ]
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += folderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
            items += [.separator, .destructive(title: "Delete", callback: onDelete)]
            return items
        })
    }

    /// Context menu for contact cards — Open, Tags, Move to Folder, Delete.
    func contactContextMenu(
        onOpen: @escaping () -> Void,
        labelIDs: [UUID] = [],
        folders: [Folder],
        onMoveToFolder: @escaping (UUID?) -> Void,
        onDelete: @escaping () -> Void,
        onToggleLabel: ((UUID) -> Void)? = nil,
        isSelected: Bool = false,
        onToggleLabelBulk: ((UUID) -> Void)? = nil
    ) -> some View {
        modifier(CardContextMenuModifier {
            var items: [CardMenuItem] = [
                .action(title: "Open", callback: onOpen)
            ]
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += folderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
            items += [.separator, .destructive(title: "Delete", callback: onDelete)]
            return items
        })
    }

    /// Context menu for todo cards — Open, Mark Complete, Tags, Move to Folder, Delete.
    func todoCardContextMenu(
        onOpen: @escaping () -> Void,
        onToggleComplete: @escaping () -> Void,
        isCompleted: Bool,
        labelIDs: [UUID] = [],
        folders: [Folder],
        onMoveToFolder: @escaping (UUID?) -> Void,
        onDelete: @escaping () -> Void,
        onToggleLabel: ((UUID) -> Void)? = nil,
        isSelected: Bool = false,
        onToggleLabelBulk: ((UUID) -> Void)? = nil
    ) -> some View {
        modifier(CardContextMenuModifier {
            var items: [CardMenuItem] = [
                .action(title: "Open", callback: onOpen),
                .action(title: isCompleted ? "Mark Incomplete" : "Mark Complete", callback: onToggleComplete)
            ]
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += folderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
            items += [.separator, .destructive(title: "Delete", callback: onDelete)]
            return items
        })
    }

    /// Context menu for bookmark cards — Open in Browser, Show Details, Refetch Metadata, Tags, Move to Folder, Delete.
    func bookmarkContextMenu(
        bookmark: Bookmark,
        folders: [Folder],
        onOpen: @escaping () -> Void,
        onShowDetails: @escaping () -> Void,
        onRefetchMetadata: @escaping () -> Void,
        onMoveToFolder: @escaping (UUID?) -> Void,
        onDelete: @escaping () -> Void,
        onToggleLabel: ((UUID) -> Void)? = nil,
        isSelected: Bool = false,
        onToggleLabelBulk: ((UUID) -> Void)? = nil
    ) -> some View {
        modifier(CardContextMenuModifier {
            var items: [CardMenuItem] = [
                .action(title: "Open in Browser", callback: onOpen),
                .action(title: "Show Details", callback: onShowDetails),
                .action(title: "Refetch Metadata", callback: onRefetchMetadata)
            ]
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: bookmark.labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += folderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
            items += [.separator, .destructive(title: "Delete", callback: onDelete)]
            return items
        })
    }
}

import AppKit
import SwiftUI
import os

// MARK: - File Export

@MainActor
enum CiderFileExporter {
    private static let logger = Logger(subsystem: "com.cider.app", category: "FileExport")

    static func exportFile(sourceURL: URL, suggestedFileName: String, helpText: String? = nil) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        if let helpText {
            panel.accessoryView = helpAccessoryView(text: helpText)
        }

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            NSSound.beep()
            logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func helpAccessoryView(text: String) -> NSView {
        SavePanelHintView(text: text)
    }
}

private final class SavePanelHintView: NSView {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 34))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let availableWidth = max(intrinsicContentSize.width, bounds.width)
        let pillWidth = min(availableWidth - 56, 240)
        let pillRect = NSRect(
            x: (bounds.width - pillWidth) / 2,
            y: 4,
            width: pillWidth,
            height: bounds.height - 8
        )
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = pillRect.insetBy(dx: 10, dy: 6)
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

// MARK: - Menu Item Model

/// Describes a single item in a card context menu.
enum CardMenuItem {
    case action(title: String, image: NSImage? = nil, callback: () -> Void)
    case submenu(title: String, children: [CardMenuItem])
    case separator
    case disabled(title: String)
    case hint(title: String)
    case destructive(title: String, callback: () -> Void)
}

// MARK: - Export Submenu Builder

enum ExportMenuBuilder {
    static let bookmarkImageMenuHint = "Opt-drag to Finder to export image"
    static let noteMarkdownMenuHint = "Opt-drag to Finder to export Markdown"
    static let bookmarkImageSavePanelHint = "Opt-drag to export image"
    static let noteMarkdownSavePanelHint = "Opt-drag to export Markdown"

    static func bookmarkImageExportMenuItems(exportAction: @escaping () -> Void) -> [CardMenuItem] {
        [
            .submenu(title: "Export", children: [
                .action(title: "Image\u{2026}", callback: exportAction),
                .hint(title: bookmarkImageMenuHint)
            ])
        ]
    }

    static func noteMarkdownExportMenuItems(exportAction: @escaping () -> Void) -> [CardMenuItem] {
        [
            .submenu(title: "Export", children: [
                .action(title: "Markdown\u{2026}", callback: exportAction),
                .hint(title: noteMarkdownMenuHint)
            ])
        ]
    }
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

        case .disabled(let title):
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.isEnabled = false
            return mi

        case .hint(let title):
            let mi = NSMenuItem()
            mi.isEnabled = false
            mi.view = MenuHintView(text: title)
            return mi

        case .destructive(let title, let callback):
            let mi = NSMenuItem(title: title, action: #selector(MenuActionTarget.runAction), keyEquivalent: "")
            mi.representedObject = callback
            mi.target = MenuActionTarget.shared
            return mi
        }
    }
}

private final class MenuHintView: NSView {
    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 210, height: 22))

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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

// MARK: - Folder Submenu Builder

/// Builds standard "Move to Folder" menu items from a folder list.
enum FolderMenuBuilder {
    static func moveToFolderMenuItems(
        folders: [Folder],
        onMoveToFolder: @escaping (UUID?) -> Void
    ) -> [CardMenuItem] {
        guard !folders.isEmpty else { return [] }
        let folderIDs = Set(folders.map(\.id))
        var children: [CardMenuItem] = [
            .action(title: "No Folder") { onMoveToFolder(nil) },
            .separator
        ]
        children += folderMenuBranch(
            parentID: nil,
            folders: folders,
            folderIDs: folderIDs,
            onMoveToFolder: onMoveToFolder
        )
        return [.submenu(title: "Move to Folder", children: children)]
    }

    private static func folderMenuBranch(
        parentID: UUID?,
        folders: [Folder],
        folderIDs: Set<UUID>,
        onMoveToFolder: @escaping (UUID?) -> Void
    ) -> [CardMenuItem] {
        folders
            .filter { folder in
                if parentID == nil, let parent = folder.parentID, !folderIDs.contains(parent) {
                    return false
                }
                return folder.parentID == parentID
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { folder in
                let folderID = folder.id
                let children = folderMenuBranch(
                    parentID: folderID,
                    folders: folders,
                    folderIDs: folderIDs,
                    onMoveToFolder: onMoveToFolder
                )
                if children.isEmpty {
                    return .action(title: folder.name) { onMoveToFolder(folderID) }
                } else {
                    return .submenu(title: folder.name, children: children)
                }
            }
    }
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
            if let fileURL = NoteDragPayload.markdownExportURL(for: note) {
                items += ExportMenuBuilder.noteMarkdownExportMenuItems {
                    CiderFileExporter.exportFile(
                        sourceURL: fileURL,
                        suggestedFileName: NoteDragPayload.markdownExportFileName(for: note, fileURL: fileURL),
                        helpText: ExportMenuBuilder.noteMarkdownSavePanelHint
                    )
                }
            }
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: note.labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += FolderMenuBuilder.moveToFolderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
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
            items += FolderMenuBuilder.moveToFolderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
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
            items += FolderMenuBuilder.moveToFolderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
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
            items += FolderMenuBuilder.moveToFolderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
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
            if let fileURL = BookmarkDragPayload.imageExportURL(for: bookmark) {
                items += ExportMenuBuilder.bookmarkImageExportMenuItems {
                    CiderFileExporter.exportFile(
                        sourceURL: fileURL,
                        suggestedFileName: BookmarkDragPayload.suggestedImageExportFileName(
                            title: bookmark.title,
                            fileURL: fileURL
                        ),
                        helpText: ExportMenuBuilder.bookmarkImageSavePanelHint
                    )
                }
            }
            if let onToggleLabel {
                items += tagMenuItems(itemLabelIDs: bookmark.labelIDs, onToggleLabel: onToggleLabel, isSelected: isSelected, onToggleLabelBulk: onToggleLabelBulk)
            }
            items += FolderMenuBuilder.moveToFolderMenuItems(folders: folders, onMoveToFolder: onMoveToFolder)
            items += [.separator, .destructive(title: "Delete", callback: onDelete)]
            return items
        })
    }
}

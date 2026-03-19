import AppKit
import SwiftUI

// MARK: - Unified Table Row

struct LibraryTableRow: View {
    let item: LibraryItemV2
    let columnConfig: TableColumnConfig
    let labels: [CardLabel]
    var folders: [Folder] = []
    var isSelected: Bool = false
    var isFocused: Bool = false
    let onOpen: () -> Void
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Checkbox column
            Button {
                onSelect?()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(CiderFont.body)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: LibraryTableDesign.checkboxColumnWidth, height: LibraryTableDesign.rowHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(item.title)" : "Select \(item.title)")
            .opacity(isSelected || isHovered ? 1 : 0)

            // Dynamic columns
            ForEach(columnConfig.visibleColumns, id: \.self) { column in
                cellContent(for: column)
                    .frame(
                        width: column.isFlexible ? nil : columnConfig.width(for: column),
                        alignment: .leading
                    )
                    .frame(maxWidth: column.isFlexible ? .infinity : nil, alignment: .leading)
            }

            // Overflow menu
            LibraryTableRowMenu(item: item, onOpen: onOpen)
                .frame(width: LibraryTableDesign.menuColumnWidth)
                .opacity(isHovered ? 1 : 0)
        }
        .frame(height: LibraryTableDesign.rowHeight)
        .padding(.horizontal, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(
                    isSelected
                        ? CiderColors.selectedFill
                        : isHovered ? CiderColors.surfaceInput : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isFocused ? CiderColors.controlAccent : Color.clear, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .hoverState($isHovered, animation: .snappy)
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                onSelect?()
            } else if flags.contains(.shift) {
                onShiftSelect?()
            } else {
                onOpen()
            }
        }
    }

    // MARK: - Cell Content Switch

    @ViewBuilder
    private func cellContent(for column: TableColumnID) -> some View {
        switch column {
        case .name:
            nameCell
        case .type:
            textCell(typeLabel)
        case .tags:
            tagsCell
        case .folder:
            textCell(folderName)
        case .created:
            dateCell(item.createdDate)
        case .modified:
            dateCell(item.updatedDate)
        case .url:
            urlCell
        case .wordCount:
            textCell(wordCountLabel)
        case .priority:
            priorityCell
        }
    }

    // MARK: - Name Cell

    private var nameCell: some View {
        HStack(spacing: Spacing.sm) {
            itemIcon
                .frame(width: FolderSidebarItemDesign.folderIconSize, height: FolderSidebarItemDesign.folderIconSize)

            Text(item.title)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
        .padding(.leading, Spacing.sm)
    }

    // MARK: - Generic Text Cell

    private func textCell(_ text: String) -> some View {
        Text(text)
            .font(CiderFont.body)
            .foregroundColor(CiderColors.tertiary)
            .lineLimit(1)
            .padding(.leading, Spacing.sm)
    }

    // MARK: - Tags Cell

    private var tagsCell: some View {
        let resolved = item.labelIDs.compactMap { id in labels.first(where: { $0.id == id }) }
        return HStack(spacing: Spacing.xs) {
            ForEach(resolved.prefix(3)) { label in
                CompactTagPill(label: label)
            }
            if resolved.count > 3 {
                Text("+\(resolved.count - 3)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
        }
        .padding(.leading, Spacing.sm)
    }

    // MARK: - Date Cell

    private func dateCell(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year()))
            .font(CiderFont.body)
            .foregroundColor(CiderColors.tertiary)
            .lineLimit(1)
            .padding(.leading, Spacing.sm)
    }

    // MARK: - URL Cell

    private var urlCell: some View {
        Group {
            if case .bookmark(let bookmark) = item, bookmark.hasURL {
                Text(bookmark.hostDisplay)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            } else {
                Text("-")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
            }
        }
        .padding(.leading, Spacing.sm)
    }

    // MARK: - Priority Cell

    private var priorityCell: some View {
        Group {
            if case .todo(let todoCard) = item, let priority = todoCard.priority {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: priority.icon)
                        .font(CiderFont.caption)
                    Text(priority.displayName)
                        .font(CiderFont.body)
                }
                .foregroundColor(CiderColors.tertiary)
            } else {
                Text("-")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
            }
        }
        .padding(.leading, Spacing.sm)
    }

    // MARK: - Computed Labels

    private var typeLabel: String {
        switch item {
        case .bookmark: "Bookmark"
        case .note: "Note"
        case .dateCard: "Event"
        case .contact: "Contact"
        case .todo: "Todo"
        case .externalFile: "File"
        case .vaultFile: "File"
        case .session: "Session"
        }
    }

    private var folderName: String {
        guard let folderID = item.folderID else { return "-" }
        return folders.first(where: { $0.id == folderID })?.name ?? "-"
    }

    private var wordCountLabel: String {
        switch item {
        case .note(let note):
            // Word count from title as approximation (full content requires async load)
            let words = note.title.split(separator: " ").count
            return words > 0 ? "\(words)" : "-"
        case .bookmark(let bookmark):
            return bookmark.notes.isEmpty ? "-" : "\(bookmark.notes.split(separator: " ").count)"
        default:
            return "-"
        }
    }

    // MARK: - Item Icon

    @ViewBuilder
    private var itemIcon: some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkTableIcon(bookmark: bookmark)
        case .note:
            Image(systemName: "doc.text")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        case .dateCard:
            Image(systemName: "calendar")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        case .contact:
            Image(systemName: "person.crop.circle")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        case .todo(let todoCard):
            Image(systemName: todoCard.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(CiderFont.bodyMedium)
                .foregroundColor(todoCard.isCompleted ? CiderColors.success : CiderColors.secondary)
        case .externalFile:
            Image(systemName: "doc")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        case .vaultFile(let file):
            Image(systemName: file.fileType.systemImageName)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        case .session:
            Image(systemName: "rectangle.stack")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        }
    }
}

// MARK: - Bookmark Table Icon (favicon with gradient fallback)

private struct BookmarkTableIcon: View {
    let bookmark: Bookmark

    @State private var faviconImage: NSImage?

    var body: some View {
        Group {
            if let faviconImage {
                Image(nsImage: faviconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            } else {
                let (start, end) = BookmarkVisualStyle.gradient(for: bookmark)
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Text(String(bookmark.title.prefix(1)).uppercased())
                            .font(CiderFont.microBold)
                            .foregroundColor(CiderColors.textOnColor)
                    )
            }
        }
        .task(id: bookmark.id) {
            faviconImage = await loadFavicon()
        }
    }

    private func loadFavicon() async -> NSImage? {
        guard let url = bookmark.thumbnailFileURL else { return nil }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 40
                  ] as CFDictionary) else { return nil as NSImage? }
            return NSImage(cgImage: cgImage, size: NSSize(width: 20, height: 20))
        }.value
    }
}

// MARK: - Compact Tag Pill (for table cells)

private struct CompactTagPill: View {
    let label: CardLabel

    private var tintColor: Color {
        Color(hex: label.colorHex) ?? CiderColors.secondary
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(tintColor)
                .frame(width: ClipboardViewerTableDesign.tagDotSize, height: ClipboardViewerTableDesign.tagDotSize)

            Text(label.name)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.xs + Spacing.xxs)
        .padding(.vertical, Spacing.hairline)
        .background(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(tintColor.opacity(TagPillDesign.fillOpacity))
        )
    }
}

// MARK: - Overflow Menu

private struct LibraryTableRowMenu: View {
    let item: LibraryItemV2
    let onOpen: () -> Void

    var body: some View {
        Menu {
            Button("Open") {
                onOpen()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

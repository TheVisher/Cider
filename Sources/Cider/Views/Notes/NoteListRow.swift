import AppKit
import SwiftUI

struct NoteListRow: View {
    let note: Note
    let cardSizing: NoteCardSizing
    let searchText: String
    var folderName: String?
    let folders: [Folder]
    let isSelected: Bool
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onMoveToFolder: (UUID?) -> Void
    var dragProvider: (() -> NSItemProvider)? = nil
    var dragPreviewOverride: AnyView? = nil
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var cardData: NoteCardData = .empty
    @State private var isRenaming = false
    @State private var renamingTitle = ""
    @FocusState private var isRenameFocused: Bool

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

    var body: some View {
        Button { handleClick(normalAction: onOpen) } label: {
            HStack(spacing: Spacing.sm) {
                // Optional thumbnail (first image)
                if let firstURL = cardData.imageURLs.first,
                   let thumbnail = cardData.thumbnails[firstURL] {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardSizing.listImageSize, height: cardSizing.listImageSize)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        if isRenaming {
                            TextField("Note title", text: $renamingTitle)
                                .textFieldStyle(.plain)
                                .font(CiderFont.subheadingMedium)
                                .foregroundColor(CiderColors.primary)
                                .focused($isRenameFocused)
                                .task {
                                    try? await Task.sleep(for: .milliseconds(150))
                                    isRenameFocused = true
                                }
                                .onSubmit {
                                    let trimmed = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty { onRename(trimmed) }
                                    isRenaming = false
                                }
                                .onExitCommand { isRenaming = false }
                        } else {
                            HighlightedText(note.title, highlight: searchText)
                                .font(CiderFont.subheadingMedium)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)
                        }

                        if let folderName, !folderName.isEmpty {
                            Text(folderName)
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.accentText)
                                .lineLimit(1)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.hairline)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                        .fill(CiderColors.accentLight)
                                )
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        Text(note.createdAt.noteCardDate)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)

                        if cardData.wordCount > 0 {
                            Text("\u{00B7}")
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(CiderColors.quaternary)

                            Text("\(cardData.wordCount)w")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.quaternary)
                        }

                        HighlightedText(cardData.preview, highlight: searchText)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.quaternary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(
                        isSelected
                            ? CiderColors.separatorMedium
                            : isHovered ? CiderColors.surfaceInput : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered, animation: .snappy)
        .noteContextMenu(
            note: note,
            folders: folders,
            onOpen: onOpen,
            onRename: {
                renamingTitle = note.title
                isRenaming = true
            },
            onMoveToFolder: onMoveToFolder,
            onDelete: onDelete
        )
        .ciderDraggable(dragProvider) {
            if let preview = dragPreviewOverride {
                preview
            } else {
                NoteDragPreview(note: note)
            }
        }
        .task(id: note.modifiedAt) {
            if let cached = NoteCardDataCache.get(noteID: note.id, modifiedAt: note.modifiedAt) {
                cardData = cached
            } else {
                let data = await Task.detached(priority: .userInitiated) {
                    NoteCardData.load(for: note)
                }.value
                guard !Task.isCancelled else { return }
                NoteCardDataCache.set(data, noteID: note.id, modifiedAt: note.modifiedAt)
                cardData = data
            }
        }
    }
}

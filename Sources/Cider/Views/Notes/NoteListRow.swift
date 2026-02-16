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

    @State private var isHovered = false
    @State private var cardData: NoteCardData = .empty
    @State private var isRenaming = false
    @State private var renamingTitle = ""
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        Button(action: onOpen) {
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
                                .padding(.vertical, 1)
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
        .task(id: note.modifiedAt) {
            cardData = await Task.detached(priority: .userInitiated) {
                NoteCardData.load(for: note)
            }.value
        }
    }
}

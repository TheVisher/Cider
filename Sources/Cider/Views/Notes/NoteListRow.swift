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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                                .font(.system(size: 13, weight: .medium))
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
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)
                        }

                        if let folderName, !folderName.isEmpty {
                            Text(folderName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(CiderColors.controlAccent.opacity(0.7))
                                .lineLimit(1)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                        .fill(CiderColors.controlAccent.opacity(0.1))
                                )
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        Text(note.createdAt.noteCardDate)
                            .font(.system(size: 11))
                            .foregroundColor(CiderColors.tertiary)

                        if cardData.wordCount > 0 {
                            Text("\u{00B7}")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(CiderColors.quaternary)

                            Text("\(cardData.wordCount)w")
                                .font(.system(size: 11))
                                .foregroundColor(CiderColors.quaternary)
                        }

                        HighlightedText(cardData.preview, highlight: searchText)
                            .font(.system(size: 11))
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
                            ? CiderColors.separator.opacity(0.3)
                            : isHovered ? Color.white.opacity(0.08) : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovered = hovering
            }
        }
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

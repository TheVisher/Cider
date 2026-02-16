import SwiftUI

struct NoteCardView: View {
    let note: Note
    let mode: NoteCardMode
    let cardSizing: NoteCardSizing
    let searchText: String
    var folderName: String?
    let folders: [Folder]
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onMoveToFolder: (UUID?) -> Void

    enum NoteCardMode {
        case grid
        case masonry
    }

    @State private var isHovered = false
    @State private var cardData: NoteCardData = .empty
    @State private var isRenaming = false
    @State private var renamingTitle = ""
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title
            if isRenaming {
                TextField("Note title", text: $renamingTitle)
                    .textFieldStyle(.plain)
                    .font(CiderFont.subheadingSemibold)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HighlightedText(note.title, highlight: searchText)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Folder sub-header
            if let folderName, !folderName.isEmpty {
                Text(folderName)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.accentText)
                    .lineLimit(1)
            }

            // Content area: text + optional image, or empty placeholder
            if !cardData.preview.isEmpty || !cardData.imageURLs.isEmpty {
                contentArea
            } else {
                Text("Empty note")
                    .font(CiderFont.bodyItalic)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Footer
            footer
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: mode == .grid ? gridMinHeight : nil)
        .cardContainer(isHovered: isHovered)
        .onTapGesture(perform: onOpen)
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

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        let images = cardData.imageURLs
        if mode == .masonry && images.count >= 2 {
            multiImageContent(images: images)
        } else if let firstImage = images.first {
            singleImageContent(imageURL: firstImage)
        } else {
            textOnlyContent
        }
    }

    private func singleImageContent(imageURL: URL) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if !cardData.preview.isEmpty {
                HighlightedText(cardData.preview, highlight: searchText)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(mode == .grid ? gridPreviewLineLimit : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            noteImage(url: imageURL)
                .frame(width: cardSizing.imageWidth, height: cardSizing.imageWidth * 0.75)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
    }

    private func multiImageContent(images: [URL]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let displayImages = Array(images.prefix(3))
            ForEach(Array(displayImages.enumerated()), id: \.offset) { index, imageURL in
                let imageOnRight = index % 2 == 0
                HStack(alignment: .top, spacing: Spacing.sm) {
                    if !imageOnRight {
                        noteImage(url: imageURL)
                            .frame(width: cardSizing.imageWidth, height: cardSizing.imageWidth * 0.75)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                    }

                    if index == 0 && !cardData.preview.isEmpty {
                        HighlightedText(cardData.preview, highlight: searchText)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }

                    if imageOnRight {
                        noteImage(url: imageURL)
                            .frame(width: cardSizing.imageWidth, height: cardSizing.imageWidth * 0.75)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                    }
                }
            }
        }
    }

    private var textOnlyContent: some View {
        HighlightedText(cardData.preview, highlight: searchText)
            .font(CiderFont.body)
            .foregroundColor(CiderColors.secondary)
            .lineLimit(mode == .grid ? gridPreviewLineLimit : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            Text(note.createdAt.noteCardDate)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)

            if cardData.wordCount > 0 {
                Text("\u{00B7}")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.quaternary)

                Text("\(cardData.wordCount) words")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Image View

    @ViewBuilder
    private func noteImage(url: URL) -> some View {
        if let thumbnail = cardData.thumbnails[url] {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        }
    }

    // MARK: - Layout Helpers

    private var gridMinHeight: CGFloat {
        cardSizing.previewHeight + 60
    }

    private var gridPreviewLineLimit: Int {
        cardSizing.scale < 1.5 ? 4 : 6
    }
}

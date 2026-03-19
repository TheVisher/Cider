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
    var dragProvider: (() -> NSItemProvider)? = nil
    var dragPreviewOverride: AnyView? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    enum NoteCardMode {
        case grid
        case masonry
    }

    @Environment(\.hideCardFooters) private var hideCardFooters
    @Environment(\.showCardDetailsOnHover) private var showCardDetailsOnHover
    @State private var isHovered = false
    @State private var cardData: NoteCardData = .empty
    @State private var isRenaming = false
    @State private var renamingTitle = ""
    @FocusState private var isRenameFocused: Bool

    private var sidecarMeta: SidecarItemMetadata? {
        SidecarService.shared.metadata(forNote: note)
    }

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
        Button { if !isRenaming { handleClick(normalAction: onOpen) } } label: {
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

                // Content area with left accent bar
                HStack(alignment: .top, spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: NoteEditorDesign.accentBarRadius, style: .continuous)
                        .fill(CiderColors.accentDim)
                        .frame(width: NoteEditorDesign.accentBarWidth)

                    if !cardData.preview.isEmpty || !cardData.imageURLs.isEmpty {
                        contentArea
                    } else {
                        Text("Empty note")
                            .font(CiderFont.bodyItalic)
                            .foregroundColor(CiderColors.quaternary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !hideCardFooters {
                    // AI-generated summary from sidecar metadata
                    if let summary = sidecarMeta?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Footer
                    footer

                    if !note.labelIDs.isEmpty {
                        TagPillRow(
                            labelIDs: note.labelIDs,
                            labels: CardLabelStorage.shared.labels
                        )
                    }

                    // Sidecar metadata tags (from AI tools or .cider-meta.json)
                    // Filter out tags that already appear as Cider labels
                    if let sidecarTags = sidecarMeta?.tags, !sidecarTags.isEmpty {
                        let ciderLabelNames = Set(note.labelIDs.compactMap { id in
                            CardLabelStorage.shared.labels.first(where: { $0.id == id })?.name.lowercased()
                        })
                        let uniqueSidecarTags = sidecarTags.filter { !ciderLabelNames.contains($0.lowercased()) }
                        if !uniqueSidecarTags.isEmpty {
                            SidecarTagsView(tags: uniqueSidecarTags)
                        }
                    }
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: mode == .grid ? gridMinHeight : nil)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .bottom) {
            if hideCardFooters && showCardDetailsOnHover && isHovered {
                HStack(spacing: Spacing.xs) {
                    if let folderName, !folderName.isEmpty {
                        Text(folderName)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.accentText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(note.createdAt.noteCardDate)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(CiderColors.surfaceElevated.opacity(NoteEditorDesign.hoverOverlayOpacity))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .hoverState($isHovered, animation: .snappy)
        .noteContextMenu(
            note: note,
            folders: folders,
            onOpen: onOpen,
            onRename: {
                renamingTitle = note.title
                isRenaming = true
            },
            onTogglePin: {
                NotesStorage.shared.togglePin(note.id)
            },
            onMoveToFolder: onMoveToFolder,
            onDelete: onDelete,
            onToggleLabel: { labelID in
                if note.labelIDs.contains(labelID) {
                    _ = NotesStorage.shared.removeLabel(note.id, labelID: labelID)
                } else {
                    _ = NotesStorage.shared.assignLabel(note.id, labelID: labelID)
                }
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
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
                .frame(width: cardSizing.imageWidth, height: cardSizing.imageHeight)
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
                            .frame(width: cardSizing.imageWidth, height: cardSizing.imageHeight)
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
                            .frame(width: cardSizing.imageWidth, height: cardSizing.imageHeight)
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
            .lineLimit(mode == .grid ? gridPreviewLineLimit : masonryPreviewLineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            if let folderName, !folderName.isEmpty {
                Text(folderName)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.accentText)
                    .lineLimit(1)

                Text("\u{00B7}")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.quaternary)
            }

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
        cardSizing.previewHeight + NoteEditorDesign.gridMinHeightPadding
    }

    private var gridPreviewLineLimit: Int {
        cardSizing.scale < 1.5 ? 4 : 6
    }

    private var masonryPreviewLineLimit: Int {
        cardSizing.scale < 1.5 ? 7 : 10
    }
}

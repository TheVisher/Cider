import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BookmarkCard: View {
    enum CardMode {
        case grid
        case masonry
    }

    private static let thumbnailDropTypeIdentifiers: [String] = [
        UTType.image.identifier,
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier,
    ]

    let bookmark: Bookmark
    var searchText: String
    let mode: CardMode
    let cardSizing: CardSizing
    var folders: [Folder] = []
    var dragProvider: (() -> NSItemProvider)? = nil
    var dragPreviewOverride: AnyView? = nil
    let onShowDetails: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isThumbnailDropTargeted = false
    @State private var cardWidth: CGFloat = 220
    @State private var resolvedThumbnailAspectRatio: CGFloat?

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
        VStack(alignment: .leading, spacing: BookmarksDesign.cardContentSpacing) {
            Button { handleClick(normalAction: onShowDetails) } label: {
                BookmarkThumbnailView(
                    bookmark: bookmark,
                    mode: mode == .grid ? .grid : .masonry,
                    onAspectRatioResolved: { resolvedThumbnailAspectRatio = $0 }
                )
                    .frame(height: resolvedThumbnailHeight)
                    .overlay(alignment: .topTrailing) {
                        if isHovered {
                            Image(systemName: "info.circle")
                                .font(CiderFont.bodySemibold(scale: textScale))
                                .foregroundColor(CiderColors.secondary)
                                .padding(Spacing.xs)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("Show bookmark details")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button { handleClick(normalAction: onOpen) } label: {
                    HighlightedText(bookmark.title, highlight: searchText)
                        .font(CiderFont.labelSemibold(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button { handleClick(normalAction: onOpen) } label: {
                    HStack(spacing: Spacing.xs) {
                        if bookmark.hasURL {
                            Text(bookmark.hostDisplay)
                                .font(CiderFont.body(scale: textScale))
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Spacing.xs)

                        Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                if !bookmark.labelIDs.isEmpty {
                    TagPillRow(
                        labelIDs: bookmark.labelIDs,
                        labels: CardLabelStorage.shared.labels
                    )
                }
            }
        }
        .padding(Spacing.sm)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isDropTargeted: isThumbnailDropTargeted)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateCardWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        updateCardWidth(width)
                    }
            }
        )
        .hoverState($isHovered, animation: .snappy)
        .bookmarkContextMenu(
            bookmark: bookmark,
            folders: folders,
            onOpen: onOpen,
            onShowDetails: onShowDetails,
            onRefetchMetadata: { BookmarksStorage.shared.refetchMetadata(for: bookmark.id) },
            onMoveToFolder: { folderID in onMoveToFolder?(folderID) },
            onDelete: onDelete,
            onToggleLabel: { labelID in
                if bookmark.labelIDs.contains(labelID) {
                    _ = BookmarksStorage.shared.removeLabel(bookmark.id, labelID: labelID)
                } else {
                    _ = BookmarksStorage.shared.assignLabel(bookmark.id, labelID: labelID)
                }
            }
        )
        .onDrop(
            of: Self.thumbnailDropTypeIdentifiers,
            isTargeted: $isThumbnailDropTargeted,
            perform: handleThumbnailDrop(providers:)
        )
        .ciderDraggable(dragProvider) {
            if let preview = dragPreviewOverride {
                preview
            } else {
                BookmarkDragPreview(bookmark: bookmark)
            }
        }
    }

    private var resolvedThumbnailHeight: CGFloat {
        let idealWidth = max(cardSizing.cardMinWidth, 1)
        let widthScale = cardWidth / idealWidth

        switch mode {
        case .grid:
            return cardWidth * (cardSizing.gridThumbnailHeight / idealWidth)
        case .masonry:
            guard let aspectRatio = resolvedThumbnailAspectRatio else {
                return cardSizing.masonryThumbnailHeightFallback * widthScale
            }

            return cardWidth * aspectRatio
        }
    }

    private func updateCardWidth(_ width: CGFloat) {
        let normalized = max(width - Spacing.sm * 2, 1)
        guard abs(normalized - cardWidth) > 0.5 else { return }
        cardWidth = normalized
    }

    private func handleThumbnailDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers where loadThumbnailDrop(from: provider) {
            return true
        }
        return false
    }

    private func loadThumbnailDrop(from provider: NSItemProvider) -> Bool {
        let bookmarkID = bookmark.id

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { item, _ in
                guard let image = item as? NSImage,
                      let data = image.pngRepresentation else { return }
                Task { @MainActor in
                    let saved = BookmarksStorage.shared.assignThumbnail(for: bookmarkID, imageData: data, preferredFileExtension: "png")
                    Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Dropped content is not a valid image", isSuccess: saved)
                }
            }
            return true
        }

        let imageIdentifiers = provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
        }

        for identifier in imageIdentifiers {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else { return }
                let ext = Self.preferredImageFileExtension(for: identifier)
                Task { @MainActor in
                    let saved = BookmarksStorage.shared.assignThumbnail(for: bookmarkID, imageData: data, preferredFileExtension: ext)
                    Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Dropped content is not a valid image", isSuccess: saved)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data else { return }
                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        let saved = BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: droppedURL)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped image file", isSuccess: saved)
                    }
                    return
                }
                if let droppedString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                    Task { @MainActor in
                        let saved = await BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedString)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                    }
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let droppedURL = item as? URL else { return }
                Task { @MainActor in
                    if droppedURL.isFileURL {
                        let saved = BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: droppedURL)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped image file", isSuccess: saved)
                    } else {
                        let saved = await BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedURL.absoluteString)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                    }
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let droppedString = item as? String else { return }
                Task { @MainActor in
                    let saved = await BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedString)
                    Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                }
            }
            return true
        }

        let fallbackIdentifiers = [
            UTType.url.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
        ]

        for identifier in fallbackIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else { return }
                if let droppedString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                    Task { @MainActor in
                        let saved = await BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedString)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                    }
                    return
                }
                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        if droppedURL.isFileURL {
                            let saved = BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: droppedURL)
                            Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped image file", isSuccess: saved)
                        } else {
                            let saved = await BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedURL.absoluteString)
                            Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                        }
                    }
                }
            }
            return true
        }

        return false
    }

    private static func postThumbnailToast(_ message: String, isSuccess: Bool) {
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: ["message": message, "isSuccess": isSuccess]
        )
    }

    private nonisolated static func preferredImageFileExtension(for typeIdentifier: String) -> String? {
        guard let type = UTType(typeIdentifier) else { return nil }

        if let extensionName = type.preferredFilenameExtension?.lowercased() {
            return extensionName == "jpeg" ? "jpg" : extensionName
        }

        if type.conforms(to: .png) { return "png" }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .gif) { return "gif" }
        if type.conforms(to: .heic) { return "heic" }
        if type.conforms(to: .tiff) { return "tiff" }
        return nil
    }
}

private extension NSImage {
    var pngRepresentation: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

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
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hideCardFooters) private var hideCardFooters
    @Environment(\.showCardDetailsOnHover) private var showCardDetailsOnHover
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
                    isHovered: isHovered,
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
                    .overlay(alignment: .bottom) {
                        if hideCardFooters && showCardDetailsOnHover && isHovered {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Button { handleClick(normalAction: onOpen) } label: {
                                    Text(bookmark.title)
                                        .font(CiderFont.labelSemibold(scale: textScale))
                                        .foregroundColor(CiderColors.textOnColor)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                if bookmark.hasURL {
                                    Text(bookmark.hostDisplay)
                                        .font(CiderFont.body(scale: textScale))
                                        .foregroundColor(CiderColors.textOnColorDim)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.sm)
                            .padding(.top, Spacing.xxl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [.clear, CiderColors.gradientOverlay],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Show bookmark details")

            if !hideCardFooters {
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
        }
        .padding(Spacing.sm)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused, isDropTargeted: isThumbnailDropTargeted)
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
            onRefetchMetadata: { VaultBookmarkService.shared.refetchMetadata(for: bookmark.id) },
            onMoveToFolder: { folderID in onMoveToFolder?(folderID) },
            onDelete: onDelete,
            onToggleLabel: { labelID in
                if bookmark.labelIDs.contains(labelID) {
                    _ = VaultBookmarkService.shared.removeLabel(bookmark.id, labelID: labelID)
                } else {
                    _ = VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: labelID)
                }
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
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

    /// Whether dropped images should append to carousel instead of replacing the thumbnail.
    private var shouldAddToCarousel: Bool {
        bookmark.thumbnailRelativePath != nil
    }

    private func loadThumbnailDrop(from provider: NSItemProvider) -> Bool {
        let bookmarkID = bookmark.id
        let addToCarousel = shouldAddToCarousel

        // Check for GIF-specific type identifier first (preserves animation)
        let gifIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .gif)
        }
        if let gifIdentifier {
            provider.loadDataRepresentation(forTypeIdentifier: gifIdentifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    if addToCarousel {
                        let saved = VaultBookmarkService.shared.addCarouselImage(for: bookmarkID, imageData: data, preferredFileExtension: "gif")
                        Self.postThumbnailToast(saved ? "Added image to carousel" : "Dropped content is not a valid image", isSuccess: saved)
                    } else {
                        let saved = VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, imageData: data, preferredFileExtension: "gif")
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Dropped content is not a valid image", isSuccess: saved)
                    }
                }
            }
            return true
        }

        // Load raw image data
        let imageIdentifiers = provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
        }

        for identifier in imageIdentifiers {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else { return }
                let ext = Self.preferredImageFileExtension(for: identifier)
                Task { @MainActor in
                    if addToCarousel {
                        let saved = VaultBookmarkService.shared.addCarouselImage(for: bookmarkID, imageData: data, preferredFileExtension: ext)
                        Self.postThumbnailToast(saved ? "Added image to carousel" : "Dropped content is not a valid image", isSuccess: saved)
                    } else {
                        let saved = VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, imageData: data, preferredFileExtension: ext)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Dropped content is not a valid image", isSuccess: saved)
                    }
                }
            }
            // Also try to load the source URL — if it's a .gif, upgrade the static TIFF to animated GIF
            if !addToCarousel {
                Self.tryUpgradeToAnimatedSource(provider: provider, bookmarkID: bookmarkID)
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { item, _ in
                guard let image = item as? NSImage,
                      let data = image.pngRepresentation else { return }
                Task { @MainActor in
                    if addToCarousel {
                        let saved = VaultBookmarkService.shared.addCarouselImage(for: bookmarkID, imageData: data, preferredFileExtension: "png")
                        Self.postThumbnailToast(saved ? "Added image to carousel" : "Dropped content is not a valid image", isSuccess: saved)
                    } else {
                        let saved = VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, imageData: data, preferredFileExtension: "png")
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Dropped content is not a valid image", isSuccess: saved)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data else { return }
                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        let saved = VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: droppedURL)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped image file", isSuccess: saved)
                    }
                    return
                }
                if let droppedString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                    Task { @MainActor in
                        let saved = await VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedString)
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
                        let saved = VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: droppedURL)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped image file", isSuccess: saved)
                    } else {
                        let saved = await VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedURL.absoluteString)
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
                    let saved = await VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedString)
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
                        let saved = await VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedString)
                        Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                    }
                    return
                }
                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        if droppedURL.isFileURL {
                            let saved = VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: droppedURL)
                            Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped image file", isSuccess: saved)
                        } else {
                            let saved = await VaultBookmarkService.shared.assignThumbnail(for: bookmarkID, fromDroppedString: droppedURL.absoluteString)
                            Self.postThumbnailToast(saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL", isSuccess: saved)
                        }
                    }
                }
            }
            return true
        }

        return false
    }

    /// After saving a static image from a drop, check if the provider also has a URL
    /// pointing to an animated format (.gif). If so, download the actual animated data
    /// and replace the static thumbnail. Browsers provide TIFF (single frame) for dragged
    /// images, so this is the only way to preserve animation from drag-drop.
    /// After saving static image data from a browser drag, try to download the actual
    /// animated source from the image's URL. Browsers give TIFF (single frame) for dragged
    /// images, so this is the only way to preserve GIF animation from drag-drop.
    private static func tryUpgradeToAnimatedSource(provider: NSItemProvider, bookmarkID: UUID) {
        guard provider.canLoadObject(ofClass: NSURL.self) else { return }
        provider.loadObject(ofClass: NSURL.self) { item, _ in
            guard let droppedURL = item as? URL, !droppedURL.isFileURL else { return }
            // Download from the source URL — cacheImageAssets detects GIF/animation via magic bytes
            // and will try .gif variant if URL is .webp
            Task { @MainActor in
                _ = await VaultBookmarkService.shared.assignThumbnail(
                    for: bookmarkID,
                    fromDroppedString: droppedURL.absoluteString
                )
            }
        }
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

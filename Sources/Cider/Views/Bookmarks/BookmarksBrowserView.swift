import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BookmarksBrowserView: View {
    let bookmarks: [Bookmark]
    @Binding var displayMode: BookmarkDisplayMode
    var searchText: String = ""
    var showsOpenWindowButton = false
    var onOpenWindow: (() -> Void)? = nil
    var onOpenBookmark: (Bookmark) -> Void
    var onShowBookmarkDetails: ((Bookmark) -> Void)? = nil
    var onDeleteBookmark: ((Bookmark) -> Void)? = nil
    var onAddBookmark: (String, String?) -> Bool
    var onUpdateBookmarkDetails: ((Bookmark, String, String, [String]) -> Bool)? = nil
    var onAssignThumbnailFromDroppedString: ((Bookmark, String) -> Bool)? = nil
    var onAssignThumbnailFromLocalFileURL: ((Bookmark, URL) -> Bool)? = nil
    var onAssignThumbnailFromImageData: ((Bookmark, Data, String?) -> Bool)? = nil
    var onCaptureFromActiveBrowser: (() -> Bool)? = nil
    var onAddFromPasteboard: (() -> Bool)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAddFormVisible = false
    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var addErrorMessage: String?
    @State private var isDropTargeted = false

    private var hasBookmarks: Bool {
        !bookmarks.isEmpty
    }

    private var cardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: BookmarksDesign.cardMinWidth), spacing: Spacing.md)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            toolbar

            if isAddFormVisible {
                addForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if hasBookmarks {
                content
            } else {
                emptyState
            }
        }
        .padding(Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? CiderColors.controlAccent.opacity(0.65) : Color.clear,
                    lineWidth: CiderBorder.innerStrokeWidth
                )
        )
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .onDrop(
            of: [UTType.url.identifier, UTType.plainText.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop(providers:)
        )
        .help("Drop a URL to save bookmark")
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            Picker("Bookmark Layout", selection: $displayMode) {
                ForEach(BookmarkDisplayMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: BookmarksDesign.layoutPickerMaxWidth)

            Spacer(minLength: Spacing.sm)

            if showsOpenWindowButton {
                Button(action: { onOpenWindow?() }) {
                    Label("Open Window", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11 * textScale, weight: .medium))
                        .frame(minHeight: BookmarksDesign.buttonTapTarget)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.14))
                )
            }

            if let onAddFromPasteboard {
                if let onCaptureFromActiveBrowser {
                    Button(action: {
                        let added = onCaptureFromActiveBrowser()
                        if !added {
                            addErrorMessage = "Could not capture active browser tab."
                        } else {
                            addErrorMessage = nil
                        }
                    }) {
                        Image(systemName: "safari")
                            .font(.system(size: 11 * textScale, weight: .semibold))
                            .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(CiderColors.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .help("Capture active browser tab")
                }

                Button(action: {
                    let added = onAddFromPasteboard()
                    if !added {
                        addErrorMessage = "Clipboard does not contain a valid URL."
                    } else {
                        addErrorMessage = nil
                    }
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11 * textScale, weight: .semibold))
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.secondary)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .help("Add bookmark from clipboard")
            }

            Button(action: toggleAddForm) {
                Image(systemName: isAddFormVisible ? "xmark" : "plus")
                    .font(.system(size: 11 * textScale, weight: .semibold))
                    .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
            }
            .buttonStyle(.plain)
            .foregroundColor(CiderColors.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .help(isAddFormVisible ? "Close add bookmark" : "Add bookmark")
        }
        .frame(minHeight: BookmarksDesign.toolbarHeight)
    }

    @ViewBuilder
    private var addForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextField("Title (optional)", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            TextField("https://example.com", text: $draftURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitAddBookmark() }

            HStack(spacing: Spacing.sm) {
                Button("Save") {
                    commitAddBookmark()
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.controlAccent)

                Button("Cancel") {
                    closeAddForm(resetFields: true)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.secondary)

                Spacer(minLength: Spacing.sm)

                if let addErrorMessage {
                    Text(addErrorMessage)
                        .font(.system(size: 11 * textScale))
                        .foregroundColor(CiderColors.destructive)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .list:
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(bookmarks) { bookmark in
                    BookmarkListRow(
                        bookmark: bookmark,
                        searchText: searchText,
                        onShowDetails: { onShowBookmarkDetails?(bookmark) },
                        onOpen: { onOpenBookmark(bookmark) },
                        onDelete: { onDeleteBookmark?(bookmark) }
                    )
                }
            }

        case .grid:
            LazyVGrid(
                columns: cardColumns,
                spacing: Spacing.md
            ) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(
                        bookmark: bookmark,
                        searchText: searchText,
                        mode: .grid,
                        onShowDetails: { onShowBookmarkDetails?(bookmark) },
                        onOpen: { onOpenBookmark(bookmark) },
                        onDelete: { onDeleteBookmark?(bookmark) },
                        onAssignThumbnailFromDroppedString: onAssignThumbnailFromDroppedString,
                        onAssignThumbnailFromLocalFileURL: onAssignThumbnailFromLocalFileURL,
                        onAssignThumbnailFromImageData: onAssignThumbnailFromImageData
                    )
                }
            }

        case .masonry:
            BookmarkMasonryLayout(
                minimumColumnWidth: BookmarksDesign.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(
                        bookmark: bookmark,
                        searchText: searchText,
                        mode: .masonry,
                        onShowDetails: { onShowBookmarkDetails?(bookmark) },
                        onOpen: { onOpenBookmark(bookmark) },
                        onDelete: { onDeleteBookmark?(bookmark) },
                        onAssignThumbnailFromDroppedString: onAssignThumbnailFromDroppedString,
                        onAssignThumbnailFromLocalFileURL: onAssignThumbnailFromLocalFileURL,
                        onAssignThumbnailFromImageData: onAssignThumbnailFromImageData
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bookmark")
                .font(.system(size: 32 * textScale))
                .foregroundColor(CiderColors.tertiary)

            Text("No bookmarks yet")
                .font(.system(size: 13 * textScale, weight: .medium))
                .foregroundColor(CiderColors.secondary)

            Text("Add one with the + button or paste from clipboard")
                .font(.system(size: 11 * textScale))
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    private func toggleAddForm() {
        withAnimation(reduceMotion ? .none : .snappy) {
            isAddFormVisible.toggle()
        }

        if !isAddFormVisible {
            closeAddForm(resetFields: false)
        }
    }

    private func closeAddForm(resetFields: Bool) {
        withAnimation(reduceMotion ? .none : .snappy) {
            isAddFormVisible = false
        }

        addErrorMessage = nil
        guard resetFields else { return }

        draftTitle = ""
        draftURL = ""
    }

    private func commitAddBookmark() {
        let saved = onAddBookmark(draftURL, draftTitle.isEmpty ? nil : draftTitle)
        if saved {
            closeAddForm(resetFields: true)
        } else {
            addErrorMessage = "Enter a valid URL to save the bookmark."
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if loadDroppedValue(from: provider) {
                return true
            }
        }
        return false
    }

    private func loadDroppedValue(from provider: NSItemProvider) -> Bool {
        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let droppedURL = item as? URL else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as a URL."
                    }
                    return
                }
                DispatchQueue.main.async {
                    saveDroppedString(droppedURL.absoluteString)
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let droppedString = item as? String else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as text."
                    }
                    return
                }
                DispatchQueue.main.async {
                    saveDroppedString(droppedString)
                }
            }
            return true
        }

        let preferredIdentifiers = [
            UTType.url.identifier,
            UTType.fileURL.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
        ]

        for identifier in preferredIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as a URL."
                    }
                    return
                }

                if let droppedString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                    DispatchQueue.main.async {
                        saveDroppedString(droppedString)
                    }
                    return
                }

                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        saveDroppedString(droppedURL.absoluteString)
                    }
                    return
                }

                DispatchQueue.main.async {
                    addErrorMessage = "Drop could not be parsed as a URL."
                }
            }
            return true
        }

        for identifier in provider.registeredTypeIdentifiers {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data, let droppedString = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as a URL."
                    }
                    return
                }
                DispatchQueue.main.async {
                    saveDroppedString(droppedString)
                }
            }
            return true
        }

        return false
    }

    private func saveDroppedString(_ rawValue: String) {
        let saved = onAddBookmark(rawValue, nil)
        if saved {
            addErrorMessage = nil
        } else {
            addErrorMessage = "Drop does not contain a valid URL."
        }
    }
}

private struct BookmarkListRow: View {
    let bookmark: Bookmark
    var searchText: String
    let onShowDetails: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onShowDetails) {
                BookmarkThumbnailView(bookmark: bookmark, mode: .list)
                    .frame(width: BookmarksDesign.thumbnailWidthList, height: BookmarksDesign.thumbnailHeightList)
            }
            .buttonStyle(.plain)
            .help("Show bookmark details")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button(action: onOpen) {
                    HighlightedText(bookmark.title, highlight: searchText)
                        .font(.system(size: 12 * textScale, weight: .semibold))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    HStack(spacing: Spacing.xs) {
                        Text(bookmark.hostDisplay)
                            .font(.system(size: 11 * textScale))
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 10 * textScale, weight: .semibold))
                            .foregroundColor(CiderColors.tertiary)

                        Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11 * textScale))
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11 * textScale, weight: .semibold))
                        .foregroundColor(CiderColors.destructive)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.destructive.opacity(0.14))
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

private struct BookmarkCard: View {
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
    let onShowDetails: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    var onAssignThumbnailFromDroppedString: ((Bookmark, String) -> Bool)? = nil
    var onAssignThumbnailFromLocalFileURL: ((Bookmark, URL) -> Bool)? = nil
    var onAssignThumbnailFromImageData: ((Bookmark, Data, String?) -> Bool)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isThumbnailDropTargeted = false
    @State private var cardWidth: CGFloat = BookmarksDesign.cardMinWidth
    @State private var resolvedThumbnailAspectRatio: CGFloat?

    private var supportsThumbnailDrops: Bool {
        onAssignThumbnailFromDroppedString != nil
            || onAssignThumbnailFromLocalFileURL != nil
            || onAssignThumbnailFromImageData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BookmarksDesign.cardContentSpacing) {
            Button(action: onShowDetails) {
                BookmarkThumbnailView(
                    bookmark: bookmark,
                    mode: mode == .grid ? .grid : .masonry,
                    onAspectRatioResolved: { resolvedThumbnailAspectRatio = $0 }
                )
                    .frame(height: resolvedThumbnailHeight)
                    .overlay(alignment: .topTrailing) {
                        if isHovered {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11 * textScale, weight: .semibold))
                                .foregroundColor(CiderColors.secondary)
                                .padding(Spacing.xs)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("Show bookmark details")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button(action: onOpen) {
                    HighlightedText(bookmark.title, highlight: searchText)
                        .font(.system(size: 12 * textScale, weight: .semibold))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    HStack(spacing: Spacing.xs) {
                        Text(bookmark.hostDisplay)
                            .font(.system(size: 11 * textScale))
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)

                        Spacer(minLength: Spacing.xs)

                        Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11 * textScale))
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BookmarksDesign.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BookmarksDesign.cardCornerRadius, style: .continuous)
                .stroke(
                    supportsThumbnailDrops && isThumbnailDropTargeted
                        ? CiderColors.controlAccent.opacity(0.65)
                        : Color.white.opacity(isHovered ? 0.18 : 0.08),
                    lineWidth: supportsThumbnailDrops && isThumbnailDropTargeted
                        ? CiderBorder.innerStrokeWidth
                        : 1
                )
        )
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
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open in Browser") { onOpen() }
            Button("Delete", role: .destructive) { onDelete() }
        }
        .onDrop(
            of: Self.thumbnailDropTypeIdentifiers,
            isTargeted: $isThumbnailDropTargeted,
            perform: handleThumbnailDrop(providers:)
        )
    }

    private var resolvedThumbnailHeight: CGFloat {
        switch mode {
        case .grid:
            return BookmarksDesign.thumbnailHeightGrid
        case .masonry:
            guard let aspectRatio = resolvedThumbnailAspectRatio else {
                return BookmarksDesign.thumbnailHeightMasonryFallback
            }

            let proposedHeight = cardWidth * aspectRatio
            return min(
                max(proposedHeight, BookmarksDesign.thumbnailHeightMasonryMin),
                BookmarksDesign.thumbnailHeightMasonryMax
            )
        }
    }

    private func updateCardWidth(_ width: CGFloat) {
        let normalized = max(width - Spacing.sm * 2, 1)
        guard abs(normalized - cardWidth) > 0.5 else { return }
        cardWidth = normalized
    }

    private func handleThumbnailDrop(providers: [NSItemProvider]) -> Bool {
        guard supportsThumbnailDrops else { return false }

        for provider in providers where loadThumbnailDrop(from: provider) {
            return true
        }

        return false
    }

    private func loadThumbnailDrop(from provider: NSItemProvider) -> Bool {
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { item, _ in
                guard let image = item as? NSImage,
                      let data = image.pngRepresentation else {
                    return
                }
                DispatchQueue.main.async {
                    _ = onAssignThumbnailFromImageData?(bookmark, data, "png")
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
                DispatchQueue.main.async {
                    _ = onAssignThumbnailFromImageData?(
                        bookmark,
                        data,
                        preferredImageFileExtension(for: identifier)
                    )
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data else { return }

                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        _ = onAssignThumbnailFromLocalFileURL?(bookmark, droppedURL)
                    }
                    return
                }

                if let droppedString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                    DispatchQueue.main.async {
                        _ = onAssignThumbnailFromDroppedString?(bookmark, droppedString)
                    }
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let droppedURL = item as? URL else { return }
                DispatchQueue.main.async {
                    if droppedURL.isFileURL {
                        _ = onAssignThumbnailFromLocalFileURL?(bookmark, droppedURL)
                    } else {
                        _ = onAssignThumbnailFromDroppedString?(bookmark, droppedURL.absoluteString)
                    }
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let droppedString = item as? String else { return }
                DispatchQueue.main.async {
                    _ = onAssignThumbnailFromDroppedString?(bookmark, droppedString)
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
                    DispatchQueue.main.async {
                        _ = onAssignThumbnailFromDroppedString?(bookmark, droppedString)
                    }
                    return
                }

                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        if droppedURL.isFileURL {
                            _ = onAssignThumbnailFromLocalFileURL?(bookmark, droppedURL)
                        } else {
                            _ = onAssignThumbnailFromDroppedString?(bookmark, droppedURL.absoluteString)
                        }
                    }
                }
            }
            return true
        }

        return false
    }

    private func preferredImageFileExtension(for typeIdentifier: String) -> String? {
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

private struct BookmarkThumbnailView: View {
    enum ThumbnailMode {
        case list
        case grid
        case masonry
    }

    let bookmark: Bookmark
    let mode: ThumbnailMode
    var onAspectRatioResolved: ((CGFloat?) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @State private var thumbnailImage: NSImage?
    @State private var rendersAsIconOverlay = false
    @State private var loadedThumbnailPath: String?

    private var palette: (Color, Color) {
        BookmarkVisualStyle.gradient(for: bookmark)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.clear)
            .overlay(content: thumbnailContent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .onAppear(perform: loadThumbnailIfNeeded)
            .onChange(of: bookmark.thumbnailRelativePath) { _, _ in
                loadThumbnailIfNeeded()
            }
    }

    @ViewBuilder
    private func thumbnailContent() -> some View {
        if let thumbnailImage, !shouldSuppressDownloadedThumbnail {
            if rendersAsIconOverlay {
                iconOverlayGradient(for: thumbnailImage)
            } else {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: mode == .masonry ? .fit : .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if bookmark.isEnriching {
            BookmarkShimmerPlaceholder()
        } else {
            fallbackGradient
        }
    }

    private var shouldSuppressDownloadedThumbnail: Bool {
        let fingerprint = (bookmark.thumbnailRemoteURLString ?? "").lowercased()
        if fingerprint.isEmpty { return false }

        let blockedFragments = [
            "if-you-are-looking-for-an-image",
            "if_you_are_looking_for_an_image",
            "/removed.",
            "/deleted.",
            "/default.",
            "/self.",
            "/nsfw.",
            "/spoiler.",
            "preview.redd.it/default",
            "preview.redd.it/self",
            "preview.redd.it/nsfw",
            "preview.redd.it/spoiler",
        ]

        return blockedFragments.contains { fragment in
            fingerprint.contains(fragment)
        }
    }

    private var fallbackGradient: some View {
        gradientBackground
        .overlay {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Spacer(minLength: 0)

                Text(String(bookmark.hostDisplay.prefix(1)).uppercased())
                    .font(.system(size: mode == .list ? 16 * textScale : 26 * textScale, weight: .black))
                    .foregroundColor(Color.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.sm)
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [palette.0.opacity(0.8), palette.1.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func iconOverlayGradient(for image: NSImage) -> some View {
        gradientBackground
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: iconOverlaySize * textScale,
                        height: iconOverlaySize * textScale
                    )
                    .padding(.top, mode == .list ? Spacing.xl : Spacing.sm)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            }
    }

    private var iconOverlaySize: CGFloat {
        switch mode {
        case .list:
            return BookmarksDesign.thumbnailIconOverlaySizeList
        case .grid, .masonry:
            return BookmarksDesign.thumbnailIconOverlaySizeGrid
        }
    }

    private func loadThumbnailIfNeeded() {
        let path = bookmark.thumbnailFileURL?.path
        guard loadedThumbnailPath != path else { return }
        loadedThumbnailPath = path

        guard let path else {
            thumbnailImage = nil
            rendersAsIconOverlay = false
            onAspectRatioResolved?(nil)
            return
        }

        thumbnailImage = NSImage(contentsOfFile: path)
        if shouldSuppressDownloadedThumbnail {
            rendersAsIconOverlay = false
            onAspectRatioResolved?(nil)
            return
        }
        rendersAsIconOverlay = shouldRenderAsIconOverlay(
            image: thumbnailImage,
            remoteURLString: bookmark.thumbnailRemoteURLString
        )
        onAspectRatioResolved?(rendersAsIconOverlay ? nil : resolvedAspectRatio(from: thumbnailImage))
    }

    private func resolvedAspectRatio(from image: NSImage?) -> CGFloat? {
        guard let image else { return nil }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image.size.height / image.size.width
    }

    private func shouldRenderAsIconOverlay(image: NSImage?, remoteURLString: String?) -> Bool {
        guard let image else { return false }
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return false }

        let aspectRatio = width / height
        let isSquareish = abs(aspectRatio - 1) <= BookmarksDesign.thumbnailIconCandidateMaxAspectDelta
        let maxDimension = max(width, height)
        let minDimension = min(width, height)
        let isTinySquareAsset =
            isSquareish &&
            minDimension >= BookmarksDesign.thumbnailIconCandidateMinDimension &&
            maxDimension <= BookmarksDesign.thumbnailIconCandidateMaxDimension

        let remoteFingerprint = (remoteURLString ?? "").lowercased()
        let hasIconURLHint =
            remoteFingerprint.contains("favicon") ||
            remoteFingerprint.contains("apple-touch-icon") ||
            remoteFingerprint.contains("mask-icon") ||
            remoteFingerprint.hasSuffix(".ico")

        return hasIconURLHint || isTinySquareAsset
    }
}

private struct BookmarkShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerProgress: CGFloat = -0.9

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.14),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceMotion {
                    let bandWidth = max(
                        BookmarksDesign.thumbnailShimmerBandMinWidth,
                        proxy.size.width * BookmarksDesign.thumbnailShimmerBandWidthRatio
                    )
                    let travel = proxy.size.width + bandWidth
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: bandWidth)
                    .rotationEffect(.degrees(20))
                    .offset(x: shimmerProgress * travel)
                    .blendMode(.plusLighter)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.smooth(duration: BookmarksDesign.thumbnailShimmerDuration).repeatForever(autoreverses: false)) {
                shimmerProgress = 1.2
            }
        }
        .onDisappear {
            shimmerProgress = -0.9
        }
    }
}

private struct BookmarkMasonryLayout: Layout {
    let minimumColumnWidth: CGFloat
    let itemSpacing: CGFloat

    struct Cache {
        var frames: [CGRect] = []
        var measuredWidth: CGFloat = 0
        var measuredHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(frames: Array(repeating: .zero, count: subviews.count))
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.frames.count != subviews.count {
            cache.frames = Array(repeating: .zero, count: subviews.count)
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let availableWidth = resolvedLayoutWidth(proposal.width)
        computeFramesIfNeeded(availableWidth: availableWidth, subviews: subviews, cache: &cache)
        return CGSize(width: availableWidth, height: cache.measuredHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let availableWidth = resolvedLayoutWidth(bounds.width)
        computeFramesIfNeeded(availableWidth: availableWidth, subviews: subviews, cache: &cache)

        for index in subviews.indices {
            let frame = cache.frames[index]
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subviews[index].place(
                at: origin,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func computeFramesIfNeeded(
        availableWidth: CGFloat,
        subviews: Subviews,
        cache: inout Cache
    ) {
        if cache.frames.count != subviews.count {
            cache.frames = Array(repeating: .zero, count: subviews.count)
        }

        let columnCount = resolvedColumnCount(for: availableWidth)
        let columnWidth = resolvedColumnWidth(for: availableWidth, columnCount: columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for index in subviews.indices {
            let column = index % columnCount
            let measured = subviews[index].sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            let height = measured.height
            let x = CGFloat(column) * (columnWidth + itemSpacing)
            let y = columnHeights[column]
            cache.frames[index] = CGRect(x: x, y: y, width: columnWidth, height: height)
            columnHeights[column] += height + itemSpacing
        }

        cache.measuredWidth = availableWidth
        cache.measuredHeight = max(0, (columnHeights.max() ?? 0) - itemSpacing)
    }

    private func resolvedColumnCount(for width: CGFloat) -> Int {
        guard width.isFinite, width > minimumColumnWidth else { return 1 }

        let denominator = minimumColumnWidth + itemSpacing
        guard denominator.isFinite, denominator > 0 else { return 1 }

        let rawCount = ((width + itemSpacing) / denominator).rounded(.down)
        guard rawCount.isFinite, rawCount > 0 else { return 1 }

        let count = Int(rawCount)
        return max(1, count)
    }

    private func resolvedColumnWidth(for width: CGFloat, columnCount: Int) -> CGFloat {
        guard width.isFinite, width > 0 else { return minimumColumnWidth }
        guard columnCount > 1 else { return width }
        let totalSpacing = itemSpacing * CGFloat(columnCount - 1)
        let computed = (width - totalSpacing) / CGFloat(columnCount)
        guard computed.isFinite, computed > 0 else { return minimumColumnWidth }
        return max(1, computed)
    }

    private func resolvedLayoutWidth(_ proposedWidth: CGFloat?) -> CGFloat {
        let rawWidth = proposedWidth ?? minimumColumnWidth
        guard rawWidth.isFinite, rawWidth > 0 else { return minimumColumnWidth }
        return max(minimumColumnWidth, rawWidth)
    }
}

private enum BookmarkVisualStyle {
    private static let gradientPairs: [(NSColor, NSColor)] = [
        (.systemBlue, .systemTeal),
        (.systemOrange, .systemYellow),
        (.systemPink, .systemRed),
        (.systemIndigo, .systemBlue),
        (.systemMint, .systemGreen),
        (.systemCyan, .systemBlue)
    ]

    static func gradient(for bookmark: Bookmark) -> (Color, Color) {
        let hashValue = abs(bookmark.urlString.hashValue)
        let index = hashValue % gradientPairs.count
        let pair = gradientPairs[index]
        return (Color(pair.0), Color(pair.1))
    }
}

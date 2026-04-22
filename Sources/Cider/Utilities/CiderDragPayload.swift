import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bookmark Drag Payload

enum BookmarkDragPayload {
    static let typeIdentifier = "com.cider.bookmark-id"
    static let textPrefix = "cider-bookmark-id:"

    nonisolated private static func registerData(
        on provider: NSItemProvider,
        typeIdentifier: String,
        data: Data
    ) {
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            MainActor.assumeIsolated {
                completion(data, nil)
            }
            return nil
        }
    }

    static func bookmarkID(from raw: String) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(textPrefix) {
            let idPortion = String(trimmed.dropFirst(textPrefix.count))
            return UUID(uuidString: idPortion)
        }
        return UUID(uuidString: trimmed)
    }

    @MainActor
    static func registerPublicURL(on provider: NSItemProvider, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        registerData(on: provider, typeIdentifier: UTType.url.identifier, data: url.dataRepresentation)
    }

    /// Register image data for drag-out using `registerDataRepresentation`.
    ///
    /// Safe to use on providers that also carry text/internal types — does NOT use
    /// `registerFileRepresentation` or `public.file-url` which break SwiftUI's `.onDrop`.
    /// However, Finder may not create a file from raw data alone.
    @MainActor
    static func registerPublicImage(on provider: NSItemProvider, bookmark: Bookmark) {
        guard let fileURL = bookmark.originalImageFileURL ?? bookmark.thumbnailFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }

        if let data = try? Data(contentsOf: fileURL) {
            let uti = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.png.identifier
            registerData(on: provider, typeIdentifier: uti, data: data)
        }
    }

}

// MARK: - Note Drag Payload

enum NoteDragPayload {
    static let typeIdentifier = "com.cider.note-id"
    static let textPrefix = "cider-note-id:"

    nonisolated private static func registerData(
        on provider: NSItemProvider,
        typeIdentifier: String,
        data: Data
    ) {
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            MainActor.assumeIsolated {
                completion(data, nil)
            }
            return nil
        }
    }

    static func noteID(from raw: String) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(textPrefix) {
            let idPortion = String(trimmed.dropFirst(textPrefix.count))
            return UUID(uuidString: idPortion)
        }
        return UUID(uuidString: trimmed)
    }

    @MainActor
    static func registerPublicFileURL(on provider: NSItemProvider, note: Note) {
        guard !note.relativePath.isEmpty else { return }
        let fileURL = StoragePaths.cachedDirectoryURL(for: .notes).appendingPathComponent(note.relativePath)
        registerData(on: provider, typeIdentifier: UTType.fileURL.identifier, data: fileURL.dataRepresentation)
    }
}

// MARK: - Multi-Drag Payload

enum MultiDragPayload {
    static let typeIdentifier = "com.cider.multi-drag"
    static let textPrefix = "cider-multi-drag:"

    struct Item: Codable {
        let type: String
        let id: UUID
    }

    struct Payload: Codable {
        let items: [Item]
    }

    static func encode(items: [Item]) -> Data? {
        try? JSONEncoder().encode(Payload(items: items))
    }

    static func decode(from data: Data) -> [Item]? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return payload.items
    }

    static func encodeToText(items: [Item]) -> String? {
        guard let data = encode(items: items),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "\(textPrefix)\(json)"
    }

    static func decodeFromText(_ text: String) -> [Item]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(textPrefix) else { return nil }
        let json = String(trimmed.dropFirst(textPrefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return decode(from: data)
    }
}

// MARK: - Multi-Drag Helper

enum CiderMultiDrag {
    nonisolated private static func registerData(
        on provider: NSItemProvider,
        typeIdentifier: String,
        data: Data
    ) {
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            MainActor.assumeIsolated {
                completion(data, nil)
            }
            return nil
        }
    }

    @MainActor
    static func makeProvider(
        primaryType: String,
        primaryID: UUID,
        allItemIDs: [(type: String, id: UUID)],
        primaryBookmark: Bookmark? = nil,
        primaryNote: Note? = nil
    ) -> NSItemProvider {
        let items = allItemIDs.map { MultiDragPayload.Item(type: $0.type, id: $0.id) }
        let textPayload = MultiDragPayload.encodeToText(items: items) ?? ""
        let provider = NSItemProvider(object: textPayload as NSString)

        if let data = MultiDragPayload.encode(items: items) {
            registerData(on: provider, typeIdentifier: MultiDragPayload.typeIdentifier, data: data)
        }

        // Register external types for the primary item so external apps get useful data.
        // NOTE: Do NOT register public.file-url for notes — it breaks .onDrop.
        if let bookmark = primaryBookmark {
            BookmarkDragPayload.registerPublicURL(on: provider, urlString: bookmark.urlString)
            BookmarkDragPayload.registerPublicImage(on: provider, bookmark: bookmark)
        }

        return provider
    }

    static func parseSelectedItemIDs(_ ids: Set<String>) -> [(type: String, id: UUID)] {
        ids.compactMap { selectedID in
            if selectedID.hasPrefix("bookmark-"),
               let uuid = UUID(uuidString: String(selectedID.dropFirst("bookmark-".count))) {
                return ("bookmark", uuid)
            }
            if selectedID.hasPrefix("note-"),
               let uuid = UUID(uuidString: String(selectedID.dropFirst("note-".count))) {
                return ("note", uuid)
            }
            if selectedID.hasPrefix("datecard-"),
               let uuid = UUID(uuidString: String(selectedID.dropFirst("datecard-".count))) {
                return ("datecard", uuid)
            }
            if selectedID.hasPrefix("contact-"),
               let uuid = UUID(uuidString: String(selectedID.dropFirst("contact-".count))) {
                return ("contact", uuid)
            }
            return nil
        }
    }
}

// MARK: - Multi-Drag Preview Item

enum MultiDragPreviewItem {
    case bookmark(Bookmark)
    case note(Note)
}

// MARK: - Bookmark Drag Preview

struct BookmarkDragPreview: View {
    let bookmark: Bookmark

    private var previewShape: some Shape {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }

    private var thumbnailShape: some Shape {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
    }

    private var gradientPair: (Color, Color) {
        BookmarkVisualStyle.gradient(for: bookmark)
    }

    /// Bookmark has an image — Option key exports image to external apps
    private var hasImageExportHint: Bool {
        (bookmark.originalImageFileURL != nil || bookmark.thumbnailFileURL != nil)
            && CiderConfig.load().showDragModeHints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let image = loadedThumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [gradientPair.0, gradientPair.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Text(String(bookmark.hostDisplay.prefix(1)).uppercased())
                            .font(CiderFont.heroFallback)
                            .foregroundColor(CiderColors.textOnColor)
                    }
                }
            }
            .frame(height: BookmarksDesign.dragPreviewThumbnailHeight)
            .clipShape(thumbnailShape)

            Text(bookmark.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            if hasImageExportHint {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "option")
                        .font(CiderFont.captionSemibold)
                    Text("for image")
                        .font(CiderFont.captionSemibold)
                }
                .foregroundColor(CiderColors.secondary)
            }
        }
        .padding(Spacing.xs)
        .frame(width: BookmarksDesign.dragPreviewWidth)
        .background(
            previewShape
                .fill(CiderColors.overlayDark)
        )
        .overlay(
            previewShape
                .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
        .padding(.top, Spacing.xxl)
        .padding(.trailing, BookmarksDesign.dragPreviewPaddingBleed)
        .scaleEffect(BookmarksDesign.dragPreviewScale)
        .rotationEffect(.degrees(BookmarksDesign.dragPreviewRotation))
        .offset(
            x: BookmarksDesign.dragPreviewXOffset,
            y: BookmarksDesign.dragPreviewYOffset
        )
    }

    private var loadedThumbnail: NSImage? {
        guard let filePath = bookmark.thumbnailFileURL?.path else { return nil }
        return NSImage(contentsOfFile: filePath)
    }
}

// MARK: - Note Drag Preview

struct NoteDragPreview: View {
    let note: Note

    private var previewShape: some Shape {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }

    private var iconShape: some Shape {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            iconShape
                .fill(CiderColors.accentSubtle)
                .frame(height: BookmarksDesign.dragPreviewThumbnailHeight)
                .overlay {
                    Image(systemName: "doc.text.fill")
                        .font(CiderFont.dragPreviewIcon)
                        .foregroundColor(CiderColors.controlAccent)
                }

            Text(note.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
        .padding(Spacing.xs)
        .frame(width: BookmarksDesign.dragPreviewWidth)
        .background(
            previewShape
                .fill(CiderColors.overlayDark)
        )
        .overlay(
            previewShape
                .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
        .padding(.top, Spacing.xxl)
        .padding(.trailing, BookmarksDesign.dragPreviewPaddingBleed)
        .scaleEffect(BookmarksDesign.dragPreviewScale)
        .rotationEffect(.degrees(BookmarksDesign.dragPreviewRotation))
        .offset(
            x: BookmarksDesign.dragPreviewXOffset,
            y: BookmarksDesign.dragPreviewYOffset
        )
    }
}

// MARK: - Multi-Drag Preview

struct MultiDragPreview: View {
    let items: [MultiDragPreviewItem]
    let totalCount: Int

    private var previewShape: some Shape {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }

    private var thumbnailShape: some Shape {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
    }

    var body: some View {
        let displayItems = Array(items.prefix(3))
        let backItems = Array(displayItems.dropFirst())
        let maxFan = CGFloat(backItems.count)
        let extraX = maxFan * BookmarksDesign.multiDragFanXStep
        let extraY = maxFan * BookmarksDesign.multiDragFanYStep

        ZStack(alignment: .topLeading) {
            ForEach(Array(backItems.enumerated().reversed()), id: \.offset) { reverseIndex, item in
                let fanIndex = backItems.count - reverseIndex
                miniCard(for: item)
                    .offset(
                        x: CGFloat(fanIndex) * BookmarksDesign.multiDragFanXStep,
                        y: CGFloat(fanIndex) * BookmarksDesign.multiDragFanYStep
                    )
                    .rotationEffect(.degrees(Double(fanIndex) * BookmarksDesign.multiDragFanRotationStep))
            }

            miniCard(for: displayItems[0])
                .overlay(alignment: .topTrailing) {
                    if totalCount > 3 {
                        countBadge
                    }
                }
        }
        .padding(.top, BookmarksDesign.dragPreviewPaddingBleed)
        .padding(.trailing, extraX + BookmarksDesign.dragPreviewPaddingBleed)
        .padding(.bottom, extraY + BookmarksDesign.dragPreviewPaddingBleed)
        .scaleEffect(BookmarksDesign.dragPreviewScale)
        .rotationEffect(.degrees(BookmarksDesign.dragPreviewRotation))
        .offset(
            x: BookmarksDesign.dragPreviewXOffset,
            y: BookmarksDesign.dragPreviewYOffset
        )
    }

    @ViewBuilder
    private func miniCard(for item: MultiDragPreviewItem) -> some View {
        switch item {
        case .bookmark(let bookmark):
            bookmarkMiniCard(bookmark: bookmark)
        case .note(let note):
            noteMiniCard(note: note)
        }
    }

    private func bookmarkMiniCard(bookmark: Bookmark) -> some View {
        let gradientPair = BookmarkVisualStyle.gradient(for: bookmark)

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let filePath = bookmark.thumbnailFileURL?.path,
                   let image = NSImage(contentsOfFile: filePath) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [gradientPair.0, gradientPair.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Text(String(bookmark.hostDisplay.prefix(1)).uppercased())
                            .font(CiderFont.heroFallback)
                            .foregroundColor(CiderColors.textOnColor)
                    }
                }
            }
            .frame(height: BookmarksDesign.dragPreviewThumbnailHeight)
            .clipShape(thumbnailShape)

            Text(bookmark.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
        .padding(Spacing.xs)
        .frame(width: BookmarksDesign.dragPreviewWidth)
        .background(previewShape.fill(CiderColors.overlayDark))
        .overlay(previewShape.stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth))
        .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
    }

    private func noteMiniCard(note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.accentSubtle)
                .frame(height: BookmarksDesign.dragPreviewThumbnailHeight)
                .overlay {
                    Image(systemName: "doc.text.fill")
                        .font(CiderFont.dragPreviewIcon)
                        .foregroundColor(CiderColors.controlAccent)
                }

            Text(note.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
        .padding(Spacing.xs)
        .frame(width: BookmarksDesign.dragPreviewWidth)
        .background(previewShape.fill(CiderColors.overlayDark))
        .overlay(previewShape.stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth))
        .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
    }

    private var countBadge: some View {
        Text("\(totalCount)")
            .font(CiderFont.captionSemibold)
            .foregroundColor(CiderColors.textOnColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(CiderColors.controlAccent))
            .padding(Spacing.xs)
    }
}

// MARK: - Cider Draggable View Extension

extension View {
    @ViewBuilder
    func ciderDraggable<Preview: View>(
        _ provider: (() -> NSItemProvider)?,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        if let provider {
            onDrag(provider, preview: preview)
        } else {
            self
        }
    }

    @ViewBuilder
    func ciderDraggable(_ provider: (() -> NSItemProvider)?) -> some View {
        if let provider {
            onDrag {
                provider()
            }
        } else {
            self
        }
    }
}

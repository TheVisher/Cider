import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Internal Drag State

@MainActor
enum CiderInternalDragState {
    private static let activeWindow: TimeInterval = 20
    private static var lastStartedAt: Date?

    static func markStarted() {
        lastStartedAt = Date()
    }

    static var isActive: Bool {
        guard let lastStartedAt else { return false }
        return Date().timeIntervalSince(lastStartedAt) < activeWindow
    }
}

// MARK: - Bookmark Drag Payload

enum BookmarkDragPayload {
    static let typeIdentifier = "com.cider.bookmark-id"
    static let textPrefix = "cider-bookmark-id:"

    static func bookmarkID(from raw: String) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(textPrefix) {
            let idPortion = String(trimmed.dropFirst(textPrefix.count))
            return UUID(uuidString: idPortion)
        }
        return UUID(uuidString: trimmed)
    }

    static func imageExportURL(for bookmark: Bookmark) -> URL? {
        for fileURL in [bookmark.originalImageFileURL, bookmark.thumbnailFileURL].compactMap(\.self) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return nil
    }

    static func suggestedImageExportName(title: String, fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension
        let fallback = fileURL.deletingPathExtension().lastPathComponent
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return fallback }
        guard !fileExtension.isEmpty else { return trimmedTitle }

        let titleExtension = (trimmedTitle as NSString).pathExtension
        let base = imageExtensionsMatch(titleExtension, fileExtension)
            ? (trimmedTitle as NSString).deletingPathExtension
            : trimmedTitle

        guard !base.isEmpty else { return fallback }
        return base
    }

    static func suggestedImageExportFileName(title: String, fileURL: URL) -> String {
        let base = suggestedImageExportName(title: title, fileURL: fileURL)
        let fileExtension = fileURL.pathExtension
        guard !fileExtension.isEmpty else { return base }
        return "\(base).\(fileExtension)"
    }

    private static func imageExtensionsMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedImageExtension(lhs) == normalizedImageExtension(rhs)
    }

    private static func normalizedImageExtension(_ value: String) -> String {
        let lowercased = value.lowercased()
        return lowercased == "jpeg" ? "jpg" : lowercased
    }
}

// MARK: - Note Drag Payload

enum NoteDragPayload {
    static let typeIdentifier = "com.cider.note-id"
    static let textPrefix = "cider-note-id:"
    static let markdownTypeIdentifier = UTType(filenameExtension: "md")?.identifier
        ?? "net.daringfireball.markdown"

    static func noteID(from raw: String) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(textPrefix) {
            let idPortion = String(trimmed.dropFirst(textPrefix.count))
            return UUID(uuidString: idPortion)
        }
        return UUID(uuidString: trimmed)
    }

    @MainActor
    static func makeMarkdownFileProvider(for note: Note) -> NSItemProvider? {
        guard let fileURL = markdownExportURL(for: note) else { return nil }

        let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
        provider.suggestedName = markdownExportName(for: note, fileURL: fileURL)

        return provider
    }

    @MainActor
    static func makeInternalProvider(for note: Note) -> NSItemProvider {
        let provider = NSItemProvider(
            object: "\(textPrefix)\(note.id.uuidString)" as NSString
        )
        return provider
    }

    static func markdownExportURL(for note: Note) -> URL? {
        guard !note.relativePath.isEmpty else { return nil }
        let fileURL = note.relativePath.hasPrefix("/")
            ? URL(fileURLWithPath: note.relativePath)
            : note.absoluteFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    static func markdownExportName(for note: Note, fileURL: URL) -> String {
        let fallback = fileURL.deletingPathExtension().lastPathComponent
        let base = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return fallback }
        return (base as NSString).pathExtension.lowercased() == "md"
            ? (base as NSString).deletingPathExtension
            : base
    }

    static func markdownExportFileName(for note: Note, fileURL: URL) -> String {
        "\(markdownExportName(for: note, fileURL: fileURL)).md"
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
            onDrag {
                CiderInternalDragState.markStarted()
                return provider()
            } preview: {
                preview()
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func ciderDraggable(_ provider: (() -> NSItemProvider)?) -> some View {
        if let provider {
            onDrag {
                CiderInternalDragState.markStarted()
                return provider()
            }
        } else {
            self
        }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    static func registerPublicURL(on provider: NSItemProvider, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.url.identifier, visibility: .all
        ) { completion in
            completion(url.dataRepresentation, nil)
            return nil
        }
    }
}

// MARK: - Note Drag Payload

enum NoteDragPayload {
    static let typeIdentifier = "com.cider.note-id"
    static let textPrefix = "cider-note-id:"

    static func noteID(from raw: String) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(textPrefix) {
            let idPortion = String(trimmed.dropFirst(textPrefix.count))
            return UUID(uuidString: idPortion)
        }
        return UUID(uuidString: trimmed)
    }

    static func registerPublicFileURL(on provider: NSItemProvider, note: Note) {
        guard !note.relativePath.isEmpty else { return }
        let dir = NSString(string: StoragePaths.notesDirectoryPath).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: dir).appendingPathComponent(note.relativePath)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier, visibility: .all
        ) { completion in
            completion(fileURL.dataRepresentation, nil)
            return nil
        }
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
    static func makeProvider(
        primaryType: String,
        primaryID: UUID,
        allItemIDs: [(type: String, id: UUID)]
    ) -> NSItemProvider {
        let items = allItemIDs.map { MultiDragPayload.Item(type: $0.type, id: $0.id) }
        let textPayload = MultiDragPayload.encodeToText(items: items) ?? ""
        let provider = NSItemProvider(object: textPayload as NSString)

        if let data = MultiDragPayload.encode(items: items) {
            provider.registerDataRepresentation(
                forTypeIdentifier: MultiDragPayload.typeIdentifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
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
        .padding(.top, 24)
        .padding(.trailing, 40)
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
                        .font(.system(size: 32, weight: .medium))
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
        .padding(.top, 24)
        .padding(.trailing, 40)
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
        .padding(.top, 40)
        .padding(.trailing, extraX + 40)
        .padding(.bottom, extraY + 40)
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
                        .font(.system(size: 32, weight: .medium))
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

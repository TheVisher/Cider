import AppKit
import SwiftUI

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
        .scaleEffect(BookmarksDesign.dragPreviewScale)
        .rotationEffect(.degrees(BookmarksDesign.dragPreviewRotation))
        .offset(
            x: BookmarksDesign.dragPreviewXOffset,
            y: BookmarksDesign.dragPreviewYOffset
        )
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

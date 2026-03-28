import AppKit
import PDFKit
import QuickLookThumbnailing
import SwiftUI

// MARK: - Shared Thumbnail Cache

/// Shared cache for vault file thumbnails — prevents re-decoding from disk on every scan/rebuild.
@MainActor
final class VaultFileThumbnailCache {
    static let shared = VaultFileThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 200 }

    func get(_ relativePath: String, modifiedAt: Date) -> NSImage? {
        let key = "\(relativePath):\(modifiedAt.timeIntervalSince1970)" as NSString
        return cache.object(forKey: key)
    }

    func set(_ image: NSImage, for relativePath: String, modifiedAt: Date) {
        let key = "\(relativePath):\(modifiedAt.timeIntervalSince1970)" as NSString
        cache.setObject(image, forKey: key)
    }
}

// MARK: - Card View (Grid / Masonry)

struct VaultFileCardView: View {
    let file: VaultFile
    var onOpen: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

    @Environment(\.hideCardFooters) private var hideCardFooters
    @Environment(\.showCardDetailsOnHover) private var showCardDetailsOnHover
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var thumbnailAspectRatio: CGFloat?

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
        Button {
            handleClick { onOpen?() }
        } label: {
            if file.fileType == .image {
                imageCardContent
            } else {
                genericCardContent
            }
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .hoverState($isHovered, animation: .snappy)
        .contextMenu {
            Button("Open in Finder") { openInFinder() }
            Button("Open with Default App") { openWithDefaultApp() }

            Divider()

            if !folders.isEmpty {
                Menu("Move to Folder") {
                    Button("Unfiled") { onMoveToFolder?(nil) }
                    Divider()
                    ForEach(folders) { folder in
                        Button(folder.name) { onMoveToFolder?(folder.id) }
                    }
                }
            }

            if !CardLabelStorage.shared.labels.isEmpty {
                Menu("Tags") {
                    ForEach(CardLabelStorage.shared.labels) { label in
                        let hasTag = file.labelIDs.contains(label.id)
                        Button {
                            if isSelected {
                                onToggleLabelBulk?(label.id)
                            } else if hasTag {
                                VaultFileStorage.shared.removeLabel(file.id, labelID: label.id)
                                VaultFileService.shared.refreshMetadata()
                            } else {
                                VaultFileStorage.shared.assignLabel(file.id, labelID: label.id)
                                VaultFileService.shared.refreshMetadata()
                            }
                        } label: {
                            HStack {
                                Text(label.name)
                                if hasTag {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) { onDelete?() }
        }
        .task {
            await loadThumbnail()
        }
    }

    // MARK: - Image Card (full-bleed thumbnail with natural aspect ratio)

    private var imageCardContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Full-bleed thumbnail with hover overlay
            imageThumbnailArea
                .overlay(alignment: .bottom) {
                    if hideCardFooters && showCardDetailsOnHover && isHovered {
                        imageHoverOverlay
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            // Static footer (only when details are visible)
            if !hideCardFooters {
                imageFooter
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var imageThumbnailArea: some View {
        if let thumbnail {
            let ratio = thumbnailAspectRatio ?? 1.0
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(1 / ratio, contentMode: .fit)
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(CiderColors.surfaceInput)
                .frame(maxWidth: .infinity)
                .frame(height: VaultFileDesign.imageFallbackHeight)
                .overlay(
                    Image(systemName: "photo")
                        .font(CiderFont.vaultCardIcon)
                        .foregroundColor(CiderColors.tertiary)
                        .imageScale(.large)
                )
        }
    }

    /// Gradient overlay that slides up from the bottom on hover (matches BookmarkCard pattern).
    private var imageHoverOverlay: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(file.displayTitle)
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.textOnColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.xs) {
                Text(file.fileType.displayName)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.textOnColorDim)
                Text("\u{00B7}")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.textOnColorDim)
                Text(formattedSize)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.textOnColorDim)
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
    }

    /// Static footer shown below the thumbnail when details are visible.
    private var imageFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(file.displayTitle)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(2)

            HStack(spacing: Spacing.xs) {
                Text(file.fileType.displayName)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                Text("\u{00B7}")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                Text(formattedSize)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
    }

    // MARK: - Generic Card (non-image files)

    private var genericCardContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Thumbnail or icon
            genericThumbnailArea

            // Title
            Text(file.displayTitle)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(2)

            // File info row
            HStack(spacing: Spacing.xs) {
                Image(systemName: file.fileType.systemImageName)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .imageScale(.small)

                Text(file.fileType.displayName)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)

                Text("\u{00B7}")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)

                Text(formattedSize)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Generic Thumbnail

    @ViewBuilder
    private var genericThumbnailArea: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: VaultFileDesign.cardThumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(CiderColors.surfaceInput)
                .frame(maxWidth: .infinity)
                .frame(height: VaultFileDesign.cardThumbnailHeight)
                .overlay(
                    Image(systemName: file.fileType.systemImageName)
                        .font(CiderFont.vaultCardIcon)
                        .foregroundColor(CiderColors.tertiary)
                        .imageScale(.large)
                )
        }
    }

    // MARK: - Helpers

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
    }

    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([file.absoluteURL])
    }

    private func openWithDefaultApp() {
        NSWorkspace.shared.open(file.absoluteURL)
    }

    private func loadThumbnail() async {
        // Check shared cache first — avoids re-decoding on scan/tag/rebuild
        if let cached = VaultFileThumbnailCache.shared.get(file.relativePath, modifiedAt: file.modifiedAt) {
            thumbnail = cached
            return
        }

        let url = file.absoluteURL
        switch file.fileType {
        case .image:
            let result: (NSImage, CGFloat)? = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                let w = CGFloat(cgImage.width)
                let h = CGFloat(cgImage.height)
                let aspectRatio = h / w
                return (NSImage(cgImage: cgImage, size: NSSize(width: w, height: h)), aspectRatio)
            }.value
            if let (image, ratio) = result {
                VaultFileThumbnailCache.shared.set(image, for: file.relativePath, modifiedAt: file.modifiedAt)
                thumbnail = image
                thumbnailAspectRatio = ratio
            }

        case .pdf:
            let pdfLoaded: NSImage? = await Task.detached(priority: .userInitiated) {
                guard let doc = PDFDocument(url: url),
                      let page = doc.page(at: 0) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let scale = min(400 / bounds.width, 400 / bounds.height)
                let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
                let image = NSImage(size: size)
                image.lockFocus()
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fill(CGRect(origin: .zero, size: size))
                    ctx.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: ctx)
                }
                image.unlockFocus()
                return image
            }.value
            if let pdfLoaded { VaultFileThumbnailCache.shared.set(pdfLoaded, for: file.relativePath, modifiedAt: file.modifiedAt) }
            thumbnail = pdfLoaded

        case .document, .archive, .unknown, .video, .audio:
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 400, height: 400),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            let qlLoaded: NSImage? = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            if let qlLoaded { VaultFileThumbnailCache.shared.set(qlLoaded, for: file.relativePath, modifiedAt: file.modifiedAt) }
            thumbnail = qlLoaded
        }
    }
}

// MARK: - List Row

struct VaultFileListRow: View {
    let file: VaultFile
    var onOpen: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

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
        Button {
            handleClick { onOpen?() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isSelected {
                    SelectionCheckmark()
                }

                Image(systemName: file.fileType.systemImageName)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: FolderSidebarItemDesign.folderIconSize)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(file.displayTitle)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(file.fileType.displayName)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)

                        Text("\u{00B7}")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.quaternary)

                        Text(formattedSize)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Spacer(minLength: Spacing.sm)

                Text(file.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(
                        isFocused ? CiderColors.controlAccent : (isSelected ? CiderColors.controlAccent : Color.clear),
                        lineWidth: isFocused ? CiderBorder.innerStrokeWidth : (isSelected ? CiderBorder.innerStrokeWidth : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.absoluteURL])
            }
            Button("Open with Default App") {
                NSWorkspace.shared.open(file.absoluteURL)
            }
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
    }
}

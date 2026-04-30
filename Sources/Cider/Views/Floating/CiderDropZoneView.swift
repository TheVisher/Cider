import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct CiderDropZoneView: View {
    private static let width: CGFloat = 340
    private static let height: CGFloat = 360

    @ObservedObject var context: CiderDropZoneContext

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            dropTarget
            recentDrops
            autoDismissProgress
        }
        .padding(Spacing.lg)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onAppear {
            context.resetDismissProgress()
        }
        .onDisappear {
            context.setHoverPaused(false)
        }
        .onDrop(
            of: CiderDropZoneDropDelegate.typeIdentifiers,
            delegate: CiderDropZoneDropDelegate(
                context: context
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 28, height: 28)
                .background(CiderColors.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(context.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
            }

            Spacer(minLength: Spacing.sm)

            Button {
                context.setPinned(!context.isPinned)
            } label: {
                Image(systemName: context.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(context.isPinned ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        context.isPinned ? CiderColors.accentSubtle : CiderColors.surfaceInput,
                        in: RoundedRectangle(cornerRadius: Radius.sm)
                    )
            }
            .buttonStyle(.plain)
            .help(context.isPinned ? "Unpin Drop Zone" : "Pin Drop Zone")
        }
    }

    private var dropTarget: some View {
        ZStack {
            VStack(spacing: Spacing.sm) {
                Image(systemName: context.isDropTargeted ? "plus.circle.fill" : "plus.circle")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(context.isDropTargeted ? CiderColors.controlAccent : CiderColors.secondary)

                Text(context.status.message)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CiderDropZonePasteboardDropView(context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(context.isDropTargeted ? CiderColors.dropTargetFill : CiderColors.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(
                    context.isDropTargeted ? CiderColors.dropTargetBorderStrong : CiderColors.borderSubtle,
                    style: StrokeStyle(lineWidth: CiderBorder.innerStrokeWidth, dash: [6, 5])
                )
        )
    }

    private var recentDrops: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            if context.droppedItems.isEmpty {
                Text("No drops yet.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
            } else {
                CiderDropZoneRecentList(items: Array(context.droppedItems.prefix(8)))
            }
        }
        .frame(height: 108, alignment: .top)
        .clipped()
    }

    private struct CiderDropZoneRecentList: View {
        let items: [CiderDropZoneContext.DroppedItem]

        var body: some View {
            ScrollView(.vertical) {
                VStack(spacing: Spacing.xs) {
                    ForEach(items) { item in
                        CiderDropZoneRecentRow(item: item)
                    }
                }
                .padding(.trailing, Spacing.xs)
            }
            .frame(height: 78)
            .scrollIndicators(.never)
        }
    }

    private var autoDismissProgress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(CiderColors.borderSelected)

                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(CiderColors.accentSolid)
                    .frame(width: proxy.size.width * max(0, min(1, context.dismissProgress)))
            }
        }
        .frame(height: 3)
        .opacity(context.isPinned ? 0 : 1)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var statusColor: Color {
        switch context.status {
        case .success:
            return CiderColors.success
        case .fallback:
            return CiderColors.warning
        case .failure:
            return CiderColors.destructive
        case .targeted, .processing:
            return CiderColors.controlAccent
        case .idle:
            return CiderColors.secondary
        }
    }
}

private struct CiderDropZonePasteboardDropView: NSViewRepresentable {
    let context: CiderDropZoneContext

    func makeNSView(context: Context) -> CiderDropZonePasteboardDropTarget {
        CiderDropZonePasteboardDropTarget(dropZoneContext: self.context)
    }

    func updateNSView(_ nsView: CiderDropZonePasteboardDropTarget, context: Context) {
        nsView.dropZoneContext = self.context
    }
}

private final class CiderDropZonePasteboardDropTarget: NSView {
    var dropZoneContext: CiderDropZoneContext

    init(dropZoneContext: CiderDropZoneContext) {
        self.dropZoneContext = dropZoneContext
        super.init(frame: .zero)
        registerForDraggedTypes(CiderDropZonePasteboardReader.acceptedPasteboardTypes)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateTargeting(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateTargeting(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropZoneContext.setTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropZoneContext.setTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        CiderDropZonePasteboardReader.performDrop(
            from: sender.draggingPasteboard,
            context: dropZoneContext
        )
    }

    private func updateTargeting(for sender: NSDraggingInfo) -> NSDragOperation {
        let canHandle = CiderDropZonePasteboardReader.canHandle(sender.draggingPasteboard)
        dropZoneContext.setTargeted(canHandle)
        return canHandle ? .copy : []
    }
}

enum CiderDropZonePasteboardReader {
    private static let jpegPasteboardType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    private static let gifPasteboardType = NSPasteboard.PasteboardType("com.compuserve.gif")

    static let acceptedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .tiff,
        .png,
        jpegPasteboardType,
        gifPasteboardType
    ]

    static func canHandle(_ pasteboard: NSPasteboard) -> Bool {
        !fileURLs(from: pasteboard).isEmpty
            || url(from: pasteboard) != nil
            || imageData(from: pasteboard) != nil
            || text(from: pasteboard) != nil
    }

    @discardableResult
    @MainActor
    static func performDrop(
        from pasteboard: NSPasteboard,
        context: CiderDropZoneContext
    ) -> Bool {
        if let fileURL = fileURLs(from: pasteboard).first {
            if CiderDropZoneImageFile.shouldSaveAsImageBookmark(fileURL) {
                context.saveDroppedImageFile(fileURL)
            } else {
                context.saveDroppedFile(fileURL)
            }
            return true
        }

        if let url = url(from: pasteboard) {
            context.saveDroppedURL(url)
            return true
        }

        if let payload = imageData(from: pasteboard) {
            context.saveDroppedImageData(
                payload.data,
                preferredFileExtension: payload.preferredFileExtension
            )
            return true
        }

        if let text = text(from: pasteboard) {
            context.saveDroppedText(text)
            return true
        }

        context.finishDropGesture()
        context.status = .failure("Drop type is not supported yet.")
        return false
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]

        if let urls, !urls.isEmpty {
            return urls
        }

        guard let rawFileURL = pasteboard.string(forType: .fileURL),
              let url = URL(string: rawFileURL),
              url.isFileURL else {
            return []
        }
        return [url]
    }

    static func url(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: { !$0.isFileURL }) {
            return url
        }

        let rawValue = pasteboard.string(forType: .URL)
            ?? pasteboard.string(forType: .string)

        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              !url.isFileURL else {
            return nil
        }
        return url
    }

    static func imageData(from pasteboard: NSPasteboard) -> CiderDropZoneImagePayload? {
        let candidates: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"),
            (jpegPasteboardType, "jpg"),
            (gifPasteboardType, "gif"),
            (.tiff, "tiff")
        ]

        for (type, preferredExtension) in candidates {
            guard let data = pasteboard.data(forType: type),
                  let payload = CiderDropZoneImageData.normalizedPayload(
                    from: data,
                    preferredFileExtension: preferredExtension
                  ) else {
                continue
            }
            return payload
        }

        return nil
    }

    static func text(from pasteboard: NSPasteboard) -> String? {
        guard let rawValue = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return rawValue
    }
}

private struct CiderDropZoneRecentRow: View {
    @ObservedObject private var bookmarkService = VaultBookmarkService.shared
    let item: CiderDropZoneContext.DroppedItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(item.didPersist ? CiderColors.success : CiderColors.warning)
                .frame(width: 22, height: 22)
                .background(CiderColors.surfaceInput, in: RoundedRectangle(cornerRadius: Radius.xs))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.resolvedTitle(from: bookmarkService.bookmarks))
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Text(item.detail)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(CiderColors.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var symbolName: String {
        switch item.kind {
        case .bookmark:
            return "link"
        case .file:
            return "doc"
        case .image:
            return "photo"
        case .text:
            return "text.alignleft"
        }
    }
}

private struct CiderDropZoneDropDelegate: DropDelegate {
    static let typeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        UTType.image.identifier,
        UTType.tiff.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier
    ]

    let context: CiderDropZoneContext

    func validateDrop(info: DropInfo) -> Bool {
        !providers(info).isEmpty
    }

    func dropEntered(info: DropInfo) {
        context.setTargeted(validateDrop(info: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            context.setTargeted(false)
            return nil
        }
        context.setTargeted(true)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        context.setTargeted(false)
    }

    func performDrop(info: DropInfo) -> Bool {
        context.finishDropGesture()
        let providers = providers(info)
        guard !providers.isEmpty else { return false }
        loadFirstSupportedItem(from: providers)
        return true
    }

    private func providers(_ info: DropInfo) -> [NSItemProvider] {
        info.itemProviders(for: Self.typeIdentifiers)
    }

    private func loadFirstSupportedItem(from providers: [NSItemProvider]) {
        for provider in providers {
            if loadFileURL(from: provider) { return }
        }

        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                Task { @MainActor in
                    context.saveDroppedURL(url)
                }
            }
            return
        }

        for provider in providers {
            if loadImageFileRepresentation(from: provider) { return }
        }

        for provider in providers where provider.canLoadObject(ofClass: NSImage.self) {
            let imageTitle = CiderDropZoneImageTitle.title(fromSuggestedName: provider.suggestedName)
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage,
                      let payload = CiderDropZoneImageData.normalizedPayload(from: image) else { return }
                Task { @MainActor in
                    context.saveDroppedImageData(
                        payload.data,
                        preferredFileExtension: payload.preferredFileExtension,
                        title: imageTitle
                    )
                }
            }
            return
        }

        for provider in providers {
            if loadData(from: provider, typeIdentifier: UTType.url.identifier, as: .url) { return }
            if loadData(from: provider, typeIdentifier: UTType.png.identifier, as: .image("png")) { return }
            if loadData(from: provider, typeIdentifier: UTType.jpeg.identifier, as: .image("jpg")) { return }
            if loadData(from: provider, typeIdentifier: UTType.tiff.identifier, as: .image("tiff")) { return }
            if loadData(from: provider, typeIdentifier: UTType.plainText.identifier, as: .text) { return }
            if loadData(from: provider, typeIdentifier: UTType.text.identifier, as: .text) { return }
        }

        Task { @MainActor in
            context.status = .failure("Drop type is not supported yet.")
        }
    }

    private func loadFileURL(from provider: NSItemProvider) -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                guard let url = CiderDropZoneURLData.url(from: data) else {
                    context.status = .failure("Dropped file could not be read.")
                    return
                }

                guard CiderDropZoneImageFile.shouldSaveAsImageBookmark(url) else {
                    context.saveDroppedURL(url)
                    return
                }

                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }

                do {
                    let imageData = try Data(contentsOf: url)
                    guard let payload = CiderDropZoneImageData.normalizedPayload(
                        from: imageData,
                        preferredFileExtension: url.pathExtension
                    ) else {
                        context.saveDroppedFile(url)
                        return
                    }

                    context.saveDroppedImageData(
                        payload.data,
                        preferredFileExtension: payload.preferredFileExtension,
                        title: CiderDropZoneImageTitle.title(fromFileURL: url)
                    )
                } catch {
                    context.saveDroppedFile(url)
                }
            }
        }
        return true
    }

    private func loadImageFileRepresentation(from provider: NSItemProvider) -> Bool {
        guard let imageTypeIdentifier = CiderDropZoneImageFile.imageTypeIdentifier(from: provider.registeredTypeIdentifiers) else {
            return false
        }

        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: imageTypeIdentifier) { url, _ in
            guard let url else { return }
            let title = CiderDropZoneImageTitle.title(
                fromSuggestedName: suggestedName,
                fileURL: url
            )

            do {
                let imageData = try Data(contentsOf: url)
                guard let payload = CiderDropZoneImageData.normalizedPayload(
                    from: imageData,
                    preferredFileExtension: url.pathExtension
                ) else {
                    return
                }

                Task { @MainActor in
                    context.saveDroppedImageData(
                        payload.data,
                        preferredFileExtension: payload.preferredFileExtension,
                        title: title
                    )
                }
            } catch {
                Task { @MainActor in
                    context.status = .failure("Dropped image could not be read.")
                }
            }
        }
        return true
    }

    private enum DataRoute {
        case url
        case text
        case image(String)
    }

    private func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String,
        as route: DataRoute
    ) -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return false }

        let imageTitle = CiderDropZoneImageTitle.title(fromSuggestedName: provider.suggestedName)
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                switch route {
                case .url:
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        context.saveDroppedURL(url)
                    } else if let rawValue = decodedString(from: data),
                              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        context.saveDroppedURL(url)
                    } else {
                        context.status = .failure("Dropped URL could not be read.")
                    }
                case .text:
                    if let text = decodedString(from: data) {
                        context.saveDroppedText(text)
                    } else {
                        context.status = .failure("Dropped text could not be read.")
                    }
                case .image(let preferredExtension):
                    if let payload = CiderDropZoneImageData.normalizedPayload(
                        from: data,
                        preferredFileExtension: preferredExtension
                    ) {
                        context.saveDroppedImageData(
                            payload.data,
                            preferredFileExtension: payload.preferredFileExtension,
                            title: imageTitle
                        )
                    } else {
                        context.status = .failure("Dropped image could not be read.")
                    }
                }
            }
        }
        return true
    }

    private func decodedString(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }
}

struct CiderDropZoneImagePayload {
    let data: Data
    let preferredFileExtension: String
}

enum CiderDropZoneImageTitle {
    static func title(fromSuggestedName suggestedName: String?) -> String {
        guard let suggestedName else { return "Dropped Image" }
        let trimmed = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Dropped Image" }

        let basename = (trimmed as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return basename.isEmpty ? trimmed : basename
    }

    static func title(fromFileURL url: URL) -> String {
        title(fromSuggestedName: url.lastPathComponent)
    }

    static func title(fromSuggestedName suggestedName: String?, fileURL: URL) -> String {
        let suggestedTitle = title(fromSuggestedName: suggestedName)
        if suggestedTitle != "Dropped Image" {
            return suggestedTitle
        }

        return title(fromFileURL: fileURL)
    }
}

enum CiderDropZoneURLData {
    static func url(from data: Data) -> URL? {
        if let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }

        guard let rawValue = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        return URL(string: rawValue)
    }
}

enum CiderDropZoneImageFile {
    static func shouldSaveAsImageBookmark(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    static func imageTypeIdentifier(from identifiers: [String]) -> String? {
        identifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
        }
    }
}

enum CiderDropZoneImageData {
    static let maxPersistableBytes = 12_000_000

    private static let candidateMaxDimensions: [CGFloat] = [2400, 1800, 1200]
    private static let jpegCompressionFactors: [CGFloat] = [0.9, 0.75, 0.6]

    static func normalizedPayload(
        from data: Data,
        preferredFileExtension: String?
    ) -> CiderDropZoneImagePayload? {
        if data.count < maxPersistableBytes,
           NSImage(data: data) != nil,
           let ext = normalizedExtension(preferredFileExtension) {
            return CiderDropZoneImagePayload(data: data, preferredFileExtension: ext)
        }

        guard let image = NSImage(data: data) else { return nil }
        return normalizedPayload(from: image)
    }

    static func normalizedPayload(from image: NSImage) -> CiderDropZoneImagePayload? {
        for maxDimension in candidateMaxDimensions {
            guard let rep = bitmapRepresentation(for: image, maxDimension: maxDimension) else {
                continue
            }

            if let png = rep.representation(using: .png, properties: [:]),
               png.count < maxPersistableBytes {
                return CiderDropZoneImagePayload(data: png, preferredFileExtension: "png")
            }

            for compression in jpegCompressionFactors {
                if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: compression]),
                   jpeg.count < maxPersistableBytes {
                    return CiderDropZoneImagePayload(data: jpeg, preferredFileExtension: "jpg")
                }
            }
        }

        return nil
    }

    private static func bitmapRepresentation(for image: NSImage, maxDimension: CGFloat) -> NSBitmapImageRep? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let scale = min(1, maxDimension / max(sourceWidth, sourceHeight))
        let targetWidth = max(1, Int((sourceWidth * scale).rounded()))
        let targetHeight = max(1, Int((sourceHeight * scale).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight).fill()
        NSImage(cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
            .draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()

        return rep
    }

    private static func normalizedExtension(_ value: String?) -> String? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "jpeg":
            return "jpg"
        case "jpg", "png", "gif", "tiff", "tif", "webp", "heic":
            return value.lowercased()
        default:
            return nil
        }
    }
}

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

private func dropZoneImageSourceContext(
    sourceFile: String?,
    preferredFileExtension: String?
) -> CaptureSourceContext {
    let filename = sourceFile.map { URL(fileURLWithPath: $0).lastPathComponent }
    let mimeType = preferredFileExtension.map { "image/\($0.lowercased())" }
    let attachment = CaptureSourceContext.Attachment(
        filename: filename,
        mimeType: mimeType,
        localPath: sourceFile
    )
    let hasAttachmentMetadata = filename != nil || mimeType != nil || sourceFile != nil

    return CaptureSourceContext(
        surface: "drop_zone",
        attachments: hasAttachmentMetadata ? [attachment] : []
    )
}

@MainActor
final class CiderDropZoneContext: ObservableObject {
    enum DropStatus: Equatable {
        case idle
        case targeted
        case processing(String)
        case success(String)
        case fallback(String)
        case failure(String)

        var message: String {
            switch self {
            case .idle:
                return "Drop files, links, text, or images"
            case .targeted:
                return "Release to add to Cider"
            case .processing(let message),
                 .success(let message),
                 .fallback(let message),
                 .failure(let message):
                return message
            }
        }
    }

    struct DroppedItem: Identifiable, Equatable {
        enum Kind: String {
            case bookmark = "Bookmark"
            case file = "File"
            case image = "Image"
            case text = "Text"
        }

        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
        let didPersist: Bool
        let bookmarkID: UUID?

        init(
            kind: Kind,
            title: String,
            detail: String,
            didPersist: Bool,
            bookmarkID: UUID? = nil
        ) {
            self.kind = kind
            self.title = title
            self.detail = detail
            self.didPersist = didPersist
            self.bookmarkID = bookmarkID
        }

        func resolvedTitle(from bookmarks: [Bookmark]) -> String {
            guard let bookmarkID,
                  let bookmark = bookmarks.first(where: { $0.id == bookmarkID }) else {
                return title
            }
            let trimmed = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? title : trimmed
        }
    }

    @Published var status: DropStatus = .idle
    @Published private(set) var isPinned = false
    @Published private(set) var dismissProgress: CGFloat = 1
    @Published private(set) var isDropTargeted = false
    @Published private(set) var isHoverPaused = false
    @Published private(set) var droppedItems: [DroppedItem] = []

    let title: String
    let subtitle: String
    private var suppressTargetingUntil: Date?
    private let noteCaptureHandler: (String) throws -> CiderCaptureResult
    private let fileCaptureHandler: (URL) throws -> CiderCaptureResult
    private let imageBookmarkCaptureHandler: (String, Data, String?, String?) throws -> CiderCaptureResult

    init(
        title: String = "Drop Zone",
        subtitle: String = "Quickly toss things into Cider.",
        noteCaptureHandler: @escaping (String) throws -> CiderCaptureResult = {
            try CiderCaptureService().addNoteCapture(
                title: nil,
                content: $0,
                folderID: nil,
                sourceContext: CaptureSourceContext(surface: "drop_zone", originalText: $0)
            )
        },
        fileCaptureHandler: @escaping (URL) throws -> CiderCaptureResult = {
            try CiderCaptureService().addFileCapture(
                sourcePath: $0.path,
                title: nil,
                folderID: nil,
                sourceContext: CaptureSourceContext(
                    surface: "drop_zone",
                    attachments: [
                        CaptureSourceContext.Attachment(
                            filename: $0.lastPathComponent,
                            localPath: $0.path
                        )
                    ]
                )
            )
        },
        imageBookmarkCaptureHandler: @escaping (String, Data, String?, String?) throws -> CiderCaptureResult = {
            try CiderCaptureService().addImageBookmarkCapture(
                title: $0,
                imageData: $1,
                preferredFileExtension: $2,
                sourceFile: $3,
                sourceContext: dropZoneImageSourceContext(sourceFile: $3, preferredFileExtension: $2)
            )
        }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.noteCaptureHandler = noteCaptureHandler
        self.fileCaptureHandler = fileCaptureHandler
        self.imageBookmarkCaptureHandler = imageBookmarkCaptureHandler
    }

    static func manualTesting() -> CiderDropZoneContext {
        CiderDropZoneContext(
            title: "Drop Zone",
            subtitle: "Manual test surface for floatable intake."
        )
    }

    func setTargeted(_ isTargeted: Bool, now: Date = Date()) {
        if isTargeted, isSuppressingTargetUpdates(now: now) {
            isDropTargeted = false
            if status == .targeted {
                status = .idle
            }
            return
        }

        isDropTargeted = isTargeted
        if isTargeted {
            status = .targeted
        } else if status == .targeted {
            status = .idle
        }
    }

    func finishDropGesture(now: Date = Date()) {
        finishDropInteraction(now: now)
    }

    func setPinned(_ isPinned: Bool) {
        self.isPinned = isPinned
        if isPinned {
            resetDismissProgress()
        }
    }

    func setHoverPaused(_ isHoverPaused: Bool) {
        self.isHoverPaused = isHoverPaused
    }

    var shouldPauseAutoDismiss: Bool {
        shouldPauseAutoDismiss(isMouseInsideWindow: isHoverPaused)
    }

    func shouldPauseAutoDismiss(isMouseInsideWindow: Bool) -> Bool {
        if isPinned || isMouseInsideWindow || isDropTargeted {
            return true
        }
        if case .processing = status {
            return true
        }
        return false
    }

    func resetDismissProgress() {
        dismissProgress = 1
    }

    func advanceDismissProgress(by amount: CGFloat, isPaused: Bool) {
        guard !isPaused else { return }
        dismissProgress = max(0, dismissProgress - amount)
    }

    @discardableResult
    func tickAutoDismiss(by amount: CGFloat, isMouseInsideWindow: Bool) -> Bool {
        setHoverPaused(isMouseInsideWindow)
        advanceDismissProgress(
            by: amount,
            isPaused: shouldPauseAutoDismiss(isMouseInsideWindow: isMouseInsideWindow)
        )
        return dismissProgress <= 0 && !isPinned
    }

    func recordFallback(kind: DroppedItem.Kind, title: String, detail: String) {
        finishDropInteraction()
        resetDismissProgress()
        droppedItems.insert(
            DroppedItem(kind: kind, title: title, detail: detail, didPersist: false),
            at: 0
        )
        status = .fallback("Prototype captured it locally. Nothing was moved.")
    }

    func saveDroppedText(_ rawValue: String) {
        finishDropInteraction()
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetDismissProgress()
            status = .failure("Dropped text was empty.")
            return
        }

        if saveBookmarkIfPossible(trimmed) {
            return
        }

        resetDismissProgress()
        status = .processing("Saving text as a note...")
        do {
            let result = try noteCaptureHandler(trimmed)
            droppedItems.insert(
                DroppedItem(
                    kind: .text,
                    title: result.item.title,
                    detail: result.item.relativePath ?? trimmed,
                    didPersist: true
                ),
                at: 0
            )
            status = .success("Saved text as note.")
        } catch {
            recordFallback(
                kind: .text,
                title: String(trimmed.prefix(60)),
                detail: "Could not save note: \(error.localizedDescription)"
            )
        }
    }

    func saveDroppedURL(_ url: URL) {
        finishDropInteraction()
        if url.isFileURL {
            saveDroppedFile(url)
            return
        }

        if saveBookmarkIfPossible(url.absoluteString) {
            return
        }

        recordFallback(
            kind: .text,
            title: url.absoluteString,
            detail: "URL scheme is not currently routed by the prototype."
        )
    }

    func saveDroppedFile(_ url: URL) {
        finishDropInteraction()
        resetDismissProgress()
        status = .processing("Copying file into the vault inbox...")

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            status = .failure("Dropped file could not be read.")
            return
        }

        do {
            let result = try fileCaptureHandler(url)
            droppedItems.insert(
                DroppedItem(
                    kind: VaultFileType.from(extension: url.pathExtension) == .image ? .image : .file,
                    title: result.item.title,
                    detail: result.item.relativePath ?? url.lastPathComponent,
                    didPersist: true
                ),
                at: 0
            )
            status = .success("Saved \(result.item.title) to Inbox.")
        } catch {
            recordFallback(
                kind: .file,
                title: url.lastPathComponent,
                detail: "Could not save file: \(error.localizedDescription)"
            )
        }
    }

    func saveDroppedImageData(
        _ data: Data,
        preferredFileExtension: String? = nil,
        title: String = "Dropped Image",
        sourceFile: String? = nil
    ) {
        finishDropInteraction()
        resetDismissProgress()
        status = .processing("Saving dropped image...")
        let result: CiderCaptureResult
        do {
            result = try imageBookmarkCaptureHandler(title, data, preferredFileExtension, sourceFile)
        } catch {
            recordFallback(
                kind: .image,
                title: title,
                detail: "Could not save image bookmark: \(error.localizedDescription)"
            )
            return
        }
        let didAssignThumbnail = result.partialSuccess?.status != "thumbnail_assignment_failed"

        droppedItems.insert(
            DroppedItem(
                kind: .image,
                title: result.item.title,
                detail: didAssignThumbnail ? "Saved as an image bookmark." : "Created image bookmark, but thumbnail save failed.",
                didPersist: true,
                bookmarkID: result.item.id
            ),
            at: 0
        )
        status = didAssignThumbnail
            ? .success("Saved dropped image.")
            : .fallback("Created image bookmark without a thumbnail.")

        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "message": didAssignThumbnail ? "Saved dropped image" : "Saved image placeholder",
                "isSuccess": didAssignThumbnail
            ]
        )
    }

    func saveDroppedImageFile(_ url: URL) {
        finishDropInteraction()
        resetDismissProgress()
        status = .processing("Saving dropped image...")

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            status = .failure("Dropped image could not be read.")
            return
        }

        do {
            let imageData = try Data(contentsOf: url)
            guard let payload = CiderDropZoneImageData.normalizedPayload(
                from: imageData,
                preferredFileExtension: url.pathExtension
            ) else {
                saveDroppedFile(url)
                return
            }

            saveDroppedImageData(
                payload.data,
                preferredFileExtension: payload.preferredFileExtension,
                title: CiderDropZoneImageTitle.title(fromFileURL: url),
                sourceFile: url.path
            )
        } catch {
            saveDroppedFile(url)
        }
    }

    private func saveBookmarkIfPossible(_ rawValue: String) -> Bool {
        guard VaultBookmarkService.shared.previewNormalizedURLString(from: rawValue) != nil else {
            return false
        }

        resetDismissProgress()
        status = .processing("Saving bookmark...")
        guard let bookmark = try? CiderBookmarkCaptureAdapter()
            .addURLBookmark(
                urlString: rawValue,
                sourceContext: CaptureSourceContext(
                    surface: "drop_zone",
                    originalText: rawValue
                )
            )
            .bookmark else {
            resetDismissProgress()
            status = .failure("That URL could not be saved.")
            return true
        }

        droppedItems.insert(
            DroppedItem(
                kind: .bookmark,
                title: bookmark.title,
                detail: bookmark.urlString,
                didPersist: true,
                bookmarkID: bookmark.id
            ),
            at: 0
        )
        status = .success("Saved bookmark.")
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "message": "Saved dropped URL",
                "isSuccess": true
            ]
        )
        return true
    }

    private func finishDropInteraction(now: Date = Date()) {
        suppressTargetingUntil = now.addingTimeInterval(1)
        isDropTargeted = false
        isHoverPaused = false
        if status == .targeted {
            status = .idle
        }
    }

    private func isSuppressingTargetUpdates(now: Date) -> Bool {
        guard let suppressTargetingUntil else { return false }
        if now < suppressTargetingUntil {
            return true
        }
        self.suppressTargetingUntil = nil
        return false
    }

}

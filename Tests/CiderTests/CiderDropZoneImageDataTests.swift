import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Cider

struct CiderDropZoneImageDataTests {
    @MainActor
    private func makeContext() -> CiderDropZoneContext {
        CiderDropZoneContext(
            title: "Drop Zone",
            subtitle: "Manual test surface for floatable intake.",
            noteCaptureHandler: { text in
                captureResult(
                    itemType: "note",
                    title: String(text.prefix(60)),
                    relativePath: "Inbox/Notes/Test.md"
                )
            },
            fileCaptureHandler: { url in
                captureResult(
                    itemType: "vaultFile",
                    title: url.lastPathComponent,
                    relativePath: "Inbox/Files/\(url.lastPathComponent)"
                )
            }
        )
    }

    private func captureResult(
        itemType: String,
        title: String,
        relativePath: String
    ) -> CiderCaptureResult {
        let id = UUID()
        let target = CiderCaptureResult.Target(
            kind: "inbox",
            name: "Inbox",
            relativePath: (relativePath as NSString).deletingLastPathComponent,
            folderID: nil
        )
        return CiderCaptureResult(
            command: "capture.add",
            source: .init(kind: "text", url: nil, file: nil, text: title, itemID: id, itemType: itemType),
            item: .init(id: id, type: itemType, title: title, relativePath: relativePath, folderID: nil, folderName: target.name),
            enrichment: .init(status: "not_applicable", isEnriching: false, titleState: "manual", lastEnrichedAt: nil),
            duplicate: .init(status: "not_checked", existingItemID: nil),
            routing: .init(decisionID: UUID(), candidateTarget: target, reviewNeeded: true, confidence: 0, reason: "test", reviewState: "needs_review"),
            nextSafeAction: "review_route"
        )
    }

    @Test("drop zone context can be pinned open")
    @MainActor
    func dropZoneContextCanBePinnedOpen() {
        let context = makeContext()

        #expect(context.isPinned == false)
        #expect(context.dismissProgress == 1)
        context.setPinned(true)
        #expect(context.isPinned == true)
        #expect(context.dismissProgress == 1)
        context.setPinned(false)
        #expect(context.isPinned == false)
    }

    @Test("drop zone dismiss progress counts down only when not paused")
    @MainActor
    func dropZoneDismissProgressCountsDownOnlyWhenNotPaused() {
        let context = makeContext()

        context.advanceDismissProgress(by: 0.25, isPaused: false)
        #expect(context.dismissProgress == 0.75)

        context.advanceDismissProgress(by: 0.25, isPaused: true)
        #expect(context.dismissProgress == 0.75)

        context.resetDismissProgress()
        #expect(context.dismissProgress == 1)
    }

    @Test("drop zone auto dismiss uses the live panel hover state instead of stale hover flags")
    @MainActor
    func dropZoneAutoDismissIgnoresStaleHoverWhenMouseIsOutside() {
        let context = makeContext()

        context.setHoverPaused(true)
        #expect(context.isHoverPaused == true)

        let shouldClose = context.tickAutoDismiss(by: 0.25, isMouseInsideWindow: false)

        #expect(shouldClose == false)
        #expect(context.isHoverPaused == false)
        #expect(context.dismissProgress == 0.75)
    }

    @Test("drop zone auto dismiss pauses while the mouse is inside the panel")
    @MainActor
    func dropZoneAutoDismissPausesWhileMouseIsInsidePanel() {
        let context = makeContext()

        let shouldClose = context.tickAutoDismiss(by: 0.25, isMouseInsideWindow: true)

        #expect(shouldClose == false)
        #expect(context.isHoverPaused == true)
        #expect(context.dismissProgress == 1)
    }

    @Test("drop zone hover pause can resume dismiss progress after exit")
    @MainActor
    func dropZoneHoverPauseCanResumeDismissProgressAfterExit() {
        let context = makeContext()

        context.setHoverPaused(true)
        #expect(context.isHoverPaused == true)
        context.advanceDismissProgress(by: 0.25, isPaused: context.shouldPauseAutoDismiss)
        #expect(context.dismissProgress == 1)

        context.setHoverPaused(false)
        #expect(context.isHoverPaused == false)
        context.advanceDismissProgress(by: 0.25, isPaused: context.shouldPauseAutoDismiss)
        #expect(context.dismissProgress == 0.75)
    }

    @Test("drop zone leaving a drag target restores idle without erasing saved statuses")
    @MainActor
    func dropZoneLeavingDragTargetRestoresOnlyTargetedStatus() {
        let context = makeContext()

        context.setTargeted(true)
        #expect(context.status == .targeted)
        #expect(context.isDropTargeted == true)

        context.setTargeted(false)
        #expect(context.status == .idle)
        #expect(context.isDropTargeted == false)

        context.recordFallback(kind: .text, title: "Captured", detail: "Detail")
        context.setTargeted(false)
        #expect(context.status == .fallback("Prototype captured it locally. Nothing was moved."))
    }

    @Test("saving a dropped item clears targeted state so auto dismiss can resume")
    @MainActor
    func savingDroppedItemClearsTargetedState() {
        let context = makeContext()

        context.setTargeted(true)
        context.setHoverPaused(true)
        context.saveDroppedText("plain note from drop zone")

        #expect(context.isDropTargeted == false)
        #expect(context.isHoverPaused == false)
        #expect(context.shouldPauseAutoDismiss == false)
    }

    @Test("saving a dropped item restarts the visible auto dismiss countdown")
    @MainActor
    func savingDroppedItemRestartsVisibleAutoDismissCountdown() {
        let context = makeContext()

        context.advanceDismissProgress(by: 0.5, isPaused: false)
        #expect(context.dismissProgress == 0.5)

        context.saveDroppedText("plain note from drop zone")

        #expect(context.dismissProgress == 1)
    }

    @Test("completed drops ignore stale targeted updates from the drop delegate")
    @MainActor
    func completedDropsIgnoreStaleTargetedUpdates() {
        let context = makeContext()
        let now = Date(timeIntervalSince1970: 1_000)

        context.setTargeted(true, now: now)
        context.finishDropGesture(now: now)
        context.setTargeted(true, now: now.addingTimeInterval(0.5))

        #expect(context.isDropTargeted == false)
        #expect(context.status == .idle)

        context.setTargeted(true, now: now.addingTimeInterval(1.5))

        #expect(context.isDropTargeted == true)
        #expect(context.status == .targeted)
    }

    @Test("dropped bookmark items resolve enriched titles from bookmark snapshots")
    func droppedBookmarkItemsResolveEnrichedTitles() {
        let bookmarkID = UUID()
        let item = CiderDropZoneContext.DroppedItem(
            kind: .bookmark,
            title: "Youtube.Com",
            detail: "https://www.youtube.com/watch?v=abc",
            didPersist: true,
            bookmarkID: bookmarkID
        )
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Actually useful video title",
            urlString: item.detail
        )

        #expect(item.resolvedTitle(from: [bookmark]) == "Actually useful video title")
        #expect(item.resolvedTitle(from: []) == "Youtube.Com")
    }

    @Test("status drop target accepts the same intake types as the drop zone")
    func statusDropTargetAcceptsDropZoneIntakeTypes() {
        #expect(CiderStatusDropTarget.acceptedTypeIdentifiers.contains(UTType.fileURL.identifier))
        #expect(CiderStatusDropTarget.acceptedTypeIdentifiers.contains(UTType.url.identifier))
        #expect(CiderStatusDropTarget.acceptedTypeIdentifiers.contains(UTType.image.identifier))
        #expect(CiderStatusDropTarget.acceptedTypeIdentifiers.contains(UTType.plainText.identifier))
    }

    @Test("raw NSImage drops are normalized into bounded decodable PNG data")
    func rawImageDropsNormalizeToBoundedPNGData() throws {
        let image = NSImage(size: NSSize(width: 2400, height: 1800))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2400, height: 1800).fill()
        NSColor.white.setFill()
        NSRect(x: 300, y: 300, width: 1800, height: 900).fill()
        image.unlockFocus()

        let payload = try #require(CiderDropZoneImageData.normalizedPayload(from: image))

        #expect(payload.preferredFileExtension == "png")
        #expect(payload.data.count < CiderDropZoneImageData.maxPersistableBytes)
        #expect(NSImage(data: payload.data) != nil)
    }

    @Test("image drop titles use the source filename without its extension")
    func imageDropTitlesUseSourceFilename() {
        #expect(CiderDropZoneImageTitle.title(fromSuggestedName: "Dashboard.png") == "Dashboard")
        #expect(CiderDropZoneImageTitle.title(fromFileURL: URL(fileURLWithPath: "/Users/test/Desktop/Dashboard.png")) == "Dashboard")
        #expect(CiderDropZoneImageTitle.title(
            fromSuggestedName: nil,
            fileURL: URL(fileURLWithPath: "/Users/test/Desktop/Library.jpeg")
        ) == "Library")
        #expect(CiderDropZoneImageTitle.title(fromSuggestedName: "  ") == "Dropped Image")
        #expect(CiderDropZoneImageTitle.title(fromSuggestedName: nil) == "Dropped Image")
    }

    @Test("desktop image files are routed as named image bookmarks")
    func desktopImageFilesRouteAsImageBookmarks() {
        #expect(CiderDropZoneImageFile.shouldSaveAsImageBookmark(URL(fileURLWithPath: "/Users/test/Desktop/Dashboard.png")))
        #expect(CiderDropZoneImageFile.shouldSaveAsImageBookmark(URL(fileURLWithPath: "/Users/test/Desktop/Dashboard.heic")))
        #expect(!CiderDropZoneImageFile.shouldSaveAsImageBookmark(URL(fileURLWithPath: "/Users/test/Desktop/Notes.pdf")))
    }

    @Test("image file representations are found from registered item provider types")
    func imageFileRepresentationsAreFoundFromRegisteredProviderTypes() {
        #expect(CiderDropZoneImageFile.imageTypeIdentifier(from: ["public.jpeg", "public.text"]) == "public.jpeg")
        #expect(CiderDropZoneImageFile.imageTypeIdentifier(from: ["public.file-url", "public.png"]) == "public.png")
        #expect(CiderDropZoneImageFile.imageTypeIdentifier(from: ["public.text"]) == nil)
    }

    @Test("drop zone file URL data decodes desktop file paths")
    func dropZoneFileURLDataDecodesDesktopFilePaths() throws {
        let fileURL = URL(fileURLWithPath: "/Users/test/Desktop/Dashboard.png")
        let decodedURL = try #require(CiderDropZoneURLData.url(from: fileURL.dataRepresentation))

        #expect(decodedURL == fileURL)
    }

    @Test("drop zone AppKit pasteboard reader preserves Finder image file URLs")
    func appKitPasteboardReaderPreservesFinderImageFileURLs() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CiderDropZoneImageFileURLTest"))
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let fileURL = URL(fileURLWithPath: "/Users/test/Desktop/Library.jpeg")
        #expect(pasteboard.writeObjects([fileURL as NSURL]))

        #expect(CiderDropZonePasteboardReader.fileURLs(from: pasteboard) == [fileURL])
    }
}

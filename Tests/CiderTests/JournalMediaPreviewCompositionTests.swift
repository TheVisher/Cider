import AppKit
import Foundation
import Testing
@testable import Cider

struct JournalMediaPreviewCompositionTests {
    @Test("production Journal media card routes available originals through canonical native file detail")
    func productionCompositionUsesNativePreviewRoute() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let journalView = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/Journal/JournalLibraryViews.swift"),
            encoding: .utf8
        )
        let detailComposition = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+DetailViews.swift"),
            encoding: .utf8
        )

        #expect(journalView.contains("onOpenCanonicalItem(source.canonicalItemRef)"))
        #expect(journalView.contains("guard source.isOriginalAvailable else { return }"))
        #expect(journalView.contains("Original unavailable"))
        #expect(journalView.contains("JournalMediaPhotoThumbnailView(source: source)"))
        #expect(journalView.contains("VaultFileThumbnailCache.shared.get("))
        #expect(journalView.contains("Task.detached(priority: .utility)"))
        #expect(detailComposition.contains("VaultFileDetailView(file:"))

        let source = JournalMediaSourceCard(
            id: "source",
            noteID: UUID(),
            timestamp24Hour: "11:42",
            capturedAt: Date(),
            kind: .photo,
            displayTitle: "Reflection Lake overlook",
            rawFilename: "IMG_8741.jpeg",
            sourceID: "discord:photo:1",
            mediaItemID: UUID(),
            relativePath: "Journal/Photos/IMG_8741.jpeg",
            isOriginalAvailable: true
        )
        #expect(source.canonicalItemRef.type == .vaultFile)
    }

    @Test("supported Journal audio follows existing VaultFile AVPlayer detail and unsupported audio keeps fallback")
    func productionCompositionUsesExistingAudioPreviewPolicy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let detailView = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/Shared/VaultFileDetailView.swift"),
            encoding: .utf8
        )

        #expect(detailView.contains("case .inlineVideo, .inlineAudio:"))
        #expect(detailView.contains("avPlayer = AVPlayer(url: url)"))
        #expect(detailView.contains("case .externalAudio:"))
        #expect(detailView.contains("ExternalAudioPreview(file: file)"))
        #expect(detailView.contains("CiderOpenPolicy.shared.openIfAllowed(.localFile(file.absoluteURL))"))

        let supported = VaultFile(
            id: UUID(),
            filename: "reflection.m4a",
            relativePath: "Journal/Audio/reflection.m4a",
            fileType: .audio,
            fileSize: 1,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )
        let unsupported = VaultFile(
            id: UUID(),
            filename: "reflection.ogg",
            relativePath: "Journal/Audio/reflection.ogg",
            fileType: .audio,
            fileSize: 1,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )
        #expect(VaultFileMediaPreviewPolicy.presentation(for: supported) == .inlineAudio)
        #expect(VaultFileMediaPreviewPolicy.presentation(for: unsupported) == .externalAudio)
    }

    @Test("Journal photo thumbnail loader downsamples a synthetic original off the presentation path")
    func photoThumbnailLoaderDecodesSyntheticOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-photo-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("synthetic.jpeg")
        let sourceImage = NSImage(size: NSSize(width: 8, height: 6))
        sourceImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 6)).fill()
        sourceImage.unlockFocus()
        let tiff = try #require(sourceImage.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        try data.write(to: original)

        let thumbnail = await JournalMediaPhotoThumbnailLoader.load(at: original)

        #expect(thumbnail != nil)
        #expect((thumbnail?.size.width ?? 0) > 0)
        #expect((thumbnail?.size.height ?? 0) > 0)
    }
}

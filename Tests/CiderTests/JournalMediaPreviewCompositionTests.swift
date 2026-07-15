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
}

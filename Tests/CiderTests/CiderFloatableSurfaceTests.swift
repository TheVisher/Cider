import Foundation
import Testing
@testable import Cider

struct CiderFloatableSurfaceTests {
    private var testingGuidePayload: KanbanTestingGuidePanelPayload {
        KanbanTestingGuidePanelPayload(
            boardID: "2afee0",
            boardName: "Cider",
            cardID: "abc123",
            cardTitle: "QA handoff",
            steps: [
                KanbanTestingGuideStep(id: "step-1", text: "Open Media."),
                KanbanTestingGuideStep(id: "step-2", text: "Confirm counts render."),
            ]
        )
    }

    @Test("floatable surfaces have stable keys and readable default titles")
    func surfacesProvideStableKeysAndTitles() {
        let noteID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let bookmarkID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let contactID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let fileID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

        #expect(CiderFloatableSurface.note(noteID).stableKey == "note:11111111-1111-1111-1111-111111111111")
        #expect(CiderFloatableSurface.bookmark(bookmarkID).stableKey == "bookmark:22222222-2222-2222-2222-222222222222")
        #expect(CiderFloatableSurface.bookmarkMetadata(bookmarkID).defaultTitle == "Bookmark Metadata")
        #expect(CiderFloatableSurface.contact(contactID).defaultTitle == "Contact")
        #expect(CiderFloatableSurface.vaultFile(fileID).stableKey == "vaultFile:77777777-7777-7777-7777-777777777777")
        #expect(CiderFloatableSurface.vaultFile(fileID).defaultTitle == "File")
        #expect(CiderFloatableSurface.clipboard.stableKey == "clipboard")
        #expect(CiderFloatableSurface.aiAssistant.defaultTitle == "Chat")
        #expect(CiderFloatableSurface.dropZone.defaultTitle == "Drop Zone")
        #expect(CiderFloatableSurface.kanbanTestingGuide(testingGuidePayload).stableKey == "kanbanTestingGuide:2afee0:abc123")
        #expect(CiderFloatableSurface.kanbanTestingGuide(testingGuidePayload).defaultTitle == "QA Companion")
    }

    @Test("notification names use cider floatable surface namespace")
    func notificationNamesUseFloatableSurfaceNamespace() {
        #expect(Notification.Name.floatCiderSurface.rawValue == "cider.floatCiderSurface")
        #expect(Notification.Name.dockCiderSurface.rawValue == "cider.dockCiderSurface")
        #expect(Notification.Name.showCiderDropZone.rawValue == "cider.showCiderDropZone")
    }

    @Test("manager resolves floatable surfaces from notification object and common userInfo keys")
    func managerResolvesSurfaceNotificationPayloads() {
        let noteID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let note = CiderFloatableSurface.note(noteID)
        let bookmark = CiderFloatableSurface.bookmarkMetadata(noteID)
        let todo = CiderFloatableSurface.todo(noteID)

        let objectNotification = Notification(name: .floatCiderSurface, object: note)
        let surfaceNotification = Notification(
            name: .floatCiderSurface,
            object: nil,
            userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: bookmark]
        )
        let compatibilityNotification = Notification(
            name: .dockCiderSurface,
            object: nil,
            userInfo: ["floatableSurface": todo]
        )

        #expect(CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: objectNotification) == note)
        #expect(CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: surfaceNotification) == bookmark)
        #expect(CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: compatibilityNotification) == todo)
    }

    @Test("manager bookkeeping reuses existing surfaces by stable key")
    @MainActor
    func managerBookkeepingReusesExistingSurfaceKeys() {
        let noteID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let first = CiderFloatableSurface.note(noteID)
        let second = CiderFloatableSurface.note(noteID)
        let metadata = CiderFloatableSurface.bookmarkMetadata(noteID)

        var bookkeeping = CiderFloatingPanelManager.Bookkeeping()

        #expect(bookkeeping.register(first) == .created)
        #expect(bookkeeping.register(second) == .reused)
        #expect(bookkeeping.register(metadata) == .created)
        #expect(bookkeeping.contains(first))
        #expect(bookkeeping.contains(second))
        #expect(bookkeeping.contains(metadata))
        #expect(bookkeeping.activeCount == 2)

        bookkeeping.unregister(first)

        #expect(!bookkeeping.contains(second))
        #expect(bookkeeping.contains(metadata))
        #expect(bookkeeping.activeCount == 1)
    }

    @Test("floating manager records recallable surfaces")
    @MainActor
    func floatingManagerRecordsRecallableSurfaces() {
        let manager = CiderFloatingPanelManager()
        let noteID = UUID()

        manager.recordRecallCandidate(.note(noteID))

        #expect(manager.recallCoordinator.lastRecallableSurface == .note(noteID))
    }

    @Test("floating manager ignores drop zone as recall candidate")
    @MainActor
    func floatingManagerIgnoresDropZoneRecall() {
        let manager = CiderFloatingPanelManager()

        manager.recordRecallCandidate(.dropZone)

        #expect(manager.recallCoordinator.lastRecallableSurface == nil)
    }

    @Test("floating manager smart recall falls back when no candidate exists")
    @MainActor
    func floatingManagerSmartRecallFallsBackWithoutCandidate() {
        let manager = CiderFloatingPanelManager()
        var didFallback = false

        manager.performSmartRecall {
            didFallback = true
        }

        #expect(didFallback)
    }

    @Test("floating bookmark metadata exposes useful detail sections")
    func floatingBookmarkMetadataBuildsUsefulSections() {
        let bookmark = Bookmark(
            title: "Useful thing",
            urlString: "https://example.com/path",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            notes: "A note worth reading",
            tags: ["research", "mac"],
            aiSummary: "Short AI summary",
            dominantColors: ["#112233", "#445566"],
            mediaType: .video,
            relativePath: "Inbox/Bookmarks/Useful thing.webloc",
            enrichmentStatus: "complete"
        )

        let metadata = FloatingBookmarkDetailMetadata(bookmark: bookmark, folderName: "Inbox")

        #expect(metadata.url == URL(string: "https://example.com/path"))
        #expect(metadata.notes == "A note worth reading")
        #expect(metadata.summary == "Short AI summary")
        #expect(metadata.tags == ["research", "mac"])
        #expect(metadata.folderName == "Inbox")
        #expect(metadata.mediaType == "Video")
        #expect(metadata.relativePath == "Inbox/Bookmarks/Useful thing.webloc")
        #expect(metadata.enrichmentStatus == "complete")
        #expect(metadata.colors == ["#112233", "#445566"])
    }

    @Test("floating bookmark metadata trims empty optional text")
    func floatingBookmarkMetadataTrimsEmptyOptionalText() {
        let bookmark = Bookmark(
            title: "Noisy",
            urlString: "not a url",
            notes: "   ",
            tags: [],
            aiSummary: "\n ",
            dominantColors: [],
            enrichmentStatus: ""
        )

        let metadata = FloatingBookmarkDetailMetadata(bookmark: bookmark, folderName: nil)

        #expect(metadata.url == nil)
        #expect(metadata.notes == nil)
        #expect(metadata.summary == nil)
        #expect(metadata.tags.isEmpty)
        #expect(metadata.folderName == nil)
        #expect(metadata.colors.isEmpty)
        #expect(metadata.enrichmentStatus == nil)
    }

    @Test("floating bookmark layout keeps metadata in a side rail when there is room")
    func floatingBookmarkLayoutUsesSideRailWhenWideEnough() {
        #expect(FloatingBookmarkDetailLayout.mode(for: 920) == .sideRail)
        #expect(FloatingBookmarkDetailLayout.mode(for: 640) == .stacked)
    }

    @Test("floating notes use editable editor chrome")
    func floatingNotePresentationUsesEditableEditorChrome() {
        let note = Note(title: "Editable note")

        let presentation = FloatingNoteDetailPresentation(note: note)

        #expect(presentation.title == "Editable note")
        #expect(presentation.usesInlineEditor)
        #expect(presentation.showsFormattingToolbar)
        #expect(presentation.showsMetadataToggle)
        #expect(!presentation.scrollsContent)
    }

    @Test("floating note panels default wide enough for editor chrome")
    func floatingNotePanelDefaultSizeFitsEditorChrome() {
        let noteID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        let size = CiderFloatingPanelLayout.defaultContentSize(for: .note(noteID))

        #expect(size.width >= 760)
        #expect(size.height >= 560)
    }

    @Test("floating QA companion panels default to checklist-friendly size")
    func floatingQACompanionPanelDefaultSizeFitsChecklist() {
        let size = CiderFloatingPanelLayout.defaultContentSize(for: .kanbanTestingGuide(testingGuidePayload))

        #expect(size.width >= 400)
        #expect(size.height >= 520)
    }

    @Test("floating metadata panels default wide enough for side rail")
    func floatingMetadataPanelDefaultSizeFitsSideRail() {
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let surfaces: [CiderFloatableSurface] = [
            .contact(id),
            .dateCard(id),
            .todo(id),
            .vaultFile(id)
        ]

        for surface in surfaces {
            let size = CiderFloatingPanelLayout.defaultContentSize(for: surface)

            #expect(size.width >= FloatingBookmarkDetailLayout.sideRailMinimumWidth)
            #expect(size.height >= 560)
        }
    }

    @Test("restored floating metadata frames expand from old narrow sizes")
    func restoredFloatingMetadataFrameExpandsOldNarrowSizes() {
        let id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let narrowFrame = NSRect(x: 10, y: 20, width: 420, height: 520)

        let restored = CiderFloatingPanelLayout.restoredFrame(narrowFrame, for: .contact(id))

        #expect(restored.origin == narrowFrame.origin)
        #expect(restored.width >= FloatingBookmarkDetailLayout.sideRailMinimumWidth)
        #expect(restored.height >= 560)
    }

    @Test("reanchor resolver accepts item and AI surfaces")
    func reanchorResolverAcceptsItemAndAISurfaces() {
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.note(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.bookmark(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.bookmarkMetadata(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.contact(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.dateCard(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.todo(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.vaultFile(UUID())))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.aiAssistant))
        #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.kanbanTestingGuide(testingGuidePayload)))
    }

    @Test("reanchor resolver rejects utility surfaces")
    func reanchorResolverRejectsUtilitySurfaces() {
        #expect(!CiderReanchorSurfaceResolver.canOpenInMainWindow(.dropZone))
        #expect(!CiderReanchorSurfaceResolver.canOpenInMainWindow(.clipboard))
    }

    @Test("vault file metadata presentation includes file-specific source and intelligence")
    func vaultFileMetadataPresentationIncludesFileSpecificDetails() {
        let file = VaultFile(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            filename: "Modern gradient C logo design.png",
            relativePath: "Inbox/Images/Modern gradient C logo design.png",
            fileType: .image,
            fileSize: 1_572_864,
            createdAt: Date(timeIntervalSince1970: 1_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000),
            folderID: nil,
            title: "Cider Logo",
            notes: "Useful brand image",
            tags: ["logo", "cider"],
            ocrText: "Modern gradient C logo",
            dominantColors: ["#FFAA00", "#111111", "  "]
        )

        let presentation = VaultFileMetadataPresentation(file: file)

        #expect(presentation.title == "Cider Logo")
        #expect(presentation.sourcePath == "Inbox/Images/Modern gradient C logo design.png")
        #expect(presentation.kind == "Image")
        #expect(presentation.fileType == "PNG")
        #expect(presentation.size == ByteCountFormatter.string(fromByteCount: 1_572_864, countStyle: .file))
        #expect(presentation.colors == ["#FFAA00", "#111111"])
        #expect(presentation.notes == "Useful brand image")
        #expect(presentation.ocrText == "Modern gradient C logo")
        #expect(presentation.keywords == ["logo", "cider"])
    }
}

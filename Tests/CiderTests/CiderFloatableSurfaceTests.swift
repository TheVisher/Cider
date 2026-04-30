import Foundation
import Testing
@testable import Cider

struct CiderFloatableSurfaceTests {
    @Test("floatable surfaces have stable keys and readable default titles")
    func surfacesProvideStableKeysAndTitles() {
        let noteID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let bookmarkID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let contactID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        #expect(CiderFloatableSurface.note(noteID).stableKey == "note:11111111-1111-1111-1111-111111111111")
        #expect(CiderFloatableSurface.bookmark(bookmarkID).stableKey == "bookmark:22222222-2222-2222-2222-222222222222")
        #expect(CiderFloatableSurface.bookmarkMetadata(bookmarkID).defaultTitle == "Bookmark Metadata")
        #expect(CiderFloatableSurface.contact(contactID).defaultTitle == "Contact")
        #expect(CiderFloatableSurface.clipboard.stableKey == "clipboard")
        #expect(CiderFloatableSurface.aiAssistant.defaultTitle == "AI Assistant")
        #expect(CiderFloatableSurface.dropZone.defaultTitle == "Drop Zone")
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
}

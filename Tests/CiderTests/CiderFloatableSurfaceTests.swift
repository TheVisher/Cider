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
}

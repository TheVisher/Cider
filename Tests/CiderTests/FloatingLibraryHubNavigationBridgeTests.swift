import Foundation
import Testing
@testable import Cider

struct FloatingLibraryHubNavigationBridgeTests {
    @Test("floating hub bridge posts safe query targets for main-window routing")
    func floatingHubBridgePostsSafeQueryTargets() throws {
        let notificationCenter = NotificationCenter()
        let target = LibraryHubNavigationTarget.query("World of Warcraft")
        let capturedTarget = CapturedHubNavigationTarget()

        let observer = notificationCenter.addObserver(
            forName: .openCiderLibraryHubNavigationTargetInMainWindow,
            object: nil,
            queue: nil
        ) { notification in
            capturedTarget.set(LibraryHubNavigationRequest.target(from: notification))
        }
        defer { notificationCenter.removeObserver(observer) }

        let handler = try #require(LibraryHubNavigationRequest.floatingPanelHandler(notificationCenter: notificationCenter))
        handler(target)

        #expect(capturedTarget.value == .query("World of Warcraft"))
    }

    @Test("floating hub bridge posts safe item targets for linked-ref opening")
    func floatingHubBridgePostsSafeItemTargets() throws {
        let notificationCenter = NotificationCenter()
        let ref = LibraryEntityRef(
            type: .bookmark,
            entityID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let capturedTarget = CapturedHubNavigationTarget()

        let observer = notificationCenter.addObserver(
            forName: .openCiderLibraryHubNavigationTargetInMainWindow,
            object: nil,
            queue: nil
        ) { notification in
            capturedTarget.set(LibraryHubNavigationRequest.target(from: notification))
        }
        defer { notificationCenter.removeObserver(observer) }

        let handler = try #require(LibraryHubNavigationRequest.floatingPanelHandler(notificationCenter: notificationCenter))
        handler(.item(ref))

        #expect(capturedTarget.value == .item(ref))
    }

    @Test("floating hub bridge stays disabled when no main-window callback is available")
    func floatingHubBridgeStaysDisabledWithoutCallback() {
        let handler = LibraryHubNavigationRequest.floatingPanelHandler(isAvailable: false)

        #expect(handler == nil)
    }

    @Test("floating hub bridge ignores malformed notifications")
    func floatingHubBridgeIgnoresMalformedNotifications() {
        let notification = Notification(
            name: .openCiderLibraryHubNavigationTargetInMainWindow,
            object: "cider-cli item hub --accept --json"
        )

        #expect(LibraryHubNavigationRequest.target(from: notification) == nil)
    }
}

private final class CapturedHubNavigationTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: LibraryHubNavigationTarget?

    var value: LibraryHubNavigationTarget? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ target: LibraryHubNavigationTarget?) {
        lock.lock()
        storedValue = target
        lock.unlock()
    }
}

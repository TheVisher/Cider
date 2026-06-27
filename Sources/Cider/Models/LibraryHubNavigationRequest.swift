import Foundation

enum LibraryHubNavigationRequest {
    static let targetUserInfoKey = "libraryHubNavigationTarget"

    static func floatingPanelHandler(
        isAvailable: Bool = true,
        notificationCenter: NotificationCenter = .default
    ) -> ((LibraryHubNavigationTarget) -> Void)? {
        guard isAvailable else { return nil }
        return { target in
            postOpenRequest(target, notificationCenter: notificationCenter)
        }
    }

    static func postOpenRequest(
        _ target: LibraryHubNavigationTarget,
        notificationCenter: NotificationCenter = .default
    ) {
        guard target.readOnly, !target.promotesTruth else { return }
        notificationCenter.post(
            name: .openCiderLibraryHubNavigationTargetInMainWindow,
            object: target,
            userInfo: [targetUserInfoKey: target]
        )
    }

    static func target(from notification: Notification) -> LibraryHubNavigationTarget? {
        let target = notification.userInfo?[targetUserInfoKey] as? LibraryHubNavigationTarget
            ?? notification.object as? LibraryHubNavigationTarget
        guard let target, target.readOnly, !target.promotesTruth else { return nil }
        return target
    }
}

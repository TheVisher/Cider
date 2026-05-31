import Foundation

enum CiderExternalOpenBridge {
    static let notificationName = Notification.Name("cider.externalOpenRequest")

    enum Key {
        static let requestID = "requestID"
        static let targetType = "targetType"
        static let targetID = "targetID"
        static let title = "title"
        static let boardID = "boardID"
        static let boardName = "boardName"
        static let sourceType = "sourceType"
        static let sourceRef = "sourceRef"
        static let requestedAt = "requestedAt"
    }

    @discardableResult
    static func post(userInfo: [String: String]) -> Bool {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        return true
    }

    static func startForwardingToLocalNotificationCenter() -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            NotificationCenter.default.post(
                name: .openCiderExternalTarget,
                object: nil,
                userInfo: notification.userInfo
            )
        }
    }

    static func stopForwarding(_ observer: NSObjectProtocol?) {
        guard let observer else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
    }
}

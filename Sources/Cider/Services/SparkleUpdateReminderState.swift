import Foundation

struct SparkleUpdateReminderState: Equatable {
    var availableUpdateIdentifier: String?
    var sidebarRemindersEnabled: Bool
    var dismissedUpdateIdentifier: String?

    var shouldShowSidebarReminder: Bool {
        guard sidebarRemindersEnabled,
              let availableUpdateIdentifier,
              availableUpdateIdentifier.isEmpty == false else {
            return false
        }
        return availableUpdateIdentifier != dismissedUpdateIdentifier
    }
}

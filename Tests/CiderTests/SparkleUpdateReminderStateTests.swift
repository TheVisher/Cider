import XCTest
@testable import Cider

final class SparkleUpdateReminderStateTests: XCTestCase {
    func testReminderVisibleWhenUpdateAvailableEnabledAndNotDismissed() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.1-10",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: nil
        )

        XCTAssertTrue(state.shouldShowSidebarReminder)
    }

    func testReminderHiddenWhenSidebarRemindersDisabled() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.1-10",
            sidebarRemindersEnabled: false,
            dismissedUpdateIdentifier: nil
        )

        XCTAssertFalse(state.shouldShowSidebarReminder)
    }

    func testReminderHiddenAfterDismissingCurrentUpdate() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.1-10",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: "0.1.1-10"
        )

        XCTAssertFalse(state.shouldShowSidebarReminder)
    }

    func testReminderVisibleAgainForDifferentUpdateIdentifier() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.2-11",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: "0.1.1-10"
        )

        XCTAssertTrue(state.shouldShowSidebarReminder)
    }

    func testReminderStateUsesPersistedDismissalForExactIdentifierOnly() {
        let dismissedCurrent = SparkleUpdateReminderState(
            availableUpdateIdentifier: "1.0.0-100",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: "1.0.0-100"
        )
        let nextUpdate = SparkleUpdateReminderState(
            availableUpdateIdentifier: "1.0.1-101",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: "1.0.0-100"
        )

        XCTAssertFalse(dismissedCurrent.shouldShowSidebarReminder)
        XCTAssertTrue(nextUpdate.shouldShowSidebarReminder)
    }

    func testReminderHiddenWhenNoUpdateIsAvailable() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: nil,
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: nil
        )

        XCTAssertFalse(state.shouldShowSidebarReminder)
    }

    @MainActor
    func testServicePersistsDismissedSidebarUpdateIdentifier() {
        let suiteName = "SparkleUpdateReminderStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let service = SparkleUpdaterService(defaults: defaults)
        service.markUpdateAvailable(identifier: "1.0.0-100", displayVersion: "1.0.0")

        XCTAssertTrue(service.shouldShowSidebarUpdateReminder)

        service.dismissSidebarUpdateReminder(identifier: "1.0.0-100")

        XCTAssertFalse(service.shouldShowSidebarUpdateReminder)

        let reloadedService = SparkleUpdaterService(defaults: defaults)
        reloadedService.markUpdateAvailable(identifier: "1.0.0-100", displayVersion: "1.0.0")

        XCTAssertFalse(reloadedService.shouldShowSidebarUpdateReminder)

        reloadedService.markUpdateAvailable(identifier: "1.0.1-101", displayVersion: "1.0.1")

        XCTAssertTrue(reloadedService.shouldShowSidebarUpdateReminder)
    }
}

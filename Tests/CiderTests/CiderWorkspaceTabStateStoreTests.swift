import Foundation
import Testing
@testable import Cider

struct CiderWorkspaceTabStateStoreTests {
    @Test("Legacy AI assistant open state does not restore workspace navigation")
    func legacyAIAssistantOpenStateDoesNotRestoreWorkspaceNavigation() {
        let suiteName = "CiderWorkspaceTabStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = CiderWorkspaceTabStateStore(defaults: defaults)
        first.setAIAssistantTabOpen(true)

        let second = CiderWorkspaceTabStateStore(defaults: defaults)

        #expect(second.isAIAssistantTabOpen)
        #expect(second.restoredWorkspaceRoute() == nil)
    }

    @Test("closed AI assistant state restores no workspace route")
    func closedAIAssistantStateRestoresNoWorkspaceRoute() {
        let suiteName = "CiderWorkspaceTabStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CiderWorkspaceTabStateStore(defaults: defaults)
        store.setAIAssistantTabOpen(true)
        store.setAIAssistantTabOpen(false)

        #expect(store.isAIAssistantTabOpen == false)
        #expect(store.restoredWorkspaceRoute() == nil)
    }
}

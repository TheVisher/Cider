import Foundation
import Testing
@testable import Cider

struct CiderWorkspaceTabStateStoreTests {
    @Test("AI assistant open state restores as a workspace route")
    func aiAssistantOpenStateRestoresAsWorkspaceRoute() {
        let suiteName = "CiderWorkspaceTabStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = CiderWorkspaceTabStateStore(defaults: defaults)
        first.setAIAssistantTabOpen(true)

        let second = CiderWorkspaceTabStateStore(defaults: defaults)

        #expect(second.isAIAssistantTabOpen)
        #expect(second.restoredWorkspaceRoute() == .ai)
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

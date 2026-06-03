import Foundation

final class CiderWorkspaceTabStateStore: @unchecked Sendable {
    static let shared = CiderWorkspaceTabStateStore()

    private let defaults: UserDefaults
    private let aiAssistantTabOpenKey = "cider.workspaceTabs.aiAssistantOpen"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isAIAssistantTabOpen: Bool {
        defaults.bool(forKey: aiAssistantTabOpenKey)
    }

    func setAIAssistantTabOpen(_ isOpen: Bool) {
        defaults.set(isOpen, forKey: aiAssistantTabOpenKey)
    }

    func restoredWorkspaceRoute() -> WorkspaceRoute? {
        isAIAssistantTabOpen ? .ai : nil
    }
}

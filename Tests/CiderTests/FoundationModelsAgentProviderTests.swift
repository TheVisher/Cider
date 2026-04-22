import Foundation
import Testing
@testable import Cider

struct FoundationModelsAgentProviderTests {
    @Test("configured tool names only include allowed tools in stable order")
    func configuredToolNamesOnlyIncludeAllowedTools() {
        let allowedTools = [
            AgentToolDefinition(
                name: "searchItems",
                description: "Search items",
                parameters: [],
                categories: [.search],
                requiresConfirmation: false,
                execute: { _ in "" }
            ),
            AgentToolDefinition(
                name: "createReminder",
                description: "Create reminder",
                parameters: [],
                categories: [.reminder],
                requiresConfirmation: false,
                execute: { _ in "" }
            )
        ]

        let configured = FoundationModelsAgentProvider.configuredToolNames(for: allowedTools)

        #expect(configured == ["searchItems", "createReminder"])
        #expect(!configured.contains("deleteItem"))
    }

    @Test("configured tool names exclude unknown tool definitions")
    func configuredToolNamesExcludeUnknownTools() {
        let allowedTools = [
            AgentToolDefinition(
                name: "searchItems",
                description: "Search items",
                parameters: [],
                categories: [.search],
                requiresConfirmation: false,
                execute: { _ in "" }
            ),
            AgentToolDefinition(
                name: "imaginaryTool",
                description: "Not implemented by foundation models",
                parameters: [],
                categories: [.system],
                requiresConfirmation: false,
                execute: { _ in "" }
            )
        ]

        let configured = FoundationModelsAgentProvider.configuredToolNames(for: allowedTools)

        #expect(configured == ["searchItems"])
    }
}

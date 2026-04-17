import Testing
@testable import Cider

@MainActor
struct AIAssistantPromptTests {
    @Test("Foundation Models prompt includes vault routing doctrine")
    func foundationPromptIncludesRoutingDoctrine() {
        let provider = FoundationModelsProvider()
        let prompt = provider._buildInstructionsForTesting(context: AIAssistantContext())

        #expect(prompt.contains("Vault save routing rules:"))
        #expect(prompt.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(prompt.contains("If the destination is unclear, save to Inbox and explain why."))
    }

    @Test("MLX prompt includes vault routing doctrine")
    func mlxPromptIncludesRoutingDoctrine() {
        let provider = MLXProvider()
        let prompt = provider._buildSystemPromptForTesting(context: AIAssistantContext())

        #expect(prompt.contains("Vault save routing rules:"))
        #expect(prompt.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(prompt.contains("If the destination is unclear, save to Inbox and explain why."))
    }
}

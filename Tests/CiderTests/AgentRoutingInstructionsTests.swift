import Testing
@testable import Cider

struct AgentRoutingInstructionsTests {
    @Test("routing doctrine includes the core vault rules")
    func includesCoreVaultRules() {
        let text = AgentRoutingInstructions.vaultSaveRoutingDoctrine

        #expect(text.contains("Do not invent new top-level folders."))
        #expect(text.contains("Food"))
        #expect(text.contains("People"))
        #expect(text.contains("Inbox"))
        #expect(text.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(text.contains("If the destination is unclear, save to Inbox and explain why."))
    }
}

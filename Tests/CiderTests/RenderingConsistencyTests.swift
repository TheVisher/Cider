import Foundation
import Testing
@testable import Cider

@Suite("Rendering Consistency Tests")
struct RenderingConsistencyTests {
    @Test("Chat bubble render key changes when message content changes without resizing")
    func chatBubbleRenderKeyChangesForContentUpdate() {
        let messageID = UUID()
        let first = AIAssistantMessage(
            id: messageID,
            role: .assistant,
            content: "Working...",
            timestamp: Date(timeIntervalSince1970: 1),
            sourceID: "hermes:1"
        )
        let second = AIAssistantMessage(
            id: messageID,
            role: .assistant,
            content: "Done.\n\nThis answer is taller than the placeholder.",
            timestamp: Date(timeIntervalSince1970: 1),
            sourceID: "hermes:1"
        )

        #expect(
            AIAssistantRenderInvalidation.messageKey(first)
            != AIAssistantRenderInvalidation.messageKey(second)
        )
    }

    @Test("Chat list layout key stays stable across content and composer changes")
    func chatListLayoutKeyIgnoresVolatileContent() {
        let messageID = UUID()
        let first = AIAssistantMessage(
            id: messageID,
            role: .assistant,
            content: "Working...",
            timestamp: Date(timeIntervalSince1970: 1),
            sourceID: "hermes:1"
        )
        let second = AIAssistantMessage(
            id: messageID,
            role: .assistant,
            content: "Done.\n\nThis answer is taller than the placeholder.",
            timestamp: Date(timeIntervalSince1970: 1),
            sourceID: "hermes:1"
        )

        #expect(
            AIAssistantRenderInvalidation.listLayoutKey(
                messages: [first],
                width: 640
            )
            == AIAssistantRenderInvalidation.listLayoutKey(
                messages: [second],
                width: 640
            )
        )
    }

    @Test("Note editor refresh plan includes an immediate and delayed push")
    func noteEditorRefreshPlanRetriesAfterMount() {
        #expect(NotesEditorRenderRefreshPlan.delays.first == 0)
        #expect(NotesEditorRenderRefreshPlan.delays.contains(0.15))
        #expect(NotesEditorRenderRefreshPlan.delays.count >= 3)
    }
}

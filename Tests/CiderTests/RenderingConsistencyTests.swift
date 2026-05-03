import Foundation
import Testing
@testable import Cider

@Suite("Rendering Consistency Tests")
struct RenderingConsistencyTests {
    @Test("Chat render key changes when message content changes without resizing")
    func chatRenderKeyChangesForContentUpdate() {
        let messageID = UUID()
        let first = [
            AIAssistantMessage(
                id: messageID,
                role: .assistant,
                content: "Working...",
                timestamp: Date(timeIntervalSince1970: 1),
                sourceID: "hermes:1"
            )
        ]
        let second = [
            AIAssistantMessage(
                id: messageID,
                role: .assistant,
                content: "Done.\n\nThis answer is taller than the placeholder.",
                timestamp: Date(timeIntervalSince1970: 1),
                sourceID: "hermes:1"
            )
        ]

        #expect(
            AIAssistantRenderInvalidation.key(
                messages: first,
                width: 640,
                composerHeight: 64,
                streamingToken: nil
            )
            != AIAssistantRenderInvalidation.key(
                messages: second,
                width: 640,
                composerHeight: 64,
                streamingToken: nil
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

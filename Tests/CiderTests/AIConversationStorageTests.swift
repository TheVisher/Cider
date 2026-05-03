import Foundation
import Testing
@testable import Cider

struct AIConversationStorageTests {
    @Test("Hermes duplicate runtime rows collapse to the newest summary")
    @MainActor
    func hermesDuplicateRuntimeRowsCollapseToNewestSummary() {
        let older = makeSummary(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Main Brain older mirror",
            updated: Date(timeIntervalSince1970: 100),
            activeRuntimeSessionID: "session-a"
        )
        let newer = makeSummary(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Main Brain latest mirror",
            updated: Date(timeIntervalSince1970: 200),
            activeRuntimeSessionID: "session-a"
        )
        let fresh = makeSummary(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Fresh Hermes chat",
            updated: Date(timeIntervalSince1970: 150),
            activeRuntimeSessionID: "session-b"
        )

        let collapsed = AIConversationStorage.collapsingDuplicateHermesRuntimeSummaries([
            older,
            fresh,
            newer
        ])

        #expect(collapsed.map(\.id).contains(newer.id))
        #expect(collapsed.map(\.id).contains(fresh.id))
        #expect(!collapsed.map(\.id).contains(older.id))
        #expect(collapsed.count == 2)
    }

    private func makeSummary(
        id: UUID,
        title: String,
        updated: Date,
        activeRuntimeSessionID: String
    ) -> AIConversationSummary {
        AIConversationSummary(
            id: id,
            title: title,
            created: Date(timeIntervalSince1970: 0),
            updated: updated,
            messageCount: 2,
            filename: "\(id.uuidString).jsonl",
            runtimeID: CiderAgentChatRegistry.hermesRuntimeID,
            activeRuntimeSessionID: activeRuntimeSessionID,
            runtimeSessionLineage: [activeRuntimeSessionID],
            runtimeSource: "cider",
            runtimeLastSyncedAt: updated
        )
    }
}

import Foundation
import Testing
@testable import Cider

@Suite("Cider Item Context Service Tests")
@MainActor
struct CiderItemContextServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-context-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func insertItem(
        _ ref: LibraryEntityRef,
        title: String,
        relativePath: String?,
        into db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
            .bind(DatabaseHelpers.encode(Date()), at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
    }

    @Test("context bundle includes item identity, sections, chunks, and related items")
    func contextBundleIncludesIdentitySectionsChunksAndRelatedItems() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and check insurance first.",
                source: "test",
                sortOrder: 0
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Dentist follow-up",
                body: "Call the dentist and check insurance first.",
                chunkIndex: 0
            )
        ])

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(database: db, linkService: linkService, secondBrainStore: store)

        let bundle = try service.context(for: note)

        #expect(bundle.item.id == note.entityID)
        #expect(bundle.item.type == .note)
        #expect(bundle.item.title == "Dentist follow-up")
        #expect(bundle.item.relativePath == "Inbox/Notes/Dentist follow-up.md")
        #expect(bundle.sections.map(\.sectionKey) == ["summary"])
        #expect(bundle.chunks.map(\.body) == ["Call the dentist and check insurance first."])
        #expect(bundle.related.map(\.title) == ["Dental insurance portal"])
    }

    @Test("search returns item title matches and chunk text matches through one surface")
    func searchReturnsItemTitleMatchesAndChunkTextMatchesThroughOneSurface() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let dentist = LibraryEntityRef(type: .note, entityID: UUID())
        let renewal = LibraryEntityRef(type: .todo, entityID: UUID())
        try insertItem(dentist, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(renewal, title: "Review home insurance", relativePath: "Inbox/Todos/Review home insurance.md", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "todo", ownerID: renewal.entityID.uuidString)
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: renewal.entityID.uuidString,
                source: "test",
                title: "Insurance renewal",
                body: "The renewal window opens in September.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let titleMatches = try service.search("dentist", limit: 10)
        #expect(titleMatches.contains {
            $0.kind == .item && $0.item?.id == dentist.entityID && $0.title == "Dentist follow-up"
        })

        let chunkMatches = try service.search("renewal window", limit: 10)
        #expect(chunkMatches.contains {
            $0.kind == .chunk && $0.item?.id == renewal.entityID && $0.owner.ownerType == "todo"
        })
    }

    @Test("search handles common Kanban acceptance terms alongside item matches")
    func searchHandlesCommonKanbanAcceptanceTermsAlongsideItemMatches() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(
            note,
            title: "Cutover acceptance text",
            relativePath: "Inbox/Notes/Cutover acceptance text.md",
            into: db
        )

        let store = SecondBrainStore(database: db)
        let cardOwner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board/card")
        try store.replaceChunks(owner: cardOwner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: nil,
                source: "kanban_notes",
                title: "Acceptance Criteria",
                body: "Focused CLI acceptance checks pass or produce scoped follow-up cards.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let singleTermMatches = try service.search("acceptance", limit: 10)
        #expect(singleTermMatches.contains {
            $0.kind == .item && $0.item?.id == note.entityID
        })
        #expect(singleTermMatches.contains {
            $0.kind == .chunk && $0.owner == cardOwner
        })

        let phraseMatches = try service.search("Cutover acceptance", limit: 10)
        #expect(phraseMatches.contains {
            $0.kind == .item && $0.item?.id == note.entityID
        })
    }

    @Test("agent context bundle is bounded and includes provenance review history and safe commands")
    func agentContextBundleIsBoundedAndActionable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and confirm insurance before booking the follow-up appointment.",
                source: "projection",
                sortOrder: 0
            )
        )
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "details",
                title: "Details",
                body: "This longer section should not be included when the section limit is one.",
                source: "projection",
                sortOrder: 1
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "note-body",
                title: "Dentist follow-up chunk",
                body: "Call the dentist, verify the insurance portal, and ask whether the claim requires prior authorization.",
                chunkIndex: 0
            ),
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "note-body",
                title: "Extra chunk",
                body: "This chunk should be omitted by the max chunk limit.",
                chunkIndex: 1
            ),
        ])
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: note.entityID.uuidString,
                targetType: "folder",
                targetPath: "Health/Dental",
                confidence: 0.64,
                reason: "Health admin item, but target needs review.",
                status: "needs_review",
                actor: "agent",
                source: "routing.test"
            )
        )
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: note.entityID.uuidString,
                toolName: "cider-cli",
                actionType: "route",
                source: "agent.test",
                status: "suggested",
                summary: "Suggested routing to Health/Dental.",
                argumentsJSON: nil,
                resultJSON: nil
            )
        )

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(database: db, linkService: linkService, secondBrainStore: store)

        let packet = try service.agentContext(
            for: note,
            limits: CiderItemAgentContextLimits(
                maxSections: 1,
                maxChunks: 1,
                maxRelated: 1,
                maxHistory: 2,
                maxBodyCharacters: 48
            )
        )

        #expect(packet.item.id == note.entityID)
        #expect(packet.summary == "Call the dentist and confirm insurance before bo")
        #expect(packet.summary.count <= 48)
        #expect(packet.provenance.contains("item:note"))
        #expect(packet.provenance.contains("path:Inbox/Notes/Dentist follow-up.md"))
        #expect(packet.contentBlocks.map(\.title) == ["Summary", "Dentist follow-up chunk"])
        #expect(packet.contentBlocks.allSatisfy { $0.body.count <= 48 })
        #expect(packet.related.map(\.title) == ["Dental insurance portal"])
        #expect(packet.review?.status == "needs_review")
        #expect(packet.review?.targetPath == "Health/Dental")
        #expect(packet.surfacing.reason == "Health admin item, but target needs review.")
        #expect(packet.surfacing.urgency == "review")
        #expect(packet.surfacing.sourceSignal == "item_context")
        #expect(packet.surfacing.reviewState == "needs_review")
        #expect(packet.recentHistory.map(\.summary).contains("Suggested routing to Health/Dental."))
        #expect(packet.safeCommands.contains("cider-cli item get note \(note.entityID.uuidString) --json"))
        #expect(packet.safeCommands.contains("cider-cli item related note \(note.entityID.uuidString) --json"))
        #expect(packet.safeCommands.contains("cider-cli routing explain \(note.entityID.uuidString) --json"))
    }

    @Test("agent context uses shared reminder relevance for todo surfacing")
    func agentContextUsesReminderRelevanceForTodoSurfacing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let todoID = UUID()
        let todoRef = LibraryEntityRef(type: .todo, entityID: todoID)
        let todo = TodoCard(
            id: todoID,
            title: "Pay rent",
            dueDate: now,
            priority: .high,
            actionURLString: "https://rent.example.com",
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now
        )
        try insertItem(todoRef, title: "Pay rent", relativePath: "Inbox/Todos/Pay rent.md", into: db)

        let service = CiderItemContextService(
            database: db,
            todoProvider: { [todo] },
            dateCardProvider: { [] },
            nowProvider: { now }
        )

        let packet = try service.agentContext(for: todoRef)

        #expect(packet.surfacing.reason == "due today")
        #expect(packet.surfacing.urgency == "today")
        #expect(packet.surfacing.sourceSignal == "reminder_relevance")
        #expect(packet.surfacing.reviewState == "ok")
        #expect(packet.surfacing.suggestedAction == "open action URL")
        #expect(packet.surfacing.actionURLString == "https://rent.example.com")
    }
}

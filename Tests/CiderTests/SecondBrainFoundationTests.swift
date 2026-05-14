import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Foundation Tests")
@MainActor
struct SecondBrainFoundationTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-second-brain-\(UUID().uuidString).db")
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

    @Test("schema creates second brain tables and FTS index")
    func schemaCreatesSecondBrainTablesAndFTSIndex() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        #expect(DatabaseMigrations.latestVersion >= 9)
        let expectedTables = [
            "item_sections",
            "content_chunks",
            "content_chunks_fts",
            "routing_decisions",
            "agent_actions",
        ]

        for table in expectedTables {
            let stmt = try db.prepare(
                "SELECT count(*) FROM sqlite_master WHERE name = ?;"
            )
            stmt.bind(table, at: 1)
            try stmt.step()
            #expect(stmt.int(at: 0) == 1, "Expected \(table) to exist")
        }
    }

    @Test("sections and chunks persist and search through FTS")
    func sectionsAndChunksPersistAndSearchThroughFTS() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        let section = SecondBrainSection(
            owner: owner,
            sectionKey: "problem",
            title: "Problem",
            body: "Walls of Markdown hide the current state.",
            source: "kanban_notes",
            sortOrder: 0
        )

        try store.upsertSection(section)
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: section.id,
                    source: "kanban_notes",
                    title: "Problem",
                    body: "The Stonewards card needs exact keyword recall and structured evidence.",
                    chunkIndex: 0
                )
            ]
        )

        let sections = try store.sections(for: owner)
        #expect(sections.map(\.sectionKey) == ["problem"])

        let results = try store.searchChunks(query: "Stonewards evidence", limit: 5)
        #expect(results.count == 1)
        #expect(results[0].owner == owner)
        #expect(results[0].title == "Problem")
        #expect(results[0].snippet.localizedCaseInsensitiveContains("Stonewards"))
    }

    @Test("FTS search treats hyphenated terms as literal content")
    func ftsSearchTreatsHyphenatedTermsAsLiteralContent() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    source: "kanban_notes",
                    title: "Hyphen Search",
                    body: "The second-brain card-a reference should be searchable.",
                    chunkIndex: 0
                )
            ]
        )

        #expect(try store.searchChunks(query: "second-brain", limit: 5).first?.owner == owner)
        #expect(try store.searchChunks(query: "card-a", limit: 5).first?.owner == owner)
    }

    @Test("replacing chunks removes stale FTS hits")
    func replacingChunksRemovesStaleFTSHits() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    source: "kanban_notes",
                    title: "Old",
                    body: "obsolete-token",
                    chunkIndex: 0
                )
            ]
        )
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    source: "kanban_notes",
                    title: "New",
                    body: "fresh-token",
                    chunkIndex: 0
                )
            ]
        )

        #expect(try store.searchChunks(query: "obsolete-token", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "fresh-token", limit: 5).first?.owner == owner)
    }

    @Test("routing decisions and agent actions are durable provenance")
    func routingDecisionsAndAgentActionsAreDurableProvenance() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)

        let routing = SecondBrainRoutingDecision(
            owner: owner,
            targetType: "space",
            targetID: "recipes",
            targetPath: "Spaces/Recipes",
            confidence: 0.94,
            reason: "Recipe extraction matched ingredients and instructions.",
            status: "accepted",
            actor: "hermes",
            source: "agent"
        )
        try store.recordRoutingDecision(routing)

        let action = SecondBrainAgentAction(
            owner: owner,
            toolName: "item.route",
            actionType: "route",
            source: "agent",
            status: "succeeded",
            summary: "Routed bookmark to Recipes Space."
        )
        try store.recordAgentAction(action)

        #expect(try store.routingDecisions(for: owner).map(\.reason) == [routing.reason])
        #expect(try store.agentActions(for: owner).map(\.toolName) == ["item.route"])
    }

    @Test("routing and agent provenance survive item deletion")
    func routingAndAgentProvenanceSurviveItemDeletion() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let itemID = UUID().uuidString
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at)
            VALUES ('\(itemID)', 'note', 'Deleted source item', 1, 1);
            """)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: itemID)
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: itemID,
                targetType: "space",
                targetID: "projects",
                targetPath: nil,
                confidence: 1,
                reason: "Keep routing audit after delete.",
                status: "accepted",
                actor: "test",
                source: "test"
            )
        )
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: itemID,
                toolName: "item.route",
                actionType: "route",
                source: "test",
                status: "succeeded",
                summary: "Audit retained."
            )
        )

        try db.runSQL("DELETE FROM items WHERE id = '\(itemID)';")

        #expect(try store.routingDecisions(for: owner).first?.itemID == nil)
        #expect(try store.agentActions(for: owner).first?.itemID == nil)
    }

    @Test("Kanban card notes parse into stable dashboard sections")
    func kanbanCardNotesParseIntoStableDashboardSections() {
        let notes = """
        One line before structured sections.

        ## Problem
        Walls of Markdown hide state.

        ## Acceptance Criteria
        - Agents can inspect the card.
        - Cider can render focused sections.
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["notes", "problem", "acceptance_criteria"])
        #expect(sections[1].title == "Problem")
        #expect(sections[1].body == "Walls of Markdown hide state.")
        #expect(sections[2].body.contains("Agents can inspect"))
    }

    @Test("Kanban parser merges duplicate headings and ignores fenced headings")
    func kanbanParserMergesDuplicateHeadingsAndIgnoresFencedHeadings() {
        let notes = """
        ## Evidence
        First proof.

        ```swift
        ## Not a real section
        let value = 1
        ```

        ## Evidence
        Second proof.

        ##NoSpace
        Plain text.
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["evidence"])
        #expect(sections[0].body.contains("First proof."))
        #expect(sections[0].body.contains("## Not a real section"))
        #expect(sections[0].body.contains("Second proof."))
        #expect(sections[0].body.contains("##NoSpace"))
    }

    @Test("Kanban parser promotes common plain labels into dashboard sections")
    func kanbanParserPromotesCommonPlainLabelsIntoDashboardSections() {
        let notes = """
        ## Second-Brain Foundation Program

        Problem:
        Agents infer too much from scattered prose.

        Research conclusion:
        SQLite stays the source of truth.

        Created: 2026-05-14
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["problem", "research_conclusion", "created"])
        #expect(sections[0].body == "Agents infer too much from scattered prose.")
        #expect(sections[1].body == "SQLite stays the source of truth.")
        #expect(sections[2].body == "2026-05-14")
    }

    @Test("Kanban parser keeps explicit handoff heading when body starts with status")
    func kanbanParserKeepsExplicitHandoffHeadingWhenBodyStartsWithStatus() {
        let notes = """
        ## Agent Handoff
        Status: Dashboard v2 is verification-ready.

        Start here:
        - Run board card inspect.
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.count == 1)
        #expect(sections[0].key == "agent_handoff")
        #expect(sections[0].body.contains("Status: Dashboard v2 is verification-ready."))
        #expect(sections[0].body.contains("Start here:"))
    }

    @Test("Kanban card section updates preserve sibling sections")
    func kanbanCardSectionUpdatesPreserveSiblingSections() {
        let notes = """
        ## Problem
        Old problem.

        ## Evidence
        - Existing proof.
        """

        let updated = KanbanCardSectionParser.updatingSection(
            in: notes,
            title: "Problem",
            body: "New problem."
        )

        #expect(updated.contains("## Problem\nNew problem."))
        #expect(updated.contains("## Evidence\n- Existing proof."))
    }

    @Test("Kanban section updates preserve unrelated Markdown shape")
    func kanbanSectionUpdatesPreserveUnrelatedMarkdownShape() {
        let notes = """
        Intro prose stays outside structured sections.

        ### Problem
        Old problem.

        #### Evidence
        - Existing proof.

        Goal: Keep this inline label intact.
        """

        let updated = KanbanCardSectionParser.updatingSection(
            in: notes,
            title: "Problem",
            body: "New problem."
        )

        #expect(updated.contains("Intro prose stays outside structured sections."))
        #expect(updated.contains("### Problem\nNew problem."))
        #expect(updated.contains("#### Evidence\n- Existing proof."))
        #expect(updated.contains("Goal: Keep this inline label intact."))
    }

    @Test("Kanban evidence appends to a durable section")
    func kanbanEvidenceAppendsToDurableSection() {
        let date = Date(timeIntervalSince1970: 1_778_700_000)
        let updated = KanbanCardSectionParser.appendingEvidence(
            to: "## Problem\nNeeds proof.",
            text: "Second-brain tests passed.",
            source: "swift test",
            at: date
        )

        #expect(updated.contains("## Test Evidence"))
        #expect(updated.contains("- 2026-05-13 19:20 - Second-brain tests passed. (source: swift test)"))
    }

    @Test("Kanban card projection populates sections and searchable chunks")
    func kanbanCardProjectionPopulatesSectionsAndSearchableChunks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let card = KanbanCard(
            id: "card-a",
            title: "Build Stonewards dashboard",
            notes: """
            ## Problem
            Stonewards needs visible blockers.

            ## Test Evidence
            - Parser tests pass.
            """
        )

        try projector.refreshCard(boardID: "board-a", card: card)

        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        #expect(try store.sections(for: owner).map(\.sectionKey) == ["problem", "test_evidence"])
        #expect(try store.searchChunks(query: "Stonewards blockers", limit: 5).first?.owner == owner)
    }

    @Test("Kanban dashboard model builds second brain cockpit surfaces")
    func kanbanDashboardModelBuildsSecondBrainCockpitSurfaces() {
        let model = KanbanCardDashboardModel(
            title: "Second-brain foundation program",
            notes: """
            ## Second-Brain Foundation Program

            Problem:
            Agents still need to infer too much from YAML, Markdown, folders, and prose.

            Research conclusion:
            Keep SQLite as the canonical local memory/query layer. Use embeddings later as optional semantics.

            Phased implementation plan:
            1. Add additive SQLite v9 schema.
            2. Add agent-safe CLI/API commands.
            3. Add native Kanban Card Dashboard MVP.

            Non-goals for this branch:
            - No full rewrite.
            - No destructive cleanup of live vault data.

            Created: 2026-05-14

            ## Test Evidence
            - 2026-05-14 01:13 - Second-brain foundation pass 1 verified. (source: swift test)
            """
        )

        #expect(model.hasStructuredContent)
        #expect(model.problem?.contains("infer too much") == true)
        #expect(model.decisions.map(\.title) == ["Research conclusion"])
        #expect(model.openLoops.contains { $0.body.contains("Add agent-safe CLI/API commands") })
        #expect(model.evidenceEntries.first?.dateLabel == "2026-05-14 01:13")
        #expect(model.evidenceEntries.first?.source == "swift test")
        #expect(model.missingCoreSections.contains("Current State"))
        #expect(model.agentContext.updateTargets.contains("Test Evidence"))
    }

    @Test("Kanban dashboard model extracts related items and agent handoff labels")
    func kanbanDashboardModelExtractsRelatedItemsAndAgentHandoffLabels() {
        let model = KanbanCardDashboardModel(
            title: "Dashboard resurfacing engine V1",
            notes: """
            Goal: Make dashboard resurfacing explainable.

            Related existing cards:
            - eb3626 Second-brain Dashboard command center MVP
            - a71bc6 Dashboard command center: docs health and actionable cards

            Agent handoff:
            Future agents should append verification to Test Evidence and implementation notes to Implementation Evidence.
            """
        )

        #expect(model.goal == "Make dashboard resurfacing explainable.")
        #expect(model.relatedItems.count == 2)
        #expect(model.relatedItems[0].body.contains("eb3626"))
        #expect(model.agentContext.notes.contains("Future agents should append verification"))
        #expect(model.agentContext.commands(board: "Cider", cardID: "abc123").contains {
            $0.contains("board evidence add Cider --card abc123")
        })
    }

    @Test("Kanban dashboard model does not treat completed plan tasks as open loops")
    func kanbanDashboardModelDoesNotTreatCompletedPlanTasksAsOpenLoops() {
        let model = KanbanCardDashboardModel(
            title: "Finished foundation",
            notes: """
            Phased implementation plan:
            - [x] Add the schema.
            - [X] Verify the app.

            Next Step:
            User review.
            """
        )

        #expect(model.openLoops.isEmpty)
        #expect(model.nextStep == "User review.")
    }

    @Test("Kanban projection prunes stale sections")
    func kanbanProjectionPrunesStaleSections() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let original = KanbanCard(
            id: "card-a",
            title: "Refresh dashboard",
            notes: """
            ## Problem
            Needs structure.

            ## Evidence
            Old proof.
            """
        )
        let updated = KanbanCard(
            id: "card-a",
            title: "Refresh dashboard",
            notes: """
            ## Problem
            Needs structure.
            """
        )

        try projector.refreshCard(boardID: "board-a", card: original)
        try projector.refreshCard(boardID: "board-a", card: updated)

        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        #expect(try store.sections(for: owner).map(\.sectionKey) == ["problem"])
    }

    @Test("projection replacement rolls back sections and chunks together")
    func projectionReplacementRollsBackSectionsAndChunksTogether() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        let original = SecondBrainSection(
            id: "original-section",
            owner: owner,
            sectionKey: "problem",
            title: "Problem",
            body: "old-token remains after rollback",
            source: "test",
            sortOrder: 0
        )
        try store.replaceProjection(
            owner: owner,
            sections: [original],
            keeping: ["problem"],
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: original.id,
                    source: "test",
                    title: "Problem",
                    body: "old-token remains after rollback",
                    chunkIndex: 0
                ),
            ]
        )

        let replacement = SecondBrainSection(
            id: "replacement-section",
            owner: owner,
            sectionKey: "decision",
            title: "Decision",
            body: "new-token should roll back",
            source: "test",
            sortOrder: 0
        )

        var didRollback = false
        do {
            try store.replaceProjection(
                owner: owner,
                sections: [replacement],
                keeping: ["decision"],
                chunks: [
                    SecondBrainChunkDraft(
                        sectionID: "missing-section",
                        source: "test",
                        title: "Decision",
                        body: "new-token should roll back",
                        chunkIndex: 0
                    ),
                ]
            )
            Issue.record("Expected invalid chunk section reference to roll back projection replacement")
        } catch {
            didRollback = true
        }

        #expect(didRollback)
        #expect(try store.sections(for: owner).map(\.sectionKey) == ["problem"])
        #expect(try store.searchChunks(query: "old-token", limit: 5).first?.owner == owner)
        #expect(try store.searchChunks(query: "new-token", limit: 5).isEmpty)
    }

    @Test("deleted Kanban card projection removes searchable chunks")
    func deletedKanbanCardProjectionRemovesSearchableChunks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let card = KanbanCard(
            id: "card-a",
            title: "Ghost projection",
            notes: "## Problem\nphantom-token should disappear after delete."
        )
        let owner = SecondBrainKanbanProjectionService.owner(boardID: "board-a", cardID: card.id)

        try projector.refreshCard(boardID: "board-a", card: card)
        #expect(try store.searchChunks(query: "phantom-token", limit: 5).first?.owner == owner)

        try store.deleteProjection(for: owner)

        #expect(try store.sections(for: owner).isEmpty)
        #expect(try store.searchChunks(query: "phantom-token", limit: 5).isEmpty)
    }

    @Test("deleted Kanban board projection removes all projected cards")
    func deletedKanbanBoardProjectionRemovesAllProjectedCards() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        try projector.refreshCard(
            boardID: "board-a",
            card: KanbanCard(id: "card-a", title: "A", notes: "## Problem\nboard-ghost-a")
        )
        try projector.refreshCard(
            boardID: "board-a",
            card: KanbanCard(id: "card-b", title: "B", notes: "## Problem\nboard-ghost-b")
        )
        try projector.refreshCard(
            boardID: "board-b",
            card: KanbanCard(id: "card-c", title: "C", notes: "## Problem\nsurviving-card")
        )

        try store.deleteProjections(ownerType: "kanban_card", ownerIDPrefix: "board-a/")

        #expect(try store.searchChunks(query: "board-ghost-a", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "board-ghost-b", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "surviving-card", limit: 5).count == 1)
    }

    @Test("v8 database migrates to v9 second brain tables")
    func v8DatabaseMigratesToV9SecondBrainTables() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        do {
            let db = CiderDatabase()
            try db.open(at: url)
            try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ai;")
            try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ad;")
            try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_au;")
            try db.runSQL("DROP TABLE IF EXISTS content_chunks_fts;")
            try db.runSQL("DROP TABLE IF EXISTS content_chunks;")
            try db.runSQL("DROP TABLE IF EXISTS item_sections;")
            try db.runSQL("DROP TABLE IF EXISTS routing_decisions;")
            try db.runSQL("DROP TABLE IF EXISTS agent_actions;")
            try db.runSQL("DELETE FROM schema_version;")
            try db.runSQL("INSERT INTO schema_version (version) VALUES (8);")
            db.close()
        }

        let migrated = CiderDatabase()
        try migrated.open(at: url)
        defer { migrated.close() }

        let version = try migrated.prepare("SELECT MAX(version) FROM schema_version;")
        try version.step()
        #expect(version.int(at: 0) == 9)

        for table in ["item_sections", "content_chunks", "content_chunks_fts", "routing_decisions", "agent_actions"] {
            let stmt = try migrated.prepare("SELECT count(*) FROM sqlite_master WHERE name = ?;")
            stmt.bind(table, at: 1)
            try stmt.step()
            #expect(stmt.int(at: 0) == 1, "Expected migrated database to include \(table)")
        }
    }
}

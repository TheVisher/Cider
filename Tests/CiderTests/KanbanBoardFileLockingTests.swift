import Foundation
import Testing
@testable import Cider

struct KanbanBoardFileLockingTests {
    @Test("moving parent group to queued moves source-column descendants only")
    @MainActor
    func movingParentGroupToQueuedMovesSourceColumnDescendantsOnly() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Hierarchy Move")
        let queued = try #require(storage.addColumn(boardID: board.id, name: "Queued"))
        let parent = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Parent plan"))
        let childA = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Child A", parentCardID: parent.id))
        let grandchild = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Grandchild", parentCardID: childA.id))
        let childB = try #require(storage.addCard(boardID: board.id, columnID: "in_progress", title: "Child B", parentCardID: parent.id))

        storage.moveCard(
            boardID: board.id,
            cardID: parent.id,
            toColumnID: queued.id,
            toIndex: 0,
            includeDescendants: true
        )

        let refreshed = try #require(KanbanStorage().boards.first { $0.id == board.id })
        let queuedColumn = try #require(refreshed.columns.first { $0.id == queued.id })

        #expect(queuedColumn.cards.map(\.id) == [parent.id, childA.id, grandchild.id])
        #expect(queuedColumn.cards.first { $0.id == childA.id }?.parentCardID == parent.id)
        #expect(queuedColumn.cards.first { $0.id == grandchild.id }?.parentCardID == childA.id)
        #expect(refreshed.columns.first { $0.id == "backlog" }?.cards.isEmpty == true)
        #expect(refreshed.columns.first { $0.id == "in_progress" }?.cards.map(\.id) == [childB.id])
        #expect(refreshed.columns.first { $0.id == "in_progress" }?.cards.first?.parentCardID == parent.id)
    }

    @Test("moving individual child keeps parent and leaves siblings in place")
    @MainActor
    func movingIndividualChildKeepsParentAndLeavesSiblingsInPlace() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Child Move")
        let parent = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Parent plan"))
        let childA = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Child A", parentCardID: parent.id))
        let childB = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Child B", parentCardID: parent.id))

        storage.moveCard(
            boardID: board.id,
            cardID: childA.id,
            toColumnID: "in_progress",
            toIndex: 0
        )

        let refreshed = try #require(KanbanStorage().boards.first { $0.id == board.id })
        let backlog = try #require(refreshed.columns.first { $0.id == "backlog" })
        let inProgress = try #require(refreshed.columns.first { $0.id == "in_progress" })

        #expect(backlog.cards.map(\.id) == [parent.id, childB.id])
        #expect(inProgress.cards.map(\.id) == [childA.id])
        #expect(inProgress.cards.first?.parentCardID == parent.id)
    }

    @Test("moving to legacy done column stamps completion")
    @MainActor
    func movingToLegacyDoneColumnStampsCompletion() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Legacy Done Move")
        storage.setColumnDone(boardID: board.id, columnID: "done", isDone: false)
        let card = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Ready to ship"))

        storage.moveCard(
            boardID: board.id,
            cardID: card.id,
            toColumnID: "done",
            toIndex: 0
        )

        let refreshed = try #require(KanbanStorage().boards.first { $0.id == board.id })
        let moved = try #require(refreshed.card(id: card.id))
        #expect(refreshed.columns.first { $0.id == "done" }?.isDoneColumn == false)
        #expect(moved.completed != nil)
        #expect(moved.lastActivityKind == "completed")
    }

    @Test("stale whole-card updates merge changed fields")
    @MainActor
    func staleWholeCardUpdatesMergeChangedFields() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Merge Smoke")
        let card = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Race card"))
        let secondWriterStorage = KanbanStorage()

        var notesEdit = card
        notesEdit.notes = "Notes from first writer"
        var priorityEdit = card
        priorityEdit.priority = .high

        storage.updateCard(boardID: board.id, card: notesEdit)
        secondWriterStorage.updateCard(boardID: board.id, card: priorityEdit)

        let refreshedStorage = KanbanStorage()
        let refreshed = try #require(refreshedStorage.findCard(id: card.id)?.card)
        #expect(refreshed.notes == "Notes from first writer")
        #expect(refreshed.priority == .high)
    }

    @Test("stale note appends merge against latest board file")
    @MainActor
    func staleNoteAppendsMergeAgainstLatestBoardFile() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Notes Merge Smoke")
        let card = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Race card"))
        let secondWriterStorage = KanbanStorage()

        storage.appendCardEvidence(
            boardID: board.id,
            cardID: card.id,
            text: "First writer verification survived.",
            source: "first"
        )
        secondWriterStorage.appendCardHistory(
            boardID: board.id,
            cardID: card.id,
            type: "implementation",
            text: "Second writer implementation survived.",
            source: "second"
        )

        let refreshed = try #require(KanbanStorage().findCard(id: card.id)?.card)
        let notes = try #require(refreshed.notes)
        #expect(notes.contains("First writer verification survived."))
        #expect(notes.contains("Second writer implementation survived."))
        #expect(notes.contains("## Test Evidence"))
        #expect(notes.contains("## Implementation History"))
    }

    @Test("reviewed inbox cards stay reviewed after no-op detail save and reload")
    @MainActor
    func reviewedInboxCardsStayReviewedAfterNoOpDetailSaveAndReload() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Inbox Persistence")
        let workspace = ProjectWorkspace(
            id: "inbox-persistence",
            kind: .project,
            title: "Inbox Persistence",
            subtitle: "",
            boardIDs: [board.id],
            referenceSearchTerms: []
        )
        let card = try #require(storage.addCard(
            boardID: board.id,
            columnID: "backlog",
            title: "Review me",
            notes: "Agent handoff ready for QA",
            priority: .high
        ))

        var inboxCandidate = card
        inboxCandidate.agent = "Cody"
        storage.updateCard(boardID: board.id, card: inboxCandidate)

        #expect(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: storage.boards) == 1)

        storage.markCardReviewed(boardID: board.id, cardID: card.id)
        let reviewed = try #require(KanbanStorage().findCard(id: card.id)?.card)

        storage.updateCard(boardID: board.id, card: reviewed)

        let reloadedStorage = KanbanStorage()
        let reloadedBoard = try #require(reloadedStorage.boards.first { $0.id == board.id })
        let reloadedCard = try #require(reloadedBoard.card(id: card.id))
        #expect(reloadedCard.reviewedAt != nil)
        #expect(reloadedBoard.columnID(containing: card.id) == "backlog")
        #expect(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: reloadedStorage.boards) == 0)
        #expect(ProjectWorkspaceInboxProvider.entries(for: workspace, boards: reloadedStorage.boards).isEmpty)
    }

    @Test("reviewed inbox cards re-enter after persisted meaningful activity")
    @MainActor
    func reviewedInboxCardsReenterAfterPersistedMeaningfulActivity() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Inbox Reentry")
        let workspace = ProjectWorkspace(
            id: "inbox-reentry",
            kind: .project,
            title: "Inbox Reentry",
            subtitle: "",
            boardIDs: [board.id],
            referenceSearchTerms: []
        )
        let card = try #require(storage.addCard(
            boardID: board.id,
            columnID: "backlog",
            title: "Review me again",
            notes: "Agent handoff ready for QA"
        ))

        var inboxCandidate = card
        inboxCandidate.agent = "Cody"
        storage.updateCard(boardID: board.id, card: inboxCandidate)

        storage.markCardReviewed(boardID: board.id, cardID: card.id)
        var reviewed = try #require(KanbanStorage().findCard(id: card.id)?.card)
        let reviewedAt = try #require(reviewed.reviewedAt)
        reviewed.historyEntries.append(KanbanCardHistoryEntry(
            type: .implementation,
            body: "Agent added a new follow-up after review.",
            author: "Cody",
            createdAt: reviewedAt.addingTimeInterval(60)
        ))
        storage.updateCard(boardID: board.id, card: reviewed)

        let reloadedStorage = KanbanStorage()
        let entries = ProjectWorkspaceInboxProvider.entries(for: workspace, boards: reloadedStorage.boards)
        let reloadedCard = try #require(reloadedStorage.findCard(id: card.id)?.card)
        #expect(entries.map { $0.card.id } == [card.id])
        #expect(reloadedCard.reviewedAt != nil)
        #expect(reloadedCard.updatedAt != nil)
        #expect(reloadedStorage.findCard(id: card.id)?.column.id == "backlog")
    }

    @Test("add card persists normalized metadata and parent")
    @MainActor
    func addCardPersistsNormalizedMetadataAndParent() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Quick Add Metadata")
        let parent = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Parent plan"))
        let child = try #require(storage.addCard(
            boardID: board.id,
            columnID: "backlog",
            title: "Child card",
            notes: "  Build the compact entry path.  ",
            priority: .medium,
            color: .purple,
            tags: ["kanban", "quick-add"],
            parentCardID: parent.id
        ))

        let refreshed = try #require(KanbanStorage().findCard(id: child.id)?.card)
        #expect(refreshed.notes == "Build the compact entry path.")
        #expect(refreshed.priority == .medium)
        #expect(refreshed.color == .purple)
        #expect(refreshed.tags == ["kanban", "quick-add"])
        #expect(refreshed.parentCardID == parent.id)
    }

    @Test("card comments persist and reload nested categories")
    @MainActor
    func cardCommentsPersistAndReloadNestedCategories() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Comment Persistence")
        let card = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Threaded card"))
        let handoff = KanbanCardComment(
            id: "comment-handoff",
            kind: .handoff,
            body: "Handoff for Cody.",
            author: "Cider/Hermes",
            source: "discord",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let evidence = KanbanCardComment(
            id: "comment-evidence",
            kind: .evidence,
            body: "Reload verified.",
            author: "Cody",
            source: "swift-test",
            createdAt: Date(timeIntervalSince1970: 1_750_000_060),
            parentCommentID: handoff.id
        )

        var updated = card
        updated.comments = [handoff, evidence]
        storage.updateCard(boardID: board.id, card: updated)

        let reloaded = try #require(KanbanStorage().findCard(id: card.id)?.card)
        #expect(reloaded.comments.map(\.id) == ["comment-handoff", "comment-evidence"])
        #expect(reloaded.comments.map(\.kind) == [.handoff, .evidence])
        #expect(reloaded.comments.last?.parentCommentID == "comment-handoff")
        #expect(reloaded.updatedAt != nil)
        #expect(reloaded.lastActivityKind == "updated")
    }

    @Test("tag editor save persists tags and reload derives visible chip semantics")
    @MainActor
    func tagEditorSavePersistsTagsAndReloadDerivesVisibleChipSemantics() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Tag Editor Persistence")
        let card = try #require(storage.addCard(
            boardID: board.id,
            columnID: "backlog",
            title: "Editable tags",
            tags: ["bug"]
        ))

        storage.updateCardTags(boardID: board.id, cardID: card.id, tags: ["Sidebar", "Bug", "QA", "sidebar"])

        let reloadedStorage = KanbanStorage()
        let reloaded = try #require(reloadedStorage.findCard(id: card.id)?.card)
        #expect(reloaded.tags == ["sidebar", "bug", "qa"])

        let chips = KanbanBoardLayout.cardFaceChips(for: reloaded)
        #expect(chips.map(\.label) == ["…", "Interface", "Bug", "QA"])
        #expect(chips.map(\.role) == [.tagEdit, .featureDomain, .typeStatus, .typeStatus])
        #expect(chips.map(\.accessory) == [.none, .featureIcon, .colorDot, .colorDot])
        #expect(chips[1].iconSystemName == "cube.transparent")
        #expect(chips[2].iconSystemName == nil)
        #expect(chips[3].iconSystemName == nil)
    }

    @Test("parallel CLI add-card operations preserve every card")
    func parallelCLIAddCardOperationsPreserveEveryCard() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        try Self.runCLI(cli, vault: vault, args: ["board", "create", "Locking Smoke"])

        let cardCount = 12
        let processes = try (0..<cardCount).map { index in
            try Self.startCLI(
                cli,
                vault: vault,
                args: [
                    "board", "add-card", "Locking Smoke",
                    "--column", "Backlog",
                    "--title", "Concurrent card \(index)",
                ]
            )
        }

        for process in processes {
            process.process.waitUntilExit()
            #expect(process.process.terminationStatus == 0)
            _ = String(data: process.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            _ = String(data: process.error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        }

        let jsonData = try Self.runCLIData(cli, vault: vault, args: ["board", "show", "Locking Smoke", "--json"])
        let root = try #require(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let columns = try #require(root["columns"] as? [[String: Any]])
        let backlog = try #require(columns.first { ($0["id"] as? String) == "backlog" })
        let cards = try #require(backlog["cards"] as? [[String: Any]])
        let titles = Set(cards.compactMap { $0["title"] as? String })

        #expect(titles.count == cardCount)
        for index in 0..<cardCount {
            #expect(titles.contains("Concurrent card \(index)"))
        }
    }

    @Test("storage update persists structured history entries during stale merge")
    @MainActor
    func storageUpdatePersistsStructuredHistoryEntriesDuringStaleMerge() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "History Merge")
        let card = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "History card"))
        let secondWriterStorage = KanbanStorage()

        var historyEdit = card
        historyEdit.historyEntries = [
            KanbanCardHistoryEntry(
                id: "test-evidence",
                type: .testEvidence,
                body: "swift test --filter KanbanBoardFileLockingTests passed.",
                author: "Hermes",
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        ]
        var priorityEdit = card
        priorityEdit.priority = .medium

        storage.updateCard(boardID: board.id, card: historyEdit)
        secondWriterStorage.updateCard(boardID: board.id, card: priorityEdit)

        let refreshed = try #require(KanbanStorage().findCard(id: card.id)?.card)
        #expect(refreshed.historyEntries.map(\.id) == ["test-evidence"])
        #expect(refreshed.historyEntries.first?.type == .testEvidence)
        #expect(refreshed.priority == .medium)
    }

    @Test("board show rejects tag filters without values")
    func boardShowRejectsTagFiltersWithoutValues() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        try Self.runCLI(cli, vault: vault, args: ["board", "create", "Tag Validation"])

        let output = try Self.runCLI(cli, vault: vault, args: ["board", "show", "Tag Validation", "--tag", "--json"])

        #expect(output.contains("Error: --tag requires a tag value."))
        #expect(output.contains("Usage: cider-cli board show <board> [--tag <tag>] [--tags <csv>] [--json]"))
    }

    @Test("board mutation validation failures exit nonzero")
    func boardMutationValidationFailuresExitNonzero() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        try Self.runCLI(cli, vault: vault, args: ["board", "create", "Mutation Validation"])
        let cardOutput = try Self.runCLI(cli, vault: vault, args: [
            "board", "add-card", "Mutation Validation",
            "--column", "Backlog",
            "--title", "Existing card",
        ])
        let cardID = String(try #require(cardOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let invalidCommands: [[String]] = [
            ["board", "add-card", "Mutation Validation", "--column", "Backlog"],
            ["board", "add-card", "Mutation Validation", "--column", "Missing", "--title", "Nope"],
            ["board", "update-card", "Mutation Validation", "--card", cardID, "--priority", "urgent"],
            ["board", "move-card", "Mutation Validation", "--card", cardID, "--to", "Missing"],
            ["board", "delete-card", "Mutation Validation", "--card", "missing-card"],
            ["board", "add-column", "Mutation Validation"],
            ["board", "set-column-done", "Mutation Validation", "--column", "Backlog"],
            ["board", "rename-column", "Mutation Validation", "--column", "Backlog"],
            ["board", "delete-column", "Mutation Validation"],
        ]

        for args in invalidCommands {
            let result = try Self.runCLIResult(cli, vault: vault, args: args)
            let output = String(data: result.output, encoding: .utf8) ?? ""
            #expect(result.status == 1, "Expected nonzero exit for cider-cli \(args.joined(separator: " "))")
            #expect(output.contains("Error:"), "Expected error output for cider-cli \(args.joined(separator: " "))")
        }
    }

    @Test("board audit reports missing parent references")
    func boardAuditReportsMissingParentReferences() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let boardsDirectory = vault.appendingPathComponent(".cider/boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try """
        id: auditbad
        board: Audit Bad
        created: '2026-05-26'
        columns:
          - id: backlog
            name: Backlog
            cards:
              - id: child
                title: Orphan child
                parentCardID: missing-parent
                created: '2026-05-26'
        """.write(
            to: boardsDirectory.appendingPathComponent("auditbad.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let result = try Self.runCLIResult(cli, vault: vault, args: ["board", "audit", "--json"])
        let root = try #require(try JSONSerialization.jsonObject(with: result.output) as? [String: Any])
        let issues = try #require(root["issues"] as? [[String: Any]])
        let firstIssue = try #require(issues.first)

        #expect(result.status == 1)
        #expect(root["ok"] as? Bool == false)
        #expect(root["issueCount"] as? Int == 1)
        #expect(firstIssue["type"] as? String == "missing_parent")
        #expect(firstIssue["boardID"] as? String == "auditbad")
        #expect(firstIssue["cardID"] as? String == "child")
        #expect(firstIssue["parentCardID"] as? String == "missing-parent")
    }

    @Test("board audit passes clean board relationships")
    func boardAuditPassesCleanBoardRelationships() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let boardsDirectory = vault.appendingPathComponent(".cider/boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try """
        id: auditclean
        board: Audit Clean
        created: '2026-05-26'
        columns:
          - id: backlog
            name: Backlog
            cards:
              - id: parent
                title: Parent
                created: '2026-05-26'
              - id: child
                title: Child
                parentCardID: parent
                created: '2026-05-26'
        """.write(
            to: boardsDirectory.appendingPathComponent("auditclean.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let result = try Self.runCLIResult(cli, vault: vault, args: ["board", "audit", "--json"])
        let root = try #require(try JSONSerialization.jsonObject(with: result.output) as? [String: Any])

        #expect(result.status == 0)
        #expect(root["ok"] as? Bool == true)
        #expect(root["issueCount"] as? Int == 0)
        #expect(root["boardCount"] as? Int == 1)
        #expect(root["cardCount"] as? Int == 2)
    }

    @Test("board audit reports YAML decode failures")
    func boardAuditReportsYAMLDecodeFailures() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let boardsDirectory = vault.appendingPathComponent(".cider/boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try """
        id: broken
        board: Broken YAML
        columns:
          - id: backlog
            name: Backlog
            cards:
              - id: card
                title: Missing closing quote
                notes: "this never closes
        """.write(
            to: boardsDirectory.appendingPathComponent("broken.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let result = try Self.runCLIResult(cli, vault: vault, args: ["board", "audit", "--json"])
        let root = try #require(try JSONSerialization.jsonObject(with: result.output) as? [String: Any])
        let issues = try #require(root["issues"] as? [[String: Any]])
        let decodeIssue = try #require(issues.first { $0["type"] as? String == "board_yaml_decode_failed" })

        #expect(result.status == 1)
        #expect(root["ok"] as? Bool == false)
        #expect(root["issueCount"] as? Int == 1)
        #expect(root["boardCount"] as? Int == 0)
        #expect(decodeIssue["boardID"] as? String == "broken")
        #expect(decodeIssue["fileName"] as? String == "broken.yaml")
    }

    @Test("board audit reports duplicate ids and parent cycles")
    func boardAuditReportsDuplicateIDsAndParentCycles() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let boardsDirectory = vault.appendingPathComponent(".cider/boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try """
        id: auditcycle
        board: Audit Cycle
        created: '2026-05-26'
        columns:
          - id: backlog
            name: Backlog
            cards:
              - id: duplicate
                title: First duplicate
                created: '2026-05-26'
              - id: alpha
                title: Alpha
                parentCardID: beta
                created: '2026-05-26'
          - id: queued
            name: Queued
            cards:
              - id: duplicate
                title: Second duplicate
                created: '2026-05-26'
              - id: beta
                title: Beta
                parentCardID: alpha
                created: '2026-05-26'
        """.write(
            to: boardsDirectory.appendingPathComponent("auditcycle.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let result = try Self.runCLIResult(cli, vault: vault, args: ["board", "audit", "--json"])
        let root = try #require(try JSONSerialization.jsonObject(with: result.output) as? [String: Any])
        let issues = try #require(root["issues"] as? [[String: Any]])
        let issueTypes = Set(issues.compactMap { $0["type"] as? String })

        #expect(result.status == 1)
        #expect(root["ok"] as? Bool == false)
        #expect(issueTypes.contains("duplicate_card_id"))
        #expect(issueTypes.contains("parent_cycle"))
    }

    private static func ciderCLIURL() -> URL? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func makeTemporaryVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-kanban-locking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    @discardableResult
    private static func runCLI(_ cli: URL, vault: URL, args: [String]) throws -> String {
        let data = try runCLIData(cli, vault: vault, args: args)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runCLIData(_ cli: URL, vault: URL, args: [String]) throws -> Data {
        let process = try startCLI(cli, vault: vault, args: args)
        process.process.waitUntilExit()
        let output = process.output.fileHandleForReading.readDataToEndOfFile()
        let error = process.error.fileHandleForReading.readDataToEndOfFile()
        if process.process.terminationStatus != 0 {
            let stderr = String(data: error, encoding: .utf8) ?? ""
            Issue.record("cider-cli failed with status \(process.process.terminationStatus): \(stderr)")
        }
        #expect(process.process.terminationStatus == 0)
        return output
    }

    private static func runCLIResult(
        _ cli: URL,
        vault: URL,
        args: [String]
    ) throws -> (status: Int32, output: Data, error: Data) {
        let process = try startCLI(cli, vault: vault, args: args)
        process.process.waitUntilExit()
        let output = process.output.fileHandleForReading.readDataToEndOfFile()
        let error = process.error.fileHandleForReading.readDataToEndOfFile()
        return (process.process.terminationStatus, output, error)
    }

    private static func startCLI(
        _ cli: URL,
        vault: URL,
        args: [String]
    ) throws -> (process: Process, output: Pipe, error: Pipe) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = cli
        process.arguments = ["--vault", vault.path] + args
        process.standardOutput = output
        process.standardError = error
        try process.run()
        return (process, output, error)
    }
}

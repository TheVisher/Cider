import XCTest
@testable import Cider

final class ProjectWorkspaceContentModelTests: XCTestCase {
    func testProjectReferencesIncludeLinkedAndTextMatchedItemsOnly() {
        let linkedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let matchedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let unrelatedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let linkedRef = LibraryEntityRef(type: .bookmark, entityID: linkedID)
        let project = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let boards = [
            KanbanBoard(
                id: "2afee0",
                name: "Cider",
                columns: [
                    KanbanColumn(
                        id: "in_progress",
                        name: "In Progress",
                        cards: [
                            KanbanCard(id: "a18f97", title: "Project references MVP", linkedEntities: [linkedRef])
                        ]
                    )
                ]
            )
        ]
        let items: [LibraryItemV2] = [
            .bookmark(Bookmark(id: linkedID, title: "Linear inspiration", urlString: "https://linear.app")),
            .note(Note(id: matchedID, title: "Cider sidebar notes", content: "Reference IA")),
            .bookmark(Bookmark(id: unrelatedID, title: "Garden planning", urlString: "https://example.com/garden"))
        ]

        let references = ProjectReferenceProvider.references(for: project, items: items, boards: boards)

        XCTAssertEqual(references.map(\.item.title), ["Linear inspiration", "Cider sidebar notes"])
        XCTAssertEqual(references.first?.linkedCardCount, 1)
        XCTAssertTrue(references.first?.isLinkedToProjectCard == true)
        XCTAssertEqual(references.first?.reason, "Linked to 1 card")
    }

    func testProjectReferencesSearchFilePathsTagsAndBookmarkURLs() {
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let bookmarkID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let project = ProjectWorkspace(
            id: "cider-ios",
            kind: .project,
            title: "Cider iOS",
            subtitle: "Mobile workspace",
            boardIDs: ["2d3f69"],
            referenceSearchTerms: ["cider ios", "cider mobile"]
        )
        let items: [LibraryItemV2] = [
            .vaultFile(VaultFile(
                id: fileID,
                filename: "dashboard.png",
                relativePath: "Projects/Cider iOS/Screenshots/dashboard.png",
                fileType: .image,
                fileSize: 128,
                createdAt: Date(timeIntervalSince1970: 10),
                modifiedAt: Date(timeIntervalSince1970: 10),
                folderID: nil
            )),
            .bookmark(Bookmark(
                id: bookmarkID,
                title: "Mobile navigation pattern",
                urlString: "https://example.com/cider-mobile-navigation",
                tags: ["inspiration"]
            ))
        ]

        let references = ProjectReferenceProvider.references(for: project, items: items, boards: [])

        XCTAssertEqual(references.map(\.item.title), ["Mobile navigation pattern", "dashboard.png"])
        XCTAssertEqual(references.map(\.reason), ["Matches Cider Mobile", "Matches Cider iOS"])
    }

    func testProjectOverviewSummarizesScopedBoardsAndHomeCommandCenter() {
        let cider = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(id: "next", title: "Next work")
                ]),
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [
                    KanbanCard(id: "active", title: "Active work")
                ]),
                KanbanColumn(id: "testing", name: "Testing", cards: [
                    KanbanCard(id: "qa", title: "Ready to Test"),
                    KanbanCard(id: "blocked", title: "Blocked by decision", tags: ["blocked"])
                ])
            ]
        )
        let web = KanbanBoard(
            id: "08c899",
            name: "Cider Web",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [
                    KanbanCard(id: "web-next", title: "Web next")
                ])
            ]
        )
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [cider, web])
        let ciderWorkspace = catalog.workspace(id: "cider")!

        let projectModel = ProjectWorkspaceOverviewProvider.model(for: ciderWorkspace, catalog: catalog, boards: [cider, web])
        let homeModel = ProjectWorkspaceOverviewProvider.model(for: catalog.home, catalog: catalog, boards: [cider, web])

        XCTAssertEqual(projectModel.boardSummaries.map(\.boardID), ["2afee0"])
        XCTAssertEqual(projectModel.totals.inProgress, 1)
        XCTAssertEqual(projectModel.totals.testing, 2)
        XCTAssertEqual(projectModel.totals.blocked, 1)
        XCTAssertEqual(homeModel.projectRows.map(\.projectID), ["cider", "cider-web"])
        XCTAssertEqual(homeModel.totals.queued, 2)
    }

    func testProjectOverviewExposesBoardCreationActionForProjectsOnly() {
        let board = KanbanBoard(id: "2afee0", name: "Cider")
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!

        let projectModel = ProjectWorkspaceOverviewProvider.model(for: ciderWorkspace, catalog: catalog, boards: [board])
        let homeModel = ProjectWorkspaceOverviewProvider.model(for: catalog.home, catalog: catalog, boards: [board])

        XCTAssertEqual(projectModel.boardCreationActionTitle, "New Board")
        XCTAssertNil(homeModel.boardCreationActionTitle)
    }

    func testProjectOverviewCanSurfaceBackendArtifactRelations() {
        let board = KanbanBoard(id: "2afee0", name: "Cider")
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: "CF06DD4E")
        let projectOwner = SecondBrainOwnerRef(ownerType: "project", ownerID: "cider")
        let relation = SecondBrainRelation(
            sourceOwner: noteOwner,
            targetOwner: projectOwner,
            relationType: "artifact_of",
            evidence: "Agent-native capture contract audit belongs to Cider.",
            source: "test",
            actor: "agent",
            confidence: 1,
            metadata: ["title": "Agent-native capture contract v1 audit"]
        )

        let model = ProjectWorkspaceOverviewProvider.model(
            for: ciderWorkspace,
            catalog: catalog,
            boards: [board],
            artifactRelations: [relation]
        )

        XCTAssertEqual(model.artifacts.map(\.owner), [noteOwner])
        XCTAssertEqual(model.artifacts.map(\.title), ["Agent-native capture contract v1 audit"])
        XCTAssertEqual(model.artifacts.map(\.relationType), ["artifact_of"])
        XCTAssertEqual(model.artifacts.map(\.safeCommand), ["cider-cli item context note CF06DD4E --json"])
    }

    func testProjectNotesSurfaceShowsOnlyMatchingFileBackedProjectNotes() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let matchingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let genericID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let otherProjectID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let decisionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let notes = [
            Note(
                id: matchingID,
                title: "Cider project note",
                content: "Project-body",
                modifiedAt: Date(timeIntervalSince1970: 4_000),
                relativePath: "Projects/Cider/Notes/Cider project note.md",
                projectID: "cider",
                artifactType: "note"
            ),
            Note(
                id: genericID,
                title: "Generic library note",
                content: "Generic-body",
                modifiedAt: Date(timeIntervalSince1970: 5_000),
                relativePath: "Inbox/Notes/Generic library note.md"
            ),
            Note(
                id: otherProjectID,
                title: "iOS project note",
                content: "Other-body",
                modifiedAt: Date(timeIntervalSince1970: 6_000),
                relativePath: "Projects/Cider iOS/Notes/iOS project note.md",
                projectID: "cider-ios",
                artifactType: "note"
            ),
            Note(
                id: decisionID,
                title: "Cider decision",
                content: "Decision-body",
                modifiedAt: Date(timeIntervalSince1970: 7_000),
                relativePath: "Projects/Cider/Decisions/Cider decision.md",
                projectID: "cider",
                artifactType: "decision"
            )
        ]

        let model = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .notes,
            notes: notes
        )

        XCTAssertEqual(model.notes.map(\.id), [matchingID])
        XCTAssertEqual(model.notes.first?.path, "Projects/Cider/Notes/Cider project note.md")
        XCTAssertEqual(model.notes.first?.owner, SecondBrainOwnerRef(ownerType: "note", ownerID: matchingID.uuidString))
    }

    func testProjectArtifactRelationshipsConnectPlanningNotesToSpawnedCardsAndQA() {
        let noteID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let qaID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let note = Note(
            id: noteID,
            title: "Project workspace plan",
            content: "Spawn relation graph card.",
            relativePath: "Projects/Cider/Notes/Project workspace plan.md",
            projectID: "cider",
            artifactType: "note"
        )
        let qaNote = Note(
            id: qaID,
            title: "Relationship graph QA",
            content: "Findings",
            relativePath: "Projects/Cider/QA/Relationship graph QA.md",
            projectID: "cider",
            artifactType: "qa"
        )
        let card = KanbanCard(id: "8b6f3c", title: "Project workspace relationship graph MVP")
        let board = KanbanBoard(id: "2afee0", name: "Cider", columns: [
            KanbanColumn(id: "in_progress", name: "In Progress", cards: [card])
        ])
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let cardOwner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "\(board.id)/\(card.id)")
        let qaOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: qaID.uuidString)
        let relations = [
            SecondBrainRelation(
                sourceOwner: cardOwner,
                targetOwner: noteOwner,
                relationType: ProjectArtifactRelationType.spawnedFrom,
                evidence: "Card was spawned from the plan.",
                source: "test",
                actor: "agent",
                confidence: 1,
                metadata: ["card_title": card.title]
            ),
            SecondBrainRelation(
                sourceOwner: qaOwner,
                targetOwner: noteOwner,
                relationType: ProjectArtifactRelationType.foundBugIn,
                evidence: "QA found a follow-up in the plan.",
                source: "test",
                actor: "agent",
                confidence: 1,
                metadata: [:]
            )
        ]

        let model = ProjectArtifactRelationshipProvider.model(
            for: noteOwner,
            relations: relations,
            boards: [board],
            notes: [note, qaNote]
        )

        XCTAssertEqual(model.derivedCards.map(\.title), ["Project workspace relationship graph MVP"])
        XCTAssertEqual(model.derivedCards.map(\.relationType), [ProjectArtifactRelationType.spawnedFrom])
        XCTAssertEqual(model.derivedCards.first?.subtitle.contains("Open · In Progress"), true)
        XCTAssertEqual(model.qaFindings.map(\.title), ["Relationship graph QA"])
        XCTAssertTrue(model.sourceArtifacts.isEmpty)
    }

    func testProjectArtifactRelationshipsShowCardSourcesDecisionsAndQA() {
        let noteID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let decisionID = UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        let qaID = UUID(uuidString: "56565656-5656-5656-5656-565656565656")!
        let notes = [
            Note(id: noteID, title: "Workspace plan", content: "", artifactType: "note"),
            Note(id: decisionID, title: "Use contextual panels", content: "", artifactType: "decision"),
            Note(id: qaID, title: "Panels QA", content: "", artifactType: "qa")
        ]
        let card = KanbanCard(id: "8b6f3c", title: "Project workspace relationship graph MVP")
        let board = KanbanBoard(id: "2afee0", name: "Cider", columns: [
            KanbanColumn(id: "testing", name: "Testing", cards: [card])
        ])
        let cardOwner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "\(board.id)/\(card.id)")
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let decisionOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: decisionID.uuidString)
        let qaOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: qaID.uuidString)
        let relations = [
            SecondBrainRelation(
                sourceOwner: cardOwner,
                targetOwner: noteOwner,
                relationType: ProjectArtifactRelationType.spawnedFrom,
                evidence: "Card came from the workspace plan.",
                source: "test",
                actor: "agent",
                confidence: 1,
                metadata: [:]
            ),
            SecondBrainRelation(
                sourceOwner: cardOwner,
                targetOwner: decisionOwner,
                relationType: ProjectArtifactRelationType.decidedFrom,
                evidence: "Implementation follows the contextual-panels decision.",
                source: "test",
                actor: "agent",
                confidence: 1,
                metadata: [:]
            ),
            SecondBrainRelation(
                sourceOwner: qaOwner,
                targetOwner: cardOwner,
                relationType: ProjectArtifactRelationType.validates,
                evidence: "QA validates the card.",
                source: "test",
                actor: "agent",
                confidence: 1,
                metadata: [:]
            )
        ]

        let model = ProjectArtifactRelationshipProvider.model(
            for: cardOwner,
            relations: relations,
            boards: [board],
            notes: notes
        )

        XCTAssertEqual(model.sourceArtifacts.map(\.title), ["Workspace plan"])
        XCTAssertEqual(model.relatedDecisions.map(\.title), ["Use contextual panels"])
        XCTAssertEqual(model.qaFindings.map(\.title), ["Panels QA"])
    }
}

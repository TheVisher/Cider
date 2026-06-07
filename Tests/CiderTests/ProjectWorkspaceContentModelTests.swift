import XCTest
@testable import Cider

final class ProjectWorkspaceContentModelTests: XCTestCase {
    func testProjectWorkspaceSurfaceDisplayModesOfferListAndGridOnly() {
        XCTAssertEqual(ProjectWorkspaceSurfaceDisplayMode.allCases, [.list, .grid])
        XCTAssertEqual(ProjectWorkspaceSurfaceDisplayMode.list.title, "List")
        XCTAssertEqual(ProjectWorkspaceSurfaceDisplayMode.grid.title, "Grid")
        XCTAssertEqual(ProjectWorkspaceSurfaceDisplayMode.list.systemImage, "list.bullet")
        XCTAssertEqual(ProjectWorkspaceSurfaceDisplayMode.grid.systemImage, "square.grid.2x2")
    }

    func testProjectReferencesIncludeProjectAssetFolderItemsOnly() {
        let linkedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let placedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
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
            .bookmark(Bookmark(
                id: placedID,
                title: "Cider design inspiration",
                urlString: "https://example.com/inspiration",
                relativePath: "Projects/Cider/Assets/Cider design inspiration.webloc"
            )),
            .bookmark(Bookmark(id: unrelatedID, title: "Garden planning", urlString: "https://example.com/garden"))
        ]

        let references = ProjectReferenceProvider.references(for: project, items: items, boards: boards)

        XCTAssertEqual(references.map(\.item.title), ["Cider design inspiration"])
        XCTAssertEqual(references.first?.linkedCardCount, 0)
        XCTAssertFalse(references.first?.isLinkedToProjectCard == true)
        XCTAssertEqual(references.first?.reason, "Projects/Cider/Assets")
    }

    func testProjectReferencesIgnoreLibrarySearchTermMatches() {
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
                relativePath: "Projects/Cider iOS/Assets/dashboard.png",
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

        XCTAssertEqual(references.map(\.item.title), ["dashboard.png"])
        XCTAssertEqual(references.map(\.reason), ["Projects/Cider iOS/Assets"])
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

    func testProjectOverviewBuildsCommandCenterSectionsFromExistingData() {
        let olderUpdate = Date(timeIntervalSince1970: 1_000)
        let latestUpdate = Date(timeIntervalSince1970: 2_000)
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [
                    KanbanCard(
                        id: "parent",
                        title: "Project workspace MVP",
                        displayKey: "CID-80",
                        tags: ["milestone"],
                        historyEntries: [
                            KanbanCardHistoryEntry(
                                id: "older",
                                type: .implementation,
                                body: "Older project implementation note.",
                                author: "cody",
                                createdAt: olderUpdate
                            )
                        ]
                    ),
                    KanbanCard(
                        id: "active",
                        title: "Overview command center",
                        displayKey: "CID-201",
                        historyEntries: [
                            KanbanCardHistoryEntry(
                                id: "latest",
                                type: .decision,
                                body: "Keep the overview calm: resources, latest update, roadmap, and recent artifacts.",
                                author: "codex",
                                createdAt: latestUpdate
                            )
                        ]
                    )
                ]),
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(id: "queued-child", title: "Queued child", parentCardID: "parent")
                ]),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true, cards: [
                    KanbanCard(id: "done-child", title: "Done child", parentCardID: "parent", completed: latestUpdate)
                ])
            ]
        )
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let relations = (1...6).map { index in
            SecondBrainRelation(
                sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: "NOTE-\(index)"),
                targetOwner: SecondBrainOwnerRef(ownerType: "project", ownerID: "cider"),
                relationType: index == 1 ? "repository" : "artifact_of",
                evidence: "Resource \(index)",
                source: "test",
                actor: "agent",
                confidence: 1,
                metadata: ["title": "Resource \(index)"]
            )
        }

        let model = ProjectWorkspaceOverviewProvider.model(
            for: ciderWorkspace,
            catalog: catalog,
            boards: [board],
            artifactRelations: relations,
            coreDocsRoot: makeCoreDocsRoot()
        )

        XCTAssertEqual(model.resources.map(\.title), ["GitHub Repository", "Local Repository", "Cider Vault"])
        XCTAssertEqual(model.recentArtifacts.map(\.title), ["PRODUCT", "FEATURES", "ARCHITECTURE"])
        XCTAssertEqual(model.recentArtifacts.first?.relativePath, "Docs/PRODUCT.md")
        XCTAssertEqual(model.recentArtifacts.first?.lineCount, 2)
        XCTAssertEqual(model.recentArtifacts.first?.wordCount, 5)
        XCTAssertEqual(model.artifacts.map(\.title).prefix(2), ["Resource 1", "Resource 2"])
        XCTAssertEqual(model.latestUpdate?.cardID, "active")
        XCTAssertEqual(model.latestUpdate?.cardDisplayKey, "CID-201")
        XCTAssertEqual(model.latestUpdate?.typeLabel, "Decision")
        XCTAssertEqual(model.latestUpdate?.body, "Keep the overview calm: resources, latest update, roadmap, and recent artifacts.")
        XCTAssertEqual(model.milestoneRows.map(\.cardID), ["parent"])
        XCTAssertEqual(model.milestoneRows.first?.progressText, "1/2")
        XCTAssertEqual(model.milestoneRows.first?.status, "In Progress")
        XCTAssertEqual(model.milestoneRows.first?.completedChildCount, 1)
        XCTAssertEqual(model.milestoneRows.first?.childCount, 2)
        XCTAssertEqual(model.milestoneRows.first?.progressFraction, 0.5)
    }

    func testProjectOverviewMilestonesPreferExplicitMilestoneCardsAndLinkArtifacts() {
        let planID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let qaID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(
                        id: "milestone",
                        title: "Milestone: One Board Per Project",
                        notes: "Goal:\nMake Cider use one canonical board with milestones and drilldown filters.",
                        displayKey: "CID-201",
                        tags: ["milestone"]
                    ),
                    KanbanCard(
                        id: "regular-parent",
                        title: "Regular parent card"
                    ),
                    KanbanCard(
                        id: "active-child",
                        title: "Active milestone child",
                        parentCardID: "milestone"
                    ),
                    KanbanCard(
                        id: "regular-child",
                        title: "Regular child",
                        parentCardID: "regular-parent"
                    )
                ]),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true, cards: [
                    KanbanCard(
                        id: "done-child",
                        title: "Done milestone child",
                        parentCardID: "milestone"
                    )
                ])
            ]
        )
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let planRelation = SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: planID.uuidString),
            targetOwner: SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/milestone"),
            relationType: "documents",
            evidence: "Plan documents milestone.",
            source: "test",
            actor: "codex",
            confidence: 1,
            metadata: ["artifactType": "plan", "title": "One Board Per Project Plan"]
        )
        let qaRelation = SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: qaID.uuidString),
            targetOwner: SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/milestone"),
            relationType: "validates",
            evidence: "QA validates milestone.",
            source: "test",
            actor: "codex",
            confidence: 1,
            metadata: ["artifactType": "qa", "title": "One Board Per Project QA"]
        )

        let model = ProjectWorkspaceOverviewProvider.model(
            for: ciderWorkspace,
            catalog: catalog,
            boards: [board],
            artifactRelations: [planRelation, qaRelation]
        )

        XCTAssertEqual(model.milestoneRows.map(\.cardID), ["milestone"])
        XCTAssertEqual(model.milestoneRows.first?.description, "Make Cider use one canonical board with milestones and drilldown filters.")
        XCTAssertEqual(model.milestoneRows.first?.progressText, "1/2")
        XCTAssertEqual(model.milestoneRows.first?.completedChildCount, 1)
        XCTAssertEqual(model.milestoneRows.first?.childCount, 2)
        XCTAssertEqual(model.milestoneRows.first?.artifactLinks.map(\.displayType), ["Plan", "QA"])
        XCTAssertEqual(model.milestoneRows.first?.artifactLinks.map(\.title), ["One Board Per Project Plan", "One Board Per Project QA"])
    }

    func testProjectOverviewMilestoneProgressCountsLegacyDoneColumns() {
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(
                        id: "milestone",
                        title: "Milestone: One Board Per Project",
                        displayKey: "CID-201",
                        tags: ["milestone"]
                    ),
                    KanbanCard(id: "active-child", title: "Active milestone child", parentCardID: "milestone")
                ]),
                KanbanColumn(id: "done", name: "Done", cards: [
                    KanbanCard(id: "done-child", title: "Done milestone child", parentCardID: "milestone")
                ])
            ]
        )
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!

        let model = ProjectWorkspaceOverviewProvider.model(
            for: ciderWorkspace,
            catalog: catalog,
            boards: [board]
        )

        XCTAssertEqual(model.milestoneRows.first?.progressText, "1/2")
        XCTAssertEqual(model.milestoneRows.first?.completedChildCount, 1)
        XCTAssertEqual(model.milestoneRows.first?.progressFraction, 0.5)
    }

    private func makeCoreDocsRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectWorkspaceContentModelTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try! "One two three\nfour five".write(to: root.appendingPathComponent("PRODUCT.md"), atomically: true, encoding: .utf8)
        try! "Feature words\n".write(to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        try! "Architecture words\n".write(to: root.appendingPathComponent("ARCHITECTURE.md"), atomically: true, encoding: .utf8)
        return root
    }

    func testProjectNotesSurfaceShowsOnlyMatchingFileBackedProjectNotes() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let matchingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let genericID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let otherProjectID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let decisionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let handoffID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
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
            ),
            Note(
                id: handoffID,
                title: "Cider handoff",
                content: "Long agent handoff.",
                modifiedAt: Date(timeIntervalSince1970: 8_000),
                relativePath: "Projects/Cider/Handoffs/Cider handoff.md",
                projectID: "cider",
                artifactType: "handoff"
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

    func testProjectPlansSurfaceShowsDedicatedPlansOnly() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let planID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let handoffID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let noteID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let notes = [
            Note(
                id: planID,
                title: "Relationship graph plan",
                content: "Plan body",
                modifiedAt: Date(timeIntervalSince1970: 4_000),
                relativePath: "Projects/Cider/Plans/Relationship graph plan.md",
                projectID: "cider",
                artifactType: "plan"
            ),
            Note(
                id: handoffID,
                title: "Cody final report",
                content: "Full final report body longer than chat.",
                modifiedAt: Date(timeIntervalSince1970: 5_000),
                relativePath: "Projects/Cider/Handoffs/Cody final report.md",
                projectID: "cider",
                artifactType: "handoff"
            ),
            Note(
                id: noteID,
                title: "Regular project note",
                content: "Note body",
                modifiedAt: Date(timeIntervalSince1970: 6_000),
                relativePath: "Projects/Cider/Notes/Regular project note.md",
                projectID: "cider",
                artifactType: "note"
            )
        ]

        let model = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .plansHandoffs,
            notes: notes
        )

        XCTAssertEqual(model.notes.map(\.id), [planID])
        XCTAssertEqual(model.notes.map(\.path), [
            "Projects/Cider/Plans/Relationship graph plan.md"
        ])
    }

    func testProjectPlansSurfaceDefaultsToActivePlansAndSuppressesParkedIdeasAndTemplates() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let activeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let parkedID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let templateID = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
        let notes = [
            Note(
                id: activeID,
                title: "Dogfood recall plan",
                content: "Active implementation plan body",
                modifiedAt: Date(timeIntervalSince1970: 4_000),
                relativePath: "Projects/Cider/Plans/Dogfood recall plan.md",
                projectID: "cider",
                artifactType: "plan"
            ),
            Note(
                id: parkedID,
                title: "Parked Spaces Media Recipes idea plan",
                content: """
                ---
                type: idea-plan
                status: parked
                category: product-surface
                source: CID-460
                dogfoodStatus: unproven
                ---

                # Parked Spaces, Media, and Recipes
                """,
                modifiedAt: Date(timeIntervalSince1970: 5_000),
                relativePath: "Projects/Cider/Plans/Parked Spaces Media Recipes idea plan.md",
                projectID: "cider",
                artifactType: "plan"
            ),
            Note(
                id: templateID,
                title: "Idea Plan Template",
                content: """
                ---
                type: idea-plan
                status: template
                category: product-surface
                dogfoodStatus: unknown
                ---

                # Idea Plan Template
                """,
                modifiedAt: Date(timeIntervalSince1970: 6_000),
                relativePath: "Projects/Cider/Plans/Idea Plan Template.md",
                projectID: "cider",
                artifactType: "plan"
            )
        ]

        let model = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .plansHandoffs,
            notes: notes
        )

        XCTAssertEqual(model.notes.map(\.id), [activeID])
        XCTAssertEqual(model.notes.first?.planMetadata?.status, "active")
    }

    func testProjectPlansSurfaceCanExplicitlyShowParkedIdeaPlansWithMetadata() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let spacesID = UUID(uuidString: "44444444-5555-6666-7777-888888888888")!
        let nativeAIID = UUID(uuidString: "55555555-6666-7777-8888-999999999999")!
        let activeID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let templateID = UUID(uuidString: "77777777-8888-9999-AAAA-BBBBBBBBBBBB")!
        let notes = [
            Note(
                id: activeID,
                title: "Active planning flow",
                content: "Active implementation plan body",
                modifiedAt: Date(timeIntervalSince1970: 8_000),
                relativePath: "Projects/Cider/Plans/Active planning flow.md",
                projectID: "cider",
                artifactType: "plan"
            ),
            Note(
                id: nativeAIID,
                title: "Parked Native AI Assistant idea plan",
                content: """
                ---
                type: idea-plan
                status: parked
                category: product-surface
                source: CID-461
                dogfoodStatus: unproven
                ---

                # Parked Native AI Assistant
                """,
                modifiedAt: Date(timeIntervalSince1970: 9_000),
                relativePath: "Projects/Cider/Plans/Parked Native AI Assistant idea plan.md",
                projectID: "cider",
                artifactType: "plan"
            ),
            Note(
                id: spacesID,
                title: "Parked Spaces Media Recipes idea plan",
                content: """
                ---
                type: idea-plan
                status: parked
                category: product-surface
                source: CID-460
                dogfoodStatus: unproven
                ---

                # Parked Spaces, Media, and Recipes
                """,
                modifiedAt: Date(timeIntervalSince1970: 10_000),
                relativePath: "Projects/Cider/Plans/Parked Spaces Media Recipes idea plan.md",
                projectID: "cider",
                artifactType: "plan"
            ),
            Note(
                id: templateID,
                title: "Idea Plan Template",
                content: """
                ---
                type: idea-plan
                status: template
                category: product-surface
                source: CID-463
                dogfoodStatus: unknown
                ---

                # Idea Plan Template
                """,
                modifiedAt: Date(timeIntervalSince1970: 11_000),
                relativePath: "Projects/Cider/Plans/Idea Plan Template.md",
                projectID: "cider",
                artifactType: "plan"
            )
        ]

        let model = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .plansHandoffs,
            notes: notes,
            planScope: .parkedIdeas
        )

        XCTAssertEqual(model.notes.map(\.id), [spacesID, nativeAIID])
        XCTAssertEqual(model.notes.map { $0.planMetadata?.type }, ["idea-plan", "idea-plan"])
        XCTAssertEqual(model.notes.map { $0.planMetadata?.status }, ["parked", "parked"])
        XCTAssertEqual(model.notes.map { $0.planMetadata?.source }, ["CID-460", "CID-461"])
        XCTAssertEqual(model.notes.map { $0.planMetadata?.dogfoodStatus }, ["unproven", "unproven"])
    }

    func testProjectPlansHandoffsSurfaceSummarizesLinkedCardsAndAgents() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let planID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let plan = Note(
            id: planID,
            title: "Cider implementation plan",
            content: "## Hermes Spec\nFull spec.\n\n## Cody Implementation\nFull report.",
            modifiedAt: Date(timeIntervalSince1970: 5_000),
            relativePath: "Projects/Cider/Plans/Cider implementation plan.md",
            projectID: "cider",
            artifactType: "plan"
        )
        let planOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: planID.uuidString)
        let cardOwner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/2c0a04")
        let relations = [
            SecondBrainRelation(
                sourceOwner: planOwner,
                targetOwner: cardOwner,
                relationType: ProjectArtifactRelationType.documents,
                evidence: "Plan documents the Plans card.",
                source: "note.project-artifact",
                actor: "cider",
                confidence: 1,
                metadata: ["card_title": "Make Plans/Handoffs surface usable for agent evidence"]
            ),
            SecondBrainRelation(
                sourceOwner: planOwner,
                targetOwner: cardOwner,
                relationType: ProjectArtifactRelationType.validates,
                evidence: "Cody verified the plan flow.",
                source: "note.project-artifact",
                actor: "cody",
                confidence: 1,
                metadata: [:]
            )
        ]

        let model = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .plansHandoffs,
            notes: [plan],
            artifactRelations: relations
        )

        XCTAssertEqual(model.notes.first?.linkedCardLabels, ["2c0a04: documents, validates"])
        XCTAssertEqual(model.notes.first?.agentLabels, ["cider", "cody"])
        XCTAssertEqual(model.notes.first?.relationSummary, "cards: 2c0a04 (documents, validates) · agents: cider, cody")
    }

    func testProjectDecisionAndQAAuditSurfacesShowMatchingArtifactsOnly() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let ciderWorkspace = catalog.workspace(id: "cider")!
        let decisionID = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let qaID = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!
        let auditID = UUID(uuidString: "30303030-3030-3030-3030-303030303030")!
        let handoffID = UUID(uuidString: "40404040-4040-4040-4040-404040404040")!
        let otherDecisionID = UUID(uuidString: "50505050-5050-5050-5050-505050505050")!
        let notes = [
            Note(
                id: decisionID,
                title: "Use stable project relation names",
                content: "Decision body",
                modifiedAt: Date(timeIntervalSince1970: 4_000),
                relativePath: "Projects/Cider/Decisions/Use stable project relation names.md",
                projectID: "cider",
                artifactType: "decision"
            ),
            Note(
                id: qaID,
                title: "Artifact relation QA",
                content: "QA body",
                modifiedAt: Date(timeIntervalSince1970: 6_000),
                relativePath: "Projects/Cider/QA/Artifact relation QA.md",
                projectID: "cider",
                artifactType: "qa"
            ),
            Note(
                id: auditID,
                title: "Artifact relation audit",
                content: "Audit body",
                modifiedAt: Date(timeIntervalSince1970: 5_000),
                relativePath: "Projects/Cider/QA/Artifact relation audit.md",
                projectID: "cider",
                artifactType: "audit"
            ),
            Note(
                id: handoffID,
                title: "Agent handoff",
                content: "Handoff body",
                modifiedAt: Date(timeIntervalSince1970: 7_000),
                relativePath: "Projects/Cider/Handoffs/Agent handoff.md",
                projectID: "cider",
                artifactType: "handoff"
            ),
            Note(
                id: otherDecisionID,
                title: "iOS decision",
                content: "Other project decision",
                modifiedAt: Date(timeIntervalSince1970: 8_000),
                relativePath: "Projects/Cider iOS/Decisions/iOS decision.md",
                projectID: "cider-ios",
                artifactType: "decision"
            )
        ]

        let decisions = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .decisions,
            notes: notes
        )
        let qaAudits = ProjectWorkspaceSurfaceProvider.model(
            for: ciderWorkspace,
            surface: .qaAudits,
            notes: notes
        )

        XCTAssertEqual(decisions.notes.map(\.id), [decisionID])
        XCTAssertEqual(decisions.notes.map(\.path), ["Projects/Cider/Decisions/Use stable project relation names.md"])
        XCTAssertEqual(qaAudits.notes.map(\.id), [qaID, auditID])
        XCTAssertEqual(qaAudits.notes.map(\.path), [
            "Projects/Cider/QA/Artifact relation QA.md",
            "Projects/Cider/QA/Artifact relation audit.md"
        ])
    }

    func testProjectSurfaceTitlesMatchVaultPlanningAndQASurfaces() {
        XCTAssertEqual(ProjectWorkspaceSurface.milestones.title, "Milestones")
        XCTAssertEqual(ProjectWorkspaceSurface.milestones.tabName, "Milestones")
        XCTAssertEqual(ProjectWorkspaceSurface.plansHandoffs.title, "Plans")
        XCTAssertEqual(ProjectWorkspaceSurface.plansHandoffs.tabName, "Plans")
        XCTAssertEqual(ProjectWorkspaceSurface.qaAudits.title, "QA")
        XCTAssertEqual(ProjectWorkspaceSurface.qaAudits.tabName, "QA")
        XCTAssertTrue(ProjectWorkspaceSurface.milestones.placeholderSubtitle.contains("Milestone goals"))
        XCTAssertTrue(ProjectWorkspaceSurface.plansHandoffs.placeholderSubtitle.contains("Draft feature plans"))
        XCTAssertTrue(ProjectWorkspaceSurface.qaAudits.placeholderSubtitle.contains("cleanup milestones"))
    }

    func testProjectMilestoneRowsCanReturnFullListForMilestonesTab() {
        let milestones = (0..<7).map { index in
            KanbanCard(
                id: "milestone-\(index)",
                title: "Milestone: Goal \(index)",
                displayKey: "CID-\(index + 1)",
                tags: ["milestone-object"],
                updatedAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let children = milestones.flatMap { milestone in
            [
                KanbanCard(id: "\(milestone.id)-child-a", title: "Child A", parentCardID: milestone.id),
                KanbanCard(id: "\(milestone.id)-child-b", title: "Child B", parentCardID: milestone.id),
            ]
        }
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: milestones + children)
            ]
        )
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!

        let overviewModel = ProjectWorkspaceOverviewProvider.model(
            for: ciderWorkspace,
            catalog: catalog,
            boards: [board]
        )
        let fullRows = ProjectWorkspaceOverviewProvider.milestoneRows(
            for: ciderWorkspace,
            boards: [board]
        )

        XCTAssertEqual(overviewModel.milestoneRows.count, 5)
        XCTAssertEqual(fullRows.count, 7)
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
        XCTAssertEqual(model.relatedDecisions.first?.subtitle, "decided from · → note:34343434-3434-3434-3434-343434343434")
        XCTAssertEqual(model.qaFindings.first?.subtitle, "validates · ← note:56565656-5656-5656-5656-565656565656")
    }
}

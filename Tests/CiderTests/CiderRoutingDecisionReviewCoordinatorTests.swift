import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Cider Routing Decision Review Coordinator Tests", .serialized)
@MainActor
struct CiderRoutingDecisionReviewCoordinatorTests {
    private static let actor = "cid837-cp4-reviewer"

    private struct InjectedRoutingFailure: Error {}

    @Test("Routing decisions carry an exact coordinator identity and version")
    func routingQueueIdentityAndVersion() throws {
        let fixture = try RoutingFixture(itemType: "note")
        defer { fixture.close() }

        let item = try #require(
            try CiderReviewQueueService(database: fixture.database)
                .list(kind: "low_confidence_routing")
                .items.first
        )
        #expect(item.candidateRef == "routing_decision:\(fixture.decision.id.uuidString)")
        #expect(item.reviewFamily == "routing_decision")
        #expect(item.candidateUpdatedAt == fixture.decision.createdAt)

        let outcome = CiderReviewActionCoordinator(database: fixture.database).perform(
            CiderReviewActionRequest(
                identity: .init(
                    candidateRef: "routing_decision:\(fixture.decision.id.uuidString)",
                    family: .routingDecision
                ),
                expectedVersion: .init(
                    reviewState: fixture.decision.reviewState,
                    updatedAt: fixture.decision.createdAt
                ),
                action: .approve,
                routingItemID: fixture.itemID,
                routingDestination: fixture.decision.target,
                actor: "user",
                surface: .home,
                exactEvidenceRequirement: .notRequired,
                mutationAuthority: .reviewApprovedCandidate
            )
        )

        #expect(outcome.isSuccessful)
        #expect(outcome.changed)
        #expect(outcome.resultingReviewState == "accepted")
        #expect(outcome.actionReceiptID != nil)
        #expect(outcome.routingDecisionID != nil)
        #expect(outcome.routingItemID == fixture.itemID)
        #expect(outcome.routingDestination == fixture.decision.target)
    }

    @Test("Bookmark and non-bookmark approve and defer have Home Review Queue and CLI parity")
    func supportedSurfaceAndItemParity() throws {
        for itemType in ["bookmark", "note"] {
            for action in [CiderReviewAction.approve, .defer] {
                let seededItemID = UUID()
                let seededDecisionID = UUID()
                let seededFolderID = UUID()
                var baseline: CiderReviewActionOutcome?
                for surface in [CiderReviewInvokingSurface.home, .reviewQueue, .cli] {
                    let fixture = try RoutingFixture(
                        itemType: itemType,
                        itemID: seededItemID,
                        decisionID: seededDecisionID,
                        folderID: seededFolderID
                    )
                    defer { fixture.close() }
                    let outcome = coordinator(for: fixture).perform(
                        request(for: fixture, action: action, surface: surface)
                    )
                    #expect(outcome.isSuccessful)
                    #expect(outcome.changed)
                    #expect(outcome.evidenceStatus == .notRequired)
                    #expect(outcome.actionReceiptID != nil)
                    #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
                    if let baseline {
                        #expect(baseline.isSemanticallyEquivalentMutation(to: outcome))
                    } else {
                        baseline = outcome
                    }
                    fixture.close()
                }
                print("CID837-CP4-PARITY itemType=\(itemType) action=\(action.rawValue) receipt=\(baseline?.actionReceiptID ?? "missing") surfaces=home,review_queue,cli")
            }
        }
    }

    @Test("Explicit bookmark folder and Inbox corrections use the canonical writer on every supported surface")
    func explicitBookmarkCorrectionsHaveSurfaceParity() throws {
        for usesInbox in [false, true] {
            let seededItemID = UUID()
            let seededDecisionID = UUID()
            let seededFolderID = UUID()
            var baseline: CiderReviewActionOutcome?
            for surface in [CiderReviewInvokingSurface.home, .reviewQueue, .cli] {
                let fixture = try RoutingFixture(
                    itemType: "bookmark",
                    itemID: seededItemID,
                    decisionID: seededDecisionID,
                    folderID: seededFolderID
                )
                defer { fixture.close() }
                let destination = usesInbox ? fixture.decision.target : try #require(fixture.correctionTarget)
                var request = request(for: fixture, action: .correct, surface: surface)
                request.routingDestination = destination
                request.reason = "Private correction reason"
                let outcome = coordinator(for: fixture).perform(request)
                #expect(outcome.isSuccessful)
                #expect(outcome.changed)
                #expect(outcome.resultingReviewState == "corrected")
                #expect(outcome.routingDestination == destination)
                #expect(try scalarCount("routing_decisions", in: fixture.database) == 2)
                #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
                #expect(try scalarCount("mutation_audit", in: fixture.database) == 1)
                #expect(try scalarCount("review_lifecycle_events", in: fixture.database) == 1)
                if !usesInbox {
                    let path = fixture.root.appendingPathComponent("Projects/Research/Routing fixture.webloc")
                    #expect(FileManager.default.fileExists(atPath: path.path))
                    #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Projects/Research/.thumbnails/thumbnail.jpg").path))
                    #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Projects/Research/.originals/original.jpg").path))
                    #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Projects/Research/.originals/carousel.jpg").path))
                    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Inbox/Bookmarks/Routing fixture.webloc").path))
                    let inMemory = try #require(fixture.bookmarkService?.bookmarks.first)
                    #expect(inMemory.folderID == destination.folderID)
                    #expect(inMemory.relativePath == "Projects/Research/Routing fixture.webloc")
                    let cacheData = try Data(contentsOf: fixture.root.appendingPathComponent(".cider/bookmarks/_cider_bookmarks_index.json"))
                    let cachedBookmarks = try JSONDecoder().decode([Bookmark].self, from: cacheData)
                    let cached = try #require(cachedBookmarks.first { $0.id == fixture.itemID })
                    #expect(cached.folderID == destination.folderID)
                    #expect(cached.relativePath == "Projects/Research/Routing fixture.webloc")
                    #expect(BookmarkFileService.shared.loadSidecar(at: fixture.root.appendingPathComponent("Inbox/Bookmarks")).items.isEmpty)
                    #expect(BookmarkFileService.shared.loadSidecar(at: fixture.root.appendingPathComponent("Projects/Research")).items.isEmpty)
                }
                if let baseline {
                    #expect(baseline.isSemanticallyEquivalentMutation(to: outcome))
                } else {
                    baseline = outcome
                }
                fixture.close()
            }
            print("CID837-CP4-CORRECTION destination=\(usesInbox ? "inbox" : "folder") receipt=\(baseline?.actionReceiptID ?? "missing")")
        }
    }

    @Test("Stale missing invalid unresolved unauthorized and writer failures preserve every table and file")
    func failuresAreAtomicAndPrivate() throws {
        let scenarios: [(String, (RoutingFixture) throws -> CiderReviewActionRequest, CiderReviewActionErrorClassification)] = [
            ("stale", { fixture in
                var request = request(for: fixture, action: .approve, surface: .home)
                request.expectedVersion.updatedAt = .distantPast
                return request
            }, .staleExpectedVersion),
            ("missing", { fixture in
                var request = request(for: fixture, action: .correct, surface: .reviewQueue)
                request.routingDestination = nil
                return request
            }, .destinationRequired),
            ("invalid", { fixture in
                var request = request(for: fixture, action: .correct, surface: .reviewQueue)
                request.routingDestination = .init(kind: "folder", name: "Private", relativePath: "/Users/private/../Secret", folderID: UUID())
                return request
            }, .destinationInvalid),
            ("unresolved", { fixture in
                var request = request(for: fixture, action: .correct, surface: .reviewQueue)
                request.routingDestination = .init(kind: "folder", name: "Private", relativePath: "Private/Secret", folderID: UUID())
                return request
            }, .destinationUnresolved),
            ("unauthorized", { fixture in
                var request = request(for: fixture, action: .approve, surface: .home)
                request.routingDestination = fixture.correctionTarget
                return request
            }, .routingUnauthorized),
        ]
        for (name, makeRequest, classification) in scenarios {
            let fixture = try RoutingFixture(itemType: "bookmark")
            let tables = try allTableFingerprints(in: fixture.database)
            let files = try sourceFileFingerprints(in: fixture.root)
            let outcome = coordinator(for: fixture).perform(try makeRequest(fixture))
            #expect(outcome.error?.classification == classification, "scenario=\(name)")
            #expect(!outcome.changed)
            #expect(outcome.actionReceiptID == nil)
            #expect(try allTableFingerprints(in: fixture.database) == tables)
            #expect(try sourceFileFingerprints(in: fixture.root) == files)
            #expect(!outcome.message.contains("/Users/private"))
            var optimistic = HomeReviewActionState()
            optimistic.begin(rowID: name)
            optimistic.reconcile(rowID: name, result: .failed(message: outcome.message))
            #expect(!optimistic.pendingReviewIDs.contains(name))
            #expect(!optimistic.resolvedReviewIDs.contains(name))
            #expect(optimistic.errorMessage(for: name) == outcome.message)
            print("CID837-CP4-FAILURE scenario=\(name) tables=\(fingerprintDigest(tables)) tableCount=\(tables.count) files=\(fingerprintDigest(files)) fileCount=\(files.count) unchanged=true")
            fixture.close()
        }

        let ambiguous = try RoutingFixture(itemType: "bookmark")
        for path in ["Archive/Research"] {
            let folder = try ambiguous.database.prepare("""
                INSERT INTO folders (id, relative_path, created_at, updated_at)
                VALUES (?, ?, ?, ?);
                """)
            folder.bind(UUID().uuidString, at: 1)
                .bind(path, at: 2)
                .bind(DatabaseHelpers.encode(ambiguous.decision.createdAt), at: 3)
                .bind(DatabaseHelpers.encode(ambiguous.decision.createdAt), at: 4)
            try folder.step()
        }
        let ambiguousTables = try allTableFingerprints(in: ambiguous.database)
        let ambiguousFiles = try sourceFileFingerprints(in: ambiguous.root)
        var ambiguousRequest = request(for: ambiguous, action: .correct, surface: .reviewQueue)
        ambiguousRequest.routingDestination = .init(
            kind: "folder",
            name: "Research",
            relativePath: "Research",
            folderID: nil
        )
        let ambiguousOutcome = coordinator(for: ambiguous).perform(ambiguousRequest)
        #expect(ambiguousOutcome.error?.classification == .destinationAmbiguous)
        #expect(try allTableFingerprints(in: ambiguous.database) == ambiguousTables)
        #expect(try sourceFileFingerprints(in: ambiguous.root) == ambiguousFiles)
        ambiguous.close()

        let writer = try RoutingFixture(itemType: "note")
        let writerFiles = try sourceFileFingerprints(in: writer.root)
        try writer.database.runSQL("CREATE TRIGGER fail_routing_writer BEFORE INSERT ON routing_decisions WHEN NEW.source = 'routing.approve' BEGIN SELECT RAISE(ABORT, 'injected routing writer failure'); END;")
        let fingerprintAfterTrigger = try allTableFingerprints(in: writer.database)
        let outcome = coordinator(for: writer).perform(request(for: writer, action: .approve, surface: .home))
        #expect(outcome.error?.classification == .databaseFailure)
        #expect(try allTableFingerprints(in: writer.database) == fingerprintAfterTrigger)
        let writerFilesAfter = try sourceFileFingerprints(in: writer.root)
        #expect(writerFilesAfter == writerFiles, "fileDiff=\(fingerprintDifference(before: writerFiles, after: writerFilesAfter))")
        writer.close()

        let database = try RoutingFixture(itemType: "note")
        try database.database.runSQL("CREATE TRIGGER fail_routing_receipt BEFORE INSERT ON action_receipts BEGIN SELECT RAISE(ABORT, 'injected routing receipt failure'); END;")
        let databaseTables = try allTableFingerprints(in: database.database)
        let databaseFiles = try sourceFileFingerprints(in: database.root)
        let databaseOutcome = coordinator(for: database).perform(request(for: database, action: .approve, surface: .cli))
        #expect(databaseOutcome.error?.classification == .databaseFailure)
        #expect(try allTableFingerprints(in: database.database) == databaseTables)
        #expect(try sourceFileFingerprints(in: database.root) == databaseFiles)
        database.close()

        let assignment = try RoutingFixture(itemType: "bookmark")
        let unloadedWriter = VaultBookmarkService(database: assignment.database, schedulesEnrichment: false)
        let assignmentTables = try allTableFingerprints(in: assignment.database)
        let assignmentFiles = try sourceFileFingerprints(in: assignment.root)
        var correction = request(for: assignment, action: .correct, surface: .reviewQueue)
        correction.routingDestination = assignment.correctionTarget
        let assignmentOutcome = CiderReviewActionCoordinator(
            database: assignment.database,
            bookmarkService: unloadedWriter
        ).perform(correction)
        #expect(assignmentOutcome.error?.classification == .writerFailure)
        #expect(try allTableFingerprints(in: assignment.database) == assignmentTables)
        #expect(try sourceFileFingerprints(in: assignment.root) == assignmentFiles)
        assignment.close()
    }

    @Test("Bookmark correction compensates injected post-move and post-persist failures")
    func bookmarkCorrectionCompensatesInjectedAssignmentFailures() throws {
        let scenarios: [(String, CiderRoutingReviewMutationCheckpoint, CiderReviewActionErrorClassification)] = [
            ("after-file-move", .afterBookmarkFileMove, .writerFailure),
            ("after-bookmark-persist", .afterBookmarkPersistence, .databaseFailure),
        ]

        for (name, checkpoint, expectedClassification) in scenarios {
            let fixture = try RoutingFixture(itemType: "bookmark")
            let beforeTables = try allTableFingerprints(in: fixture.database)
            let beforeFiles = try sourceFileFingerprints(in: fixture.root)
            let beforeBookmark = try #require(fixture.bookmarkService?.bookmarks.first)
            var correction = request(for: fixture, action: .correct, surface: .reviewQueue)
            correction.routingDestination = fixture.correctionTarget

            let coordinator = CiderReviewActionCoordinator(
                database: fixture.database,
                bookmarkService: try #require(fixture.bookmarkService),
                routingFailureInjector: { reached in
                    guard reached == checkpoint else { return }
                    if checkpoint == .afterBookmarkPersistence {
                        throw CiderDatabaseError.runExec("injected post-persist routing failure")
                    }
                    throw InjectedRoutingFailure()
                }
            )
            let outcome = coordinator.perform(correction)

            #expect(outcome.error?.classification == expectedClassification, "scenario=\(name)")
            #expect(!outcome.changed)
            #expect(outcome.actionReceiptID == nil)
            #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
            #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
            let afterBookmark = try #require(fixture.bookmarkService?.bookmarks.first)
            #expect(afterBookmark.folderID == beforeBookmark.folderID)
            #expect(afterBookmark.relativePath == beforeBookmark.relativePath)
            #expect(afterBookmark.updatedAt == beforeBookmark.updatedAt)
            print("CID837-CP4-ROLLBACK scenario=\(name) tables=\(fingerprintDigest(beforeTables)) tableCount=\(beforeTables.count) files=\(fingerprintDigest(beforeFiles)) fileCount=\(beforeFiles.count) memoryRestored=true")
            fixture.close()
        }
    }

    @Test("Receipt failure after bookmark persistence rolls back database files cache sidecars and memory")
    func bookmarkCorrectionCompensatesLaterReceiptFailure() throws {
        let fixture = try RoutingFixture(itemType: "bookmark")
        try fixture.database.runSQL("CREATE TRIGGER fail_routing_receipt_after_assignment BEFORE INSERT ON action_receipts BEGIN SELECT RAISE(ABORT, 'injected routing receipt failure after assignment'); END;")
        let beforeTables = try allTableFingerprints(in: fixture.database)
        let beforeFiles = try sourceFileFingerprints(in: fixture.root)
        let beforeBookmark = try #require(fixture.bookmarkService?.bookmarks.first)
        var correction = request(for: fixture, action: .correct, surface: .cli)
        correction.routingDestination = fixture.correctionTarget

        let outcome = coordinator(for: fixture).perform(correction)

        #expect(outcome.error?.classification == .databaseFailure)
        #expect(!outcome.changed)
        #expect(outcome.actionReceiptID == nil)
        #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
        #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
        let afterBookmark = try #require(fixture.bookmarkService?.bookmarks.first)
        #expect(afterBookmark.folderID == beforeBookmark.folderID)
        #expect(afterBookmark.relativePath == beforeBookmark.relativePath)
        #expect(afterBookmark.updatedAt == beforeBookmark.updatedAt)
        print("CID837-CP4-ROLLBACK scenario=receipt-after-assignment tables=\(fingerprintDigest(beforeTables)) tableCount=\(beforeTables.count) files=\(fingerprintDigest(beforeFiles)) fileCount=\(beforeFiles.count) memoryRestored=true")
        fixture.close()
    }

    @Test("Exact retry and reopen reuse one private receipt while changed payload and version do not replay")
    func exactRetryReopenChangedBindingAndPrivacy() throws {
        let privateReason = "PRIVATE-REASON-/Users/secret/Journal.md"
        let fixture = try RoutingFixture(itemType: "bookmark")
        var exact = request(for: fixture, action: .correct, surface: .home)
        exact.routingDestination = fixture.correctionTarget
        exact.reason = privateReason
        let coordinator = coordinator(for: fixture)
        let first = coordinator.perform(exact)
        let afterFirst = try allTableFingerprints(in: fixture.database)
        let filesAfterFirst = try sourceFileFingerprints(in: fixture.root)
        let retry = coordinator.perform(exact)
        #expect(first.isSuccessful)
        #expect(retry.isSuccessful)
        #expect(!retry.changed)
        #expect(first.actionReceiptID == retry.actionReceiptID)
        #expect(try scalarCount("routing_decisions", in: fixture.database) == 2)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try allTableFingerprints(in: fixture.database) == afterFirst)
        #expect(try sourceFileFingerprints(in: fixture.root) == filesAfterFirst)
        let routedBookmark = try #require(fixture.bookmarkService?.bookmarks.first)
        #expect(routedBookmark.folderID == fixture.correctionTarget?.folderID)
        #expect(routedBookmark.relativePath == "Projects/Research/Routing fixture.webloc")

        let receipt = try #require(try SecondBrainActionReceiptLedgerService(database: fixture.database).inspect(id: first.actionReceiptID ?? ""))
        let durable = try #require(DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON))
        #expect(durable["requestFingerprint"]?.count == 64)
        #expect(durable["routingDecisionID"] == first.routingDecisionID?.uuidString)
        #expect(durable["reviewState"] == "corrected")
        #expect(durable["truthBoundary"] == "corrected_routing_destination")
        let serialized = [receipt.id, receipt.beforeJSON ?? "", receipt.afterJSON ?? "", receipt.receiptJSON ?? "", first.message].joined(separator: "\n")
        #expect(!serialized.contains(privateReason))
        #expect(!serialized.contains("Projects/Research"))
        #expect(!serialized.contains("/Users/secret"))

        var changedDestination = exact
        changedDestination.routingDestination = fixture.decision.target
        #expect(coordinator.perform(changedDestination).error?.classification == .alreadyReviewed)
        var changedReason = exact
        changedReason.reason = "Different private reason"
        #expect(coordinator.perform(changedReason).error?.classification == .alreadyReviewed)
        var changedVersion = exact
        changedVersion.expectedVersion.updatedAt = exact.expectedVersion.updatedAt.addingTimeInterval(0.000_001)
        #expect(coordinator.perform(changedVersion).error?.classification == .alreadyReviewed)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        let reopenedBookmarkService = VaultBookmarkService(database: reopened, schedulesEnrichment: false)
        reopenedBookmarkService.loadBookmarksFromDatabase(reopened)
        let reopenedCoordinator = CiderReviewActionCoordinator(
            database: reopened,
            bookmarkService: reopenedBookmarkService
        )
        let reopenedRetry = reopenedCoordinator.perform(exact)
        #expect(reopenedRetry.isSuccessful)
        #expect(!reopenedRetry.changed)
        #expect(reopenedRetry.actionReceiptID == first.actionReceiptID)
        #expect(try scalarCount("action_receipts", in: reopened) == 1)
        let reopenedBookmark = try #require(reopenedBookmarkService.bookmarks.first)
        #expect(reopenedBookmark.folderID == fixture.correctionTarget?.folderID)
        #expect(reopenedBookmark.relativePath == "Projects/Research/Routing fixture.webloc")
        print("CID837-CP4-REOPEN item=\(fixture.itemID.uuidString) candidate=\(fixture.decision.id.uuidString) result=\(first.routingDecisionID?.uuidString ?? "missing") receipt=\(receipt.id) requestFingerprint=\(durable["requestFingerprint"] ?? "missing") tables=\(fingerprintDigest(afterFirst)) files=\(fingerprintDigest(filesAfterFirst))")
        reopened.close()
        fixture.close()
    }

    @Test("Home routing rows expose approve correct and defer and reconcile failures")
    func homeRoutingRowContract() throws {
        let fixture = try RoutingFixture(itemType: "bookmark")
        defer { fixture.close() }
        let queueItem = try #require(try CiderReviewQueueService(database: fixture.database).list().items.first)
        let bookmark = try #require(fixture.bookmarkService?.bookmarks.first)
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark)],
            recentItems: [.bookmark(bookmark)],
            folders: [],
            reviewQueueItems: [queueItem],
            surfacingDays: 30
        )
        let row = try #require(snapshot.reviewCockpitItems.first)
        #expect(row.kindLabel == "Routing")
        #expect(row.reviewActions == [.accept, .correctRoute, .deferReview])
        #expect(row.candidateRef == "routing_decision:\(fixture.decision.id.uuidString)")
        #expect(row.candidateUpdatedAt == fixture.decision.createdAt)
        #expect(row.routingDestination == fixture.decision.target)
    }

    @Test("Routing CLI keeps help side effect free preserves aliases and executes emitted verification commands")
    func cliHelpAliasesRetryAndSafeCommands() throws {
        let help = try RoutingFixture(itemType: "note")
        let helpTables = try allTableFingerprints(in: help.database)
        let helpFiles = try sourceFileFingerprints(in: help.root)
        help.database.close()
        let plainHelp = try runCLI(args: ["routing", "--help"], vault: help.root)
        let jsonHelp = try runCLI(args: ["routing", "--help", "--json"], vault: help.root)
        #expect(plainHelp.status == 0)
        #expect(jsonHelp.status == 0)
        #expect(plainHelp.stdout.contains("routing approve"))
        #expect(jsonHelp.stdout.contains("routing correct"))
        let helpReopened = CiderDatabase()
        try helpReopened.open(at: help.databaseURL)
        #expect(try allTableFingerprints(in: helpReopened) == helpTables)
        let helpFilesAfter = try sourceFileFingerprints(in: help.root)
        #expect(helpFilesAfter == helpFiles, "fileDiff=\(fingerprintDifference(before: helpFiles, after: helpFilesAfter))")
        helpReopened.close()
        help.close()

        let action = try RoutingFixture(itemType: "bookmark")
        try FileManager.default.createDirectory(
            at: action.root.appendingPathComponent("Archive/Research"),
            withIntermediateDirectories: true
        )
        let duplicateFolder = try action.database.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, 'Archive/Research', ?, ?);
            """)
        duplicateFolder.bind(UUID().uuidString, at: 1)
            .bind(DatabaseHelpers.encode(action.decision.createdAt), at: 2)
            .bind(DatabaseHelpers.encode(action.decision.createdAt), at: 3)
        try duplicateFolder.step()
        let ambiguousFiles = try sourceFileFingerprints(in: action.root)
        action.database.close()
        StoragePaths.vaultOverride = action.previousVaultOverride
        StoragePaths.invalidateCachedDirectory()
        let ambiguous = try runCLI(
            args: ["routing", "correct", action.itemID.uuidString, "--folder", "Research", "--json"],
            vault: action.root
        )
        #expect(ambiguous.status != 0)
        #expect(ambiguous.stdout.contains("ambiguous"))
        let afterAmbiguous = CiderDatabase()
        try afterAmbiguous.open(at: action.databaseURL)
        #expect(try scalarCount("routing_decisions", in: afterAmbiguous) == 1)
        #expect(try scalarCount("action_receipts", in: afterAmbiguous) == 0)
        let ambiguousFilesAfter = try sourceFileFingerprints(in: action.root)
        #expect(ambiguousFilesAfter == ambiguousFiles, "fileDiff=\(fingerprintDifference(before: ambiguousFiles, after: ambiguousFilesAfter))")
        afterAmbiguous.close()

        let first = try runCLI(
            args: ["review", "approve", action.itemID.uuidString, "--actor", "user", "--json"],
            vault: action.root
        )
        #expect(first.status == 0, "stderr=\(first.stderr) stdout=\(first.stdout)")
        let payload = try parseJSONObject(first.stdout)
        #expect(payload["command"] as? String == "review.routing.approve")
        #expect(payload["reviewState"] as? String == "accepted")
        #expect(payload["reviewFamily"] as? String == nil || payload["reviewFamily"] as? String == "routing_decision")
        let selector = try #require(payload["expectedVersionSelector"] as? String)
        let receiptID = try #require(payload["actionReceiptID"] as? String)
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(receipt["id"] as? String == receiptID)
        #expect(receipt["canonicalReceipt"] as? Bool == true)

        let retry = try runCLI(
            args: ["routing", "approve", action.itemID.uuidString, "--actor", "user", "--expected-version", selector, "--json"],
            vault: action.root
        )
        #expect(retry.status == 0, "stderr=\(retry.stderr) stdout=\(retry.stdout)")
        let retryPayload = try parseJSONObject(retry.stdout)
        #expect(retryPayload["actionReceiptID"] as? String == receiptID)
        #expect(retryPayload["changed"] as? Bool == false)

        let plainRetry = try runCLI(
            args: ["routing", "approve", action.itemID.uuidString, "--actor", "user", "--expected-version", selector],
            vault: action.root
        )
        #expect(plainRetry.status == 0, "stderr=\(plainRetry.stderr) stdout=\(plainRetry.stdout)")
        #expect(plainRetry.stdout.contains(receiptID))

        let commands = try #require(payload["safeVerificationCommands"] as? [String])
        #expect(!commands.isEmpty)
        for command in commands {
            let parts = command.split(separator: " ").map(String.init)
            #expect(parts.first == "cider-cli")
            let verified = try runCLI(args: Array(parts.dropFirst()), vault: action.root)
            #expect(verified.status == 0, "command=\(command) stderr=\(verified.stderr) stdout=\(verified.stdout)")
        }
        let reopened = CiderDatabase()
        try reopened.open(at: action.databaseURL)
        #expect(try scalarCount("action_receipts", in: reopened) == 1)
        #expect(try scalarCount("routing_decisions", in: reopened) == 2)
        reopened.close()

        let privateMissingPath = "Private/Secret/DoesNotExist"
        let missing = try runCLI(
            args: ["routing", "correct", action.itemID.uuidString, "--path", privateMissingPath, "--json"],
            vault: action.root
        )
        #expect(missing.status != 0)
        #expect(!missing.stdout.contains(privateMissingPath))
        #expect(!FileManager.default.fileExists(atPath: action.root.appendingPathComponent(privateMissingPath).path))
        print("CID837-CP4-CLI item=\(action.itemID.uuidString) candidate=\(action.decision.id.uuidString) receipt=\(receiptID) selector=\(selector) verificationCommands=\(commands.count) helpUnchanged=true")
        action.close()
    }

    @MainActor
    private struct RoutingFixture {
        let root: URL
        let databaseURL: URL
        let database: CiderDatabase
        let itemID: UUID
        let decision: CiderRoutingDecision
        let bookmarkService: VaultBookmarkService?
        let correctionTarget: CiderRoutingDecisionTarget?
        let previousVaultOverride: URL?

        init(
            itemType: String,
            itemID seededItemID: UUID = UUID(),
            decisionID: UUID = UUID(),
            folderID seededFolderID: UUID = UUID()
        ) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cid837-cp4-red-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(".cider"),
                withIntermediateDirectories: true
            )
            previousVaultOverride = StoragePaths.vaultOverride
            if itemType == "bookmark" {
                StoragePaths.vaultOverride = root
                StoragePaths.invalidateCachedDirectory()
                StoragePaths.ensureVaultStructure()
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("Projects/Research"),
                    withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("Inbox/Bookmarks/.thumbnails"),
                    withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("Inbox/Bookmarks/.originals"),
                    withIntermediateDirectories: true
                )
                try Data("thumbnail".utf8).write(to: root.appendingPathComponent("Inbox/Bookmarks/.thumbnails/thumbnail.jpg"))
                try Data("original".utf8).write(to: root.appendingPathComponent("Inbox/Bookmarks/.originals/original.jpg"))
                try Data("carousel".utf8).write(to: root.appendingPathComponent("Inbox/Bookmarks/.originals/carousel.jpg"))
                try Data("pre-route-cache".utf8).write(to: root.appendingPathComponent(".cider/bookmarks/_cider_bookmarks_index.json"))
            }
            databaseURL = root.appendingPathComponent(".cider/cider.db")
            database = CiderDatabase()
            try database.open(at: databaseURL)
            itemID = seededItemID
            let now = Date(timeIntervalSince1970: 1_800_200_001.125)
            let item = try database.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, ?, 'Routing fixture', ?, ?, NULL, ?);
                """)
            item.bind(itemID.uuidString, at: 1)
                .bind(itemType, at: 2)
                .bind(DatabaseHelpers.encode(now), at: 3)
                .bind(DatabaseHelpers.encode(now), at: 4)
                .bind(itemType == "bookmark" ? "Inbox/Bookmarks/Routing fixture.webloc" : "Inbox/Notes/Routing fixture.md", at: 5)
            try item.step()
            if itemType == "bookmark" {
                let bookmark = try database.prepare("""
                    INSERT INTO bookmarks (
                        item_id, url, notes, notes_manually_set, title_manually_set,
                        thumbnail_relative_path, original_image_path, carousel_image_paths
                    ) VALUES (
                        ?, 'https://example.com/routing-fixture', '', 0, 0,
                        '.thumbnails/thumbnail.jpg', '.originals/original.jpg', '["carousel.jpg"]'
                    );
                    """)
                bookmark.bind(itemID.uuidString, at: 1)
                try bookmark.step()
                let plist = try PropertyListSerialization.data(
                    fromPropertyList: ["URL": "https://example.com/routing-fixture"],
                    format: .xml,
                    options: 0
                )
                try plist.write(to: root.appendingPathComponent("Inbox/Bookmarks/Routing fixture.webloc"), options: .atomic)
                let folder = try database.prepare("""
                    INSERT INTO folders (id, relative_path, created_at, updated_at)
                    VALUES (?, 'Projects/Research', ?, ?);
                    """)
                folder.bind(seededFolderID.uuidString, at: 1)
                    .bind(DatabaseHelpers.encode(now), at: 2)
                    .bind(DatabaseHelpers.encode(now), at: 3)
                try folder.step()
                correctionTarget = CiderRoutingDecisionTarget(
                    kind: "folder",
                    name: "Research",
                    relativePath: "Projects/Research",
                    folderID: seededFolderID
                )
                let service = VaultBookmarkService(
                    database: database,
                    schedulesEnrichment: false,
                    writesVaultCaches: true
                )
                service.loadBookmarksFromDatabase(database)
                let loadedBookmark = try #require(service.bookmarks.first)
                BookmarkFileService.shared.updateSidecar(
                    at: root.appendingPathComponent("Inbox/Bookmarks"),
                    setting: "Routing fixture.webloc",
                    to: BookmarkFileService.shared.sidecarEntry(from: loadedBookmark)
                )
                bookmarkService = service
            } else if itemType == "note" {
                let note = try database.prepare("INSERT INTO notes (item_id, content) VALUES (?, 'Routing fixture');")
                note.bind(itemID.uuidString, at: 1)
                try note.step()
                correctionTarget = nil
                bookmarkService = nil
            } else {
                correctionTarget = nil
                bookmarkService = nil
            }
            decision = try CiderRoutingDecisionService(database: database).recordDecision(
                itemID: itemID,
                itemType: itemType,
                target: CiderRoutingDecisionTarget(
                    kind: "inbox",
                    name: itemType == "bookmark" ? "Inbox/Bookmarks" : "Inbox/Notes",
                    relativePath: itemType == "bookmark" ? "Inbox/Bookmarks" : "Inbox/Notes",
                    folderID: nil
                ),
                confidence: 0.1,
                reason: "No deterministic route was available.",
                actor: "agent",
                source: "capture.add",
                reviewState: "needs_review",
                createdAt: now,
                decisionID: decisionID
            )
        }

        @MainActor
        func close() {
            database.close()
            StoragePaths.vaultOverride = previousVaultOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func coordinator(for fixture: RoutingFixture) -> CiderReviewActionCoordinator {
        CiderReviewActionCoordinator(
            database: fixture.database,
            bookmarkService: fixture.bookmarkService ?? .shared
        )
    }

    private func request(
        for fixture: RoutingFixture,
        action: CiderReviewAction,
        surface: CiderReviewInvokingSurface
    ) -> CiderReviewActionRequest {
        CiderReviewActionRequest(
            identity: .init(
                candidateRef: "routing_decision:\(fixture.decision.id.uuidString)",
                family: .routingDecision
            ),
            expectedVersion: .init(
                reviewState: fixture.decision.reviewState,
                updatedAt: fixture.decision.createdAt
            ),
            action: action,
            reason: action == .defer ? "Deferred for more context." : nil,
            routingItemID: fixture.itemID,
            routingDestination: action == .correct ? fixture.correctionTarget : fixture.decision.target,
            actor: Self.actor,
            surface: surface,
            exactEvidenceRequirement: .notRequired,
            mutationAuthority: .reviewApprovedCandidate
        )
    }

    private func scalarCount(_ table: String, in database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func allTableFingerprints(in database: CiderDatabase) throws -> [String: String] {
        let statement = try database.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
        var tables: [String] = []
        while try statement.step() { tables.append(statement.string(at: 0)) }
        return try Dictionary(uniqueKeysWithValues: tables.map { table in
            let pragma = try database.prepare("PRAGMA table_info(\(table));")
            var columns: [String] = []
            while try pragma.step() { columns.append(pragma.string(at: 1)) }
            let pairs = columns.flatMap { ["'\($0)'", "quote(\"\($0)\")"] }.joined(separator: ", ")
            let rowsStatement = try database.prepare("SELECT json_object(\(pairs)) FROM \(table);")
            var rows: [String] = []
            while try rowsStatement.step() { rows.append(rowsStatement.string(at: 0)) }
            return (table, "count=\(rows.count);sha256=\(sha256(Data(rows.sorted().joined(separator: "\n").utf8)))")
        })
    }

    private func sourceFileFingerprints(in root: URL) throws -> [String: String] {
        let standardizedRootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [:] }
        var values: [String: String] = [:]
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let standardizedPath = url.standardizedFileURL.path
            guard standardizedPath.hasPrefix(standardizedRootPath + "/") else { continue }
            let relative = String(standardizedPath.dropFirst(standardizedRootPath.count + 1))
            guard relative != ".cider/cider.db",
                  relative != ".cider/cider.db-wal",
                  relative != ".cider/cider.db-shm" else { continue }
            if relative.hasPrefix(".cider/"),
               !relative.hasPrefix(".cider/bookmarks/") {
                continue
            }
            values[relative] = sha256(try Data(contentsOf: url))
        }
        return values
    }

    private func fingerprintDigest(_ values: [String: String]) -> String {
        sha256(Data(values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "\n").utf8))
    }

    private func fingerprintDifference(before: [String: String], after: [String: String]) -> [String] {
        Set(before.keys).union(after.keys).sorted().compactMap { key in
            before[key] == after[key] ? nil : "\(key):\(before[key] ?? "missing")->\(after[key] ?? "missing")"
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func runCLI(args: [String], vault: URL) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = try cliURL()
        process.arguments = ["--vault", vault.path] + args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    private func cliURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try #require([
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ].first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}

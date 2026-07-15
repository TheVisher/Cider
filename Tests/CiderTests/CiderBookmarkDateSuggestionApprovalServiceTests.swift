import CryptoKit
import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("CID-837 Bookmark Date Suggestion Review Coordinator Tests", .serialized)
@MainActor
struct CiderBookmarkDateSuggestionApprovalServiceTests {
    private static let actor = "cid837-cp5-reviewer"
    private struct InjectedFailure: Error {}

    @Test("Home full Review Queue and CLI produce one typed mutation and canonical receipt")
    func supportedSurfaceParity() throws {
        for destination in CiderBookmarkDateSuggestionDestination.allCases {
            let bookmarkID = UUID()
            var baseline: CiderReviewActionOutcome?
            for surface in [CiderReviewInvokingSurface.home, .reviewQueue, .cli] {
                let fixture = try Fixture(bookmarkID: bookmarkID)
                let outcome = fixture.coordinator().perform(
                    fixture.request(destination: destination, surface: surface)
                )
                #expect(outcome.isSuccessful)
                #expect(outcome.changed)
                #expect(outcome.resultingReviewState == "accepted")
                #expect(outcome.bookmarkDateDestination == destination)
                #expect(outcome.evidenceStatus == .verifiedExactEvidence)
                #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
                #expect(try scalarCount("review_lifecycle_events", in: fixture.database) == 1)
                #expect(try scalarCount("mutation_audit", in: fixture.database) == 1)
                #expect(try scalarCount(destination == .dateCard ? "events" : "todos", in: fixture.database) == 1)
                #expect(try fixture.service().hasCanonicalAcceptedBinding(
                    candidateRef: CiderBookmarkDateSuggestionApprovalService.candidatePrefix + fixture.suggestion.suggestionKey,
                    bookmarkID: fixture.bookmark.id
                ))
                if let baseline {
                    #expect(baseline.isSemanticallyEquivalentMutation(to: outcome))
                } else {
                    baseline = outcome
                }
                fixture.close()
            }
        }
    }

    @Test("Deadline and release evidence can only use the explicitly chosen destination")
    func explicitDestinationNeverInferred() throws {
        let fixture = try Fixture(kind: "deadline")
        defer { fixture.close() }

        var missing = fixture.request(destination: .todo, surface: .home)
        missing.bookmarkDateDestination = nil
        let refused = fixture.coordinator().perform(missing)
        #expect(refused.error?.classification == .destinationRequired)
        #expect(try scalarCount("items", in: fixture.database) == 1)

        let approved = fixture.coordinator().perform(
            fixture.request(destination: .dateCard, surface: .home)
        )
        #expect(approved.isSuccessful)
        #expect(approved.bookmarkDateDestination == .dateCard)
        #expect(try scalarCount("events", in: fixture.database) == 1)
        #expect(try scalarCount("todos", in: fixture.database) == 0)
    }

    @Test("Exact candidate item version and evidence are mandatory and ambiguity fails closed")
    func exactBindingAndAmbiguity() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let tables = try allTableFingerprints(in: fixture.database)
        let files = try sourceFileFingerprints(in: fixture.root)

        var wrongItem = fixture.request(destination: .dateCard, surface: .reviewQueue)
        wrongItem.bookmarkDateItemID = UUID()
        #expect(fixture.coordinator().perform(wrongItem).error?.classification == .invalidCandidateIdentity)

        var stale = fixture.request(destination: .dateCard, surface: .reviewQueue)
        stale.expectedVersion.updatedAt = .distantPast
        #expect(fixture.coordinator().perform(stale).error?.classification == .staleExpectedVersion)

        var missingEvidence = fixture.request(destination: .dateCard, surface: .reviewQueue)
        var alteredEvidence = fixture.suggestion
        alteredEvidence.nextSafeAction = "private_changed_payload"
        missingEvidence.bookmarkDateExactEvidence = alteredEvidence
        #expect(fixture.coordinator().perform(missingEvidence).error?.classification == .missingExactEvidence)

        let ambiguous = fixture.coordinator(suggestions: [fixture.suggestion, fixture.suggestion]).perform(
            fixture.request(destination: .dateCard, surface: .reviewQueue)
        )
        #expect(ambiguous.error?.classification == .destinationAmbiguous)
        #expect(try allTableFingerprints(in: fixture.database) == tables)
        #expect(try sourceFileFingerprints(in: fixture.root) == files)
    }

    @Test("Exact retry and reopen reuse one receipt item and reciprocal link pair")
    func retryAndReopenAreIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let request = fixture.request(destination: .todo, surface: .cli)
        let first = fixture.coordinator().perform(request)
        let retry = fixture.coordinator().perform(request)
        let reopened = fixture.coordinator().perform(request)

        #expect(first.isSuccessful && first.changed)
        #expect(retry.isSuccessful && !retry.changed)
        #expect(reopened.isSuccessful && !reopened.changed)
        #expect(first.actionReceiptID == retry.actionReceiptID)
        #expect(retry.actionReceiptID == reopened.actionReceiptID)
        #expect(first.targetOwnerRef == retry.targetOwnerRef)
        #expect(try scalarCount("todos", in: fixture.database) == 1)
        #expect(try scalarCount("item_links", in: fixture.database) == 2)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(fixture.todoStorage.todoCards.count == 1)
    }

    @Test("Changed destination payload and version never replay or duplicate")
    func changedBindingDoesNotReplay() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let first = fixture.coordinator().perform(
            fixture.request(destination: .dateCard, surface: .home)
        )
        #expect(first.isSuccessful)

        let changedDestination = fixture.coordinator().perform(
            fixture.request(destination: .todo, surface: .cli)
        )
        #expect(changedDestination.error?.classification == .alreadyReviewed)

        var changedPayload = fixture.request(destination: .dateCard, surface: .cli)
        var evidence = fixture.suggestion
        evidence.nextSafeAction = "changed_binding"
        changedPayload.bookmarkDateExactEvidence = evidence
        #expect(fixture.coordinator().perform(changedPayload).error?.classification == .missingExactEvidence)

        var changedVersion = fixture.request(destination: .dateCard, surface: .cli)
        changedVersion.expectedVersion.updatedAt = Date(timeIntervalSince1970: fixture.version.timeIntervalSince1970.nextUp)
        #expect(fixture.coordinator().perform(changedVersion).error?.classification == .staleExpectedVersion)
        #expect(try scalarCount("events", in: fixture.database) == 1)
        #expect(try scalarCount("todos", in: fixture.database) == 0)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
    }

    @Test("Canonical receipt identity is surface neutral and content private")
    func receiptPrivacy() throws {
        let fixture = try Fixture(
            title: "Private concert October 23, 2027",
            url: "https://private.example/secret-token",
            snippet: "Private evidence October 23, 2027 token-123"
        )
        defer { fixture.close() }
        let outcome = fixture.coordinator().perform(
            fixture.request(destination: .dateCard, surface: .home)
        )
        let receiptID = try #require(outcome.actionReceiptID)
        #expect(receiptID.hasPrefix("bookmark-date-review:approve:"))
        #expect(receiptID.count == "bookmark-date-review:approve:".count + 64)
        let receipt = try #require(try SecondBrainActionReceiptLedgerService(database: fixture.database).inspect(id: receiptID))
        let persisted = [receipt.id, receipt.beforeJSON, receipt.afterJSON, receipt.receiptJSON]
            .compactMap { $0 }
            .joined(separator: "\n")
        #expect(!persisted.contains(fixture.bookmark.title))
        #expect(!persisted.contains(fixture.bookmark.urlString))
        #expect(!persisted.contains(fixture.suggestion.sourceSnippet))
        #expect(!receiptID.contains("home"))
        #expect(!receiptID.contains("review_queue"))
        #expect(!receiptID.contains("cli"))
    }

    @Test("Every injected partial-writer failure restores every table and source file")
    func failuresRollbackEveryTableAndFile() throws {
        let checkpoints: [CiderBookmarkDateSuggestionMutationCheckpoint] = [
            .afterItemCreation,
            .afterReciprocalLink,
            .afterRequiredAudit,
            .afterLifecycle,
            .afterReceipt,
        ]
        for destination in CiderBookmarkDateSuggestionDestination.allCases {
            for checkpoint in checkpoints {
                let fixture = try Fixture()
                let tables = try allTableFingerprints(in: fixture.database)
                let files = try sourceFileFingerprints(in: fixture.root)
                let coordinator = fixture.coordinator(failureInjector: { reached in
                    if reached == checkpoint { throw InjectedFailure() }
                })
                let outcome = coordinator.perform(
                    fixture.request(destination: destination, surface: .reviewQueue)
                )
                #expect(outcome.error?.classification == .writerFailure)
                #expect(try allTableFingerprints(in: fixture.database) == tables)
                #expect(try sourceFileFingerprints(in: fixture.root) == files)
                #expect(fixture.dateCardStorage.dateCards.isEmpty)
                #expect(fixture.todoStorage.todoCards.isEmpty)
                fixture.close()
            }
        }
    }

    @Test("Date and Todo database failures after file creation restore canonical state")
    func preTokenDatabaseFailuresRestoreCanonicalState() throws {
        for destination in CiderBookmarkDateSuggestionDestination.allCases {
            let fixture = try Fixture()
            let itemType = destination == .dateCard ? "event" : "todo"
            try fixture.database.runSQL("""
                CREATE TRIGGER fail_bookmark_date_item_persistence
                BEFORE INSERT ON items
                WHEN NEW.type = '\(itemType)'
                BEGIN
                    SELECT RAISE(ABORT, 'injected bookmark date item persistence failure');
                END;
                """)
            let tables = try allTableFingerprints(in: fixture.database)
            let files = try sourceFileFingerprints(in: fixture.root)

            let outcome = fixture.coordinator().perform(
                fixture.request(destination: destination, surface: .reviewQueue)
            )

            #expect(outcome.error?.classification == .databaseFailure)
            #expect(try allTableFingerprints(in: fixture.database) == tables)
            #expect(try sourceFileFingerprints(in: fixture.root) == files)
            #expect(fixture.dateCardStorage.dateCards.isEmpty)
            #expect(fixture.todoStorage.todoCards.isEmpty)
            #expect(fixture.dateCardStorage._dateSuggestionIndexEntryCountForTesting() == 0)
            #expect(fixture.todoStorage._dateSuggestionIndexEntryCountForTesting() == 0)
            #expect(try scalarCount("events", in: fixture.database) == 0)
            #expect(try scalarCount("todos", in: fixture.database) == 0)
            #expect(try scalarCount("item_links", in: fixture.database) == 0)
            #expect(try scalarCount("mutation_audit", in: fixture.database) == 0)
            #expect(try scalarCount("review_lifecycle_events", in: fixture.database) == 0)
            #expect(try scalarCount("action_receipts", in: fixture.database) == 0)
            fixture.close()
        }
    }

    @Test("Failed optimistic action retains its exact row and recovery message")
    func failedOptimisticRowReconciles() {
        var state = HomeReviewActionState()
        state.begin(rowID: "bookmark-date-row")
        state.reconcile(
            rowID: "bookmark-date-row",
            result: .failed(message: "Refresh the review list and retry with an explicit destination.")
        )
        #expect(!state.resolvedReviewIDs.contains("bookmark-date-row"))
        #expect(!state.pendingReviewIDs.contains("bookmark-date-row"))
        #expect(state.errorMessage(for: "bookmark-date-row")?.contains("explicit destination") == true)
    }

    @Test("Coordinator is the only production surface caller and adapter keeps the writer singular")
    func singleWriterAuthority() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let coordinator = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Services/CiderReviewActionCoordinator.swift"), encoding: .utf8)
        let panel = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        let cli = try String(contentsOf: root.appendingPathComponent("Sources/CiderCLI/CiderCLI.swift"), encoding: .utf8)
        #expect(coordinator.contains("CiderBookmarkDateSuggestionReviewActionAdapter"))
        #expect(coordinator.contains("service.perform("))
        #expect(!panel.contains("CiderBookmarkDateSuggestionApprovalService().approve"))
        #expect(!panel.contains("CiderBookmarkDateSuggestionApprovalService().perform"))
        #expect(!cli.contains("CiderBookmarkDateSuggestionApprovalService().approve"))
        #expect(!cli.contains("CiderBookmarkDateSuggestionApprovalService().perform"))
    }

    @Test("Approval JSON remains compatible and adds canonical receipt fields")
    func approvalJSONCompatibility() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let mutation = try fixture.service().perform(
            fixture.writerRequest(destination: .todo)
        )
        let dict = bookmarkDateSuggestionApprovalResultToDict(mutation.approval)
        #expect(dict["command"] as? String == "bookmark.date-suggestion.approve")
        #expect(dict["action"] as? String == "created_todo")
        #expect(dict["created"] as? Bool == true)
        #expect(dict["reused"] as? Bool == false)
        #expect(dict["changed"] as? Bool == true)
        #expect(dict["destination"] as? String == "todo")
        #expect(dict["actionReceiptID"] as? String == mutation.receiptID)
        #expect((dict["safeVerificationCommands"] as? [String])?.allSatisfy { $0.hasPrefix("cider-cli ") } == true)
        #expect(dict["todoID"] != nil)
    }

    @Test("General review CLI and both existing date aliases share one receipt and item")
    func cliAndAliasParity() throws {
        let fixture = try Fixture()
        let actualSuggestion = try #require(CiderBookmarkDateSuggestionService().suggestions(for: fixture.bookmark).first)
        let candidateRef = CiderBookmarkDateSuggestionApprovalService.candidatePrefix + actualSuggestion.suggestionKey
        let selector = CiderBookmarkDateSuggestionApprovalService.expectedVersionSelector(
            reviewState: CiderBookmarkDateSuggestionApprovalService.pendingReviewState,
            updatedAt: fixture.version
        )
        fixture.database.close()
        let beforeApproval = try runCLI(
            args: ["review", "list", "--kind", "bookmark_date_suggestion", "--json"],
            vault: fixture.root
        )
        #expect(beforeApproval.status == 0)
        let beforeApprovalJSON = try parseJSONObject(beforeApproval.stdout)
        #expect(beforeApprovalJSON["count"] as? Int == 1)
        let activeBefore = try #require(beforeApprovalJSON["items"] as? [[String: Any]])
        #expect(activeBefore.count == 1)
        #expect(activeBefore.first?["candidateRef"] as? String == candidateRef)

        let general = try runCLI(
            args: [
                "review", "approve", candidateRef,
                "--item-id", fixture.bookmark.id.uuidString,
                "--destination", "todo",
                "--expected-version", selector,
                "--json",
            ],
            vault: fixture.root
        )
        #expect(general.status == 0)
        let generalJSON = try parseJSONObject(general.stdout)
        let receiptID = try #require(generalJSON["actionReceiptID"] as? String)
        let todoID = try #require(generalJSON["todoID"] as? String)
        #expect(generalJSON["changed"] as? Bool == true)

        let afterApproval = try runCLI(
            args: ["review", "list", "--kind", "bookmark_date_suggestion", "--json"],
            vault: fixture.root
        )
        #expect(afterApproval.status == 0)
        let afterApprovalJSON = try parseJSONObject(afterApproval.stdout)
        #expect(afterApprovalJSON["count"] as? Int == 0)
        #expect((afterApprovalJSON["items"] as? [[String: Any]])?.isEmpty == true)

        let listed = try runCLI(
            args: ["bookmark", "date-suggestions", fixture.bookmark.id.uuidString, "--json"],
            vault: fixture.root
        )
        #expect(listed.status == 0)
        let listedJSON = try parseJSONObject(listed.stdout)
        #expect(listedJSON["expectedVersion"] as? String == selector)

        for alias in ["date-suggestions", "dates"] {
            let retry = try runCLI(
                args: [
                    "bookmark", alias, "approve", fixture.bookmark.id.uuidString,
                    "--key", actualSuggestion.suggestionKey,
                    "--destination", "todo",
                    "--expected-version", selector,
                    "--json",
                ],
                vault: fixture.root
            )
            #expect(retry.status == 0)
            let retryJSON = try parseJSONObject(retry.stdout)
            #expect(retryJSON["actionReceiptID"] as? String == receiptID)
            #expect(retryJSON["todoID"] as? String == todoID)
            #expect(retryJSON["changed"] as? Bool == false)
            #expect(retryJSON["command"] as? String == CiderBookmarkDateSuggestionApprovalService.canonicalCommand)
        }
        try fixture.database.open(at: fixture.root.appendingPathComponent(".cider/cider.db"))
        #expect(try scalarCount("todos", in: fixture.database) == 1)
        #expect(try scalarCount("item_links", in: fixture.database) == 2)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        fixture.close()
    }

    @Test("Bookmark date help and list commands are read only and emit executable verification commands")
    func cliHelpAndListAreReadOnly() throws {
        let fixture = try Fixture()
        fixture.database.close()
        let warmup = try runCLI(
            args: ["review", "list", "--kind", "bookmark_date_suggestion", "--json"],
            vault: fixture.root
        )
        #expect(warmup.status == 0)
        try fixture.database.open(at: fixture.root.appendingPathComponent(".cider/cider.db"))
        let beforeTables = try allTableFingerprints(in: fixture.database)
        let beforeFiles = try sourceFileFingerprints(in: fixture.root)
        fixture.database.close()

        let help = try runCLI(
            args: ["bookmark", "dates", "approve", "--help", "--json"],
            vault: fixture.root
        )
        #expect(help.status == 0)
        let helpJSON = try parseJSONObject(help.stdout)
        #expect(helpJSON["readOnly"] as? Bool == true)
        #expect(helpJSON["changed"] as? Bool == false)
        let helpCommand = try #require((helpJSON["safeVerificationCommands"] as? [String])?.first)
        #expect(helpCommand == "cider-cli bookmark dates approve --help --json")
        let repeatedHelp = try runCLI(
            args: helpCommand.split(separator: " ").dropFirst().map(String.init),
            vault: fixture.root
        )
        #expect(repeatedHelp.status == 0)

        let list = try runCLI(
            args: ["review", "list", "--kind", "bookmark_date_suggestion", "--json"],
            vault: fixture.root
        )
        #expect(list.status == 0)
        let listJSON = try parseJSONObject(list.stdout)
        #expect(listJSON["readOnly"] as? Bool == true)
        #expect(listJSON["changed"] as? Bool == false)
        let items = try #require(listJSON["items"] as? [[String: Any]])
        let commands = try #require(items.first?["safeVerificationCommands"] as? [String])
        #expect(commands.count == 2)
        #expect(commands.allSatisfy {
            $0.hasPrefix("cider-cli review approve bookmark_date_suggestion:")
                && $0.contains(" --item-id ")
                && $0.contains(" --destination ")
                && $0.contains(" --expected-version ")
                && $0.hasSuffix(" --json")
        })

        try fixture.database.open(at: fixture.root.appendingPathComponent(".cider/cider.db"))
        let afterTables = try allTableFingerprints(in: fixture.database)
        let afterFiles = try sourceFileFingerprints(in: fixture.root)
        #expect(afterTables == beforeTables)
        #expect(afterFiles == beforeFiles)
        fixture.close()
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let database: CiderDatabase
        let bookmark: Bookmark
        let suggestion: CiderBookmarkDateSuggestion
        let version: Date
        let dateCardStorage: DateCardStorage
        let todoStorage: TodoCardStorage
        let previousVaultOverride: URL?

        init(
            bookmarkID: UUID = UUID(),
            kind: String = "event_date",
            title: String = "Concert October 23, 2027",
            url: String = "https://example.com/concert",
            snippet: String? = nil
        ) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cid837-cp5-\(UUID().uuidString)", isDirectory: true)
            previousVaultOverride = StoragePaths.vaultOverride
            StoragePaths.vaultOverride = root
            StoragePaths.invalidateCachedDirectory()
            StoragePaths.ensureVaultStructure()
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".cider"), withIntermediateDirectories: true)
            database = CiderDatabase()
            try database.open(at: root.appendingPathComponent(".cider/cider.db"))
            version = Date(timeIntervalSince1970: 1_820_000_000.125)
            bookmark = Bookmark(
                id: bookmarkID,
                title: title,
                urlString: url,
                createdAt: version,
                updatedAt: version,
                notes: "Official source evidence",
                relativePath: "Inbox/Bookmarks/Fixture.webloc"
            )
            let item = try database.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, 'bookmark', ?, ?, ?, NULL, 'Inbox/Bookmarks/Fixture.webloc');
                """)
            item.bind(bookmark.id.uuidString, at: 1)
                .bind(bookmark.title, at: 2)
                .bind(DatabaseHelpers.encode(version), at: 3)
                .bind(DatabaseHelpers.encode(version), at: 4)
            try item.step()
            let detail = try database.prepare("""
                INSERT INTO bookmarks (item_id, url, notes, notes_manually_set, title_manually_set)
                VALUES (?, ?, ?, 1, 1);
                """)
            detail.bind(bookmark.id.uuidString, at: 1)
                .bind(bookmark.urlString, at: 2)
                .bind(bookmark.notes, at: 3)
            try detail.step()
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["URL": bookmark.urlString],
                format: .xml,
                options: 0
            )
            try plist.write(
                to: root.appendingPathComponent("Inbox/Bookmarks/Fixture.webloc"),
                options: .atomic
            )
            suggestion = CiderBookmarkDateSuggestion(
                bookmarkID: bookmark.id,
                bookmarkTitle: bookmark.title,
                sourceURL: bookmark.urlString,
                kind: kind,
                confidence: 0.91,
                date: Date(timeIntervalSince1970: 1_824_240_000),
                sourceField: "title",
                sourceSnippet: snippet ?? bookmark.title,
                nextSafeAction: "review_date_suggestion"
            )
            dateCardStorage = DateCardStorage(database: database)
            todoStorage = TodoCardStorage(database: database)
        }

        func service(
            suggestions: [CiderBookmarkDateSuggestion]? = nil,
            failureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)? = nil
        ) -> CiderBookmarkDateSuggestionApprovalService {
            let provided = suggestions ?? [suggestion]
            return CiderBookmarkDateSuggestionApprovalService(
                database: database,
                bookmarkProvider: { [bookmark = self.bookmark] in [bookmark] },
                dateCardStorage: dateCardStorage,
                todoStorage: todoStorage,
                dateSuggestionProvider: { _ in provided },
                failureInjector: failureInjector
            )
        }

        func coordinator(
            suggestions: [CiderBookmarkDateSuggestion]? = nil,
            failureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)? = nil
        ) -> CiderReviewActionCoordinator {
            CiderReviewActionCoordinator(
                bookmarkDateService: service(
                    suggestions: suggestions,
                    failureInjector: failureInjector
                )
            )
        }

        func request(
            destination: CiderBookmarkDateSuggestionDestination,
            surface: CiderReviewInvokingSurface
        ) -> CiderReviewActionRequest {
            CiderReviewActionRequest(
                identity: .init(
                    candidateRef: CiderBookmarkDateSuggestionApprovalService.candidatePrefix + suggestion.suggestionKey,
                    family: .bookmarkDateSuggestion
                ),
                expectedVersion: .init(
                    reviewState: CiderBookmarkDateSuggestionApprovalService.pendingReviewState,
                    updatedAt: version
                ),
                action: .approve,
                bookmarkDateItemID: bookmark.id,
                bookmarkDateDestination: destination,
                bookmarkDateExactEvidence: suggestion,
                actor: CiderBookmarkDateSuggestionApprovalServiceTests.actor,
                surface: surface,
                exactEvidenceRequirement: .required,
                mutationAuthority: .reviewApprovedCandidate
            )
        }

        func writerRequest(
            destination: CiderBookmarkDateSuggestionDestination
        ) -> CiderBookmarkDateSuggestionApprovalRequest {
            CiderBookmarkDateSuggestionApprovalRequest(
                candidateRef: CiderBookmarkDateSuggestionApprovalService.candidatePrefix + suggestion.suggestionKey,
                bookmarkID: bookmark.id,
                expectedReviewState: CiderBookmarkDateSuggestionApprovalService.pendingReviewState,
                expectedUpdatedAt: version,
                exactEvidence: suggestion,
                destination: destination,
                actor: CiderBookmarkDateSuggestionApprovalServiceTests.actor
            )
        }

        func close() {
            database.close()
            StoragePaths.vaultOverride = previousVaultOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: root)
        }
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
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [:] }
        var values: [String: String] = [:]
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(path.dropFirst(rootPath.count + 1))
            guard ![".cider/cider.db", ".cider/cider.db-wal", ".cider/cider.db-shm"].contains(relative) else { continue }
            if relative.hasPrefix(".cider/"),
               !relative.hasPrefix(".cider/bookmarks/"),
               !relative.hasPrefix(".cider/date-cards/"),
               !relative.hasPrefix(".cider/todos/") {
                continue
            }
            values[relative] = sha256(try Data(contentsOf: url))
        }
        return values
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

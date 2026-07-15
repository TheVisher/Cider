import CryptoKit
import Foundation

struct CiderBookmarkDateSuggestionApprovalDraft: Equatable {
    let title: String
    let details: String
    let startAt: Date
    let allDay: Bool
    let actionURLString: String?
}

struct CiderBookmarkDateSuggestionTodoApprovalDraft: Equatable {
    let title: String
    let details: String
    let dueDate: Date
    let actionURLString: String?
}

enum CiderBookmarkDateSuggestionDestination: String, CaseIterable, Equatable, Sendable {
    case dateCard = "date"
    case todo

    var entityType: LibraryEntityType {
        switch self {
        case .dateCard: .dateCard
        case .todo: .todo
        }
    }
}

enum CiderBookmarkDateSuggestionApprovalAction: String, Equatable, Sendable {
    case createdDateCard = "created_date_card"
    case reusedExistingDateCard = "reused_existing_date_card"
    case createdTodo = "created_todo"
    case reusedExistingTodo = "reused_existing_todo"
}

struct CiderBookmarkDateSuggestionApprovalResult: Equatable {
    let command: String
    let bookmarkID: UUID
    let bookmarkTitle: String
    let sourceURL: String
    let suggestion: CiderBookmarkDateSuggestion
    let action: CiderBookmarkDateSuggestionApprovalAction
    let dateCard: DateCard?
    let todo: TodoCard?
    var changed: Bool = true
    var actionReceiptID: String? = nil
    var truthBoundary: String = "approved_bookmark_date_suggestion_created_item"
    var expectedVersionSelector: String? = nil
    var safeVerificationCommands: [String] = []
    var safeNextCommands: [String] = []

    var created: Bool {
        switch action {
        case .createdDateCard, .createdTodo: true
        case .reusedExistingDateCard, .reusedExistingTodo: false
        }
    }

    var reused: Bool { !created }

    var createdItemType: LibraryEntityType {
        todo == nil ? .dateCard : .todo
    }

    var destination: CiderBookmarkDateSuggestionDestination {
        todo == nil ? .dateCard : .todo
    }

    var targetOwnerRef: String? {
        if let todo { return "todo:\(todo.id.uuidString)" }
        if let dateCard { return "dateCard:\(dateCard.id.uuidString)" }
        return nil
    }
}

struct CiderBookmarkDateSuggestionApprovalRequest: Equatable {
    let candidateRef: String
    let bookmarkID: UUID
    let expectedReviewState: String
    let expectedUpdatedAt: Date
    let exactEvidence: CiderBookmarkDateSuggestion
    let destination: CiderBookmarkDateSuggestionDestination
    let actor: String
}

struct CiderBookmarkDateSuggestionApprovalMutationResult: Equatable {
    let approval: CiderBookmarkDateSuggestionApprovalResult
    let receiptID: String
    let changed: Bool
    let truthBoundary: String
}

enum CiderBookmarkDateSuggestionMutationCheckpoint: Equatable {
    case afterItemCreation
    case afterReciprocalLink
    case afterRequiredAudit
    case afterLifecycle
    case afterReceipt
}

enum CiderBookmarkDateSuggestionApprovalError: Error, LocalizedError, Equatable {
    case databaseUnavailable
    case bookmarkNotFound(UUID)
    case invalidCandidateIdentity
    case candidateUnavailable
    case ambiguousCandidate
    case staleExpectedVersion
    case alreadyReviewed
    case missingExactEvidence
    case destinationRequired
    case unsupportedAction
    case createFailed(bookmarkID: UUID)
    case linkFailed(String)
    case compensationFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "The bookmark date review database is unavailable. Nothing was changed."
        case .bookmarkNotFound(let id):
            return "No bookmark found with id \(id.uuidString)"
        case .invalidCandidateIdentity:
            return "This bookmark date suggestion identity is invalid. Refresh the review list; nothing was changed."
        case .candidateUnavailable:
            return "This bookmark date suggestion is no longer available. Refresh the review list; nothing was changed."
        case .ambiguousCandidate:
            return "This bookmark date suggestion is ambiguous. Refresh and choose one exact candidate; nothing was changed."
        case .staleExpectedVersion:
            return "This bookmark date suggestion changed after it loaded. Refresh the review list before acting."
        case .alreadyReviewed:
            return "This bookmark date suggestion was already reviewed with a different binding. Refresh to see its current state."
        case .missingExactEvidence:
            return "Cider could not verify the exact bookmark source evidence, so the action was blocked."
        case .destinationRequired:
            return "Choose Date Card or Todo explicitly before approving. Nothing was changed."
        case .unsupportedAction:
            return "Only explicit approval is supported for bookmark date suggestions. Nothing was changed."
        case .createFailed(let bookmarkID):
            return "Failed to create the approved date suggestion item for bookmark \(bookmarkID.uuidString)"
        case .linkFailed(let message):
            return "Failed to link the date suggestion approval: \(message)"
        case .compensationFailed:
            return "Cider could not safely reconcile a failed bookmark date approval. Reopen the review list before retrying."
        }
    }
}

@MainActor
final class CiderBookmarkDateSuggestionApprovalService {
    nonisolated static let candidatePrefix = "bookmark_date_suggestion:"
    nonisolated static let pendingReviewState = "needs_review"
    nonisolated static let canonicalCommand = "bookmark.date-suggestion.approve"

    private let database: CiderDatabase
    private let bookmarkProvider: () -> [Bookmark]
    private let dateCardProvider: () -> [DateCard]
    private let todoProvider: () -> [TodoCard]
    private let dateSuggestionProvider: (Bookmark) -> [CiderBookmarkDateSuggestion]
    private let dateCardStorage: DateCardStorage
    private let todoStorage: TodoCardStorage
    private let calendar: Calendar
    private let failureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)?

    init(
        database: CiderDatabase = .shared,
        bookmarkService: VaultBookmarkService = .shared,
        dateCardStorage: DateCardStorage = .shared,
        todoStorage: TodoCardStorage = .shared,
        dateSuggestionService: CiderBookmarkDateSuggestionService = CiderBookmarkDateSuggestionService(),
        calendar: Calendar = .current,
        failureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)? = nil
    ) {
        self.database = database
        bookmarkProvider = { bookmarkService.bookmarks }
        dateCardProvider = { dateCardStorage.dateCards }
        todoProvider = { todoStorage.todoCards }
        dateSuggestionProvider = { dateSuggestionService.suggestions(for: $0) }
        self.dateCardStorage = dateCardStorage
        self.todoStorage = todoStorage
        self.calendar = calendar
        self.failureInjector = failureInjector
    }

    init(
        database: CiderDatabase,
        bookmarkProvider: @escaping () -> [Bookmark],
        dateCardStorage: DateCardStorage,
        todoStorage: TodoCardStorage,
        dateSuggestionProvider: @escaping (Bookmark) -> [CiderBookmarkDateSuggestion],
        calendar: Calendar = .current,
        failureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)? = nil
    ) {
        self.database = database
        self.bookmarkProvider = bookmarkProvider
        dateCardProvider = { dateCardStorage.dateCards }
        todoProvider = { todoStorage.todoCards }
        self.dateSuggestionProvider = dateSuggestionProvider
        self.dateCardStorage = dateCardStorage
        self.todoStorage = todoStorage
        self.calendar = calendar
        self.failureInjector = failureInjector
    }

    func perform(
        _ request: CiderBookmarkDateSuggestionApprovalRequest
    ) throws -> CiderBookmarkDateSuggestionApprovalMutationResult {
        let validated = try validatedCandidate(for: request)
        let fingerprint = Self.requestFingerprint(request)
        let receiptID = Self.actionReceiptID(fingerprint: fingerprint)
        if let replay = try replayedMutation(
            request: request,
            bookmark: validated.bookmark,
            fingerprint: fingerprint,
            receiptID: receiptID
        ) {
            return replay
        }
        if try priorReceiptExists(candidateRef: request.candidateRef) {
            throw CiderBookmarkDateSuggestionApprovalError.alreadyReviewed
        }

        var dateCreation: DateCardStorage.CompensatableDateSuggestionCreation?
        var todoCreation: TodoCardStorage.CompensatableDateSuggestionCreation?
        var mutationResult: CiderBookmarkDateSuggestionApprovalMutationResult!
        do {
            try database.withTransaction {
                let current = try validatedCandidate(for: request)
                if try priorReceiptExists(candidateRef: request.candidateRef) {
                    throw CiderBookmarkDateSuggestionApprovalError.alreadyReviewed
                }

                let legacy = try existingApproval(
                    bookmarkID: request.bookmarkID,
                    suggestion: current.suggestion
                )
                if let legacy, legacy.destination != request.destination {
                    throw CiderBookmarkDateSuggestionApprovalError.alreadyReviewed
                }

                let target: ApprovalTarget
                if let legacy {
                    target = legacy
                } else {
                    let targetID = Self.deterministicTargetID(fingerprint: fingerprint)
                    let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: request.bookmarkID)
                    switch request.destination {
                    case .dateCard:
                        let card = DateCard(
                            id: targetID,
                            title: current.bookmark.title,
                            details: details(for: current.suggestion),
                            startAt: current.suggestion.date,
                            allDay: !sourceSnippetHasExplicitTime(current.suggestion.sourceSnippet),
                            linkedEntities: [bookmarkRef],
                            actionURLString: current.bookmark.urlString
                        )
                        dateCreation = try dateCardStorage.beginCompensatableDateSuggestionCreation(
                            card,
                            database: database
                        )
                        target = .dateCard(card, created: true)
                    case .todo:
                        let todo = TodoCard(
                            id: targetID,
                            title: current.bookmark.title,
                            details: details(for: current.suggestion),
                            dueDate: current.suggestion.date,
                            linkedEntities: [bookmarkRef],
                            actionURLString: current.bookmark.urlString
                        )
                        todoCreation = try todoStorage.beginCompensatableDateSuggestionCreation(
                            todo,
                            database: database
                        )
                        target = .todo(todo, created: true)
                    }
                    try failureInjector?(.afterItemCreation)
                    try insertReciprocalBookmarkLink(bookmarkID: request.bookmarkID, target: target)
                    try failureInjector?(.afterReciprocalLink)
                    try recordCreateRoutingProvenance(target: target, actor: request.actor)
                }

                let targetRef = target.ownerRef
                let truthBoundary = "approved_bookmark_date_suggestion_created_item"
                _ = try MutationAuditService(database: database).recordRequired(
                    action: Self.canonicalCommand,
                    itemType: request.destination.entityType.rawValue,
                    itemID: target.id,
                    before: [
                        "candidateRef": request.candidateRef,
                        "reviewState": request.expectedReviewState,
                    ],
                    after: [
                        "reviewState": "accepted",
                        "targetOwnerRef": targetRef,
                        "destination": request.destination.rawValue,
                    ],
                    metadata: [
                        "actor": request.actor,
                        "bookmarkID": request.bookmarkID.uuidString,
                    ],
                    source: request.actor == "user" ? .ui : .agent
                )
                try failureInjector?(.afterRequiredAudit)
                try SecondBrainReviewLifecycleService(database: database).record(
                    SecondBrainReviewLifecycleEvent(
                        owner: SecondBrainOwnerRef(
                            ownerType: CiderReviewCandidateFamily.bookmarkDateSuggestion.rawValue,
                            ownerID: String(request.candidateRef.dropFirst(Self.candidatePrefix.count))
                        ),
                        candidateRef: request.candidateRef,
                        lifecycleState: "accepted",
                        eventKind: "accepted",
                        actor: request.actor,
                        source: Self.canonicalCommand,
                        toolName: Self.canonicalCommand,
                        reason: "Approved exact source-backed bookmark date suggestion to an explicit destination.",
                        metadata: [
                            "bookmark_ref": "bookmark:\(request.bookmarkID.uuidString)",
                            "target_owner_ref": targetRef,
                            "destination": request.destination.rawValue,
                        ]
                    )
                )
                try failureInjector?(.afterLifecycle)

                let selector = Self.expectedVersionSelector(
                    reviewState: request.expectedReviewState,
                    updatedAt: request.expectedUpdatedAt
                )
                let verificationCommands = Self.safeVerificationCommands(
                    request: request,
                    receiptID: receiptID,
                    targetOwnerRef: targetRef
                )
                let nextCommands = [
                    "cider-cli review list --kind bookmark_date_suggestion --json",
                    "cider-cli item context bookmark \(request.bookmarkID.uuidString) --max-history 10 --json",
                ]
                _ = try SecondBrainActionReceiptLedgerService(database: database).record(
                    SecondBrainActionReceiptRecord(
                        id: receiptID,
                        command: Self.canonicalCommand,
                        action: "approve",
                        actor: request.actor,
                        status: "succeeded",
                        owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: request.bookmarkID.uuidString),
                        sourceRefs: [
                            "bookmark:\(request.bookmarkID.uuidString)",
                            request.candidateRef,
                            targetRef,
                        ],
                        evidenceRefs: [request.candidateRef],
                        readOnly: false,
                        changed: true,
                        beforeJSON: DatabaseHelpers.encodeJSON([
                            "reviewState": request.expectedReviewState,
                            "candidateVersion": Self.preciseVersion(request.expectedUpdatedAt),
                        ]),
                        afterJSON: DatabaseHelpers.encodeJSON([
                            "requestFingerprint": fingerprint,
                            "evidenceFingerprint": Self.evidenceFingerprint(request.exactEvidence),
                            "reviewState": "accepted",
                            "truthBoundary": truthBoundary,
                            "destination": request.destination.rawValue,
                            "targetOwnerRef": targetRef,
                            "candidateVersion": Self.preciseVersion(request.expectedUpdatedAt),
                        ]),
                        safeVerificationCommands: verificationCommands,
                        safeNextCommands: nextCommands,
                        correlationID: "bookmark-date-review:\(request.candidateRef)",
                        receiptJSON: DatabaseHelpers.encodeJSON([
                            "id": receiptID,
                            "commandFamily": CiderReviewCandidateFamily.bookmarkDateSuggestion.rawValue,
                            "truthBoundary": truthBoundary,
                            "requestFingerprint": fingerprint,
                        ])
                    )
                )
                try failureInjector?(.afterReceipt)

                let approval = approvalResult(
                    bookmark: current.bookmark,
                    suggestion: current.suggestion,
                    target: target,
                    changed: true,
                    receiptID: receiptID,
                    selector: selector,
                    verificationCommands: verificationCommands,
                    nextCommands: nextCommands,
                    truthBoundary: truthBoundary
                )
                mutationResult = CiderBookmarkDateSuggestionApprovalMutationResult(
                    approval: approval,
                    receiptID: receiptID,
                    changed: true,
                    truthBoundary: truthBoundary
                )
            }
        } catch {
            do {
                if let dateCreation {
                    try dateCardStorage.compensateDateSuggestionCreation(dateCreation)
                }
                if let todoCreation {
                    try todoStorage.compensateDateSuggestionCreation(todoCreation)
                }
            } catch {
                throw CiderBookmarkDateSuggestionApprovalError.compensationFailed
            }
            if let creationError = error as? DateCardStorage.CompensatableCreationError,
               case .compensationFailed = creationError {
                throw CiderBookmarkDateSuggestionApprovalError.compensationFailed
            }
            if let creationError = error as? TodoCardStorage.CompensatableCreationError,
               case .compensationFailed = creationError {
                throw CiderBookmarkDateSuggestionApprovalError.compensationFailed
            }
            throw error
        }

        if let dateCreation { dateCardStorage.finalizeDateSuggestionCreation(dateCreation) }
        if let todoCreation { todoStorage.finalizeDateSuggestionCreation(todoCreation) }
        return mutationResult
    }

    /// Read-only reconciliation for surfaces that advertise active review work.
    /// A derived suggestion is no longer active only while its canonical approval
    /// receipt still points at the currently linked Date Card or Todo row.
    func hasCanonicalAcceptedBinding(candidateRef: String, bookmarkID: UUID) throws -> Bool {
        guard candidateRef.hasPrefix(Self.candidatePrefix),
              candidateRef.count > Self.candidatePrefix.count else {
            return false
        }
        let bookmarkRef = "bookmark:\(bookmarkID.uuidString)"
        let receipts = try SecondBrainActionReceiptLedgerService(database: database).list(
            filter: SecondBrainActionReceiptFilter(
                command: Self.canonicalCommand,
                status: "succeeded",
                sourceRef: candidateRef,
                limit: 100
            )
        )
        return try receipts.contains { receipt in
            guard receipt.action == "approve",
                  !receipt.readOnly,
                  receipt.changed,
                  receipt.owner == SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmarkID.uuidString),
                  receipt.sourceRefs.contains(candidateRef),
                  receipt.sourceRefs.contains(bookmarkRef),
                  let durable = DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON),
                  durable["reviewState"] == "accepted",
                  let targetOwnerRef = durable["targetOwnerRef"],
                  receipt.sourceRefs.contains(targetOwnerRef),
                  let destination = durable["destination"] else {
                return false
            }
            return try canonicalTargetBindingExists(
                targetOwnerRef: targetOwnerRef,
                bookmarkID: bookmarkID,
                destination: destination
            )
        }
    }

    nonisolated static func expectedVersionSelector(reviewState: String, updatedAt: Date) -> String {
        "\(reviewState)@\(preciseVersion(updatedAt))"
    }

    nonisolated static func parseExpectedVersionSelector(_ selector: String) -> (reviewState: String, updatedAt: Date)? {
        let parts = selector.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              parts[0] == pendingReviewState,
              let bits = UInt64(parts[1], radix: 16) else { return nil }
        return (parts[0], Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits)))
    }

    private enum ApprovalTarget {
        case dateCard(DateCard, created: Bool)
        case todo(TodoCard, created: Bool)

        var id: UUID {
            switch self {
            case .dateCard(let card, _): card.id
            case .todo(let todo, _): todo.id
            }
        }

        var destination: CiderBookmarkDateSuggestionDestination {
            switch self {
            case .dateCard: .dateCard
            case .todo: .todo
            }
        }

        var ownerRef: String {
            switch self {
            case .dateCard(let card, _): "dateCard:\(card.id.uuidString)"
            case .todo(let todo, _): "todo:\(todo.id.uuidString)"
            }
        }

        var created: Bool {
            switch self {
            case .dateCard(_, let created), .todo(_, let created): created
            }
        }
    }

    private func validatedCandidate(
        for request: CiderBookmarkDateSuggestionApprovalRequest
    ) throws -> (bookmark: Bookmark, suggestion: CiderBookmarkDateSuggestion) {
        guard request.candidateRef.hasPrefix(Self.candidatePrefix),
              request.candidateRef.count > Self.candidatePrefix.count,
              request.candidateRef == Self.candidatePrefix + request.exactEvidence.suggestionKey,
              request.exactEvidence.bookmarkID == request.bookmarkID else {
            throw CiderBookmarkDateSuggestionApprovalError.invalidCandidateIdentity
        }
        guard request.expectedReviewState == Self.pendingReviewState else {
            throw CiderBookmarkDateSuggestionApprovalError.staleExpectedVersion
        }
        guard let bookmark = bookmarkProvider().first(where: { $0.id == request.bookmarkID }) else {
            throw CiderBookmarkDateSuggestionApprovalError.bookmarkNotFound(request.bookmarkID)
        }
        let canonical = try canonicalBookmarkState(id: request.bookmarkID)
        guard Self.preciseVersion(canonical.updatedAt) == Self.preciseVersion(request.expectedUpdatedAt),
              Self.preciseVersion(bookmark.updatedAt) == Self.preciseVersion(request.expectedUpdatedAt),
              bookmark.title == canonical.title,
              bookmark.urlString == canonical.url,
              bookmark.notes == canonical.notes,
              bookmark.aiSummary == canonical.aiSummary else {
            throw CiderBookmarkDateSuggestionApprovalError.staleExpectedVersion
        }
        let matches = dateSuggestionProvider(bookmark).filter {
            Self.candidatePrefix + $0.suggestionKey == request.candidateRef
        }
        guard !matches.isEmpty else {
            throw CiderBookmarkDateSuggestionApprovalError.candidateUnavailable
        }
        guard matches.count == 1 else {
            throw CiderBookmarkDateSuggestionApprovalError.ambiguousCandidate
        }
        guard matches[0] == request.exactEvidence else {
            throw CiderBookmarkDateSuggestionApprovalError.missingExactEvidence
        }
        return (bookmark, matches[0])
    }

    private func canonicalBookmarkState(
        id: UUID
    ) throws -> (title: String, updatedAt: Date, url: String, notes: String, aiSummary: String?) {
        let statement = try database.prepare("""
            SELECT i.title, i.updated_at, b.url, b.notes, b.ai_summary
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.id = ? AND i.type = 'bookmark'
            LIMIT 1;
            """)
        statement.bind(id.uuidString, at: 1)
        guard try statement.step(),
              let updatedAtValue = statement.optionalDouble(at: 1) else {
            throw CiderBookmarkDateSuggestionApprovalError.bookmarkNotFound(id)
        }
        return (
            statement.string(at: 0),
            DatabaseHelpers.decodeDate(updatedAtValue),
            statement.string(at: 2),
            statement.string(at: 3),
            statement.optionalString(at: 4)
        )
    }

    private func existingApproval(
        bookmarkID: UUID,
        suggestion: CiderBookmarkDateSuggestion
    ) throws -> ApprovalTarget? {
        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmarkID)
        let dateMatches = dateCardProvider().filter { card in
            card.linkedEntities.contains(bookmarkRef)
                && calendar.isDate(card.startAt, inSameDayAs: suggestion.date)
                && matchesSuggestionDetails(card.details, suggestion: suggestion)
        }
        let todoMatches = todoProvider().filter { todo in
            todo.linkedEntities.contains(bookmarkRef)
                && todo.dueDate.map { calendar.isDate($0, inSameDayAs: suggestion.date) } == true
                && matchesSuggestionDetails(todo.details, suggestion: suggestion)
        }
        guard dateMatches.count + todoMatches.count <= 1 else {
            throw CiderBookmarkDateSuggestionApprovalError.ambiguousCandidate
        }
        if let card = dateMatches.first { return .dateCard(card, created: false) }
        if let todo = todoMatches.first { return .todo(todo, created: false) }
        return nil
    }

    private func insertReciprocalBookmarkLink(bookmarkID: UUID, target: ApprovalTarget) throws {
        let statement = try database.prepare("""
            INSERT OR IGNORE INTO item_links (source_id, target_id, link_type, created_at)
            SELECT ?, ?, 'linked', ?
            WHERE EXISTS (SELECT 1 FROM items WHERE id = ?)
              AND EXISTS (SELECT 1 FROM items WHERE id = ?);
            """)
        statement.bind(bookmarkID.uuidString, at: 1)
            .bind(target.id.uuidString, at: 2)
            .bind(DatabaseHelpers.encode(Date()), at: 3)
            .bind(bookmarkID.uuidString, at: 4)
            .bind(target.id.uuidString, at: 5)
        try statement.step()
    }

    private func recordCreateRoutingProvenance(target: ApprovalTarget, actor: String) throws {
        let itemLabel = target.destination == .todo ? "todo" : "date card"
        _ = try CiderRoutingDecisionService(database: database).recordCreateProvenance(
            itemID: target.id,
            source: "bookmark.date_suggestion.\(target.destination.rawValue).create",
            actor: actor,
            reviewReason: "Cider created a \(itemLabel) from an approved bookmark date suggestion and kept it in Inbox for review.",
            acceptedReason: "Cider created a \(itemLabel) from an approved bookmark date suggestion."
        )
    }

    private func replayedMutation(
        request: CiderBookmarkDateSuggestionApprovalRequest,
        bookmark: Bookmark,
        fingerprint: String,
        receiptID: String
    ) throws -> CiderBookmarkDateSuggestionApprovalMutationResult? {
        guard let receipt = try SecondBrainActionReceiptLedgerService(database: database).inspect(id: receiptID),
              receipt.command == Self.canonicalCommand,
              receipt.action == "approve",
              receipt.actor == request.actor,
              receipt.status == "succeeded",
              !receipt.readOnly,
              receipt.changed,
              receipt.sourceRefs.contains(request.candidateRef),
              let durable = DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON),
              durable["requestFingerprint"] == fingerprint,
              durable["evidenceFingerprint"] == Self.evidenceFingerprint(request.exactEvidence),
              durable["candidateVersion"] == Self.preciseVersion(request.expectedUpdatedAt),
              durable["destination"] == request.destination.rawValue,
              durable["reviewState"] == "accepted",
              let targetRef = durable["targetOwnerRef"],
              let target = targetFromOwnerRef(targetRef),
              target.destination == request.destination else {
            return nil
        }
        let selector = Self.expectedVersionSelector(
            reviewState: request.expectedReviewState,
            updatedAt: request.expectedUpdatedAt
        )
        let verificationCommands = Self.safeVerificationCommands(
            request: request,
            receiptID: receiptID,
            targetOwnerRef: targetRef
        )
        let nextCommands = receipt.safeNextCommands
        let truthBoundary = durable["truthBoundary"] ?? "approved_bookmark_date_suggestion_created_item"
        let approval = approvalResult(
            bookmark: bookmark,
            suggestion: request.exactEvidence,
            target: target,
            changed: false,
            receiptID: receiptID,
            selector: selector,
            verificationCommands: verificationCommands,
            nextCommands: nextCommands,
            truthBoundary: truthBoundary
        )
        return CiderBookmarkDateSuggestionApprovalMutationResult(
            approval: approval,
            receiptID: receiptID,
            changed: false,
            truthBoundary: truthBoundary
        )
    }

    private func priorReceiptExists(candidateRef: String) throws -> Bool {
        try !SecondBrainActionReceiptLedgerService(database: database).list(
            filter: SecondBrainActionReceiptFilter(
                command: Self.canonicalCommand,
                sourceRef: candidateRef,
                limit: 2
            )
        ).isEmpty
    }

    private func targetFromOwnerRef(_ ownerRef: String) -> ApprovalTarget? {
        let parts = ownerRef.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "dateCard":
            return dateCardProvider().first(where: { $0.id == id }).map { .dateCard($0, created: false) }
        case "todo":
            return todoProvider().first(where: { $0.id == id }).map { .todo($0, created: false) }
        default:
            return nil
        }
    }

    private func canonicalTargetBindingExists(
        targetOwnerRef: String,
        bookmarkID: UUID,
        destination: String
    ) throws -> Bool {
        let parts = targetOwnerRef.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let targetID = UUID(uuidString: parts[1]) else {
            return false
        }
        let expectedItemType: String
        switch (parts[0], destination) {
        case ("dateCard", CiderBookmarkDateSuggestionDestination.dateCard.rawValue):
            expectedItemType = "event"
        case ("todo", CiderBookmarkDateSuggestionDestination.todo.rawValue):
            expectedItemType = "todo"
        default:
            return false
        }
        let statement = try database.prepare("""
            SELECT 1
            FROM items target
            WHERE target.id = ?
              AND target.type = ?
              AND EXISTS (
                  SELECT 1
                  FROM item_links link
                  WHERE (link.source_id = ? AND link.target_id = ?)
                     OR (link.source_id = ? AND link.target_id = ?)
              )
            LIMIT 1;
            """)
        statement.bind(targetID.uuidString, at: 1)
            .bind(expectedItemType, at: 2)
            .bind(bookmarkID.uuidString, at: 3)
            .bind(targetID.uuidString, at: 4)
            .bind(targetID.uuidString, at: 5)
            .bind(bookmarkID.uuidString, at: 6)
        return try statement.step()
    }

    private func approvalResult(
        bookmark: Bookmark,
        suggestion: CiderBookmarkDateSuggestion,
        target: ApprovalTarget,
        changed: Bool,
        receiptID: String,
        selector: String,
        verificationCommands: [String],
        nextCommands: [String],
        truthBoundary: String
    ) -> CiderBookmarkDateSuggestionApprovalResult {
        let action: CiderBookmarkDateSuggestionApprovalAction
        let dateCard: DateCard?
        let todo: TodoCard?
        switch target {
        case .dateCard(let card, let created):
            action = created ? .createdDateCard : .reusedExistingDateCard
            dateCard = card
            todo = nil
        case .todo(let card, let created):
            action = created ? .createdTodo : .reusedExistingTodo
            dateCard = nil
            todo = card
        }
        return CiderBookmarkDateSuggestionApprovalResult(
            command: Self.canonicalCommand,
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            suggestion: suggestion,
            action: action,
            dateCard: dateCard,
            todo: todo,
            changed: changed,
            actionReceiptID: receiptID,
            truthBoundary: truthBoundary,
            expectedVersionSelector: selector,
            safeVerificationCommands: verificationCommands,
            safeNextCommands: nextCommands
        )
    }

    private func details(for suggestion: CiderBookmarkDateSuggestion) -> String {
        [
            "Candidate ref: \(Self.candidatePrefix)\(suggestion.suggestionKey)",
            "Date suggestion kind: \(suggestion.kind)",
            "Confidence: \(String(format: "%.2f", suggestion.confidence))",
            "Source field: \(suggestion.sourceField)",
            "Evidence: \(suggestion.sourceSnippet)",
            "Source bookmark: \(suggestion.sourceURL)",
        ].joined(separator: "\n")
    }

    private func matchesSuggestionDetails(
        _ details: String,
        suggestion: CiderBookmarkDateSuggestion
    ) -> Bool {
        if details.contains("Candidate ref: \(Self.candidatePrefix)\(suggestion.suggestionKey)") {
            return true
        }
        return details.contains("Date suggestion kind: \(suggestion.kind)")
            && details.contains("Source field: \(suggestion.sourceField)")
            && details.contains("Evidence: \(suggestion.sourceSnippet)")
            && details.contains("Source bookmark: \(suggestion.sourceURL)")
    }

    private func sourceSnippetHasExplicitTime(_ snippet: String) -> Bool {
        let pattern = #"(?i)\b(\d{1,2}:\d{2}\s*(am|pm)?|\d{1,2}\s*(am|pm))\b"#
        return snippet.range(of: pattern, options: .regularExpression) != nil
    }

    private static func safeVerificationCommands(
        request: CiderBookmarkDateSuggestionApprovalRequest,
        receiptID: String,
        targetOwnerRef: String
    ) -> [String] {
        let target = targetOwnerRef.split(separator: ":", maxSplits: 1).map(String.init)
        let targetCommand = target.count == 2
            ? "cider-cli item context \(target[0]) \(target[1]) --max-history 10 --json"
            : "cider-cli item context bookmark \(request.bookmarkID.uuidString) --max-history 10 --json"
        return [
            "cider-cli item action-ledger inspect \(receiptID) --json",
            targetCommand,
            "cider-cli item context bookmark \(request.bookmarkID.uuidString) --max-history 10 --json",
        ]
    }

    private static func requestFingerprint(_ request: CiderBookmarkDateSuggestionApprovalRequest) -> String {
        let fields = [
            "bookmark-date-review-request-v1",
            request.candidateRef,
            request.bookmarkID.uuidString.lowercased(),
            request.expectedReviewState,
            preciseVersion(request.expectedUpdatedAt),
            "approve",
            request.destination.rawValue,
            request.actor,
            evidenceFingerprint(request.exactEvidence),
        ]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return sha256(canonical)
    }

    private static func evidenceFingerprint(_ suggestion: CiderBookmarkDateSuggestion) -> String {
        let fields = [
            suggestion.bookmarkID.uuidString.lowercased(),
            suggestion.bookmarkTitle,
            suggestion.sourceURL,
            suggestion.kind,
            String(format: "%016llx", suggestion.confidence.bitPattern),
            preciseVersion(suggestion.date),
            suggestion.sourceField,
            suggestion.sourceSnippet,
            suggestion.nextSafeAction,
        ]
        return sha256(fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|"))
    }

    private static func actionReceiptID(fingerprint: String) -> String {
        "bookmark-date-review:approve:\(fingerprint)"
    }

    private static func deterministicTargetID(fingerprint: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("bookmark-date-target:\(fingerprint)".utf8)))
        var uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        uuid.6 = (uuid.6 & 0x0F) | 0x50
        uuid.8 = (uuid.8 & 0x3F) | 0x80
        return UUID(uuid: uuid)
    }

    nonisolated private static func preciseVersion(_ date: Date) -> String {
        String(format: "%016llx", date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit
import Foundation

enum CiderBookmarkEnrichmentQueueScheduleDisposition: String, Equatable, Sendable {
    case scheduled
    case adopted
    case reused
}

enum CiderBookmarkEnrichmentQueueCancellationDisposition: String, Equatable, Sendable {
    case canceledScheduledTask
    case detachedAdoptedTask
    case identityNotFound

    func compensates(_ scheduleDisposition: CiderBookmarkEnrichmentQueueScheduleDisposition) -> Bool {
        switch (scheduleDisposition, self) {
        case (.scheduled, .canceledScheduledTask), (.adopted, .detachedAdoptedTask):
            return true
        case (.reused, _), (.scheduled, _), (.adopted, _):
            return false
        }
    }
}

enum CiderBookmarkEnrichmentSchedulingCheckpoint: CaseIterable, Equatable, Sendable {
    case afterReceipt
    case afterAudit
    case afterScheduler
}

struct CiderBookmarkEnrichmentBatchContext: Equatable, Sendable {
    var batchID: UUID
    var candidateCount: Int
    var excludedCount: Int
}

struct CiderBookmarkEnrichmentSchedulingRequest: Equatable, Sendable {
    var candidateRef: String
    var bookmarkID: UUID
    var expectedReviewState: String
    var expectedUpdatedAt: Date
    var actor: String
    var batchContext: CiderBookmarkEnrichmentBatchContext?
}

struct CiderBookmarkEnrichmentSchedulingMutationResult: Equatable, Sendable {
    var changed: Bool
    var receiptID: String
    var schedulingIdentity: String
    var reviewState: String
    var queueDisposition: CiderBookmarkEnrichmentQueueScheduleDisposition
    var truthBoundary: String = "durable_enrichment_schedule_not_enrichment_completion"
}

enum CiderBookmarkEnrichmentSchedulingError: Error, LocalizedError {
    case databaseUnavailable
    case invalidCandidateIdentity
    case candidateUnavailable
    case staleCandidate
    case unsupportedItemType
    case missingSource
    case unauthorizedActor
    case schedulingConflict
    case schedulerFailure
    case compensationUnavailable
    case compensationFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "The review database is unavailable. Nothing was scheduled."
        case .invalidCandidateIdentity:
            return "The enrichment candidate does not match the exact bookmark item. Refresh the review queue and try again."
        case .candidateUnavailable:
            return "The enrichment review item is no longer active. Refresh the review queue."
        case .staleCandidate:
            return "The bookmark changed after this enrichment row was loaded. Refresh the review queue and try again."
        case .unsupportedItemType:
            return "Review enrichment scheduling is supported only for bookmarks."
        case .missingSource:
            return "The bookmark no longer has an eligible source URL. Repair the bookmark source before retrying enrichment."
        case .unauthorizedActor:
            return "The enrichment scheduling actor is not authorized."
        case .schedulingConflict:
            return "This exact enrichment candidate already has scheduled work under a different request binding. Refresh before retrying."
        case .schedulerFailure:
            return "Cider could not enqueue bookmark enrichment. The review row was kept and nothing was recorded."
        case .compensationUnavailable:
            return "Bookmark enrichment scheduling requires an explicit compensation boundary. Nothing was scheduled or recorded."
        case .compensationFailed:
            return "Bookmark enrichment scheduling failed and exact queue cleanup could not be established. Durable receipt and audit writes were rolled back, but queue rollback is not claimed."
        }
    }
}

@MainActor
final class CiderBookmarkEnrichmentSchedulingService {
    typealias Scheduler = @MainActor (
        UUID,
        String
    ) throws -> CiderBookmarkEnrichmentQueueScheduleDisposition
    typealias ScheduleCanceller = @MainActor (
        UUID,
        String
    ) throws -> CiderBookmarkEnrichmentQueueCancellationDisposition

    private struct CandidateSnapshot {
        var itemType: String
        var updatedAt: Date
        var sourceURL: String
        var reviewState: String
    }

    private let database: CiderDatabase
    private let scheduler: Scheduler
    private let scheduleCanceller: ScheduleCanceller?
    private let failureInjector: (@MainActor (CiderBookmarkEnrichmentSchedulingCheckpoint) throws -> Void)?

    init(
        database: CiderDatabase,
        scheduler: @escaping Scheduler,
        scheduleCanceller: ScheduleCanceller?,
        failureInjector: (@MainActor (CiderBookmarkEnrichmentSchedulingCheckpoint) throws -> Void)? = nil
    ) {
        self.database = database
        self.scheduler = scheduler
        self.scheduleCanceller = scheduleCanceller
        self.failureInjector = failureInjector
    }

    convenience init(
        database: CiderDatabase,
        bookmarkService: VaultBookmarkService,
        failureInjector: (@MainActor (CiderBookmarkEnrichmentSchedulingCheckpoint) throws -> Void)? = nil
    ) {
        self.init(
            database: database,
            scheduler: { bookmarkID, schedulingIdentity in
                try bookmarkService.scheduleReviewEnrichment(
                    for: bookmarkID,
                    schedulingIdentity: schedulingIdentity
                )
            },
            scheduleCanceller: { bookmarkID, schedulingIdentity in
                bookmarkService.cancelReviewEnrichment(
                    for: bookmarkID,
                    schedulingIdentity: schedulingIdentity
                )
            },
            failureInjector: failureInjector
        )
    }

    func perform(
        _ request: CiderBookmarkEnrichmentSchedulingRequest
    ) throws -> CiderBookmarkEnrichmentSchedulingMutationResult {
        guard database.isOpen else {
            throw CiderBookmarkEnrichmentSchedulingError.databaseUnavailable
        }
        let actor = request.actor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["user", "agent", "cli"].contains(actor) else {
            throw CiderBookmarkEnrichmentSchedulingError.unauthorizedActor
        }
        guard request.candidateRef == Self.candidateRef(for: request.bookmarkID) else {
            throw CiderBookmarkEnrichmentSchedulingError.invalidCandidateIdentity
        }
        guard scheduleCanceller != nil else {
            throw CiderBookmarkEnrichmentSchedulingError.compensationUnavailable
        }

        let candidate = try loadCandidate(bookmarkID: request.bookmarkID)
        guard candidate.itemType == "bookmark" else {
            throw CiderBookmarkEnrichmentSchedulingError.unsupportedItemType
        }
        guard Self.isEligibleSourceURL(candidate.sourceURL) else {
            throw CiderBookmarkEnrichmentSchedulingError.missingSource
        }
        guard candidate.reviewState != "complete" else {
            throw CiderBookmarkEnrichmentSchedulingError.candidateUnavailable
        }
        guard candidate.reviewState == request.expectedReviewState,
              Self.sameVersion(candidate.updatedAt, request.expectedUpdatedAt) else {
            throw CiderBookmarkEnrichmentSchedulingError.staleCandidate
        }

        let fingerprint = Self.requestFingerprint(request, normalizedActor: actor)
        let receiptID = "bookmark-enrichment-schedule:enrich:\(fingerprint)"
        if let existing = try SecondBrainActionReceiptLedgerService(database: database).inspect(id: receiptID) {
            guard Self.receiptMatches(
                existing,
                request: request,
                normalizedActor: actor,
                fingerprint: fingerprint
            ) else {
                throw CiderBookmarkEnrichmentSchedulingError.schedulingConflict
            }
            let queueDisposition = try invokeScheduler(
                bookmarkID: request.bookmarkID,
                schedulingIdentity: receiptID
            )
            return CiderBookmarkEnrichmentSchedulingMutationResult(
                changed: false,
                receiptID: receiptID,
                schedulingIdentity: receiptID,
                reviewState: candidate.reviewState,
                queueDisposition: queueDisposition
            )
        }

        if try hasConflictingReceipt(for: request, excluding: receiptID) {
            throw CiderBookmarkEnrichmentSchedulingError.schedulingConflict
        }

        var queueDisposition: CiderBookmarkEnrichmentQueueScheduleDisposition?
        do {
            return try database.withTransaction {
                let safeVerificationCommands = Self.safeVerificationCommands(
                    bookmarkID: request.bookmarkID,
                    receiptID: receiptID
                )
                let receiptMetadata: [String: Any] = [
                    "commandFamily": "review",
                    "candidateRef": request.candidateRef,
                    "expectedReviewState": request.expectedReviewState,
                    "expectedVersionBits": Self.versionBits(request.expectedUpdatedAt),
                    "requestFingerprint": fingerprint,
                    "schedulingIdentity": receiptID,
                    "truthBoundary": "durable_enrichment_schedule_not_enrichment_completion",
                    "outcomeBoundary": "receipt_proves_scheduling_only",
                ]
                let receipt = SecondBrainActionReceiptRecord(
                    id: receiptID,
                    command: "review.enrich",
                    action: "enrich",
                    actor: actor,
                    status: "scheduled",
                    owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: request.bookmarkID.uuidString),
                    sourceRefs: ["bookmark:\(request.bookmarkID.uuidString)"],
                    evidenceRefs: ["enrichment_candidate:\(fingerprint)"],
                    readOnly: false,
                    changed: true,
                    beforeJSON: Self.jsonString([
                        "reviewState": request.expectedReviewState,
                        "expectedVersionBits": Self.versionBits(request.expectedUpdatedAt),
                    ]),
                    afterJSON: Self.jsonString([
                        "reviewState": request.expectedReviewState,
                        "schedulingStatus": "scheduled",
                    ]),
                    safeVerificationCommands: safeVerificationCommands,
                    safeNextCommands: safeVerificationCommands,
                    correlationID: request.batchContext?.batchID.uuidString,
                    receiptJSON: Self.jsonString(receiptMetadata)
                )
                _ = try SecondBrainActionReceiptLedgerService(database: database).record(receipt)
                try failureInjector?(.afterReceipt)

                var auditMetadata: [String: String] = [
                    "candidateRef": request.candidateRef,
                    "receiptID": receiptID,
                    "expectedVersionBits": Self.versionBits(request.expectedUpdatedAt),
                ]
                let auditAction: String
                if let batch = request.batchContext {
                    auditAction = "review.enrich.batch.schedule"
                    auditMetadata["batchID"] = batch.batchID.uuidString
                    auditMetadata["candidateCount"] = String(batch.candidateCount)
                    auditMetadata["excludedCount"] = String(batch.excludedCount)
                } else {
                    auditAction = "review.enrich.schedule"
                }
                _ = try MutationAuditService(database: database).recordRequired(
                    action: auditAction,
                    itemType: "bookmark",
                    itemID: request.bookmarkID,
                    after: [
                        "reviewAction": "enrich",
                        "status": "scheduled",
                    ],
                    metadata: auditMetadata,
                    source: Self.auditSource(for: actor)
                )
                try failureInjector?(.afterAudit)

                let disposition = try invokeScheduler(
                    bookmarkID: request.bookmarkID,
                    schedulingIdentity: receiptID
                )
                queueDisposition = disposition
                try failureInjector?(.afterScheduler)

                return CiderBookmarkEnrichmentSchedulingMutationResult(
                    changed: true,
                    receiptID: receiptID,
                    schedulingIdentity: receiptID,
                    reviewState: candidate.reviewState,
                    queueDisposition: disposition
                )
            }
        } catch {
            if let queueDisposition, queueDisposition != .reused {
                do {
                    guard let cancellationDisposition = try scheduleCanceller?(
                        request.bookmarkID,
                        receiptID
                    ), cancellationDisposition.compensates(queueDisposition) else {
                        throw CiderBookmarkEnrichmentSchedulingError.compensationFailed
                    }
                } catch {
                    throw CiderBookmarkEnrichmentSchedulingError.compensationFailed
                }
            }
            throw error
        }
    }

    static func candidateRef(for bookmarkID: UUID) -> String {
        "enrichment:\(bookmarkID.uuidString)"
    }

    private func invokeScheduler(
        bookmarkID: UUID,
        schedulingIdentity: String
    ) throws -> CiderBookmarkEnrichmentQueueScheduleDisposition {
        do {
            return try scheduler(bookmarkID, schedulingIdentity)
        } catch {
            do {
                guard let cancellationDisposition = try scheduleCanceller?(
                    bookmarkID,
                    schedulingIdentity
                ), cancellationDisposition != .identityNotFound else {
                    throw CiderBookmarkEnrichmentSchedulingError.compensationFailed
                }
            } catch {
                throw CiderBookmarkEnrichmentSchedulingError.compensationFailed
            }
            throw error
        }
    }

    static func expectedVersionSelector(reviewState: String, updatedAt: Date) -> String {
        "\(reviewState)@\(versionBits(updatedAt))"
    }

    static func decodeExpectedVersionSelector(_ selector: String) -> CiderReviewExpectedVersion? {
        guard let separator = selector.lastIndex(of: "@"),
              separator != selector.startIndex,
              selector.index(after: separator) != selector.endIndex,
              let bits = UInt64(selector[selector.index(after: separator)...], radix: 16) else {
            return nil
        }
        return CiderReviewExpectedVersion(
            reviewState: String(selector[..<separator]),
            updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(bitPattern: bits))
        )
    }

    static func batchID(
        candidateBindings: [String],
        actor: String
    ) -> UUID {
        let fields = ["actor=\(actor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"]
            + candidateBindings.sorted().map { "candidate=\($0)" }
        let framed = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(framed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func loadCandidate(bookmarkID: UUID) throws -> CandidateSnapshot {
        let statement = try database.prepare("""
            SELECT i.type, i.updated_at, b.url, b.enrichment_status, b.last_enriched_at
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.id = ?
            LIMIT 1;
            """)
        statement.bind(bookmarkID.uuidString, at: 1)
        guard try statement.step() else {
            throw CiderBookmarkEnrichmentSchedulingError.candidateUnavailable
        }
        let status = statement.optionalString(at: 3)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let lastEnrichedAt = statement.optionalDouble(at: 4)
        let reviewState: String
        if status == "complete", lastEnrichedAt != nil {
            reviewState = "complete"
        } else if status == "failed" || status == "error" {
            reviewState = "needs_review"
        } else {
            reviewState = "pending"
        }
        return CandidateSnapshot(
            itemType: statement.string(at: 0),
            updatedAt: DatabaseHelpers.decodeDate(statement.double(at: 1)),
            sourceURL: statement.string(at: 2),
            reviewState: reviewState
        )
    }

    private func hasConflictingReceipt(
        for request: CiderBookmarkEnrichmentSchedulingRequest,
        excluding receiptID: String
    ) throws -> Bool {
        let receipts = try SecondBrainActionReceiptLedgerService(database: database).list(
            filter: .init(
                owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: request.bookmarkID.uuidString),
                command: "review.enrich",
                limit: 100
            )
        )
        return receipts.contains { receipt in
            guard receipt.id != receiptID,
                  let metadata = Self.jsonObject(receipt.receiptJSON) else { return false }
            return metadata["candidateRef"] as? String == request.candidateRef
                && metadata["expectedReviewState"] as? String == request.expectedReviewState
                && metadata["expectedVersionBits"] as? String == Self.versionBits(request.expectedUpdatedAt)
        }
    }

    private static func requestFingerprint(
        _ request: CiderBookmarkEnrichmentSchedulingRequest,
        normalizedActor: String
    ) -> String {
        let fields = [
            "family=enrichment",
            "candidate=\(request.candidateRef)",
            "bookmark=\(request.bookmarkID.uuidString)",
            "state=\(request.expectedReviewState)",
            "version=\(versionBits(request.expectedUpdatedAt))",
            "action=enrich",
            "actor=\(normalizedActor)",
            "eligibility=source_backed_bookmark",
        ]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func receiptMatches(
        _ receipt: SecondBrainActionReceiptRecord,
        request: CiderBookmarkEnrichmentSchedulingRequest,
        normalizedActor: String,
        fingerprint: String
    ) -> Bool {
        guard receipt.command == "review.enrich",
              receipt.action == "enrich",
              receipt.actor == normalizedActor,
              receipt.status == "scheduled",
              receipt.owner == SecondBrainOwnerRef(ownerType: "bookmark", ownerID: request.bookmarkID.uuidString),
              let metadata = jsonObject(receipt.receiptJSON) else {
            return false
        }
        return metadata["candidateRef"] as? String == request.candidateRef
            && metadata["expectedReviewState"] as? String == request.expectedReviewState
            && metadata["expectedVersionBits"] as? String == versionBits(request.expectedUpdatedAt)
            && metadata["requestFingerprint"] as? String == fingerprint
            && metadata["schedulingIdentity"] as? String == receipt.id
    }

    static func isEligibleSourceURL(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            return false
        }
        return true
    }

    private static func sameVersion(_ lhs: Date, _ rhs: Date) -> Bool {
        lhs.timeIntervalSinceReferenceDate.bitPattern == rhs.timeIntervalSinceReferenceDate.bitPattern
    }

    private static func versionBits(_ date: Date) -> String {
        String(format: "%016llx", date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private static func auditSource(for actor: String) -> MutationAuditSource {
        switch actor {
        case "agent": .agent
        case "cli": .cli
        default: .ui
        }
    }

    private static func safeVerificationCommands(bookmarkID: UUID, receiptID: String) -> [String] {
        [
            "cider-cli item action-ledger inspect \(receiptID) --json",
            "cider-cli item get bookmark \(bookmarkID.uuidString) --json",
            "cider-cli review list --kind enrichment --json",
        ]
    }

    private static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func jsonObject(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

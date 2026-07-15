import CryptoKit
import Foundation

struct SecondBrainEventDateFactReviewMutationResult {
    var view: SecondBrainEventDateFactCandidateView
    var receiptID: String
    var changed: Bool
}

struct SecondBrainEventDateFactCandidateView: Equatable {
    var id: String
    var candidateRef: String
    var targetRef: String
    var factKind: String
    var eventLabel: String
    var proposedDate: String
    var confidence: String
    var reason: String
    var reviewState: String
    var truthBoundary: String
    var sourceItemRefs: [String]
    var structuredFactRef: String?
    var candidate: SecondBrainFactValidityCandidateView
    var provenance: [String: Any]
    var actionReceipt: [String: Any]
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]

    static func == (lhs: SecondBrainEventDateFactCandidateView, rhs: SecondBrainEventDateFactCandidateView) -> Bool {
        lhs.id == rhs.id
            && lhs.candidateRef == rhs.candidateRef
            && lhs.targetRef == rhs.targetRef
            && lhs.factKind == rhs.factKind
            && lhs.eventLabel == rhs.eventLabel
            && lhs.proposedDate == rhs.proposedDate
            && lhs.confidence == rhs.confidence
            && lhs.reason == rhs.reason
            && lhs.reviewState == rhs.reviewState
            && lhs.truthBoundary == rhs.truthBoundary
            && lhs.sourceItemRefs == rhs.sourceItemRefs
            && lhs.structuredFactRef == rhs.structuredFactRef
            && lhs.candidate == rhs.candidate
            && NSDictionary(dictionary: lhs.provenance).isEqual(to: rhs.provenance)
            && NSDictionary(dictionary: lhs.actionReceipt).isEqual(to: rhs.actionReceipt)
            && lhs.safeVerificationCommands == rhs.safeVerificationCommands
            && lhs.safeNextCommands == rhs.safeNextCommands
    }
}

@MainActor
final class SecondBrainEventDateFactReviewService {
    enum TargetKind: String, Equatable {
        case contactBirthday
        case dateCard

        var factKind: String {
            switch self {
            case .contactBirthday: return "contact_birthday"
            case .dateCard: return "event_date"
            }
        }

        var acceptedTruthBoundary: String {
            switch self {
            case .contactBirthday: return "accepted_contact_birthday"
            case .dateCard: return "accepted_event_date"
            }
        }

        var targetRefPrefix: String {
            switch self {
            case .contactBirthday: return "contact_birthday_name"
            case .dateCard: return "date_card_title"
            }
        }
    }

    enum EventDateFactReviewError: Error, LocalizedError, Equatable {
        case noBoundedEventDateFactFound
        case ambiguousEventDateFact([String])
        case candidateNotFound(String)
        case unsupportedCandidate(String)
        case invalidProposedDate(String)
        case staleCandidate(String)
        case alreadyReviewed(String, String)
        case missingSourceEvidence(String)
        case unsupportedReviewAction(String)

        var errorDescription: String? {
            switch self {
            case .noBoundedEventDateFactFound:
                return "No bounded event/date fact was found in the source observation."
            case .ambiguousEventDateFact(let labels):
                return "Ambiguous event/date observation; found multiple birthday facts: \(labels.joined(separator: ", "))."
            case .candidateNotFound(let id):
                return "Event/date fact candidate not found: \(id)."
            case .unsupportedCandidate(let id):
                return "Candidate is not a review-backed event/date fact candidate: \(id)."
            case .invalidProposedDate(let value):
                return "Invalid proposed event/date fact date: \(value)."
            case .staleCandidate:
                return "This event/date fact changed after it loaded. Refresh the review list before acting."
            case .alreadyReviewed(_, let state):
                return "This event/date fact is already \(state). Refresh to see its current state."
            case .missingSourceEvidence:
                return "Cider could not verify the exact event/date source evidence, so the action was blocked."
            case .unsupportedReviewAction:
                return "This action is not supported for event/date fact review. Nothing was changed."
            }
        }
    }

    private let database: CiderDatabase
    private let factValidity: SecondBrainFactValidityService
    private let store: SecondBrainStore

    init(database: CiderDatabase = .shared) {
        self.database = database
        self.factValidity = SecondBrainFactValidityService(database: database)
        self.store = SecondBrainStore(database: database)
    }

    func proposeFromSourceObservation(
        sourceOwner: SecondBrainOwnerRef,
        sourceQuote: String,
        sourceDate: Date,
        targetKind: TargetKind,
        actor: String,
        reason: String,
        confidence: String = "source_backed_observation",
        targetItemID: UUID? = nil
    ) throws -> SecondBrainEventDateFactCandidateView {
        let personName = try detectBirthdayFact(in: sourceQuote)
        let proposedDate = Self.localDayFormatter.string(from: sourceDate)
        let label = "\(personName) birthday"
        let proposedTargetRef = targetItemID.map { targetRef(for: targetKind, itemID: $0) }
            ?? "\(targetKind.targetRefPrefix):\(stableSlug(label))"
        let metadata: [String: String] = [
            "candidate_family": "event_date_fact",
            "fact_kind": targetKind.factKind,
            "target_kind": targetKind.rawValue,
            "person_name": personName,
            "event_label": label,
            "proposed_date": proposedDate,
            "confidence": confidence,
            "source_item_ref": sourceOwner.canonicalRef,
            "structured_fact_ref": "",
        ].merging(targetItemID.map { ["target_item_id": $0.uuidString] } ?? [:]) { current, _ in current }

        let candidate = try factValidity.propose(
            targetRef: proposedTargetRef,
            proposedState: "structured_event_date_fact",
            sourceOwner: sourceOwner,
            sourceQuote: sourceQuote,
            actor: actor,
            reason: reason,
            validAt: sourceDate,
            source: "event_date_fact.propose",
            metadata: metadata
        )
        return try view(
            candidate,
            command: "item.event-date-facts.propose",
            action: "propose",
            actor: actor,
            changed: true,
            beforeState: nil
        )
    }

    func inspect(candidateID rawID: String) throws -> SecondBrainEventDateFactCandidateView {
        let id = normalizedCandidateID(rawID)
        guard let candidate = try factValidity.candidate(id: id) else {
            throw EventDateFactReviewError.candidateNotFound(id)
        }
        return try view(
            candidate,
            command: "item.event-date-facts.inspect",
            action: "inspect",
            actor: "cider-cli",
            changed: false,
            beforeState: candidate.reviewState,
            readOnly: true
        )
    }

    func candidates(reviewStates: [String] = ["suggested", "needs_review", "deferred"]) throws -> [SecondBrainEventDateFactCandidateView] {
        try factValidity.candidates(reviewStates: reviewStates)
            .filter { $0.candidate.metadata["candidate_family"] == "event_date_fact" }
            .map {
                try view(
                    $0,
                    command: "item.event-date-facts.list",
                    action: "list",
                    actor: "cider-cli",
                    changed: false,
                    beforeState: $0.reviewState,
                    readOnly: true
                )
            }
    }

    func accept(candidateID rawID: String, actor: String, decisionNote: String? = nil) throws -> SecondBrainEventDateFactCandidateView {
        let id = normalizedCandidateID(rawID)
        guard let existing = try factValidity.candidate(id: id) else {
            throw EventDateFactReviewError.candidateNotFound(id)
        }
        _ = try requireEventDateCandidate(existing)
        let beforeState = existing.reviewState
        let accepted = try factValidity.accept(candidateID: id, actor: actor, decisionNote: decisionNote)
        let structuredRef = try applyStructuredFact(for: accepted)
        try setStructuredFactRef(candidateID: id, structuredFactRef: structuredRef)
        let refreshed = try factValidity.candidate(id: id) ?? accepted
        return try view(
            refreshed,
            command: "item.event-date-facts.accept",
            action: "accept",
            actor: actor,
            changed: beforeState != refreshed.reviewState || structuredRef != nil,
            beforeState: beforeState
        )
    }

    func reject(candidateID rawID: String, actor: String, reason: String) throws -> SecondBrainEventDateFactCandidateView {
        let id = normalizedCandidateID(rawID)
        guard let existing = try factValidity.candidate(id: id) else {
            throw EventDateFactReviewError.candidateNotFound(id)
        }
        _ = try requireEventDateCandidate(existing)
        let rejected = existing.reviewState == "rejected"
            ? existing
            : try factValidity.reject(candidateID: id, actor: actor, reason: reason)
        return try view(
            rejected,
            command: "item.event-date-facts.reject",
            action: "reject",
            actor: actor,
            changed: existing.reviewState != rejected.reviewState,
            beforeState: existing.reviewState
        )
    }

    func deferReview(candidateID rawID: String, actor: String, reason: String) throws -> SecondBrainEventDateFactCandidateView {
        let id = normalizedCandidateID(rawID)
        guard let existing = try factValidity.candidate(id: id) else {
            throw EventDateFactReviewError.candidateNotFound(id)
        }
        _ = try requireEventDateCandidate(existing)
        let deferred = existing.reviewState == "deferred"
            ? existing
            : try factValidity.deferReview(candidateID: id, actor: actor, reason: reason)
        return try view(
            deferred,
            command: "item.event-date-facts.defer",
            action: "defer",
            actor: actor,
            changed: existing.reviewState != deferred.reviewState,
            beforeState: existing.reviewState
        )
    }

    func performReviewAction(
        candidateID rawID: String,
        expectedReviewState: String,
        expectedUpdatedAt: Date,
        action: CiderReviewAction,
        actor: String,
        reason: String?
    ) throws -> SecondBrainEventDateFactReviewMutationResult {
        guard action != .correct else {
            throw EventDateFactReviewError.unsupportedReviewAction(action.rawValue)
        }
        let id = normalizedCandidateID(rawID)
        let normalizedReason = Self.normalizedReason(reason, action: action)
        let fingerprint = Self.requestFingerprint(
            candidateID: id,
            expectedReviewState: expectedReviewState,
            expectedUpdatedAt: expectedUpdatedAt,
            action: action,
            actor: actor,
            reason: normalizedReason
        )
        let receiptID = Self.actionReceiptID(action: action, fingerprint: fingerprint)
        if let replay = try replayedMutation(
            candidateID: id,
            action: action,
            actor: actor,
            requestFingerprint: fingerprint,
            receiptID: receiptID
        ) {
            return replay
        }

        var result: SecondBrainEventDateFactReviewMutationResult!
        try database.withTransaction {
            guard let existing = try factValidity.candidate(id: id) else {
                throw EventDateFactReviewError.candidateNotFound(id)
            }
            _ = try requireEventDateCandidate(existing)
            guard existing.reviewState == expectedReviewState,
                  Self.preciseVersion(existing.candidate.updatedAt) == Self.preciseVersion(expectedUpdatedAt) else {
                if ["accepted", "rejected", "deferred"].contains(existing.reviewState) {
                    throw EventDateFactReviewError.alreadyReviewed(id, existing.reviewState)
                }
                throw EventDateFactReviewError.staleCandidate(id)
            }
            if ["accepted", "rejected"].contains(existing.reviewState)
                || (action == .defer && existing.reviewState == "deferred") {
                throw EventDateFactReviewError.alreadyReviewed(id, existing.reviewState)
            }
            try requireExactSourceEvidence(existing)

            var mutated: SecondBrainEventDateFactCandidateView
            switch action {
            case .approve:
                mutated = try accept(candidateID: id, actor: actor, decisionNote: normalizedReason)
            case .reject:
                mutated = try reject(candidateID: id, actor: actor, reason: normalizedReason)
            case .defer:
                mutated = try deferReview(candidateID: id, actor: actor, reason: normalizedReason)
            case .correct:
                throw EventDateFactReviewError.unsupportedReviewAction(action.rawValue)
            case .enrich:
                throw EventDateFactReviewError.unsupportedReviewAction(action.rawValue)
            }

            let canonicalCommand = Self.canonicalCommand(for: action)
            let canonicalAction = Self.canonicalAction(for: action)
            var receiptDictionary = mutated.actionReceipt
            receiptDictionary["id"] = receiptID
            receiptDictionary["command"] = canonicalCommand
            receiptDictionary["action"] = canonicalAction
            receiptDictionary["status"] = action == .defer ? "deferred" : "succeeded"
            var after = receiptDictionary["after"] as? [String: Any] ?? [:]
            after["requestFingerprint"] = fingerprint
            after["resultingCandidateVersion"] = Self.preciseVersion(mutated.candidate.candidate.updatedAt)
            receiptDictionary["after"] = after
            mutated.actionReceipt = receiptDictionary

            var record = try SecondBrainActionReceiptRecord(receiptDictionary: receiptDictionary)
            record.id = receiptID
            record.command = canonicalCommand
            record.action = canonicalAction
            record.status = action == .defer ? "deferred" : "succeeded"
            record.afterJSON = DatabaseHelpers.encodeJSON([
                "requestFingerprint": fingerprint,
                "resultingCandidateVersion": Self.preciseVersion(mutated.candidate.candidate.updatedAt),
                "reviewState": mutated.reviewState,
                "truthBoundary": mutated.truthBoundary,
                "structuredFactRef": mutated.structuredFactRef ?? "",
            ])
            record.correlationID = "event-date-review:\(mutated.candidateRef)"
            record.receiptJSON = Self.jsonString(receiptDictionary)
            _ = try SecondBrainActionReceiptLedgerService(database: database).record(record)
            result = SecondBrainEventDateFactReviewMutationResult(view: mutated, receiptID: receiptID, changed: true)
        }
        return result
    }

    private func view(
        _ candidate: SecondBrainFactValidityCandidateView,
        command: String,
        action: String,
        actor: String,
        changed: Bool,
        beforeState: String?,
        readOnly: Bool = false
    ) throws -> SecondBrainEventDateFactCandidateView {
        let metadata = try requireEventDateCandidate(candidate)
        let factKind = metadata["fact_kind"] ?? "event_date"
        let proposedDate = metadata["proposed_date"] ?? ""
        let eventLabel = metadata["event_label"] ?? candidate.candidate.targetRef
        let sourceItemRefs = [metadata["source_item_ref"] ?? candidate.candidate.sourceOwner.canonicalRef]
        let structuredFactRef = nonEmpty(metadata["structured_fact_ref"])
        let truthBoundary = truthBoundary(reviewState: candidate.reviewState, factKind: factKind)
        let structuredVerification = structuredFactRef.map {
            ["cider-cli item context \(contextCommandType(for: $0)) \(contextCommandID(for: $0)) --json"]
        } ?? []
        let safeVerification = [
            "cider-cli item event-date-facts inspect \(candidate.id) --json",
            "cider-cli item fact-validity inspect \(candidate.id) --json",
        ] + structuredVerification
        let safeNext = safeNextCommands(
            candidateID: candidate.id,
            reviewState: candidate.reviewState,
            updatedAt: candidate.candidate.updatedAt
        )
        let provenance: [String: Any] = [
            "sourceRef": candidate.candidate.sourceOwner.canonicalRef,
            "sourceItemRefs": sourceItemRefs,
            "sourceQuote": candidate.candidate.sourceQuote,
            "sourceEvidenceRef": candidate.candidate.sourceEvidenceRef as Any,
            "proposedDate": proposedDate,
            "eventLabel": eventLabel,
            "confidence": metadata["confidence"] ?? "source_backed_observation",
            "truthBoundary": candidate.truthBoundary,
        ]
        let receipt = actionReceipt(
            command: command,
            action: action,
            actor: actor,
            candidate: candidate,
            readOnly: readOnly,
            changed: changed,
            beforeState: beforeState,
            afterTruthBoundary: truthBoundary,
            structuredFactRef: structuredFactRef,
            safeVerificationCommands: safeVerification,
            safeNextCommands: safeNext
        )
        return SecondBrainEventDateFactCandidateView(
            id: candidate.id,
            candidateRef: candidate.candidate.candidateRef,
            targetRef: candidate.targetRef,
            factKind: factKind,
            eventLabel: eventLabel,
            proposedDate: proposedDate,
            confidence: metadata["confidence"] ?? "source_backed_observation",
            reason: candidate.candidate.reason,
            reviewState: candidate.reviewState,
            truthBoundary: truthBoundary,
            sourceItemRefs: sourceItemRefs,
            structuredFactRef: structuredFactRef,
            candidate: candidate,
            provenance: provenance,
            actionReceipt: receipt,
            safeVerificationCommands: safeVerification,
            safeNextCommands: safeNext
        )
    }

    private func requireEventDateCandidate(_ candidate: SecondBrainFactValidityCandidateView) throws -> [String: String] {
        let metadata = candidate.candidate.metadata
        guard metadata["candidate_family"] == "event_date_fact" else {
            throw EventDateFactReviewError.unsupportedCandidate(candidate.id)
        }
        return metadata
    }

    private func applyStructuredFact(for candidate: SecondBrainFactValidityCandidateView) throws -> String? {
        let metadata = try requireEventDateCandidate(candidate)
        guard candidate.reviewState == "accepted" else { return nil }
        guard let dateString = metadata["proposed_date"],
              let date = Self.localDayFormatter.date(from: dateString)
        else {
            throw EventDateFactReviewError.invalidProposedDate(metadata["proposed_date"] ?? "")
        }
        let label = metadata["event_label"] ?? "Accepted event date"
        let personName = metadata["person_name"] ?? label.replacingOccurrences(of: " birthday", with: "")
        let targetItemID = metadata["target_item_id"].flatMap(UUID.init(uuidString:))
        switch metadata["target_kind"] {
        case TargetKind.contactBirthday.rawValue:
            let id = try targetItemID ?? findContactID(displayName: personName) ?? createContact(displayName: personName)
            try upsertContactBirthday(contactID: id, displayName: personName, birthday: date, sourceQuote: candidate.candidate.sourceQuote)
            return "contact:\(id.uuidString)"
        default:
            let id = try targetItemID ?? findDateCardID(title: label) ?? createDateCard(title: label)
            try upsertDateCardStart(dateCardID: id, title: label, startAt: date, sourceQuote: candidate.candidate.sourceQuote)
            return "dateCard:\(id.uuidString)"
        }
    }

    private func createContact(displayName: String) throws -> UUID {
        let id = UUID()
        let now = Date()
        let itemStmt = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'contact', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(displayName, at: 2)
            .bind(DatabaseHelpers.encode(now), at: 3)
            .bind(DatabaseHelpers.encode(now), at: 4)
            .bind("Inbox/Contacts/\(displayName).vcf", at: 5)
        try itemStmt.step()
        return id
    }

    private func upsertContactBirthday(contactID: UUID, displayName: String, birthday: Date, sourceQuote: String) throws {
        let now = Date()
        let stmt = try database.prepare("""
            INSERT INTO contacts (item_id, relationship_label, birthday, notes, email, phone, address, has_avatar, custom_fields)
            VALUES (?, '', ?, ?, '', '', '', 0, '[]')
            ON CONFLICT(item_id) DO UPDATE SET birthday = excluded.birthday, notes = excluded.notes;
            """)
        stmt.bind(DatabaseHelpers.encode(contactID), at: 1)
            .bind(DatabaseHelpers.encode(birthday), at: 2)
            .bind(sourceQuote, at: 3)
        try stmt.step()
        try touchItem(id: contactID, title: displayName, updatedAt: now)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "contact", ownerID: contactID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: contactID.uuidString, source: "event_date_fact.accept", title: displayName, body: "\(displayName) birthday: \(Self.localDayFormatter.string(from: birthday))\nSource: \(sourceQuote)", chunkIndex: 0)
        ])
    }

    private func createDateCard(title: String) throws -> UUID {
        let id = UUID()
        let now = Date()
        let stmt = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'event', ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(title, at: 2)
            .bind(DatabaseHelpers.encode(now), at: 3)
            .bind(DatabaseHelpers.encode(now), at: 4)
            .bind("Inbox/DateCards/\(title).ics", at: 5)
        try stmt.step()
        return id
    }

    private func upsertDateCardStart(dateCardID: UUID, title: String, startAt: Date, sourceQuote: String) throws {
        let now = Date()
        let stmt = try database.prepare("""
            INSERT INTO events (item_id, details, start_at, end_at, all_day, location, amount, recurrence_rule, is_completed, completed_at, surfacing_rules, action_url, snoozed_until)
            VALUES (?, ?, ?, NULL, 1, '', NULL, NULL, 0, NULL, NULL, NULL, NULL)
            ON CONFLICT(item_id) DO UPDATE SET details = excluded.details, start_at = excluded.start_at, all_day = 1;
            """)
        stmt.bind(DatabaseHelpers.encode(dateCardID), at: 1)
            .bind(sourceQuote, at: 2)
            .bind(DatabaseHelpers.encode(startAt), at: 3)
        try stmt.step()
        try touchItem(id: dateCardID, title: title, updatedAt: now)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "dateCard", ownerID: dateCardID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: dateCardID.uuidString, source: "event_date_fact.accept", title: title, body: "\(title): \(Self.localDayFormatter.string(from: startAt))\nSource: \(sourceQuote)", chunkIndex: 0)
        ])
    }

    private func touchItem(id: UUID, title: String, updatedAt: Date) throws {
        let stmt = try database.prepare("UPDATE items SET title = ?, updated_at = ? WHERE id = ?;")
        stmt.bind(title, at: 1)
            .bind(DatabaseHelpers.encode(updatedAt), at: 2)
            .bind(DatabaseHelpers.encode(id), at: 3)
        try stmt.step()
    }

    private func findContactID(displayName: String) throws -> UUID? {
        let stmt = try database.prepare("SELECT id FROM items WHERE type = 'contact' AND lower(title) = lower(?) LIMIT 1;")
        stmt.bind(displayName, at: 1)
        guard try stmt.step() else { return nil }
        return DatabaseHelpers.decodeUUID(stmt.string(at: 0))
    }

    private func findDateCardID(title: String) throws -> UUID? {
        let stmt = try database.prepare("SELECT id FROM items WHERE type = 'event' AND lower(title) = lower(?) LIMIT 1;")
        stmt.bind(title, at: 1)
        guard try stmt.step() else { return nil }
        return DatabaseHelpers.decodeUUID(stmt.string(at: 0))
    }

    private func setStructuredFactRef(candidateID: String, structuredFactRef: String?) throws {
        guard let structuredFactRef else { return }
        let stmt = try database.prepare("""
            SELECT metadata FROM fact_validity_candidates WHERE id = ? LIMIT 1;
            """)
        stmt.bind(candidateID, at: 1)
        guard try stmt.step() else { return }
        var metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 0)) ?? [:]
        metadata["structured_fact_ref"] = structuredFactRef
        let update = try database.prepare("UPDATE fact_validity_candidates SET metadata = ?, updated_at = ? WHERE id = ?;")
        update.bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 1)
            .bind(DatabaseHelpers.encode(Date()), at: 2)
            .bind(candidateID, at: 3)
        try update.step()
    }

    private func detectBirthdayFact(in sourceQuote: String) throws -> String {
        let patterns = [
            #"(?i)\b([A-Z][A-Za-z0-9_-]{1,40})['’]s\s+birthday\b"#,
            #"(?i)\btoday\s+is\s+([A-Z][A-Za-z0-9_-]{1,40})\s+birthday\b"#,
            #"(?i)\b([A-Z][A-Za-z0-9_-]{1,40})\s+birthday\b"#,
        ]
        var names: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(sourceQuote.startIndex..., in: sourceQuote)
            for match in regex.matches(in: sourceQuote, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: sourceQuote) else { continue }
                let name = String(sourceQuote[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedName = name.lowercased()
                guard !["happy", "her", "his", "their", "my", "your"].contains(normalizedName) else { continue }
                if !name.isEmpty { names.append(name) }
            }
        }
        let unique = orderedUniqueStrings(names)
        if unique.isEmpty { throw EventDateFactReviewError.noBoundedEventDateFactFound }
        if unique.count > 1 { throw EventDateFactReviewError.ambiguousEventDateFact(unique) }
        return unique[0]
    }

    private func targetRef(for targetKind: TargetKind, itemID: UUID) -> String {
        switch targetKind {
        case .contactBirthday: return "contact:\(itemID.uuidString)#birthday"
        case .dateCard: return "dateCard:\(itemID.uuidString)#startAt"
        }
    }

    private func truthBoundary(reviewState: String, factKind: String) -> String {
        guard reviewState == "accepted" else { return "reviewable_candidate_not_truth" }
        return factKind == "contact_birthday" ? "accepted_contact_birthday" : "accepted_event_date"
    }

    private func actionReceipt(
        command: String,
        action: String,
        actor: String,
        candidate: SecondBrainFactValidityCandidateView,
        readOnly: Bool,
        changed: Bool,
        beforeState: String?,
        afterTruthBoundary: String,
        structuredFactRef: String?,
        safeVerificationCommands: [String],
        safeNextCommands: [String]
    ) -> [String: Any] {
        var after: [String: Any] = [
            "reviewState": candidate.reviewState,
            "truthBoundary": afterTruthBoundary,
            "targetRef": candidate.targetRef,
        ]
        if let structuredFactRef { after["structuredFactRef"] = structuredFactRef }
        var receipt: [String: Any] = [
            "command": command,
            "action": action,
            "actor": actor,
            "status": "succeeded",
            "readOnly": readOnly,
            "changed": changed,
            "owner": [
                "ownerType": candidate.candidate.sourceOwner.ownerType,
                "ownerID": candidate.candidate.sourceOwner.ownerID,
                "ref": candidate.candidate.sourceOwner.canonicalRef,
            ],
            "sourceRefs": orderedUniqueStrings([candidate.candidate.candidateRef, candidate.targetRef, candidate.candidate.sourceOwner.canonicalRef] + (structuredFactRef.map { [$0] } ?? [])),
            "evidenceRefs": orderedUniqueStrings([candidate.candidate.sourceOwner.canonicalRef, candidate.candidate.sourceEvidenceRef].compactMap { $0 }),
            "after": after,
            "safeVerificationCommands": safeVerificationCommands,
            "safeNextCommands": safeNextCommands,
        ]
        if let beforeState {
            receipt["before"] = ["reviewState": beforeState]
        }
        return receipt
    }

    private func safeNextCommands(candidateID: String, reviewState: String, updatedAt: Date) -> [String] {
        var commands = [
            "cider-cli item event-date-facts inspect \(candidateID) --json",
            "cider-cli item fact-validity inspect \(candidateID) --json",
        ]
        if ["suggested", "needs_review", "deferred"].contains(reviewState) {
            let selector = "\(reviewState)@\(Self.preciseVersion(updatedAt))"
            commands.append("cider-cli item event-date-facts accept \(candidateID) --reason <reason> --expected-version \(selector) --json")
            commands.append("cider-cli item event-date-facts reject \(candidateID) --reason <reason> --expected-version \(selector) --json")
            commands.append("cider-cli item event-date-facts defer \(candidateID) --reason <reason> --expected-version \(selector) --json")
            commands.append("cider-cli item event-date-facts accept \(candidateID) --reason <reason> --json")
            commands.append("cider-cli item event-date-facts reject \(candidateID) --reason <reason> --json")
            commands.append("cider-cli review approve \(candidateID) --json")
            commands.append("cider-cli review reject \(candidateID) --reason <reason> --json")
            commands.append("cider-cli review defer \(candidateID) --reason <reason> --json")
        }
        return commands
    }

    private func requireExactSourceEvidence(_ candidate: SecondBrainFactValidityCandidateView) throws {
        guard let evidenceID = candidate.candidate.sourceEvidenceID,
              candidate.candidate.sourceEvidenceRef == "source_evidence:\(evidenceID)",
              let evidence = candidate.sourceEvidenceRecord,
              evidence.id == evidenceID,
              evidence.candidateRef == candidate.candidate.candidateRef,
              evidence.sourceOwner == candidate.candidate.sourceOwner,
              evidence.sourceQuote == candidate.candidate.sourceQuote else {
            throw EventDateFactReviewError.missingSourceEvidence(candidate.id)
        }
    }

    private func replayedMutation(
        candidateID: String,
        action: CiderReviewAction,
        actor: String,
        requestFingerprint: String,
        receiptID: String
    ) throws -> SecondBrainEventDateFactReviewMutationResult? {
        guard let receipt = try SecondBrainActionReceiptLedgerService(database: database).inspect(id: receiptID),
              let current = try factValidity.candidate(id: candidateID),
              current.candidate.metadata["candidate_family"] == "event_date_fact",
              receipt.command == Self.canonicalCommand(for: action),
              receipt.action == Self.canonicalAction(for: action),
              receipt.actor == actor,
              receipt.status == (action == .defer ? "deferred" : "succeeded"),
              !receipt.readOnly,
              receipt.changed,
              receipt.sourceRefs.contains(current.candidate.candidateRef),
              let durable = DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON),
              durable["requestFingerprint"] == requestFingerprint,
              durable["resultingCandidateVersion"] == Self.preciseVersion(current.candidate.updatedAt),
              durable["reviewState"] == current.reviewState else {
            return nil
        }
        var view = try self.view(
            current,
            command: Self.canonicalCommand(for: action),
            action: Self.canonicalAction(for: action),
            actor: actor,
            changed: false,
            beforeState: current.reviewState
        )
        guard durable["truthBoundary"] == view.truthBoundary,
              durable["structuredFactRef"] == (view.structuredFactRef ?? "") else {
            return nil
        }
        var projectedReceipt = view.actionReceipt
        projectedReceipt["id"] = receipt.id
        projectedReceipt["status"] = action == .defer ? "deferred" : "succeeded"
        var after = projectedReceipt["after"] as? [String: Any] ?? [:]
        after["requestFingerprint"] = requestFingerprint
        after["resultingCandidateVersion"] = Self.preciseVersion(current.candidate.updatedAt)
        projectedReceipt["after"] = after
        view.actionReceipt = projectedReceipt
        return SecondBrainEventDateFactReviewMutationResult(view: view, receiptID: receipt.id, changed: false)
    }

    private static func requestFingerprint(
        candidateID: String,
        expectedReviewState: String,
        expectedUpdatedAt: Date,
        action: CiderReviewAction,
        actor: String,
        reason: String
    ) -> String {
        let fields = [
            "event-date-review-request-v1",
            "fact_validity_candidate:\(candidateID)",
            "event_date_fact",
            action.rawValue,
            actor,
            expectedReviewState,
            preciseVersion(expectedUpdatedAt),
            reason,
        ]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func actionReceiptID(action: CiderReviewAction, fingerprint: String) -> String {
        "event-date-review:\(canonicalAction(for: action)):\(fingerprint)"
    }

    private static func canonicalCommand(for action: CiderReviewAction) -> String {
        "item.event-date-facts.\(canonicalAction(for: action))"
    }

    private static func canonicalAction(for action: CiderReviewAction) -> String {
        action == .approve ? "accept" : action.rawValue
    }

    private static func normalizedReason(_ reason: String?, action: CiderReviewAction) -> String {
        let normalized = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty { return normalized }
        switch action {
        case .approve: return "Approved event/date fact."
        case .reject: return "Rejected event/date fact."
        case .defer: return "Deferred event/date fact."
        case .correct: return "Corrected event/date fact."
        case .enrich: return "Enrichment is not an event/date fact action."
        }
    }

    private static func preciseVersion(_ date: Date) -> String {
        String(format: "%016llx", date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private static func jsonString(_ dictionary: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func stableSlug(_ value: String) -> String {
        let slug = value
            .lowercased()
            .replacingOccurrences(of: #"'s\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "event-date-fact" : slug
    }

    private func normalizedCandidateID(_ value: String) -> String {
        value
            .replacingOccurrences(of: "fact_validity_candidate:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func contextCommandType(for ref: String) -> String {
        ref.hasPrefix("dateCard:") ? "dateCard" : "contact"
    }

    private func contextCommandID(for ref: String) -> String {
        ref.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ref
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

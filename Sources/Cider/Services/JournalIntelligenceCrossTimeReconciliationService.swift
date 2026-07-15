import Foundation

enum JournalIntelligenceReconciliationClassification: String, Codable, Equatable, CaseIterable {
    case repeated = "repeat"
    case newUpdate = "new_update"
    case correctionOrConflict = "correction_or_conflict"
    case genuinelyNew = "genuinely_new"
}

enum JournalIntelligenceReconciliationStatus: String, Codable, Equatable {
    case matched
    case noMatch = "no_match"
    case classificationWithheld = "classification_withheld"
    case ambiguous
    case unsupported
}

enum JournalIntelligenceMatchStrength: String, Codable, Equatable {
    case exact
    case strong
}

struct JournalIntelligenceLikelyMatch: Codable, Equatable, Identifiable {
    var id: String { canonicalRef }
    var canonicalRef: String
    var canonicalKind: String
    var canonicalLabel: String
    var matchStrength: JournalIntelligenceMatchStrength
    var confidence: Double
    var reasonCodes: [String]
    var evidence: String
    var safeNextCommands: [String]
}

struct JournalIntelligenceCanonicalFamilyScan: Codable, Equatable, Identifiable {
    var id: String { family }
    var family: String
    var limit: Int
    var loadedCount: Int
    var complete: Bool
    var truncated: Bool
}

struct JournalIntelligenceCrossTimeReconciliation: Codable, Equatable {
    var status: JournalIntelligenceReconciliationStatus
    var classification: JournalIntelligenceReconciliationClassification?
    var likelyMatches: [JournalIntelligenceLikelyMatch]
    var reasonCodes: [String]
    var explanation: String
    var comparedCanonicalKinds: [String]
    var canonicalFamilyScans: [JournalIntelligenceCanonicalFamilyScan]
    var maxLikelyMatches: Int
    var truthBoundary: String = "reviewable_candidate_not_truth"
    var readOnly: Bool = true
    var changed: Bool = false
    var safeNextCommands: [String]
}

@MainActor
final class JournalIntelligenceCrossTimeReconciliationService {
    struct Input {
        var proposal: JournalIntelligenceProposal
        var output: SecondBrainEnrichmentOutput
    }

    struct Batch {
        var byCandidateRef: [String: JournalIntelligenceCrossTimeReconciliation]
        var dataAsOf: Date?
    }

    private struct LabelRecord {
        var owner: SecondBrainOwnerRef
        var ownerKind: String
        var label: String
        var aliases: [String]
        var confidence: Double?
        var updatedAt: Date

        var allLabels: [String] { [label] + aliases }
    }

    private struct ItemRecord {
        var owner: SecondBrainOwnerRef
        var kind: String
        var title: String
        var detail: String
        var completed: Bool?
        var updatedAt: Date
    }

    private enum CanonicalScanFamily: String, Hashable {
        case ownerLabels = "owner_labels"
        case tasks = "tasks"
        case artifacts = "artifacts_media"
        case projects = "trip_projects"
        case acceptedMemories = "accepted_memory_facts"
        case acceptedGraph = "accepted_graph_facts"
    }

    private struct BoundedRows<Value> {
        var values: [Value]
        var scan: JournalIntelligenceCanonicalFamilyScan
    }

    private struct Snapshot {
        var labels: [LabelRecord]
        var tasks: [ItemRecord]
        var artifacts: [ItemRecord]
        var projects: [ItemRecord]
        var acceptedMemories: [SecondBrainEnrichmentOutput]
        var acceptedGraph: [SecondBrainEnrichmentOutput]
        var scans: [CanonicalScanFamily: JournalIntelligenceCanonicalFamilyScan]
        var dataAsOf: Date?
    }

    private struct PersonUpdate {
        var name: String
        var employer: String
    }

    private struct TripPlan {
        var destination: String
        var normalizedValue: String
    }

    private let database: CiderDatabase
    private let outputService: SecondBrainEnrichmentOutputService
    private let maximumLikelyMatches: Int
    private let labelScanLimit = 800
    private let itemScanLimit = 800
    private let projectScanLimit = 800
    private let acceptedOutputScanLimit = 500

    init(database: CiderDatabase = .shared, maximumLikelyMatches: Int = 3) {
        self.database = database
        self.outputService = SecondBrainEnrichmentOutputService(database: database)
        self.maximumLikelyMatches = min(5, max(1, maximumLikelyMatches))
    }

    func reconcile(_ inputs: [Input]) throws -> Batch {
        let snapshot = try loadSnapshot()
        var results: [String: JournalIntelligenceCrossTimeReconciliation] = [:]
        for input in inputs.sorted(by: { $0.proposal.candidateRef < $1.proposal.candidateRef }) {
            results[input.proposal.candidateRef] = reconcile(input, snapshot: snapshot)
        }
        return Batch(byCandidateRef: results, dataAsOf: snapshot.dataAsOf)
    }

    private func reconcile(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        switch input.proposal.category {
        case .people:
            return reconcilePerson(input, snapshot: snapshot)
        case .places:
            return reconcilePlace(input, snapshot: snapshot)
        case .tasks:
            return reconcileTask(input, snapshot: snapshot)
        case .artifactsMedia:
            return reconcileArtifact(input, snapshot: snapshot)
        case .tripPlans:
            return reconcileTrip(input, snapshot: snapshot)
        case .preferences:
            return reconcilePreference(input, snapshot: snapshot)
        case .durableMemory:
            return reconcileDurableMemory(input, snapshot: snapshot)
        case .activities, .commitments:
            return unsupported(
                comparedKinds: [],
                reason: "category_not_in_cross_time_checkpoint",
                explanation: "This category has no bounded canonical reconciliation family in this checkpoint, so Cider leaves it unclassified."
            )
        }
    }

    private func reconcilePerson(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        if let candidate = graphCandidate(input.output),
           !Set(candidate.objectTypeGuesses).isDisjoint(with: [.person, .contact]) {
            return reconcilePersonReference(candidate.mentionText, snapshot: snapshot)
        }
        let scans = canonicalScans([.ownerLabels, .acceptedMemories], in: snapshot)
        guard let update = personUpdate(from: input.output.value) else {
            return unsupported(
                comparedKinds: ["person", "accepted_memory_fact"],
                scans: scans,
                reason: "unsupported_person_assertion_shape",
                explanation: "The proposal does not expose one explicit person and employer update, so Cider cannot compare it safely."
            )
        }
        let personLabels = exactLabels(
            update.name,
            in: snapshot.labels,
            ownerKinds: ["person"],
            ownerTypes: ["contact", "person"]
        )
        if personLabels.count > 1 {
            return ambiguous(
                matches: personLabels.map { labelMatch($0, reason: "exact_person_label") },
                comparedKinds: ["person", "accepted_memory_fact"],
                scans: scans,
                reason: "multiple_exact_canonical_identities",
                explanation: "More than one canonical person has the exact label '\(update.name)', so Cider will not choose one."
            )
        }

        let priorUpdates = snapshot.acceptedMemories.compactMap { output -> (SecondBrainEnrichmentOutput, PersonUpdate)? in
            guard memoryKind(output) == "relationship_event",
                  let prior = personUpdate(from: output.value),
                  normalized(prior.name) == normalized(update.name) else { return nil }
            return (output, prior)
        }
        var matches = personLabels.map { labelMatch($0, reason: "exact_person_label") }
        matches += priorUpdates.map { acceptedMemoryMatch($0.0, strength: .strong, reason: "same_person_relationship_history") }
        guard !matches.isEmpty else {
            return noMatch(
                comparedKinds: ["person", "accepted_memory_fact"],
                scans: scans,
                reason: "no_exact_person_identity_or_history",
                explanation: "No canonical person or accepted person-update history exactly matches '\(update.name)'."
            )
        }
        if priorUpdates.contains(where: { normalized($0.1.employer) == normalized(update.employer) }) {
            return matched(
                classification: .repeated,
                matches: matches,
                comparedKinds: ["person", "accepted_memory_fact"],
                scans: scans,
                reason: "same_person_same_employer",
                explanation: "The same person and employer already appear in accepted canonical history."
            )
        }
        return matched(
            classification: .newUpdate,
            matches: matches,
            comparedKinds: ["person", "accepted_memory_fact"],
            scans: scans,
            reason: priorUpdates.isEmpty ? "known_person_new_relationship_update" : "known_person_changed_employer",
            explanation: priorUpdates.isEmpty
                ? "The person is canonical, but this source-backed employer update is new."
                : "The person is canonical and accepted history names a different employer, so this looks like a new update rather than a repeat."
        )
    }

    private func reconcilePersonReference(
        _ mention: String,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.ownerLabels], in: snapshot)
        let matches = exactLabels(
            mention,
            in: snapshot.labels,
            ownerKinds: ["person"],
            ownerTypes: ["contact", "person"]
        )
        if matches.count > 1 {
            return ambiguous(
                matches: matches.map { labelMatch($0, reason: "exact_person_label") },
                comparedKinds: ["person"],
                scans: scans,
                reason: "multiple_exact_canonical_identities",
                explanation: "More than one canonical person has the exact label '\(mention)', so Cider will not choose one."
            )
        }
        guard let match = matches.first else {
            return noMatch(
                comparedKinds: ["person"],
                scans: scans,
                reason: "no_exact_person_identity",
                explanation: "No canonical person exactly matches '\(mention)'."
            )
        }
        return matched(
            classification: .newUpdate,
            matches: [labelMatch(match, reason: "exact_person_label")],
            comparedKinds: ["person"],
            scans: scans,
            reason: "known_person_new_source_mention",
            explanation: "The Journal source names one known person exactly; the mention remains a reviewable update rather than an automatic link."
        )
    }

    private func reconcilePlace(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.ownerLabels, .acceptedGraph], in: snapshot)
        let mention = graphCandidate(input.output)?.mentionText ?? input.output.value
        let labelMatches = exactLabels(
            mention,
            in: snapshot.labels,
            ownerKinds: ["place"],
            ownerTypes: ["place"]
        )
        if labelMatches.count > 1 {
            return ambiguous(
                matches: labelMatches.map { labelMatch($0, reason: "exact_place_label") },
                comparedKinds: ["place", "accepted_graph_fact"],
                scans: scans,
                reason: "multiple_exact_canonical_identities",
                explanation: "More than one canonical place exactly matches '\(mention)', so Cider will not choose one."
            )
        }
        let accepted = acceptedGraphMatches(mention: mention, outputs: snapshot.acceptedGraph)
        var matches = labelMatches.map { labelMatch($0, reason: "exact_place_label") }
        matches += accepted.map { acceptedGraphMatch($0, reason: "same_place_accepted_graph_history") }
        guard !matches.isEmpty else {
            return noMatch(
                comparedKinds: ["place", "accepted_graph_fact"],
                scans: scans,
                reason: "no_exact_place_identity",
                explanation: "No canonical place or accepted graph fact exactly matches '\(mention)'."
            )
        }
        let currentRelations = Set(graphCandidate(input.output)?.relationGuesses.map(\.rawValue) ?? [])
        let repeated = accepted.contains { output in
            !currentRelations.isDisjoint(with: Set(graphRelations(output)))
        }
        return matched(
            classification: repeated ? .repeated : .newUpdate,
            matches: matches,
            comparedKinds: ["place", "accepted_graph_fact"],
            scans: scans,
            reason: repeated ? "same_place_same_relation" : "known_place_new_occurrence",
            explanation: repeated
                ? "The same place and relationship already exist in accepted graph history."
                : "The place is canonical, but this chronological Journal occurrence is a new update."
        )
    }

    private func reconcileTask(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.tasks, .acceptedMemories], in: snapshot)
        let value = canonicalAction(input.output.value)
        var matches = snapshot.tasks.filter { record in
            normalized(canonicalAction(record.title)) == normalized(value)
                || (!record.detail.isEmpty && normalized(canonicalAction(record.detail)) == normalized(value))
        }.map { itemMatch($0, reason: "exact_task_action") }
        matches += snapshot.acceptedMemories.filter { output in
            isMemoryKind(output, in: ["task", "todo", "reminder", "follow_up", "action_intent", "task_intent"])
                && normalized(canonicalAction(output.value)) == normalized(value)
        }.map { acceptedMemoryMatch($0, strength: .exact, reason: "same_accepted_task_intent") }
        let distinct = distinctMatches(matches)
        if distinct.count > 1 {
            return ambiguous(
                matches: distinct,
                comparedKinds: ["task", "accepted_memory_fact"],
                scans: scans,
                reason: "multiple_exact_canonical_tasks",
                explanation: "Multiple canonical tasks exactly match this action, so Cider will not choose one."
            )
        }
        guard !distinct.isEmpty else {
            return noMatch(
                comparedKinds: ["task", "accepted_memory_fact"],
                scans: scans,
                reason: "no_exact_task_action",
                explanation: "No canonical task or accepted task fact exactly matches this action."
            )
        }
        return matched(
            classification: .repeated,
            matches: distinct,
            comparedKinds: ["task", "accepted_memory_fact"],
            scans: scans,
            reason: "same_task_action",
            explanation: "A canonical task already carries the same normalized action."
        )
    }

    private func reconcileArtifact(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.ownerLabels, .artifacts, .acceptedMemories, .acceptedGraph], in: snapshot)
        let graph = graphCandidate(input.output)
        let identity = graph?.mentionText ?? artifactIdentity(from: input.output.value)
        guard let identity, !normalized(identity).isEmpty else {
            return unsupported(
                comparedKinds: ["media", "artifact", "accepted_memory_fact"],
                scans: scans,
                reason: "unsupported_artifact_identity_shape",
                explanation: "The proposal does not expose one explicit artifact identity, so Cider cannot compare it safely."
            )
        }
        let labels = exactLabels(
            identity,
            in: snapshot.labels,
            ownerKinds: ["media", "artifact", "file"],
            ownerTypes: ["media_item", "vaultFile", "bookmark"]
        )
        var matches = labels.map { labelMatch($0, reason: "exact_artifact_label") }
        matches += snapshot.artifacts.filter { normalized($0.title) == normalized(identity) }
            .map { itemMatch($0, reason: "exact_artifact_item_title") }
        let acceptedMemory = snapshot.acceptedMemories.filter { output in
            isMemoryKind(output, in: ["artifact", "artifact_intent", "media", "movie", "show", "book", "file", "url", "recipe"])
                && artifactIdentity(from: output.value).map(normalized) == normalized(identity)
        }
        matches += acceptedMemory.map { acceptedMemoryMatch($0, strength: .exact, reason: "same_accepted_artifact") }
        let acceptedGraph = acceptedGraphMatches(mention: identity, outputs: snapshot.acceptedGraph)
        matches += acceptedGraph.map { acceptedGraphMatch($0, reason: "same_accepted_artifact_history") }
        let distinct = distinctMatches(matches)
        if distinct.count > 1 {
            return ambiguous(
                matches: distinct,
                comparedKinds: ["media", "artifact", "accepted_memory_fact"],
                scans: scans,
                reason: "multiple_exact_canonical_artifacts",
                explanation: "Multiple canonical artifacts exactly match '\(identity)', so Cider will not choose one."
            )
        }
        guard !distinct.isEmpty else {
            return noMatch(
                comparedKinds: ["media", "artifact", "accepted_memory_fact"],
                scans: scans,
                reason: "no_exact_artifact_identity",
                explanation: "No canonical media or artifact record exactly matches '\(identity)'."
            )
        }
        let currentRelations = Set(graph?.relationGuesses.map(\.rawValue) ?? [])
        let repeatedGraphRelation = acceptedGraph.contains { output in
            !currentRelations.isEmpty && !currentRelations.isDisjoint(with: Set(graphRelations(output)))
        }
        let isArtifactIntent = isMemoryKind(input.output, in: ["artifact_intent"])
        let sameAcceptedIntent = acceptedMemory.contains { normalized($0.value) == normalized(input.output.value) }
        let isRepeat = repeatedGraphRelation
            || sameAcceptedIntent
            || (currentRelations.isEmpty && !isArtifactIntent)
        return matched(
            classification: isRepeat ? .repeated : .newUpdate,
            matches: distinct,
            comparedKinds: ["media", "artifact", "accepted_graph_fact", "accepted_memory_fact"],
            scans: scans,
            reason: isRepeat ? "same_artifact_assertion" : "known_artifact_new_occurrence_or_intent",
            explanation: isRepeat
                ? "Canonical history already contains the same artifact assertion."
                : "The artifact identity is canonical, but this source-backed occurrence or routing intent is a new update."
        )
    }

    private func reconcileTrip(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.ownerLabels, .projects, .acceptedMemories], in: snapshot)
        guard let plan = tripPlan(from: input.output.value) else {
            return unsupported(
                comparedKinds: ["trip_plan", "project", "accepted_memory_fact"],
                scans: scans,
                reason: "unsupported_trip_plan_shape",
                explanation: "The proposal does not contain one explicit named trip destination, so Cider cannot compare it safely."
            )
        }
        let prior = snapshot.acceptedMemories.compactMap { output -> (SecondBrainEnrichmentOutput, TripPlan)? in
            guard isMemoryKind(output, in: ["trip", "travel", "future_planning", "trip_plan"]),
                  let existing = tripPlan(from: output.value),
                  normalized(existing.destination) == normalized(plan.destination) else { return nil }
            return (output, existing)
        }
        var matches = prior.map { acceptedMemoryMatch($0.0, strength: .strong, reason: "same_trip_destination") }
        matches += snapshot.projects.filter { record in
            let label = normalized(record.title)
            return label == plan.normalizedValue
                || label.hasSuffix("trip to \(normalized(plan.destination))")
        }.map { itemMatch($0, reason: "same_trip_project") }
        matches += snapshot.labels.filter { record in
            ["trip", "project"].contains(record.ownerKind)
                && record.allLabels.contains(where: { label in
                    let normalizedLabel = normalized(label)
                    return normalizedLabel == plan.normalizedValue
                        || normalizedLabel.hasSuffix("trip to \(normalized(plan.destination))")
                })
        }.map { labelMatch($0, reason: "same_trip_identity") }
        let distinct = distinctMatches(matches)
        guard !distinct.isEmpty else {
            return noMatch(
                comparedKinds: ["trip_plan", "project", "accepted_memory_fact"],
                scans: scans,
                reason: "no_same_trip_destination",
                explanation: "No canonical trip plan, project, or accepted trip fact names '\(plan.destination)'."
            )
        }
        let exact = prior.contains { normalized($0.1.normalizedValue) == normalized(plan.normalizedValue) }
        return matched(
            classification: exact ? .repeated : .newUpdate,
            matches: distinct,
            comparedKinds: ["trip_plan", "project", "accepted_memory_fact"],
            scans: scans,
            reason: exact ? "same_trip_plan_value" : "same_destination_changed_plan_value",
            explanation: exact
                ? "Accepted trip history already contains the same destination and plan value."
                : "Canonical trip history names the same destination with different plan details, so this looks like a new update."
        )
    }

    private func reconcilePreference(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.acceptedGraph, .acceptedMemories], in: snapshot)
        guard let candidate = graphCandidate(input.output),
              let relation = candidate.relationGuesses.first(where: { [.likes, .likesDrink, .likesFood, .dislikes].contains($0) }) else {
            return unsupported(
                comparedKinds: ["accepted_graph_fact", "accepted_memory_fact"],
                scans: scans,
                reason: "unsupported_preference_assertion_shape",
                explanation: "The proposal does not expose one explicit preference relation, so Cider cannot compare it safely."
            )
        }
        let accepted = acceptedGraphMatches(mention: candidate.mentionText, outputs: snapshot.acceptedGraph)
            .filter { output in
                graphRelations(output).contains(where: { ["likes", "likes_drink", "likes_food", "dislikes"].contains($0) })
            }
        let targetRefs = Set(accepted.compactMap(acceptedGraphTargetRef))
        if targetRefs.count > 1 {
            return ambiguous(
                matches: accepted.map { acceptedGraphMatch($0, reason: "same_preference_object") },
                comparedKinds: ["accepted_graph_fact", "accepted_memory_fact"],
                scans: scans,
                reason: "multiple_exact_canonical_identities",
                explanation: "Accepted preference history points the same label at multiple canonical objects, so Cider will not choose one."
            )
        }
        let acceptedMemory = snapshot.acceptedMemories.filter { output in
            isMemoryKind(output, in: ["preference", "liked", "disliked", "favorite", "food_preference", "gift_preference"])
                && normalized(output.value) == normalized(input.output.value)
        }
        var matches = accepted.map { acceptedGraphMatch($0, reason: "same_preference_object") }
        matches += acceptedMemory.map { acceptedMemoryMatch($0, strength: .exact, reason: "same_accepted_preference") }
        guard !matches.isEmpty else {
            return noMatch(
                comparedKinds: ["accepted_graph_fact", "accepted_memory_fact"],
                scans: scans,
                reason: "no_exact_preference_object",
                explanation: "No accepted preference fact exactly matches '\(candidate.mentionText)'."
            )
        }
        let acceptedRelations = Set(accepted.flatMap(graphRelations))
        let current = relation.rawValue
        let conflict = (current == "dislikes" && !acceptedRelations.isDisjoint(with: ["likes", "likes_drink", "likes_food"]))
            || (current != "dislikes" && acceptedRelations.contains("dislikes"))
        let repeated = acceptedRelations.contains(current) || !acceptedMemory.isEmpty
        let classification: JournalIntelligenceReconciliationClassification = conflict
            ? .correctionOrConflict
            : (repeated ? .repeated : .newUpdate)
        return matched(
            classification: classification,
            matches: matches,
            comparedKinds: ["accepted_graph_fact", "accepted_memory_fact"],
            scans: scans,
            reason: conflict ? "opposing_accepted_preference_relation" : (repeated ? "same_preference_relation" : "known_object_new_preference"),
            explanation: conflict
                ? "Accepted preference history contains the opposing like/dislike relation, so this proposal is a correction or conflict for review."
                : (repeated
                    ? "Accepted preference history already contains the same relation."
                    : "The canonical object is known, but this preference relation is a new update.")
        )
    }

    private func reconcileDurableMemory(
        _ input: Input,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        if let candidate = graphCandidate(input.output), candidate.objectTypeGuesses.contains(.project) {
            return reconcileProjectReference(candidate.mentionText, snapshot: snapshot)
        }
        let scans = canonicalScans([.acceptedMemories], in: snapshot)
        let currentValue = normalized(input.output.value)
        let currentKey = normalized(input.output.metadata["memory_key"] ?? "")
        let relevant = snapshot.acceptedMemories.filter { output in
            isMemoryKind(output, in: ["memory", "pattern", "lesson", "project_context", "fact", "durable_memory", "spending", "payroll", "gift"])
        }
        let exact = relevant.filter { normalized($0.value) == currentValue }
        if !exact.isEmpty {
            return matched(
                classification: .repeated,
                matches: exact.map { acceptedMemoryMatch($0, strength: .exact, reason: "same_accepted_memory_value") },
                comparedKinds: ["accepted_memory_fact"],
                scans: scans,
                reason: "same_accepted_memory_value",
                explanation: "Accepted memory already contains the same normalized value."
            )
        }
        let sameKey = currentKey.isEmpty ? [] : relevant.filter {
            normalized($0.metadata["memory_key"] ?? "") == currentKey
        }
        if !sameKey.isEmpty {
            return matched(
                classification: .correctionOrConflict,
                matches: sameKey.map { acceptedMemoryMatch($0, strength: .strong, reason: "same_memory_key_changed_value") },
                comparedKinds: ["accepted_memory_fact"],
                scans: scans,
                reason: "same_memory_key_changed_value",
                explanation: "Accepted memory uses the same explicit memory key with a different value, so this proposal requires correction/conflict review."
            )
        }
        return noMatch(
            comparedKinds: ["accepted_memory_fact"],
            scans: scans,
            reason: "no_exact_accepted_memory",
            explanation: "No accepted memory has the same value or explicit memory key."
        )
    }

    private func reconcileProjectReference(
        _ mention: String,
        snapshot: Snapshot
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let scans = canonicalScans([.ownerLabels, .projects], in: snapshot)
        let labelMatches = exactLabels(
            mention,
            in: snapshot.labels,
            ownerKinds: ["project"],
            ownerTypes: ["project"]
        ).map { labelMatch($0, reason: "exact_project_label") }
        let key = normalized(mention)
        let projectMatches = snapshot.projects
            .filter { normalized($0.title) == key }
            .map { itemMatch($0, reason: "exact_project_title") }
        let matches = distinctMatches(labelMatches + projectMatches)
        if matches.count > 1 {
            return ambiguous(
                matches: matches,
                comparedKinds: ["project"],
                scans: scans,
                reason: "multiple_exact_canonical_projects",
                explanation: "More than one canonical project exactly matches '\(mention)', so Cider will not choose one."
            )
        }
        guard let match = matches.first else {
            return noMatch(
                comparedKinds: ["project"],
                scans: scans,
                reason: "no_exact_project_identity",
                explanation: "No canonical project exactly matches '\(mention)'."
            )
        }
        return matched(
            classification: .newUpdate,
            matches: [match],
            comparedKinds: ["project"],
            scans: scans,
            reason: "known_project_new_source_mention",
            explanation: "The Journal source names one known project exactly; the mention remains a reviewable update rather than an automatic link."
        )
    }

    private func loadSnapshot() throws -> Snapshot {
        let labels = try labelRecords()
        let tasks = try itemRecords(types: ["todo"], kind: "task", family: .tasks)
        let artifacts = try itemRecords(types: ["bookmark", "vaultFile"], kind: "artifact", family: .artifacts)
        let projects = try projectRecords()
        let memories = boundedRows(
            try outputService.outputs(
                kind: "memory_candidate",
                reviewStates: ["accepted"],
                limit: acceptedOutputScanLimit + 1
            ),
            family: .acceptedMemories,
            limit: acceptedOutputScanLimit
        )
        let graph = boundedRows(
            try outputService.outputs(
                kind: SecondBrainGraphCandidateContract.outputKind,
                reviewStates: [SecondBrainGraphCandidateContract.ReviewState.accepted.rawValue],
                limit: acceptedOutputScanLimit + 1
            ),
            family: .acceptedGraph,
            limit: acceptedOutputScanLimit
        )
        let dates = labels.values.map(\.updatedAt)
            + tasks.values.map(\.updatedAt)
            + artifacts.values.map(\.updatedAt)
            + projects.values.map(\.updatedAt)
            + memories.values.map(\.updatedAt)
            + graph.values.map(\.updatedAt)
        return Snapshot(
            labels: labels.values,
            tasks: tasks.values,
            artifacts: artifacts.values,
            projects: projects.values,
            acceptedMemories: memories.values,
            acceptedGraph: graph.values,
            scans: [
                .ownerLabels: labels.scan,
                .tasks: tasks.scan,
                .artifacts: artifacts.scan,
                .projects: projects.scan,
                .acceptedMemories: memories.scan,
                .acceptedGraph: graph.scan,
            ],
            dataAsOf: dates.max()
        )
    }

    private func labelRecords() throws -> BoundedRows<LabelRecord> {
        let stmt = try database.prepare("""
            SELECT owner_type, owner_id, owner_kind, canonical_label, aliases_json, confidence, updated_at
            FROM owner_label_index
            WHERE is_deleted = 0
            ORDER BY owner_type ASC, owner_id ASC
            LIMIT \(labelScanLimit + 1);
            """)
        var records: [LabelRecord] = []
        while try stmt.step() {
            records.append(LabelRecord(
                owner: SecondBrainOwnerRef(ownerType: stmt.string(at: 0), ownerID: stmt.string(at: 1)),
                ownerKind: stmt.string(at: 2),
                label: stmt.string(at: 3),
                aliases: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 4)),
                confidence: stmt.optionalDouble(at: 5),
                updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 6))
            ))
        }
        return boundedRows(records, family: .ownerLabels, limit: labelScanLimit)
    }

    private func itemRecords(
        types: [String],
        kind: String,
        family: CanonicalScanFamily
    ) throws -> BoundedRows<ItemRecord> {
        let placeholders = Array(repeating: "?", count: types.count).joined(separator: ",")
        let taskColumns = types == ["todo"] ? ", COALESCE(t.details, ''), t.is_completed" : ", '', NULL"
        let taskJoin = types == ["todo"] ? "LEFT JOIN todos t ON t.item_id = i.id" : ""
        let stmt = try database.prepare("""
            SELECT i.id, i.type, i.title, i.updated_at\(taskColumns)
            FROM items i
            \(taskJoin)
            WHERE i.type IN (\(placeholders))
            ORDER BY i.type ASC, i.id ASC
            LIMIT \(itemScanLimit + 1);
            """)
        for (index, type) in types.enumerated() { stmt.bind(type, at: Int32(index + 1)) }
        var records: [ItemRecord] = []
        while try stmt.step() {
            records.append(ItemRecord(
                owner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 0)),
                kind: kind,
                title: stmt.string(at: 2),
                detail: stmt.optionalString(at: 4) ?? "",
                completed: stmt.optionalInt(at: 5).map { $0 != 0 },
                updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 3))
            ))
        }
        return boundedRows(records, family: family, limit: itemScanLimit)
    }

    private func projectRecords() throws -> BoundedRows<ItemRecord> {
        let stmt = try database.prepare("SELECT id, title, subtitle, updated_at FROM projects ORDER BY id ASC LIMIT \(projectScanLimit + 1);")
        var records: [ItemRecord] = []
        while try stmt.step() {
            records.append(ItemRecord(
                owner: SecondBrainOwnerRef(ownerType: "project", ownerID: stmt.string(at: 0)),
                kind: "project",
                title: stmt.string(at: 1),
                detail: stmt.string(at: 2),
                completed: nil,
                updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 3))
            ))
        }
        return boundedRows(records, family: .projects, limit: projectScanLimit)
    }

    private func boundedRows<Value>(
        _ values: [Value],
        family: CanonicalScanFamily,
        limit: Int
    ) -> BoundedRows<Value> {
        let truncated = values.count > limit
        let bounded = Array(values.prefix(limit))
        return BoundedRows(
            values: bounded,
            scan: JournalIntelligenceCanonicalFamilyScan(
                family: family.rawValue,
                limit: limit,
                loadedCount: bounded.count,
                complete: !truncated,
                truncated: truncated
            )
        )
    }

    private func canonicalScans(
        _ families: [CanonicalScanFamily],
        in snapshot: Snapshot
    ) -> [JournalIntelligenceCanonicalFamilyScan] {
        families.compactMap { snapshot.scans[$0] }
    }

    private func exactLabels(
        _ identity: String,
        in records: [LabelRecord],
        ownerKinds: Set<String>,
        ownerTypes: Set<String>
    ) -> [LabelRecord] {
        let key = normalized(identity)
        return records.filter { record in
            (ownerKinds.isEmpty || ownerKinds.contains(record.ownerKind))
                && (ownerTypes.isEmpty || ownerTypes.contains(record.owner.ownerType))
                && record.allLabels.contains(where: { normalized($0) == key })
        }
    }

    private func acceptedGraphMatches(
        mention: String,
        outputs: [SecondBrainEnrichmentOutput]
    ) -> [SecondBrainEnrichmentOutput] {
        let key = normalized(mention)
        return outputs.filter { output in
            acceptedGraphTargetRef(output) != nil
                && normalized(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.mentionText] ?? output.value) == key
        }
    }

    private func personUpdate(from value: String) -> PersonUpdate? {
        let pattern = #"^\s*(.+?)\s+started\s+a\s+new\s+job\s+at\s+(.+?)[.]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 3,
              let nameRange = Range(match.range(at: 1), in: value),
              let employerRange = Range(match.range(at: 2), in: value) else { return nil }
        let name = String(value[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let employer = String(value[employerRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !name.isEmpty, !employer.isEmpty else { return nil }
        return PersonUpdate(name: name, employer: employer)
    }

    private func tripPlan(from value: String) -> TripPlan? {
        let cleaned = value
            .replacingOccurrences(of: #"^\s*plan\s+(?:a\s+|the\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let pattern = #"\btrip\s+to\s+([A-Za-z0-9'’.-]+(?:\s+[A-Za-z0-9'’.-]+){0,3})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              match.numberOfRanges == 2,
              let range = Range(match.range(at: 1), in: cleaned) else { return nil }
        let destination = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !destination.isEmpty else { return nil }
        return TripPlan(destination: destination, normalizedValue: normalized(cleaned))
    }

    private func artifactIdentity(from value: String) -> String? {
        let pattern = #"^\s*(?:save|attach|keep)\s+(?:the\s+)?(.+?)\s+(?:with|for|to)\s+(?:the\s+)?[^.]+[.]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 2,
              let range = Range(match.range(at: 1), in: value) else {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return cleaned.isEmpty ? nil : cleaned
        }
        let identity = String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return identity.isEmpty ? nil : identity
    }

    private func graphCandidate(_ output: SecondBrainEnrichmentOutput) -> SecondBrainGraphCandidateContract.Candidate? {
        guard output.kind == SecondBrainGraphCandidateContract.outputKind else { return nil }
        return try? SecondBrainGraphCandidateContract.validate(output)
    }

    private func graphRelations(_ output: SecondBrainEnrichmentOutput) -> [String] {
        DatabaseHelpers.decodeStringArray(
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses]
        )
    }

    private func acceptedGraphTargetRef(_ output: SecondBrainEnrichmentOutput) -> String? {
        guard let type = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType],
              let id = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID],
              !type.isEmpty, !id.isEmpty else { return nil }
        return "\(type):\(id)"
    }

    private func memoryKind(_ output: SecondBrainEnrichmentOutput) -> String {
        normalized(output.metadata["accepted_memory_kind"]
            ?? output.metadata["memory_kind"]
            ?? output.metadata["candidate_kind"]
            ?? "memory")
    }

    private func isMemoryKind(_ output: SecondBrainEnrichmentOutput, in fragments: [String]) -> Bool {
        let kind = memoryKind(output)
        return fragments.contains(where: kind.contains)
    }

    private func labelMatch(_ record: LabelRecord, reason: String) -> JournalIntelligenceLikelyMatch {
        JournalIntelligenceLikelyMatch(
            canonicalRef: record.owner.canonicalRef,
            canonicalKind: record.ownerKind,
            canonicalLabel: record.label,
            matchStrength: .exact,
            confidence: bounded(record.confidence ?? 0.95),
            reasonCodes: [reason],
            evidence: "Canonical label or alias exactly matches the proposal identity.",
            safeNextCommands: [contextCommand(for: record.owner)]
        )
    }

    private func itemMatch(_ record: ItemRecord, reason: String) -> JournalIntelligenceLikelyMatch {
        JournalIntelligenceLikelyMatch(
            canonicalRef: record.owner.canonicalRef,
            canonicalKind: record.kind,
            canonicalLabel: record.title,
            matchStrength: .exact,
            confidence: 1,
            reasonCodes: [reason] + (record.completed == true ? ["canonical_task_completed"] : []),
            evidence: record.detail.isEmpty
                ? "Canonical item title exactly matches the proposal identity."
                : "Canonical item title or detail exactly matches the proposal identity.",
            safeNextCommands: [contextCommand(for: record.owner)]
        )
    }

    private func acceptedMemoryMatch(
        _ output: SecondBrainEnrichmentOutput,
        strength: JournalIntelligenceMatchStrength,
        reason: String
    ) -> JournalIntelligenceLikelyMatch {
        JournalIntelligenceLikelyMatch(
            canonicalRef: "accepted_memory_fact:\(output.id)",
            canonicalKind: "accepted_memory_fact",
            canonicalLabel: output.value,
            matchStrength: strength,
            confidence: bounded(output.confidence ?? 0.9),
            reasonCodes: [reason, "accepted_truth_only"],
            evidence: output.evidence.isEmpty ? output.value : output.evidence,
            safeNextCommands: ["cider-cli item memory-facts inspect \(output.id) --json"]
        )
    }

    private func acceptedGraphMatch(
        _ output: SecondBrainEnrichmentOutput,
        reason: String
    ) -> JournalIntelligenceLikelyMatch {
        let ref = acceptedGraphTargetRef(output) ?? "graph_candidate:\(output.id)"
        let kind = ref.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "accepted_graph_fact"
        let label = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.mentionText] ?? output.value
        let command: String
        if let target = ownerRef(from: ref) {
            command = contextCommand(for: target)
        } else {
            command = "cider-cli item graph-candidate \(output.id) --json"
        }
        return JournalIntelligenceLikelyMatch(
            canonicalRef: ref,
            canonicalKind: kind,
            canonicalLabel: label,
            matchStrength: .exact,
            confidence: bounded(output.confidence ?? 0.9),
            reasonCodes: [reason, "accepted_truth_only"],
            evidence: output.evidence,
            safeNextCommands: [command]
        )
    }

    private func matched(
        classification: JournalIntelligenceReconciliationClassification,
        matches: [JournalIntelligenceLikelyMatch],
        comparedKinds: [String],
        scans: [JournalIntelligenceCanonicalFamilyScan],
        reason: String,
        explanation: String
    ) -> JournalIntelligenceCrossTimeReconciliation {
        return makeResult(
            status: .matched,
            classification: classification,
            matches: matches,
            comparedKinds: comparedKinds,
            scans: scans,
            reasonCodes: [reason],
            explanation: explanation
        )
    }

    private func noMatch(
        comparedKinds: [String],
        scans: [JournalIntelligenceCanonicalFamilyScan],
        reason: String,
        explanation: String
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let truncatedScans = scans.filter(\.truncated)
        if !truncatedScans.isEmpty {
            let families = truncatedScans.map { "\($0.family) (\($0.loadedCount)/\($0.limit) loaded)" }
                .joined(separator: ", ")
            return makeResult(
                status: .classificationWithheld,
                classification: nil,
                matches: [],
                comparedKinds: comparedKinds,
                scans: scans,
                reasonCodes: ["canonical_scan_truncated", "classification_withheld"]
                    + truncatedScans.map { "truncated_canonical_family_\($0.family)" },
                explanation: "No match appeared in the loaded canonical rows, but these relevant bounded family scans were truncated and may omit a match: \(families). Cider withholds classification rather than asserting that the proposal is genuinely new."
            )
        }
        return makeResult(
            status: .noMatch,
            classification: .genuinelyNew,
            matches: [],
            comparedKinds: comparedKinds,
            scans: scans,
            reasonCodes: [reason],
            explanation: "\(explanation) Within the bounded audited families, this proposal looks genuinely new."
        )
    }

    private func ambiguous(
        matches: [JournalIntelligenceLikelyMatch],
        comparedKinds: [String],
        scans: [JournalIntelligenceCanonicalFamilyScan],
        reason: String,
        explanation: String
    ) -> JournalIntelligenceCrossTimeReconciliation {
        makeResult(
            status: .ambiguous,
            classification: nil,
            matches: matches,
            comparedKinds: comparedKinds,
            scans: scans,
            reasonCodes: [reason, "classification_withheld"],
            explanation: explanation
        )
    }

    private func unsupported(
        comparedKinds: [String],
        scans: [JournalIntelligenceCanonicalFamilyScan] = [],
        reason: String,
        explanation: String
    ) -> JournalIntelligenceCrossTimeReconciliation {
        makeResult(
            status: .unsupported,
            classification: nil,
            matches: [],
            comparedKinds: comparedKinds,
            scans: scans,
            reasonCodes: [reason, "classification_withheld"],
            explanation: explanation
        )
    }

    private func makeResult(
        status: JournalIntelligenceReconciliationStatus,
        classification: JournalIntelligenceReconciliationClassification?,
        matches: [JournalIntelligenceLikelyMatch],
        comparedKinds: [String],
        scans: [JournalIntelligenceCanonicalFamilyScan],
        reasonCodes: [String],
        explanation: String
    ) -> JournalIntelligenceCrossTimeReconciliation {
        let boundedMatches = Array(distinctMatches(matches).prefix(maximumLikelyMatches))
        return JournalIntelligenceCrossTimeReconciliation(
            status: status,
            classification: classification,
            likelyMatches: boundedMatches,
            reasonCodes: orderedUnique(reasonCodes),
            explanation: explanation,
            comparedCanonicalKinds: orderedUnique(comparedKinds),
            canonicalFamilyScans: scans,
            maxLikelyMatches: maximumLikelyMatches,
            safeNextCommands: orderedUnique(boundedMatches.flatMap(\.safeNextCommands))
        )
    }

    private func distinctMatches(_ matches: [JournalIntelligenceLikelyMatch]) -> [JournalIntelligenceLikelyMatch] {
        var byRef: [String: JournalIntelligenceLikelyMatch] = [:]
        for match in matches {
            if let current = byRef[match.canonicalRef], current.confidence >= match.confidence { continue }
            byRef[match.canonicalRef] = match
        }
        return byRef.values.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.canonicalRef < rhs.canonicalRef
        }
    }

    private func canonicalAction(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\s*(?:remember\s+to|i\s+(?:need|must)\s+to)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bounded(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func ownerRef(from canonicalRef: String) -> SecondBrainOwnerRef? {
        let parts = canonicalRef.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return SecondBrainOwnerRef(ownerType: parts[0], ownerID: parts[1])
    }

    private func contextCommand(for owner: SecondBrainOwnerRef) -> String {
        let libraryTypes: Set<String> = ["bookmark", "note", "todo", "dateCard", "event", "contact", "vaultFile"]
        if libraryTypes.contains(owner.ownerType) {
            return "cider-cli item context \(owner.ownerType) \(owner.ownerID) --json"
        }
        return "cider-cli item owner-get \(owner.ownerType) \(owner.ownerID) --json"
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

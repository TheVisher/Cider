import CryptoKit
import Foundation

private struct LegacyRegistryMappingDiagnoser {
    private struct SaturatingCount {
        private(set) var value: LegacyBoundedCount = .exact(0)
        mutating func increment() {
            switch value {
            case .exact(let current) where current < 99: value = .exact(current + 1)
            case .exact, .atLeast100: value = .atLeast100
            }
        }
    }

    static func diagnose(_ records: [CiderAgentChatRecord]) -> LegacyRegistryMappingDiagnosis? {
        let conversationGroups = Dictionary(grouping: records.indices, by: { records[$0].conversationID })
        let stableGroups = Dictionary(grouping: records.indices, by: { records[$0].stableID })
        var conversationCount = SaturatingCount()
        var stableCount = SaturatingCount()
        var affected = Set<Int>()
        var affectedCount = SaturatingCount()

        for group in conversationGroups.values where group.count >= 2 {
            conversationCount.increment()
            for index in group where affected.insert(index).inserted { affectedCount.increment() }
        }
        for group in stableGroups.values where group.count >= 2 {
            stableCount.increment()
            for index in group where affected.insert(index).inserted { affectedCount.increment() }
        }
        guard !conversationCount.value.isZero || !stableCount.value.isZero else { return nil }
        return .init(affectedRegistryRecordCount: affectedCount.value, counts: [
            .init(kind: .conversationIdentityMapping, conflictingMappingGroups: conversationCount.value),
            .init(kind: .stableRoomMapping, conflictingMappingGroups: stableCount.value),
        ])
    }
}

struct LegacyCandidateConflictDiagnoser {
    private struct RuntimeBindingIdentity: Hashable {
        let sourceNamespace: String
        let externalSessionID: String
    }

    private struct SaturatingCount {
        private(set) var value: LegacyBoundedCount = .exact(0)

        mutating func increment() {
            switch value {
            case .exact(let current) where current < 99:
                value = .exact(current + 1)
            case .exact, .atLeast100:
                value = .atLeast100
            }
        }
    }

    private struct IdentityAccumulator<Key: Hashable> {
        private var firstCandidateByKey: [Key: Int] = [:]
        private var conflictingKeys = Set<Key>()
        private(set) var conflictingGroupCount = SaturatingCount()

        mutating func record(
            _ keys: Set<Key>,
            candidateIndex: Int,
            affectedCandidates: inout Set<Int>,
            affectedCount: inout SaturatingCount
        ) {
            for key in keys {
                guard let firstCandidate = firstCandidateByKey[key] else {
                    firstCandidateByKey[key] = candidateIndex
                    continue
                }
                guard firstCandidate != candidateIndex else { continue }
                if conflictingKeys.insert(key).inserted {
                    conflictingGroupCount.increment()
                }
                if affectedCandidates.insert(firstCandidate).inserted { affectedCount.increment() }
                if affectedCandidates.insert(candidateIndex).inserted { affectedCount.increment() }
            }
        }
    }

    static func diagnose(_ plans: [LegacyConversationImportPlan]) -> LegacyCandidateConflictDiagnosis? {
        var messageRecords = IdentityAccumulator<UUID>()
        var messageProvenance = IdentityAccumulator<ConversationSourceIdentity>()
        var runtimeBindings = IdentityAccumulator<RuntimeBindingIdentity>()
        var historicalTurns = IdentityAccumulator<ConversationSourceIdentity>()
        var affectedCandidates = Set<Int>()
        var affectedCount = SaturatingCount()

        for (candidateIndex, plan) in plans.enumerated() {
            messageRecords.record(
                Set(plan.messages.map(\.id)),
                candidateIndex: candidateIndex,
                affectedCandidates: &affectedCandidates,
                affectedCount: &affectedCount
            )
            messageProvenance.record(
                Set(plan.messages.compactMap(\.source)),
                candidateIndex: candidateIndex,
                affectedCandidates: &affectedCandidates,
                affectedCount: &affectedCount
            )
            runtimeBindings.record(
                Set(plan.bindings.map {
                    RuntimeBindingIdentity(
                        sourceNamespace: $0.sourceNamespace,
                        externalSessionID: $0.externalSessionID
                    )
                }),
                candidateIndex: candidateIndex,
                affectedCandidates: &affectedCandidates,
                affectedCount: &affectedCount
            )
            historicalTurns.record(
                Set(plan.turns.map(\.source)),
                candidateIndex: candidateIndex,
                affectedCandidates: &affectedCandidates,
                affectedCount: &affectedCount
            )
        }

        let counts = [
            LegacyCandidateConflictCount(
                kind: .messageRecordIdentity,
                conflictingIdentityGroups: messageRecords.conflictingGroupCount.value
            ),
            LegacyCandidateConflictCount(
                kind: .messageProvenanceIdentity,
                conflictingIdentityGroups: messageProvenance.conflictingGroupCount.value
            ),
            LegacyCandidateConflictCount(
                kind: .runtimeBindingIdentity,
                conflictingIdentityGroups: runtimeBindings.conflictingGroupCount.value
            ),
            LegacyCandidateConflictCount(
                kind: .historicalTurnProvenanceIdentity,
                conflictingIdentityGroups: historicalTurns.conflictingGroupCount.value
            ),
        ]
        guard counts.contains(where: { !$0.conflictingIdentityGroups.isZero }) else { return nil }
        return .init(affectedCandidateCount: affectedCount.value, counts: counts)
    }
}

/// Read-only legacy Rooms reader. It never creates storage, writes canonical rows, or authorizes migration.
@MainActor
final class LegacyConversationEligiblePreviewService {
    struct Limits: Equatable {
        var maximumFiles = 1_000
        var maximumMessageLines = 100_000
        var maximumTotalBytes = 256 * 1_024 * 1_024
    }

    private struct Fingerprint: Equatable {
        let name: String
        let byteCount: Int
        let sha256: String
        let inode: UInt64
        let modifiedAt: TimeInterval
    }

    private struct SnapshottedFile {
        let url: URL
        let data: Data
        let fingerprint: Fingerprint
    }

    private struct Snapshot {
        let registry: [SnapshottedFile]
        let conversations: [SnapshottedFile]
    }

    private struct DecodedConversation {
        let metadata: AIConversationMeta?
        let messages: [LegacyConversationSnapshotMapper.PhysicalMessage]
        let physicalMessageRows: Int
        let complete: Bool
    }

    private struct Candidate {
        let record: CiderAgentChatRecord
        var plan: LegacyConversationImportPlan
        var valid: Bool
    }

    private enum SnapshotError: Error { case blocked, failed }

    private let registryDirectory: URL
    private let conversationDirectory: URL
    private let parityReader: any ConversationCoreParityReading
    private let canonicalIsHonestlyEmpty: () throws -> Bool
    private let limits: Limits
    private let fileManager: FileManager
    private let beforeRevalidation: () -> Void
    private let decoder: JSONDecoder
    private let mapper = LegacyConversationSnapshotMapper()
    private let sourceMapper = LegacyConversationSourceIdentityMapper()

    init(
        registryDirectory: URL,
        conversationDirectory: URL,
        parityReader: any ConversationCoreParityReading,
        canonicalIsHonestlyEmpty: @escaping () throws -> Bool,
        limits: Limits = .init(),
        fileManager: FileManager = .default,
        beforeRevalidation: @escaping () -> Void = {}
    ) {
        self.registryDirectory = registryDirectory
        self.conversationDirectory = conversationDirectory
        self.parityReader = parityReader
        self.canonicalIsHonestlyEmpty = canonicalIsHonestlyEmpty
        self.limits = limits
        self.fileManager = fileManager
        self.beforeRevalidation = beforeRevalidation
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func preview() -> LegacyConversationEligiblePreview {
        do {
            guard try canonicalIsHonestlyEmpty() else { return .sanitized(.blocked) }
            let snapshot = try captureSnapshot()
            let result = try evaluate(snapshot)
            beforeRevalidation()
            guard try snapshotIsUnchanged(snapshot) else { return .sanitized(.failed) }
            return result
        } catch SnapshotError.blocked {
            return .sanitized(.blocked)
        } catch {
            return .sanitized(.failed)
        }
    }

    private func evaluate(_ snapshot: Snapshot) throws -> LegacyConversationEligiblePreview {
        let registries = try decodeRegistries(snapshot.registry)
        if let diagnosis = LegacyRegistryMappingDiagnoser.diagnose(registries) {
            return .registryMappingConflict(diagnosis)
        }
        let active = registries.filter { !$0.archived }
        let allRegistryIDs = Set(registries.map(\.conversationID))

        var totalLines = 0
        var conversations: [DecodedConversation] = []
        for file in snapshot.conversations {
            let decoded = decodeConversation(file.data)
            totalLines += decoded.physicalMessageRows
            guard totalLines <= limits.maximumMessageLines else { throw SnapshotError.blocked }
            conversations.append(decoded)
        }

        let orphanIndices = conversations.indices.filter { index in
            guard let id = conversations[index].metadata?.id else { return true }
            return !allRegistryIDs.contains(id)
        }
        guard orphanIndices.allSatisfy({ conversations[$0].complete }) else { throw SnapshotError.blocked }

        let byMetadataID = Dictionary(grouping: conversations.indices.compactMap { index in
            conversations[index].metadata.map { ($0.id, index) }
        }, by: { $0.0 }).mapValues { $0.map(\.1) }

        var candidates: [Candidate] = []
        for record in active {
            let matches = byMetadataID[record.conversationID] ?? []
            guard matches.count == 1 else {
                candidates.append(.init(record: record, plan: .init(), valid: false))
                continue
            }
            let conversation = conversations[matches[0]]
            var valid = conversation.complete && conversation.physicalMessageRows == conversation.messages.count
            if let metadata = conversation.metadata {
                valid = valid && metadata.type == "metadata" && metadata.messageCount == conversation.messages.count
                valid = valid && registry(record, agreesWith: metadata)
            } else {
                valid = false
            }
            valid = valid && validateRaw(record: record, conversation: conversation)
            var plan = mapper.map(
                record: record,
                metadata: conversation.metadata.map(LegacyConversationMetadataSnapshot.init),
                messages: conversation.messages
            )
            valid = valid && validatePlan(plan)
            if valid { valid = try applyCanonicalParity(to: &plan) }
            candidates.append(.init(record: record, plan: plan, valid: valid))
        }

        omitCandidatesCollidingWithOrphans(&candidates, conversations: conversations, orphanIndices: orphanIndices)
        let locallyEligible = candidates.filter(\.valid)
        if let diagnosis = LegacyCandidateConflictDiagnoser.diagnose(locallyEligible.map(\.plan)) {
            return .identityConflict(diagnosis)
        }

        let sortedEligible = locallyEligible.sorted {
            if $0.record.updatedAt != $1.record.updatedAt { return $0.record.updatedAt > $1.record.updatedAt }
            return $0.record.conversationID.uuidString < $1.record.conversationID.uuidString
        }
        let displayed = Array(sortedEligible.prefix(20))
        let rooms = displayed.map { candidate -> LegacyConversationEligibleRoom in
            let total = candidate.plan.messages.count
            var cappedPlan = candidate.plan
            cappedPlan.messages = Array(candidate.plan.messages.sorted(by: messageDescending).prefix(100))
                .sorted(by: messageAscending)
            return .init(plan: cappedPlan, totalMessages: total, messageCapOmitted: max(total - 100, 0))
        }
        let counts = LegacyConversationEligibleCounts(
            registeredActiveTotal: active.count,
            eligibleTotal: sortedEligible.count,
            roomLocalOmitted: active.count - sortedEligible.count,
            displayedTotal: displayed.count,
            eligibleCapOmitted: sortedEligible.count - displayed.count,
            unregisteredFileTotal: orphanIndices.count
        )
        guard counts.isExact else { return .sanitized(.blocked) }
        let state: LegacyConversationEligiblePreviewState
        if active.isEmpty {
            state = .empty
        } else if sortedEligible.isEmpty {
            state = .eligibleEmpty
        } else {
            state = .ready
        }
        return .init(state: state, counts: counts, rooms: rooms)
    }

    private func captureSnapshot() throws -> Snapshot {
        let registry = try snapshotFiles(in: registryDirectory, extension: "json")
        let conversations = try snapshotFiles(in: conversationDirectory, extension: "jsonl")
        guard registry.count + conversations.count <= limits.maximumFiles,
              registry.reduce(0, { $0 + $1.data.count }) + conversations.reduce(0, { $0 + $1.data.count }) <= limits.maximumTotalBytes else {
            throw SnapshotError.blocked
        }
        return .init(registry: registry, conversations: conversations)
    }

    private func snapshotFiles(in directory: URL, extension pathExtension: String) throws -> [SnapshottedFile] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue, !isSymbolicLink(directory) else { throw SnapshotError.blocked }
        let root = directory.standardizedFileURL.path
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw SnapshotError.blocked
        }
        return try urls.filter { $0.pathExtension == pathExtension }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let standardized = url.standardizedFileURL
            guard standardized.deletingLastPathComponent().path == root,
                  !isSymbolicLink(url),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw SnapshotError.blocked
            }
            do {
                let data = try Data(contentsOf: url)
                return .init(url: url, data: data, fingerprint: try fingerprint(url: url, data: data))
            } catch let error as SnapshotError {
                throw error
            } catch {
                throw SnapshotError.failed
            }
        }
    }

    private func snapshotIsUnchanged(_ snapshot: Snapshot) throws -> Bool {
        for (directory, pathExtension, expected) in [
            (registryDirectory, "json", snapshot.registry),
            (conversationDirectory, "jsonl", snapshot.conversations),
        ] {
            let current = try snapshotFiles(in: directory, extension: pathExtension)
            guard current.map(\.fingerprint) == expected.map(\.fingerprint) else { return false }
        }
        return true
    }

    private func fingerprint(url: URL, data: Data) throws -> Fingerprint {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { throw SnapshotError.failed }
        return .init(
            name: url.lastPathComponent,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            inode: inode,
            modifiedAt: modified.timeIntervalSince1970
        )
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func decodeRegistries(_ files: [SnapshottedFile]) throws -> [CiderAgentChatRecord] {
        do { return try files.map { try decoder.decode(CiderAgentChatRecord.self, from: $0.data) } }
        catch { throw SnapshotError.blocked }
    }

    private func decodeConversation(_ data: Data) -> DecodedConversation {
        guard let text = String(data: data, encoding: .utf8) else {
            return .init(metadata: nil, messages: [], physicalMessageRows: 0, complete: false)
        }
        var lines = text.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        guard let first = lines.first, !first.isEmpty else {
            return .init(metadata: nil, messages: [], physicalMessageRows: max(lines.count - 1, 0), complete: false)
        }
        let metadata = try? decoder.decode(AIConversationMeta.self, from: Data(first.utf8))
        var messages: [LegacyConversationSnapshotMapper.PhysicalMessage] = []
        var complete = true
        for (offset, line) in lines.dropFirst().enumerated() {
            guard !line.isEmpty,
                  let message = try? decoder.decode(AIAssistantMessage.self, from: Data(line.utf8)) else {
                complete = false
                continue
            }
            messages.append(.init(physicalLine: offset + 2, message: .init(message)))
        }
        return .init(
            metadata: metadata,
            messages: messages,
            physicalMessageRows: max(lines.count - 1, 0),
            complete: complete
        )
    }

    private func registry(_ record: CiderAgentChatRecord, agreesWith metadata: AIConversationMeta) -> Bool {
        record.conversationID == metadata.id && record.title == metadata.title &&
            record.runtimeID == (metadata.runtimeID ?? "") &&
            record.activeRuntimeSessionID == (metadata.activeRuntimeSessionID ?? "") &&
            record.runtimeSessionLineage == (metadata.runtimeSessionLineage ?? []) &&
            record.lastSyncedMessageID == metadata.runtimeLastSyncedMessageID &&
            record.lastSyncedTimestamp == metadata.runtimeLastSyncedTimestamp &&
            record.lastImportedRuntimeSessionID == metadata.runtimeLastImportedSessionID
    }

    private func validateRaw(record: CiderAgentChatRecord, conversation: DecodedConversation) -> Bool {
        var sessions = record.runtimeSessionLineage
        if !record.activeRuntimeSessionID.isEmpty, !sessions.contains(record.activeRuntimeSessionID) { sessions.append(record.activeRuntimeSessionID) }
        guard !sessions.isEmpty, sessions.allSatisfy({ !$0.isEmpty }), unique(sessions) else { return false }
        var messageIDs = Set<UUID>()
        var sources = Set<ConversationSourceIdentity>()
        for physical in conversation.messages {
            let message = physical.message
            let mapped = sourceMapper.map(message.sourceID, role: message.role.rawValue)
            guard message.attachments.isEmpty, !mapped.malformedRecognizedStyle,
                  messageIDs.insert(message.id).inserted else { return false }
            if let source = mapped.source, !sources.insert(source).inserted { return false }
            if let session = message.sourceSessionID, !session.isEmpty, !sessions.contains(session) { return false }
        }
        return true
    }

    private func validatePlan(_ plan: LegacyConversationImportPlan) -> Bool {
        guard plan.rooms.count == 1, !plan.bindings.isEmpty,
              unique(plan.bindings.map(\.id)), unique(plan.bindings.map { "\($0.sourceNamespace)\u{1f}\($0.externalSessionID)" }),
              unique(plan.turns.map(\.id)), unique(plan.turns.map(\.source)),
              unique(plan.messages.map(\.id)), unique(plan.messages.compactMap(\.source)) else { return false }
        let roomID = plan.rooms[0].id
        let bindings = Dictionary(uniqueKeysWithValues: plan.bindings.map { ($0.id, $0) })
        let turns = Dictionary(uniqueKeysWithValues: plan.turns.map { ($0.id, $0) })
        let messages = Dictionary(uniqueKeysWithValues: plan.messages.map { ($0.id, $0) })
        for binding in plan.bindings {
            guard binding.roomID == roomID else { return false }
            if let parent = binding.parentBindingID, bindings[parent]?.roomID != roomID { return false }
            if containsCycle(start: binding.id, next: { bindings[$0]?.parentBindingID }) { return false }
        }
        for turn in plan.turns {
            guard turn.roomID == roomID else { return false }
            if let binding = turn.runtimeBindingID, bindings[binding]?.roomID != roomID { return false }
        }
        for message in plan.messages {
            guard message.roomID == roomID, message.role == "user" || message.role == "assistant",
                  message.metadata["attachmentCount"] == "0" else { return false }
            if let binding = message.runtimeBindingID, bindings[binding]?.roomID != roomID { return false }
            if let turn = message.turnID, turns[turn]?.roomID != roomID { return false }
            if let parent = message.parentMessageID, messages[parent]?.roomID != roomID { return false }
            if containsCycle(start: message.id, next: { messages[$0]?.parentMessageID }) { return false }
        }
        return true
    }

    private func applyCanonicalParity(to plan: inout LegacyConversationImportPlan) throws -> Bool {
        let plannedRoom = plan.rooms[0]
        let byID = try parityReader.room(id: plannedRoom.id)
        let byStable = try parityReader.room(stableKey: plannedRoom.stableKey)
        if let byID, let byStable, byID.id != byStable.id { return false }
        if let existing = byID ?? byStable {
            guard existing.id == plannedRoom.id && existing.stableKey == plannedRoom.stableKey &&
                    existing.title == plannedRoom.title && existing.kind == plannedRoom.kind &&
                    existing.lifecycleState == plannedRoom.lifecycleState && existing.metadata == plannedRoom.metadata &&
                    existing.nextTurnSequence == plannedRoom.nextTurnSequence &&
                    existing.nextMessageSequence == plannedRoom.nextMessageSequence &&
                    existing.createdAt == plannedRoom.createdAt && existing.updatedAt == plannedRoom.updatedAt &&
                    existing.archivedAt == plannedRoom.archivedAt else { return false }
            plan.rooms[0].disposition = .equivalent
        }
        let existingBindings = try parityReader.bindings(roomID: plannedRoom.id)
        for index in plan.bindings.indices {
            let planned = plan.bindings[index]
            guard let existing = existingBindings.first(where: { $0.id == planned.id }) ?? existingBindings.first(where: {
                $0.sourceNamespace == planned.sourceNamespace && $0.externalSessionID == planned.externalSessionID
            }) else { continue }
            guard existing.id == planned.id && existing.roomID == planned.roomID &&
                    existing.parentBindingID == planned.parentBindingID && existing.runtimeID == planned.runtimeID &&
                    existing.transportID == planned.transportID && existing.sourceNamespace == planned.sourceNamespace &&
                    existing.externalSessionID == planned.externalSessionID && existing.state == planned.state &&
                    existing.cursorMessageID == planned.cursorMessageID && existing.cursorTimestamp == planned.cursorTimestamp &&
                    existing.metadata == planned.metadata && existing.createdAt == planned.createdAt &&
                    existing.updatedAt == planned.updatedAt else { return false }
            plan.bindings[index].disposition = .equivalent
        }
        for index in plan.turns.indices {
            let planned = plan.turns[index]
            guard let existing = try parityReader.turn(id: planned.id) else { continue }
            guard existing.roomID == planned.roomID && existing.sequence == planned.sequence &&
                    existing.runtimeBindingID == planned.runtimeBindingID && existing.source == planned.source &&
                    existing.status == planned.status && existing.metadata == planned.metadata &&
                    existing.createdAt == planned.createdAt && existing.startedAt == planned.startedAt &&
                    existing.completedAt == planned.completedAt && existing.updatedAt == planned.updatedAt else { return false }
            plan.turns[index].disposition = .equivalent
        }
        let existingMessages = try parityReader.messages(roomID: plannedRoom.id)
        for index in plan.messages.indices {
            let planned = plan.messages[index]
            guard let existing = existingMessages.first(where: { $0.id == planned.id }) ??
                    existingMessages.first(where: { $0.source == planned.source && planned.source != nil }) else { continue }
            guard existing.id == planned.id && existing.roomID == planned.roomID && existing.turnID == planned.turnID &&
                    existing.runtimeBindingID == planned.runtimeBindingID && existing.parentMessageID == planned.parentMessageID &&
                    existing.sequence == planned.sequence && existing.role == planned.role && existing.contentText == planned.contentText &&
                    existing.status == planned.status && existing.finishReason == planned.finishReason && existing.source == planned.source &&
                    existing.sourceCreatedAt == planned.sourceCreatedAt && existing.metadata == planned.metadata &&
                    existing.createdAt == planned.createdAt && existing.updatedAt == planned.updatedAt else { return false }
            plan.messages[index].disposition = .equivalent
        }
        return true
    }

    private func omitCandidatesCollidingWithOrphans(
        _ candidates: inout [Candidate],
        conversations: [DecodedConversation],
        orphanIndices: [Int]
    ) {
        let orphanMessages = orphanIndices.flatMap { conversations[$0].messages.map(\.message) }
        let orphanIDs = Set(orphanMessages.map(\.id))
        let orphanSources = Set(orphanMessages.compactMap { sourceMapper.map($0.sourceID, role: $0.role.rawValue).source })
        for index in candidates.indices where candidates[index].valid {
            if candidates[index].plan.messages.contains(where: { orphanIDs.contains($0.id) || ($0.source.map(orphanSources.contains) ?? false) }) {
                candidates[index].valid = false
            }
        }
    }

    private func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }

    private func containsCycle<T: Hashable>(start: T, next: (T) -> T?) -> Bool {
        var seen = Set<T>()
        var cursor: T? = start
        while let value = cursor {
            guard seen.insert(value).inserted else { return true }
            cursor = next(value)
        }
        return false
    }

    private func messageAscending(_ lhs: LegacyConversationMessagePlanRecord, _ rhs: LegacyConversationMessagePlanRecord) -> Bool {
        lhs.sequence == rhs.sequence ? lhs.id.uuidString < rhs.id.uuidString : lhs.sequence < rhs.sequence
    }

    private func messageDescending(_ lhs: LegacyConversationMessagePlanRecord, _ rhs: LegacyConversationMessagePlanRecord) -> Bool {
        lhs.sequence == rhs.sequence ? lhs.id.uuidString > rhs.id.uuidString : lhs.sequence > rhs.sequence
    }
}

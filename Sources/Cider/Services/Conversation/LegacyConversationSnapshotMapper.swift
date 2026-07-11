import CryptoKit
import Foundation

struct LegacyConversationSourceIdentityMapper {
    struct Mapping: Equatable {
        var source: ConversationSourceIdentity?
        var runID: String?
        var malformedRecognizedStyle: Bool = false
    }

    func map(_ rawValue: String?, role: String) -> Mapping {
        guard let rawValue, !rawValue.isEmpty else { return .init(source: nil, runID: nil) }
        if rawValue.hasPrefix("hermes-live:") {
            let remainder = String(rawValue.dropFirst("hermes-live:".count))
            guard !remainder.isEmpty else { return legacy(rawValue, malformed: true) }
            return .init(source: .init(namespace: "hermes.live.v1", id: remainder), runID: nil)
        }
        if rawValue.hasPrefix("hermes-run:") {
            let remainder = String(rawValue.dropFirst("hermes-run:".count))
            let expectedSuffix = ":\(role)"
            guard remainder.hasSuffix(expectedSuffix) else { return legacy(rawValue, malformed: true) }
            let runID = String(remainder.dropLast(expectedSuffix.count))
            guard !runID.isEmpty else { return legacy(rawValue, malformed: true) }
            return .init(source: .init(namespace: "hermes.runs.v1", id: remainder), runID: runID)
        }
        if rawValue.hasPrefix("hermes:") {
            let remainder = String(rawValue.dropFirst("hermes:".count))
            guard !remainder.isEmpty else { return legacy(rawValue, malformed: true) }
            return .init(source: .init(namespace: "hermes.export.v1", id: remainder), runID: nil)
        }
        return legacy(rawValue, malformed: false)
    }

    private func legacy(_ rawValue: String, malformed: Bool) -> Mapping {
        .init(
            source: .init(namespace: "legacy.message-source.v1", id: rawValue),
            runID: nil,
            malformedRecognizedStyle: malformed
        )
    }
}

/// Pure CID-772 legacy-to-v30 mapping shared by read-only preview and dormant shadow writes.
struct LegacyConversationSnapshotMapper {
    struct PhysicalMessage: Equatable, Sendable {
        let physicalLine: Int
        let message: LegacyConversationMessageSnapshot
    }

    private let sourceMapper = LegacyConversationSourceIdentityMapper()

    func map(
        record: CiderAgentChatRecord,
        metadata: LegacyConversationMetadataSnapshot?,
        messages: [PhysicalMessage]
    ) -> LegacyConversationImportPlan {
        let bindingResult = bindings(record: record)
        var runTurns: [String: LegacyConversationTurnPlanRecord] = [:]
        var messageRecords: [LegacyConversationMessagePlanRecord] = []

        for (index, physical) in messages.enumerated() {
            let message = physical.message
            let mapped = sourceMapper.map(message.sourceID, role: message.role.rawValue)
            var turnID: UUID?
            if let runID = mapped.runID {
                if runTurns[runID] == nil {
                    let id = deterministicUUID(
                        seed: "turn|\(record.conversationID.uuidString.lowercased())|hermes.runs.v1|\(runID)"
                    )
                    runTurns[runID] = .init(
                        id: id,
                        roomID: record.conversationID,
                        sequence: Int64(runTurns.count + 1),
                        runtimeBindingID: bindingResult.bySession[message.sourceSessionID ?? ""],
                        source: .init(namespace: "hermes.runs.v1", id: runID),
                        status: .unknown,
                        metadata: ["historicalOutcome": "unknown", "provenance": "legacy-hermes-run-source"],
                        createdAt: message.timestamp,
                        startedAt: nil,
                        completedAt: message.timestamp,
                        updatedAt: message.timestamp,
                        disposition: .plannedInsert
                    )
                }
                turnID = runTurns[runID]?.id
            }

            let parentID = index == 0 ? nil : messages[index - 1].message.id
            var messageMetadata: [String: String] = [
                "legacyPhysicalLine": String(physical.physicalLine),
                "legacyPhysicalIndex": String(index),
                "attachmentCount": String(message.attachments.count),
            ]
            if parentID != nil { messageMetadata["parentProvenance"] = "legacy-linear" }
            if let value = message.sourceID { messageMetadata["legacySourceID"] = value }
            if let value = message.sourceSessionID { messageMetadata["legacySourceSessionID"] = value }
            if let value = message.sourceName { messageMetadata["legacySourceName"] = value }
            messageRecords.append(.init(
                id: message.id,
                roomID: record.conversationID,
                turnID: turnID,
                runtimeBindingID: bindingResult.bySession[message.sourceSessionID ?? ""],
                parentMessageID: parentID,
                sequence: Int64(index + 1),
                role: message.role.rawValue,
                contentText: message.content,
                status: .complete,
                finishReason: nil,
                source: mapped.source,
                sourceCreatedAt: message.timestamp,
                metadata: messageMetadata,
                createdAt: message.timestamp,
                updatedAt: message.timestamp,
                disposition: .plannedInsert
            ))
        }

        let turns = runTurns.values.sorted { $0.sequence < $1.sequence }
        let room = LegacyConversationRoomPlanRecord(
            id: record.conversationID,
            stableKey: record.stableID,
            title: record.title,
            kind: record.kind,
            lifecycleState: record.archived ? .archived : .active,
            nextTurnSequence: Int64(turns.count + 1),
            nextMessageSequence: Int64(messageRecords.count + 1),
            metadata: roomMetadata(record: record, conversation: metadata),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            archivedAt: record.archived ? record.updatedAt : nil,
            disposition: .plannedInsert
        )
        return .init(rooms: [room], bindings: bindingResult.records, turns: turns, messages: messageRecords)
    }

    private func bindings(
        record: CiderAgentChatRecord
    ) -> (records: [LegacyConversationBindingPlanRecord], bySession: [String: UUID]) {
        var sessions = record.runtimeSessionLineage
        if !record.activeRuntimeSessionID.isEmpty, !sessions.contains(record.activeRuntimeSessionID) {
            sessions.append(record.activeRuntimeSessionID)
        }
        sessions = sessions.filter { !$0.isEmpty }
        var records: [LegacyConversationBindingPlanRecord] = []
        var bySession: [String: UUID] = [:]
        for (index, session) in sessions.enumerated() {
            let id = deterministicUUID(
                seed: "binding|\(record.conversationID.uuidString.lowercased())|\(record.runtimeID)|\(session)"
            )
            bySession[session] = id
            records.append(.init(
                id: id,
                roomID: record.conversationID,
                parentBindingID: index == 0 ? nil : records[index - 1].id,
                runtimeID: record.runtimeID,
                transportID: "legacy",
                sourceNamespace: "legacy.runtime-binding.v1.\(normalized(record.runtimeID))",
                externalSessionID: session,
                state: session == record.activeRuntimeSessionID ? .active : .inactive,
                cursorMessageID: session == record.activeRuntimeSessionID ? record.lastSyncedMessageID : nil,
                cursorTimestamp: session == record.activeRuntimeSessionID ? record.lastSyncedTimestamp : nil,
                metadata: [
                    "lineageIndex": String(index),
                    "lineageProvenance": "legacy-registry",
                    "lastImported": String(session == record.lastImportedRuntimeSessionID),
                ],
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                disposition: .plannedInsert
            ))
        }
        return (records, bySession)
    }

    private func roomMetadata(
        record: CiderAgentChatRecord,
        conversation: LegacyConversationMetadataSnapshot?
    ) -> [String: String] {
        var metadata: [String: String] = [
            "legacyStableID": record.stableID,
            "legacyHermesTitle": record.hermesTitle ?? "",
            "legacyScope": record.scope ?? "",
            "legacyDefaultInCider": String(record.defaultInCider),
            "legacyRuntimeID": record.runtimeID,
            "legacyActiveRuntimeSessionID": record.activeRuntimeSessionID,
            "legacyRuntimeSessionLineage": record.runtimeSessionLineage.joined(separator: "\u{1f}"),
            "legacyLastSyncedMessageID": record.lastSyncedMessageID ?? "",
            "legacyLastSyncedTimestamp": iso8601(record.lastSyncedTimestamp),
            "legacyLastImportedRuntimeSessionID": record.lastImportedRuntimeSessionID ?? "",
        ]
        if let conversation {
            metadata["legacyJSONLModel"] = conversation.model
            metadata["legacyJSONLCreatedAt"] = iso8601(conversation.created)
            metadata["legacyJSONLUpdatedAt"] = iso8601(conversation.updated)
            metadata["legacyJSONLRuntimeSource"] = conversation.runtimeSource ?? ""
            metadata["legacyJSONLLastSyncedAt"] = iso8601(conversation.runtimeLastSyncedAt)
            metadata["legacyJSONLRuntimeID"] = conversation.runtimeID ?? ""
            metadata["legacyJSONLActiveRuntimeSessionID"] = conversation.activeRuntimeSessionID ?? ""
            metadata["legacyJSONLRuntimeSessionLineage"] = (conversation.runtimeSessionLineage ?? []).joined(separator: "\u{1f}")
            metadata["legacyJSONLLastSyncedMessageID"] = conversation.runtimeLastSyncedMessageID ?? ""
            metadata["legacyJSONLLastSyncedTimestamp"] = iso8601(conversation.runtimeLastSyncedTimestamp)
            metadata["legacyJSONLLastImportedRuntimeSessionID"] = conversation.runtimeLastImportedSessionID ?? ""
        }
        return metadata
    }

    private func deterministicUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("cider.legacy-conversation-import-id.v1|\(seed)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))")!
    }

    private func normalized(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(scalars).split(separator: "-").joined(separator: "-")
    }

    private func iso8601(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter().string(from: date)
    }
}

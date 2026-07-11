import CryptoKit
import Foundation

@MainActor
protocol ConversationCoreParityReading {
    func room(id: UUID) throws -> ConversationRoom?
    func room(stableKey: String) throws -> ConversationRoom?
    func bindings(roomID: UUID) throws -> [ConversationRuntimeBinding]
    func turn(id: UUID) throws -> ConversationTurn?
    func messages(roomID: UUID) throws -> [ConversationMessage]
}

@MainActor
struct ConversationRepositoryParityReader: ConversationCoreParityReading {
    let repository: ConversationRepository

    func room(id: UUID) throws -> ConversationRoom? { try repository.room(id: id) }
    func room(stableKey: String) throws -> ConversationRoom? { try repository.room(stableKey: stableKey) }
    func bindings(roomID: UUID) throws -> [ConversationRuntimeBinding] { try repository.bindings(roomID: roomID) }
    func turn(id: UUID) throws -> ConversationTurn? { try repository.turn(id: id) }
    func messages(roomID: UUID) throws -> [ConversationMessage] { try repository.messages(roomID: roomID) }
}

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
            return .init(
                source: .init(namespace: "hermes.live.v1", id: remainder),
                runID: nil
            )
        }
        if rawValue.hasPrefix("hermes-run:") {
            let remainder = String(rawValue.dropFirst("hermes-run:".count))
            let expectedSuffix = ":\(role)"
            guard remainder.hasSuffix(expectedSuffix) else { return legacy(rawValue, malformed: true) }
            let runID = String(remainder.dropLast(expectedSuffix.count))
            guard !runID.isEmpty else { return legacy(rawValue, malformed: true) }
            return .init(
                source: .init(namespace: "hermes.runs.v1", id: remainder),
                runID: runID
            )
        }
        if rawValue.hasPrefix("hermes:") {
            let remainder = String(rawValue.dropFirst("hermes:".count))
            guard !remainder.isEmpty else { return legacy(rawValue, malformed: true) }
            return .init(
                source: .init(namespace: "hermes.export.v1", id: remainder),
                runID: nil
            )
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

@MainActor
final class LegacyConversationImportPreviewService {
    struct Limits: Equatable {
        var maximumFiles = 1_000
        var maximumMessageLines = 100_000
        var maximumDiagnosticSamples = 50
    }

    private struct RegistryInput {
        var record: CiderAgentChatRecord
        var location: String
    }

    private struct ConversationInput {
        var metadata: AIConversationMeta
        var messages: [(line: Int, message: AIAssistantMessage)]
        var physicalMessageLineCount: Int
        var location: String
    }

    private let registryDirectory: URL
    private let conversationDirectory: URL
    private let parityReader: any ConversationCoreParityReading
    private let limits: Limits
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let sourceMapper = LegacyConversationSourceIdentityMapper()

    init(
        registryDirectory: URL,
        conversationDirectory: URL,
        parityReader: any ConversationCoreParityReading,
        limits: Limits = .init(),
        fileManager: FileManager = .default
    ) {
        self.registryDirectory = registryDirectory
        self.conversationDirectory = conversationDirectory
        self.parityReader = parityReader
        self.limits = limits
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func preview() throws -> LegacyConversationImportPreview {
        var diagnostics: [ConversationParityDiagnostic] = []
        var inputs: [LegacyConversationImportInput] = []
        let registryURLs = try inputURLs(in: registryDirectory, extension: "json")
        let conversationURLs = try inputURLs(in: conversationDirectory, extension: "jsonl")
        let fileCount = registryURLs.count + conversationURLs.count
        guard fileCount <= limits.maximumFiles else {
            add(.inputLimitExceeded, "inputs", "Found \(fileCount) files; limit is \(limits.maximumFiles).", to: &diagnostics)
            return makePreview(inputs: [], plan: .init(), diagnostics: diagnostics, registryFiles: registryURLs.count, conversationFiles: conversationURLs.count)
        }

        let registries = decodeRegistries(registryURLs, inputs: &inputs, diagnostics: &diagnostics)
        let conversations = decodeConversations(conversationURLs, inputs: &inputs, diagnostics: &diagnostics)
        validateIdentities(registries: registries, conversations: conversations, diagnostics: &diagnostics)
        validateMessageInputs(conversations, diagnostics: &diagnostics)
        var plan = buildPlan(registries: registries, conversations: conversations, diagnostics: &diagnostics)
        try compareWithCore(plan: &plan, diagnostics: &diagnostics)
        return makePreview(
            inputs: inputs.sorted { $0.path < $1.path },
            plan: plan,
            diagnostics: diagnostics,
            registryFiles: registryURLs.count,
            conversationFiles: conversationURLs.count,
            inputRooms: registries.count,
            inputMessages: conversations.reduce(0) { $0 + $1.messages.count },
            physicalMessageRows: conversations.reduce(0) { $0 + $1.physicalMessageLineCount },
            attachmentBearingMessages: conversations.reduce(0) { count, conversation in
                count + conversation.messages.filter { !$0.message.attachments.isEmpty }.count
            }
        )
    }

    private func inputURLs(in directory: URL, extension pathExtension: String) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [directory] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        .filter { $0.pathExtension == pathExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func decodeRegistries(
        _ urls: [URL],
        inputs: inout [LegacyConversationImportInput],
        diagnostics: inout [ConversationParityDiagnostic]
    ) -> [RegistryInput] {
        var values: [RegistryInput] = []
        for url in urls {
            let location = "registry/\(url.lastPathComponent)"
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                inputs.append(input(data, path: location))
                let record = try decoder.decode(CiderAgentChatRecord.self, from: data)
                values.append(.init(record: record, location: location))
            } catch {
                add(.malformedRegistryRecord, location, String(describing: error), to: &diagnostics)
            }
        }
        return values
    }

    private func decodeConversations(
        _ urls: [URL],
        inputs: inout [LegacyConversationImportInput],
        diagnostics: inout [ConversationParityDiagnostic]
    ) -> [ConversationInput] {
        var values: [ConversationInput] = []
        var totalMessageLines = 0
        for url in urls {
            let location = "conversation/\(url.lastPathComponent)"
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                inputs.append(input(data, path: location))
                guard let text = String(data: data, encoding: .utf8) else {
                    add(.unreadableInput, location, "Input is not valid UTF-8.", to: &diagnostics)
                    continue
                }
                var lines = text.components(separatedBy: .newlines)
                while lines.last == "" { lines.removeLast() }
                guard let metadataLine = lines.first, !metadataLine.isEmpty else {
                    add(.malformedMetadataLine, "\(location):1", "Missing metadata line.", to: &diagnostics)
                    continue
                }
                let metadata: AIConversationMeta
                do {
                    metadata = try decoder.decode(AIConversationMeta.self, from: Data(metadataLine.utf8))
                } catch {
                    add(.malformedMetadataLine, "\(location):1", String(describing: error), to: &diagnostics)
                    continue
                }
                if metadata.type != "metadata" {
                    add(.invalidMetadataType, "\(location):1", "Expected metadata type, found \(metadata.type).", to: &diagnostics)
                }
                let physicalCount = max(0, lines.count - 1)
                totalMessageLines += physicalCount
                guard totalMessageLines <= limits.maximumMessageLines else {
                    add(.inputLimitExceeded, location, "Message line limit \(limits.maximumMessageLines) exceeded.", to: &diagnostics)
                    break
                }
                var messages: [(Int, AIAssistantMessage)] = []
                for (offset, line) in lines.dropFirst().enumerated() {
                    let lineNumber = offset + 2
                    guard !line.isEmpty else {
                        add(.malformedMessageLine, "\(location):\(lineNumber)", "Blank message line.", to: &diagnostics)
                        continue
                    }
                    do {
                        messages.append((lineNumber, try decoder.decode(AIAssistantMessage.self, from: Data(line.utf8))))
                    } catch {
                        add(.malformedMessageLine, "\(location):\(lineNumber)", String(describing: error), to: &diagnostics)
                    }
                }
                if metadata.messageCount != messages.count {
                    add(
                        .messageCountMismatch,
                        location,
                        "Metadata declares \(metadata.messageCount) messages; \(messages.count) decoded from \(physicalCount) physical rows.",
                        to: &diagnostics
                    )
                }
                values.append(.init(
                    metadata: metadata,
                    messages: messages,
                    physicalMessageLineCount: physicalCount,
                    location: location
                ))
            } catch {
                add(.unreadableInput, location, String(describing: error), to: &diagnostics)
            }
        }
        return values
    }

    private func validateIdentities(
        registries: [RegistryInput],
        conversations: [ConversationInput],
        diagnostics: inout [ConversationParityDiagnostic]
    ) {
        reportDuplicates(registries, key: { $0.record.conversationID.uuidString }, code: .duplicateRoomID, diagnostics: &diagnostics)
        reportDuplicates(registries, key: { $0.record.stableID }, code: .duplicateStableID, diagnostics: &diagnostics)
        reportDuplicates(conversations, key: { $0.metadata.id.uuidString }, code: .duplicateConversationFile, diagnostics: &diagnostics)

        let registryIDs = Set(registries.map { $0.record.conversationID })
        let conversationIDs = Set(conversations.map { $0.metadata.id })
        for registry in registries where !conversationIDs.contains(registry.record.conversationID) {
            add(.missingConversationFile, registry.location, "No JSONL metadata references room \(registry.record.conversationID).", to: &diagnostics)
        }
        for conversation in conversations where !registryIDs.contains(conversation.metadata.id) {
            add(.missingRegistryRecord, conversation.location, "No registry record references room \(conversation.metadata.id).", to: &diagnostics)
        }
    }

    private func reportDuplicates<T>(
        _ values: [T],
        key: (T) -> String,
        code: ConversationParityDiagnosticCode,
        diagnostics: inout [ConversationParityDiagnostic]
    ) {
        let groups = Dictionary(grouping: values, by: key)
        for duplicate in groups.keys.sorted() where (groups[duplicate]?.count ?? 0) > 1 {
            add(code, duplicate, "Identity occurs \(groups[duplicate]?.count ?? 0) times.", to: &diagnostics)
        }
    }

    private func validateMessageInputs(
        _ conversations: [ConversationInput],
        diagnostics: inout [ConversationParityDiagnostic]
    ) {
        var globalMessageIDs: [UUID: String] = [:]
        var globalSources: [ConversationSourceIdentity: (UUID, String, String)] = [:]
        for conversation in conversations {
            for row in conversation.messages {
                let message = row.message
                let location = "\(conversation.location):\(row.line)"
                if let prior = globalMessageIDs[message.id] {
                    add(.duplicateMessageID, location, "Message UUID already appeared at \(prior).", to: &diagnostics)
                } else {
                    globalMessageIDs[message.id] = location
                }
                let mapped = sourceMapper.map(message.sourceID, role: message.role.rawValue)
                if mapped.malformedRecognizedStyle {
                    add(.invalidSourceIdentity, location, "Recognized Hermes source style is incomplete or disagrees with the message role.", to: &diagnostics)
                }
                if let source = mapped.source {
                    if let prior = globalSources[source], prior.0 != message.id || prior.1 != message.role.rawValue || prior.2 != message.content {
                        add(.conflictingSourceIdentity, location, "Source \(source.namespace)/\(source.id) conflicts with message \(prior.0).", to: &diagnostics)
                    } else {
                        globalSources[source] = (message.id, message.role.rawValue, message.content)
                    }
                }
                if !message.attachments.isEmpty {
                    add(.attachmentsUnsupported, location, "Message has \(message.attachments.count) attachment(s); v30 cannot represent them.", to: &diagnostics)
                }
            }
        }
    }

    private func buildPlan(
        registries: [RegistryInput],
        conversations: [ConversationInput],
        diagnostics: inout [ConversationParityDiagnostic]
    ) -> LegacyConversationImportPlan {
        var plan = LegacyConversationImportPlan()
        let conversationsByID = Dictionary(grouping: conversations, by: { $0.metadata.id })

        for registry in registries.sorted(by: registrySort) {
            let record = registry.record
            let matching = conversationsByID[record.conversationID] ?? []
            let conversation = matching.count == 1 ? matching[0] : nil
            if let conversation { validate(record, against: conversation.metadata, location: conversation.location, diagnostics: &diagnostics) }
            let roomMetadata = roomMetadata(record: record, conversation: conversation?.metadata)
            plan.rooms.append(.init(
                id: record.conversationID,
                stableKey: record.stableID,
                title: record.title,
                kind: record.kind,
                lifecycleState: record.archived ? .archived : .active,
                nextTurnSequence: 1,
                nextMessageSequence: 1,
                metadata: roomMetadata,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                archivedAt: record.archived ? record.updatedAt : nil,
                disposition: .plannedInsert
            ))

            let bindingResult = buildBindings(record: record, diagnostics: &diagnostics)
            plan.bindings.append(contentsOf: bindingResult.records)
            guard let conversation else { continue }

            var runTurns: [String: LegacyConversationTurnPlanRecord] = [:]
            for (index, row) in conversation.messages.enumerated() {
                let message = row.message
                let location = "\(conversation.location):\(row.line)"
                let mapped = sourceMapper.map(message.sourceID, role: message.role.rawValue)
                if let sessionID = message.sourceSessionID,
                   !sessionID.isEmpty,
                   bindingResult.bySession[sessionID] == nil {
                    add(.missingGraphReference, location, "Source session \(sessionID) has no registry runtime binding.", to: &diagnostics)
                }

                var turnID: UUID?
                if let runID = mapped.runID {
                    if runTurns[runID] == nil {
                        let id = deterministicUUID(seed: "turn|\(record.conversationID.uuidString.lowercased())|hermes.runs.v1|\(runID)")
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
                let parentID = index == 0 ? nil : conversation.messages[index - 1].message.id
                if parentID == message.id {
                    add(.graphCycle, location, "Synthetic predecessor would make the message parent itself.", to: &diagnostics)
                }
                var metadata: [String: String] = [
                    "legacyPhysicalLine": String(row.line),
                    "legacyPhysicalIndex": String(index),
                    "attachmentCount": String(message.attachments.count),
                ]
                if parentID != nil { metadata["parentProvenance"] = "legacy-linear" }
                if let value = message.sourceID { metadata["legacySourceID"] = value }
                if let value = message.sourceSessionID { metadata["legacySourceSessionID"] = value }
                if let value = message.sourceName { metadata["legacySourceName"] = value }
                plan.messages.append(.init(
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
                    metadata: metadata,
                    createdAt: message.timestamp,
                    updatedAt: message.timestamp,
                    disposition: .plannedInsert
                ))
            }
            plan.turns.append(contentsOf: runTurns.values.sorted { $0.sequence < $1.sequence })
            validateGraph(roomID: record.conversationID, messages: plan.messages.filter { $0.roomID == record.conversationID }, diagnostics: &diagnostics)
        }
        for index in plan.rooms.indices {
            let roomID = plan.rooms[index].id
            plan.rooms[index].nextTurnSequence = Int64(plan.turns.filter { $0.roomID == roomID }.count + 1)
            plan.rooms[index].nextMessageSequence = Int64(plan.messages.filter { $0.roomID == roomID }.count + 1)
        }
        return plan
    }

    private func buildBindings(
        record: CiderAgentChatRecord,
        diagnostics: inout [ConversationParityDiagnostic]
    ) -> (records: [LegacyConversationBindingPlanRecord], bySession: [String: UUID]) {
        var sessions = record.runtimeSessionLineage
        if !record.activeRuntimeSessionID.isEmpty, !sessions.contains(record.activeRuntimeSessionID) {
            sessions.append(record.activeRuntimeSessionID)
        }
        var seen = Set<String>()
        for session in sessions where session.isEmpty || !seen.insert(session).inserted {
            add(.duplicateRuntimeSessionID, record.stableID, "Runtime lineage contains an empty or duplicate session identity.", to: &diagnostics)
        }
        sessions = sessions.filter { !$0.isEmpty }
        var records: [LegacyConversationBindingPlanRecord] = []
        var bySession: [String: UUID] = [:]
        for (index, session) in sessions.enumerated() {
            let id = deterministicUUID(seed: "binding|\(record.conversationID.uuidString.lowercased())|\(record.runtimeID)|\(session)")
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

    private func validate(
        _ record: CiderAgentChatRecord,
        against metadata: AIConversationMeta,
        location: String,
        diagnostics: inout [ConversationParityDiagnostic]
    ) {
        var mismatches: [String] = []
        if record.conversationID != metadata.id { mismatches.append("conversationID") }
        if record.title != metadata.title { mismatches.append("title") }
        if record.runtimeID != (metadata.runtimeID ?? "") { mismatches.append("runtimeID") }
        if record.activeRuntimeSessionID != (metadata.activeRuntimeSessionID ?? "") { mismatches.append("activeRuntimeSessionID") }
        if record.runtimeSessionLineage != (metadata.runtimeSessionLineage ?? []) { mismatches.append("runtimeSessionLineage") }
        if record.lastSyncedMessageID != metadata.runtimeLastSyncedMessageID { mismatches.append("lastSyncedMessageID") }
        if record.lastSyncedTimestamp != metadata.runtimeLastSyncedTimestamp { mismatches.append("lastSyncedTimestamp") }
        if record.lastImportedRuntimeSessionID != metadata.runtimeLastImportedSessionID { mismatches.append("lastImportedRuntimeSessionID") }
        if !mismatches.isEmpty {
            add(.registryMetadataMismatch, location, "Registry and JSONL disagree on: \(mismatches.joined(separator: ", ")).", to: &diagnostics)
        }
    }

    private func validateGraph(
        roomID: UUID,
        messages: [LegacyConversationMessagePlanRecord],
        diagnostics: inout [ConversationParityDiagnostic]
    ) {
        let ids = Set(messages.map(\.id))
        var parents: [UUID: UUID] = [:]
        for message in messages where parents[message.id] == nil {
            if let parent = message.parentMessageID { parents[message.id] = parent }
        }
        for message in messages {
            if let parent = message.parentMessageID, !ids.contains(parent) {
                add(.missingGraphReference, message.id.uuidString, "Parent \(parent) is absent from room \(roomID).", to: &diagnostics)
            }
            var cursor: UUID? = message.id
            var visited = Set<UUID>()
            while let id = cursor {
                guard visited.insert(id).inserted else {
                    add(.graphCycle, message.id.uuidString, "Message ancestry contains a cycle.", to: &diagnostics)
                    break
                }
                cursor = parents[id]
            }
        }
    }

    private func compareWithCore(
        plan: inout LegacyConversationImportPlan,
        diagnostics: inout [ConversationParityDiagnostic]
    ) throws {
        for index in plan.rooms.indices {
            let planned = plan.rooms[index]
            let byID = try parityReader.room(id: planned.id)
            let byStable = try parityReader.room(stableKey: planned.stableKey)
            if let byID, let byStable, byID.id != byStable.id {
                plan.rooms[index].disposition = .conflict
                parityConflict("room-identity", id: planned.id.uuidString, diagnostics: &diagnostics)
                continue
            }
            guard let existing = byID ?? byStable else { continue }
            let equivalent = existing.id == planned.id && existing.stableKey == planned.stableKey &&
                existing.title == planned.title && existing.kind == planned.kind &&
                existing.lifecycleState == planned.lifecycleState && existing.metadata == planned.metadata &&
                existing.nextTurnSequence == planned.nextTurnSequence &&
                existing.nextMessageSequence == planned.nextMessageSequence &&
                existing.createdAt == planned.createdAt && existing.archivedAt == planned.archivedAt
            plan.rooms[index].disposition = equivalent ? .equivalent : .conflict
            if !equivalent { parityConflict("room", id: planned.id.uuidString, diagnostics: &diagnostics) }
        }

        for room in plan.rooms {
            let existingBindings = try parityReader.bindings(roomID: room.id)
            let bindingsByID = Dictionary(uniqueKeysWithValues: existingBindings.map { ($0.id, $0) })
            for index in plan.bindings.indices where plan.bindings[index].roomID == room.id {
                let planned = plan.bindings[index]
                guard let existing = bindingsByID[planned.id] ?? existingBindings.first(where: {
                    $0.sourceNamespace == planned.sourceNamespace && $0.externalSessionID == planned.externalSessionID
                }) else { continue }
                let equivalent = existing.id == planned.id && existing.roomID == planned.roomID &&
                    existing.parentBindingID == planned.parentBindingID && existing.runtimeID == planned.runtimeID &&
                    existing.transportID == planned.transportID && existing.sourceNamespace == planned.sourceNamespace &&
                    existing.externalSessionID == planned.externalSessionID && existing.state == planned.state &&
                    existing.cursorMessageID == planned.cursorMessageID && existing.cursorTimestamp == planned.cursorTimestamp &&
                    existing.metadata == planned.metadata && existing.createdAt == planned.createdAt
                plan.bindings[index].disposition = equivalent ? .equivalent : .conflict
                if !equivalent { parityConflict("binding", id: planned.id.uuidString, diagnostics: &diagnostics) }
            }

            for index in plan.turns.indices where plan.turns[index].roomID == room.id {
                let planned = plan.turns[index]
                guard let existing = try parityReader.turn(id: planned.id) else { continue }
                let equivalent = existing.roomID == planned.roomID && existing.sequence == planned.sequence &&
                    existing.runtimeBindingID == planned.runtimeBindingID && existing.source == planned.source &&
                    existing.status == planned.status && existing.metadata == planned.metadata &&
                    existing.createdAt == planned.createdAt && existing.startedAt == planned.startedAt &&
                    existing.completedAt == planned.completedAt && existing.updatedAt == planned.updatedAt
                plan.turns[index].disposition = equivalent ? .equivalent : .conflict
                if !equivalent { parityConflict("turn", id: planned.id.uuidString, diagnostics: &diagnostics) }
            }

            let existingMessages = try parityReader.messages(roomID: room.id)
            let messagesByID = Dictionary(uniqueKeysWithValues: existingMessages.map { ($0.id, $0) })
            for index in plan.messages.indices where plan.messages[index].roomID == room.id {
                let planned = plan.messages[index]
                let existing = messagesByID[planned.id] ?? existingMessages.first(where: { $0.source == planned.source && planned.source != nil })
                guard let existing else { continue }
                let equivalent = existing.id == planned.id && existing.roomID == planned.roomID &&
                    existing.turnID == planned.turnID && existing.runtimeBindingID == planned.runtimeBindingID &&
                    existing.parentMessageID == planned.parentMessageID && existing.sequence == planned.sequence &&
                    existing.role == planned.role && existing.contentText == planned.contentText &&
                    existing.status == planned.status && existing.finishReason == planned.finishReason &&
                    existing.source == planned.source &&
                    existing.sourceCreatedAt == planned.sourceCreatedAt && existing.metadata == planned.metadata &&
                    existing.createdAt == planned.createdAt && existing.updatedAt == planned.updatedAt
                plan.messages[index].disposition = equivalent ? .equivalent : .conflict
                if !equivalent { parityConflict("message", id: planned.id.uuidString, diagnostics: &diagnostics) }
            }
        }
    }

    private func parityConflict(
        _ kind: String,
        id: String,
        diagnostics: inout [ConversationParityDiagnostic]
    ) {
        add(.coreParityConflict, "core/\(kind)/\(id)", "Existing conversation-core row is not equivalent to the deterministic plan.", to: &diagnostics)
    }

    private func roomMetadata(record: CiderAgentChatRecord, conversation: AIConversationMeta?) -> [String: String] {
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

    private func makePreview(
        inputs: [LegacyConversationImportInput],
        plan: LegacyConversationImportPlan,
        diagnostics: [ConversationParityDiagnostic],
        registryFiles: Int,
        conversationFiles: Int,
        inputRooms: Int = 0,
        inputMessages: Int = 0,
        physicalMessageRows: Int = 0,
        attachmentBearingMessages: Int = 0
    ) -> LegacyConversationImportPreview {
        let sortedDiagnostics = diagnostics.sorted {
            ($0.code.rawValue, $0.location, $0.detail) < ($1.code.rawValue, $1.location, $1.detail)
        }
        let blockers = sortedDiagnostics.filter { $0.severity == .blocker }.count
        let warnings = sortedDiagnostics.count - blockers
        let dispositions = plan.rooms.map(\.disposition) + plan.bindings.map(\.disposition) +
            plan.turns.map(\.disposition) + plan.messages.map(\.disposition)
        let empty = registryFiles == 0 && conversationFiles == 0
        var counts = LegacyConversationImportCounts(
            registryFiles: registryFiles,
            conversationFiles: conversationFiles,
            inputRooms: inputRooms,
            inputMessages: inputMessages,
            physicalMessageRows: physicalMessageRows,
            attachmentBearingMessages: attachmentBearingMessages,
            plannedRooms: plan.rooms.count,
            plannedBindings: plan.bindings.count,
            plannedTurns: plan.turns.count,
            plannedMessages: plan.messages.count,
            plannedInserts: dispositions.filter { $0 == .plannedInsert }.count,
            equivalents: dispositions.filter { $0 == .equivalent }.count,
            conflicts: dispositions.filter { $0 == .conflict }.count,
            warningDiagnostics: warnings,
            blockingDiagnostics: blockers,
            omittedDiagnosticSamples: max(0, sortedDiagnostics.count - limits.maximumDiagnosticSamples)
        )
        counts.inputRooms = inputRooms
        let diagnosticCounts = Dictionary(grouping: sortedDiagnostics, by: { $0.code.rawValue }).mapValues(\.count)
        return .init(
            state: empty ? .empty : (blockers == 0 ? .ready : .blocked),
            safeForBackfill: !empty && blockers == 0,
            safeForShadowWrites: !empty && blockers == 0,
            inputs: inputs,
            counts: counts,
            diagnosticCounts: diagnosticCounts,
            diagnosticSamples: Array(sortedDiagnostics.prefix(limits.maximumDiagnosticSamples)),
            plan: plan
        )
    }

    private func add(
        _ code: ConversationParityDiagnosticCode,
        _ location: String,
        _ detail: String,
        severity: ConversationParityDiagnosticSeverity = .blocker,
        to diagnostics: inout [ConversationParityDiagnostic]
    ) {
        diagnostics.append(.init(code: code, severity: severity, location: location, detail: detail))
    }

    private func input(_ data: Data, path: String) -> LegacyConversationImportInput {
        .init(path: path, byteCount: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    private func deterministicUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("cider.legacy-conversation-import-id.v1|\(seed)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))")!
    }

    private func registrySort(_ lhs: RegistryInput, _ rhs: RegistryInput) -> Bool {
        (lhs.record.stableID, lhs.record.conversationID.uuidString) < (rhs.record.stableID, rhs.record.conversationID.uuidString)
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

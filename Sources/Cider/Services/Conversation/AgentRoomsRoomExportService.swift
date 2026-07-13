import Foundation

struct AgentRoomsRoomExportFactCollection<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let state: HermesStructuredFactState
    let values: [Value]
}

struct AgentRoomsRoomExportManifest: Codable, Equatable, Sendable {
    struct Room: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let kind: String
        let lifecycleState: ConversationRoomLifecycle
        let createdAt: String
        let updatedAt: String
    }

    struct RuntimeBinding: Codable, Equatable, Sendable {
        let id: UUID
        let parentBindingID: UUID?
        let runtimeID: String
        let transportID: String
        let sourceNamespace: String
        let state: ConversationRuntimeBindingState
        /// Deliberately omitted from portable output. Runtime session IDs are replaceable
        /// bindings, not Cider product identity and may contain provider-private material.
        let externalSessionID: String?
    }

    struct Turn: Codable, Equatable, Sendable {
        let id: UUID
        let sequence: Int64
        let runtimeBindingID: UUID?
        let source: ConversationSourceIdentity?
        let status: ConversationTurnStatus
        let errorCode: String?
        let createdAt: String
        let startedAt: String?
        let completedAt: String?
        let updatedAt: String
        let sources: AgentRoomsRoomExportFactCollection<HermesCiderReference>
        let context: AgentRoomsRoomExportFactCollection<HermesCiderContextCheckpoint>
        let approvals: AgentRoomsRoomExportFactCollection<HermesApprovalRequest>
        let attachments: AgentRoomsRoomExportFactCollection<HermesCiderAttachment>
        let generatedArtifacts: AgentRoomsRoomExportFactCollection<HermesCiderGeneratedArtifact>
    }

    struct Message: Codable, Equatable, Sendable {
        let id: UUID
        let turnID: UUID?
        let runtimeBindingID: UUID?
        let parentMessageID: UUID?
        let sequence: Int64
        let role: String
        let body: String
        let status: ConversationMessageStatus
        let finishReason: ConversationMessageFinishReason?
        let source: ConversationSourceIdentity?
        let sourceCreatedAt: String?
        let createdAt: String
        let updatedAt: String
    }

    let schemaVersion: Int
    let room: Room
    let runtimeBindings: [RuntimeBinding]
    let turns: [Turn]
    let messages: [Message]
}

struct AgentRoomsRoomExportPackage: Equatable, Sendable {
    let markdown: String
    let manifestData: Data
}

struct AgentRoomsRoomExportResult: Equatable, Sendable {
    let packageURL: URL
    let markdownURL: URL
    let manifestURL: URL
}

enum AgentRoomsRoomExportError: Error, Equatable {
    case roomNotFound
    case ineligibleRoom
    case corruptHistory
    case privateContent
    case invalidDestination
    case destinationExists
    case writeFailed
}

@MainActor
protocol AgentRoomsRoomExporting: AnyObject {
    func render(roomID: UUID) throws -> AgentRoomsRoomExportPackage
    func export(roomID: UUID, to destination: URL) throws -> AgentRoomsRoomExportResult
}

/// Provider-neutral, Conversation Core-backed open-data export. It reads only
/// canonical Cider rows and writes only to a caller-supplied new destination.
@MainActor
final class AgentRoomsRoomExportService: AgentRoomsRoomExporting {
    static let markdownFileName = "conversation.md"
    static let manifestFileName = "manifest.json"

    private let repository: ConversationRepository
    private let fileManager: FileManager

    init(repository: ConversationRepository, fileManager: FileManager = .default) {
        self.repository = repository
        self.fileManager = fileManager
    }

    func render(roomID: UUID) throws -> AgentRoomsRoomExportPackage {
        guard let room = try repository.room(id: roomID) else { throw AgentRoomsRoomExportError.roomNotFound }
        try validateAuthority(room)
        let bindings = try repository.bindings(roomID: roomID)
        let turns = try repository.turns(roomID: roomID)
        let messages = try repository.messages(roomID: roomID)
        try validateRows(room: room, bindings: bindings, turns: turns, messages: messages)

        let manifest = AgentRoomsRoomExportManifest(
            schemaVersion: 1,
            room: .init(
                id: room.id,
                title: room.title,
                kind: room.kind,
                lifecycleState: room.lifecycleState,
                createdAt: Self.timestamp(room.createdAt),
                updatedAt: Self.timestamp(room.updatedAt)
            ),
            runtimeBindings: bindings.map {
                .init(
                    id: $0.id,
                    parentBindingID: $0.parentBindingID,
                    runtimeID: $0.runtimeID,
                    transportID: $0.transportID,
                    sourceNamespace: $0.sourceNamespace,
                    state: $0.state,
                    externalSessionID: nil
                )
            },
            turns: try turns.map(exportTurn),
            messages: messages.map {
                .init(
                    id: $0.id,
                    turnID: $0.turnID,
                    runtimeBindingID: $0.runtimeBindingID,
                    parentMessageID: $0.parentMessageID,
                    sequence: $0.sequence,
                    role: $0.role,
                    body: $0.contentText,
                    status: $0.status,
                    finishReason: $0.finishReason,
                    source: $0.source,
                    sourceCreatedAt: $0.sourceCreatedAt.map(Self.timestamp),
                    createdAt: Self.timestamp($0.createdAt),
                    updatedAt: Self.timestamp($0.updatedAt)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifestData: Data
        do {
            manifestData = try encoder.encode(manifest)
        } catch {
            throw AgentRoomsRoomExportError.corruptHistory
        }
        return AgentRoomsRoomExportPackage(
            markdown: markdown(manifest: manifest),
            manifestData: manifestData
        )
    }

    func export(roomID: UUID, to destination: URL) throws -> AgentRoomsRoomExportResult {
        guard destination.isFileURL,
              !destination.lastPathComponent.isEmpty,
              destination.standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL
                    || !fileManager.fileExists(atPath: destination.path)
        else { throw AgentRoomsRoomExportError.invalidDestination }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AgentRoomsRoomExportError.destinationExists
        }
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: destination.deletingLastPathComponent().path,
            isDirectory: &parentIsDirectory
        ), parentIsDirectory.boolValue else {
            throw AgentRoomsRoomExportError.invalidDestination
        }

        let package = try render(roomID: roomID)
        let markdownURL = destination.appendingPathComponent(Self.markdownFileName)
        let manifestURL = destination.appendingPathComponent(Self.manifestFileName)
        var createdDestination = false
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            createdDestination = true
            try Data(package.markdown.utf8).write(to: markdownURL, options: [.atomic])
            try package.manifestData.write(to: manifestURL, options: [.atomic])
        } catch {
            if createdDestination {
                try? fileManager.removeItem(at: destination)
            }
            throw AgentRoomsRoomExportError.writeFailed
        }
        return AgentRoomsRoomExportResult(
            packageURL: destination,
            markdownURL: markdownURL,
            manifestURL: manifestURL
        )
    }

    private func validateAuthority(_ room: ConversationRoom) throws {
        guard room.lifecycleState != .trashed, room.trashedAt == nil else {
            throw AgentRoomsRoomExportError.ineligibleRoom
        }
        if room.stableKey == nil {
            guard room.kind == "chat",
                  room.metadata.isEmpty || room.metadata == [
                    "authority": AgentRoomsConversationPersistence.nativeRoomAuthority,
                    "schema_version": "1",
                  ]
            else { throw AgentRoomsRoomExportError.ineligibleRoom }
        } else {
            guard room.stableKey == AgentRoomsTestChatPersistence.stableRoomKey,
                  room.kind == "cider-test-chat",
                  room.metadata["authority"] == "cider-test-chat.hermes-runs.v1",
                  room.metadata["schema_version"] == "1",
                  room.metadata["source"] == "cider-rooms-live-continuation",
                  room.metadata.count == 3
            else { throw AgentRoomsRoomExportError.ineligibleRoom }
        }
        guard safeText(room.title, limit: 240) else { throw AgentRoomsRoomExportError.privateContent }
    }

    private func validateRows(
        room: ConversationRoom,
        bindings: [ConversationRuntimeBinding],
        turns: [ConversationTurn],
        messages: [ConversationMessage]
    ) throws {
        guard turns.enumerated().allSatisfy({ $0.element.roomID == room.id && $0.element.sequence == Int64($0.offset + 1) }),
              messages.enumerated().allSatisfy({ $0.element.roomID == room.id && $0.element.sequence == Int64($0.offset + 1) }),
              bindings.allSatisfy({ $0.roomID == room.id }),
              room.nextTurnSequence == Int64(turns.count + 1),
              room.nextMessageSequence == Int64(messages.count + 1)
        else { throw AgentRoomsRoomExportError.corruptHistory }

        let turnIDs = Set(turns.map(\.id))
        let bindingIDs = Set(bindings.map(\.id))
        for binding in bindings {
            guard safeIdentity(binding.runtimeID),
                  safeIdentity(binding.transportID),
                  safeIdentity(binding.sourceNamespace),
                  binding.parentBindingID.map(bindingIDs.contains) ?? true
            else { throw AgentRoomsRoomExportError.privateContent }
        }
        for turn in turns {
            guard turn.runtimeBindingID.map(bindingIDs.contains) ?? true,
                  turn.source.map({ safeSource($0) }) ?? true,
                  turn.error.map({ safeIdentity($0.code) }) ?? true
            else { throw AgentRoomsRoomExportError.privateContent }
        }
        for message in messages {
            guard message.turnID.map(turnIDs.contains) ?? true,
                  message.runtimeBindingID.map(bindingIDs.contains) ?? true,
                  message.source.map({ safeSource($0) }) ?? true,
                  safeIdentity(message.role),
                  safeText(message.contentText, limit: AgentRoomsLiveChatModel.maximumStreamingMessageLength)
            else { throw AgentRoomsRoomExportError.privateContent }
        }
    }

    private func exportTurn(_ turn: ConversationTurn) throws -> AgentRoomsRoomExportManifest.Turn {
        let references = referencesFact(turn.metadata["cider_references_json"])
        let context = contextFact(turn.metadata)
        let approvals = approvalFact(turn.metadata)
        let attachments = attachmentFact(turn.metadata)
        let artifacts = generatedArtifactFact(turn.metadata)
        return .init(
            id: turn.id,
            sequence: turn.sequence,
            runtimeBindingID: turn.runtimeBindingID,
            source: turn.source,
            status: turn.status,
            errorCode: turn.error?.code,
            createdAt: Self.timestamp(turn.createdAt),
            startedAt: turn.startedAt.map(Self.timestamp),
            completedAt: turn.completedAt.map(Self.timestamp),
            updatedAt: Self.timestamp(turn.updatedAt),
            sources: references,
            context: context,
            approvals: approvals,
            attachments: attachments,
            generatedArtifacts: artifacts
        )
    }

    private func referencesFact(_ raw: String?) -> AgentRoomsRoomExportFactCollection<HermesCiderReference> {
        guard let raw else { return .init(state: .notReported, values: []) }
        guard let values = decode([HermesCiderReference].self, raw), !values.isEmpty else {
            return raw == "[]" ? .init(state: .notReported, values: []) : .init(state: .rejected, values: [])
        }
        guard values.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount,
              values.allSatisfy({ safeText($0.title, limit: AgentRoomsCiderReceiptProjector.maximumTitleLength) }),
              AgentRoomsCiderReceiptProjector.project(values, bookmarkThumbnail: { _ in nil }) != nil
        else { return .init(state: .rejected, values: []) }
        return .init(state: .validated, values: values)
    }

    private func contextFact(_ metadata: [String: String]) -> AgentRoomsRoomExportFactCollection<HermesCiderContextCheckpoint> {
        let state = factState(metadata["context_checkpoint_fact_state"])
        let value = metadata["context_checkpoint_json"].flatMap { decode(HermesCiderContextCheckpoint.self, $0) }
        guard state == .validated else { return .init(state: state, values: []) }
        guard let value,
              AgentRoomsContextCheckpointProjector.project(
                factState: .validated,
                checkpoint: value,
                bookmarkThumbnail: { _ in nil }
              ) != nil
        else { return .init(state: .rejected, values: []) }
        return .init(state: .validated, values: [value])
    }

    private func approvalFact(_ metadata: [String: String]) -> AgentRoomsRoomExportFactCollection<HermesApprovalRequest> {
        let state = factState(metadata["approval_fact_state"])
        guard state == .validated else { return .init(state: state, values: []) }
        guard let raw = metadata["approval_requests_json"],
              let values = decode([HermesApprovalRequest].self, raw),
              AgentRoomsApprovalProjector.project(
                factState: .validated,
                requests: values,
                bookmarkThumbnail: { _ in nil }
              ) != nil
        else { return .init(state: .rejected, values: []) }
        return .init(state: .validated, values: values)
    }

    private func attachmentFact(_ metadata: [String: String]) -> AgentRoomsRoomExportFactCollection<HermesCiderAttachment> {
        let state = factState(metadata["attachment_fact_state"])
        guard state == .validated else { return .init(state: state, values: []) }
        guard let raw = metadata["attachments_json"],
              let values = decode([HermesCiderAttachment].self, raw),
              AgentRoomsAssetProjector.validatesAttachments(values)
        else { return .init(state: .rejected, values: []) }
        return .init(state: .validated, values: values)
    }

    private func generatedArtifactFact(_ metadata: [String: String]) -> AgentRoomsRoomExportFactCollection<HermesCiderGeneratedArtifact> {
        let state = factState(metadata["generated_artifact_fact_state"])
        guard state == .validated else { return .init(state: state, values: []) }
        guard let raw = metadata["generated_artifacts_json"],
              let values = decode([HermesCiderGeneratedArtifact].self, raw),
              AgentRoomsAssetProjector.validatesGeneratedArtifacts(values)
        else { return .init(state: .rejected, values: []) }
        return .init(state: .validated, values: values)
    }

    private func factState(_ raw: String?) -> HermesStructuredFactState {
        raw.flatMap(HermesStructuredFactState.init(rawValue:)) ?? (raw == nil ? .notReported : .rejected)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ raw: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    private func markdown(manifest: AgentRoomsRoomExportManifest) -> String {
        var lines = [
            "# \(manifest.room.title)",
            "",
            "- Cider room: `\(manifest.room.id.uuidString)`",
            "- Lifecycle: \(manifest.room.lifecycleState.rawValue)",
            "- Created: \(manifest.room.createdAt)",
            "- Updated: \(manifest.room.updatedAt)",
            "",
            "This is a local, open-data Cider export. Runtime sessions, private paths, credentials, and raw transport payloads are omitted.",
        ]
        let messagesByTurn = Dictionary(grouping: manifest.messages, by: \.turnID)
        for turn in manifest.turns {
            lines.append(contentsOf: [
                "",
                "## Turn \(turn.sequence) · \(turn.status.rawValue.capitalized)",
                "",
                "- Turn ID: `\(turn.id.uuidString)`",
                "- Terminal truth: \(terminalTruth(turn.status))",
                "- Source: \(turn.source?.namespace ?? "Cider local")",
            ])
            if let errorCode = turn.errorCode { lines.append("- Error code: \(errorCode)") }
            for message in (messagesByTurn[turn.id] ?? []).sorted(by: { $0.sequence < $1.sequence }) {
                lines.append(contentsOf: [
                    "",
                    "### \(message.role == "user" ? "You" : "Hermes")",
                    "",
                    message.body,
                ])
                if message.status == .incomplete {
                    lines.append("")
                    lines.append("_Incomplete · \(message.finishReason?.rawValue ?? "unknown")_"
                    )
                }
            }
            appendFactSummary("Sources", state: turn.sources.state, count: turn.sources.values.count, to: &lines)
            appendFactSummary("Context checkpoints", state: turn.context.state, count: turn.context.values.count, to: &lines)
            appendFactSummary("Approvals", state: turn.approvals.state, count: turn.approvals.values.count, to: &lines)
            appendAttachmentSummary(turn.attachments, to: &lines)
            appendGeneratedArtifactSummary(turn.generatedArtifacts, to: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendFactSummary(
        _ title: String,
        state: HermesStructuredFactState,
        count: Int,
        to lines: inout [String]
    ) {
        lines.append("")
        lines.append("### \(title)")
        lines.append("")
        lines.append("\(state.rawValue) · \(count)")
    }

    private func appendAttachmentSummary(
        _ facts: AgentRoomsRoomExportFactCollection<HermesCiderAttachment>,
        to lines: inout [String]
    ) {
        appendFactSummary("Attachments", state: facts.state, count: facts.values.count, to: &lines)
        for fact in facts.values {
            lines.append("- \(fact.displayName) · \(fact.contentType)\(sizeSuffix(fact.byteSize)) · \(fact.provenance)")
        }
    }

    private func appendGeneratedArtifactSummary(
        _ facts: AgentRoomsRoomExportFactCollection<HermesCiderGeneratedArtifact>,
        to lines: inout [String]
    ) {
        appendFactSummary("Generated artifacts", state: facts.state, count: facts.values.count, to: &lines)
        for fact in facts.values {
            lines.append("- \(fact.displayName) · \(fact.contentType)\(sizeSuffix(fact.byteSize)) · \(fact.provenance)")
        }
    }

    private func sizeSuffix(_ byteSize: Int64?) -> String {
        guard let byteSize else { return "" }
        guard byteSize >= 1_024 else { return " · \(byteSize) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(byteSize)
        var unit = -1
        repeat {
            value /= 1_024
            unit += 1
        } while value >= 1_024 && unit < units.count - 1
        let rendered = value.rounded() == value
            ? String(Int64(value))
            : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        return " · \(rendered) \(units[unit])"
    }

    private func terminalTruth(_ status: ConversationTurnStatus) -> String {
        switch status {
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .unknown: "Outcome unavailable"
        case .pending, .running, .waiting: "Incomplete · \(status.rawValue)"
        }
    }

    private func safeSource(_ source: ConversationSourceIdentity) -> Bool {
        safeIdentity(source.namespace) && safeIdentity(source.id)
    }

    private func safeIdentity(_ raw: String) -> Bool {
        guard raw.count <= 240,
              AgentRoomsTurnFactPrivacyPolicy.isSafeDisplayText(raw),
              !raw.contains("/"),
              !raw.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
        else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
        return raw.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func safeText(_ raw: String, limit: Int) -> Bool {
        raw.count <= limit && AgentRoomsTurnFactPrivacyPolicy.isSafeDisplayText(raw)
    }

    private static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

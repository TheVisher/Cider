import Foundation

enum HermesBridgeAvailability: Equatable, Sendable {
    case apiRuns
    case cliFallback
    case unavailable(String)
}

enum HermesRunStatus: Equatable, Sendable {
    case queued
    case running(runID: String)
    case waitingForApproval(String?)
    case completed(String)
    case failed(String)
    case cancelled
}

enum HermesRunEvent: Equatable, Sendable {
    case runStarted(String)
    case messageDelta(String)
    case toolStarted(name: String?, preview: String?)
    case toolCompleted(name: String?, isError: Bool)
    case reasoningAvailable(String)
    case approvalRequested(String?)
    case completed(output: String)
    case failed(String)
    case cancelled
}

struct HermesRunSnapshot: Equatable, Sendable {
    var status: HermesRunStatus
    var visibleText: String
    var toolSummary: String?

    static let empty = HermesRunSnapshot(status: .queued, visibleText: "", toolSummary: nil)

    func reducing(_ event: HermesRunEvent) -> HermesRunSnapshot {
        var next = self
        switch event {
        case .runStarted(let runID):
            next.status = .running(runID: runID)
        case .messageDelta(let delta):
            next.visibleText += delta
        case .toolStarted(let name, let preview):
            next.toolSummary = preview ?? name
        case .toolCompleted(let name, let isError):
            if isError {
                next.toolSummary = "\(name ?? "Tool") failed"
            }
        case .reasoningAvailable:
            break
        case .approvalRequested(let detail):
            next.status = .waitingForApproval(detail)
            next.toolSummary = detail ?? "Waiting for approval"
        case .completed(let output):
            next.status = .completed(output)
            // Runs streaming is provisional. The gateway's completed output is
            // the authoritative per-turn transcript and may contain content the
            // provider did not deliver through message.delta callbacks.
            next.visibleText = output
        case .failed(let message):
            next.status = .failed(message)
        case .cancelled:
            next.status = .cancelled
        }
        return next
    }
}

struct HermesBridgeSendResult: Sendable {
    let completion: HermesRunCompletionEnvelope

    var state: HermesConversationState { completion.finalState }
    var messages: [AIAssistantMessage] { completion.finalMessages }
}

enum HermesTransportProvenance: Equatable, Sendable {
    case hermesRunsAPI
    case cliFallback
    case other
}

enum HermesRunTerminalStatus: Equatable, Sendable {
    case completed
    case cancelled
    case failed
    case disconnected
    case unknown
}

struct HermesRunObservedFacts: Equatable, Sendable {
    let containedToolEvent: Bool
    let containedReasoningEvent: Bool
    let containedApprovalEvent: Bool
    let containedAttachmentContentOrEvent: Bool
    let containedPendingContentOrEvent: Bool
    let containedStreamingContentOrEvent: Bool
    let runIdentityConsistent: Bool

    static let none = Self(
        containedToolEvent: false,
        containedReasoningEvent: false,
        containedApprovalEvent: false,
        containedAttachmentContentOrEvent: false,
        containedPendingContentOrEvent: false,
        containedStreamingContentOrEvent: false,
        runIdentityConsistent: true
    )

    var containsExcludedEventOrContent: Bool {
        containedToolEvent || containedReasoningEvent || containedApprovalEvent ||
        containedAttachmentContentOrEvent || containedPendingContentOrEvent ||
        containedStreamingContentOrEvent
    }
}

struct HermesTerminalSourceIdentityEvidence: Equatable, Sendable {
    let reportedTerminalRunID: String?
    let userSourceID: String?
    let assistantSourceID: String?
    let userSourceSessionID: String?
    let assistantSourceSessionID: String?
}

struct HermesCiderReference: Codable, Equatable, Sendable {
    let kind: String
    let id: String
    let title: String
    let boardID: String?
    let projectID: String?
    let artifactType: String?
    let source: String
    let sourceRef: String

    enum CodingKeys: String, CodingKey {
        case kind, id, title, source
        case boardID = "board_id"
        case projectID = "project_id"
        case artifactType = "artifact_type"
        case sourceRef = "source_ref"
    }
}

enum HermesStructuredFactState: String, Codable, Equatable, Sendable {
    case notReported
    case validated
    case rejected
}

struct HermesCiderContextCheckpoint: Codable, Equatable, Sendable {
    let id: String
    let selected: [HermesCiderReference]
    let citations: [HermesCiderReference]
    let omissionReason: String?
    let source: String
    let sourceRef: String

    enum CodingKeys: String, CodingKey {
        case id, selected, citations, source
        case omissionReason = "omission_reason"
        case sourceRef = "source_ref"
    }
}

struct HermesApprovalRequest: Codable, Equatable, Sendable {
    let id: String
    let action: String
    let target: HermesCiderReference?
    let risk: String
    let scope: String
    let status: String
    let source: String
    let sourceRef: String

    enum CodingKeys: String, CodingKey {
        case id, action, target, risk, scope, status, source
        case sourceRef = "source_ref"
    }
}

private struct HermesStrictCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private enum HermesStrictStructuredFactDecoder {
    static func rejectUnknownKeys(
        from decoder: Decoder,
        allowed: Set<String>
    ) throws {
        let container = try decoder.container(keyedBy: HermesStrictCodingKey.self)
        let actual = Set(container.allKeys.map(\.stringValue))
        guard actual.isSubset(of: allowed) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported structured fact keys"
            ))
        }
    }
}

/// Strict Cider-owned target identity used only by attachment and generated-artifact
/// facts. Unknown transport keys reject the containing fact instead of being ignored.
struct HermesCiderAssetReference: Codable, Equatable, Sendable {
    let kind: String
    let id: String
    let title: String
    let projectID: String?
    let artifactType: String?
    let source: String
    let sourceRef: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, id, title, source
        case projectID = "project_id"
        case artifactType = "artifact_type"
        case sourceRef = "source_ref"
    }

    init(
        kind: String,
        id: String,
        title: String,
        projectID: String?,
        artifactType: String?,
        source: String,
        sourceRef: String
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.projectID = projectID
        self.artifactType = artifactType
        self.source = source
        self.sourceRef = sourceRef
    }

    init(from decoder: Decoder) throws {
        try HermesStrictStructuredFactDecoder.rejectUnknownKeys(
            from: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        artifactType = try container.decodeIfPresent(String.self, forKey: .artifactType)
        source = try container.decode(String.self, forKey: .source)
        sourceRef = try container.decode(String.self, forKey: .sourceRef)
    }
}

struct HermesCiderAttachment: Codable, Equatable, Sendable {
    let id: String
    let target: HermesCiderAssetReference
    let displayName: String
    let contentType: String
    let byteSize: Int64?
    let provenance: String
    let source: String
    let sourceRef: String
    let sha256: String?
    let inputSource: String?
    let lifecycle: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, target, provenance, source
        case displayName = "display_name"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case sourceRef = "source_ref"
        case sha256
        case inputSource = "input_source"
        case lifecycle
    }

    init(
        id: String,
        target: HermesCiderAssetReference,
        displayName: String,
        contentType: String,
        byteSize: Int64?,
        provenance: String,
        source: String,
        sourceRef: String,
        sha256: String? = nil,
        inputSource: String? = nil,
        lifecycle: String? = nil
    ) {
        self.id = id
        self.target = target
        self.displayName = displayName
        self.contentType = contentType
        self.byteSize = byteSize
        self.provenance = provenance
        self.source = source
        self.sourceRef = sourceRef
        self.sha256 = sha256
        self.inputSource = inputSource
        self.lifecycle = lifecycle
    }

    init(from decoder: Decoder) throws {
        try HermesStrictStructuredFactDecoder.rejectUnknownKeys(
            from: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        target = try container.decode(HermesCiderAssetReference.self, forKey: .target)
        displayName = try container.decode(String.self, forKey: .displayName)
        contentType = try container.decode(String.self, forKey: .contentType)
        byteSize = try container.decodeIfPresent(Int64.self, forKey: .byteSize)
        provenance = try container.decode(String.self, forKey: .provenance)
        source = try container.decode(String.self, forKey: .source)
        sourceRef = try container.decode(String.self, forKey: .sourceRef)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        inputSource = try container.decodeIfPresent(String.self, forKey: .inputSource)
        lifecycle = try container.decodeIfPresent(String.self, forKey: .lifecycle)
    }
}

struct HermesCiderGeneratedArtifact: Codable, Equatable, Sendable {
    let id: String
    let target: HermesCiderAssetReference
    let displayName: String
    let contentType: String
    let byteSize: Int64?
    let provenance: String
    let source: String
    let sourceRef: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, target, provenance, source
        case displayName = "display_name"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case sourceRef = "source_ref"
    }

    init(
        id: String,
        target: HermesCiderAssetReference,
        displayName: String,
        contentType: String,
        byteSize: Int64?,
        provenance: String,
        source: String,
        sourceRef: String
    ) {
        self.id = id
        self.target = target
        self.displayName = displayName
        self.contentType = contentType
        self.byteSize = byteSize
        self.provenance = provenance
        self.source = source
        self.sourceRef = sourceRef
    }

    init(from decoder: Decoder) throws {
        try HermesStrictStructuredFactDecoder.rejectUnknownKeys(
            from: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        target = try container.decode(HermesCiderAssetReference.self, forKey: .target)
        displayName = try container.decode(String.self, forKey: .displayName)
        contentType = try container.decode(String.self, forKey: .contentType)
        byteSize = try container.decodeIfPresent(Int64.self, forKey: .byteSize)
        provenance = try container.decode(String.self, forKey: .provenance)
        source = try container.decode(String.self, forKey: .source)
        sourceRef = try container.decode(String.self, forKey: .sourceRef)
    }
}

enum HermesCiderAssetFactContract {
    static let maximumCount = 8
    static let maximumDisplayLength = 160
    static let maximumContentTypeLength = 127
    static let maximumIdentifierLength = 120
    static let maximumByteSize: Int64 = 1_125_899_906_842_624 // 1 PiB

    static func normalizedAttachments(
        _ values: [HermesCiderAttachment]
    ) -> (state: HermesStructuredFactState, values: [HermesCiderAttachment]) {
        guard values.allSatisfy({ value in
            let hashValid = value.sha256.map { hash in
                hash.count == 64 && hash.unicodeScalars.allSatisfy {
                    CharacterSet(charactersIn: "0123456789abcdef").contains($0)
                }
            } ?? true
            let inputValid = value.inputSource.map {
                ConversationAttachmentInputSource(rawValue: $0) != nil
            } ?? true
            let lifecycleValid = value.lifecycle.map { $0 == "accepted" } ?? true
            return hashValid && inputValid && lifecycleValid
        }) else { return (.rejected, []) }
        return normalized(
            values,
            id: \.id,
            target: \.target,
            displayName: \.displayName,
            contentType: \.contentType,
            byteSize: \.byteSize,
            provenance: \.provenance,
            source: \.source,
            sourceRef: \.sourceRef,
            sourcePrefix: "attachment",
            allowedProvenance: ["user_attachment", "source_attachment"],
            allowsProjectArtifact: false
        )
    }

    static func normalizedGeneratedArtifacts(
        _ values: [HermesCiderGeneratedArtifact]
    ) -> (state: HermesStructuredFactState, values: [HermesCiderGeneratedArtifact]) {
        normalized(
            values,
            id: \.id,
            target: \.target,
            displayName: \.displayName,
            contentType: \.contentType,
            byteSize: \.byteSize,
            provenance: \.provenance,
            source: \.source,
            sourceRef: \.sourceRef,
            sourcePrefix: "generated_artifact",
            allowedProvenance: ["cider_generated"],
            allowsProjectArtifact: true
        )
    }

    private static func normalized<Value: Equatable>(
        _ values: [Value],
        id: KeyPath<Value, String>,
        target: KeyPath<Value, HermesCiderAssetReference>,
        displayName: KeyPath<Value, String>,
        contentType: KeyPath<Value, String>,
        byteSize: KeyPath<Value, Int64?>,
        provenance: KeyPath<Value, String>,
        source: KeyPath<Value, String>,
        sourceRef: KeyPath<Value, String>,
        sourcePrefix: String,
        allowedProvenance: Set<String>,
        allowsProjectArtifact: Bool
    ) -> (state: HermesStructuredFactState, values: [Value]) {
        guard !values.isEmpty else { return (.notReported, []) }
        guard values.count <= maximumCount else { return (.rejected, []) }
        var byID: [String: Value] = [:]
        var byTarget: [String: Value] = [:]
        for value in values {
            let valueID = value[keyPath: id]
            let valueTarget = value[keyPath: target]
            guard canonicalUUID(valueID),
                  value[keyPath: source] == "cider",
                  value[keyPath: sourceRef] == "\(sourcePrefix):\(valueID)",
                  allowedProvenance.contains(value[keyPath: provenance]),
                  safeDisplayText(value[keyPath: displayName]),
                  safeContentType(value[keyPath: contentType]),
                  value[keyPath: byteSize].map({ $0 >= 0 && $0 <= maximumByteSize }) ?? true,
                  validTarget(valueTarget, allowsProjectArtifact: allowsProjectArtifact)
            else { return (.rejected, []) }
            if let existing = byID[valueID], existing != value { return (.rejected, []) }
            if let existing = byTarget[valueTarget.sourceRef], existing != value { return (.rejected, []) }
            byID[valueID] = value
            byTarget[valueTarget.sourceRef] = value
        }
        return (.validated, byID.keys.sorted().compactMap { byID[$0] })
    }

    private static func validTarget(
        _ target: HermesCiderAssetReference,
        allowsProjectArtifact: Bool
    ) -> Bool {
        guard target.source == "cider",
              canonicalUUID(target.id),
              safeDisplayText(target.title)
        else { return false }
        switch target.kind {
        case "vault_file":
            return target.projectID == nil
                && target.artifactType == nil
                && target.sourceRef == "vaultFile:\(target.id)"
        case "project_artifact" where allowsProjectArtifact:
            return safeIdentifier(target.projectID)
                && safeIdentifier(target.artifactType)
                && target.sourceRef == "note:\(target.id)"
        default:
            return false
        }
    }

    private static func canonicalUUID(_ raw: String) -> Bool {
        UUID(uuidString: raw)?.uuidString == raw
    }

    private static func safeIdentifier(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty, raw.count <= maximumIdentifierLength else { return false }
        let lower = raw.lowercased()
        guard !lower.contains("api_key"),
              !lower.contains("password"),
              !lower.contains("secret"),
              !lower.contains("token")
        else { return false }
        return raw.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }

    private static func safeDisplayText(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return !raw.isEmpty
            && raw == raw.trimmingCharacters(in: .whitespacesAndNewlines)
            && raw.count <= maximumDisplayLength
            && !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !raw.contains("/")
            && !raw.contains("\\")
            && !lower.contains("file://")
            && !lower.contains(".ssh")
            && !lower.contains(".env")
            && !lower.contains("api_key")
            && !lower.contains("access_key")
            && !lower.contains("password")
            && !lower.contains("bearer ")
            && !lower.contains("token=")
            && !lower.contains("secret=")
            && !lower.contains("sk-proj-")
            && !lower.contains("sk_live_")
            && !lower.contains("rk_live_")
            && !lower.contains("ghp_")
            && !lower.contains("github_pat_")
            && !lower.contains("xoxb-")
            && !lower.contains("private key")
    }

    private static func safeContentType(_ raw: String) -> Bool {
        guard raw.count <= maximumContentTypeLength,
              raw == raw.lowercased(),
              let slash = raw.firstIndex(of: "/"),
              slash != raw.startIndex,
              raw.index(after: slash) != raw.endIndex,
              !raw[raw.index(after: slash)...].contains("/")
        else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-/")
        return raw.unicodeScalars.allSatisfy(allowed.contains)
    }
}

struct HermesRunCompletionEnvelope: Equatable, Sendable {
    let provenance: HermesTransportProvenance
    let runID: String?
    let terminalStatus: HermesRunTerminalStatus
    let observedFacts: HermesRunObservedFacts
    let finalSessionSynchronizationComplete: Bool
    let finalMessages: [AIAssistantMessage]
    let finalState: HermesConversationState
    let modelIdentity: String?
    let terminalSourceEvidence: HermesTerminalSourceIdentityEvidence
    let ciderReferences: [HermesCiderReference]
    let contextCheckpointFactState: HermesStructuredFactState
    let contextCheckpoint: HermesCiderContextCheckpoint?
    let approvalFactState: HermesStructuredFactState
    let approvalRequests: [HermesApprovalRequest]
    let attachmentFactState: HermesStructuredFactState
    let attachments: [HermesCiderAttachment]
    let generatedArtifactFactState: HermesStructuredFactState
    let generatedArtifacts: [HermesCiderGeneratedArtifact]

    init(
        provenance: HermesTransportProvenance,
        runID: String?,
        terminalStatus: HermesRunTerminalStatus,
        observedFacts: HermesRunObservedFacts,
        finalSessionSynchronizationComplete: Bool,
        finalMessages: [AIAssistantMessage],
        finalState: HermesConversationState,
        modelIdentity: String?,
        terminalSourceEvidence: HermesTerminalSourceIdentityEvidence,
        ciderReferences: [HermesCiderReference] = [],
        contextCheckpointFactState: HermesStructuredFactState = .notReported,
        contextCheckpoint: HermesCiderContextCheckpoint? = nil,
        approvalFactState: HermesStructuredFactState = .notReported,
        approvalRequests: [HermesApprovalRequest] = [],
        attachmentFactState: HermesStructuredFactState = .notReported,
        attachments: [HermesCiderAttachment] = [],
        generatedArtifactFactState: HermesStructuredFactState = .notReported,
        generatedArtifacts: [HermesCiderGeneratedArtifact] = []
    ) {
        self.provenance = provenance
        self.runID = runID
        self.terminalStatus = terminalStatus
        self.observedFacts = observedFacts
        self.finalSessionSynchronizationComplete = finalSessionSynchronizationComplete
        self.finalMessages = finalMessages
        self.finalState = finalState
        self.modelIdentity = modelIdentity
        self.terminalSourceEvidence = terminalSourceEvidence
        self.ciderReferences = ciderReferences
        self.contextCheckpointFactState = contextCheckpointFactState
        self.contextCheckpoint = contextCheckpoint
        self.approvalFactState = approvalFactState
        self.approvalRequests = approvalRequests
        self.attachmentFactState = attachmentFactState
        self.attachments = attachments
        self.generatedArtifactFactState = generatedArtifactFactState
        self.generatedArtifacts = generatedArtifacts
    }

    var isEligibleForFutureShadowPersistence: Bool {
        HermesRunCompletionEligibility.isEligible(self)
    }
}

enum HermesRunCompletionEligibility {
    static func isEligible(_ envelope: HermesRunCompletionEnvelope) -> Bool {
        guard envelope.provenance == .hermesRunsAPI,
              envelope.terminalStatus == .completed,
              envelope.finalSessionSynchronizationComplete,
              !envelope.observedFacts.containsExcludedEventOrContent,
              envelope.observedFacts.runIdentityConsistent,
              envelope.contextCheckpointFactState == .notReported,
              envelope.contextCheckpoint == nil,
              envelope.approvalFactState == .notReported,
              envelope.approvalRequests.isEmpty,
              envelope.attachmentFactState == .notReported,
              envelope.attachments.isEmpty,
              envelope.generatedArtifactFactState == .notReported,
              envelope.generatedArtifacts.isEmpty,
              let runID = nonempty(envelope.runID),
              nonempty(envelope.modelIdentity) != nil,
              envelope.terminalSourceEvidence.reportedTerminalRunID == runID,
              envelope.finalMessages.allSatisfy({ $0.attachments.isEmpty }),
              !envelope.finalMessages.contains(where: hasPendingOrStreamingIdentity),
              envelope.finalMessages.count >= 2
        else { return false }

        let user = envelope.finalMessages[envelope.finalMessages.count - 2]
        let assistant = envelope.finalMessages[envelope.finalMessages.count - 1]
        let expectedUserSourceID = "hermes-run:\(runID):user"
        let expectedAssistantSourceID = "hermes-run:\(runID):assistant"
        guard user.role == .user,
              assistant.role == .assistant,
              nonempty(user.content) != nil,
              nonempty(assistant.content) != nil,
              user.sourceID == expectedUserSourceID,
              assistant.sourceID == expectedAssistantSourceID,
              envelope.terminalSourceEvidence.userSourceID == expectedUserSourceID,
              envelope.terminalSourceEvidence.assistantSourceID == expectedAssistantSourceID,
              let userSessionID = nonempty(user.sourceSessionID),
              let assistantSessionID = nonempty(assistant.sourceSessionID),
              userSessionID == assistantSessionID,
              envelope.terminalSourceEvidence.userSourceSessionID == userSessionID,
              envelope.terminalSourceEvidence.assistantSourceSessionID == assistantSessionID
        else { return false }

        let state = envelope.finalState
        return state.runtimeID == "hermes" &&
            state.activeRuntimeSessionID == assistantSessionID &&
            state.runtimeSessionLineage.last == assistantSessionID &&
            Set(state.runtimeSessionLineage).count == state.runtimeSessionLineage.count &&
            state.lastSyncedAt == assistant.timestamp &&
            state.lastSyncedMessageID == expectedAssistantSourceID &&
            state.lastSyncedTimestamp == assistant.timestamp &&
            state.lastImportedRuntimeSessionID == assistantSessionID
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func hasPendingOrStreamingIdentity(_ message: AIAssistantMessage) -> Bool {
        guard let sourceID = message.sourceID else { return false }
        return sourceID.hasPrefix("hermes:pending:") || sourceID.hasPrefix("hermes-live:")
    }
}

protocol HermesBridgeTransport: Sendable {
    func availability() async -> HermesBridgeAvailability
    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult
    func attachmentCapability() async -> ConversationAttachmentTransportCapability
    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        attachments: [ConversationAttachmentTransportPayload],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult
    func stop(runID: String) async throws
}

extension HermesBridgeTransport {
    func attachmentCapability() async -> ConversationAttachmentTransportCapability {
        .unsupported(reason: "The selected runtime does not support native file attachments.")
    }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        attachments: [ConversationAttachmentTransportPayload],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        guard attachments.isEmpty else {
            throw ConversationAttachmentInputError.rejected("The selected runtime does not support native file attachments.")
        }
        return try await send(text: text, state: state, existingMessages: existingMessages, onEvent: onEvent)
    }
    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesBridgeSendResult {
        try await send(text: text, state: state, existingMessages: existingMessages, onEvent: nil)
    }
}

actor HermesTurnCoordinator {
    static let shared = HermesTurnCoordinator()

    private var activeTurnID: UUID?

    func beginTurn() throws -> UUID {
        if activeTurnID != nil {
            throw HermesSessionClientError.hermesCommandFailed("Hermes is already handling a Cider message")
        }
        let id = UUID()
        activeTurnID = id
        return id
    }

    func endTurn(_ id: UUID) {
        guard activeTurnID == id else { return }
        activeTurnID = nil
    }
}

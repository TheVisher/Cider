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
            if next.visibleText.isEmpty {
                next.visibleText = output
            }
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
        approvalRequests: [HermesApprovalRequest] = []
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
    func stop(runID: String) async throws
}

extension HermesBridgeTransport {
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

import Foundation

enum AgentRoomsLiveTransportState: Equatable, Sendable {
    case unchecked
    case checking
    case ready
    case blocked
}

enum AgentRoomsLiveTurnState: String, Equatable, Sendable {
    case idle, sending, streaming, cancelling, failed, completed
}

struct AgentRoomsLiveActivity: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case reasoning, toolStarted, toolCompleted }
    let id: UUID
    let kind: Kind
    let detail: String
}

enum AgentRoomsCiderOpenRoute: Equatable, Sendable {
    case bookmark(bookmarkID: UUID)
    case card(boardID: String, cardID: String)
    case note(noteID: UUID)

    var userInfo: [String: String] {
        switch self {
        case .bookmark(let bookmarkID):
            return [
                CiderExternalOpenBridge.Key.targetType: "bookmark",
                CiderExternalOpenBridge.Key.targetID: bookmarkID.uuidString,
            ]
        case .card(let boardID, let cardID):
            return [
                CiderExternalOpenBridge.Key.targetType: "card",
                CiderExternalOpenBridge.Key.targetID: cardID,
                CiderExternalOpenBridge.Key.boardID: boardID,
            ]
        case .note(let noteID):
            return [
                CiderExternalOpenBridge.Key.targetType: "note",
                CiderExternalOpenBridge.Key.targetID: noteID.uuidString,
            ]
        }
    }
}

struct AgentRoomsCiderObjectReceipt: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case bookmark, task, projectArtifact }

    let kind: Kind
    let title: String
    let identifier: String
    let provenance: String
    let truthBoundary: String
    let openRoute: AgentRoomsCiderOpenRoute
    var bookmarkThumbnail: AgentRoomsBookmarkThumbnailReference? = nil
}

struct AgentRoomsSavedBookmarkReference: Equatable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    var thumbnail: AgentRoomsBookmarkThumbnailReference? = nil
}

@MainActor
enum AgentRoomsCanonicalSavedBookmarkResolver {
    static func matches(_ url: URL) -> [AgentRoomsSavedBookmarkReference] {
        guard let candidate = VaultDuplicateAuditor.canonicalBookmarkURL(url.absoluteString) else { return [] }
        return VaultBookmarkService.shared.bookmarks.compactMap { bookmark in
            guard let saved = VaultDuplicateAuditor.canonicalBookmarkURL(bookmark.urlString),
                  saved == candidate,
                  let savedURL = bookmark.url
            else { return nil }
            return AgentRoomsSavedBookmarkReference(
                id: bookmark.id,
                title: bookmark.title,
                url: savedURL,
                thumbnail: AgentRoomsBookmarkReceiptThumbnail.reference(for: bookmark)
            )
        }
    }
}

enum AgentRoomsCiderReceiptProjector {
    static let maximumReferenceCount = 1
    static let maximumTitleLength = 160
    static let maximumIdentifierLength = 120
    static let maximumURLLength = 2_048
    static let provenance = "Cider canonical read"
    static let truthBoundary = "Source-backed object, not transcript truth"

    @MainActor
    static func projectSavedBookmark(
        terminalOutput: String,
        matching: @MainActor (URL) -> [AgentRoomsSavedBookmarkReference]
    ) -> AgentRoomsCiderObjectReceipt? {
        guard terminalOutput.count <= AgentRoomsLiveChatModel.maximumStreamingMessageLength,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }

        let fullRange = NSRange(terminalOutput.startIndex..<terminalOutput.endIndex, in: terminalOutput)
        let detected = detector.matches(in: terminalOutput, options: [], range: fullRange)
        guard detected.count == 1,
              let match = detected.first,
              let matchRange = Range(match.range, in: terminalOutput)
        else { return nil }

        let rawURL = String(terminalOutput[matchRange])
        let standaloneLines = terminalOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0 == rawURL }
        guard standaloneLines.count == 1,
              rawURL.count <= maximumURLLength,
              !rawURL.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              var components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.host = host
        guard let url = components.url else { return nil }
        let matches = matching(url)
        guard matches.count == 1,
              let bookmark = matches.first,
              let candidateIdentity = VaultDuplicateAuditor.canonicalBookmarkURL(url.absoluteString),
              VaultDuplicateAuditor.canonicalBookmarkURL(bookmark.url.absoluteString) == candidateIdentity,
              let title = boundedTitle(bookmark.title)
        else { return nil }

        let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return AgentRoomsCiderObjectReceipt(
            kind: .bookmark,
            title: title,
            identifier: "Saved bookmark · \(displayHost)",
            provenance: provenance,
            truthBoundary: truthBoundary,
            openRoute: .bookmark(bookmarkID: bookmark.id),
            bookmarkThumbnail: bookmark.thumbnail?.bookmarkID == bookmark.id ? bookmark.thumbnail : nil
        )
    }

    static func project(_ references: [HermesCiderReference]) -> AgentRoomsCiderObjectReceipt? {
        guard references.count == maximumReferenceCount,
              let reference = references.first,
              reference.source == "cider",
              let id = identifier(reference.id),
              let title = boundedTitle(reference.title)
        else { return nil }

        switch reference.kind {
        case "task":
            guard reference.projectID == nil,
                  reference.artifactType == nil,
                  let boardID = identifier(reference.boardID),
                  reference.sourceRef == "kanban_card:\(boardID)/\(id)"
            else { return nil }
            return AgentRoomsCiderObjectReceipt(
                kind: .task,
                title: title,
                identifier: "Task · \(id)",
                provenance: provenance,
                truthBoundary: truthBoundary,
                openRoute: .card(boardID: boardID, cardID: id)
            )
        case "project_artifact":
            guard reference.boardID == nil,
                  let noteID = UUID(uuidString: id),
                  let projectID = identifier(reference.projectID),
                  let artifactType = identifier(reference.artifactType),
                  reference.sourceRef == "note:\(id)"
            else { return nil }
            return AgentRoomsCiderObjectReceipt(
                kind: .projectArtifact,
                title: title,
                identifier: "\(displayName(projectID)) · \(displayName(artifactType))",
                provenance: provenance,
                truthBoundary: truthBoundary,
                openRoute: .note(noteID: noteID)
            )
        default:
            return nil
        }
    }

    private static func identifier(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= maximumIdentifierLength,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else { return nil }
        return value
    }

    private static func boundedTitle(_ raw: String) -> String? {
        let scalars = raw.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
        }
        let title = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return String(title.prefix(maximumTitleLength))
    }

    private static func displayName(_ identifier: String) -> String {
        if identifier.count <= 2 { return identifier.uppercased() }
        return identifier
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct AgentRoomsTranscriptFollowPolicy: Equatable, Sendable {
    static let nearBottomDistance: CGFloat = 72
    private(set) var shouldAutoScrollForNewContent = true

    @discardableResult
    mutating func shouldFollow(distanceFromBottom: CGFloat) -> Bool {
        shouldAutoScrollForNewContent = distanceFromBottom <= Self.nearBottomDistance
        return shouldAutoScrollForNewContent
    }
}

@MainActor
final class AgentRoomsLiveChatModel: ObservableObject {
    static let roomTitle = "Cider Test Chat"
    static let maximumMessageLength = 4_000
    static let maximumStreamingMessageLength = 32_000
    static let maximumEventDetailLength = 240
    static let maximumRunIdentityLength = 120
    static let maximumLiveActivityCount = 24
    static let unavailableMessage = "Hermes live transport is not ready. Open Live Chat to check the connection."
    static let failedMessage = "Hermes could not complete this message."
    static let acceptedInterruptionMessage = "Hermes accepted the message, but the response was interrupted. It cannot be retried safely."
    static let receiptSourceIdentity = "Hermes Runs API"

    @Published private(set) var testRoom: AgentRoom?
    @Published private(set) var transportState: AgentRoomsLiveTransportState = .unchecked
    @Published private(set) var composerMessage: String?
    @Published private(set) var activeRunCanBeCancelled = false
    @Published private(set) var turnState: AgentRoomsLiveTurnState = .idle
    @Published private(set) var liveActivity: [AgentRoomsLiveActivity] = []

    private let transport: any HermesBridgeTransport
    private let turnCoordinator: HermesTurnCoordinator
    private let savedBookmarkMatches: @MainActor (URL) -> [AgentRoomsSavedBookmarkReference]
    private let makeID: @MainActor () -> UUID
    private let now: @MainActor () -> Date
    private let persistence: AgentRoomsTestChatPersistence?

    private var roomID: UUID?
    private var conversationState: HermesConversationState?
    private var transportMessages: [AIAssistantMessage] = []
    private var roomMessages: [AgentRoomMessage] = []
    private var receipt: AgentRoomReceipt?
    private var activeAttemptID: UUID?
    private var activeClientMessageID: String?
    private var activeRunID: String?
    private var eventIntegrityFailed = false
    private var completedAssistantSourceIDs = Set<String>()
    private var streamingAssistantID: String?
    private var recoveredDraft: String?

    init(
        transport: any HermesBridgeTransport,
        turnCoordinator: HermesTurnCoordinator = .shared,
        savedBookmarkMatches: @escaping @MainActor (URL) -> [AgentRoomsSavedBookmarkReference] = {
            AgentRoomsCanonicalSavedBookmarkResolver.matches($0)
        },
        makeID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init,
        persistence: AgentRoomsTestChatPersistence? = nil
    ) {
        self.transport = transport
        self.turnCoordinator = turnCoordinator
        self.savedBookmarkMatches = savedBookmarkMatches
        self.makeID = makeID
        self.now = now
        self.persistence = persistence
    }

    @discardableResult
    func restoreDurableTestChat() -> Bool {
        guard roomID == nil, let persistence else { return roomID != nil }
        do {
            guard let snapshot = try persistence.restore() else { return false }
            roomID = snapshot.roomID
            conversationState = snapshot.conversationState
            transportMessages = snapshot.messages
            roomMessages = snapshot.messages.map { message in
                AgentRoomMessage(
                    id: message.sourceID ?? makeID().uuidString,
                    role: message.role == .user ? .human : .agent,
                    author: message.role == .user ? "You" : "Hermes",
                    body: message.content,
                    deliveryState: .sent
                )
            }
            completedAssistantSourceIDs = Set(
                snapshot.messages.filter { $0.role == .assistant }.compactMap(\.sourceID)
            )
            let lastAssistant = snapshot.messages.last(where: { $0.role == .assistant })
            let objectReceipt = snapshot.latestCiderReferences.isEmpty
                ? lastAssistant.flatMap {
                    AgentRoomsCiderReceiptProjector.projectSavedBookmark(
                        terminalOutput: $0.content,
                        matching: savedBookmarkMatches
                    )
                }
                : AgentRoomsCiderReceiptProjector.project(snapshot.latestCiderReferences)
            receipt = .init(
                id: "cider-room-receipt:\(snapshot.latestRunID)",
                title: "Hermes completed a live turn",
                detail: "Runs API · Source-backed terminal · Live continuation",
                status: .completed,
                continuity: .liveContinuation,
                sourceBackedTransport: true,
                sourceIdentity: Self.receiptSourceIdentity,
                runIdentity: sanitized(snapshot.latestRunID, limit: Self.maximumRunIdentityLength),
                activity: [],
                objectReceipt: objectReceipt
            )
            turnState = .completed
            rebuildRoom()
            return true
        } catch {
            return false
        }
    }

    func startTestChat() async {
        createTestChat()
        await refreshTransportReadiness()
    }

    func createTestChat() {
        if roomID == nil {
            let id = makeID()
            roomID = id
            conversationState = HermesConversationState(
                conversationID: id,
                activeRuntimeSessionID: "",
                runtimeSessionLineage: [],
                title: Self.roomTitle,
                source: "cider-rooms-live-continuation"
            )
            rebuildRoom()
        }
    }

    func refreshTransportReadiness() async {
        guard roomID != nil, activeAttemptID == nil else { return }
        transportState = .checking
        switch await transport.availability() {
        case .apiRuns:
            transportState = .ready
            composerMessage = nil
        case .cliFallback, .unavailable:
            transportState = .blocked
            composerMessage = Self.unavailableMessage
        }
    }

    func isComposerEnabled(selectedRoomID: String?) -> Bool {
        guard let roomID else { return false }
        return selectedRoomID == roomID.uuidString && transportState == .ready && activeAttemptID == nil
    }

    func send(_ text: String, selectedRoomID: String?) async {
        guard isComposerEnabled(selectedRoomID: selectedRoomID) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            composerMessage = "Type a message before sending."
            return
        }
        guard trimmed.count <= Self.maximumMessageLength else {
            composerMessage = "Messages can be up to \(Self.maximumMessageLength) characters."
            return
        }

        let clientID = "cider-room-client:\(makeID().uuidString)"
        roomMessages.append(.init(
            id: clientID,
            role: .human,
            author: "You",
            body: trimmed,
            deliveryState: .pending
        ))
        rebuildRoom()
        await performSend(text: trimmed, clientID: clientID)
    }

    func takeRecoveredDraft() -> String? {
        defer { recoveredDraft = nil }
        return recoveredDraft
    }

    func retry(clientMessageID: String, selectedRoomID: String?) async {
        guard isComposerEnabled(selectedRoomID: selectedRoomID),
              let index = roomMessages.firstIndex(where: {
                  $0.id == clientMessageID && $0.role == .human && $0.deliveryState == .failed && $0.canRetry
              })
        else { return }
        let text = roomMessages[index].body
        recoveredDraft = nil
        roomMessages[index].deliveryState = .pending
        roomMessages[index].canRetry = false
        composerMessage = nil
        rebuildRoom()
        await performSend(text: text, clientID: clientMessageID)
    }

    func cancelActiveSend() async {
        guard let attemptID = activeAttemptID else { return }
        turnState = .cancelling
        if let runID = activeRunID {
            try? await transport.stop(runID: runID)
        }
        guard activeAttemptID == attemptID else { return }
        if activeRunID == nil,
           let activeClientMessageID,
           let message = roomMessages.first(where: { $0.id == activeClientMessageID }) {
            recoveredDraft = message.body
        }
        failActiveMessage(message: "Hermes response cancelled.", canRetry: activeRunID == nil)
        turnState = .failed
        receipt = makeReceipt(
            title: "Hermes turn cancelled",
            detail: "Runs API · Live continuation",
            status: .cancelled,
            runID: activeRunID
        )
        clearActiveAttempt()
        rebuildRoom()
    }

    private func performSend(text: String, clientID: String) async {
        guard let state = conversationState, activeAttemptID == nil else { return }
        let attemptID = makeID()
        activeAttemptID = attemptID
        activeClientMessageID = clientID
        activeRunID = nil
        eventIntegrityFailed = false
        composerMessage = nil
        receipt = nil
        turnState = .sending
        liveActivity = []
        streamingAssistantID = nil

        do {
            let result = try await coordinatedSend(text: text, state: state, attemptID: attemptID)
            guard activeAttemptID == attemptID else { return }
            try persistence?.persist(
                result.completion,
                expectedText: text,
                expectedConversationID: state.conversationID
            )
            try applyCompletion(result.completion, expectedText: text, clientID: clientID)
            turnState = .completed
            clearActiveAttempt()
            rebuildRoom()
        } catch is CancellationError {
            guard activeAttemptID == attemptID else { return }
            failActiveMessage(message: "Hermes response was interrupted.", canRetry: activeRunID == nil)
            recoveredDraft = activeRunID == nil ? text : nil
            turnState = .failed
            receipt = makeReceipt(
                title: "Hermes turn interrupted",
                detail: "Runs API · Live continuation",
                status: .cancelled,
                runID: activeRunID
            )
            clearActiveAttempt()
            rebuildRoom()
        } catch {
            guard activeAttemptID == attemptID else { return }
            let accepted = activeRunID != nil
            failActiveMessage(
                message: accepted ? Self.acceptedInterruptionMessage : Self.failedMessage,
                canRetry: !accepted
            )
            recoveredDraft = accepted ? nil : text
            turnState = .failed
            receipt = makeReceipt(
                title: accepted ? "Hermes response interrupted" : "Hermes send failed",
                detail: "Runs API · Live continuation",
                status: .failed,
                runID: activeRunID
            )
            clearActiveAttempt()
            rebuildRoom()
        }
    }

    private func coordinatedSend(
        text: String,
        state: HermesConversationState,
        attemptID: UUID
    ) async throws -> HermesBridgeSendResult {
        let turnID = try await turnCoordinator.beginTurn()
        do {
            let result = try await transport.send(
                text: text,
                state: state,
                existingMessages: transportMessages,
                onEvent: { [weak self] event in
                    await self?.receive(event, attemptID: attemptID)
                }
            )
            await turnCoordinator.endTurn(turnID)
            return result
        } catch {
            await turnCoordinator.endTurn(turnID)
            throw error
        }
    }

    private func receive(_ event: HermesRunEvent, attemptID: UUID) {
        guard activeAttemptID == attemptID else { return }
        switch event {
        case .runStarted(let runID):
            guard nonempty(runID) != nil else {
                eventIntegrityFailed = true
                return
            }
            if let activeRunID, activeRunID != runID {
                eventIntegrityFailed = true
            } else {
                activeRunID = runID
                activeRunCanBeCancelled = true
            }
        case .messageDelta(let delta):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendStreamingDelta(delta)
        case .toolStarted(let name, let preview):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendActivity(.toolStarted, detail: preview ?? name)
        case .toolCompleted(let name, let isError):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendActivity(.toolCompleted, detail: "\(name ?? "Tool") \(isError ? "failed" : "completed")")
        case .reasoningAvailable(let detail):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendActivity(.reasoning, detail: detail)
        case .failed, .cancelled:
            eventIntegrityFailed = true
        case .completed(let output):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            reconcileStreamingOutput(output)
        case .approvalRequested:
            break
        }
    }

    private func appendStreamingDelta(_ raw: String) {
        let delta = sanitized(raw, limit: Self.maximumStreamingMessageLength, trimmingWhitespace: false)
        guard !delta.isEmpty else { return }
        turnState = .streaming
        let id = streamingAssistantID ?? "cider-room-stream:\(activeAttemptID?.uuidString ?? makeID().uuidString)"
        streamingAssistantID = id
        if let index = roomMessages.firstIndex(where: { $0.id == id }) {
            let remaining = max(0, Self.maximumStreamingMessageLength - roomMessages[index].body.count)
            guard remaining > 0 else { return }
            roomMessages[index].body += String(delta.prefix(remaining))
        } else {
            roomMessages.append(.init(id: id, role: .agent, author: "Hermes", body: String(delta.prefix(Self.maximumStreamingMessageLength))))
        }
        rebuildRoom()
    }

    private func reconcileStreamingOutput(_ raw: String) {
        let output = sanitized(raw, limit: Self.maximumStreamingMessageLength)
        guard !output.isEmpty else { return }
        turnState = .streaming
        let id = streamingAssistantID ?? "cider-room-stream:\(activeAttemptID?.uuidString ?? makeID().uuidString)"
        streamingAssistantID = id
        if let index = roomMessages.firstIndex(where: { $0.id == id }) {
            if output.hasPrefix(roomMessages[index].body) { roomMessages[index].body = output }
        } else {
            roomMessages.append(.init(id: id, role: .agent, author: "Hermes", body: output))
        }
        rebuildRoom()
    }

    private func appendActivity(_ kind: AgentRoomsLiveActivity.Kind, detail raw: String?) {
        let detail = sanitized(raw ?? "", limit: Self.maximumEventDetailLength)
        guard !detail.isEmpty else { return }
        turnState = .streaming
        liveActivity.append(.init(id: makeID(), kind: kind, detail: detail))
        if liveActivity.count > Self.maximumLiveActivityCount {
            liveActivity.removeFirst(liveActivity.count - Self.maximumLiveActivityCount)
        }
        rebuildRoom()
    }

    private func sanitized(_ raw: String, limit: Int, trimmingWhitespace: Bool = true) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        let clean = String(String.UnicodeScalarView(scalars))
        let normalized = trimmingWhitespace ? clean.trimmingCharacters(in: .whitespacesAndNewlines) : clean
        return normalized.prefix(limit).description
    }

    private func applyCompletion(
        _ completion: HermesRunCompletionEnvelope,
        expectedText: String,
        clientID: String
    ) throws {
        guard !eventIntegrityFailed,
              completion.provenance == .hermesRunsAPI,
              completion.terminalStatus == .completed,
              completion.finalSessionSynchronizationComplete,
              completion.observedFacts.runIdentityConsistent,
              nonempty(completion.modelIdentity) != nil,
              let runID = nonempty(completion.runID),
              activeRunID == nil || activeRunID == runID,
              completion.terminalSourceEvidence.reportedTerminalRunID == runID,
              completion.finalMessages.count >= 2
        else { throw AgentRoomsLiveChatError.invalidTerminalReceipt }

        let user = completion.finalMessages[completion.finalMessages.count - 2]
        let assistant = completion.finalMessages[completion.finalMessages.count - 1]
        let expectedUserSourceID = "hermes-run:\(runID):user"
        let expectedAssistantSourceID = "hermes-run:\(runID):assistant"
        guard user.role == .user,
              assistant.role == .assistant,
              user.content == expectedText,
              nonempty(assistant.content) != nil,
              user.sourceID == expectedUserSourceID,
              assistant.sourceID == expectedAssistantSourceID,
              completion.terminalSourceEvidence.userSourceID == expectedUserSourceID,
              completion.terminalSourceEvidence.assistantSourceID == expectedAssistantSourceID,
              let userSession = nonempty(user.sourceSessionID),
              userSession == nonempty(assistant.sourceSessionID),
              completion.terminalSourceEvidence.userSourceSessionID == userSession,
              completion.terminalSourceEvidence.assistantSourceSessionID == userSession,
              user.attachments.isEmpty,
              assistant.attachments.isEmpty,
              completion.finalState.runtimeID == "hermes",
              completion.finalState.activeRuntimeSessionID == userSession,
              completion.finalState.runtimeSessionLineage.last == userSession,
              completion.finalState.lastSyncedMessageID == expectedAssistantSourceID,
              completion.finalState.lastSyncedTimestamp == assistant.timestamp,
              completion.finalState.lastImportedRuntimeSessionID == userSession
        else { throw AgentRoomsLiveChatError.invalidTerminalReceipt }

        if let index = roomMessages.firstIndex(where: { $0.id == clientID }) {
            roomMessages[index].deliveryState = .sent
            roomMessages[index].canRetry = false
        }
        if completedAssistantSourceIDs.insert(expectedAssistantSourceID).inserted {
            if let streamingAssistantID,
               let index = roomMessages.firstIndex(where: { $0.id == streamingAssistantID }) {
                roomMessages[index] = .init(id: expectedAssistantSourceID, role: .agent, author: "Hermes", body: assistant.content)
            } else {
                roomMessages.append(.init(id: expectedAssistantSourceID, role: .agent, author: "Hermes", body: assistant.content))
            }
        }
        transportMessages = completion.finalMessages
        conversationState = completion.finalState
        let objectReceipt = completion.ciderReferences.isEmpty
            ? AgentRoomsCiderReceiptProjector.projectSavedBookmark(
                terminalOutput: assistant.content,
                matching: savedBookmarkMatches
            )
            : AgentRoomsCiderReceiptProjector.project(completion.ciderReferences)
        receipt = .init(
            id: "cider-room-receipt:\(runID)",
            title: "Hermes completed a live turn",
            detail: "Runs API · Source-backed terminal · Live continuation",
            status: .completed,
            continuity: .liveContinuation,
            sourceBackedTransport: true,
            sourceIdentity: Self.receiptSourceIdentity,
            runIdentity: sanitized(runID, limit: Self.maximumRunIdentityLength),
            activity: liveActivity,
            objectReceipt: objectReceipt
        )
    }

    private func makeReceipt(
        title: String,
        detail: String,
        status: AgentRoomReceiptStatus,
        runID: String?
    ) -> AgentRoomReceipt {
        let displayRunID = runID.map { sanitized($0, limit: Self.maximumRunIdentityLength) }
        return AgentRoomReceipt(
            id: "cider-room-receipt:\(displayRunID ?? makeID().uuidString)",
            title: title,
            detail: detail,
            status: status,
            continuity: .liveContinuation,
            sourceBackedTransport: runID != nil,
            sourceIdentity: Self.receiptSourceIdentity,
            runIdentity: displayRunID,
            activity: liveActivity
        )
    }

    private func failActiveMessage(message: String, canRetry: Bool) {
        if let activeClientMessageID,
           let index = roomMessages.firstIndex(where: { $0.id == activeClientMessageID }) {
            roomMessages[index].deliveryState = .failed
            roomMessages[index].canRetry = canRetry
        }
        composerMessage = message
        if let streamingAssistantID {
            roomMessages.removeAll { $0.id == streamingAssistantID }
        }
    }

    private func clearActiveAttempt() {
        activeAttemptID = nil
        activeClientMessageID = nil
        activeRunID = nil
        activeRunCanBeCancelled = false
        eventIntegrityFailed = false
        streamingAssistantID = nil
    }

    private func rebuildRoom() {
        guard let roomID else {
            testRoom = nil
            return
        }
        let preview = roomMessages.last?.body ?? "New live conversation with Hermes"
        testRoom = AgentRoom(
            id: roomID.uuidString,
            title: Self.roomTitle,
            preview: preview,
            updatedAt: now(),
            relativeTime: "Now",
            transcript: .init(
                runtimeLabel: "Hermes",
                messages: roomMessages,
                link: nil,
                receipt: receipt,
                futureArtifact: nil
            ),
            continuity: .liveContinuation
        )
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private enum AgentRoomsLiveChatError: Error {
    case invalidTerminalReceipt
}

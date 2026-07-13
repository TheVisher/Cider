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

struct AgentRoomsRecoveredDraft: Equatable, Sendable {
    let roomID: String
    let text: String
}

enum AgentRoomsCiderOpenRoute: Equatable, Sendable {
    case bookmark(bookmarkID: UUID)
    case card(boardID: String, cardID: String)
    case note(noteID: UUID)

    var stableIdentity: String {
        switch self {
        case .bookmark(let bookmarkID):
            "bookmark:\(bookmarkID.uuidString)"
        case .card(let boardID, let cardID):
            "kanban_card:\(boardID)/\(cardID)"
        case .note(let noteID):
            "note:\(noteID.uuidString)"
        }
    }

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

struct AgentRoomsCiderObjectReceipt: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case bookmark, note, task, projectArtifact }

    let id: String
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

    static func thumbnail(bookmarkID: UUID) -> AgentRoomsBookmarkThumbnailReference? {
        guard let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == bookmarkID }) else {
            return nil
        }
        return AgentRoomsBookmarkReceiptThumbnail.reference(for: bookmark)
    }
}

enum AgentRoomsCiderReceiptProjector {
    static let maximumReferenceCount = 8
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
            id: AgentRoomsCiderOpenRoute.bookmark(bookmarkID: bookmark.id).stableIdentity,
            kind: .bookmark,
            title: title,
            identifier: "Saved bookmark · \(displayHost)",
            provenance: provenance,
            truthBoundary: truthBoundary,
            openRoute: .bookmark(bookmarkID: bookmark.id),
            bookmarkThumbnail: bookmark.thumbnail?.bookmarkID == bookmark.id ? bookmark.thumbnail : nil
        )
    }

    @MainActor
    static func project(
        _ references: [HermesCiderReference],
        bookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference? = {
            AgentRoomsCanonicalSavedBookmarkResolver.thumbnail(bookmarkID: $0)
        }
    ) -> [AgentRoomsCiderObjectReceipt]? {
        guard !references.isEmpty, references.count <= maximumReferenceCount else { return nil }

        var byIdentity: [String: AgentRoomsCiderObjectReceipt] = [:]
        for reference in references {
            guard let receipt = project(reference, bookmarkThumbnail: bookmarkThumbnail) else { return nil }
            if let existing = byIdentity[receipt.openRoute.stableIdentity] {
                guard existing == receipt else { return nil }
            } else {
                byIdentity[receipt.openRoute.stableIdentity] = receipt
            }
        }
        return byIdentity.values.sorted { lhs, rhs in
            let left = sortKey(lhs)
            let right = sortKey(rhs)
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    @MainActor
    private static func project(
        _ reference: HermesCiderReference,
        bookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference?
    ) -> AgentRoomsCiderObjectReceipt? {
        guard reference.source == "cider",
              let id = identifier(reference.id),
              let title = boundedTitle(reference.title)
        else { return nil }

        switch reference.kind {
        case "bookmark":
            guard reference.boardID == nil,
                  reference.projectID == nil,
                  reference.artifactType == nil,
                  let bookmarkID = UUID(uuidString: id),
                  reference.sourceRef == "bookmark:\(id)"
            else { return nil }
            let route = AgentRoomsCiderOpenRoute.bookmark(bookmarkID: bookmarkID)
            let thumbnail = bookmarkThumbnail(bookmarkID)
            return AgentRoomsCiderObjectReceipt(
                id: route.stableIdentity,
                kind: .bookmark,
                title: title,
                identifier: "Saved bookmark",
                provenance: provenance,
                truthBoundary: truthBoundary,
                openRoute: route,
                bookmarkThumbnail: thumbnail?.bookmarkID == bookmarkID ? thumbnail : nil
            )
        case "note":
            guard reference.boardID == nil,
                  reference.projectID == nil,
                  reference.artifactType == nil,
                  let noteID = UUID(uuidString: id),
                  reference.sourceRef == "note:\(id)"
            else { return nil }
            let route = AgentRoomsCiderOpenRoute.note(noteID: noteID)
            return AgentRoomsCiderObjectReceipt(
                id: route.stableIdentity,
                kind: .note,
                title: title,
                identifier: "Note",
                provenance: provenance,
                truthBoundary: truthBoundary,
                openRoute: route
            )
        case "task", "card", "kanban_card":
            guard reference.projectID == nil,
                  reference.artifactType == nil,
                  let boardID = identifier(reference.boardID),
                  reference.sourceRef == "kanban_card:\(boardID)/\(id)"
            else { return nil }
            let route = AgentRoomsCiderOpenRoute.card(boardID: boardID, cardID: id)
            return AgentRoomsCiderObjectReceipt(
                id: route.stableIdentity,
                kind: .task,
                title: title,
                identifier: "Kanban card · \(id)",
                provenance: provenance,
                truthBoundary: truthBoundary,
                openRoute: route
            )
        case "project_artifact":
            guard reference.boardID == nil,
                  let noteID = UUID(uuidString: id),
                  let projectID = identifier(reference.projectID),
                  let artifactType = identifier(reference.artifactType),
                  reference.sourceRef == "note:\(id)"
            else { return nil }
            let route = AgentRoomsCiderOpenRoute.note(noteID: noteID)
            return AgentRoomsCiderObjectReceipt(
                id: route.stableIdentity,
                kind: .projectArtifact,
                title: title,
                identifier: "\(displayName(projectID)) · \(displayName(artifactType))",
                provenance: provenance,
                truthBoundary: truthBoundary,
                openRoute: route
            )
        default:
            return nil
        }
    }

    private static func sortKey(_ receipt: AgentRoomsCiderObjectReceipt) -> Int {
        switch receipt.kind {
        case .bookmark: 0
        case .note: 1
        case .task: 2
        case .projectArtifact: 3
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

    @Published private(set) var activeRoom: AgentRoom?
    @Published private(set) var transportState: AgentRoomsLiveTransportState = .unchecked
    @Published private(set) var composerMessage: String?
    @Published private(set) var activeRunCanBeCancelled = false
    @Published private(set) var turnState: AgentRoomsLiveTurnState = .idle
    @Published private(set) var liveActivity: [AgentRoomsLiveActivity] = []

    private let transport: any HermesBridgeTransport
    private let turnCoordinator: HermesTurnCoordinator
    private let savedBookmarkMatches: @MainActor (URL) -> [AgentRoomsSavedBookmarkReference]
    private let savedBookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference?
    private let makeID: @MainActor () -> UUID
    private let now: @MainActor () -> Date
    private let persistence: (any AgentRoomsConversationPersisting)?

    private var roomID: UUID?
    private var activeRoomTitle = AgentRoomsLiveChatModel.roomTitle
    private var isReservedTestChat = false
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
    private var recoveredDraftRoomID: String?
    private var persistentAttempt: AgentRoomsConversationAttempt?

    var testRoom: AgentRoom? {
        isReservedTestChat ? activeRoom : nil
    }

    init(
        transport: any HermesBridgeTransport,
        turnCoordinator: HermesTurnCoordinator = .shared,
        savedBookmarkMatches: @escaping @MainActor (URL) -> [AgentRoomsSavedBookmarkReference] = {
            AgentRoomsCanonicalSavedBookmarkResolver.matches($0)
        },
        savedBookmarkThumbnail: @escaping @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference? = {
            AgentRoomsCanonicalSavedBookmarkResolver.thumbnail(bookmarkID: $0)
        },
        makeID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init,
        persistence: (any AgentRoomsConversationPersisting)? = nil
    ) {
        self.transport = transport
        self.turnCoordinator = turnCoordinator
        self.savedBookmarkMatches = savedBookmarkMatches
        self.savedBookmarkThumbnail = savedBookmarkThumbnail
        self.makeID = makeID
        self.now = now
        self.persistence = persistence
    }

    @discardableResult
    func restoreDurableTestChat() -> Bool {
        guard roomID == nil, let persistence else { return roomID != nil }
        do {
            guard let snapshot = try persistence.restoreReservedTestChat() else { return false }
            apply(snapshot, reservedTestChat: true)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func activateCanonicalRoom(id: UUID) -> Bool {
        guard activeAttemptID == nil, let persistence else { return false }
        do {
            guard let snapshot = try persistence.restoreCanonicalRoom(id: id) else { return false }
            let previousTransportState = roomID == id && !isReservedTestChat ? transportState : .unchecked
            apply(snapshot, reservedTestChat: false)
            transportState = previousTransportState
            return true
        } catch {
            return false
        }
    }

    func deactivateRoom() {
        guard activeAttemptID == nil else { return }
        roomID = nil
        activeRoomTitle = Self.roomTitle
        isReservedTestChat = false
        conversationState = nil
        transportMessages = []
        roomMessages = []
        receipt = nil
        activeRoom = nil
        transportState = .unchecked
        composerMessage = nil
        turnState = .idle
        liveActivity = []
        completedAssistantSourceIDs = []
    }

    func startTestChat() async {
        createTestChat()
        await refreshTransportReadiness()
    }

    func createTestChat() {
        if !isReservedTestChat || roomID == nil {
            let id = makeID()
            roomID = id
            activeRoomTitle = Self.roomTitle
            isReservedTestChat = true
            transportMessages = []
            roomMessages = []
            receipt = nil
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

        guard let roomID else { return }
        let userMessageID = makeID()
        let clientID = "cider-room-client:\(userMessageID.uuidString)"
        let attemptID = makeID()
        let assistantMessageID = makeID()
        let timestamp = now()
        let durableAttempt: AgentRoomsConversationAttempt?
        do {
            durableAttempt = try persistence?.beginAttempt(
                roomID: roomID,
                roomTitle: activeRoomTitle,
                isReservedTestChat: isReservedTestChat,
                attemptID: attemptID,
                clientMessageID: clientID,
                userMessageID: userMessageID,
                assistantMessageID: assistantMessageID,
                text: trimmed,
                at: timestamp
            )
        } catch {
            composerMessage = "Cider could not safely save this message. Nothing was sent."
            return
        }
        roomMessages.append(.init(
            id: clientID,
            role: .human,
            author: "You",
            body: trimmed,
            deliveryState: .pending
        ))
        rebuildRoom()
        await performSend(text: trimmed, clientID: clientID, persistentAttempt: durableAttempt)
    }

    func takeRecoveredDraft() -> String? {
        defer {
            recoveredDraft = nil
            recoveredDraftRoomID = nil
        }
        return recoveredDraft
    }

    func takeRecoveredDraftRecovery() -> AgentRoomsRecoveredDraft? {
        defer {
            recoveredDraft = nil
            recoveredDraftRoomID = nil
        }
        guard let recoveredDraft, let recoveredDraftRoomID else { return nil }
        return .init(roomID: recoveredDraftRoomID, text: recoveredDraft)
    }

    func retry(clientMessageID: String, selectedRoomID: String?) async {
        guard isComposerEnabled(selectedRoomID: selectedRoomID),
              let index = roomMessages.firstIndex(where: {
                  $0.id == clientMessageID && $0.role == .human && $0.deliveryState == .failed && $0.canRetry
              })
        else { return }
        let text = roomMessages[index].body
        recoveredDraft = nil
        recoveredDraftRoomID = nil
        roomMessages[index].deliveryState = .pending
        roomMessages[index].canRetry = false
        composerMessage = nil
        rebuildRoom()
        let attemptID = makeID()
        let durableAttempt: AgentRoomsConversationAttempt?
        do {
            guard let roomID else { return }
            durableAttempt = try persistence?.beginAttempt(
                roomID: roomID,
                roomTitle: activeRoomTitle,
                isReservedTestChat: isReservedTestChat,
                attemptID: attemptID,
                clientMessageID: clientMessageID,
                userMessageID: makeID(),
                assistantMessageID: makeID(),
                text: text,
                at: now()
            )
        } catch {
            roomMessages[index].deliveryState = .failed
            roomMessages[index].canRetry = true
            composerMessage = "Cider could not safely prepare this retry. Nothing was sent."
            rebuildRoom()
            return
        }
        await performSend(text: text, clientID: clientMessageID, persistentAttempt: durableAttempt)
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
            setRecoveredDraft(message.body)
        }
        let partial = streamingAssistantID.flatMap { id in
            roomMessages.first(where: { $0.id == id })?.body
        }
        if let persistentAttempt {
            try? persistence?.terminate(
                persistentAttempt,
                status: .cancelled,
                runID: activeRunID,
                partialAssistantText: partial,
                activity: liveActivity,
                at: now()
            )
        }
        failActiveMessage(message: "Hermes response cancelled.", canRetry: activeRunID == nil)
        turnState = .failed
        receipt = makeReceipt(
            title: "Hermes turn cancelled",
            detail: activeRunID == nil
                ? "Cancelled before acceptance · Safe to retry"
                : "Cancelled · Accepted by Hermes · Partial response kept",
            status: .cancelled,
            runID: activeRunID
        )
        clearActiveAttempt()
        rebuildRoom()
    }

    private func performSend(
        text: String,
        clientID: String,
        persistentAttempt: AgentRoomsConversationAttempt?
    ) async {
        guard let state = conversationState, activeAttemptID == nil else { return }
        let attemptID = makeID()
        activeAttemptID = attemptID
        activeClientMessageID = clientID
        activeRunID = nil
        self.persistentAttempt = persistentAttempt
        eventIntegrityFailed = false
        composerMessage = nil
        recoveredDraft = nil
        recoveredDraftRoomID = nil
        receipt = nil
        turnState = .sending
        liveActivity = []
        streamingAssistantID = persistentAttempt?.assistantMessageID.uuidString

        do {
            let result = try await coordinatedSend(text: text, state: state, attemptID: attemptID)
            guard activeAttemptID == attemptID else { return }
            guard !eventIntegrityFailed,
                  let terminalRunID = nonempty(result.completion.runID),
                  activeRunID == nil || activeRunID == terminalRunID
            else { throw AgentRoomsLiveChatError.invalidTerminalReceipt }
            if let persistentAttempt {
                try persistence?.complete(
                    persistentAttempt,
                    completion: result.completion,
                    expectedText: text,
                    activity: liveActivity
                )
            }
            try applyCompletion(result.completion, expectedText: text, clientID: clientID)
            turnState = .completed
            clearActiveAttempt()
            rebuildRoom()
        } catch is CancellationError {
            guard activeAttemptID == attemptID else { return }
            let partial = streamingAssistantID.flatMap { id in
                roomMessages.first(where: { $0.id == id })?.body
            }
            if let persistentAttempt {
                try? persistence?.terminate(
                    persistentAttempt,
                    status: .cancelled,
                    runID: activeRunID,
                    partialAssistantText: partial,
                    activity: liveActivity,
                    at: now()
                )
            }
            failActiveMessage(message: "Hermes response was interrupted.", canRetry: activeRunID == nil)
            if activeRunID == nil { setRecoveredDraft(text) }
            turnState = .failed
            receipt = makeReceipt(
                title: "Hermes turn interrupted",
                detail: activeRunID == nil
                    ? "Not accepted by Hermes · Safe to retry"
                    : "Accepted by Hermes · Partial response kept · Cannot retry safely",
                status: .cancelled,
                runID: activeRunID
            )
            clearActiveAttempt()
            rebuildRoom()
        } catch {
            guard activeAttemptID == attemptID else { return }
            let accepted = activeRunID != nil
            let partial = streamingAssistantID.flatMap { id in
                roomMessages.first(where: { $0.id == id })?.body
            }
            if let persistentAttempt {
                try? persistence?.terminate(
                    persistentAttempt,
                    status: .failed,
                    runID: activeRunID,
                    partialAssistantText: partial,
                    activity: liveActivity,
                    at: now()
                )
            }
            failActiveMessage(
                message: accepted ? Self.acceptedInterruptionMessage : Self.failedMessage,
                canRetry: !accepted
            )
            if !accepted { setRecoveredDraft(text) }
            turnState = .failed
            receipt = makeReceipt(
                title: accepted ? "Hermes response interrupted" : "Hermes send failed",
                detail: accepted
                    ? "Accepted by Hermes · Partial response kept · Cannot retry safely"
                    : "Not accepted by Hermes · Safe to retry",
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
                if let persistentAttempt {
                    do {
                        try persistence?.markRunStarted(
                            persistentAttempt,
                            runID: runID,
                            activity: liveActivity,
                            at: now()
                        )
                    } catch {
                        eventIntegrityFailed = true
                    }
                }
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
                roomMessages[index].body = assistant.content
            } else {
                roomMessages.append(.init(
                    id: persistentAttempt?.assistantMessageID.uuidString ?? expectedAssistantSourceID,
                    role: .agent,
                    author: "Hermes",
                    body: assistant.content
                ))
            }
        }
        transportMessages = completion.finalMessages
        conversationState = completion.finalState
        let objectReceipts = completion.ciderReferences.isEmpty
            ? AgentRoomsCiderReceiptProjector.projectSavedBookmark(
                terminalOutput: assistant.content,
                matching: savedBookmarkMatches
            ).map { [$0] } ?? []
            : AgentRoomsCiderReceiptProjector.project(
                completion.ciderReferences,
                bookmarkThumbnail: savedBookmarkThumbnail
            ) ?? []
        receipt = .init(
            id: "cider-room-receipt:\(runID)",
            title: "Hermes completed a live turn",
            detail: "Completed · Source-backed · Live continuation",
            status: .completed,
            continuity: .liveContinuation,
            sourceBackedTransport: true,
            sourceIdentity: Self.receiptSourceIdentity,
            runIdentity: sanitized(runID, limit: Self.maximumRunIdentityLength),
            activity: liveActivity,
            objectReceipts: objectReceipts
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
        if let streamingAssistantID, activeRunID == nil {
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
        persistentAttempt = nil
    }

    private func rebuildRoom() {
        guard let roomID else {
            activeRoom = nil
            return
        }
        let preview = roomMessages.last?.body ?? "New live conversation with Hermes"
        activeRoom = AgentRoom(
            id: roomID.uuidString,
            title: activeRoomTitle,
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

    private func apply(_ snapshot: AgentRoomsConversationSnapshot, reservedTestChat: Bool) {
        roomID = snapshot.room.id
        activeRoomTitle = snapshot.room.title
        isReservedTestChat = reservedTestChat
        conversationState = snapshot.conversationState
        transportMessages = snapshot.transportMessages
        roomMessages = snapshot.presentationMessages
        completedAssistantSourceIDs = Set(
            snapshot.transportMessages.filter { $0.role == .assistant }.compactMap(\.sourceID)
        )
        liveActivity = snapshot.latestActivity
        recoveredDraft = snapshot.presentationMessages.last(where: { $0.canRetry })?.body
        recoveredDraftRoomID = recoveredDraft == nil ? nil : snapshot.room.id.uuidString

        let lastAssistant = snapshot.transportMessages.last(where: { $0.role == .assistant })
        let objectReceipts = snapshot.latestCiderReferences.isEmpty
            ? lastAssistant.flatMap {
                AgentRoomsCiderReceiptProjector.projectSavedBookmark(
                    terminalOutput: $0.content,
                    matching: savedBookmarkMatches
                )
            }.map { [$0] } ?? []
            : AgentRoomsCiderReceiptProjector.project(
                snapshot.latestCiderReferences,
                bookmarkThumbnail: savedBookmarkThumbnail
            ) ?? []
        if let status = snapshot.latestTurnStatus, status.isTerminal {
            let presentation: (status: AgentRoomReceiptStatus, title: String, detail: String)
            switch status {
            case .completed:
                presentation = (
                    .completed,
                    "Hermes completed a live turn",
                    "Completed · Source-backed · Live continuation"
                )
            case .cancelled:
                presentation = (
                    .cancelled,
                    "Hermes turn cancelled",
                    snapshot.latestRunID == nil
                        ? "Cancelled before acceptance · Safe to retry"
                        : "Cancelled · Accepted by Hermes · Partial response kept"
                )
            case .failed:
                switch snapshot.latestErrorCode {
                case "pre_accept_interruption":
                    presentation = (
                        .failed,
                        "Message interrupted before acceptance",
                        "Not accepted by Hermes · Safe to retry"
                    )
                case "accepted_interruption":
                    presentation = (
                        .failed,
                        "Hermes response interrupted",
                        "Accepted by Hermes · Cannot retry safely"
                    )
                default:
                    presentation = (
                        .failed,
                        "Hermes turn failed",
                        snapshot.latestRunID == nil
                            ? "Not accepted by Hermes · Safe to retry"
                            : "Accepted by Hermes · Cannot retry safely"
                    )
                }
            case .unknown:
                presentation = (.failed, "Hermes turn outcome is unavailable", "Outcome unavailable · Cannot retry safely")
            case .pending, .running, .waiting:
                presentation = (.failed, "Hermes turn interrupted", "Recovery required")
            }
            receipt = AgentRoomReceipt(
                id: "cider-room-receipt:\(snapshot.latestRunID ?? snapshot.room.id.uuidString)",
                title: presentation.title,
                detail: presentation.detail,
                status: presentation.status,
                continuity: .liveContinuation,
                sourceBackedTransport: snapshot.latestRunID != nil,
                sourceIdentity: Self.receiptSourceIdentity,
                runIdentity: snapshot.latestRunID.map {
                    sanitized($0, limit: Self.maximumRunIdentityLength)
                },
                activity: snapshot.latestActivity,
                objectReceipts: status == .completed ? objectReceipts : []
            )
            turnState = status == .completed ? .completed : .failed
        } else {
            receipt = nil
            turnState = .idle
        }
        transportState = .unchecked
        composerMessage = nil
        clearActiveAttempt()
        rebuildRoom()
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func setRecoveredDraft(_ text: String) {
        recoveredDraft = text
        recoveredDraftRoomID = roomID?.uuidString
    }
}

private enum AgentRoomsLiveChatError: Error {
    case invalidTerminalReceipt
}

import Foundation
import os

// MARK: - Wake Purpose

enum AgentWakePurpose: Sendable {
    case deliverReminder(AgentContext.ReminderContext)
    case dailyDigest
    case scheduledCheck(String)
}

// MARK: - Agent Thread

/// A conversation thread with message history, channel, and metadata.
final class AgentThread: @unchecked Sendable {
    let id: UUID
    let externalKey: String
    let channel: AgentChannel
    var messages: [AgentMessage] = []
    var context: AgentContext
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: String] = [:]

    init(id: UUID, externalKey: String, channel: AgentChannel, context: AgentContext = .empty) {
        self.id = id
        self.externalKey = externalKey
        self.channel = channel
        self.context = context
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func append(_ message: AgentMessage) {
        messages.append(message)
        updatedAt = Date()
    }
}

// MARK: - Agent Orchestrator

actor AgentOrchestrator {
    static let shared = AgentOrchestrator()
    private let logger = Logger(subsystem: "com.cider.app", category: "AgentOrchestrator")

    // Current runtime (set via setRuntime or setProvider adapter)
    private var runtime: (any AgentRuntime)?

    // Active threads by ID
    private var threads: [UUID: AgentThread] = [:]

    // Thread lookup by external key
    private var threadsByKey: [String: UUID] = [:]

    /// Maximum tool call rounds per conversation turn
    private let maxToolRounds = 5

    // MARK: - Configuration

    func setProvider(_ provider: any AgentProvider) {
        self.runtime = ModelAgentRuntime(provider: provider)
    }

    func setRuntime(_ runtime: any AgentRuntime) {
        self.runtime = runtime
    }

    func startRuntimeIfNeeded() async throws {
        guard let runtime else { throw AgentError.providerUnavailable }
        try await runtime.start()
    }

    func stopRuntimeIfNeeded() async {
        guard let runtime else { return }
        await runtime.stop()
    }

    func runtimeHealth() async -> AgentRuntimeHealth {
        guard let runtime else {
            return AgentRuntimeHealth(
                status: .unavailable,
                detail: "No runtime configured",
                lastStartedAt: nil,
                lastActivityAt: nil,
                lastError: nil
            )
        }
        return await runtime.health()
    }

    func runtimeIdentity() -> (id: String, displayName: String, kind: AgentRuntimeKind)? {
        guard let runtime else { return nil }
        return (runtime.id, runtime.displayName, runtime.kind)
    }

    // MARK: - Handle Message

    /// Process an inbound message from any channel.
    func handleMessage(_ envelope: AgentEnvelope) async throws -> AgentResponse {
        guard let runtime else {
            throw AgentError.providerUnavailable
        }

        try await runtime.start()

        let thread = getOrCreateThread(
            id: envelope.threadID,
            externalKey: externalKey(for: envelope),
            channel: envelope.channel,
            context: envelope.context
        )
        thread.append(.user(envelope.text))

        // Get tools allowed for this channel
        let permissionLevel = permissionLevel(for: envelope.channel)
        let allowedTools = await AgentToolRegistry.shared.tools(for: permissionLevel)
        let allowedToolNames = Set(allowedTools.map(\.name))

        // Build system prompt
        let systemPrompt = buildSystemPrompt(thread: thread, runtime: runtime, allowedTools: allowedTools)

        // Run the tool loop
        let response = try await runConversationLoop(
            runtime: runtime,
            threadID: thread.id,
            channel: envelope.channel,
            systemPrompt: systemPrompt,
            messages: thread.messages,
            allowedTools: allowedTools,
            allowedToolNames: allowedToolNames
        )

        thread.append(.assistant(response.text))
        logger.info("Handled message on \(envelope.channel.rawValue) via runtime \(runtime.id, privacy: .public): \(response.toolCallsMade.count) tool calls")
        return response
    }

    // MARK: - Wake

    /// Wake the agent for autonomous actions (reminders, digests, etc.)
    func wake(purpose: AgentWakePurpose) async throws -> AgentResponse {
        switch purpose {
        case .deliverReminder(let reminderContext):
            let threadID = UUID()
            var reminderAgentContext = AgentContext.empty
            reminderAgentContext.reminderContext = reminderContext
            let envelope = AgentEnvelope(
                text: formatReminderPrompt(reminderContext),
                threadID: threadID,
                channel: .system,
                channelThreadID: threadID.uuidString,
                context: reminderAgentContext,
                senderID: nil,
                senderDisplayName: nil,
                metadata: [:]
            )
            return try await handleMessage(envelope)

        case .dailyDigest:
            let threadID = UUID()
            let envelope = AgentEnvelope.system(
                text: "Generate a daily digest of upcoming events, due reminders, and recent vault activity for today.",
                threadID: threadID,
                context: .empty
            )
            return try await handleMessage(envelope)

        case .scheduledCheck(let description):
            let threadID = UUID()
            let envelope = AgentEnvelope.system(
                text: description,
                threadID: threadID,
                context: .empty
            )
            return try await handleMessage(envelope)
        }
    }

    // MARK: - Conversation Loop

    /// The orchestrator owns the tool execution loop.
    /// Provider requests tool calls → orchestrator checks permissions → executes → feeds back.
    private func runConversationLoop(
        runtime: any AgentRuntime,
        threadID: UUID,
        channel: AgentChannel,
        systemPrompt: String,
        messages: [AgentMessage],
        allowedTools: [AgentToolDefinition],
        allowedToolNames: Set<String>
    ) async throws -> AgentResponse {
        var conversationMessages = messages
        var allToolCalls: [AgentToolCall] = []

        for round in 0..<maxToolRounds {
            let runtimeResponse = try await runtime.send(
                AgentRuntimeRequest(
                    threadID: threadID,
                    channel: channel,
                    systemPrompt: systemPrompt,
                    messages: conversationMessages,
                    tools: allowedTools
                )
            )

            if runtimeResponse.toolRequests.isEmpty {
                return AgentResponse(text: runtimeResponse.text, toolCallsMade: allToolCalls)
            }

            logger.debug("Tool round \(round + 1): \(runtimeResponse.toolRequests.count) requests")

            for request in runtimeResponse.toolRequests {
                // Enforce permissions at execution time
                guard allowedToolNames.contains(request.name) else {
                    logger.warning("Tool denied: \(request.name) on channel")
                    conversationMessages.append(.toolResult(
                        name: request.name,
                        result: "Tool '\(request.name)' is not permitted on this channel."
                    ))
                    continue
                }

                // Convert [String: String] to [String: Any] for executor
                let args: [String: Any] = Dictionary(
                    uniqueKeysWithValues: request.arguments.map { ($0.key, $0.value as Any) }
                )

                do {
                    let result = try await AgentToolRegistry.shared.execute(name: request.name, arguments: args)
                    allToolCalls.append(AgentToolCall(name: request.name, arguments: request.arguments, result: result))
                    conversationMessages.append(.toolResult(name: request.name, result: result))
                } catch {
                    let errorResult = "Tool error: \(error.localizedDescription)"
                    conversationMessages.append(.toolResult(name: request.name, result: errorResult))
                }
            }
        }

        logger.warning("Max tool rounds (\(self.maxToolRounds)) exceeded")
        return AgentResponse(text: "I've done as much as I can in one turn.", toolCallsMade: allToolCalls)
    }

    // MARK: - Thread Management

    private func getOrCreateThread(
        id: UUID,
        externalKey: String,
        channel: AgentChannel,
        context: AgentContext
    ) -> AgentThread {
        // Check by external key first (for reply routing)
        if let existingID = threadsByKey[externalKey], let existing = threads[existingID] {
            existing.context = context
            return existing
        }

        // Check by ID
        if let existing = threads[id] {
            existing.context = context
            return existing
        }

        // Create new
        let thread = AgentThread(id: id, externalKey: externalKey, channel: channel, context: context)
        threads[id] = thread
        threadsByKey[externalKey] = id
        return thread
    }

    private func externalKey(for envelope: AgentEnvelope) -> String {
        switch envelope.channel {
        case .uiPanel:
            return "ui:\(envelope.channelThreadID ?? envelope.threadID.uuidString)"
        case .iMessage:
            return "imessage:\(envelope.channelThreadID ?? envelope.senderID ?? "unknown")"
        case .telegram:
            return "telegram:\(envelope.channelThreadID ?? envelope.senderID ?? "unknown")"
        case .shareIngress:
            return "share:\(envelope.channelThreadID ?? envelope.threadID.uuidString)"
        case .iosApp:
            return "ios:\(envelope.channelThreadID ?? envelope.threadID.uuidString)"
        case .system:
            return "system:\(envelope.channelThreadID ?? envelope.threadID.uuidString)"
        case .notification:
            return "notification:\(envelope.channelThreadID ?? envelope.threadID.uuidString)"
        }
    }

    private func permissionLevel(for channel: AgentChannel) -> ToolPermissionLevel {
        switch channel {
        case .uiPanel, .system: return .full
        case .iMessage, .telegram, .iosApp: return .standard
        case .notification, .shareIngress: return .limited
        }
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(
        thread: AgentThread,
        runtime: any AgentRuntime,
        allowedTools: [AgentToolDefinition]
    ) -> String {
        let latestUserMessage = thread.messages.last(where: { $0.role == .user })?.content ?? ""
        var prompt = """
        You are Cider's AI assistant. Cider is a native macOS personal knowledge management app \
        that manages bookmarks, notes, todos, events, contacts, and files in a local vault.

        You help users search, organize, and manage their vault using tools. Be concise and helpful. \
        When asked to create or modify items, use the appropriate tools.
        """

        if runtime.kind == .process {
            prompt += """


            This runtime has direct access to the mounted vault on disk and can run local shell commands.
            Do not claim the user must enable a separate vault connector if the answer can be obtained from the local vault or `cider-cli`.
            For count questions like "how many bookmarks/folders/notes/todos/events/contacts/files/images/labels/boards do I have?", use `cider-cli status --json` first and treat that output as canonical unless the user explicitly asks for on-disk filesystem counts.
            Prefer `cider-cli` for exact counts, searches, and mutations. Fall back to `.cider` indexes next. Only use raw filesystem counts as a last resort.
            If filesystem counts differ from `cider-cli` or Cider indexes, report the `cider-cli` value as the app-authoritative count and mention the filesystem count only as a secondary caveat.
            Do not derive app-level totals by counting Markdown files or folders directly when `cider-cli` or Cider indexes can answer.
            Do not answer factual vault questions from memory alone when a current `cider-cli` query can verify the answer.
            Do not ask to enable tools unless the request truly requires an unavailable app-only capability.
            """

            if let routingHints = processRuntimeRoutingHints(for: latestUserMessage) {
                prompt += "\n\nCLI routing for this request:\n\(routingHints)"
            }
        } else if !allowedTools.isEmpty {
            let toolNames = allowedTools.map(\.name).joined(separator: ", ")
            prompt += "\n\nAvailable Cider tools: \(toolNames)"
        }

        if let agentInstructions = canonicalAgentInstructions() {
            prompt += "\n\nVault agent instructions:\n\(agentInstructions)"
        }

        let contextDesc = thread.context.contextDescription
        if !contextDesc.isEmpty {
            prompt += "\n\nCurrent context:\n\(contextDesc)"
        }

        return prompt
    }

    private func processRuntimeRoutingHints(for userMessage: String) -> String? {
        let normalized = userMessage.lowercased()
        guard !normalized.isEmpty else { return nil }

        var hints: [String] = []

        let countTerms = [
            "how many", "count", "total", "number of", "how much"
        ]
        let countEntities = [
            "bookmark", "bookmarks",
            "folder", "folders",
            "note", "notes",
            "todo", "todos",
            "task", "tasks",
            "event", "events",
            "contact", "contacts",
            "file", "files",
            "image", "images",
            "label", "labels",
            "board", "boards"
        ]
        let asksForCount = countTerms.contains(where: normalized.contains)
            && countEntities.contains(where: normalized.contains)

        let asksForRecent = [
            "recent", "latest", "newest", "most recent",
            "last added", "last saved", "last updated"
        ].contains(where: normalized.contains)
        let asksForWholeVaultRecent = [
            "most recent", "overall", "whole vault", "entire vault",
            "all time", "not just today", "not just recently"
        ].contains(where: normalized.contains)
        let requestedLimit = normalized.firstMatch(for: #"\b(\d+)\b"#).flatMap(Int.init)
        let asksForSearch = ["find", "search", "look up", "lookup", "show me", "do i have", "have any", "where is"]
            .contains(where: normalized.contains)
        let scopedEntityQueries: [(terms: [String], cliScope: String, entityLabel: String)] = [
            (["bookmark", "bookmarks", "url", "urls", "link", "links"], "@bookmarks", "bookmarks"),
            (["note", "notes"], "@notes", "notes"),
            (["todo", "todos", "task", "tasks"], "@todos", "todos"),
            (["event", "events", "calendar"], "@events", "events"),
            (["contact", "contacts", "person", "people"], "@contacts", "contacts"),
            (["file", "files", "document", "documents"], "@files", "files"),
            (["image", "images", "photo", "photos", "picture", "pictures"], "@images", "images")
        ]
        let matchedEntityScopes = scopedEntityQueries.filter { query in
            query.terms.contains(where: normalized.contains)
        }
        let asksForBookmarkFacts = normalized.contains("bookmark") || normalized.contains("url") || normalized.contains("link")
        let asksForBroadTopicLookup = [
            "what do i have about",
            "what do i have on",
            "show me what i have about",
            "show me what i have on",
            "what have i saved about",
            "everything i have about",
            "all i have about",
            "summarize my notes on",
            "summarize my bookmarks on",
            "summarize my contacts on",
            "summarize my todos on",
            "summarize my events on",
            "summarize my files on"
        ].contains(where: normalized.contains)
        let asksAboutDuplicates = [
            "do i already have this",
            "have i saved this before",
            "saved this before",
            "saved it before",
            "already saved",
            "already have this",
            "duplicate",
            "duplicates",
            "same url",
            "same link"
        ].contains(where: normalized.contains)
        let asksForBookmarkExistence = asksForBookmarkFacts || asksAboutDuplicates
        let asksAmbiguousRetrieval = asksForSearch
            && !asksForCount
            && !asksForRecent
            && !asksForBookmarkExistence
            && !asksForBroadTopicLookup
            && matchedEntityScopes.isEmpty
        let explicitlyRequestsFilesystem = ["filesystem", "on disk", "on-disk", "raw files", "files on disk"]
            .contains(where: normalized.contains)

        if asksForCount {
            hints.append("- For high-level totals, run `cider-cli status --json` first and answer from that output.")
            hints.append("- Do not replace that with manual vault file counting unless the user explicitly asks for filesystem numbers.")
        }

        if asksForRecent {
            if asksForWholeVaultRecent {
                hints.append("- For whole-vault recency questions, do not rely on the default 24-hour recent window.")
                hints.append("- Prefer `cider-cli recent --hours 87600 --json` so older items remain eligible, then preserve the user's requested limit if they gave one.")
            } else {
                hints.append("- For recent vault activity, prefer `cider-cli recent --json` and preserve any requested limit.")
            }
        }

        if asksForRecent, let requestedLimit {
            hints.append("- The user asked for \(requestedLimit) item(s); preserve that with `--limit \(requestedLimit)` when using `cider-cli recent`.")
        }

        if asksForBookmarkExistence {
            hints.append("- For bookmark existence, duplicate, or bookmark search questions, prefer `cider-cli duplicate-check \"<url>\" --json` when the user gave a URL, otherwise prefer `cider-cli bookmark search \"<query>\" --json` or `cider-cli bookmark list --json`.")
            hints.append("- If the user asks whether they already saved something and the item is not clearly a bookmark, use `cider-cli query \"<question>\" --json` to verify the current vault state before answering.")
        } else if asksForSearch && !matchedEntityScopes.isEmpty {
            let entityDescriptions = matchedEntityScopes.map(\.entityLabel).joined(separator: ", ")
            hints.append("- This looks scoped to specific entity types: \(entityDescriptions). Prefer a scoped search first, such as `cider-cli search \"\(matchedEntityScopes[0].cliScope) <topic>\" --json`, then expand with `cider-cli query \"<question>\" --json` if the request becomes cross-entity.")
            hints.append("- If the user is asking for one exact item, verify against the scoped search results before summarizing.")
        } else if asksForBroadTopicLookup {
            hints.append("- For broad topical or cross-entity questions like \"what do I have about X?\" or \"summarize my notes/bookmarks on X\", start with `cider-cli query \"<topic>\" --json`.")
            hints.append("- If the request is clearly scoped to one entity type, use the matching search path next, such as `cider-cli search \"@notes <topic>\" --json`, `@bookmarks`, `@contacts`, `@todos`, `@events`, or `@files` as appropriate.")
            hints.append("- Use the entity-specific CLI when it is a better fit than a general vault sweep; do not fall back to ad hoc filesystem inspection for topic lookups.")
        } else if asksAmbiguousRetrieval {
            hints.append("- This retrieval request is ambiguous. Start with `cider-cli query \"<question>\" --json` to sweep the vault before making assumptions about entity type or location.")
            hints.append("- If the query result is mixed or unclear, answer with the best verified result and briefly ask a clarifying follow-up instead of guessing.")
        } else if asksForSearch {
            hints.append("- For factual lookups across the vault, prefer `cider-cli query \"<question>\" --json` before ad hoc file inspection.")
        }

        if !asksForCount && !asksForRecent && !asksForSearch {
            hints.append("- If a current vault fact is needed, verify with `cider-cli query \"<question>\" --json` or another matching `cider-cli` command before answering.")
        }

        if !explicitlyRequestsFilesystem {
            hints.append("- Do not mention raw filesystem counts unless they were explicitly requested or they conflict with app/index results in a way worth surfacing.")
        }

        return hints.isEmpty ? nil : hints.joined(separator: "\n")
    }

    private func canonicalAgentInstructions() -> String? {
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        let canonicalURL = vaultRoot
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("memory")
            .appendingPathComponent("agent.md")

        if let text = try? String(contentsOf: canonicalURL, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let legacyURL = vaultRoot.appendingPathComponent("CLAUDE.md")
        if let text = try? String(contentsOf: legacyURL, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func formatReminderPrompt(_ context: AgentContext.ReminderContext) -> String {
        var prompt = "A reminder is due. Compose a friendly, conversational reminder message to send to the user.\n"
        prompt += "Title: \(context.title)\n"
        prompt += "Date: \(context.occurrence)\n"
        if !context.location.isEmpty { prompt += "Location: \(context.location)\n" }
        if !context.details.isEmpty { prompt += "Details: \(context.details)\n" }
        if context.isRecurring { prompt += "This is a recurring reminder.\n" }
        if context.minutesBefore == 0 {
            prompt += "The event is happening now.\n"
        } else if context.minutesBefore < 60 {
            prompt += "The event is in \(context.minutesBefore) minutes.\n"
        } else if context.minutesBefore < 1440 {
            prompt += "The event is in \(context.minutesBefore / 60) hour(s).\n"
        } else {
            prompt += "The event is in \(context.minutesBefore / 1440) day(s).\n"
        }
        return prompt
    }

    // MARK: - Cleanup

    /// Remove threads older than the given TTL.
    func cleanupStaleThreads(olderThan ttl: TimeInterval = 30 * 60) {
        let cutoff = Date().addingTimeInterval(-ttl)
        let staleIDs = threads.filter { $0.value.updatedAt < cutoff }.map(\.key)
        for id in staleIDs {
            if let thread = threads.removeValue(forKey: id) {
                threadsByKey.removeValue(forKey: thread.externalKey)
            }
        }
        if !staleIDs.isEmpty {
            logger.debug("Cleaned up \(staleIDs.count) stale threads")
        }
    }

}

private extension String {
    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[matchRange])
    }
}

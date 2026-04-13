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

    // Current provider (set via setProvider)
    private var provider: (any AgentProvider)?

    // Active threads by ID
    private var threads: [UUID: AgentThread] = [:]

    // Thread lookup by external key
    private var threadsByKey: [String: UUID] = [:]

    /// Maximum tool call rounds per conversation turn
    private let maxToolRounds = 5

    // MARK: - Configuration

    func setProvider(_ provider: any AgentProvider) {
        self.provider = provider
    }

    // MARK: - Handle Message

    /// Process an inbound message from any channel.
    func handleMessage(_ envelope: AgentEnvelope) async throws -> AgentResponse {
        guard let provider else {
            throw AgentError.providerUnavailable
        }

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
        let systemPrompt = buildSystemPrompt(thread: thread)

        // Run the tool loop
        let response = try await runConversationLoop(
            provider: provider,
            systemPrompt: systemPrompt,
            messages: thread.messages,
            allowedTools: allowedTools,
            allowedToolNames: allowedToolNames
        )

        thread.append(.assistant(response.text))
        logger.info("Handled message on \(envelope.channel.rawValue): \(response.toolCallsMade.count) tool calls")
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
                context: reminderAgentContext,
                senderID: nil,
                senderDisplayName: nil
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
        provider: any AgentProvider,
        systemPrompt: String,
        messages: [AgentMessage],
        allowedTools: [AgentToolDefinition],
        allowedToolNames: Set<String>
    ) async throws -> AgentResponse {
        var conversationMessages = messages
        var allToolCalls: [AgentToolCall] = []

        for round in 0..<maxToolRounds {
            let providerResponse = try await provider.generate(
                systemPrompt: systemPrompt,
                messages: conversationMessages,
                tools: allowedTools
            )

            if providerResponse.toolRequests.isEmpty {
                return AgentResponse(text: providerResponse.text, toolCallsMade: allToolCalls)
            }

            logger.debug("Tool round \(round + 1): \(providerResponse.toolRequests.count) requests")

            for request in providerResponse.toolRequests {
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
            return "ui:\(envelope.threadID.uuidString)"
        case .iMessage:
            return "imessage:\(envelope.senderID ?? "unknown")"
        case .system:
            return "system:\(envelope.threadID.uuidString)"
        case .notification:
            return "notification:\(envelope.threadID.uuidString)"
        }
    }

    private func permissionLevel(for channel: AgentChannel) -> ToolPermissionLevel {
        switch channel {
        case .uiPanel, .system: return .full
        case .iMessage: return .standard
        case .notification: return .limited
        }
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(thread: AgentThread) -> String {
        var prompt = """
        You are Cider's AI assistant. Cider is a native macOS personal knowledge management app \
        that manages bookmarks, notes, todos, events, contacts, and files in a local vault.

        You help users search, organize, and manage their vault using tools. Be concise and helpful. \
        When asked to create or modify items, use the appropriate tools.
        """

        let contextDesc = thread.context.contextDescription
        if !contextDesc.isEmpty {
            prompt += "\n\nCurrent context:\n\(contextDesc)"
        }

        return prompt
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

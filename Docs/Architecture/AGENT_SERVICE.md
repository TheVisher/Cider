# Agent Service Architecture

## Table of Contents

1. [Overview](#overview) — Line 12
2. [Current State](#current-state) — Line 32
3. [Target Architecture](#target-architecture) — Line 60
4. [Agent Orchestrator](#agent-orchestrator) — Line 95
5. [Durable Wake Jobs](#durable-wake-jobs) — Line 175
6. [Input Channels](#input-channels) — Line 215
7. [Channel Security](#channel-security) — Line 285
8. [Provider Abstraction](#provider-abstraction) — Line 325
9. [Reminder Wake Flow](#reminder-wake-flow) — Line 410
10. [Conversation Threading](#conversation-threading) — Line 455
11. [Tool Registry](#tool-registry) — Line 500
12. [Implementation Phases](#implementation-phases) — Line 555
13. [Open Questions](#open-questions) — Line 650

---

## Overview

Cider's AI assistant currently lives inside the UI chat panel. It responds when the user types in the panel and has no way to act autonomously. This doc describes the architecture for an **Agent Service** — a headless orchestration layer that:

- Runs inside Cider as a background service (not a terminal session, not a child process)
- Can be woken by Cider (reminders, scheduled checks, vault events) or by the user (iMessage, chat panel)
- Manages conversations across multiple input channels (iMessage, UI, future: Shortcuts, notifications)
- Is model-agnostic — user picks Claude API, OpenAI API, Gemini API, Apple Intelligence, or local MLX
- Handles tool execution, conversation state, and context injection identically regardless of input channel
- Uses durable job persistence for wake events so reminders survive crashes and delivery failures

The agent is not a separate process. It is a Swift service inside Cider's process, same as `VaultBookmarkService` or `DateCardStorage`. Cider owns its lifecycle.

---

## Current State

### What exists

| Component | File | Role |
|-----------|------|------|
| `AIAssistantProvider` | `Services/AI/AIAssistantProvider.swift` | Protocol: `streamResponse(messages:context:)` → `AsyncThrowingStream<String>` |
| `AIAssistantViewModel` | `ViewModels/AIAssistantViewModel.swift` | Manages conversation state, streaming, typewriter effect, persistence |
| `FoundationModelsProvider` | `Services/AI/FoundationModelsProvider.swift` | Apple Intelligence backend. Tool calling via `LanguageModelSession`. 4K context. |
| `MLXProvider` | `Services/AI/MLXProvider.swift` | Local Qwen 2.5 via MLX Swift. Manual tool loop (parse → execute → re-prompt, max 3 rounds). 32K context. |
| `AIAssistantTools.swift` | `Services/AI/AIAssistantTools.swift` | 25 tool structs conforming to `Tool` protocol (Foundation Models) |
| `MLXToolExecutor` | `Services/AI/MLXToolExecutor.swift` | Mirror implementations for MLX (switch dispatch) |
| `MLXToolDefinitions` | `Services/AI/MLXToolDefinitions.swift` | JSON schema for MLX system prompt |
| `AIConversationStorage` | `Services/AI/AIConversationStorage.swift` | JSONL persistence per conversation |
| `AIAssistantPanelView` | `Views/AIAssistant/AIAssistantPanelView.swift` | SwiftUI chat UI |
| `ReminderReconciler` | `Services/ReminderReconciler.swift` | Periodic reconciliation — launch, wake, tz, day rollover |
| `ReminderOutbox` | `Services/ReminderOutbox.swift` | Filesystem outbox for agent reminders (interim, replaced by orchestrator in Phase 3) |
| `DateCardNotificationService` | `Services/DateCardNotificationService.swift` | Deterministic local notifications, multi-offset, recurring-safe |

### What's wrong

1. **UI-coupled** — The conversation loop lives in `AIAssistantViewModel`, which is a `@MainActor ObservableObject` tightly bound to the chat panel SwiftUI view. No way to run a conversation without the panel open.
2. **No wake mechanism** — Nothing can trigger the AI to act autonomously. It only responds to user typing in the panel.
3. **No input routing** — There's one input (the text field) and one output (the chat bubble). No way to receive from iMessage or push to iMessage.
4. **Tool definitions are split** — Foundation Models uses `@Generable` struct conformances. MLX uses JSON schemas + a separate executor. Adding a tool means editing 3 files.
5. **No thread/conversation routing** — All messages go to one conversation. No concept of "this is a reminder thread" vs "this is a general question."
6. **No channel security** — No concept of which tools are available on which channel, no allowlisting for iMessage senders.

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Cider App Process                                               │
│                                                                 │
│  ┌──────────────┐    ┌────────────────────────────────────────┐ │
│  │ Input        │    │ Agent Orchestrator (actor)             │ │
│  │ Channels     │───▶│                                        │ │
│  │              │    │  ┌──────────┐ ┌──────┐ ┌───────────┐  │ │
│  │ • UI Panel   │    │  │ Thread   │ │ Tool │ │ Channel   │  │ │
│  │ • iMessage   │    │  │ Manager  │ │ Reg. │ │ Security  │  │ │
│  │ • Wake Jobs  │    │  └──────────┘ └──────┘ └───────────┘  │ │
│  │ • Vault Evts │    │                                        │ │
│  └──────────────┘    │  ┌─────────────────────────────────┐   │ │
│                      │  │ Provider (swappable)            │   │ │
│  ┌──────────────┐    │  │ • Claude API    • OpenAI API    │   │ │
│  │ Output       │◀───│  │ • Gemini API    • Apple Intell. │   │ │
│  │ Channels     │    │  │ • MLX Local                     │   │ │
│  │              │    │  └─────────────────────────────────┘   │ │
│  │ • UI Panel   │    └────────────────────────────────────────┘ │
│  │ • iMessage   │                                               │
│  │ • Notif.     │    ┌────────────────────────────────────────┐ │
│  └──────────────┘    │ Wake Job Store (SQLite)                │ │
│                      │ Persisted delivery attempts + retries  │ │
│                      └────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Cider Services (existing)                                │   │
│  │ DateCardStorage, VaultBookmarkService, NotesStorage,      │   │
│  │ ReminderReconciler, etc.                                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

The Agent Orchestrator is a Swift `actor` (not `@MainActor`) — it handles iMessage I/O, API calls, and wake jobs without blocking the UI. Only UI adapter code runs on the main actor. The Wake Job Store ensures reminders survive crashes and delivery failures.

---

## Agent Orchestrator

The core of the system. Receives messages from any input channel, routes them through the configured provider, executes tool calls (with channel-appropriate permissions), and delivers responses to the appropriate output channel.

**Important:** The orchestrator is a Swift `actor`, not `@MainActor`. This prevents API calls, iMessage sends, and tool execution from blocking the UI. Only the UI adapter layer (`AIAssistantViewModel`) bridges to `@MainActor` for SwiftUI updates.

```swift
actor AgentOrchestrator {
    static let shared = AgentOrchestrator()

    // Current provider (user-configurable)
    private var provider: AgentProvider

    // Active conversations by thread ID
    private var threads: [UUID: AgentThread] = [:]

    // Tool registry (unified, provider-agnostic)
    private let toolRegistry = AgentToolRegistry.shared

    // Channel security policy
    private let channelPolicy = AgentChannelPolicy.shared

    // Durable wake job store
    private let wakeJobStore = AgentWakeJobStore.shared

    /// Process an inbound message from any channel.
    func handleMessage(
        _ text: String,
        threadID: UUID,
        channel: AgentChannel,
        context: AgentContext = .empty
    ) async throws {
        // Check sender authorization for this channel
        guard channelPolicy.isAuthorized(channel: channel) else {
            throw AgentError.unauthorized
        }

        let thread = getOrCreateThread(id: threadID, channel: channel)
        thread.append(.user(text))

        // Get tools allowed for this channel
        let allowedTools = channelPolicy.allowedTools(for: channel)

        // Build messages for provider
        let systemPrompt = buildSystemPrompt(thread: thread, context: context)
        let messages = thread.messagesForProvider()

        // Run the orchestrator-owned tool loop
        let response = try await runConversationLoop(
            systemPrompt: systemPrompt,
            messages: messages,
            allowedTools: allowedTools
        )

        // Deliver response to the originating channel
        thread.append(.assistant(response.text))
        try await deliver(response.text, to: channel, threadID: threadID)
        thread.save()
    }

    /// Wake the agent for a specific purpose (no user message).
    /// Creates a durable wake job, then attempts delivery.
    func wake(purpose: AgentWakePurpose) async {
        // Persist the wake job FIRST — survives crash
        let job = wakeJobStore.create(purpose: purpose)

        do {
            try await executeWakeJob(job)
            wakeJobStore.markCompleted(job.id)
        } catch {
            wakeJobStore.markFailed(job.id, error: error.localizedDescription)
            // Will be retried on next reconciliation cycle
        }
    }

    /// Retry any failed or pending wake jobs.
    /// Called by ReminderReconciler on launch, wake, day rollover.
    func retryPendingWakeJobs() async {
        let pending = wakeJobStore.pendingJobs()
        for job in pending {
            do {
                try await executeWakeJob(job)
                wakeJobStore.markCompleted(job.id)
            } catch {
                wakeJobStore.markFailed(job.id, error: error.localizedDescription)
            }
        }
    }

    // MARK: - Tool Loop (orchestrator-owned)

    /// The orchestrator owns the tool execution loop, not the provider.
    /// Provider requests tool calls → orchestrator checks permissions →
    /// executes → feeds results back → provider continues.
    private func runConversationLoop(
        systemPrompt: String,
        messages: [AgentMessage],
        allowedTools: [AgentToolDefinition],
        maxRounds: Int = 5
    ) async throws -> AgentResponse {
        var conversationMessages = messages
        var allToolCalls: [AgentToolCall] = []

        for _ in 0..<maxRounds {
            let providerResponse = try await provider.respond(
                systemPrompt: systemPrompt,
                messages: conversationMessages,
                tools: allowedTools
            )

            if providerResponse.toolRequests.isEmpty {
                // No tool calls — final response
                return AgentResponse(text: providerResponse.text, toolCallsMade: allToolCalls)
            }

            // Execute requested tool calls
            for request in providerResponse.toolRequests {
                let result = await toolRegistry.execute(
                    name: request.name,
                    arguments: request.arguments
                )
                allToolCalls.append(AgentToolCall(
                    name: request.name,
                    arguments: request.arguments,
                    result: result
                ))
                conversationMessages.append(.toolResult(name: request.name, result: result))
            }
        }

        return AgentResponse(text: "I ran out of tool rounds. Here's what I found so far.", toolCallsMade: allToolCalls)
    }
}
```

### Key design decisions

- **Swift `actor`** — Not `@MainActor`. API calls, iMessage I/O, and tool execution happen off the main thread. UI adapters bridge to main actor as needed.
- **Orchestrator owns tool loop** — The provider requests tool calls, the orchestrator checks permissions and executes them. This keeps policy (which tools are allowed per channel) in one place, not spread across providers.
- **Durable wake jobs** — `wake()` persists the job to SQLite before attempting delivery. If delivery fails (provider error, iMessage failure, crash), the job is retried on the next reconciliation cycle.
- **Thread-based** — Each conversation gets a `UUID` thread. The reminder thread for "Pay Rent" is different from the general chat thread.

---

## Durable Wake Jobs

Wake jobs are persisted to SQLite so reminders survive crashes, provider failures, and iMessage send errors. This replaces the filesystem outbox approach with a proper delivery state machine.

```swift
struct AgentWakeJob: Identifiable {
    let id: UUID
    let purpose: AgentWakePurpose
    let createdAt: Date
    var status: WakeJobStatus
    var lastAttemptAt: Date?
    var attemptCount: Int
    var lastError: String?
    var threadID: UUID?  // Set after delivery creates a thread
}

enum WakeJobStatus: String, Codable {
    case pending     // Not yet attempted
    case delivered   // Successfully sent to user
    case failed      // Last attempt failed, will retry
    case expired     // Past retry window, abandoned
}
```

### Job lifecycle

```
1. ReminderReconciler determines reminder is due
2. Calls AgentOrchestrator.wake(.deliverReminder(context))
3. Orchestrator creates WakeJob with status = .pending in SQLite
4. Orchestrator attempts delivery (provider → iMessage send)
5a. Success → status = .delivered, threadID stored for reply routing
5b. Failure → status = .failed, error logged, attemptCount++
6. On next reconciliation, retryPendingWakeJobs() picks up failed jobs
7. After N failures or past TTL → status = .expired (falls back to local notification)
```

### Deduplication

Wake jobs use a deterministic key: `(cardID, occurrence, minutesBefore)`. Before creating a new job, check if one already exists for the same key. This replaces the triple-source dedup in the outbox system.

```swift
final class AgentWakeJobStore {
    static let shared = AgentWakeJobStore()

    func create(purpose: AgentWakePurpose) -> AgentWakeJob {
        let key = purpose.deduplicationKey
        // Return existing job if one exists for this key
        if let existing = findByKey(key), existing.status != .expired {
            return existing
        }
        // Create and persist new job
        let job = AgentWakeJob(id: UUID(), purpose: purpose, ...)
        persist(job)
        return job
    }

    func pendingJobs() -> [AgentWakeJob] {
        // Jobs with status .pending or .failed where attemptCount < maxRetries
    }

    func markCompleted(_ id: UUID) { ... }
    func markFailed(_ id: UUID, error: String) { ... }
}
```

---

## Input Channels

```swift
enum AgentChannel: String, Codable {
    case uiPanel       // User typed in the AI chat panel
    case iMessage      // User texted the agent's iMessage address
    case system        // Cider triggered the agent internally (reminders, events)
    case notification   // User replied to a notification action
}
```

### UI Panel (existing, refactored)

`AIAssistantViewModel` becomes a thin `@MainActor` wrapper around `AgentOrchestrator`:

```swift
// Before: ViewModel owns conversation state and provider
func send(_ text: String) {
    provider.streamResponse(messages: messages, context: context)
}

// After: ViewModel delegates to orchestrator
func send(_ text: String) {
    Task {
        try await AgentOrchestrator.shared.handleMessage(
            text,
            threadID: currentThreadID,
            channel: .uiPanel,
            context: currentContext
        )
    }
}
```

The ViewModel still handles streaming display, typewriter effect, and UI state. But conversation logic, tool execution, and provider management move to the orchestrator. The orchestrator provides an `AsyncStream` for the ViewModel to observe for streaming updates.

### iMessage

Cider integrates iMessage directly (not via Claude Code's plugin).

**Outbound (sending):** AppleScript via `tell application "Messages"`. Cider already has the Apple Events entitlement (`Cider.entitlements`) and established AppleScript patterns in `ActiveBrowserCaptureService.swift`. This is viable and straightforward for v1.

**Inbound (receiving):** This is the harder problem. Options:

- **`chat.db` polling** — Read the Messages SQLite database directly. Works but is brittle: SIP-protected on some macOS versions, schema changes between releases, and polling introduces latency. **Acceptable as v1 with caveats.** Use file system events on `chat.db` to trigger reads instead of interval polling.
- **ScriptingBridge** — `SBApplication(bundleIdentifier: "com.apple.iChat")` can enumerate chats and messages but has no event/notification API for new messages. Not better than polling.
- **Private APIs / Notification listeners** — Some apps use `IMDaemonListener` or `CBDaemonConnection`. Fragile, undocumented, breaks between OS versions. Not recommended.

**Recommendation:** AppleScript for outbound, `chat.db` FSEvents-triggered reads for inbound. Both are opt-in (user explicitly enables iMessage agent in settings). Document this as a temporary bridge — a proper Messages extension or Apple-supported API would be the long-term path if Apple opens one up.

**Important:** `chat.db` polling should be a separate, isolated service (`iMessageBridge`) that feeds messages to the orchestrator. The orchestrator should not know or care about chat.db internals.

### Notification Replies

Current notification categories include "Open" and "Mark Complete" (recurring cards only have "Open"). To support text replies from notifications, add a `UNTextInputNotificationAction`:

```swift
let replyAction = UNTextInputNotificationAction(
    identifier: "REPLY",
    title: "Reply",
    options: [],
    textInputButtonTitle: "Send",
    textInputPlaceholder: "Snooze, dismiss, or ask a question..."
)
```

When the user types a reply in the notification banner, route it to the orchestrator:

```swift
case "REPLY":
    if let textResponse = response as? UNTextInputNotificationResponse {
        Task {
            try await AgentOrchestrator.shared.handleMessage(
                textResponse.userInputText,
                threadID: reminderThreadID(for: dateCardID),
                channel: .notification,
                context: .reminder(...)
            )
        }
    }
```

---

## Channel Security

Different input channels have different trust levels. iMessage is a remote-control surface — anyone who texts the agent's number could invoke vault operations unless we gate it.

```swift
struct AgentChannelPolicy {
    static let shared = AgentChannelPolicy()

    /// Allowed iMessage senders (phone numbers / Apple IDs)
    var iMessageAllowlist: [String] = []

    /// Tool permissions per channel
    private let channelToolPermissions: [AgentChannel: ToolPermissionLevel] = [
        .uiPanel: .full,           // User is at the keyboard — all tools
        .system: .full,            // Cider-initiated — all tools
        .notification: .limited,    // Notification reply — snooze/dismiss only
        .iMessage: .standard       // Remote — read + safe writes, no delete/move without confirm
    ]

    func isAuthorized(channel: AgentChannel) -> Bool {
        switch channel {
        case .iMessage:
            // Check sender against allowlist
            return true // TODO: implement sender extraction + check
        default:
            return true
        }
    }

    func allowedTools(for channel: AgentChannel) -> [AgentToolDefinition] {
        let level = channelToolPermissions[channel] ?? .limited
        return AgentToolRegistry.shared.tools.filter { tool in
            switch level {
            case .full:
                return true
            case .standard:
                // Exclude destructive tools unless user confirms
                return !tool.requiresConfirmation
            case .limited:
                // Only reminder-specific tools
                return tool.categories.contains(.reminder)
            }
        }
    }
}

enum ToolPermissionLevel {
    case full        // All tools, no restrictions
    case standard    // Read + safe writes, destructive needs confirmation
    case limited     // Only tools in specific categories
}
```

### Per-tool metadata

Each `AgentToolDefinition` includes security metadata:

```swift
struct AgentToolDefinition {
    let name: String
    let description: String
    let parameters: [AgentToolParameter]
    let categories: Set<ToolCategory>           // .reminder, .vault, .search, etc.
    let requiresConfirmation: Bool              // If true, agent must confirm with user before executing
    let execute: @Sendable ([String: Any]) async throws -> String
}

enum ToolCategory: String {
    case search      // Read-only queries
    case vaultRead   // Reading vault contents
    case vaultWrite  // Creating/modifying items
    case vaultDelete // Deleting items
    case reminder    // Reminder-specific (create, snooze, dismiss)
    case system      // App-level actions
}
```

---

## Provider Abstraction

The orchestrator owns the tool execution loop. Providers are responsible only for:
- Receiving a system prompt + messages + tool definitions
- Generating text or requesting tool calls
- Reporting their capabilities

Providers do NOT execute tools, manage retries, or enforce permissions. That's all orchestrator responsibility.

```swift
protocol AgentProvider: Sendable {
    var isAvailable: Bool { get }
    var displayName: String { get }
    var capabilities: AgentProviderCapabilities { get }

    /// Generate a response. May include tool call requests.
    /// The orchestrator handles tool execution and feeds results back.
    func generate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) async throws -> AgentProviderResponse

    /// Streaming variant for UI display.
    func streamGenerate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) -> AsyncThrowingStream<AgentProviderStreamEvent, Error>

    func resetSession()
}

struct AgentProviderCapabilities {
    let supportsToolCalling: Bool
    let supportsStreaming: Bool
    let maxContextTokens: Int
    let estimatedTokensPerChar: Double  // For context window management
}

/// What the provider returns — either text or tool call requests (or both).
struct AgentProviderResponse {
    let text: String
    let toolRequests: [AgentToolRequest]  // Empty if no tools requested
}

struct AgentToolRequest {
    let name: String
    let arguments: [String: Any]
}

enum AgentProviderStreamEvent {
    case textDelta(String)
    case toolCallRequest(AgentToolRequest)
    case done
}
```

### Provider implementations

| Provider | Model | Tool calling | Context window | Notes |
|----------|-------|-------------|----------------|-------|
| `FoundationModelsAgentProvider` | Apple Intelligence | Native via `LanguageModelSession` | 4K | Needs adapter for `@Generable` tool format |
| `MLXAgentProvider` | Qwen 2.5+ (local) | Prompt-based `<tool_call>` parsing | 32K | Existing pattern, extracted from MLXProvider |
| `ClaudeAPIAgentProvider` | Claude (API) | Native tool_use | 200K | Anthropic Swift SDK or raw HTTP |
| `OpenAIAPIAgentProvider` | GPT-4o/o1 (API) | Native function calling | 128K | Raw HTTP (no official Swift SDK) |
| `GeminiAPIAgentProvider` | Gemini (API) | Native function declarations | 1M | Google AI Swift SDK |

### Per-provider configuration

Each provider needs its own config, not a shared `aiAPIKey` field:

```swift
// In CiderConfig
var aiProvider: AIProviderType = .appleIntelligence

// Per-provider settings
var claudeAPIKey: String?
var claudeModel: String?          // e.g., "claude-sonnet-4-20250514"
var claudeBaseURL: String?        // Custom endpoint

var openAIAPIKey: String?
var openAIModel: String?          // e.g., "gpt-4o"
var openAIBaseURL: String?        // For Azure OpenAI or proxies

var geminiAPIKey: String?
var geminiModel: String?          // e.g., "gemini-2.5-pro"

var mlxModelName: String?         // e.g., "Qwen/Qwen2.5-7B-Instruct"
```

---

## Reminder Wake Flow

This is how Cider wakes the agent for reminders — the specific use case that motivated this architecture.

```
1. ReminderReconciler fires (launch, wake, midnight, vault change)
2. Reconciler checks DateCards with due reminders
3. For each due reminder:
   a. Local notification → macOS notification center (already built)
   b. Agent wake → AgentOrchestrator.shared.wake(.deliverReminder(context))
4. Orchestrator creates durable WakeJob in SQLite (status: pending)
5. Orchestrator attempts delivery:
   a. Sends reminder context to provider
   b. Provider generates conversational message: "Hey! Rent is due tomorrow."
   c. Orchestrator sends via iMessage (AppleScript)
6. Success → WakeJob status = .delivered, threadID stored
7. Failure → WakeJob status = .failed, retried on next reconciliation
8. User replies: "Snooze until the morning"
9. iMessage bridge receives the reply
10. Routes to the same thread (matched by deterministic thread key)
11. Provider processes: "Got it, I'll remind you tomorrow at 9 AM."
12. Orchestrator executes CreateReminderTool (permitted on iMessage channel)
13. Orchestrator delivers confirmation via iMessage
```

### Thread matching for replies

Reminder threads use **deterministic external keys** instead of random UUIDs for routing:

```swift
// Thread key for a reminder conversation
"reminder:\(cardID):\(compactISO(occurrence))"

// Thread key for general iMessage conversation with a sender
"imessage:\(senderPhoneOrAppleID)"
```

When an iMessage arrives:
1. Check if there's an active reminder thread for this sender (within TTL)
2. If yes → route to that thread (the user is replying to a reminder)
3. If no → route to the sender's general thread

TTL for reminder threads: 30 minutes after last message. After that, new messages start fresh.

### Wake purposes

```swift
enum AgentWakePurpose: Codable {
    case deliverReminder(ReminderContext)
    case dailyDigest
    case vaultEvent(VaultEvent)
    case scheduledCheck(String)

    /// Deterministic key for deduplication.
    var deduplicationKey: String {
        switch self {
        case .deliverReminder(let ctx):
            return "reminder:\(ctx.cardID):\(ctx.occurrence.timeIntervalSince1970):\(ctx.minutesBefore)"
        case .dailyDigest:
            let day = Calendar.current.startOfDay(for: Date())
            return "digest:\(day.timeIntervalSince1970)"
        case .vaultEvent(let event):
            return "vault:\(event.id)"
        case .scheduledCheck(let name):
            return "check:\(name):\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        }
    }
}

struct ReminderContext: Codable {
    let cardID: UUID
    let title: String
    let occurrence: Date
    let minutesBefore: Int
    let isRecurring: Bool
    let details: String
    let location: String
}
```

---

## Conversation Threading

Each conversation with the agent is a **thread** — an ordered list of messages with a channel, context, and persistence.

```swift
struct AgentThread {
    let id: UUID
    let externalKey: String          // Deterministic key for routing (e.g., "reminder:cardID:date")
    let channel: AgentChannel
    var messages: [AgentMessage]
    var context: AgentContext
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]   // e.g., "reminderCardID": "..."

    func messagesForProvider(maxTokens: Int) -> [AgentMessage] {
        // Trim to fit context window, keeping system + recent messages
        // Use provider's estimatedTokensPerChar for budget
    }

    func save() {
        AgentConversationStorage.shared.save(thread: self)
    }
}
```

### Thread types

| Type | Created by | External key pattern | Lifetime | Example |
|------|-----------|---------------------|----------|---------|
| General (UI) | User opens chat | `"ui:panel"` | Until cleared | "What did I save today?" |
| General (iMessage) | User texts agent | `"imessage:{sender}"` | Ongoing | "Save this link for me" |
| Reminder | Reconciler wake | `"reminder:{cardID}:{date}"` | 30-min TTL after last message | "Rent is due" → "Snooze 1 hour" |
| Digest | Daily schedule | `"digest:{date}"` | Single message, no reply expected | "Here's your daily summary" |
| Event | Vault trigger | `"vault:{eventID}"` | Short-lived | "You saved 5 recipes, want a folder?" |

---

## Tool Registry

Unified tool definitions that work across all providers. Tools are `async throws` with structured results and security metadata.

```swift
struct AgentToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: [AgentToolParameter]
    let categories: Set<ToolCategory>
    let requiresConfirmation: Bool
    let execute: @Sendable ([String: Any]) async throws -> String
}

struct AgentToolParameter: Sendable {
    let name: String
    let type: AgentToolParameterType  // string, integer, boolean, array
    let description: String
    let required: Bool
}

actor AgentToolRegistry {
    static let shared = AgentToolRegistry()
    private(set) var tools: [AgentToolDefinition] = []

    func register(_ tool: AgentToolDefinition) { tools.append(tool) }

    func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            return "Unknown tool: \(name)"
        }
        return try await tool.execute(arguments)
    }

    /// Generate provider-specific tool format.
    func jsonSchemas() -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters.map { p in
                    ["name": p.name, "type": p.type.rawValue, "description": p.description, "required": p.required]
                }
            ]
        }
    }
}
```

Each provider converts `AgentToolDefinition` to its native format:
- Foundation Models → `@Generable` struct (may need codegen or runtime adapter)
- MLX → JSON schema string (from `jsonSchemas()`)
- Claude API → `tools` parameter in API request
- OpenAI → `functions` parameter
- Gemini → `function_declarations`

Adding a new tool = one `AgentToolRegistry.shared.register(...)` call.

---

## Implementation Phases

### Phase 1: Extract Orchestrator + Unified Tool Contract

**Goal:** Decouple conversation logic from the ViewModel. Define the provider and tool interfaces. No new features, no new channels.

- Create `AgentOrchestrator` as a Swift `actor` with `handleMessage()` and thread management
- Define `AgentProvider` protocol (provider returns tool requests, orchestrator executes)
- Define `AgentToolDefinition` with categories and security metadata
- Create `AgentToolRegistry` — register all 25 existing tools once
- Adapt `FoundationModelsProvider` and `MLXProvider` to conform to `AgentProvider`
- Refactor `AIAssistantViewModel` to delegate to orchestrator
- Chat panel works exactly as before — just plumbed differently underneath

**Files:** ~6 new, ~4 modified. No UI changes. No new features.

### Phase 2: Durable Wake Jobs + Reminder Delivery State

**Goal:** Wake jobs persist to SQLite. Reminders survive crashes and delivery failures. Keep current outbox as fallback until parity is proven.

- Create `AgentWakeJobStore` (SQLite table: `wake_jobs`)
- Add `wake(purpose:)` and `retryPendingWakeJobs()` to orchestrator
- Wire `ReminderReconciler` to call `wake(.deliverReminder(...))` in addition to current outbox
- Add deduplication via deterministic keys
- Add retry logic with max attempts and TTL-based expiry
- Keep `ReminderOutbox` as fallback — remove only after agent delivery is proven reliable

**Files:** ~2 new, ~2 modified. Reminders become durable.

### Phase 3: Add API Providers + Settings

**Goal:** Users can choose Claude, OpenAI, or Gemini as their AI backend. Per-provider config.

- Implement `ClaudeAPIAgentProvider` (Anthropic Swift SDK or raw HTTP)
- Implement `OpenAIAPIAgentProvider` (raw HTTP)
- Implement `GeminiAPIAgentProvider` (Google AI Swift SDK or raw HTTP)
- Add per-provider API key and model fields to CiderConfig
- Add model picker in settings UI (extend existing provider switcher)
- Add token usage tracking and cost display for API providers

**Files:** ~3 new provider files, ~3 modified (config, settings UI, provider picker).

### Phase 4: iMessage Channel + Channel Security

**Goal:** The agent can send and receive iMessages. Senders are allowlisted. Tools are permission-gated per channel.

- Implement `iMessageBridge` — AppleScript outbound, chat.db FSEvents inbound
- Add `AgentChannelPolicy` with allowlist and per-channel tool permissions
- Add per-tool categories and `requiresConfirmation` metadata
- Add iMessage sender configuration in settings (allowlist management)
- Wire inbound messages → orchestrator → outbound reply
- Reminder wake jobs now deliver via iMessage through the orchestrator

**Files:** ~4 new, ~3 modified.

### Phase 5: Advanced Features

- **Notification text replies** — Add `UNTextInputNotificationAction` for inline replies to reminder notifications
- **Daily digest messages** — Reconciler composes and sends a morning summary
- **Proactive vault suggestions** — "You saved 5 recipes today, want me to organize them?"
- **Conversation threading in UI** — Multiple threads visible in the chat panel
- **Siri / Shortcuts integration** — `AppIntent` conformances that route through the orchestrator
- **Privacy consent** — Clear opt-in for cloud providers, data-sent indicators, local-only mode

---

## Open Questions

1. **Foundation Models tool adapter** — Apple's `@Generable` structs are compile-time. Can we generate `Tool` conformances at runtime from `AgentToolDefinition`, or do we need a code-generation step? If not feasible, Foundation Models may need to keep its own struct-based tool definitions alongside the unified registry.

2. **Context window management** — Each provider has a different context limit (4K to 1M). The orchestrator needs a per-provider strategy for trimming conversation history. Current approach (summarize when approaching the limit) works for local models but may be wasteful for 200K+ context windows.

3. **Rate limiting for API providers** — Claude/OpenAI/Gemini have rate limits and costs. Need a token budget tracker and user-facing usage display. Should the orchestrator refuse to wake for non-critical purposes when the budget is exhausted?

4. **Privacy** — API providers send vault data to external servers. Need clear user consent, opt-in per provider, and possibly a "local-only mode" that restricts to Apple Intelligence + MLX. Show a data-sent indicator in the UI.

5. **Multi-model routing** — Could use a cheap/fast model for simple tasks (snooze, dismiss) and a capable model for complex ones (organize my vault). Is this worth the complexity in v1?

6. **iMessage reliability** — `chat.db` polling + AppleScript sending is functional but brittle. If Apple ever ships a proper Messages framework for macOS, migrate to it. Until then, document the fragility and make the bridge easily replaceable.

7. **Concurrent wake jobs** — If multiple reminders fire simultaneously, the orchestrator needs to handle concurrent `wake()` calls without races. The `actor` model handles this naturally, but provider rate limits may cause queuing.

8. **Attachments / media** — Current tools are text-only. Future: sending images (e.g., bookmark thumbnails in reminder messages), receiving photos (e.g., "save this screenshot"), voice messages.

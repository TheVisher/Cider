# Agent Service Architecture

## Table of Contents

1. [Overview](#overview) — Line 12
2. [Current State](#current-state) — Line 30
3. [Target Architecture](#target-architecture) — Line 55
4. [Agent Orchestrator](#agent-orchestrator) — Line 85
5. [Input Channels](#input-channels) — Line 140
6. [Provider Abstraction](#provider-abstraction) — Line 185
7. [Reminder Wake Flow](#reminder-wake-flow) — Line 235
8. [Conversation Threading](#conversation-threading) — Line 275
9. [Tool Registry](#tool-registry) — Line 315
10. [Implementation Phases](#implementation-phases) — Line 350
11. [Open Questions](#open-questions) — Line 430

---

## Overview

Cider's AI assistant currently lives inside the UI chat panel. It responds when the user types in the panel and has no way to act autonomously. This doc describes the architecture for an **Agent Service** — a headless orchestration layer that:

- Runs inside Cider as a background service (not a terminal session, not a child process)
- Can be woken by Cider (reminders, scheduled checks, vault events) or by the user (iMessage, chat panel)
- Manages conversations across multiple input channels (iMessage, UI, future: Shortcuts, notifications)
- Is model-agnostic — user picks Claude API, OpenAI API, Gemini API, Apple Intelligence, or local MLX
- Handles tool execution, conversation state, and context injection identically regardless of input channel

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

### What's wrong

1. **UI-coupled** — The conversation loop lives in `AIAssistantViewModel`, which is a `@MainActor ObservableObject` tightly bound to the chat panel SwiftUI view. No way to run a conversation without the panel open.
2. **No wake mechanism** — Nothing can trigger the AI to act autonomously. It only responds to user typing in the panel.
3. **No input routing** — There's one input (the text field) and one output (the chat bubble). No way to receive from iMessage or push to iMessage.
4. **Tool definitions are split** — Foundation Models uses `@Generable` struct conformances. MLX uses JSON schemas + a separate executor. Adding a tool means editing 3 files.
5. **No thread/conversation routing** — All messages go to one conversation. No concept of "this is a reminder thread" vs "this is a general question."

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Cider App Process                                           │
│                                                             │
│  ┌──────────────┐    ┌──────────────────────────────────┐   │
│  │ Input        │    │ Agent Orchestrator                │   │
│  │ Channels     │───▶│                                  │   │
│  │              │    │  ┌─────────────┐  ┌───────────┐  │   │
│  │ • UI Panel   │    │  │ Conversation│  │ Tool      │  │   │
│  │ • iMessage   │    │  │ Manager     │  │ Registry  │  │   │
│  │ • Reminders  │    │  └─────────────┘  └───────────┘  │   │
│  │ • Vault Evts │    │                                  │   │
│  └──────────────┘    │  ┌─────────────────────────────┐ │   │
│                      │  │ Provider (swappable)        │ │   │
│  ┌──────────────┐    │  │ • Claude API                │ │   │
│  │ Output       │◀───│  │ • OpenAI API                │ │   │
│  │ Channels     │    │  │ • Gemini API                │ │   │
│  │              │    │  │ • Apple Intelligence         │ │   │
│  │ • UI Panel   │    │  │ • MLX Local                 │ │   │
│  │ • iMessage   │    │  └─────────────────────────────┘ │   │
│  │ • Notif.     │    └──────────────────────────────────┘   │
│  └──────────────┘                                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Cider Services (existing)                            │   │
│  │ DateCardStorage, VaultBookmarkService, NotesStorage,  │   │
│  │ ReminderReconciler, ReminderOutbox, etc.             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

The Agent Orchestrator is a singleton service, not a ViewModel. The UI chat panel becomes a thin client that reads from and writes to the orchestrator. iMessage becomes another thin client. Reminders become another.

---

## Agent Orchestrator

The core of the system. Receives messages from any input channel, routes them through the configured provider, executes tool calls, and delivers responses to the appropriate output channel.

```swift
@MainActor
final class AgentOrchestrator: ObservableObject {
    static let shared = AgentOrchestrator()

    // Current provider (user-configurable)
    private var provider: AgentProvider

    // Active conversations by thread ID
    private var threads: [UUID: AgentThread] = [:]

    // Tool registry (unified, provider-agnostic)
    private let toolRegistry = AgentToolRegistry.shared

    /// Process an inbound message from any channel.
    /// Returns the agent's response (or streams it via the thread's publisher).
    func handleMessage(
        _ text: String,
        threadID: UUID,
        channel: AgentChannel,
        context: AgentContext = .empty
    ) async {
        let thread = getOrCreateThread(id: threadID, channel: channel)
        thread.append(.user(text))

        // Build messages for provider
        let systemPrompt = buildSystemPrompt(thread: thread, context: context)
        let messages = thread.messagesForProvider()

        // Run the conversation loop (may include tool calls)
        let response = await runConversationLoop(
            provider: provider,
            systemPrompt: systemPrompt,
            messages: messages,
            thread: thread
        )

        // Deliver response to the originating channel
        thread.append(.assistant(response))
        await deliver(response, to: channel, threadID: threadID)
        thread.save()
    }

    /// Wake the agent for a specific purpose (no user message).
    /// Used by ReminderReconciler, vault event handlers, etc.
    func wake(
        purpose: AgentWakePurpose,
        threadID: UUID? = nil,
        channel: AgentChannel = .system
    ) async {
        switch purpose {
        case .deliverReminder(let reminderContext):
            // Create or reuse a reminder thread
            let tid = threadID ?? UUID()
            let message = formatReminderMessage(reminderContext)
            await handleMessage(message, threadID: tid, channel: .iMessage, context: .reminder(reminderContext))

        case .dailyDigest:
            // Compose a daily summary and send via iMessage
            let summary = await composeDailySummary()
            await deliver(summary, to: .iMessage, threadID: UUID())

        case .vaultEvent(let event):
            // Handle vault events that need agent attention
            // (e.g., "you saved 5 recipes today, want me to organize them?")
            break
        }
    }
}
```

### Key design decisions

- **Singleton, not per-view** — One orchestrator instance. Multiple views/channels can interact with it concurrently via different thread IDs.
- **Thread-based** — Each conversation gets a `UUID` thread. The reminder thread for "Pay Rent" is different from the general chat thread. When you reply to a reminder, the reply routes to the same thread with full context.
- **Wake mechanism** — `wake(purpose:)` is how Cider triggers autonomous agent actions. The reconciler calls it when a reminder is due. No cron, no polling, no external process.

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

`AIAssistantViewModel` becomes a thin wrapper around `AgentOrchestrator`:

```swift
// Before: ViewModel owns conversation state and provider
func send(_ text: String) {
    provider.streamResponse(messages: messages, context: context)
}

// After: ViewModel delegates to orchestrator
func send(_ text: String) {
    await AgentOrchestrator.shared.handleMessage(
        text,
        threadID: currentThreadID,
        channel: .uiPanel,
        context: currentContext
    )
}
```

The ViewModel still handles streaming display, typewriter effect, and UI state. But conversation logic, tool execution, and provider management move to the orchestrator.

### iMessage

Cider integrates iMessage directly (not via Claude Code's plugin). Two approaches:

**Option A: AppleScript bridge** — Cider watches for incoming iMessages via `NSAppleScript` or `ScriptingBridge`, extracts the text, routes through the orchestrator, and sends the reply via AppleScript. Simple, works today, but requires Accessibility permissions.

**Option B: MessageKit / Chat framework** — Apple's MessageKit for richer integration. More complex, may require entitlements.

**Option A is recommended for v1.** AppleScript iMessage sending already works in macOS, and Cider can poll the Messages database (chat.db) for new messages addressed to the agent's configured phone number.

### Reminders (the wake flow)

See [Reminder Wake Flow](#reminder-wake-flow) below.

### Notification Replies

When a user taps a notification action like "Reply" or "Snooze", the `UNUserNotificationCenterDelegate` in `DateCardNotificationService` routes the response to the orchestrator:

```swift
case "REPLY":
    let reply = response as? UNTextInputNotificationResponse
    await AgentOrchestrator.shared.handleMessage(
        reply?.userInputText ?? "snooze",
        threadID: reminderThreadID(for: dateCardID),
        channel: .notification,
        context: .reminder(...)
    )
```

---

## Provider Abstraction

The current `AIAssistantProvider` protocol is streaming-only and doesn't abstract tool calling. The new `AgentProvider` protocol unifies both:

```swift
@MainActor
protocol AgentProvider {
    var isAvailable: Bool { get }
    var displayName: String { get }
    var supportsToolCalling: Bool { get }

    /// Send a conversation and get a response.
    /// The provider handles tool calling internally if supported.
    /// Returns the final text response after all tool rounds complete.
    func respond(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) async throws -> AgentResponse

    /// Streaming variant for UI display.
    func streamRespond(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) -> AsyncThrowingStream<AgentStreamEvent, Error>

    func resetSession()
}

enum AgentStreamEvent {
    case textDelta(String)          // Partial text for UI streaming
    case toolCallStart(String)       // Tool name, for UI status display
    case toolCallResult(String)      // Result, for UI logging
    case complete(AgentResponse)     // Final response
}

struct AgentResponse {
    let text: String
    let toolCallsMade: [AgentToolCall]  // For logging/debugging
}
```

### Provider implementations

| Provider | Model | Tool calling | Context window |
|----------|-------|-------------|----------------|
| `FoundationModelsAgentProvider` | Apple Intelligence | Native via `LanguageModelSession` | 4K |
| `MLXAgentProvider` | Qwen 2.5 (local) | Prompt-based `<tool_call>` parsing | 32K |
| `ClaudeAPIAgentProvider` | Claude (API) | Native via Anthropic SDK | 200K |
| `OpenAIAPIAgentProvider` | GPT-4o/o1 (API) | Native via function calling | 128K |
| `GeminiAPIAgentProvider` | Gemini (API) | Native via function declarations | 1M |

API-based providers use their respective SDKs or raw HTTP. All conform to the same `AgentProvider` protocol. The orchestrator doesn't know or care which one is active.

### User configuration

```swift
// In CiderConfig
var aiProvider: AIProviderType = .appleIntelligence
var aiAPIKey: String?  // For Claude/OpenAI/Gemini
var aiModel: String?   // Optional model override (e.g., "claude-sonnet-4-20250514")
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
4. Orchestrator creates/reuses a reminder thread
5. Orchestrator sends the reminder context to the provider
6. Provider generates a conversational message: "Hey! Rent is due tomorrow."
7. Orchestrator delivers via iMessage
8. User replies: "Snooze until the morning"
9. iMessage input channel receives the reply
10. Routes to the same reminder thread (matched by sender + recent reminder context)
11. Provider processes: "Got it, I'll remind you tomorrow at 9 AM."
12. Agent creates a one-time DateCard via CreateReminderTool
13. Orchestrator delivers confirmation via iMessage
```

### Thread matching for replies

When a user replies to a reminder iMessage, the orchestrator needs to route the reply to the correct thread. Strategy:

- Keep a mapping of `(iMessageSenderID, lastReminderCardID) → threadID`
- Reminder threads have a TTL (e.g., 30 minutes) — replies within the window go to the reminder thread
- After the TTL, new messages start a fresh general thread

### Wake purposes

```swift
enum AgentWakePurpose {
    case deliverReminder(ReminderContext)
    case dailyDigest
    case vaultEvent(VaultEvent)
    case scheduledCheck(String)  // Generic scheduled tasks
}

struct ReminderContext {
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
    let channel: AgentChannel
    var messages: [AgentMessage]
    var context: AgentContext
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]  // e.g., "reminderCardID": "..."

    func messagesForProvider() -> [AgentMessage] {
        // Trim to fit context window, keeping system + recent messages
    }

    func save() {
        AgentConversationStorage.shared.save(thread: self)
    }
}
```

### Thread types

| Type | Created by | Lifetime | Example |
|------|-----------|----------|---------|
| General | User opens chat | Until cleared | "What did I save today?" |
| Reminder | Reconciler wake | 30-min TTL after last message | "Rent is due tomorrow" → "Snooze 1 hour" |
| Digest | Daily schedule | Single message, no reply expected | "Here's your daily summary" |
| Event | Vault trigger | Short-lived | "You saved 5 recipes, want a folder?" |

---

## Tool Registry

Unified tool definitions that work across all providers.

```swift
struct AgentToolDefinition {
    let name: String
    let description: String
    let parameters: [AgentToolParameter]
    let execute: @MainActor ([String: Any]) -> String
}

struct AgentToolParameter {
    let name: String
    let type: AgentToolParameterType  // string, integer, boolean, array
    let description: String
    let required: Bool
}

@MainActor
final class AgentToolRegistry {
    static let shared = AgentToolRegistry()
    private(set) var tools: [AgentToolDefinition] = []

    func register(_ tool: AgentToolDefinition) { tools.append(tool) }

    func execute(name: String, arguments: [String: Any]) -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            return "Unknown tool: \(name)"
        }
        return tool.execute(arguments)
    }
}
```

Each provider converts `AgentToolDefinition` to its native format:
- Foundation Models → `@Generable` struct (may need codegen or runtime adapter)
- MLX → JSON schema string
- Claude API → `tools` parameter in API request
- OpenAI → `functions` parameter
- Gemini → `function_declarations`

This means adding a new tool is **one registration** instead of editing 3 files.

---

## Implementation Phases

### Phase 1: Extract Orchestrator (no new features)

**Goal:** Decouple conversation logic from the ViewModel without changing any user-facing behavior.

- Create `AgentOrchestrator` with `handleMessage()` and thread management
- Create `AgentProvider` protocol (mirrors current `AIAssistantProvider` but adds tool abstraction)
- Adapt `FoundationModelsProvider` and `MLXProvider` to conform to `AgentProvider`
- Refactor `AIAssistantViewModel` to delegate to orchestrator
- Chat panel works exactly as before — just plumbed differently underneath

**Files:** ~5 new, ~3 modified. No UI changes. No new features.

### Phase 2: Add wake mechanism + iMessage channel

**Goal:** The agent can be triggered by Cider and can send/receive iMessages.

- Add `wake(purpose:)` to orchestrator
- Wire `ReminderReconciler` to call `wake(.deliverReminder(...))` instead of writing outbox files
- Implement iMessage input (AppleScript-based chat.db polling or ScriptingBridge)
- Implement iMessage output (AppleScript `tell application "Messages"`)
- Remove outbox system (replaced by direct orchestrator wake)

**Files:** ~4 new (iMessage bridge), ~3 modified. Reminders now text you directly.

### Phase 3: Add API-based providers

**Goal:** Users can choose Claude, OpenAI, or Gemini as their AI backend.

- Implement `ClaudeAPIAgentProvider` (Anthropic Swift SDK or raw HTTP)
- Implement `OpenAIAPIAgentProvider` (raw HTTP — no official Swift SDK)
- Implement `GeminiAPIAgentProvider` (Google AI Swift SDK)
- Add API key configuration in Cider settings
- Add model picker in UI (extend existing provider switcher)

**Files:** ~3 new provider files, ~2 modified (config, settings UI).

### Phase 4: Unified tool registry

**Goal:** One tool definition works across all providers.

- Create `AgentToolRegistry` with provider-agnostic definitions
- Generate provider-specific formats at runtime
- Remove duplicate tool definitions (AIAssistantTools.swift, MLXToolDefinitions.swift, MLXToolExecutor.swift → single source)
- Adding a new tool = one registration call

**Files:** ~2 new, ~3 removed/simplified.

### Phase 5: Advanced features

- Daily digest messages
- Proactive vault suggestions ("you saved 5 recipes today")
- Conversation threading in UI (multiple threads visible)
- Notification reply routing
- Shortcut/Siri integration

---

## Open Questions

1. **iMessage access method** — AppleScript polling works but is janky. Is there a better way to receive iMessages in a macOS app without a full Messages extension? ScriptingBridge? Private APIs? The current Claude Code iMessage plugin uses Anthropic's server-side approach, which won't work here.

2. **Foundation Models tool adapter** — Apple's `@Generable` structs are compile-time. Can we generate `Tool` conformances at runtime from `AgentToolDefinition`, or do we need a code-generation step?

3. **Context window management** — Each provider has a different context limit (4K to 1M). The orchestrator needs a strategy for trimming conversation history per provider. Current approach: summarize when approaching the limit.

4. **Rate limiting for API providers** — Claude/OpenAI/Gemini have rate limits and costs. Need a token budget tracker and user-facing usage display.

5. **Privacy** — API providers send vault data to external servers. Need clear user consent, opt-in per provider, and possibly a "local-only mode" that restricts to Apple Intelligence + MLX.

6. **Multi-model routing** — Could use a cheap/fast model for simple tasks (snooze, dismiss) and a capable model for complex ones (organize my vault). Is this worth the complexity?

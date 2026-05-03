# Managed Agent Runtime

> Status: historical/alternate architecture context. Current durable Main Brain and Hermes integration guidance lives in `Docs/Features/MainBrain/`. Agent Host future-boundary guidance lives in `Docs/Features/AgentHost/README.md`.

## Status

Draft architecture for the next phase after `AgentOrchestrator` / unified tool registration.

This doc refines the direction in [AGENT_SERVICE.md](/Users/minivish/Cider/Docs/Architecture/AGENT_SERVICE.md). The existing doc still assumes API/on-device providers are first-class peers and that the agent lives entirely inside Cider's process. That is not the primary product direction anymore.

The primary direction is:

- Cider manages one long-lived agent process per vault while the app is open
- The first managed runtime is `Claude Code`
- UI chat, iMessage, reminders, and other wake events route into the same logical conversation
- On-device / request-response model providers remain supported, but as fallback runtimes

---

## Goals

- Run one durable assistant per vault while Cider is open
- Let Cider wake that assistant for reminders, scheduled work, and inbound channel messages
- Keep one logical conversation across AI panel, iMessage, and reminder follow-ups
- Make the primary path work with the user's existing `Claude Code` subscription and vault-local workflow
- Preserve support for on-device / non-Claude runtimes for users who want them later

## Non-Goals

- Rebuild Claude Code's reasoning, tool system, or plugin model inside Cider
- Force every provider into the same request/response abstraction
- Ship provider parity in this phase
- Solve every future channel up front

---

## Product Decisions

These are treated as decided for this design:

- Primary runtime: managed `Claude Code` subprocess
- Runtime lifetime: one long-lived agent per vault while Cider is open
- Conversation model: same logical thread across AI panel, iMessage, and reminders
- Reminder delivery: proactive messages appear in the same existing iMessage thread
- Failure policy: agent process auto-restarts if it dies
- Permissions: configurable profiles, up to full vault read/write + command execution
- Fallbacks: on-device / model-backed runtimes remain available but are not the primary path

---

## Architecture

```text
┌────────────────────────────────────────────────────────────────────┐
│ Cider App                                                         │
│                                                                    │
│  ┌──────────────────────────────┐                                  │
│  │ ReminderReconciler           │                                  │
│  │ UIPanelBridge                │                                  │
│  │ iMessageBridge               │                                  │
│  └──────────────┬───────────────┘                                  │
│                 │ AgentEnvelope / WakeIntent                        │
│                 ▼                                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ AgentOrchestrator                                           │   │
│  │ - thread routing                                            │   │
│  │ - wake handling                                             │   │
│  │ - permissions / policy                                      │   │
│  │ - channel routing                                           │   │
│  └──────────────┬───────────────────────────────────────────────┘   │
│                 │ uses                                              │
│                 ▼                                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ AgentRuntime                                                 │   │
│  │                                                              │   │
│  │  ProcessAgentRuntime      ModelAgentRuntime                  │   │
│  │  - ClaudeCodeRuntime      - FoundationModelsRuntime          │   │
│  │  - future CLIs            - MLXRuntime                       │   │
│  │                           - future API runtimes              │   │
│  └──────────────┬───────────────────────────────────────────────┘   │
│                 │                                                   │
│                 ▼                                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ AgentProcessManager                                          │   │
│  │ - spawn / stop / restart                                     │   │
│  │ - health checks                                              │   │
│  │ - transport session                                          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

Core idea: `AgentOrchestrator` remains the system-level coordinator, but it talks to an `AgentRuntime`, not directly to an `AgentProvider`.

`AgentProvider` becomes an implementation detail of `ModelAgentRuntime`.

---

## Runtime Split

### AgentRuntime

Top-level abstraction for anything Cider can talk to as "the agent".

```swift
protocol AgentRuntime: Sendable {
    var id: String { get }
    var displayName: String { get }
    var kind: AgentRuntimeKind { get }
    var capabilities: AgentRuntimeCapabilities { get }

    func start() async throws
    func stop() async
    func health() async -> AgentRuntimeHealth

    func send(_ envelope: AgentRuntimeEnvelope) async throws -> AgentRuntimeResponse
    func stream(_ envelope: AgentRuntimeEnvelope) -> AsyncThrowingStream<AgentRuntimeEvent, Error>
}

enum AgentRuntimeKind: String, Sendable {
    case process
    case model
}
```

Why this exists:

- a managed CLI process has lifecycle and health semantics that a model adapter does not
- a direct model runtime does not need spawn/stop/restart logic
- the orchestrator should not care which one is underneath

### ProcessAgentRuntime

Used for long-lived subprocess agents.

```swift
protocol ProcessAgentRuntime: AgentRuntime {
    var launchPath: String { get }
    var workingDirectory: URL { get }
}
```

Responsibilities:

- spawn process
- maintain transport session
- correlate outbound messages and inbound responses
- restart on crash
- surface health / stuck state

### ModelAgentRuntime

Adapter around the current provider model.

```swift
protocol ModelAgentRuntime: AgentRuntime {
    var provider: any AgentProvider { get }
}
```

This keeps the current work useful:

- `FoundationModelsAgentProvider`
- `MLXAgentProvider`
- future API providers

They no longer define the whole agent architecture; they become one runtime family.

---

## Claude Code Runtime

`ClaudeCodeRuntime` is the primary runtime for v1 of the managed-agent architecture.

### Responsibilities

- launch `claude` (or a wrapper command) in the vault directory
- ensure the runtime sees the vault's `CLAUDE.md`, MCP tools, and Cider CLI
- keep one long-lived process while Cider is open
- receive prompts from Cider
- return structured responses to Cider
- survive transient crashes with automatic restart

### Non-Responsibilities

- deciding whether a reminder is due
- deciding which channel a response should go to
- routing thread IDs between UI and iMessage

Those stay in Cider.

### Required Runtime Guarantees

For Cider to treat Claude Code as a runtime, the transport must support:

1. Sending a user/system message with metadata
2. Receiving a structured assistant response
3. Correlating one response with one request
4. Preserving one logical conversation across multiple sends
5. Distinguishing normal assistant output from transport framing

If the local `claude` CLI cannot provide this in a stable machine-readable mode, Cider should use a thin wrapper process around it rather than scraping a terminal transcript directly in app code.

---

## Transport Contract

This is the main design risk and must be settled before Phase 2 implementation.

### Preferred Option

A structured framed protocol over stdin/stdout, ideally newline-delimited JSON.

```json
{"type":"request","request_id":"...","thread_id":"primary","channel":"ui","role":"user","text":"How many bookmarks do I have?","context":{...}}
{"type":"response_start","request_id":"..."}
{"type":"response_delta","request_id":"...","text":"You have "}
{"type":"response_delta","request_id":"...","text":"149 bookmarks."}
{"type":"response_done","request_id":"...","final_text":"You have 149 bookmarks.","metadata":{"tool_calls":2}}
```

Advantages:

- simple correlation
- stream-friendly
- no terminal scraping
- same contract works for process-backed and wrapped runtimes

### Acceptable Fallback

If Claude Code only supports terminal-style usage, introduce a small wrapper executable:

- Cider talks JSONL to the wrapper
- the wrapper owns the fragile Claude Code interaction
- the wrapper normalizes output into the framed protocol above

That keeps terminal coupling out of the app.

### Explicit Non-Goal

Do not make `AgentOrchestrator` parse arbitrary human-readable Claude terminal output.

That is acceptable for an experiment, not for the foundation of reminders + iMessage.

---

## Core Types

### Runtime Envelope

```swift
struct AgentRuntimeEnvelope: Sendable {
    let requestID: UUID
    let threadID: UUID
    let logicalThreadKey: String
    let channel: AgentChannel
    let message: AgentMessage
    let context: AgentContext
    let permissions: AgentPermissionProfile
}
```

### Runtime Response

```swift
struct AgentRuntimeResponse: Sendable {
    let text: String
    let toolCallsMade: Int
    let rawMetadata: [String: String]
}
```

### Runtime Events

```swift
enum AgentRuntimeEvent: Sendable {
    case textDelta(String)
    case requiresPermission(String)
    case done(AgentRuntimeResponse)
}
```

### Health

```swift
struct AgentRuntimeHealth: Sendable {
    let status: AgentRuntimeStatus
    let startedAt: Date?
    let lastResponseAt: Date?
    let restartCount: Int
    let lastError: String?
}

enum AgentRuntimeStatus: String, Sendable {
    case stopped
    case starting
    case running
    case degraded
    case failed
}
```

---

## Process Management

`AgentProcessManager` owns the long-lived subprocess.

### Responsibilities

- spawn at app launch when the managed agent feature is enabled
- stop at app termination
- restart automatically on unexpected exit
- expose health information
- serialize transport access if the runtime only supports one active exchange at a time

### Behavior

- one process per vault
- one active session identity per vault
- configurable restart backoff to avoid crash loops

### Restart Policy

- first failure: restart immediately
- repeated failures: exponential backoff
- after N failures in M minutes: mark runtime degraded and surface UI warning

---

## Channel Routing

The user wants one logical conversation, not separate panel and reminder personas.

That means:

- AI panel messages
- proactive reminder messages
- inbound iMessage replies

all route to the same logical thread unless the app explicitly chooses a temporary subthread.

### Routing Rule

Default thread for the vault:

```text
logicalThreadKey = "primary"
```

Reminder wakes should still route through `"primary"` unless there is a strong reason to isolate them.

The result:

- reminder arrives in the same iMessage conversation
- user says "snooze that until tomorrow morning"
- the same agent context can resolve "that"

### Important Distinction

"same thread" does not mean one unbounded transcript forever.

Implementation should support:

- one canonical logical thread ID for the user experience
- internal summarization / compaction
- channel-specific metadata attached to messages

---

## Reminder Flow

This is the target end-to-end behavior.

1. `ReminderReconciler` determines a reminder is due
2. It builds a `WakeIntent.deliverReminder`
3. `AgentOrchestrator` routes that wake intent to the managed runtime on logical thread `"primary"`
4. The runtime produces reminder text
5. `iMessageBridge` delivers it into the existing conversation
6. User replies in the same iMessage thread
7. `iMessageBridge` routes the inbound reply back into logical thread `"primary"`
8. The runtime interprets the reply
9. Cider executes the resulting change via the orchestrator / tools / CLI

Key rule: Cider remains the source of truth for reminders. The agent does not become the scheduler of record.

---

## iMessage Bridge

For this architecture, iMessage is a channel bridge, not the agent host.

Responsibilities:

- outbound send
- inbound receive
- map incoming messages to the logical thread key
- feed inbound messages into the orchestrator

It should not:

- decide what to say
- own reminder timing
- maintain separate reminder state

This lets the same bridge work for:

- managed Claude Code runtime
- on-device runtime
- future runtimes

---

## Permissions

The user explicitly wants support for broad permissions, but that must be shaped into profiles.

### Proposed Profiles

```swift
enum AgentPermissionProfile: String, Codable, Sendable {
    case readOnly
    case command
    case fullAccess
}
```

### Semantics

- `readOnly`
  - vault reads
  - summaries
  - search
  - no mutation

- `command`
  - vault reads
  - shell / CLI execution
  - mutating actions may still require explicit confirmation depending on channel

- `fullAccess`
  - full vault read/write
  - shell / CLI execution
  - destructive operations allowed subject to policy

Channel policy can still narrow permissions:

- local UI can be `fullAccess`
- reminder replies may be `command`
- remote channels can require confirmation for destructive actions

---

## Minimal Phase 2 Scope

This is the smallest useful next implementation slice.

### Build

1. `AgentRuntime` protocol
2. `ModelAgentRuntime` adapter over current `AgentProvider`
3. `ProcessAgentManager`
4. `ClaudeCodeRuntime` skeleton
5. transport contract prototype
6. `iMessageBridge` remains external / stubbed if needed
7. `ReminderReconciler -> AgentOrchestrator.wake()` path

### Do Not Build Yet

- provider parity for Gemini / ChatGPT
- full iMessage implementation if transport is not settled
- generalized multi-agent support
- cron-based workaround logic

### Exit Criteria

Phase 2 is successful when:

- Cider launches one managed Claude Code agent for the vault
- the AI panel can send a message through that runtime
- the runtime can be auto-restarted
- a reminder wake can route into the same logical thread
- transport is structured enough that the app is not scraping ad hoc terminal text

---

## Open Questions

These are now concrete discovery questions rather than product questions.

1. Does local `claude` support a stable machine-readable / headless mode suitable for a long-lived managed runtime?
2. If not, should Cider ship a wrapper executable that normalizes Claude Code into a framed transport?
3. Can one long-lived Claude Code process cleanly preserve one conversation while servicing mixed-origin messages from UI, reminders, and iMessage?
4. What is the cleanest way to represent "same logical thread" while still allowing summarization and compaction?
5. Which transport errors should force restart vs retry-in-place?

---

## Recommendation

Proceed with the managed-runtime architecture.

Specifically:

- keep `AgentOrchestrator`
- move `AgentProvider` under `ModelAgentRuntime`
- introduce `ProcessAgentRuntime` for Claude Code
- settle transport before adding more implementation complexity

This gives Cider the right foundation for:

- headless always-on assistant behavior
- proactive reminders
- one shared conversation across UI and iMessage
- future fallback runtimes without sacrificing the Claude-first path

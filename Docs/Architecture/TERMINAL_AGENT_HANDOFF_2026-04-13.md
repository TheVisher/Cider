# Terminal Handoff: Managed Agent + iMessage Direction

## Purpose

This document is a handoff for continuing agent-runtime and messaging work from a terminal session without losing the reasoning that led here.

It captures:

- the current state of the agent-service work already landed
- the architecture decisions made after that work
- the `claude` CLI transport spike results
- the official Anthropic iMessage plugin implementation details
- the product direction for a Cider-owned, LLM-agnostic messaging layer
- the recommended next implementation steps

This should be read together with:

- [AGENT_SERVICE.md](/Users/minivish/Cider/Docs/Architecture/AGENT_SERVICE.md)
- [MANAGED_AGENT_RUNTIME.md](/Users/minivish/Cider/Docs/Architecture/MANAGED_AGENT_RUNTIME.md)

This file is the practical status/handoff note. The other docs are the architecture references.

---

## Executive Summary

The important conclusion is:

- `Claude Code` should not be modeled as just another `AgentProvider.generate()` backend.
- Long-term, Cider needs a top-level `AgentRuntime` abstraction with at least two families:
  - `ProcessAgentRuntime`
  - `ModelAgentRuntime`
- However, after transport testing, a simpler first implementation is viable:
  - Cider can invoke `claude` per event using structured I/O and durable `session_id` continuity.
- After the Claude account was disabled during development, it became clear that **messaging must be owned by Cider, not by a specific LLM runtime**.
- Therefore, the best long-term design is:
  - Cider owns channels, especially iMessage
  - runtimes are pluggable
  - texting remains the user-facing interface
  - the active runtime can be Claude Code, Gemini, OpenAI, on-device, etc.

The strongest updated product direction is:

1. Build an `iMessageBridge` inside Cider.
2. Route inbound/outbound iMessage through `AgentOrchestrator`.
3. Keep the agent runtime swappable.
4. Use the Anthropic plugin architecture as the baseline for reliability.
5. Do **not** hard-couple the texting channel to Claude-specific plugins.

---

## Product Intent

The intended user experience is:

- one assistant per vault while Cider is open
- the same assistant is reachable from:
  - Cider AI panel
  - iMessage
  - reminders / proactive notifications
- the same logical conversation context should span all of those channels
- reminders should arrive in the same ongoing conversation, not as isolated one-off jobs
- the user should be able to switch the intelligence behind that assistant later
- the channel experience should not collapse if one provider account is unavailable

Concrete product decisions already discussed:

- Primary intelligence for now: `Claude Code`, if available
- Future requirement: user must be able to swap to other LLMs
- One logical conversation across panel + reminders + texting
- Reminder follow-ups should happen in the existing thread
- Auto-restart or automatic recovery is desirable
- Permissions should be configurable, up to full vault read/write + command execution
- Headless agent behavior is foundational, but it must not make iMessage vendor-specific

---

## Current Codebase State

There is already substantial agent-service groundwork on the `feature/agent-service` line of work.

Previously completed:

- core agent-service types
- provider protocol
- unified tool registry
- `AgentOrchestrator` actor
- registration of all 24 tools

Phase 1 follow-up work was then completed:

- `FoundationModelsAgentProvider`
- `MLXAgentProvider`
- `AIAssistantViewModel` orchestrator-backed path
- `AppDelegate` wiring for tool registration and orchestrator enablement

That work produced a functioning UI-panel orchestrator path with tool execution confirmed in logs.

Observed validation:

- tool rounds executed correctly
- real vault counts/folders were returned
- both Foundation Models and MLX adapter paths compiled
- build passed aside from pre-existing unrelated warnings/errors when using `-warnings-as-errors`

This matters because the orchestrator/tool groundwork should be preserved. The runtime/channel split should build on it, not replace it.

---

## Architectural Reframe

The earlier `AGENT_SERVICE.md` doc treated providers as the top-level abstraction and assumed the agent lived fully inside Cider’s process as a model service.

That is no longer sufficient for the product direction.

The better model is:

```text
Cider
  ├─ ChannelBridge
  │   ├─ UIPanelBridge
  │   ├─ iMessageBridge
  │   └─ ReminderBridge
  │
  ├─ AgentOrchestrator
  │   ├─ threads
  │   ├─ wake intents
  │   ├─ permissions
  │   └─ routing
  │
  └─ AgentRuntime
      ├─ ProcessAgentRuntime
      │   └─ ClaudeCodeRuntime / future CLIs
      └─ ModelAgentRuntime
          ├─ FoundationModels
          ├─ MLX
          └─ future API runtimes
```

Key distinction:

- `AgentProvider` is a good fit for request/response or local-model adapters.
- It is a poor fit for a managed CLI/runtime with lifecycle, channels, health, and session continuity.

That led to the doc:

- [MANAGED_AGENT_RUNTIME.md](/Users/minivish/Cider/Docs/Architecture/MANAGED_AGENT_RUNTIME.md)

That doc should be treated as the architectural baseline for the next phase.

---

## Claude CLI Transport Spike

A local transport spike was run against the installed `claude` CLI to answer whether Cider can talk to it in a structured way.

### Environment

- installed CLI version observed locally: `2.1.105`
- relevant flags discovered:
  - `-p/--print`
  - `--input-format stream-json`
  - `--output-format stream-json`
  - `--include-partial-messages`
  - `--session-id`
  - `--resume`

### Results

#### 1. Structured output works

This worked:

```sh
claude -p --output-format json "hello"
```

It returned a structured JSON result object.

#### 2. Streaming structured output works

This worked:

```sh
claude -p --verbose --output-format stream-json --include-partial-messages "hello"
```

Observed event types included:

- `message_start`
- `content_block_delta`
- final `result`

So typewriter-style UI integration is viable.

#### 3. Tools work in vault context

Running from the vault directory and allowing Bash worked. Claude used tools and returned the expected path.

Representative prompt used:

```text
Use Bash to run 'pwd' and reply with only the resulting absolute path.
```

Observed output matched the expected vault path.

#### 4. Session continuity across separate invocations works

Two separate invocations using the same session identifier were tested:

- first invocation stored a fact
- second invocation resumed the same session and correctly recalled it

This is the most important transport result.

It means conversation continuity can be preserved across multiple short-lived process invocations.

#### 5. Recovery after interruption works

A structured run was interrupted mid-response and then resumed with the same session.

The resumed session still knew what it had been doing.

### Important Caveats

- `stream-json` output is noisy.
- It includes more than assistant content:
  - init metadata
  - hook events
  - plugin / MCP state
  - assistant deltas
  - final result
- Cider therefore needs a stream parser/filter, not naive stdout scraping.

Also:

- `-p` is still one invocation per request.
- It is **not** a persistent socket server by itself.

### Architectural Implication

This reduces transport risk significantly.

Two viable designs now exist:

#### Option A: per-event structured invocation with durable session ID

- Cider handles panel input, reminders, and iMessage
- for each event, Cider spawns `claude`
- Cider passes the durable session id / resume token
- continuity lives in Claude session state, not a forever-running OS process

Pros:

- simpler lifecycle
- auto-restart is trivial because there is nothing persistent to recover
- easier to keep vendor-agnostic channel ownership in Cider

Cons:

- if a runtime must itself own inbound channel listeners, this is not enough

#### Option B: persistent Claude subprocess

- Cider keeps Claude running
- Cider somehow interacts with that live process
- potentially more natural if Claude itself owns a channel plugin

Pros:

- fits “one live agent process” intuition

Cons:

- transport into the live process becomes harder
- not necessary if Cider owns channels anyway

### Current Recommendation

After later product discussion, Option A is now the better first implementation:

- Cider should own channels
- Cider should invoke runtimes per event
- Claude session continuity can come from session IDs
- persistent always-on process management is no longer required for v1

This change happened because messaging needs to be LLM-agnostic.

---

## Why Messaging Must Be Owned by Cider

At one point the design direction was leaning toward:

- a managed long-lived Claude Code process
- Claude owning iMessage directly through its plugin

That was attractive because it made the agent feel “alive.”

However, during development the Claude account in use was disabled. That exposed the product risk very clearly:

- if the messaging channel belongs to Claude, losing Claude means losing the assistant channel
- if Gemini/OpenAI/local model users want the same feature, each runtime would need its own messaging stack
- reminders and texting would become vendor features instead of Cider features

That is the wrong layer boundary.

The correct boundary is:

- Cider owns messaging
- Cider owns reminders
- Cider owns thread routing
- runtimes generate responses

This keeps:

- channel behavior stable
- runtime choice swappable
- reminders independent of one vendor

Therefore:

**Text messaging should be a Cider capability, not an LLM capability.**

---

## Research: How Anthropic’s iMessage Plugin Actually Works

Anthropic’s official iMessage plugin source was inspected locally from:

- `/Users/minivish/.claude/plugins/cache/claude-plugins-official/imessage/0.1.0`

Public references:

- <https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/imessage>
- <https://code.claude.com/docs/en/channels>

### Core Design

Anthropic’s plugin is straightforward:

- reads `~/Library/Messages/chat.db` directly
- polls `chat.db` every second
- initializes a watermark to current `MAX(ROWID)` on boot
- only processes rows with `ROWID > watermark`
- sends outbound text and attachments using AppleScript to `Messages.app`
- keeps access control in a local JSON file
- exposes two tools:
  - `reply`
  - `chat_messages`

No private Apple API.
No external service.
No special background daemon.

### Inbound

The plugin queries:

- `message`
- `chat`
- `handle`
- join tables

It interprets:

- `chat.style == 45` as DM
- `chat.style == 43` as group

It filters:

- non-iMessage traffic by default
- unknown chat styles
- empty / tapback-like rows
- its own echoes
- non-allowlisted senders/groups

### Outbound

Outbound is pure AppleScript:

```applescript
tell application "Messages" to send ... to chat id ...
```

Attachments are sent separately.

### Access Control

State lives in:

- `~/.claude/channels/imessage/access.json`

Concepts:

- self-chat bypass
- allowlist DMs
- group allowlist
- optional pairing mode
- mention-pattern regexes for groups

### Loop Prevention / Echo Suppression

This is one of the most important implementation details.

Because self-chat is weird, the plugin keeps a short-lived map of recently sent items keyed by:

- `chatGuid`
- normalized text

Window:

- 15 seconds

Normalization includes stripping:

- signature
- some unicode presentation artifacts
- whitespace normalization

Then inbound messages matching a recent echo are consumed instead of being delivered upstream.

This is the reason the plugin feels stable in practice.

### Permission Relay

For permission prompts, the plugin sends an approval/deny request back only to self-chat.

That is a Claude-specific behavior and should not be copied directly into Cider as-is.

### Attachments

Attachments are resolved from paths already stored by Messages on disk. The plugin can surface the first inbound image as a local file path.

This is a good pattern for Cider too.

### Reliability Takeaway

Anthropic’s plugin is reliable because it is boring:

- local DB reads
- local AppleScript sends
- small JSON state
- clear gating
- explicit echo suppression

There is no hidden magic.

---

## What Cider Should Copy

The following parts should be copied almost directly:

### 1. Read `chat.db` directly

This is the right source of truth for iMessage history and inbound detection on macOS.

### 2. Send through AppleScript / Messages.app

This is the practical outbound path without relying on private API.

### 3. Use local access control state

Keep a Cider-owned config/state file for:

- allowlisted handles
- group rules
- mention patterns
- delivery preferences

### 4. Use watermark-based incremental reads

At minimum:

- remember last seen row id
- only process newer rows

### 5. Use echo suppression

This is mandatory, especially if self-chat is supported.

### 6. Surface attachments as file paths

Do not try to invent a blob transport layer for image attachments.

### 7. Keep the implementation local-first

The channel layer should not rely on any LLM provider.

---

## What Cider Should Improve

Anthropic’s plugin is good, but it is built for Claude’s plugin model, not for Cider’s product.

Cider should do better in these areas.

### 1. Channel ownership

Anthropic’s plugin is owned by Claude.

Cider should own the channel itself.

That is the single biggest architectural improvement.

### 2. Persisted dedupe across restarts

Anthropic initializes the watermark to `MAX(ROWID)` at boot, which avoids replay but can miss messages that arrived while the server was down.

Cider should persist:

- last processed row id
- recent message GUIDs
- maybe a short dedupe cache

That allows cleaner restart recovery.

### 3. Health and permissions UI

Cider should expose:

- Full Disk Access status
- Automation permission status
- bridge connected / disconnected state
- last inbound/outbound activity
- channel errors

Anthropic’s plugin surfaces this mostly through logs and plugin behavior.

### 4. Better permission UX

Do not default to relaying permission prompts into iMessage the way Claude does.

Cider should prefer app UI first, then remote fallback if needed.

### 5. LLM-agnostic routing

Inbound iMessage should be turned into an internal envelope and sent through `AgentOrchestrator`.

Do not let the channel talk directly to a specific runtime.

### 6. Better transport abstraction

The channel layer should not know whether the active runtime is:

- Claude Code
- Gemini
- OpenAI
- Foundation Models
- MLX

### 7. Better message recovery and audit

Cider should track:

- inbound message id
- associated thread id
- delivery attempt state
- agent response id
- retry state if sending fails

This is much easier when the app owns the channel.

---

## The Self-Chat UX Problem

The screenshot and product concern are real:

- if the user texts themselves
- and the assistant replies in that same self-chat
- it feels like talking to yourself
- visually, it produces awkward duplicate-looking exchanges

Anthropic’s plugin does not solve this.

It accepts it and optimizes around it.

### Hard Truth

If the transport is a self-chat in iMessage, the “talking to myself” feeling cannot be fully eliminated.

It can only be mitigated.

This is not a coding bug.
It is a consequence of using one Apple identity as both sender and receiver.

### Real Options

#### Option A: keep self-chat as bootstrap mode

Pros:

- simple
- zero extra setup
- works today

Cons:

- ugly conversational feel
- duplicate/self-talk vibe never fully goes away

#### Option B: separate agent identity

Pros:

- truly fixes the UX
- agent feels like a separate participant

Cons:

- requires a second iMessage-capable identity / number / account
- more setup friction

#### Option C: use iMessage as remote access, not as primary visual conversation

Pros:

- app can remain the clean main assistant thread
- texting is mostly for nudges, quick replies, reminders

Cons:

- weakens the “everything is in Messages” simplicity

### Recommendation

For v1:

- support self-chat
- be honest that it is bootstrap mode
- optimize it, but do not pretend it is perfect

For polished mode later:

- support a separate agent identity if the user wants it

That is the only real way around the UX issue while staying in iMessage.

---

## Recommended System Design Now

### Top-Level Direction

Build:

- `ChannelBridge`
- `iMessageBridge`
- runtime-independent `AgentOrchestrator`
- runtime switching

Keep:

- `AgentProvider`-based work as the model-runtime path

Add:

- a higher-level `AgentRuntime` abstraction

### Proposed Layering

```text
UI Panel
Reminder Engine
iMessageBridge
    ↓
AgentOrchestrator
    ↓
Active AgentRuntime
    ├─ ClaudeCodeRuntime
    ├─ GeminiRuntime
    ├─ OpenAIRuntime
    ├─ FoundationModelsRuntime
    └─ MLXRuntime
```

### One Logical Thread

The product wants one logical conversation across:

- panel
- reminders
- texts

That should be modeled as a Cider thread identity, not a raw provider transcript.

The runtime may map that to:

- Claude session id
- local conversation record
- API conversation token

But Cider should own the canonical thread identity.

---

## Suggested Module Breakdown

### `ChannelBridge`

Protocol for app-owned communication channels.

Possible responsibilities:

- start / stop
- health reporting
- receive inbound events
- send outbound responses

### `iMessageBridge`

macOS implementation using:

- direct `chat.db` reads
- AppleScript send

Responsibilities:

- poll / watch for new rows
- convert rows to normalized inbound events
- dedupe / echo suppression
- attachment discovery
- sender/group gating
- delivery reporting

### `AgentRuntime`

Top-level runtime abstraction.

For now, the practical implementation strategy can be:

- keep the existing provider work under a model runtime path
- add Claude runtime later, likely per-event structured invocations with durable session IDs

### `AgentOrchestrator`

Already partially built. Should remain responsible for:

- thread routing
- permissions
- context assembly
- tool policy
- wake events
- dispatch to active runtime

### `ReminderBridge`

This should not send text directly.

It should:

- create a reminder wake event
- route it through orchestrator
- let the resulting agent response go back out through the chosen channel

---

## Immediate Implementation Recommendation

Do not start by rebuilding everything.

The best next engineering slice is:

### Phase 2A: iMessageBridge foundation

Build:

- direct `chat.db` read access
- outbound AppleScript sender
- inbound poller
- dedupe / echo suppression
- persistent watermark store
- sender allowlist / policy store
- simple health/status reporting

Do **not** tie it to Claude.

The bridge should emit internal events only.

### Phase 2B: orchestrator routing

Connect:

- UI panel input
- reminder wakes
- iMessage inbound

into one thread-routing layer.

### Phase 2C: runtime adapter behind channel

Use the easiest currently available runtime behind the orchestrator first.

If Claude access is unavailable, use another runtime temporarily to validate the channel/orchestrator flow.

### Phase 2D: Claude runtime

When Claude access is available again:

- implement runtime using structured invocations and durable session continuity
- avoid prematurely requiring a persistent raw subprocess transport

---

## Concrete Open Questions

These are the remaining design questions worth answering in code or small spikes.

### 1. Polling only, or polling plus file/watch signal?

Anthropic polls once per second. That is acceptable.

Cider could improve this with:

- polling as the reliable fallback
- a lighter wake-up signal when the DB/WAL changes

But polling alone is enough to start.

### 2. Canonical thread key

Need a durable mapping between:

- UI conversation
- iMessage chat id
- reminder conversations
- runtime session id

This mapping belongs in Cider.

### 3. Self-chat handling

Need to decide whether to present self-chat in settings/UI as:

- default bootstrap mode
- or just one of multiple channel modes

### 4. Permissions UX

Need a clear answer for:

- what happens when an iMessage asks the agent to run a command?
- does the user approve in app, by text, or both?

Recommendation:

- app-first approval
- text fallback only if explicitly enabled

### 5. Runtime switching semantics

If the user switches runtime:

- does the logical thread stay the same?
- does the new runtime get a summarized carry-over?

Recommendation:

- yes, same Cider thread
- runtime-specific session continuity should be bridged by Cider summaries/context, not assumed

---

## Recommended Next Prompt for a Terminal Agent

If continuing this work from terminal, a good starting instruction is:

> Read `/Users/minivish/Cider/Docs/Architecture/TERMINAL_AGENT_HANDOFF_2026-04-13.md`, `/Users/minivish/Cider/Docs/Architecture/MANAGED_AGENT_RUNTIME.md`, and `/Users/minivish/Cider/Docs/Architecture/AGENT_SERVICE.md`. Then inspect the current `AgentOrchestrator` / provider code and propose a Phase 2A implementation plan for a Cider-owned `iMessageBridge` that is LLM-agnostic, modeled after Anthropic’s `chat.db + AppleScript + echo suppression` approach.

If the terminal agent should start coding immediately instead of planning:

> Implement the first slice of `iMessageBridge` in Cider: local `chat.db` access check, persistent watermark state, outbound AppleScript sender, and a standalone inbound poller with GUID dedupe and echo suppression. Keep it runtime-agnostic and do not wire it directly to Claude-specific code.

---

## Final Recommendation

The strongest current direction is:

- adopt Anthropic’s iMessage mechanics
- reject Anthropic’s Claude-owned channel ownership for Cider’s product
- make messaging a Cider feature
- keep the runtime pluggable
- use self-chat as bootstrap mode only
- treat separate agent identity as the real long-term UX fix

If future work stays aligned to those principles, the system should remain both reliable and flexible.

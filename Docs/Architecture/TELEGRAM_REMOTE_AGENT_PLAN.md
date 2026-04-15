# Telegram-First Remote Agent Plan

## Decision

The remote agent v1 should use Telegram as the first bidirectional channel.

This is the best near-term tradeoff because:

- it avoids Claude-specific product coupling
- it avoids iMessage-specific macOS automation workarounds
- it gives Cider a real bot transport with official APIs
- it keeps the architecture compatible with a later first-party iOS chat surface

This does **not** make Telegram the center of the product.

The center of the product remains:

- Cider-owned thread identity
- Cider-owned permissions and approvals
- Cider-owned vault actions
- swappable agent runtimes behind a stable app-owned interface

Telegram is just the first `ChannelBridge`.

## Product Shape

### v1

- Cider macOS hosts the vault and agent orchestrator
- Telegram provides remote chat and reminder delivery
- current model-backed providers remain usable through a runtime adapter
- iOS Share Sheet remains the mobile capture path

### v2

- add a chat UI to the existing Cider iOS app
- reuse the same thread model, vault actions, and runtime abstraction
- make Telegram optional rather than foundational

## Final Architecture

```text
iOS Share Sheet        Telegram
      |                  |
      v                  v
  ShareIngressBridge   TelegramBridge
           \            /
            v          v
            AgentOrchestrator
                  |
           VaultActionEngine
                  |
             AgentRuntime
          /                  \
ModelAgentRuntime      ProcessAgentRuntime
```

## Design Rules

### 1. Cider owns the assistant

Telegram must not own:

- conversation identity
- permissions
- memory routing
- business logic

Telegram only transports messages in and out.

### 2. One action system

All channels must hit the same app-owned operations.

Examples:

- `capture_url`
- `capture_text`
- `search_vault`
- `create_note`
- `add_bookmark`
- `create_reminder`

The Telegram handler must not implement a parallel tool/action stack.

### 3. Runtime-agnostic core

The orchestrator must talk to `AgentRuntime`, not directly to a Claude-specific or provider-specific integration.

That keeps:

- Foundation Models
- MLX
- future OpenAI / Gemini providers
- future CLI runtimes

interchangeable.

### 4. iOS later, not separate logic

The later iOS chat UI should behave like another channel bridge.

It should reuse:

- the same thread mapping
- the same approval model
- the same vault action engine
- the same runtime routing

## Telegram v1 Scope

### Must ship

- authenticated Telegram bot link to one or more allowed users
- inbound message polling or webhook ingestion
- outbound message sending
- Cider thread mapping by Telegram chat ID
- reminder delivery to Telegram
- basic command-and-chat routing through `AgentOrchestrator`

### Explicitly out of scope for v1

- group chat support
- file-heavy workflows beyond simple attachments
- voice note transcription
- complex inline keyboards and mini apps
- multi-device live sync with the iOS app

## Security Model

Telegram is cleaner than iMessage technically, but it is still a remote channel and must be treated as untrusted input.

Rules:

- allowlist chat IDs
- store bot token outside source control
- app-first approval for destructive or shell-like actions
- remote channels get a narrower permission profile than the desktop panel
- keep an audit trail of inbound and outbound Telegram activity

## Implementation Phases

### Phase 1: runtime and channel foundation

Build:

- `AgentRuntime`
- `ModelAgentRuntime`
- `ChannelBridge`
- richer `AgentChannel` / `AgentEnvelope` metadata
- orchestrator routing through runtime instead of direct provider ownership

Goal:

Preserve the current AI panel path while making remote channels first-class.

### Phase 2: Telegram bridge

Build:

- `TelegramBridge`
- bot config model
- long-polling receiver
- outbound sender
- chat ID allowlist
- message-to-thread mapping

Goal:

Enable remote ask/reply and reminders from Telegram.

### Phase 3: Share ingress

Build:

- a normalized share-ingress payload format
- a `ShareIngressBridge` entrypoint
- Cider-side handlers for `capture_url`, `capture_text`, and `capture_image`

Goal:

Let iOS Share Sheet feed the same backend without becoming a chat surface.

### Phase 4: iOS chat

Build:

- first-party iOS chat UI
- same thread model as Telegram
- same orchestrator/runtime path

Goal:

Make Telegram optional once the iOS experience is good enough.

## File/Module Plan

### Agent core

- `Sources/Cider/Services/Agent/AgentRuntime.swift`
- `Sources/Cider/Services/Agent/ModelAgentRuntime.swift`
- extend `AgentTypes.swift`
- update `AgentOrchestrator.swift`

### Channels

- `Sources/Cider/Services/Channels/ChannelBridge.swift`
- `Sources/Cider/Services/Channels/Telegram/TelegramBridge.swift`
- `Sources/Cider/Services/Channels/Telegram/TelegramModels.swift`

### Later share ingress

- `Sources/Cider/Services/Channels/ShareIngress/ShareIngressBridge.swift`

## Go/No-Go Criteria

Proceed with Telegram-first if all are true:

- current panel flow still works through the new runtime abstraction
- Telegram can receive and send one-to-one messages reliably
- reminders can be routed to a Telegram chat ID
- runtime switching does not change Cider thread identity

Do not start iOS chat work until those are stable.

# Codex Handoff: Telegram-First Remote Agent

## Current Branch

- repository: `/Users/minivish/Cider`
- branch: `feature/agent-service`
- this work was done on the feature branch, not `main`

## Goal

Move Cider toward a remote, runtime-agnostic agent architecture.

Chosen v1 direction:

- Telegram as the first remote chat channel
- local iOS Share Sheet later for capture
- existing iOS app later for first-party chat UI
- Cider-owned orchestration
- swappable runtimes behind the orchestration layer

## Final Product Decision So Far

The current recommended architecture is:

- `ChannelBridge`
- `AgentOrchestrator`
- `AgentRuntime`

Principles:

- Cider owns channels, thread identity, permissions, and vault actions
- Telegram is only a transport layer
- runtimes must remain swappable
- current local model path remains a valid fallback
- do not couple the product to Claude
- avoid API billing if possible by adding subscription-backed CLI runtimes next

## Research / Conclusion Summary

What was decided:

- iMessage is viable but more brittle and workaround-heavy on macOS
- Telegram is the cleaner v1 remote channel
- Share Sheet is useful for mobile capture, not as a conversational channel
- the existing iOS app can later become the first-party remote chat surface
- the next likely intelligence upgrade should be a subscription-backed CLI runtime, not a direct API integration

Recommended next runtime work:

- add `ProcessAgentRuntime`
- then add either:
  - Gemini CLI runtime
  - Codex CLI runtime

Current default recommendation:

- keep MLX/Qwen as fallback
- add a CLI-backed runtime for better remote intelligence

## Files Added

- [TELEGRAM_REMOTE_AGENT_PLAN.md](/Users/minivish/Cider/Docs/Architecture/TELEGRAM_REMOTE_AGENT_PLAN.md)
- [AgentRuntime.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentRuntime.swift)
- [ModelAgentRuntime.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/ModelAgentRuntime.swift)
- [ChannelBridge.swift](/Users/minivish/Cider/Sources/Cider/Services/Channels/ChannelBridge.swift)
- [TelegramModels.swift](/Users/minivish/Cider/Sources/Cider/Services/Channels/Telegram/TelegramModels.swift)
- [TelegramBridge.swift](/Users/minivish/Cider/Sources/Cider/Services/Channels/Telegram/TelegramBridge.swift)

## Files Updated

- [AgentTypes.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentTypes.swift)
- [AgentOrchestrator.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentOrchestrator.swift)
- [ReminderReconciler.swift](/Users/minivish/Cider/Sources/Cider/Services/ReminderReconciler.swift)
- [AppDelegate.swift](/Users/minivish/Cider/Sources/Cider/App/AppDelegate.swift)

## What Is Implemented

### Runtime foundation

The agent layer no longer assumes only direct provider usage.

Added:

- `AgentRuntime` protocol
- `ModelAgentRuntime` adapter wrapping the existing `AgentProvider` path

This means the app can later support:

- local model runtimes
- API runtimes
- CLI/process runtimes

without changing channel ownership.

### Telegram bridge

There is now a real Telegram bridge implementation, not just a stub.

It currently supports:

- persisted config in `~/CiderVault/.cider/telegram/config.json`
- persisted state in `~/CiderVault/.cider/telegram/state.json`
- Telegram Bot API long polling
- first-chat pairing bootstrap
- allowlisted chat IDs
- inbound Telegram message routing to `AgentOrchestrator`
- outbound Telegram replies
- reminder delivery attempts through Telegram

### Startup wiring

On app launch:

- the bridge bootstraps its config/state files if missing
- loads config
- starts polling if enabled

### Reminder hook

`ReminderReconciler` now also calls Telegram reminder processing in addition to the older reminder outbox behavior.

## Current Runtime Behavior

Right now the Telegram bot uses the same active model-backed path as the app panel.

In practice:

- if MLX local model mode is enabled, Telegram uses MLX/Qwen
- otherwise it uses Foundation Models / Apple Intelligence

This was confirmed during testing: Telegram was answering through Qwen 2.5.

## Current Telegram Config

> First-user beta scope, 2026-04-24: Telegram is experimental and deferred. Keep it disabled unless a developer is intentionally running the Telegram regression set with a rotated bot token.

The config file path is:

- `~/CiderVault/.cider/telegram/config.json`

Current expected shape:

```json
{
  "allowFirstChatToPair": true,
  "allowedChatIDs": [],
  "botToken": "YOUR_TOKEN",
  "isEnabled": false,
  "pollingTimeoutSeconds": 30,
  "sendReminders": false
}
```

Notes:

- `allowFirstChatToPair: true` means the first DM can be auto-added to `allowedChatIDs`
- after pairing, the config is rewritten with the paired chat ID
- Telegram chat, Telegram reminders, and image attachment ingestion are not part of the first-user release promise

## Important Security Note

The user pasted a Telegram bot token directly into the chat transcript during setup.

That token should be treated as compromised and rotated in BotFather.

It was temporarily written into the local config for testing because the user explicitly asked for that.

If continuing this work, assume the token may need rotation and the config may need updating.

## Build Status

Last verified build:

```sh
swift build -c debug
```

Status:

- passed

Warnings observed:

- unrelated existing warnings
- linker warnings from dependency object files built for a slightly newer macOS target

No blocking compile errors remained after the Telegram changes.

## Known Gaps

Still missing:

- Telegram settings UI inside Cider
- full scheduled reminder reliability
- reliable image attachment ingestion
- runtime selection UI/config
- first-party iOS chat interface
- Share Sheet ingress bridge
- CLI-backed subscription runtime
- richer auth/pairing UX
- group chat / attachment-heavy Telegram behavior

Already present:

- `/runtime` command support in `TelegramBridge` for active runtime visibility and switching

## Recommended Next Step

The most valuable next implementation is:

### Phase: better intelligence without API billing

Build:

- `ProcessAgentRuntime`
- one CLI-backed runtime adapter

Recommended candidates:

- Gemini CLI
- Codex CLI

Why:

- user wants stronger intelligence while away from the Mac
- user prefers subscription-backed usage over raw API billing
- the architecture now supports adding that cleanly

## Suggested Next Prompt

Use this in the Codex app:

> Read `/Users/minivish/Cider/Docs/Architecture/CODEX_HANDOFF_2026-04-14.md` and `/Users/minivish/Cider/Docs/Architecture/TELEGRAM_REMOTE_AGENT_PLAN.md`. Inspect the current Telegram bridge and agent runtime code. Then implement the next phase: a `ProcessAgentRuntime` plus one subscription-backed CLI runtime adapter, preferably Gemini CLI or Codex CLI, and add a simple way to see which runtime Telegram is using.

## Practical Testing Notes

Current testing flow:

1. Launch Cider
2. Ensure `~/CiderVault/.cider/telegram/config.json` has the bot token and `"isEnabled": true`
3. DM the bot from Telegram
4. The first message should pair if `allowFirstChatToPair` is enabled
5. Ask a simple vault question

If the bot replies, the bridge/orchestrator/runtime path is working.

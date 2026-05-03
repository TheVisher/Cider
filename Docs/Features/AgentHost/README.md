# Agent Host Feature

**Status:** Future boundary / feature folder seed. Current durable Main Brain and Hermes integration guidance lives in `Docs/Features/MainBrain/`.

## Purpose

Agent Host is the neutral backend layer that coordinates Cider, Hermes, mobile clients, Telegram, and future clients. It should own multi-client chat coordination while Hermes owns agent session internals.

Current direction: Cider should first be a strong local-first client and context surface for Hermes/Codex-style agents, not a replacement runtime for every agent. Agent Host is the future coordinator for true multi-client rooms, event fanout, send ordering, approvals, and runtime adapters.

## Responsibilities

- stable logical chat IDs
- mapping logical chats to current Hermes session IDs and lineage
- send ordering and active-run locks
- event fanout to clients
- approval/status surfaces
- attachment and voice routing
- safe bridge between Cider vault actions and agent runtime actions

## Related docs

- `Docs/Architecture/AGENT_SERVICE.md`
- `Docs/Architecture/MANAGED_AGENT_RUNTIME.md`
- `Docs/Architecture/TELEGRAM_REMOTE_AGENT_PLAN.md`
- `Docs/Product/COMPUTER_AGENT_CHAT_APP_CONCEPT.md`
- `Docs/Product/COMPUTER_AGENT_CHAT_APP_MVP_SPEC.md`

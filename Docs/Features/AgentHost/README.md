# Agent Host Feature

**Status:** Feature folder seed.

## Purpose

Agent Host is the neutral backend layer that coordinates Cider, Hermes, mobile clients, Telegram, and future clients. It should own multi-client chat coordination while Hermes owns agent session internals.

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

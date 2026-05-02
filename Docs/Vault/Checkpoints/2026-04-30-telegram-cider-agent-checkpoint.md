# Cider Telegram Agent Checkpoint — 2026-04-30 12:14 PDT

## Purpose

This checkpoint preserves durable context from the Telegram Cider/Hermes conversation before chat compaction can lose nuance. It is intentionally concise and action-oriented, not a raw transcript.

## Current High-Level Direction

The user is using Hermes through Telegram as a real-world Cider vault operator and product discovery partner. The goal is to improve Cider enough that it can be marketed as a local-first, agent-operable personal knowledge vault.

Hermes should function as:

- a Cider vault operator
- a field tester for Cider workflows
- a recorder of real product/CLI friction
- a producer of Codex-ready implementation plans/prompts
- a verifier of Cider CLI/app changes against real workflows

Codex remains the user’s primary coding app for implementation, but Hermes can inspect the Cider codebase, write plans/prompts, verify diffs, run tests, and preserve product context.

## User Preferences / Operating Rules

- Ask clarifying questions when under roughly 90% confident about routing, metadata, expected behavior, or broad/destructive actions.
- Do not guess on uncertain vault routing; use `Inbox/Bookmarks` for unresolved bookmarks.
- Prefer more questions during this learning/ironing-out phase.
- Document real observed workflow issues in Cider docs/hardening notes instead of only discussing them in chat.
- Keep AI-generated enrichment in AI-owned fields such as `aiSummary`, not user-authored notes.
- For batch saves, process links one by one and report per-link results.
- Verify Cider state through `cider-cli` before reporting success.
- Use type-specific Inbox folders for files, e.g. `Inbox/Images`.
- Use city-based restaurant routing, e.g. `Food/Restaurants/{City}`.
- Use `Media/Movies` and `Media/TV Shows` for watchlist/media bookmarks.
- The user wants periodic checkpoints so important operating rules, decisions, and workflow lessons survive context compaction.

## Hermes / Telegram Usage Decisions

- This Telegram chat can serve as the main `Cider Vault Agent` operating thread.
- Hermes is not inherently sandboxed to Cider; it can operate more broadly when tools/permissions allow, but non-Cider actions should be scoped and confirmed when broad or risky.
- User may eventually use Hermes as a system-wide agent across Cider, other repos, macOS operations, app ideas, and marketing.
- Named sessions are preferred for different contexts, e.g.:
  - `Cider Vault Agent`
  - `Cider Codebase`
  - `Mac System Agent`
  - `App Ideas`
  - `Marketing Ideas`
- The user does not know how to view context/compaction state from Telegram, so Hermes should proactively checkpoint durable lessons.
- Voice mode is valuable mainly for driving/walking ideation; text summaries remain preferable for vault operations with paths/IDs/results.
- Telegram DMs are one long visual thread; Telegram group topics or Discord channels could organize multiple agent contexts, but this friction itself suggests a product opportunity.

## Durable Docs Created / Updated Recently

### `/Users/minivish/Cider/Docs/Vault/06-telegram-agent-checkpoint-protocol.md`

Created to define how Hermes should checkpoint Cider/Hermes operating context before compaction. Key points:

- checkpoint when user says “checkpoint”, “save context”, “don’t lose this”, or durable lessons accumulate
- promote stable facts to memory/docs/plans rather than relying on raw chat
- store routing rules in routing docs
- store CLI/app friction in hardening notes
- store broad Telegram/Cider operating conventions in this protocol
- redact secrets
- verify changed docs

### `cider-vault-agent` skill

Updated to include a `Telegram Context Checkpoints` section and reference file:

- `references/telegram-checkpoint-protocol.md`

This makes checkpoint behavior load with the Cider skill in future sessions.

### `/Users/minivish/Cider/Docs/Product/COMPUTER_AGENT_CHAT_APP_CONCEPT.md`

Created as a standalone product concept: a provider-agnostic chat/control app for talking to computer-based AI agents.

Core idea:

> A lightweight mobile and desktop chat client for talking to computer-based AI agents, with local-first session history, resumable chats, voice input, approvals, and provider-agnostic model/runtime support.

Important framing:

- not tied to Cider
- not tied to one provider/model
- works with agents on the user’s own computer
- phone/mobile app is thin; host computer owns work/storage
- supports sessions, chat history, voice, approvals, permissions, logs, checkpoints, and background work

### Tech Stack Section Added To Concept Doc

Recommended MVP direction:

- iOS client: SwiftUI
- Mac host app/service: Swift/AppKit/SwiftUI, or Node/Python daemon depending on first runtime
- host database: SQLite as durable local source of truth
- relay/sync: Convex, Supabase Realtime, or custom WebSocket relay
- push: APNs
- voice: host-side Whisper/faster-whisper first, optional hosted fallback
- runtime adapter: start with Hermes Agent but design for Codex, Claude Code, OpenCode, local agents, MCP runtimes, etc.

Recommended first build:

1. Native iOS app in SwiftUI.
2. Mac host daemon/app with SQLite sessions.
3. Convex as realtime relay/control plane, not source of truth.
4. Hermes Agent runtime adapter first.
5. APNs notifications.
6. Voice note capture with host-side transcription where possible.
7. Basic permission profiles and approval cards.

Key principle: relay/cloud services may help with connectivity, but the user’s computer remains the authoritative owner of sessions, logs, permissions, credentials, artifacts, and agent state.

## Product Insight To Preserve

The user identified a product gap: existing chat apps are awkward for controlling local computer agents.

Telegram, Discord, Slack, Signal, iMessage, ChatGPT, Claude, and Codex can each do parts of the job, but none provide a first-class local-first agent command center with:

- workspaces
- resumable sessions
- provider-neutral runtime adapters
- voice ideation
- local chat history
- approval flows
- action logs
- computer/tool permission modes
- checkpoints
- share-sheet/attachment ingress
- background task status

This could be a standalone app, not necessarily Cider. Cider may still be a natural inspiration/integration point because it already has local-first vault and agent-operable ambitions.

## Current Cider Vault Routing / Workflow Facts

- Cider vault root: `/Users/minivish/CiderVault`.
- Cider repo/docs root: `/Users/minivish/Cider`.
- Cider CLI: `/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli`.
- Use `cider-cli` for vault mutations and prefer `--json` for reads.
- Avoid direct edits to `.cider` internals.
- Movies/watchlist items route to `Media/Movies`.
- TV/watchlist items route to `Media/TV Shows`.
- Uncertain bookmarks route to `Inbox/Bookmarks`.
- Restaurants route to `Food/Restaurants/{City}`.
- File/image captures should use type-specific Inbox folders and verify through Cider file commands.

## Known Cider Hardening Themes From Recent Field Use

- Need high-level `cider-cli file add/import` for files/images/GIFs.
- Telegram pasted/copied GIF-like media may arrive in Hermes as static JPEG stills.
- Direct `.gif` URLs can preserve animation, but Cider app GIF playback may still fail or show still preview.
- `bookmark update --title` can update Cider title without renaming the underlying `.webloc` filename.
- Batch social link capture needs deterministic per-link duplicate-check/add/enrich/title/route/verify results.
- Full `bookmark list` / broad `query` commands may be too slow for agent triage; need scalable paginated/filterable triage commands.

## How Future Agents Should Resume

When resuming Cider work:

1. Load the `cider-vault-agent` skill.
2. Read relevant Cider docs before relying on chat memory:
   - `Docs/Vault/06-telegram-agent-checkpoint-protocol.md`
   - `Docs/Vault/02-routing-rules-v1.md`
   - `Docs/Vault/05-agent-cli-hardening-notes.md`
   - this checkpoint if recent context is needed
3. Use live `cider-cli` output for current vault state.
4. If asked to work on the standalone agent chat app idea, read:
   - `Docs/Product/COMPUTER_AGENT_CHAT_APP_CONCEPT.md`
5. Continue promoting durable lessons into docs/memory instead of trusting long chat context.

## Open Follow-Ups

- Decide whether the standalone computer-agent chat app is only an idea, a future Cider-adjacent product, or something to plan/build.
- Potentially create a more formal PRD from `COMPUTER_AGENT_CHAT_APP_CONCEPT.md`.
- Potentially create a Codex-ready plan for an MVP prototype.
- Continue using Telegram as a field-test bridge and record every friction point as product evidence.

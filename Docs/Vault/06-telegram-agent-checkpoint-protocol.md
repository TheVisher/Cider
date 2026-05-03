# Telegram Agent Checkpoint Protocol

## Purpose

This document preserves the operating protocol for using Hermes over Telegram as a long-running Cider vault agent. It exists so important workflow decisions are not lost when chat context compacts, sessions are resumed, or a fresh agent starts with only the repository/vault docs.

The goal is continuous improvement: every awkward real-world Cider/Hermes workflow should either become a documented rule, a hardening note, a regression case, or a Codex-ready implementation plan.

## Current Operating Model

Cider's primary product target is a native **Cider Main Brain** chat inside the app, powered by Hermes and backed by the Cider Vault. Telegram/Discord are remote access surfaces, not the product source of truth and not required to visually mirror Cider's full transcript.

Use the active Cider/Hermes chat surface for:

- saving links, files, screenshots, GIFs, and notes into the vault
- triaging Inbox and generic bookmarks
- routing items according to current vault taxonomy
- recording observed workflow failures and friction
- producing Codex-ready implementation prompts/plans
- verifying Cider CLI/app changes against real workflows
- resuming the stable named brain from anywhere, usually `/resume Cider`

The chat transcript is not the only source of truth. Durable behavior must be reflected in:

- `Docs/Vault/01-folder-domains-v1.md`
- `Docs/Vault/02-routing-rules-v1.md`
- `Docs/Vault/03-metadata-schema-v1.md`
- `Docs/Vault/05-agent-cli-hardening-notes.md`
- this checkpoint protocol
- persistent Hermes memory for compact, stable user preferences/conventions

## Checkpoint Trigger

Run a Cider checkpoint when any of these happen:

- the user says “checkpoint”, “save context”, “don’t lose this”, or similar
- a new stable routing convention is decided
- a repeated workflow failure is observed
- an agent behavior correction should apply in future sessions
- a batch of vault operations exposes missing CLI affordances
- before intentionally starting a fresh session for Cider work
- after a long Cider session that may soon compact
- after finishing a substantial plan, implementation review, or product decision

The user may not know when Hermes is near context compaction from Telegram, so the agent should proactively checkpoint when the conversation accumulates durable Cider lessons.

## Checkpoint Procedure

When performing a Cider checkpoint:

1. Identify durable facts from the recent conversation:
   - routing decisions
   - vault taxonomy changes
   - user preferences/corrections
   - observed Cider CLI/app limitations
   - successful workflows worth repeating
   - failed workflows and exact caveats

2. Save each fact to the right durable place:
   - stable user preference → Hermes user memory
   - Cider routing/taxonomy rule → `02-routing-rules-v1.md` or `01-folder-domains-v1.md`
   - metadata/AI field convention → `03-metadata-schema-v1.md`
   - CLI/app pain point or missing affordance → `05-agent-cli-hardening-notes.md`
   - broad Telegram/vault-agent operating convention → this document
   - implementation-ready work → `Docs/superpowers/plans/` or another explicit plan doc

3. Avoid dumping raw chat transcripts into docs. Write concise, actionable rules or repro notes.

4. Do not save secrets, tokens, API keys, passwords, private connection strings, or sensitive raw payloads. Redact as `[REDACTED]` if necessary.

5. Verify changed docs by reading back the changed section or checking file existence.

6. Report a short Telegram summary:
   - what was checkpointed
   - which files/memory were updated
   - anything still intentionally unresolved

## Cider Vault Agent Defaults

Unless the user says otherwise:

- Use `cider-cli` for vault facts and mutations.
- Prefer `--json` for reads/search/status.
- Do not edit `.cider` indexes, caches, thumbnails, or sidecars directly.
- Do not write AI-generated text into user-owned notes fields.
- Use AI-owned fields such as `aiSummary` for generated enrichment.
- Ask clarifying questions when under roughly 90% confident about routing, metadata, or expected behavior.
- Route unclear bookmarks to `Inbox/Bookmarks`, not bare `Inbox`.
- Use type-specific Inbox folders for files, e.g. `Inbox/Images` for images/GIFs.
- Process batch links one by one with per-link results.
- Re-read/verify after save, move, title update, or file import.
- Document real workflow friction in hardening notes instead of only mentioning it in chat.

## Current Known Routing Decisions

- Restaurants route by city: `Food/Restaurants/{City}`.
- Movies/watchlist bookmarks route to `Media/Movies`.
- TV show/watchlist bookmarks route to `Media/TV Shows`.
- Wallpapers route to `Wallpapers` or an existing wallpaper-specific folder, not speculative new folders.
- Unclear social/short links should be saved conservatively, enriched/re-read, and moved only when metadata is clear enough.

## Known Hardening Themes From Field Use

Keep improving Cider so weaker/local agents can operate it safely through deterministic workflows. Repeated themes:

- high-level file import is needed; direct file placement is a workaround
- Telegram pasted GIF-like media may arrive as JPEG stills
- direct `.gif` links can preserve animation, but Cider app playback may still need support
- bookmark title updates do not always rename the underlying `.webloc` file
- batch social-link capture needs deterministic per-link save/enrich/route/verify results
- scalable/paginated triage commands are needed so agents do not rely on slow full-list queries

## User Control Pattern From Telegram

Useful user commands/prompts:

- `checkpoint` — preserve durable Cider/Hermes lessons from the current session
- `save these links one by one` — batch capture workflow with per-link verification
- `triage inbox` — conservative Inbox/generic bookmark cleanup
- `document this as a hardening note` — append real observed workflow issue
- `make a Codex prompt` — produce implementation-ready handoff for Codex app
- `inspect the current Cider repo` — read code/docs and report or plan; do not assume permission to make broad edits
- `codebase mode` — work in `/Users/minivish/Cider` repo rather than mutating the vault
- `vault mode` — operate on `/Users/minivish/CiderVault` through Cider CLI

## Fresh Sessions vs Resume

A long-running Cider Main Brain session is useful, but important knowledge should not live only in chat context. Use fresh sessions for large focused work, then bring durable outcomes back into docs/memory/vault objects.

Current recommended context model:

- `Cider` / `cider.main` — the core second-brain/vault/life-assistant chat. This is the priority.
- `Cody` — optional later coding/project helper if it proves useful; not required before Cider chat parity.
- `Mac` — optional later system-task helper; not required before Cider chat parity.

When resuming a Cider session, the agent should resolve the latest backing Hermes thread/compaction by the stable `Cider` title/lineage, reload relevant Cider docs/skills, and trust repository/vault state over memory.

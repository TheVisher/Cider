# Main Brain Architecture

**Status:** Durable architecture source of truth for the Main Brain feature.

---

## Current Shape

```text
Cider chat UI
        │
        ▼
AIAssistantViewModel
        │
        ├─ local command/router behavior
        │
        ├─ CiderAgentChatRegistry
        │       └─ cider.main → Hermes title/session pointer/lineage
        │
        ├─ HermesSessionClient / Hermes transport
        │       └─ Hermes session state, resume, export/CLI fallback, future Runs/SSE
        │
        └─ Cider vault mutation rails
                └─ bookmarks / notes / todos / events / contacts / docs / dashboard cards
```

---

## Ownership Boundaries

### Cider owns

- stable logical chat identity: `cider.main`
- visible display name: `Cider`
- aliases: `Cider`, `Main Brain`, `Vault`, `Brain`
- current Hermes session pointer cache
- lineage/repair metadata cache
- Cider-local transcript/cache/previews
- native slash-command parsing/routing/presentation
- native UI state: busy, stop, command help, last response preview
- vault object creation through supported Cider rails

### Hermes owns

- agent runtime and model conversation internals
- actual Hermes sessions and compaction
- tool execution
- memory injection
- skills
- run state when using Runs/SSE
- approval semantics once exposed through a client API

### Remote transports own

- delivery to their own surface
- platform-specific message/voice/button rendering

Telegram/Discord do not own Main Brain identity. They are ways to reach `/resume Cider`.

---

## Session Resolution

Cider should treat raw Hermes session IDs as rotating pointers.

```text
Open Cider Main Brain
        │
        ▼
load cider.main
        │
        ├─ valid currentHermesSessionID → resume it
        │
        └─ stale/missing pointer
                │
                ▼
          search/resolve Hermes title Cider + lineage
                │
                ▼
          choose newest valid continuation
                │
                ▼
          update cider.main pointer
```

The user-facing chat remains `Cider` even when Hermes compaction creates a new backing session ID.

---

## Transport Strategy

Use a transport seam:

1. Prefer Hermes Runs/SSE when available.
2. Fall back to CLI/export/session-file flow when unavailable.
3. Do not let the fallback define the product UX forever.

Expected Hermes API paths when API server is enabled:

```text
GET  /v1/capabilities
POST /v1/runs
GET  /v1/runs/{run_id}
GET  /v1/runs/{run_id}/events
POST /v1/runs/{run_id}/stop
```

Runs/SSE unlocks native streaming, run state, and stop/cancel. Native approval prompts require a future Hermes API approval event/response contract.

---

## Slash Command Boundary

Cider owns command parsing and native presentation.

Hermes owns execution for commands that require runtime/model/tool semantics.

Examples:

- Cider-local: `/help`, `/status`, `/last`, `/resume Cider`
- Cider-or-Hermes hybrid: `/summary`, `/checkpoint`, `/new`, `/title`
- Hermes-owned later: `/model`, `/tools`, `/skills`, approvals

Unknown commands should return a clean local help/error response instead of being blindly sent as a normal LLM prompt.

---

## Safety Rules

- `/title` must not casually rename canonical `cider.main` away from `Cider`.
- `/new` must preserve lineage and avoid accidental context loss.
- Mutating vault actions must use Cider CLI/storage rails, not direct edits to `.cider` internals.
- Transcript mirroring/import is compatibility, not source-of-truth identity.
- If Cider cannot confidently resolve the backing Hermes session, show status and ask before destructive relink/start-fresh actions.

---

## Future Agent Host Boundary

A neutral Agent Host may eventually coordinate multi-client live rooms, approvals, event fanout, and runtime adapters. That is not required for the current Main Brain slice.

For now, Cider should become a strong Hermes client over the existing Hermes surfaces while preserving a clean seam for future host integration.

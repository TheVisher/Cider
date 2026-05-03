# Main Brain Command Surface

**Status:** Command surface source of truth for Cider Main Brain.

---

## Purpose

This document covers user-facing slash commands for the Cider Main Brain chat. These commands are not necessarily `cider-cli` shell commands; they are the native Cider/Hermes chat command surface.

---

## v1 Commands

### `/help`

Shows available Main Brain commands and short descriptions.

Owner: Cider-local.

### `/status`

Shows Main Brain status:

- active logical chat
- display title
- current Hermes session pointer if available
- transport mode: Runs/SSE or fallback
- busy/run state
- last sync/import status when available

Owner: Cider-local with Hermes health probe when available.

### `/resume [name]`

Resolves and attaches a named brain. Default should be `Cider` when no name is supplied.

For v1, the canonical remote command is:

```text
/resume Cider
```

Owner: Cider-local for UI attachment; Hermes for runtime resume.

### `/last`

Shows the last cached assistant response or a concise note that no cached response is available.

Owner: Cider-local.

### `/summary`

Shows the latest local summary when available. If no summary exists, Cider may ask Hermes to summarize the current Main Brain state.

Owner: hybrid.

### `/checkpoint`

Promotes durable decisions/context into the correct source-of-truth place:

- Cider product/feature docs
- vault notes
- Hermes memory
- skills/procedures
- hardening notes

Owner: hybrid, with Cider guardrails.

### `/new`

Starts a fresh backing Hermes session for the current logical chat while preserving lineage.

Safety rule: `/new` on `cider.main` must not make the old brain feel lost. It should confirm or clearly explain that old sessions remain in lineage.

Owner: hybrid.

### `/title [title]`

Renames a chat/title where allowed.

Safety rule: v1 must not casually rename canonical `cider.main` away from `Cider`. On the main brain, `/title` should either be blocked, require confirmation, or update only a subtitle/alias.

Owner: hybrid.

---

## Later Commands

Possible later commands:

```text
/model
/tools
/skills
/voice
/approve
/deny
```

These should wait until the Hermes transport/API exposes the needed runtime/approval semantics cleanly.

---

## Parser Rules

- A command starts with `/` at the beginning of the trimmed input.
- Unknown commands return local help/error output.
- Plain text messages should not be parsed as commands.
- Commands should be registered in one obvious router/registry.
- Command handlers should be testable without SwiftUI.
- Telegram/Discord compatibility is useful, but Cider native behavior is the product source of truth.

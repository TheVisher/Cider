# Cider / Hermes Session Lineage Sync Note

> Status: historical handoff/checkpoint. Current durable Main Brain and Hermes integration guidance lives in `Docs/Features/MainBrain/`.

Date: 2026-05-02

Purpose: preserve the design decision for how Cider should keep a stable Main Brain chat even when Hermes compacts and creates continuation sessions. This is written as a handoff note for ChatGPT / future agents.

## Core Problem

A fragile implementation maps a Cider chat directly to one raw Hermes session ID:

```text
cider.main -> 20260501_100416_ebff7f
```

That breaks when Hermes compacts or continues the conversation into a new session:

```text
20260501_100416_ebff7f -> 20260501_114444_443f9e
```

If Cider keeps watching only the old session ID, it may think the chat stopped. Telegram may keep talking to the new Hermes continuation session while Cider fails to associate that new session with the same visible Cider chat.

## Correct Model

Cider should treat raw Hermes session IDs as pointers, not identities.

The stable identity is the Cider logical chat ID:

```text
cider.main
```

Each Cider chat should track:

1. **Logical chat ID**
   - Stable forever.
   - Example: `cider.main`, `cider.dashboard-worktree`, `cider.web-review`.
   - This is what Cider UI cares about.

2. **Current Hermes session ID**
   - The newest active Hermes session backing that logical Cider chat.
   - This is what Cider should send new messages to.

3. **Hermes session lineage**
   - Every raw Hermes session ID that belongs to the same logical chat across compactions/continuations.
   - This lets Cider show/search/import the full transcript history.

4. **Last synced cursor**
   - A practical sync cursor so Cider knows where it left off when importing or reconciling Hermes/Telegram messages.
   - Examples: `lastSyncedMessageId`, `lastSyncedTimestamp`, `lastImportedHermesSessionId`.

Example registry record:

```json
{
  "logicalChatId": "cider.main",
  "displayName": "Cider Main Brain",
  "currentHermesSessionId": "20260501_114444_443f9e",
  "hermesLineage": [
    "20260501_100416_ebff7f",
    "20260501_114444_443f9e"
  ],
  "lastSyncedMessageId": "...",
  "lastSyncedTimestamp": "2026-05-02T02:00:00Z",
  "updatedAt": "2026-05-02T02:00:00Z"
}
```

## Why This Solves the Session-ID Rotation Problem

Bad model:

```text
Cider chat -> Hermes session ID
```

Better model:

```text
Cider logical chat -> current Hermes session ID + Hermes session lineage + sync cursor
```

When Hermes creates a continuation session, Cider should update:

```text
currentHermesSessionId = newest continuation session
hermesLineage.append(newest continuation session)
```

The visible Cider chat remains the same:

```text
Cider Main Brain
```

The raw Hermes session ID can change underneath without changing the user's Cider chat identity.

## Telegram Sync Implication

This design prevents the main failure mode:

> Cider watches session A, Hermes continues into session B, Telegram keeps talking to B, and Cider does not realize B belongs to the same Main Brain chat.

With lineage tracking, Cider can recover:

```text
Session B is a continuation of cider.main. Update currentHermesSessionId and keep syncing/importing from B.
```

This does **not** require Telegram to visually mirror Cider messages. The current product decision is simpler:

- Cider owns the clean visible in-app chat transcript.
- Telegram can resume the same Hermes named/logical session when needed.
- Telegram does not need to show all prior Cider-side messages.
- If needed later, add a lightweight catch-up summary command rather than full transcript mirroring.

## First-Class Telegram + Cider Model

It is possible for both Telegram and Cider to be first-class chat interfaces for the same agent work. The key constraint is that neither client should directly treat a raw Hermes session ID as the durable user-facing identity.

Telegram feels stable because its visible container is a stable external identity:

```text
telegramChatId + optional thread/topic ID -> current Hermes backing session
```

Cider should use the same class of abstraction:

```text
cider.logicalChatId -> current Hermes backing session + lineage + sync cursor
```

For example:

```text
cider.main -> currentHermesSessionId + hermesLineage[] + lastSyncedCursor
telegram:7908352979 -> currentHermesSessionId + optional thread/topic + lastDeliveredCursor
```

In this model, Telegram and Cider are both clients over a shared durable logical agent room. Hermes remains the agent runtime and transcript store, but a neutral Agent Host / session broker should own:

- stable chat registry
- client-to-logical-chat mappings
- current Hermes session pointer
- Hermes session lineage
- send locks / busy state
- message ordering
- approval prompts
- event fanout to attached clients
- transcript import/sync cursors

The important product distinction:

- **Cider** is the clean native Main Brain interface inside the second-brain app.
- **Telegram** is the lightweight remote control, notification, voice/capture, and approval surface.
- **Hermes** is the agent runtime and tool executor.
- **Agent Host** is the coordinator that lets multiple clients attach to one logical conversation without racing or losing continuity.

Do **not** solve this by letting Cider and Telegram independently write to the same raw Hermes session files. That risks duplicate sends, out-of-order messages, stale session pointers after compaction, inconsistent tool progress, and ambiguous approvals. All writes should go through the host/broker so there is one ordered stream per logical chat.

Initial pragmatic product decision:

- Make `cider.main` the canonical long-lived Main Brain logical chat.
- Let Telegram `/resume` or attach to that named/logical chat for remote use.
- Do not require full Telegram/Cider transcript mirroring for the first version.
- Provide catch-up summaries when one client was offline or not synced.
- Build toward true event-stream fanout later, where both clients can see the same logical room updates in near real time.

## What Could Still Fail

Lineage tracking is robust, but not magic. Remaining risks:

- Hermes may not expose the continuation link cleanly.
- Cider may miss an update and need to rediscover lineage from Hermes state.
- Two clients may send messages into the same logical chat at the same time.
- Telegram delivery may happen in the wrong chat/topic.
- The user may manually `/new` and forget to `/title` or attach the new Hermes session to a Cider logical chat.
- Compaction summaries may lose nuance even when the session lineage is preserved.

Mitigations:

- Add a recovery scan of Hermes session metadata/state.
- Add a “relink this Hermes session to Cider chat” action.
- Add a per-chat send lock so Cider/Telegram do not write concurrently into the same Hermes session.
- Add durable checkpoints for important context into memory, vault docs, product plans, or hardening notes.

## Product Decision

For the Cider Main Brain:

- Do **not** regularly use `/new` just because the chat is long.
- Keep one long-running logical chat: `cider.main`.
- Let Hermes compact/continue it over time.
- Cider should follow continuation sessions through `currentHermesSessionId` and `hermesLineage`.
- Use `/new` or separate named chats only for side quests, worktree reviews, messy debugging, or tasks that should not pollute Main Brain context.

Simple rule:

```text
Use Main Brain for continuity.
Use side chats for containment.
Use memory/docs/vault for permanence.
```

## Implementation Shape

Cider should have a small local chat registry, probably under `.cider`, that maps stable Cider chat records to Hermes runtime sessions.

Suggested fields:

```text
logicalChatId
name / displayName
scope: main | project | scratchpad | system | other
currentHermesSessionId
hermesLineage[]
lastSyncedMessageId
lastSyncedTimestamp
lastImportedHermesSessionId
createdAt
updatedAt
archived
pinned/default flags
optional telegramChatId
optional telegramThreadId
```

The Cider UI should show the logical chat name, not raw Hermes session IDs.

Raw session IDs are implementation details and may rotate after compaction.

## Related Existing Plan

There is already an implementation plan that mentions this registry pattern:

```text
/Users/minivish/Cider/Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md
```

This checkpoint captures the reasoning and product decision behind the `currentHermesSessionId + hermesLineage + sync cursor` approach so it can be handed to another agent tomorrow without relying on Telegram chat history.

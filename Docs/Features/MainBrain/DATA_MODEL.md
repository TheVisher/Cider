# Main Brain Data Model

**Status:** Durable data/source-of-truth notes for Main Brain identity and state.

---

## Stable Logical Chat Record

The core record is `CiderAgentChatRecord` in:

`Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`

Conceptual shape:

```text
CiderAgentChatRecord
├─ stableID: cider.main
├─ title/displayName: Cider
├─ runtimeID: hermes
├─ activeRuntimeSessionID: latest backing Hermes session pointer
├─ runtimeSessionLineage: previous/current Hermes session IDs
├─ conversationUUID: stable Cider-side conversation identity
├─ defaultInCider: true
├─ createdAt
└─ updatedAt
```

`stableID` is the durable identity. `activeRuntimeSessionID` can rotate when Hermes compacts or continues a conversation.

---

## Canonical Main Brain Values

```text
stableID/logicalChatID: cider.main
display name: Cider
Hermes title: Cider
runtimeID: hermes
remote resume: /resume Cider
aliases: Cider, Main Brain, Vault, Brain
```

---

## Persistence Responsibilities

Cider should persist enough local state to keep the UI stable:

- stable logical chat record
- active Hermes session pointer
- Hermes lineage/alias list
- local conversation UUID
- last assistant response preview when available
- last summary/checkpoint when available
- sync/import cursors when compatibility mirroring is used

Hermes remains the source of truth for its own session internals.

---

## Transcript Data

Cider may cache or mirror transcript entries for UI display and search, but the product should not depend on perfect transcript sync between all surfaces.

Important durable facts should be promoted into Cider objects/docs/memory:

- bookmarks
- notes
- todos
- events
- contacts
- dashboard cards
- product decisions
- checkpoints
- skills/procedures

---

## Run State

When Runs/SSE is available, Cider should track per active run:

```text
runID
logicalChatID
runtimeSessionID
status: queued | running | stopping | completed | failed | cancelled
startedAt
lastEventAt
completedAt
canStop
lastError
```

This state is UI/runtime state. It should not replace the durable chat identity record.

---

## Future Approval State

Native approvals need a future Hermes API contract. The likely shape is:

```text
approvalID
runID
kind
title
description
risk/command/tool payload
choices
status: pending | approved | denied | expired
createdAt
resolvedAt
```

Do not block slash commands or streaming on native approvals.

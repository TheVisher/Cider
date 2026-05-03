# Main Brain Roadmap

**Status:** Feature-specific roadmap for the Cider Main Brain.

---

## Now

### Cider-native slash command router

Build the command surface before chasing deeper transport complexity.

Initial commands:

```text
/help
/status
/resume
/last
/summary
/checkpoint
/new
/title
```

Outcomes:

- Cider chat feels more like Hermes immediately.
- Basic commands work without Hermes API server dependency.
- Unknown commands are handled cleanly.
- Main Brain identity remains stable.

---

## Next

### Runs/SSE streaming transport

Use Hermes API server Runs/SSE when available for:

- streaming assistant text
- busy/running state
- stop/cancel
- final run reconciliation

Keep CLI/export/session fallback until Runs/SSE is stable in daily use.

### Safer latest-session resume

Improve `cider.main` repair behavior:

- resolve by Hermes title `Cider`
- follow newest continuation/compaction
- update active runtime session pointer
- keep lineage traceable

---

## Soon

### Native approvals

Add native Cider approval UI after Hermes exposes a durable approval event/response contract.

Desired shape:

```text
approval.requested → Cider renders approve/deny UI
approval.resolved  → Cider updates run state
```

### Last response and summary UX

Make it easy to recover context when a remote surface cannot show prior Cider transcript:

```text
/last
/summary
```

---

## Later

- Voice dictation and spoken replies
- Cider iOS chat as a native remote brain client
- Discord channels/bots if they prove useful
- Cody/Mac named agents only if the core Cider brain already feels excellent
- Full multi-client live-room/event-fanout through a neutral Agent Host

---

## Parked For Now

Do not spend current implementation time on:

- perfect Cider ↔ Telegram transcript sync
- multiple persistent bot roster
- Discord-first architecture
- broad doc generation for speculative features

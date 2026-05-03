# Main Brain Product

**Status:** Durable product source of truth for the Main Brain feature.

---

## Product Promise

Main Brain makes Cider feel like Erik's second brain: a native chat surface that can save, recall, organize, and resurface life/vault context from anywhere.

The product promise is:

```text
Open Cider, talk to Cider, and trust that important things become durable vault knowledge.
```

---

## Primary User Need

Erik wants one reliable Cider brain that can help with:

- bookmarks and web resources
- notes and ideas
- todos and reminders
- events and follow-ups
- contacts and people context
- media/game/show/movie taste signals
- Cider product/project decisions
- dashboard cards and resurfacing
- recall from the Cider vault

The chat transcript is the working surface. The vault is the durable memory.

---

## Current Product Target

The current target is **Cider Main Brain Chat parity with Hermes**.

This means Cider chat should support the Hermes behaviors Erik expects:

- stable named brain: `Cider`
- automatic latest-session resume
- native slash commands
- clean visible assistant output
- streaming responses when Runs/SSE is available
- busy/running state
- stop/cancel
- approval prompts when Hermes exposes an API approval contract
- future voice dictation/replies

---

## Explicit Non-Goals For Now

Do not optimize for these before Cider chat feels excellent:

- perfect Cider ↔ Telegram visual transcript sync
- Discord-first routing/channels
- Cody/Mac/Nexus persistent bot roster
- 40–50 named chats
- full multi-client live-room fanout
- speculative docs for every future idea

Remote surfaces are useful, but they are remote access surfaces. The primary cockpit is Cider.

---

## Main Brain Identity

The default brain identity is stable and easy to remember:

```text
logicalChatID: cider.main
display name: Cider
Hermes title: Cider
remote resume: /resume Cider
aliases: Cider, Main Brain, Vault, Brain
```

Raw Hermes session IDs are rotating runtime pointers, not user-facing identity.

---

## Desired Experience

### At the Mac

Erik opens Cider and talks to the `Cider` brain directly. The chat should feel native, not like a weak wrapper around a CLI/export file.

### Away from the Mac

Erik uses Telegram/Discord/mobile to resume `Cider`, capture something, or ask a recall question. Perfect transcript visibility is optional; correct brain context and durable vault output are required.

### During compaction

Compaction should feel like maintenance, not losing the brain. Cider should follow the newest continuation and preserve the visible `Cider` identity.

---

## Quality Bar

Main Brain succeeds when:

1. Erik can remember one command/name: `/resume Cider`.
2. Opening Cider chat lands in the right brain without session-ID anxiety.
3. Cider chat can do the important Hermes interactions natively.
4. Important information becomes Cider vault objects/docs/memory, not fragile transcript-only context.
5. The UI hides internal tool/progress noise unless it is useful.

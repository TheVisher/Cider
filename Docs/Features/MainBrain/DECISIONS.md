# Main Brain Decisions

Durable decision log for Main Brain.

---

## 2026-05-01 — Stable Cider Main Brain Identity

**Decision:** Cider should maintain a stable logical chat record for the Main Brain instead of exposing raw Hermes session IDs as the user-facing identity.

**Canonical identity:**

```text
logicalChatID: cider.main
display name: Cider
Hermes title: Cider
remote resume: /resume Cider
```

**Why:** Hermes sessions can compact, continue, or rotate IDs. Erik needs one easy-to-remember brain name.

**Source:** `Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md`

---

## 2026-05-02 — Raw Hermes Session IDs Are Runtime Pointers

**Decision:** Treat raw Hermes session IDs as backing runtime pointers, not durable Cider chat identity.

**Why:** Hermes gateway compression can split a visible thread into a new session ID. Cider must follow the latest continuation without changing the visible `Cider` brain.

**Source:** `Docs/Vault/Checkpoints/2026-05-02-cider-hermes-session-lineage-sync.md`

---

## 2026-05-03 — Chat Parity Over Perfect Telegram Sync

**Decision:** The current product target is Cider Main Brain Chat parity with Hermes, not perfect Cider ↔ Telegram transcript mirroring.

**Why:** Erik mainly needs a second brain inside Cider that can be reached from anywhere. Remote surfaces only need to resume the right named brain and produce durable Cider outputs.

**Implications:**

- Build Cider-native slash commands first.
- Use Runs/SSE for native streaming when available.
- Keep Telegram/Discord as remote access surfaces.
- Do not build Cody/Mac/Nexus bots before the Cider brain feels excellent.

**Source:** `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md` and `Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md`

# Todos And Reminders Decisions

Durable decision log for todos, reminders, and resurfacing.

---

## 2026-05-03 — Cider Owns Reminder Data

**Decision:** Cider-owned `TodoCard`, `DateCard`, and `SurfacingRule` data are the durable reminder/task model.

**Why:** External delivery channels can change, but Cider needs one inspectable local-first source of truth.

**Source:** `Docs/Product/CIDER_LIFE_ASSISTANT_VISION.md`

---

## 2026-05-03 — Apple Reminders Is a Fallback

**Decision:** Apple Reminders may be used as a fallback for unsupported reminder types, especially location-aware reminders, but it is not the long-term Cider source of truth.

**Why:** The product direction is Cider-owned reminders that can surface through Dashboard, Telegram/text, notifications, and future mobile.

**Source:** `Docs/Product/CIDER_LIFE_ASSISTANT_VISION.md`


# Dashboard Decisions

Durable decision log for Dashboard.

---

## 2026-04-19 — Curated Modular Dashboard

**Decision:** Build a curated modular dashboard instead of a one-off hardcoded screen or a fully generic dashboard engine.

**Why:** A polished default helps Erik immediately, while modular panels keep future swapping/resizing possible.

**Source:** `Docs/superpowers/specs/2026-04-19-dashboard-design.md`

---

## 2026-05-02 — Dashboard Is Not Generic News

**Decision:** Dashboard should be personal context resurfacing + curated discovery + action routing, not a generic RSS/news feed.

**Why:** The product value is Cider understanding Erik's vault, interests, projects, reminders, and taste signals.

**Source:** `Docs/Product/CIDER_DASHBOARD_SECOND_BRAIN_FEED.md`

---

## 2026-05-02 — Desktop/Vault Source of Truth First

**Decision:** Desktop/vault owns the MVP dashboard data. Web can consume/mutate the same model later after a schema gate.

**Why:** Cider is local-first, and Web should not fork the dashboard into a separate browser-only model.

**Source:** `Shared/DASHBOARD.md` and `Docs/superpowers/plans/2026-05-02-cider-dashboard-shared-desktop-web-plan.md`

---

## 2026-05-02 — Preserve Existing Overview as Main

**Decision:** The existing Desktop overview dashboard remains available as the `Main` dashboard view inside the dashboard shell.

**Why:** Erik already likes the dashboard; topic/card boards should extend it, not replace or demote it.

**Source:** `Docs/superpowers/specs/2026-05-02-dashboard-tabs-shared-design.md`

---

## 2026-05-02 — Use One Snapshot JSON for MVP

**Decision:** Persist MVP dashboard data as one snapshot file at `.cider/dashboard/_cider_dashboard.json`.

**Why:** It matches existing Cider JSON conventions, is easy for agents to reason about, and can migrate later if volume requires.

**Source:** `Shared/DASHBOARD.md`

---

## 2026-05-02 — Dashboard Is Not the AI Panel

**Decision:** Dashboard is a Cider product/data surface, not the AI assistant panel or AI chat UI.

**Why:** Dashboard cards, topics, feedback, and source routing should evolve independently from assistant transport, chat state, and panel behavior.

**Source:** `Docs/superpowers/plans/2026-05-02-cider-dashboard-shared-desktop-web-plan.md`
